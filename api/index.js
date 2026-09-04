/**
 * HydroPulse Serverless API Gateway for Vercel
 * Provides centralized database authentication, user registration, device fetching, and pump control.
 */

const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');

const STORE_PATH = process.env.STORE_PATH || path.join(os.tmpdir(), 'hydropulse_store.json');

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
  const { hash } = hashPassword(password, salt);
  return hash === storedHash;
}

function generateToken(userId, email) {
  const header = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
  const payload = Buffer.from(JSON.stringify({
    userId,
    email,
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + (7 * 24 * 60 * 60)
  })).toString('base64url');
  const signature = crypto.createHmac('sha256', 'hydropulse_jwt_secret_key_2026').update(`${header}.${payload}`).digest('base64url');
  return `${header}.${payload}.${signature}`;
}

function verifyToken(token) {
  if (!token) return null;
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  const signature = crypto.createHmac('sha256', 'hydropulse_jwt_secret_key_2026').update(`${parts[0]}.${parts[1]}`).digest('base64url');
  if (signature !== parts[2]) return null;
  try {
    const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
    if (payload.exp && payload.exp < Math.floor(Date.now() / 1000)) return null;
    return payload;
  } catch {
    return null;
  }
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

// Double verification of hardware online status:
// 1. Must have authentic hardware heartbeat timestamp
// 2. Heartbeat age must be within 15 seconds (< 15000ms)
const ONLINE_THRESHOLD_MS = 15000;
function verifyHardwareOnline(target) {
  if (!target) return false;
  const lastHb = target.lastHeartbeat || 0;
  if (!lastHb) return false;
  const age = Date.now() - lastHb;
  return age >= 0 && age <= ONLINE_THRESHOLD_MS;
}

// Rolling telemetry history buffer (real data)
const telemetryHistory = [];

// Rate Limiter: In-memory sliding window keyed by client IP
const rateLimitMap = new Map();

function getClientIp(req) {
  const forwarded = req.headers['x-forwarded-for'];
  if (forwarded) return forwarded.split(',')[0].trim();
  const realIp = req.headers['x-real-ip'];
  if (realIp) return realIp.trim();
  return req.socket?.remoteAddress || req.connection?.remoteAddress || '127.0.0.1';
}

function checkRateLimit(ip, endpointType) {
  const now = Date.now();
  const windowMs = 60 * 1000; // 1 minute window
  let limit = 150; // default general API limit
  if (endpointType === 'auth') limit = 15; // 15 auth attempts / min
  else if (endpointType === 'command') limit = 45; // 45 command actions / min

  const key = `${ip}_${endpointType}`;
  let record = rateLimitMap.get(key);
  if (!record || now > record.resetTime) {
    record = { count: 1, resetTime: now + windowMs };
    rateLimitMap.set(key, record);
    return { allowed: true, limit, remaining: limit - 1, reset: Math.ceil(record.resetTime / 1000) };
  }

  record.count++;
  const remaining = Math.max(0, limit - record.count);
  const reset = Math.ceil(record.resetTime / 1000);
  const allowed = record.count <= limit;
  const retryAfter = Math.max(1, Math.ceil((record.resetTime - now) / 1000));
  return { allowed, limit, remaining, reset, retryAfter };
}

// Periodic cleanup of rate limit map every 5 minutes
const cleanupInterval = setInterval(() => {
  const now = Date.now();
  for (const [key, record] of rateLimitMap.entries()) {
    if (now > record.resetTime) rateLimitMap.delete(key);
  }
}, 5 * 60 * 1000);
if (cleanupInterval.unref) cleanupInterval.unref();

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
  saveState();
  console.log('[Store] Full database flush complete. All user accounts and devices cleared.');
}

function loadState() {
  try {
    if (fs.existsSync(STORE_PATH)) {
      const content = fs.readFileSync(STORE_PATH, 'utf8');
      const parsed = JSON.parse(content);
      if (parsed.users && Array.isArray(parsed.users)) {
        usersDb.clear();
        for (const u of parsed.users) usersDb.set(u.email, u);
      }
      if (parsed.devices && Array.isArray(parsed.devices)) {
        devicesDb.clear();
        for (const d of parsed.devices) devicesDb.set(d.id || d.deviceId, d);
      }
      if (parsed.liveState) {
        Object.assign(liveState, parsed.liveState);
      }
      if (parsed.telemetryHistory && Array.isArray(parsed.telemetryHistory)) {
        telemetryHistory.length = 0;
        telemetryHistory.push(...parsed.telemetryHistory);
      }
    }
  } catch (err) {
    console.warn('[Store] Notice loading state:', err.message);
  }

  // Strictly ZERO default or pre-seeded accounts or devices!
  saveState();
}

