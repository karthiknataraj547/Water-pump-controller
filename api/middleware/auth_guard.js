/**
 * HydroPulse Multi-Tenant Auth Guard & Authorization Middleware
 * Verifies JWT token authenticity and enforces strict device ownership boundaries.
 */

const crypto = require('crypto');

const JWT_SECRET = process.env.JWT_SECRET || 'hydropulse-enterprise-jwt-super-secret-key-2026';

/**
 * Verifies and decodes a JWT token.
 * Returns payload if valid, null otherwise.
 */
function verifyToken(token) {
  if (!token || typeof token !== 'string') return null;
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return null;

    const [headerB64, payloadB64, signature] = parts;
    const expectedSig = crypto
      .createHmac('sha256', JWT_SECRET)
      .update(`${headerB64}.${payloadB64}`)
      .digest('base64url');

    // Constant-time signature comparison to prevent timing attacks
    const sigBuf = Buffer.from(signature, 'utf8');
    const expBuf = Buffer.from(expectedSig, 'utf8');
    if (sigBuf.length !== expBuf.length || !crypto.timingSafeEqual(sigBuf, expBuf)) {
      return null;
    }

    const payloadStr = Buffer.from(payloadB64, 'base64url').toString('utf8');
    const payload = JSON.parse(payloadStr);

    // Expiration check
    if (payload.exp && Math.floor(Date.now() / 1000) > payload.exp) {
      return null;
    }

    return payload;
  } catch (_) {
    return null;
  }
}

/**
 * Generates a signed JWT token with standard claims.
 */
function generateToken(userId, email, role = 'user', expiresInSeconds = 7 * 24 * 3600) {
  const header = { alg: 'HS256', typ: 'JWT' };
  const nowSec = Math.floor(Date.now() / 1000);
  const payload = {
    userId,
    email: email.toLowerCase().trim(),
    role,
    iat: nowSec,
    exp: nowSec + expiresInSeconds
  };

  const headerB64 = Buffer.from(JSON.stringify(header)).toString('base64url');
  const payloadB64 = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const signature = crypto
    .createHmac('sha256', JWT_SECRET)
    .update(`${headerB64}.${payloadB64}`)
    .digest('base64url');

  return `${headerB64}.${payloadB64}.${signature}`;
}

/**
 * Extracts Bearer token from request Authorization header or fallback query param.
 */
function extractToken(req) {
  const authHeader = req.headers?.authorization || req.headers?.Authorization || '';
  if (authHeader.startsWith('Bearer ')) {
    return authHeader.substring(7).trim();
  }
  return null;
}

/**
 * Validates that an authenticated user owns or is authorized to access a given device.
 * Enforces strict multi-tenant isolation.
 */
function verifyDeviceOwnership(device, userEmail, userRole = 'user') {
  if (!device) return false;
  if (userRole === 'admin' || userRole === 'superadmin') return true;

  const dEmail = (device.userEmail || '').trim().toLowerCase();
  const dUser = (device.userId || '').trim().toLowerCase();
  const cleanEmail = (userEmail || '').trim().toLowerCase();

  if (!cleanEmail) return false;

  return dEmail === cleanEmail || dUser === cleanEmail;
}

module.exports = {
  JWT_SECRET,
  verifyToken,
  generateToken,
  extractToken,
  verifyDeviceOwnership
};
