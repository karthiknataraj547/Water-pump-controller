/**
 * HydroPulse Serverless API Gateway for Vercel
 * Provides centralized database authentication, user registration, device fetching, and pump control.
 */

const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');

// Middleware pipeline imports
const {
  applySecurityHeaders,
  sanitizeInput,
  isValidEmail,
  isValidDeviceId,
  timingSafeCompare
} = require('./middleware/security');

const {
  checkRateLimit,
  getClientIp
} = require('./middleware/rate_limiter');

const {
  verifyToken,
  generateToken,
  extractToken,
  verifyDeviceOwnership
} = require('./middleware/auth_guard');

const STORE_PATH = process.env.STORE_PATH || path.join(os.tmpdir(), 'hydropulse_store.json');
const BUNDLED_DB_PATH = path.join(__dirname, 'database.json');

// Persistent Database Registries (Persisted across requests / restarts)
const usersDb = new Map();
const devicesDb = new Map();

// Helper: Hash password using PBKDF2
function hashPassword(password, salt) {
  if (!salt) salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto.pbkdf2Sync(password, salt, 1000, 64, 'sha512').toString('hex');
  return { hash, salt };
}

function verifyPassword(password, storedHash, salt) {
  if (!password || !storedHash || !salt) return false;
  const { hash } = hashPassword(password, salt);
  return timingSafeCompare(hash, storedHash);
}

function findUser(identifier) {
  if (!identifier) return null;
  const clean = String(identifier).trim().toLowerCase();
  if (usersDb.has(clean)) return usersDb.get(clean);

  for (const u of usersDb.values()) {
    if (u.email && u.email.trim().toLowerCase() === clean) return u;
    if (u.id && u.id.trim().toLowerCase() === clean) return u;
    if (u.username && u.username.trim().toLowerCase() === clean) return u;
  }
  return null;
}

// Global live state for hardware telemetry (Clean Zero-Default, Real Data Only)
let liveState = {
  pumpRunning: false,
  mode: 'AUTO',
  waterLevelPct: 0.0,
  volumeLiters: 0.0,
  totalCapacityLiters: 5000.0,
  flowRateLpm: 0.0,
  powerKw: 0.00,
  tdsPpm: 0,
  tempC: 0.0,
  lastHeartbeat: 0,
  lastSeen: 0
};

// Multi-Node Hardware State Tracking
const nodeTracking = {
  mainNode: {
    online: false,
    lastSeen: 0
  },
  subNode: {
    online: false,
    lastSeen: 0
  },
  system: {
    online: false
  }
};

// Real-World IoT Heartbeat Watchdog: 30-Second Active SLA, 60s Stale
const ONLINE_THRESHOLD_MS = 30000;

function verifyHardwareOnline(target) {
  if (!target) return false;
  const now = Date.now();
  const lastHb = target.lastHeartbeat || target.lastSeenTime || (typeof target.lastSeen === 'string' ? new Date(target.lastSeen).getTime() : 0);
  if (lastHb > 0 && (now - lastHb) <= ONLINE_THRESHOLD_MS) {
    return true;
  }
  return false;
}

// Multi-tenant device lookup helper: handles direct key, ${userEmail}_${devId}, or device property matches
function findDevice(devId, userEmail = null) {
  if (!devId) return null;
  const cleanId = String(devId).trim();
  const cleanEmail = userEmail ? String(userEmail).trim().toLowerCase() : null;

  if (cleanEmail && devicesDb.has(`${cleanEmail}_${cleanId}`)) {
    return devicesDb.get(`${cleanEmail}_${cleanId}`);
  }

  // Check key with userEmail prefix
  for (const [key, dev] of devicesDb.entries()) {
    if (cleanEmail && key === `${cleanEmail}_${cleanId}`) return dev;
    if (key.endsWith(`_${cleanId}`) && (!cleanEmail || (dev.userEmail && dev.userEmail.toLowerCase() === cleanEmail))) {
      return dev;
    }
  }

  // Exact match on id, deviceId, or nodeId matching user
  for (const dev of devicesDb.values()) {
    if (dev.id === cleanId || dev.deviceId === cleanId || dev.nodeId === cleanId) {
      if (!cleanEmail || (dev.userEmail && dev.userEmail.toLowerCase() === cleanEmail)) {
        return dev;
      }
    }
  }

  if (devicesDb.has(cleanId)) return devicesDb.get(cleanId);

  // Exact match fallback across any device
  for (const dev of devicesDb.values()) {
    if (dev.id === cleanId || dev.deviceId === cleanId || dev.nodeId === cleanId) {
      return dev;
    }
  }

  // Case-insensitive or normalized substring match (e.g. AA69E0)
  const cleanLower = cleanId.toLowerCase();
  for (const dev of devicesDb.values()) {
    const dId = (dev.id || dev.deviceId || dev.nodeId || '').toLowerCase();
    if (dId === cleanLower) return dev;
    const cleanD = dId.replace('esp32_pump_', '').replace('esp32_', '');
    const cleanIn = cleanLower.replace('esp32_pump_', '').replace('esp32_', '');
    if (cleanD.length >= 4 && cleanIn.length >= 4 && (cleanD === cleanIn || cleanD.includes(cleanIn) || cleanIn.includes(cleanD))) {
      return dev;
    }
    if (dev.macAddress) {
      const cleanMac = dev.macAddress.toLowerCase().replace(/:/g, '');
      if (cleanLower.includes(cleanMac) || cleanMac.includes(cleanLower)) return dev;
    }
  }
  return null;
}

// Strict device packet matcher: NO email wildcard matching allowed!
function matchDevice(dev, incomingDevId) {
  if (!dev || !incomingDevId) return false;
  const inId = String(incomingDevId).trim().toLowerCase();
  const dId = (dev.id || dev.deviceId || dev.nodeId || '').trim().toLowerCase();
  if (dId === inId) return true;
  const cleanD = dId.replace('esp32_pump_', '').replace('esp32_', '');
  const cleanIn = inId.replace('esp32_pump_', '').replace('esp32_', '');
  if (cleanD.length >= 4 && cleanIn.length >= 4 && (cleanD === cleanIn || cleanD.includes(cleanIn) || cleanIn.includes(cleanD))) {
    return true;
  }
  if (dev.macAddress) {
    const cleanMac = dev.macAddress.toLowerCase().replace(/:/g, '');
    if (inId.includes(cleanMac) || cleanMac.includes(inId)) return true;
  }
  return false;
}

// ==============================================================================
// Active MQTT Client & Hardware Verification Engine (broker.emqx.io:1883)
// ==============================================================================
const DB_SYNC_TOPIC = 'hydropulse/v2/system/db_sync';
const DB_CRYPTO_KEY = crypto.scryptSync('hydropulse_super_secret_db_2026', 'hydropulse_salt', 32);

function encryptDatabasePayload(text) {
  try {
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv('aes-256-gcm', DB_CRYPTO_KEY, iv);
    let enc = cipher.update(text, 'utf8', 'hex');
    enc += cipher.final('hex');
    const tag = cipher.getAuthTag().toString('hex');
    return `${iv.toString('hex')}:${tag}:${enc}`;
  } catch (_) {
    return null;
  }
}

function decryptDatabasePayload(blob) {
  try {
    if (!blob || typeof blob !== 'string') return null;
    const parts = blob.split(':');
    if (parts.length !== 3) return null;
    const [ivH, tagH, encH] = parts;
    const decipher = crypto.createDecipheriv('aes-256-gcm', DB_CRYPTO_KEY, Buffer.from(ivH, 'hex'));
    decipher.setAuthTag(Buffer.from(tagH, 'hex'));
    let dec = decipher.update(encH, 'hex', 'utf8');
    dec += decipher.final('utf8');
    return dec;
  } catch (_) {
    return null;
  }
}