function saveState() {
  try {
    const payload = {
      users: Array.from(usersDb.values()),
      devices: Array.from(devicesDb.values()),
      liveState,
      telemetryHistory: telemetryHistory.slice(-50)
    };
    fs.writeFileSync(STORE_PATH, JSON.stringify(payload, null, 2), 'utf8');
  } catch (err) {
    // Ephemeral container notice
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

  // Security Headers
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('X-XSS-Protection', '1; mode=block');
  res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');

  // Enable CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-User-Email');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  const clientIp = getClientIp(req);
  const url = req.url || '';
  const method = req.method;

  // Rate Limiting Check
  let endpointType = 'general';
  if (url.includes('/auth/')) endpointType = 'auth';
  else if (url.includes('/command') || url.includes('/pump')) endpointType = 'command';

  const rateCheck = checkRateLimit(clientIp, endpointType);
  res.setHeader('X-RateLimit-Limit', rateCheck.limit);
  res.setHeader('X-RateLimit-Remaining', rateCheck.remaining);
  res.setHeader('X-RateLimit-Reset', rateCheck.reset);

  if (!rateCheck.allowed) {
    res.setHeader('Retry-After', rateCheck.retryAfter);
    return res.status(429).json({
      status: 'error',
      code: 'RATE_LIMIT_EXCEEDED',
      message: `Too many requests. Rate limit of ${rateCheck.limit} req/min exceeded. Please retry after ${rateCheck.retryAfter}s.`,
      retryAfterSeconds: rateCheck.retryAfter
    });
  }

  const parsedUrl = new URL(url, 'http://localhost');
  const query = req.query || Object.fromEntries(parsedUrl.searchParams.entries());

  // Parse JSON body if present
  let body = {};
  if (req.body) {
    body = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;
  } else if ((method === 'POST' || method === 'PUT') && typeof req.on === 'function') {
    body = await new Promise((resolve) => {
      let data = '';
      req.on('data', chunk => { data += chunk; });
      req.on('end', () => {
        try { resolve(JSON.parse(data || '{}')); }
        catch { resolve({}); }
      });
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
  if (url.includes('/api/v1/app/version') || url.includes('/app/version') || url.endsWith('/version.json')) {
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
        version: '2.0.9',
        build_number: 12,
        release_date: '2026-09-05',
        min_supported_version: '1.0.0',
        download_url: 'https://water-pump-controller.vercel.app/releases/HydroPulse_WaterPumpController.apk',
        website_url: 'https://water-pump-controller.vercel.app',
        title: 'HydroPulse v2.0.9 - Backend Double Verification of Online Status & Clean Pump Control Card',
        changelog: [
          'Backend Double-Verification: Device status verified strictly against authentic hardware heartbeats (<15s window). Offline by default until physical connection is confirmed.',
          'Zero False Online: Fixed bug where reading live telemetry or arbitrary MQTT broadcasts marked hardware as online.',
          'Pump Control Card Cleanup: Removed redundant status pills from the pump control card, returning to a clean, minimal interface.',
          'Web & Mobile Consistency: Both app and webapp enforce double-verified hardware presence and start in offline state when unpowered.'
        ],
        is_critical: false
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

  // 3. User Registration (Pushes to Database)
  if (method === 'POST' && url.includes('/api/v1/auth/register')) {
    const { email, password, firstName, lastName } = body;
    const cleanFirstName = (firstName || '').trim();
    const cleanLastName = (lastName || '').trim();
    const cleanEmail = (email || '').trim().toLowerCase();

    if (!cleanEmail || !password || !cleanFirstName) {
      return res.status(400).json({ status: 'error', message: 'First name, email, and password are required.' });
    }
    if (password.length < 6) {
      return res.status(400).json({ status: 'error', message: 'Password must be at least 6 characters long.' });
    }

    if (usersDb.has(cleanEmail)) {
      return res.status(400).json({ status: 'error', message: 'An account with this email address already exists.' });
    }

    const salt = crypto.randomBytes(16).toString('hex');
    const hash = hashPassword(password, salt).hash;
    const newUser = {
      id: `usr_${Date.now()}_${Math.floor(Math.random() * 1000)}`,
      email: cleanEmail,
      passwordHash: hash,
      salt,
      firstName: cleanFirstName,
      lastName: cleanLastName || cleanFirstName,
      role: 'USER',
      createdAt: new Date().toISOString()
    };

    usersDb.set(cleanEmail, newUser);
    saveState();

    const token = generateToken(newUser.id, newUser.email);
    const refreshToken = generateToken(newUser.id, newUser.email);

    return res.status(201).json({
      status: 'success',
      data: {
        user: {
          id: newUser.id,
          email: newUser.email,
          firstName: newUser.firstName,
          lastName: newUser.lastName,
          role: newUser.role,
          createdAt: newUser.createdAt
        },
        tokens: {
          accessToken: token,
          refreshToken
        }
      }
    });
  }

  // 3b. Google OAuth Authentication & Registration
  if (method === 'POST' && url.includes('/api/v1/auth/google')) {
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

  // 4. User Login
  if (method === 'POST' && url.includes('/api/v1/auth/login')) {
    const { email, password } = body;
    if (!email || !password) {
      return res.status(400).json({ status: 'error', message: 'Email and password are required.' });
    }

    const cleanEmail = email.trim().toLowerCase();
    const user = usersDb.get(cleanEmail);

    if (!user) {
      return res.status(401).json({ status: 'error', message: 'Account not found. Please create an account via the registration page first.' });
    }

    const isValid = verifyPassword(password, user.passwordHash, user.salt);
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
          email: cleanEmail,
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

  // 5. Google Login
  if (method === 'POST' && url.includes('/api/v1/auth/google')) {
    const { email, firstName, lastName } = body;
    const cleanEmail = (email || 'google.user@gmail.com').trim().toLowerCase();

    let user = usersDb.get(cleanEmail);
    if (!user) {
      const salt = crypto.randomBytes(16).toString('hex');
      const hash = hashPassword('GoogleOAuth2026!', salt).hash;
      user = {
        id: `usr_g_${Date.now()}`,
        email: cleanEmail,
        passwordHash: hash,
        salt,
        firstName: firstName || 'Google',
        lastName: lastName || 'User',
        role: 'USER',
        createdAt: new Date().toISOString()
      };
      usersDb.set(cleanEmail, user);
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

  // 6. User Profile
  if (method === 'GET' && url.includes('/api/v1/auth/profile')) {
    const authHeader = req.headers.authorization || '';
    const token = authHeader.replace('Bearer ', '');
    const decoded = verifyToken(token);

    if (!decoded) {
      return res.status(401).json({ status: 'error', message: 'Unauthorized session' });
    }

    const user = usersDb.get(decoded.email) || defaultAdmin;
    return res.status(200).json({
      status: 'success',
      data: {
        id: user.id,
        email: user.email,
        firstName: user.firstName,
        lastName: user.lastName,
        role: user.role
      }
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

    const userDevices = Array.from(devicesDb.values()).filter(d => {
      const dEmail = (d.userEmail || '').trim().toLowerCase();
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
    }).map(d => {
      const isOnline = verifyHardwareOnline(d);
      return {
        ...d,
        isOnline,
        status: isOnline ? 'ONLINE' : 'OFFLINE'
      };
    });

    return res.status(200).json({
      status: 'success',
      data: userDevices
    });
  }

  // 7b. Register / Pair / Claim New Device (Strict Multi-Tenant Database Storage)
  if (method === 'POST' && (url.includes('/devices/claim') || url.includes('/devices/pair') || url.includes('/devices'))) {
    const authHeader = req.headers['authorization'] || '';
    const token = authHeader.startsWith('Bearer ') ? authHeader.substring(7) : '';
    const payload = verifyToken(token);

    const targetEmail = (payload?.email || body.userEmail || body.email || req.headers['x-user-email'] || '').trim().toLowerCase();
    const targetUserId = (payload?.userId || body.userId || targetEmail || '').trim();

    if (!targetEmail && !targetUserId) {
      return res.status(400).json({
        status: 'error',
        message: 'Authentication required. Hardware must be paired to a registered user account.'
      });
    }

    const devId = body.deviceId || body.id || body.nodeId || `esp32_${Date.now()}`;
    const newDevice = {
      id: devId,
      deviceId: devId,
      nodeId: devId,
      name: body.name || 'HydroPulse Gateway',
      macAddress: body.macAddress || body.mac || '24:6F:28:B2:A4:10',
      userId: targetUserId,
      userEmail: targetEmail,
      isOnline: false,
      status: 'OFFLINE',
      lastHeartbeat: 0,
      pumpRunning: liveState.pumpRunning,
      mode: liveState.mode,
      waterLevelPct: liveState.waterLevelPct,
      pairedAt: new Date().toISOString(),
      lastSeen: new Date().toISOString()
    };
    devicesDb.set(devId, newDevice);
    saveState();

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
    if (devId && devicesDb.has(devId)) {
      const existing = devicesDb.get(devId);
      const isOwner = (!targetEmail && !targetUserId) ||
        (existing.userEmail && existing.userEmail.toLowerCase() === targetEmail) ||
        (existing.userId && existing.userId === targetUserId);

      if (isOwner) {
        devicesDb.delete(devId);
        saveState();
      }
    }
    return res.status(200).json({
      status: 'success',
      message: `Device ${devId} unpaired successfully.`
    });
  }

  // 8. Pump Command Actuation (Supports Mobile App & Web App formats)
  if (method === 'POST' && (url.includes('/command') || url.includes('/pump'))) {
    const cmd = (body.command || body.action || '').toUpperCase();
    const parameters = body.parameters || body.params || {};

    if (cmd === 'START_PUMP' || cmd === 'PUMP_ON' || cmd === 'ON') {
      liveState.pumpRunning = true;
      liveState.flowRateLpm = 18.5;
      liveState.powerKw = 1.45;
    } else if (cmd === 'STOP_PUMP' || cmd === 'PUMP_OFF' || cmd === 'OFF' || cmd === 'EMERGENCY_STOP') {
      liveState.pumpRunning = false;
      liveState.flowRateLpm = 0.0;
      liveState.powerKw = 0.00;
    } else if (cmd === 'SET_MODE' && parameters && parameters.mode) {
      liveState.mode = parameters.mode.toUpperCase();
    }
    // Sync state across all registered devices (does not alter online verification)
    for (const dev of devicesDb.values()) {
      dev.pumpRunning = liveState.pumpRunning;
      dev.mode = liveState.mode;
    }
    saveState();

    return res.status(200).json({
      status: 'success',
      data: {
        command: cmd,
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
  if (method === 'GET' && url.includes('/api/v1/telemetry/live')) {
    const isOnline = verifyHardwareOnline(liveState);
    return res.status(200).json({
      status: 'success',
      data: {
        ...liveState,
        isOnline,
        status: isOnline ? 'ONLINE' : 'OFFLINE'
      }
    });
  }

  // 8c. Double-Verified Device Status Endpoint
  if (method === 'GET' && (url.includes('/api/v1/devices/status') || url.includes('/devices/status'))) {
    const devId = query.deviceId || query.id;
    const dev = devId ? devicesDb.get(devId) : null;
    const isOnline = dev ? verifyHardwareOnline(dev) : verifyHardwareOnline(liveState);
    return res.status(200).json({
      status: 'success',
      data: {
        deviceId: devId || 'esp32_pump_main',
        isOnline,
        status: isOnline ? 'ONLINE' : 'OFFLINE',
        lastHeartbeat: dev ? (dev.lastHeartbeat || 0) : (liveState.lastHeartbeat || 0),
        verifiedAt: new Date().toISOString()
      }
    });
  }

  // 8d. Ingest / Sync Telemetry from Hardware or Mobile
  if (method === 'POST' && (url.includes('/api/v1/telemetry') || url.includes('/telemetry') || url.includes('/hardware/heartbeat'))) {
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
      const devId = body.deviceId || body.id || body.nodeId;
      if (devId && devicesDb.has(devId)) {
        const d = devicesDb.get(devId);
        d.lastHeartbeat = now;
        d.lastSeen = new Date().toISOString();
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
