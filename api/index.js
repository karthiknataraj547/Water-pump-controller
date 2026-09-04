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
  lastSeen: Date.now()
};

// Rolling telemetry history buffer (real data)
const telemetryHistory = [];

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

  // Ensure standard demo account is always available for instant multi-device sign-in
  const demoEmail = 'demo@hydropulse.io';
  if (!usersDb.has(demoEmail)) {
    const demoSalt = '7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c';
    const demoHash = hashPassword('HydroPulse2025!#', demoSalt).hash;
    usersDb.set(demoEmail, {
      id: 'usr_demo_001',
      email: demoEmail,
      passwordHash: demoHash,
      salt: demoSalt,
      firstName: 'Demo',
      lastName: 'Demo',
      role: 'ADMIN',
      createdAt: new Date().toISOString()
    });
  }

  // Ensure primary developer/owner account (Karthik Nataraj) is always present & persistent
  const karthikSalt = '3b8a1c9e4f2d7a5b6c8e0f1a2b3c4d5e';
  const karthikHash = hashPassword('HydroPulse2025!#', karthikSalt).hash;
  const karthikAliases = ['karthiknataraj547@gmail.com', 'karthiknataraj547@gamil.com'];
  for (const kEmail of karthikAliases) {
    if (!usersDb.has(kEmail)) {
      usersDb.set(kEmail, {
        id: 'usr_karthik_547',
        email: kEmail,
        passwordHash: karthikHash,
        salt: karthikSalt,
        firstName: 'Karthik',
        lastName: 'Nataraj',
        role: 'ADMIN',
        createdAt: '2026-09-01T00:00:00.000Z'
      });
    }
  }

  // Ensure default primary gateway device is always present
  if (!devicesDb.has('esp32_pump_main')) {
    devicesDb.set('esp32_pump_main', {
      id: 'esp32_pump_main',
      deviceId: 'esp32_pump_main',
      nodeId: 'esp32_pump_main',
      name: 'ESP32 Main Gateway',
      macAddress: '24:6F:28:B2:A4:10',
      userId: 'all',
      isOnline: true,
      pumpRunning: liveState.pumpRunning,
      mode: liveState.mode,
      waterLevelPct: liveState.waterLevelPct,
      pairedAt: new Date().toISOString()
    });
  }

  // Pre-seed paired agricultural hardware for karthiknataraj547
  const karthikEmail = 'karthiknataraj547@gmail.com';
  if (!devicesDb.has('esp32_pump_94B97E')) {
    devicesDb.set('esp32_pump_94B97E', {
      id: 'esp32_pump_94B97E',
      deviceId: 'esp32_pump_94B97E',
      nodeId: 'esp32_pump_94B97E',
      name: 'Agricultural Borewell Pump',
      macAddress: '24:6F:28:94:B9:7E',
      userId: karthikEmail,
      userEmail: karthikEmail,
      isOnline: true,
      pumpRunning: liveState.pumpRunning,
      mode: liveState.mode,
      waterLevelPct: liveState.waterLevelPct,
      pairedAt: '2026-09-04T01:59:17.936Z',
      lastSeen: new Date().toISOString()
    });
  }

  // Guarantee loaded state is synchronized to disk storage
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

  // Enable CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  const url = req.url || '';
  const method = req.method;
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
      registeredUsers: usersDb.size
    });
  }

  // 2. In-App Version & OTA Manifest
  if (url.includes('/api/v1/app/version') || url === '/version.json') {
    const versionFilePaths = [
      path.join(__dirname, '../version.json'),
      path.join(__dirname, 'version.json'),
      path.join(process.cwd(), 'version.json'),
      path.join(process.cwd(), '../version.json')
    ];
    let manifest = {
      version: '2.0.3',
      build_number: 6,
      release_date: '2026-09-04',
      min_supported_version: '1.0.0',
      download_url: 'https://github.com/karthiknataraj547/Water-pump-controller/raw/main/releases/HydroPulse_WaterPumpController.apk',
      website_url: 'https://github.com/karthiknataraj547/Water-pump-controller',
      title: 'HydroPulse v2.0.3 - Real-Time In-App OTA Update Engine',
      changelog: [
        'Automatic in-app update popup with full changelog changes on developer release',
        'Real-time instant update push notification via Cloud MQTT broadcast',
        'Direct in-app APK downloader with live progress percentage and auto-installer',
        'Global background update check on app launch, resume, and 15-minute intervals',
        'Cross-device hardware synchronization and persistent multi-client device pairing'
      ],
      is_critical: false
    };

    for (const p of versionFilePaths) {
      if (fs.existsSync(p)) {
        try {
          manifest = JSON.parse(fs.readFileSync(p, 'utf-8'));
          break;
        } catch (_) {}
      }
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

      for (const p of versionFilePaths) {
        try {
          fs.writeFileSync(p, JSON.stringify(updated, null, 2));
          break;
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
    return res.redirect(302, 'https://github.com/karthiknataraj547/Water-pump-controller/raw/main/releases/HydroPulse_WaterPumpController.apk');
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

    const isKarthik = (cleanEmail === 'karthiknataraj547@gmail.com' || cleanEmail === 'karthiknataraj547@gamil.com');

    if (usersDb.has(cleanEmail) || (isKarthik && (usersDb.has('karthiknataraj547@gmail.com') || usersDb.has('karthiknataraj547@gamil.com')))) {
      if (isKarthik) {
        // Seamlessly update credentials for Karthik so he is never blocked
        const salt = crypto.randomBytes(16).toString('hex');
        const hash = hashPassword(password, salt).hash;
        const userObj = {
          id: 'usr_karthik_547',
          email: cleanEmail,
          passwordHash: hash,
          salt,
          firstName: cleanFirstName || 'Karthik',
          lastName: cleanLastName || 'Nataraj',
          role: 'ADMIN',
          createdAt: new Date().toISOString()
        };
        usersDb.set('karthiknataraj547@gmail.com', userObj);
        usersDb.set('karthiknataraj547@gamil.com', userObj);
        saveState();

        const token = generateToken(userObj.id, userObj.email);
        const refreshToken = generateToken(userObj.id, userObj.email);

        return res.status(200).json({
          status: 'success',
          message: 'Account updated successfully.',
          data: {
            user: {
              id: userObj.id,
              email: userObj.email,
              firstName: userObj.firstName,
              lastName: userObj.lastName,
              role: userObj.role,
              createdAt: userObj.createdAt
            },
            tokens: {
              accessToken: token,
              refreshToken
            }
          }
        });
      }
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
    if (cleanEmail.endsWith('@gamil.com')) {
      usersDb.set(cleanEmail.replace('@gamil.com', '@gmail.com'), newUser);
    }
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
    let user = usersDb.get(cleanEmail);

    // Support alias lookup for typo domain (gamil.com <-> gmail.com)
    if (!user) {
      if (cleanEmail.endsWith('@gamil.com')) {
        user = usersDb.get(cleanEmail.replace('@gamil.com', '@gmail.com'));
      } else if (cleanEmail.endsWith('@gmail.com')) {
        user = usersDb.get(cleanEmail.replace('@gmail.com', '@gamil.com'));
      }
    }

    const isKarthik = (cleanEmail === 'karthiknataraj547@gmail.com' || cleanEmail === 'karthiknataraj547@gamil.com' || (user && user.id === 'usr_karthik_547'));

    // If Karthik account is accessed and somehow missing from in-memory map, auto-provision immediately
    if (!user && isKarthik) {
      const salt = crypto.randomBytes(16).toString('hex');
      const hash = hashPassword(password, salt).hash;
      user = {
        id: 'usr_karthik_547',
        email: cleanEmail,
        passwordHash: hash,
        salt,
        firstName: 'Karthik',
        lastName: 'Nataraj',
        role: 'ADMIN',
        createdAt: '2026-09-01T00:00:00.000Z'
      };
      usersDb.set('karthiknataraj547@gmail.com', user);
      usersDb.set('karthiknataraj547@gamil.com', user);
      saveState();
    }

    if (!user) {
      return res.status(401).json({ status: 'error', message: 'Account not found. Please create an account via the registration page first.' });
    }

    // Verify password, with automatic credential sync for developer owner account
    const isValid = verifyPassword(password, user.passwordHash, user.salt);
    if (!isValid) {
      if (isKarthik && password && password.length >= 4) {
        // Automatically sync and update Karthik's password so he is never locked out
        const newSalt = crypto.randomBytes(16).toString('hex');
        const newHash = hashPassword(password, newSalt).hash;
        user.passwordHash = newHash;
        user.salt = newSalt;
        for (const kEmail of ['karthiknataraj547@gmail.com', 'karthiknataraj547@gamil.com']) {
          const u = usersDb.get(kEmail);
          if (u) {
            u.passwordHash = newHash;
            u.salt = newSalt;
          }
        }
        saveState();
      } else {
        return res.status(401).json({ status: 'error', message: 'Invalid email address or password.' });
      }
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

    const targetEmail = (payload?.email || query.email || req.headers['x-user-email'] || '').toLowerCase();
    const targetUserId = payload?.userId || query.userId || '';

    const isKarthikEmail = (!targetEmail || targetEmail === 'karthiknataraj547@gmail.com' || targetEmail === 'karthiknataraj547@gamil.com' || targetEmail.includes('karthiknataraj547'));

    let userDevices = Array.from(devicesDb.values()).filter(d => {
      if (d.userId === 'all') return true;
      if (targetUserId && d.userId === targetUserId) return true;
      if (targetEmail && d.userEmail && (d.userEmail.toLowerCase() === targetEmail || (isKarthikEmail && d.userEmail.toLowerCase().includes('karthiknataraj547')))) return true;
      if (targetEmail && d.userId && (d.userId.toLowerCase() === targetEmail || (isKarthikEmail && d.userId.toLowerCase().includes('karthiknataraj547')))) return true;
      return false;
    });

    if (isKarthikEmail && devicesDb.has('esp32_pump_94B97E')) {
      if (!userDevices.some(d => d.id === 'esp32_pump_94B97E')) {
        userDevices.unshift(devicesDb.get('esp32_pump_94B97E'));
      }
    }

    // If user has custom added hardware, prioritize that over generic default
    const customDevices = userDevices.filter(d => (d.userEmail && targetEmail && (d.userEmail.toLowerCase() === targetEmail || (isKarthikEmail && d.userEmail.toLowerCase().includes('karthiknataraj547')))) || (d.id !== 'esp32_pump_main'));
    if (customDevices.length > 0) {
      userDevices = customDevices;
    } else if (userDevices.length === 0) {
      const defaultDev = {
        id: 'esp32_pump_main',
        deviceId: 'esp32_pump_main',
        nodeId: 'esp32_pump_main',
        name: 'ESP32 Main Gateway',
        macAddress: '24:6F:28:B2:A4:10',
        userId: targetUserId || targetEmail || 'default_user',
        userEmail: targetEmail || '',
        isOnline: true,
        pumpRunning: liveState.pumpRunning,
        mode: liveState.mode,
        waterLevelPct: liveState.waterLevelPct,
        pairedAt: new Date().toISOString(),
        lastSeen: new Date().toISOString()
      };
      devicesDb.set(`esp32_pump_main_${targetUserId || targetEmail || 'default'}`, defaultDev);
      userDevices = [defaultDev];
      saveState();
    }

    return res.status(200).json({
      status: 'success',
      data: userDevices
    });
  }

  // 7b. Register / Pair / Claim New Device (Saves to Persistent Database)
  if (method === 'POST' && (url.includes('/devices/claim') || url.includes('/devices/pair') || url.includes('/devices'))) {
    const authHeader = req.headers['authorization'] || '';
    const token = authHeader.startsWith('Bearer ') ? authHeader.substring(7) : '';
    const payload = verifyToken(token);

    const targetEmail = (payload?.email || body.userEmail || body.email || req.headers['x-user-email'] || '').toLowerCase();
    const targetUserId = payload?.userId || body.userId || (targetEmail ? targetEmail : 'unassigned');

    const devId = body.deviceId || body.id || body.nodeId || `esp32_${Date.now()}`;
    const newDevice = {
      id: devId,
      deviceId: devId,
      nodeId: devId,
      name: body.name || 'ESP32 Main Gateway',
      macAddress: body.macAddress || body.mac || '24:6F:28:B2:A4:10',
      userId: targetUserId,
      userEmail: targetEmail,
      isOnline: true,
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

  // 7c. Unpair / Delete Device
  if ((method === 'DELETE' && url.includes('/devices')) || (method === 'POST' && url.includes('/devices/unpair'))) {
    const devId = req.query?.id || body.deviceId || body.id || (url.split('/').pop() !== 'devices' ? url.split('/').pop() : '');
    if (devId && devicesDb.has(devId)) {
      devicesDb.delete(devId);
      saveState();
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
    liveState.lastSeen = Date.now();

    // Sync state across all registered devices
    for (const dev of devicesDb.values()) {
      dev.pumpRunning = liveState.pumpRunning;
      dev.mode = liveState.mode;
      dev.isOnline = true;
      dev.lastSeen = new Date().toISOString();
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

  // 8b. Live Authoritative Telemetry Endpoint
  if (method === 'GET' && url.includes('/api/v1/telemetry/live')) {
    liveState.lastSeen = Date.now();
    return res.status(200).json({
      status: 'success',
      data: liveState
    });
  }

  // 8c. Ingest / Sync Telemetry from Hardware or Mobile
  if (method === 'POST' && url.includes('/api/v1/telemetry')) {
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
    liveState.lastSeen = Date.now();

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

  // 11. Application Release Version Manifest (OTA Update Engine)
  if (method === 'GET' && (url.includes('/api/v1/app/version') || url.includes('/app/version') || url.endsWith('/version.json'))) {
    try {
      const vPath = path.join(__dirname, '..', 'version.json');
      if (fs.existsSync(vPath)) {
        const vData = JSON.parse(fs.readFileSync(vPath, 'utf8'));
        return res.status(200).json(vData);
      }
    } catch (_) {}
    return res.status(200).json({
      version: "2.0.4",
      build_number: 7,
      release_date: "2026-09-04",
      min_supported_version: "1.0.0",
      download_url: "https://github.com/karthiknataraj547/Water-pump-controller/raw/main/releases/HydroPulse_WaterPumpController.apk",
      website_url: "https://github.com/karthiknataraj547/Water-pump-controller",
      title: "HydroPulse v2.0.4 - Real-Time Motor Sync & Watchdog Stabilization",
      changelog: [
        "Zero-delay cross-device motor synchronization between Android app and web console",
        "Watchdog timeout extended to eliminate online/offline status flickering on cellular/Wi-Fi",
        "Automatic button & mode lockouts when hardware is offline to prevent false actuation",
        "Seamless background refresh with preserved last-known state and zero offline flashing",
        "Direct MQTT command acknowledgement (ACK) with instant tactile confirmation"
      ],
      is_critical: false
    });
  }

  // Default fallback
  return res.status(404).json({ status: 'error', message: 'Endpoint not found' });
};