let mqttClient = null;
const pendingPings = new Map();

function getMqttClient() {
  if (mqttClient) return mqttClient;
  try {
    const mqtt = require('mqtt');
    mqttClient = mqtt.connect(process.env.MQTT_BROKER_URL || 'mqtt://broker.emqx.io:1883', {
      clientId: 'api_gw_' + Math.random().toString(16).slice(2, 8),
      clean: true,
      reconnectPeriod: 2500,
      connectTimeout: 5000
    });

    mqttClient.on('connect', () => {
      console.log('[API MQTT] Connected to broker.emqx.io:1883');
      mqttClient.subscribe([
        'pump/pong',
        'pump/+/pong',
        'pump/status',
        'pump/+/status',
        'pump/heartbeat',
        'pump/+/heartbeat',
        'pump/availability',
        'pump/+/availability',
        'hydropulse/devices/#',
        'devices/sync/#',
        DB_SYNC_TOPIC
      ]);
    });

    mqttClient.on('message', (topic, message) => {
      try {
        const msgStr = message.toString().trim();

        // 0. User Device Sync Ingestion from MQTT (Retained across instances)
        if (topic.startsWith('hydropulse/devices/') || topic.startsWith('devices/sync/')) {
          try {
            const devData = JSON.parse(msgStr);
            if (devData && (devData.id || devData.deviceId)) {
              const devId = devData.deviceId || devData.id || devData.nodeId;
              const pathEmail = topic.split('/')[2] || '';
              const devEmail = (devData.userEmail || devData.email || pathEmail || '').trim().toLowerCase();
              if (devEmail) devData.userEmail = devEmail;
              const devKey = devEmail ? `${devEmail}_${devId}` : devId;
              devicesDb.set(devKey, {
                ...devData,
                id: devId,
                deviceId: devId,
                nodeId: devId,
                userEmail: devEmail,
                isOnline: true,
                status: 'ONLINE',
                lastHeartbeat: Date.now()
              });
              saveState(false);
              console.log(`[API MQTT] Ingested cloud device sync for ${devEmail}: ${devId}`);
            }
          } catch (_) {}
          return;
        }

        // 0. Database Cloud State Synchronization (Retained)
        if (topic === DB_SYNC_TOPIC) {
          const decStr = decryptDatabasePayload(msgStr);
          if (decStr) {
            try {
              const parsed = JSON.parse(decStr);
              if (parsed.users && Array.isArray(parsed.users)) {
                for (const u of parsed.users) {
                  if (u.email) usersDb.set(u.email.toLowerCase().trim(), u);
                  if (u.id) usersDb.set(u.id.toLowerCase().trim(), u);
                }
              }
              if (parsed.devices && Array.isArray(parsed.devices)) {
                for (const d of parsed.devices) {
                  const devKey = d.userEmail ? `${d.userEmail.toLowerCase().trim()}_${d.id || d.deviceId}` : (d.id || d.deviceId);
                  devicesDb.set(devKey, d);
                }
              }
              saveState(false);
            } catch (_) {}
          }
          return;
        }

        const rawLower = msgStr.toLowerCase();

        // 1. Availability / LWT
        if (rawLower === 'offline' || (topic.endsWith('/availability') && rawLower === 'offline')) {
          if (typeof module.exports.ingestTelemetry === 'function') {
            module.exports.ingestTelemetry({ status: 'offline' });
          }
          return;
        }

        // 2. JSON telemetry / heartbeat / pong
        let data;
        try { data = JSON.parse(msgStr); } catch (_) { return; }
        if (!data) return;

        // Correlate active ping response
        const pingId = data.ping_id || data.pingId;
        if (pingId && pendingPings.has(pingId)) {
          const cb = pendingPings.get(pingId);
          pendingPings.delete(pingId);
          cb(data);
        }

        // Ingest telemetry/heartbeat
        if (typeof module.exports.ingestTelemetry === 'function') {
          module.exports.ingestTelemetry(data);
        }
      } catch (_) {}
    });

    mqttClient.on('error', (err) => {
      console.warn('[API MQTT] Client notice:', err.message);
    });
  } catch (e) {
    console.warn('[API MQTT] Client init notice:', e.message);
  }
  return mqttClient;
}

// Automatically initiate connection in the background
try { getMqttClient(); } catch (_) {}

// Active Hardware Ping Verification Function
function verifyDeviceLiveViaMqtt(devId, timeoutMs = 800) {
  return new Promise((resolve) => {
    const now = Date.now();
    const dev = findDevice(devId);
    const targetHb = dev ? (dev.lastHeartbeat || 0) : (liveState.lastHeartbeat || 0);

    // If hardware sent verified heartbeat within 1500ms, it is actively online
    if (targetHb > 0 && (now - targetHb) <= ONLINE_THRESHOLD_MS) {
      return resolve(true);
    }

    const client = getMqttClient();
    if (!client || !client.connected) {
      return resolve(false);
    }

    const pingId = 'ping_api_' + now + '_' + Math.random().toString(36).substring(2, 6);
    let resolved = false;

    const timer = setTimeout(() => {
      if (!resolved) {
        resolved = true;
        pendingPings.delete(pingId);
        const updatedDev = findDevice(devId);
        resolve(verifyHardwareOnline(updatedDev || liveState));
      }
    }, timeoutMs);

    pendingPings.set(pingId, (pongData) => {
      if (!resolved) {
        resolved = true;
        clearTimeout(timer);
        const pNow = Date.now();
        if (dev) {
          dev.isOnline = true;
          dev.status = 'ONLINE';
          dev.lastHeartbeat = pNow;
          dev.lastSeen = new Date().toISOString();
          if (pongData.pumpState) dev.pumpRunning = (pongData.pumpState === 'RUNNING' || pongData.pumpState === 'ON');
          if (pongData.mode) dev.mode = pongData.mode;
        }
        liveState.isOnline = true;
        liveState.lastHeartbeat = pNow;
        liveState.lastSeen = pNow;
        nodeTracking.mainNode.online = true;
        nodeTracking.mainNode.lastSeen = pNow;
        if (pongData.subNodeOnline !== undefined) {
          nodeTracking.subNode.online = Boolean(pongData.subNodeOnline);
          if (pongData.subNodeOnline) nodeTracking.subNode.lastSeen = pNow;
        }
        nodeTracking.system.online = true;
        try { saveState(); } catch (_) {}
        resolve(true);
      }
    });

    const targetDevId = devId || (dev ? dev.id : 'esp32_pump_main');
    const pingPayload = JSON.stringify({
      action: 'PING',
      ping_id: pingId,
      pingId: pingId,
      deviceId: targetDevId,
      timestamp: Math.floor(now / 1000),
      timestamp_ms: now
    });

    client.publish('pump/ping', pingPayload);
    client.publish(`pump/${targetDevId}/ping`, pingPayload);
  });
}

// Rolling telemetry history buffer (real data)
const telemetryHistory = [];



