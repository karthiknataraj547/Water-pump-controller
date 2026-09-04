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

module.exports = server;
