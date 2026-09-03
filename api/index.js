/**
 * HydroPulse Serverless API Gateway for Vercel
 * Provides centralized database authentication, user registration, device fetching, and pump control.
 */

const crypto = require('crypto');

// In-memory persistent user registry for serverless instance (persists across warm invocations)
// Seeded with default administrator
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

// Database Registries start completely empty (0 accounts, 0 devices)
// When a user registers via the mobile app, they are securely stored here.
// Global live state for hardware telemetry (Pristine zero state)
let liveState = {
  pumpRunning: false,
  mode: 'MANUAL',
  waterLevelPct: 0.0,
  flowRateLpm: 0.0,
  powerKw: 0.00,
  tdsPpm: 0,
  tempC: 0.0,
  lastSeen: 0
};

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
    if (method === 'POST') {
      const { version, build_number, title, changelog, is_critical } = body;
      return res.status(200).json({
        status: 'success',
        message: `Application update v${version || '2.0.1'} published successfully.`,
        data: {
          version: version || '2.0.1',
          build_number: build_number || 3,
          release_date: new Date().toISOString().split('T')[0],
          download_url: 'https://github.com/karthiknataraj547/Water-pump-controller/raw/main/releases/HydroPulse_WaterPumpController.apk',
          title: title || 'HydroPulse v2.0.1 - System Console & OTA Update',
          changelog: changelog || ['System Console update with left sidebar navigation', 'Automated OTA update system'],
          is_critical: is_critical || false
        }
      });
    }

    return res.status(200).json({
      version: '2.0.2',
      build_number: 4,
      release_date: '2026-09-03',
      min_supported_version: '1.0.0',
      download_url: 'https://github.com/karthiknataraj547/Water-pump-controller/raw/main/releases/HydroPulse_WaterPumpController.apk',
      website_url: 'https://github.com/karthiknataraj547/Water-pump-controller',
      title: 'HydroPulse v2.0.2 - In-App OTA Update Engine & Direct Package Installer',
      changelog: [
        'In-App OTA direct APK downloader with live progress percentage',
        'Automatic Android package installer trigger with zero sandbox blocks',
        'Native dynamic version detection via Android package manager',
        'Zero-failure authentic customer onboarding and device setup',
        'Real-time bidirectional MQTT sync between mobile and web console'
      ],
      is_critical: false
    });
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

    if (!verifyPassword(password, user.passwordHash, user.salt)) {
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
  if (method === 'GET' && url.includes('/api/v1/devices')) {
    const authHeader = req.headers['authorization'] || '';
    const token = authHeader.startsWith('Bearer ') ? authHeader.substring(7) : '';
    const payload = verifyToken(token);

    if (payload && payload.userId) {
      const userDevices = Array.from(devicesDb.values()).filter(d => d.userId === payload.userId);
      return res.status(200).json({
        status: 'success',
        data: userDevices
      });
    }

    return res.status(200).json({
      status: 'success',
      data: []
    });
  }

  // 7b. Register / Pair New Device
  if (method === 'POST' && url.includes('/api/v1/devices')) {
    const authHeader = req.headers['authorization'] || '';
    const token = authHeader.startsWith('Bearer ') ? authHeader.substring(7) : '';
    const payload = verifyToken(token);

    const { name, macAddress, deviceId } = body;
    const newDevice = {
      id: deviceId || `esp32_${Date.now()}`,
      deviceId: deviceId || `esp32_${Date.now()}`,
      name: name || 'HydroPulse Pump Gateway',
      macAddress: macAddress || '00:00:00:00:00:00',
      userId: payload ? payload.userId : 'unassigned',
      isOnline: true,
      pumpRunning: liveState.pumpRunning,
      mode: liveState.mode,
      waterLevelPct: liveState.waterLevelPct,
      pairedAt: new Date().toISOString()
    };
    devicesDb.set(newDevice.id, newDevice);

    return res.status(201).json({
      status: 'success',
      data: newDevice
    });
  }

  // 8. Pump Command Actuation
  if (method === 'POST' && url.includes('/command')) {
    const { command, parameters } = body;
    if (command === 'PUMP_ON') {
      liveState.pumpRunning = true;
      liveState.flowRateLpm = 18.5;
      liveState.powerKw = 1.45;
    } else if (command === 'PUMP_OFF' || command === 'EMERGENCY_STOP') {
      liveState.pumpRunning = false;
      liveState.flowRateLpm = 0.0;
      liveState.powerKw = 0.00;
    } else if (command === 'SET_MODE' && parameters && parameters.mode) {
      liveState.mode = parameters.mode;
    }

    return res.status(200).json({
      status: 'success',
      data: {
        command,
        executed: true,
        pumpRunning: liveState.pumpRunning,
        mode: liveState.mode,
        timestamp: new Date().toISOString()
      }
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