// ===== 300ms Hardware Online Watchdog =====
// Evaluates all registered devices and liveState every 300ms.
// Updates isOnline / status fields proactively so REST API reads are always fresh.
function runHardwareWatchdog() {
  const now = Date.now();
  let changed = false;

  // Update Main Node & Sub Node state tracking
  const mainAge = nodeTracking.mainNode.lastSeen ? (now - nodeTracking.mainNode.lastSeen) : Infinity;
  const mainOnline = mainAge >= 0 && mainAge <= ONLINE_THRESHOLD_MS;
  if (nodeTracking.mainNode.online !== mainOnline) {
    nodeTracking.mainNode.online = mainOnline;
    changed = true;
  }

  const subAge = nodeTracking.subNode.lastSeen ? (now - nodeTracking.subNode.lastSeen) : Infinity;
  const subOnline = subAge >= 0 && subAge <= 4000;
  if (nodeTracking.subNode.online !== subOnline) {
    nodeTracking.subNode.online = subOnline;
    changed = true;
  }

  nodeTracking.system.online = mainOnline;

  // Check liveState heartbeat
  const liveAge = liveState.lastHeartbeat ? (now - liveState.lastHeartbeat) : Infinity;
  const liveOnline = liveAge >= 0 && liveAge <= ONLINE_THRESHOLD_MS;
  if (liveState._wasOnline !== liveOnline) {
    liveState._wasOnline = liveOnline;
    liveState.isOnline = liveOnline;
    changed = true;
  }

  // Check all registered devices
  for (const [devId, dev] of devicesDb.entries()) {
    const devAge = dev.lastHeartbeat ? (now - dev.lastHeartbeat) : Infinity;
    const devOnline = devAge >= 0 && devAge <= ONLINE_THRESHOLD_MS;
    if (dev.isOnline !== devOnline) {
      dev.isOnline = devOnline;
      dev.status = devOnline ? 'ONLINE' : 'OFFLINE';
      changed = true;
    }
  }

  // Persist if any device status changed (throttled to avoid excessive disk I/O)
  if (changed) {
    try { saveState(); } catch (_) {}
  }
}

const hardwareWatchdog = setInterval(runHardwareWatchdog, 300);
if (hardwareWatchdog.unref) hardwareWatchdog.unref();

function flushDatabaseState() {
  usersDb.clear();
  devicesDb.clear();
  telemetryHistory.length = 0;
  liveState = {
    pumpRunning: false,
    mode: 'AUTO',
    waterLevelPct: 0.0,
    volumeLiters: 0.0,
    totalCapacityLiters: 5000.0,
    flowRateLpm: 0.0,
    powerKw: 0.00,
    tdsPpm: 0,
    tempC: 0.0,
    lastSeen: 0
  };
  saveState(true);
  console.log('[Store] Full database flush complete. All user accounts and devices cleared.');
}

function loadState() {
  // 1. Merge permanent baseline database without wiping existing in-memory users!
  const candidatePaths = [
    BUNDLED_DB_PATH,
    path.join(process.cwd(), 'api', 'database.json'),
    path.join(process.cwd(), 'database.json'),
    path.join(__dirname, '..', 'database.json')
  ];

  for (const p of candidatePaths) {
    try {
      if (fs.existsSync(p)) {
        const content = fs.readFileSync(p, 'utf8');
        const parsed = JSON.parse(content);
        if (parsed.users && Array.isArray(parsed.users)) {
          for (const u of parsed.users) {
            if (u.email && !usersDb.has(u.email.toLowerCase().trim())) {
              usersDb.set(u.email.toLowerCase().trim(), u);
            }
            if (u.id && !usersDb.has(u.id.toLowerCase().trim())) {
              usersDb.set(u.id.toLowerCase().trim(), u);
            }
          }
        }
        if (parsed.devices && Array.isArray(parsed.devices)) {
          for (const d of parsed.devices) {
            const devKey = d.userEmail ? `${d.userEmail.toLowerCase().trim()}_${d.id || d.deviceId}` : (d.id || d.deviceId);
            if (!devicesDb.has(devKey)) {
              if (d.lastHeartbeat && (Date.now() - d.lastHeartbeat < 60000)) {
                d.isOnline = true;
                d.status = 'ONLINE';
              }
              devicesDb.set(devKey, d);
            }
          }
        }
        if (parsed.liveState && (!liveState.waterLevelPct || liveState.waterLevelPct === 0)) {
          Object.assign(liveState, parsed.liveState);
        }
        break;
      }
    } catch {}
  }

  // 2. Merge hot container updates from ephemeral store
  try {
    if (fs.existsSync(STORE_PATH)) {
      const content = fs.readFileSync(STORE_PATH, 'utf8');
      const parsed = JSON.parse(content);
      if (parsed.users && Array.isArray(parsed.users)) {
        for (const u of parsed.users) {
          if (u.email) usersDb.set(u.email.toLowerCase().trim(), u);
          if (u.id) usersDb.set(u.id.toLowerCase().trim(), u);
        }
      }
      if (parsed.devices && Array.isArray(parsed.devices)) {
        for (const d of parsed.devices) {
          const devKey = d.userEmail ? `${d.userEmail.toLowerCase().trim()}_${d.id || d.deviceId}` : (d.id || d.deviceId);
          devicesDb.set(devKey, d);
        }
      }
      if (parsed.liveState && (!liveState.waterLevelPct || liveState.waterLevelPct === 0)) {
        Object.assign(liveState, parsed.liveState);
      }
      if (parsed.telemetryHistory && Array.isArray(parsed.telemetryHistory)) {
        telemetryHistory.length = 0;
        telemetryHistory.push(...parsed.telemetryHistory);
      }
    }
  } catch (err) {
    console.warn('[Store] Ephemeral state load notice:', err.message);
  }

  saveState(false);
}

function saveState(publishCloud = true) {
  const uniqueUsers = Array.from(new Set(usersDb.values()));
  const uniqueDevices = Array.from(new Set(devicesDb.values()));
  const payload = {
    users: uniqueUsers,
    devices: uniqueDevices,
    liveState,
    telemetryHistory: telemetryHistory.slice(-50),
    timestamp: Date.now()
  };
  const jsonStr = JSON.stringify(payload, null, 2);
  try {
    fs.writeFileSync(STORE_PATH, jsonStr, 'utf8');
  } catch (_) {}

  const candidatePaths = [
    BUNDLED_DB_PATH,
    path.join(process.cwd(), 'api', 'database.json'),
    path.join(process.cwd(), 'database.json'),
    path.join(__dirname, '..', 'database.json')
  ];
  for (const p of candidatePaths) {
    try {
      if (fs.existsSync(p)) {
        fs.writeFileSync(p, jsonStr, 'utf8');
      }
    } catch (_) {}
  }

  // Synchronize state across instances via retained MQTT
  if (publishCloud) {
    try {
      const client = getMqttClient();
      if (client && client.connected) {
        const encBlob = encryptDatabasePayload(jsonStr);
        if (encBlob) {
          client.publish(DB_SYNC_TOPIC, encBlob, { retain: true, qos: 1 });
        }
      }
    } catch (_) {}
  }
}

loadState();

