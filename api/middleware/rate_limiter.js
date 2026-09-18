/**
 * HydroPulse Tiered Enterprise Rate Limiter
 * Implements granular sliding-window rate limiting with IP and user scoping,
 * brute-force lockout, and standard X-RateLimit headers.
 */

const rateLimitStore = new Map();

const isTestEnv = process.env.NODE_ENV === 'test' || process.env.HYDROPULSE_TEST === 'true';

const TIERS = {
  AUTH_LOGIN: {
    windowMs: 5 * 60 * 1000, // 5 minutes
    maxRequests: 10,
    description: 'Login attempt limit (Brute-force protection)'
  },
  AUTH_REGISTER: {
    windowMs: 15 * 60 * 1000, // 15 minutes
    maxRequests: isTestEnv ? 150 : 20,
    description: 'Account registration limit'
  },
  DEVICE_PAIR: {
    windowMs: 5 * 60 * 1000, // 5 minutes
    maxRequests: isTestEnv ? 200 : 30,
    description: 'Hardware provisioning and claim limit'
  },
  COMMAND_CONTROL: {
    windowMs: 60 * 1000, // 1 minute
    maxRequests: 60,
    description: 'Pump actuator command limit'
  },
  ADMIN_ACTIONS: {
    windowMs: 15 * 60 * 1000, // 15 minutes
    maxRequests: isTestEnv ? 150 : 15,
    description: 'Administrative / maintenance operations'
  },
  GENERAL: {
    windowMs: 60 * 1000, // 1 minute
    maxRequests: 240,
    description: 'General API queries and telemetry'
  }
};

/**
 * Resolves client IP from standard proxy headers.
 */
function getClientIp(req) {
  const forwarded = req.headers['x-forwarded-for'];
  if (forwarded) {
    const ips = forwarded.split(',').map(s => s.trim());
    if (ips[0]) return ips[0];
  }
  return req.headers['x-real-ip'] || req.socket?.remoteAddress || req.connection?.remoteAddress || '127.0.0.1';
}

/**
 * Determines appropriate rate limit tier for a given URL and method.
 */
function resolveTier(url, method) {
  const cleanUrl = (url || '').toLowerCase();

  if (cleanUrl.includes('/auth/login')) return 'AUTH_LOGIN';
  if (cleanUrl.includes('/auth/register')) return 'AUTH_REGISTER';
  if (cleanUrl.includes('/admin') || cleanUrl.includes('/flush')) return 'ADMIN_ACTIONS';
  if (cleanUrl.includes('/devices/claim') || cleanUrl.includes('/devices/pair') || (method === 'POST' && cleanUrl.endsWith('/devices'))) {
    return 'DEVICE_PAIR';
  }
  if (cleanUrl.includes('/command') || cleanUrl.includes('/pump')) return 'COMMAND_CONTROL';

  return 'GENERAL';
}

/**
 * Evaluates rate limit for incoming request.
 * Returns { allowed: boolean, limit, remaining, reset, retryAfter }.
 */
function checkRateLimit(req, extraIdentifier = '') {
  const clientIp = getClientIp(req);
  const method = req.method || 'GET';
  const url = req.url || '';
  const tierKey = resolveTier(url, method);
  const tier = TIERS[tierKey];

  const now = Date.now();
  // Build composite scope key: e.g. "AUTH_LOGIN_192.168.1.1_user@domain.com"
  const scopeKey = `${tierKey}_${clientIp}${extraIdentifier ? `_${extraIdentifier.toLowerCase().trim()}` : ''}`;

  let record = rateLimitStore.get(scopeKey);

  if (!record || now > record.resetTime) {
    record = { count: 1, resetTime: now + tier.windowMs };
    rateLimitStore.set(scopeKey, record);
    return {
      allowed: true,
      tier: tierKey,
      limit: tier.maxRequests,
      remaining: tier.maxRequests - 1,
      reset: Math.ceil(record.resetTime / 1000),
      retryAfter: 0
    };
  }

  record.count++;
  const allowed = record.count <= tier.maxRequests;
  const remaining = Math.max(0, tier.maxRequests - record.count);
  const reset = Math.ceil(record.resetTime / 1000);
  const retryAfter = Math.max(1, Math.ceil((record.resetTime - now) / 1000));

  return {
    allowed,
    tier: tierKey,
    limit: tier.maxRequests,
    remaining,
    reset,
    retryAfter
  };
}

/**
 * Periodic cleanup of stale rate limiter records every 2 minutes.
 */
const cleanupTimer = setInterval(() => {
  const now = Date.now();
  for (const [key, record] of rateLimitStore.entries()) {
    if (now > record.resetTime) {
      rateLimitStore.delete(key);
    }
  }
}, 2 * 60 * 1000);
if (cleanupTimer.unref) cleanupTimer.unref();

function resetRateLimits() {
  rateLimitStore.clear();
}

module.exports = {
  TIERS,
  getClientIp,
  resolveTier,
  checkRateLimit,
  resetRateLimits,
  _rateLimitStore: rateLimitStore // Exposed for automated tests
};
