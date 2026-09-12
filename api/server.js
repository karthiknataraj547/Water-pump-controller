/**
 * HydroPulse Standalone Web & API Server
 * Designed for PM2 Process Management & Direct Node Execution
 */

const http = require('http');
const fs = require('fs');
const path = require('path');
const url = require('url');

const apiHandler = require('./index.js');

const PORT = process.env.PORT || 3000;
const ROOT_DIR = path.resolve(__dirname, '..');

const MIME_TYPES = {
  '.html': 'text/html',
  '.css': 'text/css',
  '.js': 'application/javascript',
  '.json': 'application/json',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf'
};

const server = http.createServer(async (req, res) => {
  const parsedUrl = url.parse(req.url, true);
  const pathname = parsedUrl.pathname;

  // 1. Route API requests to api/index.js
  if (
    pathname.startsWith('/api/') ||
    pathname === '/auth/login' ||
    pathname === '/auth/register' ||
    pathname === '/command' ||
    pathname === '/telemetry' ||
    pathname.startsWith('/devices') ||
    pathname.startsWith('/pumps/') ||
    pathname.startsWith('/automation/')
  ) {
    // Wrap req / res to provide express/vercel compatibility
    req.query = parsedUrl.query || {};
    res.status = function (code) {
      res.statusCode = code;
      return res;
    };
    res.json = function (data) {
      if (!res.getHeader('Content-Type')) {
        res.setHeader('Content-Type', 'application/json');
      }
      res.end(JSON.stringify(data));
      return res;
    };
    res.send = function (data) {
      res.end(typeof data === 'object' ? JSON.stringify(data) : String(data));
      return res;
    };

    // Parse JSON body if applicable
    if (req.method === 'POST' || req.method === 'PUT' || req.method === 'PATCH') {
      let body = '';
      req.on('data', chunk => {
        body += chunk;
      });
      req.on('end', async () => {
        try {
          req.body = body ? JSON.parse(body) : {};
        } catch {
          req.body = {};
        }
        try {
          await apiHandler(req, res);
        } catch (err) {
          console.error('[API Server Error]', err);
          if (!res.headersSent) {
            res.writeHead(500, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ status: 'error', message: 'Internal server error' }));
          }
        }
      });
      return;
    }

    req.body = {};
    try {
      await apiHandler(req, res);
    } catch (err) {
      console.error('[API Server Error]', err);
      if (!res.headersSent) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ status: 'error', message: 'Internal server error' }));
      }
    }
    return;
  }

  // 2. Serve Static Frontend Webapp Files
  let filePath = path.join(ROOT_DIR, pathname === '/' ? 'app.html' : pathname);

  // Security: prevent directory traversal
  if (!filePath.startsWith(ROOT_DIR)) {
    res.writeHead(403);
    res.end('Access Denied');
    return;
  }

  fs.stat(filePath, (err, stats) => {
    if (err || !stats.isFile()) {
      // Fallback: check if app.html or index.html exists
      filePath = path.join(ROOT_DIR, 'app.html');
    }

    const ext = path.extname(filePath).toLowerCase();
    const contentType = MIME_TYPES[ext] || 'application/octet-stream';

    fs.readFile(filePath, (readErr, content) => {
      if (readErr) {
        res.writeHead(404, { 'Content-Type': 'text/plain' });
        res.end('404 Not Found');
        return;
      }
      res.writeHead(200, {
        'Content-Type': contentType,
        'Cache-Control': 'no-cache'
      });
      res.end(content);
    });
  });
});

let currentPort = parseInt(PORT, 10);
server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.warn(`[PM2 / Node] Port ${currentPort} in use, trying port ${currentPort + 1}...`);
    currentPort++;
    server.listen(currentPort);
  } else {
    throw err;
  }
});

server.listen(currentPort, () => {
  console.log(`[PM2 / Node] HydroPulse Full-Stack Server running on port ${currentPort}`);
  console.log(`[Web App URL] http://localhost:${currentPort}`);
});

// ==============================================================================
// Background MQTT Bridge for PM2 Service (Real Hardware Heartbeat Sync)
// ==============================================================================
let mqttClient = null;
try {
  const mqtt = require('mqtt');
  const CLOUD_API_URL = process.env.CLOUD_API_URL || 'https://water-pump-controller.vercel.app/api/v1';
  mqttClient = mqtt.connect('mqtt://broker.emqx.io:1883', {
    clientId: 'pm2_server_bridge_' + Math.random().toString(16).slice(2, 8),
    clean: true,
    reconnectPeriod: 3000
  });

  mqttClient.on('connect', () => {
    console.log('[PM2 MQTT Bridge] Connected to broker.emqx.io:1883');
    mqttClient.subscribe(['pump/#', 'devices/#', 'hydropulse/#']);
  });

  let lastCloudSync = 0;
  mqttClient.on('message', async (topic, message) => {
    try {
      const msgStr = message.toString().trim();
      const rawLower = msgStr.toLowerCase();

      // 1. Direct check for plaintext availability/offline/online
      if (rawLower === 'offline' || (topic.endsWith('/availability') && rawLower === 'offline')) {
        if (apiHandler && typeof apiHandler.ingestTelemetry === 'function') {
          apiHandler.ingestTelemetry({ status: 'offline' });
        }
        return;
      }
      if (rawLower === 'online' || (topic.endsWith('/availability') && rawLower === 'online')) {
        if (apiHandler && typeof apiHandler.ingestTelemetry === 'function') {
          apiHandler.ingestTelemetry({ status: 'online' });
        }
        return;
      }

      // 2. Direct plaintext state ("ON" / "OFF")
      if (topic.endsWith('/state/pump') || topic.endsWith('/state')) {
        if (rawLower === 'on' || rawLower === 'off') {
          if (apiHandler && typeof apiHandler.ingestTelemetry === 'function') {
            apiHandler.ingestTelemetry({ pumpState: rawLower === 'on' ? 'RUNNING' : 'STOPPED' });
          }
          return;
        }
      }

      // 3. JSON formatted payloads
      let data;
      try {
        data = JSON.parse(msgStr);
      } catch (_) {
        return;
      }
      if (!data) return;

      const devId = (data.deviceId || data.id || data.nodeId || '').trim();
      if (!devId && !topic.startsWith('pump/')) return;

      if (data.status === 'OFFLINE' || data.state === 'OFFLINE' || data.status === 'offline') {
        if (apiHandler && typeof apiHandler.ingestTelemetry === 'function') {
          apiHandler.ingestTelemetry({ status: 'offline', deviceId: devId });
        }
        return;
      }

      if (apiHandler && typeof apiHandler.ingestTelemetry === 'function') {
        apiHandler.ingestTelemetry(data);
      }

      const now = Date.now();
      if (now - lastCloudSync >= 4000) {
        lastCloudSync = now;
        fetch(`${CLOUD_API_URL}/telemetry`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            source: 'hardware',
            deviceId: devId || 'esp32_pump_AA69E0',
            ...data
          })
        }).catch(() => {});
      }
    } catch (_) {}
  });
} catch (e) {
  console.warn('[PM2 MQTT Bridge] Init notice:', e.message);
}

module.exports = server;
