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

// Seed default users
const adminSalt = crypto.randomBytes(16).toString('hex');
const adminHash = hashPassword('AdminPassword123!', adminSalt).hash;
const defaultAdmin = {
  id: 'usr_admin_001',
  email: 'admin@waterpump.io',
  passwordHash: adminHash,
  salt: adminSalt,
  firstName: 'Admin',
  lastName: 'HydroPulse',
  role: 'ADMIN',
  createdAt: new Date().toISOString()
};
usersDb.set(defaultAdmin.email, defaultAdmin);

const karthikSalt = crypto.randomBytes(16).toString('hex');
const karthikHash = hashPassword('Password123!', karthikSalt).hash;
const defaultKarthik = {
  id: 'usr_karthik_002',
  email: 'karthik.iotpump@gmail.com',
  passwordHash: karthikHash,
  salt: karthikSalt,
  firstName: 'Karthik',
  lastName: 'Nataraj',
  role: 'ADMIN',
  createdAt: new Date().toISOString()
};
usersDb.set(defaultKarthik.email, defaultKarthik);

// Global live state for pump
let liveState = {
  pumpRunning: false,
  mode: 'AUTO',
  waterLevelPct: 68.5,
  flowRateLpm: 0.0,
  powerKw: 0.00,
  tdsPpm: 118,
  tempC: 24.5,
  lastSeen: Date.now()
};

module.exports = async (req, res) => {
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
  } else if (method === 'POST' || method === 'PUT') {
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
  if (url === '/health' || url.endsWith('/health')) {
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
      version: '2.0.1',
      build_number: 3,
      release_date: '2026-09-03',
      min_supported_version: '1.0.0',
      download_url: 'https://github.com/karthiknataraj547/Water-pump-controller/raw/main/releases/HydroPulse_WaterPumpController.apk',
      website_url: 'https://github.com/karthiknataraj547/Water-pump-controller',
      title: 'HydroPulse v2.0.1 - System Console, Minimalism UI & Central Auth Update',
      changelog: [
        'Enterprise System Console with persistent left sidebar navigation',
        'Full mobile-responsive website and web application layouts',
        'Centralized account authentication and direct mobile registration',
        'Strict hardware presence verification with sub-100ms ping/pong handshake',
        'Automatic In-App OTA Update System managed by backend'
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
    if (!email || !password || !firstName || !lastName) {
      return res.status(400).json({ status: 'error', message: 'First name, last name, email, and password are required.' });
    }
    if (password.length < 8) {
      return res.status(400).json({ status: 'error', message: 'Password must be at least 8 characters long.' });
    }

    const cleanEmail = email.trim().toLowerCase();
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
      firstName: firstName.trim(),
      lastName: lastName.trim(),
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

  // 4. User Login
  if (method === 'POST' && url.includes('/api/v1/auth/login')) {
    const { email, password } = body;
    if (!email || !password) {
      return res.status(400).json({ status: 'error', message: 'Email and password are required.' });
    }

    const cleanEmail = email.trim().toLowerCase();
    const user = usersDb.get(cleanEmail);

    if (!user || !verifyPassword(password, user.passwordHash, user.salt)) {
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
    return res.status(200).json({
      status: 'success',
      data: [
        {
          id: 'esp32_pump_main',
          deviceId: 'esp32_pump_main',
          name: 'ESP32 Main Gateway',
          macAddress: '3C:61:05:D4:B2:A0',
          isOnline: true,
          pumpRunning: liveState.pumpRunning,
          mode: liveState.mode,
          waterLevelPct: liveState.waterLevelPct
        }
      ]
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

  // Default fallback
  return res.status(404).json({ status: 'error', message: 'Endpoint not found' });
};
