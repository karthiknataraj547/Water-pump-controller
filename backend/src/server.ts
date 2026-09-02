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