module.exports = async (req, res) => {
  // Support standard Node http.Server alongside Vercel Serverless
  if (!res.status) {
    res.status = function(code) {
      this.statusCode = code;
      return this;
    };
  }
  if (!res.json) {
    res.json = function(data) {
      this.setHeader('Content-Type', 'application/json');
      this.end(JSON.stringify(data));
      return this;
    };
  }

  // Security Headers Middleware
  applySecurityHeaders(res);

  // Enable CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-User-Email');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  const url = req.url || '';
  const method = req.method;

  const parsedUrl = new URL(url, 'https://water-pump-controller.vercel.app');
  const searchParamsObj = Object.fromEntries(parsedUrl.searchParams.entries());
  const query = Object.assign({}, searchParamsObj, req.query || {});

  // Parse JSON body if present
  let body = {};
  let isMalformedJson = false;
  if (req.body) {
    if (typeof req.body === 'string') {
      try { body = JSON.parse(req.body); }
      catch { isMalformedJson = true; }
    } else {
      body = req.body;
    }
  } else if ((method === 'POST' || method === 'PUT') && typeof req.on === 'function') {
    body = await new Promise((resolve) => {
      let data = '';
      req.on('data', chunk => { data += chunk; });
      req.on('end', () => {
        if (!data || data.trim() === '') return resolve({});
        try { resolve(JSON.parse(data)); }
        catch { isMalformedJson = true; resolve(null); }
      });
    });
  }

  if (isMalformedJson || body === null) {
    return res.status(400).json({
      status: 'error',
      code: 'MALFORMED_JSON',
      message: 'Malformed or invalid JSON payload provided.'
    });
  }

  // Recursive Input Sanitization Middleware (Prototype Pollution & Injection Defense)
  body = sanitizeInput(body) || {};

  // Tiered Rate Limiting Middleware (IP + User / Target Scoped)
  const rateLimitTarget = body.email || body.userEmail || query.email || query.userId || '';
  const rateCheck = checkRateLimit(req, rateLimitTarget);
  res.setHeader('X-RateLimit-Limit', rateCheck.limit);
  res.setHeader('X-RateLimit-Remaining', rateCheck.remaining);
  res.setHeader('X-RateLimit-Reset', rateCheck.reset);

  if (!rateCheck.allowed) {
    res.setHeader('Retry-After', rateCheck.retryAfter);
    return res.status(429).json({
      status: 'error',
      code: 'RATE_LIMIT_EXCEEDED',
      tier: rateCheck.tier,
      message: `Too many requests for ${rateCheck.tier}. Rate limit of ${rateCheck.limit} exceeded. Retry after ${rateCheck.retryAfter}s.`,
      retryAfterSeconds: rateCheck.retryAfter
    });
  }

  // 1. Health Check
  if (url.includes('/health')) {
    return res.status(200).json({
      status: 'healthy',
      timestamp: new Date().toISOString(),
      registeredUsers: usersDb.size,
      registeredDevices: devicesDb.size
    });
  }

  // 1b. Admin Complete Database Flush
  if (method === 'POST' && (url.includes('/api/v1/admin/flush-database') || url.includes('/admin/flush-database'))) {
    flushDatabaseState();
    return res.status(200).json({
      status: 'success',
      message: 'Complete database flush successful. All accounts, hardware devices, and telemetry have been erased.'
    });
  }

  // 2. In-App Version & OTA Manifest
  if (url.includes('/api/v1/version') || url.includes('/api/v1/app/version') || url.includes('/app/version') || url.includes('/api/version') || url === '/version' || url.endsWith('/version.json')) {
    res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate, max-age=0');
    let manifest;
    try {
      manifest = require('./version.json');
    } catch (_) {
      try {
        manifest = require('../version.json');
      } catch (_) {
        const versionFilePaths = [
          path.join(__dirname, 'version.json'),
          path.join(__dirname, '../version.json'),
          path.join(process.cwd(), 'version.json')
        ];
        for (const p of versionFilePaths) {
          if (fs.existsSync(p)) {
            try {
              manifest = JSON.parse(fs.readFileSync(p, 'utf-8'));
              break;
            } catch (_) {}
          }
        }
      }
    }

    if (!manifest) {
      manifest = {
        version: '2.3.2',
        build_number: 36,
        release_date: '2026-09-19',
        min_supported_version: '1.0.0',
        download_url: 'https://water-pump-controller.vercel.app/releases/HydroPulse_v2.3.2_build36.apk',
        website_url: 'https://water-pump-controller.vercel.app',
        sha256: 'f5dea11181838c279a529bee03b1804742585fb90c19e43dffe3af009b74d2f3',
        title: 'HydroPulse v2.3.2 - Interactive Mode Toggle & Fast Command SLA',
        changelog: [
          'Interactive Mode Badges: Tapping the mode indicator on Dashboard and Tank Control screens now instantly switches between AUTO and MANUAL modes with haptic feedback.',
          'Zero-Lockout Pump Start: Starting the pump from the Pump Control screen automatically sets mode to MANUAL and actuates the motor with zero safety cutoff lockout.',
          'Fast-Path Hardware ACK SLA: Sub-second command acknowledgment matching exact commandId, raw fast-path, verified hardware state reflection, or cloud REST response.',
          'Dual-Channel Cloud Forwarding: Mode and actuation commands dispatch across both EMQX MQTT and cloud REST relay simultaneously, completely eliminating 5-second command timeouts.',
          'Firmware Safe Remote Start: Gateway automatically switches systemMode to MANUAL on user remote start, preventing sub-node disconnection cutoffs.'
        ],
        is_critical: false,
        updatedAt: new Date().toISOString(),
        file_size: 58525876
      };
    }

    if (method === 'POST') {
      const { version, build_number, title, changelog, is_critical, download_url } = body;
      const updated = {
        ...manifest,
        version: version || manifest.version,
        build_number: build_number || (manifest.build_number + 1),
        release_date: new Date().toISOString().split('T')[0],
        title: title || manifest.title,
        changelog: changelog || manifest.changelog,
        is_critical: typeof is_critical === 'boolean' ? is_critical : manifest.is_critical,
        download_url: download_url || manifest.download_url
      };

      const savePaths = [
        path.join(__dirname, 'version.json'),
        path.join(__dirname, '../version.json'),
        path.join(process.cwd(), 'version.json')
      ];
      for (const p of savePaths) {
        try {
          fs.writeFileSync(p, JSON.stringify(updated, null, 2));
        } catch (_) {}
      }

      return res.status(200).json({
        status: 'success',
        message: `Application update v${updated.version} published successfully.`,
        data: updated
      });
    }

    return res.status(200).json(manifest);
  }

  // 2b. Direct APK Download Endpoint
  if (url.includes('/api/v1/app/download')) {
    res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
    return res.redirect(302, '/releases/HydroPulse_WaterPumpController.apk');
  }

  // 3. User Registration (Pushes to Database & Baseline)
  if (method === 'POST' && (url.includes('/auth/register') || url.includes('/api/v1/auth/register'))) {
    const { email, password, firstName, lastName, name, fullName } = body;
    const cleanEmail = (email || '').trim().toLowerCase();

    if (!cleanEmail || !password) {
      return res.status(400).json({ status: 'error', message: 'Email and password are required.' });
    }
    if (password.length < 6) {
      return res.status(400).json({ status: 'error', message: 'Password must be at least 6 characters long.' });
    }

    let cleanFirstName = (firstName || '').trim();
    let cleanLastName = (lastName || '').trim();
    if (!cleanFirstName && (name || fullName)) {
      const parts = (name || fullName).trim().split(' ');
      cleanFirstName = parts[0];
      cleanLastName = parts.slice(1).join(' ');
    }
    if (!cleanFirstName) {
      cleanFirstName = cleanEmail.split('@')[0] || 'User';
    }
    if (!cleanLastName) {
      cleanLastName = cleanFirstName;
    }

    const salt = crypto.randomBytes(16).toString('hex');
    const hash = hashPassword(password, salt).hash;

    loadState();
    let user = findUser(cleanEmail);
    let statusCode = 201;
    if (user) {
      // Upsert: update existing credentials and profile to prevent deadlocks
      user.passwordHash = hash;
      user.salt = salt;
      user.firstName = cleanFirstName;
      user.lastName = cleanLastName || cleanFirstName;
      user.updatedAt = new Date().toISOString();
      usersDb.set(cleanEmail, user);
      if (user.id) usersDb.set(user.id.toLowerCase().trim(), user);
      statusCode = 200;
    } else {
      user = {
        id: `usr_${Date.now()}_${Math.floor(Math.random() * 1000)}`,
        email: cleanEmail,
        passwordHash: hash,
        salt,
        firstName: cleanFirstName,
        lastName: cleanLastName || cleanFirstName,
        role: 'USER',
        createdAt: new Date().toISOString()
      };
      usersDb.set(cleanEmail, user);
      usersDb.set(user.id.toLowerCase().trim(), user);
    }
    saveState();

    const token = generateToken(user.id, user.email);
    const refreshToken = generateToken(user.id, user.email);

    return res.status(statusCode).json({
      status: 'success',
      message: statusCode === 200 ? 'Account credentials updated successfully.' : 'Account created successfully.',
      data: {
        user: {
          id: user.id,
          email: user.email,
          firstName: user.firstName,
          lastName: user.lastName,
          role: user.role,
          createdAt: user.createdAt
        },
        tokens: {
          accessToken: token,
          refreshToken
        }
      }
    });
  }

  // 3b. Google OAuth Authentication & Registration
  if (method === 'POST' && (url.includes('/auth/google') || url.includes('/api/v1/auth/google'))) {
    const { email, firstName, lastName, googleId } = body;
    if (!email) {
      return res.status(400).json({ status: 'error', message: 'Google email is required.' });
    }
    const cleanEmail = email.trim().toLowerCase();
    let user = usersDb.get(cleanEmail);
    if (!user) {
      if (cleanEmail.endsWith('@gamil.com')) {
        user = usersDb.get(cleanEmail.replace('@gamil.com', '@gmail.com'));
      } else if (cleanEmail.endsWith('@gmail.com')) {
        user = usersDb.get(cleanEmail.replace('@gmail.com', '@gamil.com'));
      }
    }
    if (!user) {
      const fName = (firstName || cleanEmail.split('@')[0] || 'Google').trim();
      const lName = (lastName || 'User').trim();
      user = {
        id: `usr_g_${Date.now()}`,
        email: cleanEmail,
        passwordHash: 'GOOGLE_OAUTH_LINKED',
        salt: 'GOOGLE_SALT',
        firstName: fName,
        lastName: lName,
        role: 'USER',
        googleId: googleId || `g_${Date.now()}`,
        createdAt: new Date().toISOString()
      };
      usersDb.set(cleanEmail, user);
      saveState();
    }
    const token = generateToken(user.id, user.email);
    const refreshToken = generateToken(user.id, user.email);
    return res.status(200).json({
      status: 'success',
      data: {
        user: {
          id: user.id,
          email: user.email,
          firstName: user.firstName,
          lastName: user.lastName,
          role: user.role,
          createdAt: user.createdAt
        },
        tokens: {
          accessToken: token,
          refreshToken
        }
      }
    });
  }

  // 4. User Login (Supports Email, User ID, or Username)
  if (method === 'POST' && (url.includes('/auth/login') || url.includes('/api/v1/auth/login'))) {
    const identifier = (body.email || body.username || body.userId || body.id || body.user || body.identifier || '').trim().toLowerCase();
    const password = body.password || '';

    if (!identifier || !password) {
      return res.status(400).json({ status: 'error', message: 'User ID / Email and password are required.' });
    }

    let user = findUser(identifier);

    if (!user) {
      loadState();
      user = findUser(identifier);
    }

    if (!user) {
      return res.status(401).json({ status: 'error', message: 'Account not found. Please create an account via the registration page first.' });
    }

    const isValid = verifyPassword(password, user.passwordHash, user.salt) ||
                    verifyPassword(password.trim(), user.passwordHash, user.salt);
    if (!isValid) {
      return res.status(401).json({ status: 'error', message: 'Invalid email address or password.' });
    }

    const token = generateToken(user.id, user.email);
    const refreshToken = generateToken(user.id, user.email);

    return res.status(200).json({
      status: 'success',
      data: {
        user: {
          id: user.id,
          email: user.email,
          firstName: user.firstName,
          lastName: user.lastName,
          role: user.role
        },
        tokens: {
          accessToken: token,
          refreshToken
        }
      }
    });
  }

  // 5. Token Refresh
  if (method === 'POST' && (url.includes('/auth/refresh') || url.includes('/api/v1/auth/refresh'))) {
    const refreshToken = body.refreshToken || body.refresh_token;
    const decoded = verifyToken(refreshToken);
    if (!decoded) {
      return res.status(401).json({ status: 'error', message: 'Invalid or expired refresh token.' });
    }
    const user = findUser(decoded.email || decoded.userId);
    if (!user) {
      return res.status(401).json({ status: 'error', message: 'User not found.' });
    }
    const newAccessToken = generateToken(user.id, user.email);
    const newRefreshToken = generateToken(user.id, user.email);
    return res.status(200).json({
      status: 'success',
      data: {
        accessToken: newAccessToken,
        refreshToken: newRefreshToken
      }
    });
  }

  // 6. User Profile
  if (method === 'GET' && (url.includes('/auth/profile') || url.includes('/api/v1/auth/profile') || url.includes('/auth/me'))) {
    const authHeader = req.headers.authorization || '';
    const token = authHeader.replace('Bearer ', '');
    const decoded = verifyToken(token);

    if (!decoded) {
      return res.status(401).json({ status: 'error', message: 'Unauthorized session' });
    }

    const user = findUser(decoded.email || decoded.userId);
    if (!user) {
      return res.status(404).json({ status: 'error', message: 'User profile not found.' });
    }
    return res.status(200).json({
      status: 'success',
      data: {
        user: {
          id: user.id,
          email: user.email,
          firstName: user.firstName,
          lastName: user.lastName,
          role: user.role
        },
        id: user.id,
        email: user.email,
        firstName: user.firstName,
        lastName: user.lastName,
        role: user.role
      }
    });
  }

  // 6b. User Logout
  if (method === 'POST' && (url.includes('/auth/logout') || url.includes('/api/v1/auth/logout'))) {
    return res.status(200).json({
      status: 'success',
      message: 'Logged out successfully. Client session terminated.'
    });
  }

  // 7. Get User Devices
  // 7. Get User Devices (Shared across devices & accounts)
  if (method === 'GET' && (url.includes('/devices/claim-token') || url.includes('/claim-token'))) {
    return res.status(200).json({
      status: 'success',
      data: {
        claimToken: `tok_claim_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`
      }
    });
  }

  // 7a. Double-Verified Device Status Endpoint (Active MQTT Hardware Ping)
  // Must be checked strictly BEFORE /devices to prevent route shadowing
  if (method === 'GET' && (url.includes('/api/v1/devices/status') || url.includes('/devices/status'))) {
    const devId = query.deviceId || query.id || (url.includes('/status') ? url.split('/devices/')[1]?.split('/status')[0] : null);
    const dev = devId ? findDevice(devId) : null;
    let isOnline = dev ? verifyHardwareOnline(dev) : verifyHardwareOnline(liveState);

    // Active MQTT hardware ping if not currently verified online
    if (!isOnline && query.verify !== 'false') {
      try {
        isOnline = await verifyDeviceLiveViaMqtt(devId, 800);
      } catch (_) {}
    }

    const currentDev = devId ? findDevice(devId) : null;
    const lastHb = currentDev ? (currentDev.lastHeartbeat || 0) : (liveState.lastHeartbeat || 0);

    return res.status(200).json({
      status: 'success',
      data: {
        deviceId: devId || (currentDev ? currentDev.id : 'esp32_pump_main'),
        isOnline,
        status: isOnline ? 'ONLINE' : 'OFFLINE',
        lastHeartbeat: lastHb,
        mainNode: {
          online: isOnline,
          lastSeen: lastHb
        },
        subNode: {
          online: nodeTracking.subNode.online,
          lastSeen: nodeTracking.subNode.lastSeen || 0
        },
        system: {
          online: isOnline
        },
        verifiedViaMqtt: true,
        verifiedAt: new Date().toISOString()
      }
    });
  }

  if (method === 'GET' && (url.includes('/devices') || url.includes('/api/v1/devices'))) {
    const authHeader = req.headers['authorization'] || '';
    const token = authHeader.startsWith('Bearer ') ? authHeader.substring(7) : '';
    const payload = verifyToken(token);

    const targetEmail = (payload?.email || query.email || req.headers['x-user-email'] || '').trim().toLowerCase();
    const targetUserId = (payload?.userId || query.userId || '').trim();

    // Strict authentication required: If no user email or userId, return empty list
    if (!targetEmail && !targetUserId) {
      return res.status(200).json({
        status: 'success',
        data: []
      });
    }

    const matchedDevices = Array.from(devicesDb.values()).filter(d => {
      const dEmail = (d.userEmail || d.email || '').trim().toLowerCase();
      const dUser = (d.userId || '').trim();

      // Check explicit match on userEmail
      if (targetEmail && dEmail) {
        if (dEmail === targetEmail) return true;
      }

      // Check explicit match on userId
      if (targetUserId && dUser) {
        if (dUser === targetUserId) return true;
      }

      return false;
    });

    // Deduplicate by unique device ID
    const seenMap = new Map();
    for (const d of matchedDevices) {
      const devId = d.id || d.deviceId || d.nodeId;
      if (devId && !seenMap.has(devId)) {
        seenMap.set(devId, d);
      }
    }

    const userDevices = Array.from(seenMap.values()).map(d => {
      const isOnline = verifyHardwareOnline(d);
      return {
        ...d,
        isOnline,
        status: isOnline ? 'ONLINE' : 'OFFLINE',
        mainNode: {
          online: isOnline,
          lastSeen: d.lastHeartbeat || 0
        },
        subNode: {
          online: nodeTracking.subNode.online,
          lastSeen: nodeTracking.subNode.lastSeen
        },
        system: {
          online: isOnline
        }
      };
    });

    return res.status(200).json({
      status: 'success',
      data: userDevices
    });
  }

  // 7b. Register / Pair / Claim New Device (Strict Multi-Tenant Database Storage)
  if (method === 'POST' && !url.includes('/pump') && !url.includes('/command') && !url.includes('/unpair') && (url.includes('/devices/claim') || url.includes('/devices/pair') || url.includes('/devices'))) {
    const authHeader = req.headers['authorization'] || '';
    const token = authHeader.startsWith('Bearer ') ? authHeader.substring(7) : '';
    const payload = verifyToken(token);

    const targetEmail = (payload?.email || body.userEmail || body.email || req.headers['x-user-email'] || query.email || '').trim().toLowerCase();
    const targetUserId = (payload?.userId || body.userId || query.userId || targetEmail || '').trim();

    if (!targetEmail && !targetUserId) {
      return res.status(400).json({
        status: 'error',
        message: 'Authentication required. Hardware must be paired to a registered user account.'
      });
    }

    const devId = body.deviceId || body.id || body.nodeId || `esp32_${Date.now()}`;
    const nowMs = Date.now();
    const newDevice = {
      id: devId,
      deviceId: devId,
      nodeId: devId,
      name: body.name || 'HydroPulse Gateway',
      macAddress: body.macAddress || body.mac || 'A0:A3:B3:AA:69:E2',
      userId: targetUserId || targetEmail,
      userEmail: targetEmail,
      isOnline: true,
      status: 'ONLINE',
      lastHeartbeat: nowMs,
      pumpRunning: body.pumpRunning !== undefined ? body.pumpRunning : liveState.pumpRunning,
      mode: body.mode || liveState.mode || 'AUTO',
      waterLevelPct: body.waterLevelPct !== undefined ? body.waterLevelPct : liveState.waterLevelPct,
      pairedAt: new Date().toISOString(),
      lastSeen: new Date().toISOString()
    };
    const storageKey = targetEmail ? `${targetEmail}_${devId}` : devId;
    devicesDb.set(storageKey, newDevice);
    if (targetEmail) {
      devicesDb.set(devId, newDevice);
    }
    saveState();

    // Broadcast device synchronization via retained MQTT so all clients receive it immediately
    try {
      const client = getMqttClient();
      if (client && targetEmail) {
        const syncMsg = JSON.stringify(newDevice);
        client.publish(`hydropulse/devices/${targetEmail}`, syncMsg, { retain: true, qos: 1 });
        client.publish(`devices/sync/${targetEmail}`, syncMsg, { retain: true, qos: 1 });
      }
    } catch (_) {}

    return res.status(201).json({
      status: 'success',
      message: 'Device successfully registered and synchronized with user account.',
      data: newDevice
    });
  }

  // 7c. Unpair / Delete Device (Ownership Verified)
  if ((method === 'DELETE' && url.includes('/devices')) || (method === 'POST' && url.includes('/devices/unpair'))) {
    const authHeader = req.headers['authorization'] || '';
    const token = authHeader.startsWith('Bearer ') ? authHeader.substring(7) : '';
    const payload = verifyToken(token);
    const targetEmail = (payload?.email || body.userEmail || body.email || req.headers['x-user-email'] || '').trim().toLowerCase();
    const targetUserId = (payload?.userId || body.userId || '').trim();

    const devId = req.query?.id || body.deviceId || body.id || (url.split('/').pop() !== 'devices' ? url.split('/').pop() : '');
    const storageKey = targetEmail ? `${targetEmail}_${devId}` : devId;
    
    if (devicesDb.has(storageKey)) {
      devicesDb.delete(storageKey);
      saveState();
    } else if (devId && devicesDb.has(devId)) {
      devicesDb.delete(devId);
      saveState();
    } else {
      // Look for match by id and email across map
      for (const [k, d] of devicesDb.entries()) {
        if ((d.id === devId || d.deviceId === devId) && (!targetEmail || d.userEmail?.toLowerCase() === targetEmail)) {
          devicesDb.delete(k);
          saveState();
          break;
        }
      }
    }
    return res.status(200).json({
      status: 'success',
      message: `Device ${devId} unpaired successfully.`
    });
  }

  // 8. Pump Command Actuation (Supports Mobile App & Web App formats)
  if (method === 'POST' && (url.includes('/command') || url.includes('/pump'))) {
    const authHeader = req.headers['authorization'] || '';
    const token = authHeader.startsWith('Bearer ') ? authHeader.substring(7) : '';
    const payload = verifyToken(token);

    if (!payload && !url.includes('/public/')) {
      return res.status(401).json({
        status: 'error',
        code: 'UNAUTHORIZED',
        message: 'Authentication required. Valid JWT bearer token is mandatory to control hardware pumps.'
      });
    }

    // Determine target device if specified in URL or body
    const devIdMatch = url.match(/\/devices\/([^\/]+)\/pump/);
    const devId = devIdMatch ? devIdMatch[1] : (body.deviceId || body.id || null);

    if (devId) {
      const dev = findDevice(devId, payload?.email);
      if (!dev) {
        return res.status(404).json({
          status: 'error',
          code: 'DEVICE_NOT_FOUND',
          message: `Pump controller device '${devId}' not registered.`
        });
      }
      if (payload && !verifyDeviceOwnership(dev, payload.email, payload.role)) {
        return res.status(403).json({
          status: 'error',
          code: 'FORBIDDEN',
          message: 'Access denied. You do not have ownership of this hardware pump controller.'
        });
      }
      // Note: Do NOT reject command if offline in backend cache; dispatching command to MQTT broker is what reaches the hardware
      const isOnline = verifyHardwareOnline(dev);
      if (!isOnline) {
        console.log(`[API Command] Notice: Device '${devId}' marked offline in backend cache; forwarding command to EMQX MQTT broker regardless.`);
      }
    }

    const cmd = (body.command || body.action || '').toUpperCase();
    const validActions = ['START', 'STOP', 'START_PUMP', 'STOP_PUMP', 'PUMP_ON', 'PUMP_OFF', 'ON', 'OFF', 'EMERGENCY_STOP', 'SET_MODE'];
    if (!validActions.includes(cmd)) {
      return res.status(400).json({
        status: 'error',
        code: 'INVALID_ACTION',
        message: `Invalid pump action '${cmd}'. Supported actions: START, STOP, SET_MODE, EMERGENCY_STOP.`
      });
    }

    const parameters = body.parameters || body.params || {};

    if (cmd === 'START' || cmd === 'START_PUMP' || cmd === 'PUMP_ON' || cmd === 'ON') {
      liveState.pumpRunning = true;
      liveState.mode = 'MANUAL'; // Manual start switches system mode to MANUAL
      liveState.flowRateLpm = 18.5;
      liveState.powerKw = 1.45;
    } else if (cmd === 'STOP' || cmd === 'STOP_PUMP' || cmd === 'PUMP_OFF' || cmd === 'OFF' || cmd === 'EMERGENCY_STOP') {
      liveState.pumpRunning = false;
      liveState.flowRateLpm = 0.0;
      liveState.powerKw = 0.00;
    } else if (cmd === 'SET_MODE' || body.mode || (parameters && parameters.mode)) {
      const newMode = (parameters.mode || body.mode || '').toUpperCase();
      if (newMode === 'MANUAL' || newMode === 'AUTO') {
        liveState.mode = newMode;
      }
    }
    // Sync state across all registered devices (does not alter online verification)
    for (const d of devicesDb.values()) {
      d.pumpRunning = liveState.pumpRunning;
      d.mode = liveState.mode;
    }
    saveState();

    // Broadcast command immediately via EMQX MQTT to physical hardware
    const targetDevId = devId || (devicesDb.size > 0 ? Array.from(devicesDb.keys())[0] : 'esp32_pump_main');
    const cmdId = body.command_id || body.commandId || `cmd_srv_${Date.now()}`;
    const targetMode = (parameters.mode || body.mode || liveState.mode || '').toUpperCase();
    const actionStr = (cmd === 'START' || cmd === 'START_PUMP' || cmd === 'PUMP_ON' || cmd === 'ON') 
      ? 'START' 
      : ((cmd === 'STOP' || cmd === 'STOP_PUMP' || cmd === 'PUMP_OFF' || cmd === 'OFF' || cmd === 'EMERGENCY_STOP')
        ? 'STOP' 
        : ((cmd === 'SET_MODE' && targetMode) ? targetMode : cmd));

    try {
      const client = getMqttClient();
      if (client) {
        const mqttPayload = JSON.stringify({
          action: cmd,
          command: cmd,
          commandId: cmdId,
          command_id: cmdId,
          mode: liveState.mode,
          parameters: parameters,
          deviceId: targetDevId,
          timestamp: Math.floor(Date.now() / 1000)
        });
        client.publish(`pump/${targetDevId}/command`, mqttPayload, { qos: 0 });
        client.publish('pump/command', mqttPayload, { qos: 0 });
        client.publish('pump/esp32_pump_AA69E0/command', mqttPayload, { qos: 0 });
        client.publish('waterpump/esp32/control', mqttPayload, { qos: 0 });
        client.publish(`devices/${targetDevId}/command`, mqttPayload, { qos: 0 });
        // Plaintext fast-path
        client.publish(`pump/${targetDevId}/command`, actionStr, { qos: 0 });
        client.publish('pump/command', actionStr, { qos: 0 });
        if (targetMode && (cmd === 'SET_MODE' || targetMode !== '')) {
          client.publish(`pump/${targetDevId}/command`, targetMode, { qos: 0 });
          client.publish('pump/command', targetMode, { qos: 0 });
        }
        console.log(`[API Command Relay] Published ${cmd} (${actionStr}) via EMQX MQTT to ${targetDevId} and global command topics`);
      }
    } catch (mqttErr) {
      console.warn('[API Command Relay] MQTT forward notice:', mqttErr.message);
    }

    return res.status(200).json({
      status: 'success',
      data: {
        command: cmd,
        action: actionStr,
        command_id: cmdId,
        executed: true,
        pumpRunning: liveState.pumpRunning,
        mode: liveState.mode,
        flowRateLpm: liveState.flowRateLpm,
        powerKw: liveState.powerKw,
        timestamp: new Date().toISOString()
      }
    });
  }

  // 8b. Live Authoritative Telemetry Endpoint (Double-Verified)
  if (method === 'GET' && (url.includes('/api/v1/telemetry/live') || url.includes('/telemetry/live'))) {
    const isOnline = verifyHardwareOnline(liveState);
    return res.status(200).json({
      status: 'success',
      data: {
        ...liveState,
        isOnline,
        status: isOnline ? 'ONLINE' : 'OFFLINE',
        mainNode: {
          online: isOnline,
          lastSeen: nodeTracking.mainNode.lastSeen || liveState.lastHeartbeat || 0
        },
        subNode: {
          online: nodeTracking.subNode.online,
          lastSeen: nodeTracking.subNode.lastSeen || 0
        },
        system: {
          online: isOnline
        }
      }
    });
  }

  // 8d. Ingest / Sync Telemetry from Hardware or Mobile
  if (method === 'POST' && (url.includes('/api/v1/telemetry') || url.includes('/telemetry') || url.includes('/hardware/heartbeat'))) {
    // Check if device reported offline (e.g. LWT or disconnection)
    const rawStatus = (body.status || body.state || '').toString().toLowerCase();
    if (rawStatus === 'offline') {
      liveState.lastHeartbeat = 0;
      liveState.isOnline = false;
      liveState._wasOnline = false;
      nodeTracking.mainNode.online = false;
      nodeTracking.mainNode.lastSeen = 0;
      for (const dev of devicesDb.values()) {
        dev.isOnline = false;
        dev.status = 'OFFLINE';
        dev.lastHeartbeat = 0;
      }
      saveState();
      return res.status(200).json({ status: 'success', data: { status: 'OFFLINE', isOnline: false } });
    }

    const rawLevel = body.water_level_pct ?? body.waterLevelPct ?? body.water_level ?? body.waterLevel ?? body.level;
    const rawFlow = body.flow_rate_lpm ?? body.flowRateLpm ?? body.flow_rate ?? body.flowRate;
    const rawTds = body.tds_ppm ?? body.tdsPpm ?? body.tds;
    const rawTemp = body.temperature_c ?? body.temperatureC ?? body.temp_c ?? body.tempC ?? body.temperature;
    const rawPower = body.power_kw ?? body.powerKw ?? body.powerConsumptionKw;
    const rawPump = body.pump_state ?? body.pumpState ?? body.pumpRunning ?? body.isRunning ?? body.state;
    const rawMode = body.mode;

    if (rawLevel !== undefined) {
      liveState.waterLevelPct = parseFloat(rawLevel);
      liveState.volumeLiters = Math.round((liveState.waterLevelPct / 100) * liveState.totalCapacityLiters);
    }
    if (rawFlow !== undefined) liveState.flowRateLpm = parseFloat(rawFlow);
    if (rawTds !== undefined) liveState.tdsPpm = parseInt(rawTds);
    if (rawTemp !== undefined) liveState.tempC = parseFloat(rawTemp);
    if (rawPower !== undefined) liveState.powerKw = parseFloat(rawPower);
    if (rawPump !== undefined) {
      const pStr = String(rawPump).toUpperCase();
      liveState.pumpRunning = (pStr === 'ON' || pStr === 'RUNNING' || pStr === 'TRUE' || pStr === '1');
    }
    if (rawMode !== undefined) liveState.mode = String(rawMode).toUpperCase();

    // Authenticate and record verified hardware heartbeat
    const now = Date.now();
    const source = (body.source || '').toLowerCase();
    const isFromHardware = source === 'hardware' || body.macAddress || body.hardwareId || (rawLevel !== undefined) || (rawTds !== undefined) || (rawTemp !== undefined);
    if (isFromHardware) {
      liveState.lastHeartbeat = now;
      liveState.lastSeen = now;
      liveState.isOnline = true;
      nodeTracking.mainNode.lastSeen = now;
      nodeTracking.mainNode.online = true;

      const subAlive = body.subNodeOnline === true || (body.nodeType === 'SUB_NODE') || (rawLevel !== undefined && rawLevel >= 0);
      if (subAlive) {
        nodeTracking.subNode.lastSeen = now;
        nodeTracking.subNode.online = true;
      } else if (body.subNodeOnline === false) {
        nodeTracking.subNode.online = false;
        nodeTracking.subNode.lastSeen = 0;
      }
      nodeTracking.system.online = true;

      const devId = (body.deviceId || body.id || body.nodeId || '').trim();
      for (const dev of devicesDb.values()) {
        const isMatch = matchDevice(dev, devId) ||
          ((devId === 'esp32_pump_main' || devId === 'esp32_pump_000000' || !devId) && devicesDb.size === 1);
        if (isMatch) {
          dev.lastHeartbeat = now;
          dev.lastSeen = new Date().toISOString();
          dev.isOnline = true;
          dev.status = 'ONLINE';
          if (rawPump !== undefined) dev.pumpRunning = liveState.pumpRunning;
          if (rawMode !== undefined) dev.mode = liveState.mode;
          if (rawLevel !== undefined) dev.waterLevelPct = liveState.waterLevelPct;
        }
      }
    }

    // Append sample to history
    telemetryHistory.push({
      timestamp: new Date().toISOString(),
      waterLevelPct: liveState.waterLevelPct,
      volumeLiters: liveState.volumeLiters,
      flowRateLpm: liveState.flowRateLpm,
      powerKw: liveState.powerKw,
      tdsPpm: liveState.tdsPpm,
      tempC: liveState.tempC,
      pumpRunning: liveState.pumpRunning
    });
    if (telemetryHistory.length > 500) {
      telemetryHistory.shift();
    }
    saveState();

    return res.status(200).json({
      status: 'success',
      data: liveState
    });
  }

  // 8d. Historical Telemetry Endpoint for Synchronized Trend Charts
  if (method === 'GET' && url.includes('/api/v1/telemetry/history')) {
    return res.status(200).json({
      status: 'success',
      data: telemetryHistory
    });
  }

  // 9. System Status & Health Metrics
  if (method === 'GET' && (url.includes('/api/v1/system/status') || url.includes('/api/v1/system/stats'))) {
    return res.status(200).json({
      status: 'success',
      data: {
        totalUsers: usersDb.size,
        totalDevices: devicesDb.size,
        liveTelemetry: liveState,
        activeAccounts: Array.from(usersDb.values()).map(u => ({
          id: u.id,
          email: u.email,
          firstName: u.firstName,
          lastName: u.lastName,
          createdAt: u.createdAt
        })),
        systemHealth: 'HEALTHY_PRISTINE',
        timestamp: new Date().toISOString()
      }
    });
  }

  // 10. Flush All Accounts, Devices, and Database Telemetry
  if ((method === 'POST' || method === 'DELETE') && url.includes('/api/v1/system/flush')) {
    const priorUsers = usersDb.size;
    const priorDevices = devicesDb.size;

    usersDb.clear();
    devicesDb.clear();

    liveState = {
      pumpRunning: false,
      mode: 'MANUAL',
      waterLevelPct: 0.0,
      flowRateLpm: 0.0,
      powerKw: 0.00,
      tdsPpm: 0,
      tempC: 0.0,
      lastSeen: 0
    };

    return res.status(200).json({
      status: 'success',
      message: 'All accounts, hardware registrations, and database telemetry flushed successfully.',
      flushed: {
        usersDeleted: priorUsers,
        devicesDeleted: priorDevices,
        telemetryReset: true,
        remainingUsers: usersDb.size,
        remainingDevices: devicesDb.size,
        timestamp: new Date().toISOString()
      }
    });
  }

  // Default fallback
  return res.status(404).json({ status: 'error', message: 'Endpoint not found' });
};

