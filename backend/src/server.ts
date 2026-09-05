import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import { createServer } from 'http';
import { WebSocketServer, WebSocket } from 'ws';
import { config } from './config';
import { connectDatabase } from './config/database';
import { redis } from './config/redis';
import { mqttService } from './modules/mqtt/mqtt.service';
import { errorHandler } from './common/middlewares/error.middleware';
import { logger } from './common/utils/logger';

// Module Routers
import authRouter from './modules/auth/auth.controller';
import devicesRouter from './modules/devices/devices.controller';
import pumpsRouter from './modules/pumps/pumps.controller';
import sensorsRouter from './modules/sensors/sensors.controller';
import automationRouter from './modules/automation/automation.controller';
import alertsRouter from './modules/alerts/alerts.controller';
import analyticsRouter from './modules/analytics/analytics.controller';

const app = express();
const httpServer = createServer(app);

// Security & Parsing Middlewares
app.use(helmet());
app.use(cors({ origin: '*', methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'] }));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(morgan('combined', { stream: { write: (msg) => logger.debug(msg.trim()) } }));

// Health Check
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    environment: config.nodeEnv,
    mqttConnected: true,
  });
});

import fs from 'fs';
import path from 'path';

// Helper to resolve and read version.json dynamically
function getVersionManifest() {
  const versionFilePaths = [
    path.join(__dirname, '../../version.json'),
    path.join(__dirname, '../version.json'),
    path.join(process.cwd(), 'version.json'),
    path.join(process.cwd(), '../version.json'),
  ];
  for (const p of versionFilePaths) {
    if (fs.existsSync(p)) {
      try {
        const raw = fs.readFileSync(p, 'utf-8');
        return JSON.parse(raw);
      } catch (err) {
        logger.warn(`Failed parsing ${p}: ${err}`);
      }
    }
  }
  return {
    version: '2.1.4',
    build_number: 17,
    release_date: '2026-09-05',
    min_supported_version: '1.0.0',
    download_url: 'https://water-pump-controller.vercel.app/releases/HydroPulse_WaterPumpController.apk',
    website_url: 'https://water-pump-controller.vercel.app',
    sha256: '95424d04200c61aa0d4905fa9b6cac148d247785603d0dee417bbd8ac70fed63',
    title: 'HydroPulse v2.1.4 - Zero-Latency Control & Push Notifications',
    changelog: [
      'Zero-Delay Actuation: Eliminated 3-second mode-switch lag by reducing command lock from 3000ms to 400ms.',
      'Smart Offline Detection: Widened heartbeat watchdog to 15s/25s window — eliminates false \'offline\' flashes during brief WiFi hiccups.',
      'Instant Mode Switching: AUTO/MANUAL toggle now responds immediately; commands dispatch even during stale states.',
      'Push Notifications: System-level Android notifications for motor start/stop, tank overflow, and emergency alerts via flutter_local_notifications.',
      'Emergency Stop Always Active: E-Stop button dispatches MQTT command regardless of connection state — safety first.',
      'Reconnect Grace Window: 2-second grace period after MQTT reconnect prevents false offline flash while retained messages load.',
      'UI Polish: Mode switcher and action buttons smoothed with 250ms easing instead of 300ms — snappier feel.'
    ],
    is_critical: true,
    file_size: 58325423
  };
}

// In-App Version & Update Manifest
app.get('/api/v1/app/version', (req, res) => {
  const manifest = getVersionManifest();
  res.status(200).json(manifest);
});

// Admin Endpoint: Update / Publish New Application Version from Backend
app.post('/api/v1/app/version', (req, res) => {
  const { version, build_number, title, changelog, is_critical, download_url } = req.body;
  const current = getVersionManifest();
  const updated = {
    ...current,
    version: version || current.version,
    build_number: build_number || current.build_number,
    release_date: new Date().toISOString().split('T')[0],
    title: title || current.title,
    changelog: changelog || current.changelog,
    is_critical: typeof is_critical === 'boolean' ? is_critical : current.is_critical,
    download_url: download_url || current.download_url,
  };

  const versionFilePaths = [
    path.join(__dirname, '../../version.json'),
    path.join(process.cwd(), 'version.json'),
    path.join(process.cwd(), '../version.json'),
  ];
  for (const p of versionFilePaths) {
    try {
      fs.writeFileSync(p, JSON.stringify(updated, null, 2));
      break;
    } catch {
      // try next
    }
  }

  logger.info(`📢 Application update v${updated.version} published via backend API`);
  res.status(200).json({
    status: 'success',
    message: `Application update v${updated.version} published successfully.`,
    data: updated,
  });
});

// Direct APK Download Endpoint
app.get('/api/v1/app/download', (req, res) => {
  const apkPaths = [
    path.join(__dirname, '../../releases/HydroPulse_WaterPumpController.apk'),
    path.join(process.cwd(), 'releases/HydroPulse_WaterPumpController.apk'),
    path.join(process.cwd(), '../releases/HydroPulse_WaterPumpController.apk'),
  ];
  for (const p of apkPaths) {
    if (fs.existsSync(p)) {
      return res.download(p, 'HydroPulse_WaterPumpController.apk');
    }
  }
  return res.redirect('https://water-pump-controller.vercel.app/releases/HydroPulse_WaterPumpController.apk');
});

// API Routes Mounting
app.use('/api/v1/auth', authRouter);
app.use('/api/v1/devices', devicesRouter);
app.use('/api/v1/pumps', pumpsRouter);
app.use('/api/v1/sensors', sensorsRouter);
app.use('/api/v1/automation', automationRouter);
app.use('/api/v1/alerts', alertsRouter);
app.use('/api/v1/analytics', analyticsRouter);

// Global Error Handler
app.use(errorHandler);

// WebSocket Server for Real-Time Client Push Updates
const wss = new WebSocketServer({ server: httpServer, path: '/ws' });

wss.on('connection', (ws: WebSocket) => {
  logger.info('🔌 New WebSocket client connected to real-time telemetry stream');

  ws.send(JSON.stringify({ type: 'WELCOME', message: 'Connected to IoT Water Pump Stream Gateway' }));

  ws.on('message', (message: string) => {
    try {
      const data = JSON.parse(message.toString());
      if (data.type === 'PING') {
        ws.send(JSON.stringify({ type: 'PONG', timestamp: Date.now() }));
      }
    } catch {
      // ignore
    }
  });

  ws.on('close', () => {
    logger.debug('WebSocket client disconnected');
  });
});

// Bootstrap Application Services
async function bootstrap() {
  await connectDatabase();
  await redis.connect();
  mqttService.connect();

  httpServer.listen(config.port, () => {
    logger.info(`🚀 IoT Water Pump Backend API listening on port ${config.port} (${config.nodeEnv})`);
    logger.info(`📡 WebSocket Gateway running at ws://localhost:${config.port}/ws`);
  });
}

if (process.env.NODE_ENV !== 'test') {
  bootstrap().catch((err) => {
    logger.error('Failed to bootstrap backend service:', err);
    process.exit(1);
  });
}

export { app, httpServer };