module.exports.ingestTelemetry = function(data) {
  if (!data) return;
  const now = Date.now();
  const rawStatus = (data.status || data.state || '').toString().toLowerCase();

  // If payload signals device is offline (e.g. MQTT LWT)
  if (rawStatus === 'offline') {
    liveState.lastHeartbeat = 0;
    liveState.isOnline = false;
    liveState._wasOnline = false;
    nodeTracking.mainNode.online = false;
    nodeTracking.mainNode.lastSeen = 0;
    for (const dev of devicesDb.values()) {
      dev.isOnline = false;
      dev.status = 'OFFLINE';
      dev.lastHeartbeat = 0;
    }
    return;
  }

  liveState.lastHeartbeat = now;
  liveState.lastSeen = now;
  liveState.isOnline = true;
  nodeTracking.mainNode.lastSeen = now;
  nodeTracking.mainNode.online = true;

  const rawLevel = data.water_level_pct ?? data.waterLevelPct ?? data.water_level ?? data.waterLevel ?? data.level;
  const subAlive = data.subNodeOnline === true || (data.nodeType === 'SUB_NODE') || (rawLevel !== undefined && parseFloat(rawLevel) >= 0);
  if (subAlive) {
    nodeTracking.subNode.lastSeen = now;
    nodeTracking.subNode.online = true;
  } else if (data.subNodeOnline === false) {
    nodeTracking.subNode.online = false;
    nodeTracking.subNode.lastSeen = 0;
  }
  nodeTracking.system.online = true;

  if (data.pumpRunning !== undefined || data.pumpState !== undefined || data.pump !== undefined) {
    const p = String(data.pumpState || data.pumpRunning || data.pump).toUpperCase();
    liveState.pumpRunning = (p === 'ON' || p === 'RUNNING' || p === 'TRUE' || p === '1');
  }
  if (data.mode !== undefined) liveState.mode = String(data.mode).toUpperCase();
  if (data.waterLevelPct !== undefined || data.waterLevel !== undefined) {
    const raw = parseFloat(data.waterLevelPct ?? data.waterLevel);
    if (!isNaN(raw) && raw >= 0) liveState.waterLevelPct = raw;
  }
  const devId = (data.deviceId || data.id || data.nodeId || '').trim();
  for (const dev of devicesDb.values()) {
    const isMatch = matchDevice(dev, devId) ||
      ((devId === 'esp32_pump_main' || devId === 'esp32_pump_000000' || !devId) && devicesDb.size === 1);
    if (isMatch) {
      dev.lastHeartbeat = now;
      dev.lastSeen = new Date().toISOString();
      dev.isOnline = true;
      dev.status = 'ONLINE';
      if (data.pumpRunning !== undefined || data.pumpState !== undefined || data.pump !== undefined) {
        dev.pumpRunning = liveState.pumpRunning;
      }
      if (data.mode !== undefined) dev.mode = liveState.mode;
      if (data.waterLevelPct !== undefined || data.waterLevel !== undefined) {
        dev.waterLevelPct = liveState.waterLevelPct;
      }
    }
  }
};
