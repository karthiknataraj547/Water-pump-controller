/**
 * HydroPulse Enterprise Security Middleware
 * Provides Helmet-style HTTP security headers, recursive input sanitization,
 * prototype pollution defense, timing-safe crypto comparison, and schema validation.
 */

const crypto = require('crypto');

/**
 * Applies strict HTTP security headers to all responses.
 */
function applySecurityHeaders(res) {
  // Prevent MIME type sniffing
  res.setHeader('X-Content-Type-Options', 'nosniff');

  // Prevent Clickjacking via iframes
  res.setHeader('X-Frame-Options', 'DENY');

  // Cross-Site Scripting (XSS) filter
  res.setHeader('X-XSS-Protection', '1; mode=block');

  // Strict Transport Security (HSTS) - 1 year with subdomains
  res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains; preload');

  // Referrer policy
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');

  // Restrict browser feature permissions
  res.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=(), payment=()');

  // Content Security Policy (strict defaults)
  res.setHeader(
    'Content-Security-Policy',
    "default-src 'self'; script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' data: https:; connect-src 'self' https://water-pump-controller.vercel.app wss: https:;"
  );
}

/**
 * Recursively sanitizes input objects to prevent prototype pollution and NoSQL injection.
 * Strips keys such as __proto__, constructor, and prototype.
 * Truncates excessively long strings to prevent ReDoS or buffer exhaustion.
 */
function sanitizeInput(data, depth = 0) {
  if (depth > 8) return null; // Guard against circular/deeply-nested objects
  if (data === null || data === undefined) return data;

  if (typeof data === 'string') {
    // Truncate strings exceeding 4096 chars unless base64 payload
    if (data.length > 4096 && !data.startsWith('data:')) {
      data = data.substring(0, 4096);
    }
    // Neutralize dangerous XSS script tags and executable JavaScript injections
    data = data
      .replace(/<\s*script[^>]*>[\s\S]*?<\s*\/\s*script\s*>/gi, '')
      .replace(/<\s*script[^>]*>/gi, '')
      .replace(/<\s*\/\s*script\s*>/gi, '')
      .replace(/javascript:/gi, '');
    // Remove control characters (except common whitespace)
    return data.replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '').trim();
  }

  if (typeof data === 'number' || typeof data === 'boolean') {
    return data;
  }

  if (Array.isArray(data)) {
    return data.slice(0, 100).map(item => sanitizeInput(item, depth + 1));
  }

  if (typeof data === 'object') {
    const clean = {};
    for (const [key, val] of Object.entries(data)) {
      // Prototype pollution defense
      const cleanKey = String(key).trim();
      if (cleanKey === '__proto__' || cleanKey === 'constructor' || cleanKey === 'prototype') {
        continue;
      }
      // Skip dangerous property names
      if (cleanKey.includes('$') || cleanKey.includes('.')) {
        continue;
      }
      clean[cleanKey] = sanitizeInput(val, depth + 1);
    }
    return clean;
  }

  return null;
}

/**
 * Validates email format strictly against RFC 5322 compatible regex.
 */
function isValidEmail(email) {
  if (!email || typeof email !== 'string') return false;
  const re = /^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$/;
  return email.length <= 254 && re.test(email);
}

/**
 * Validates hardware Device ID (alphanumeric, underscores, hyphens only, 3-64 chars).
 */
function isValidDeviceId(devId) {
  if (!devId || typeof devId !== 'string') return false;
  return /^[a-zA-Z0-9_\-:]{3,64}$/.test(devId.trim());
}

/**
 * Performs a constant-time string comparison to prevent timing attacks.
 */
function timingSafeCompare(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  const bufA = Buffer.from(a, 'utf8');
  const bufB = Buffer.from(b, 'utf8');
  if (bufA.length !== bufB.length) {
    // Constant time dummy comparison
    crypto.timingSafeEqual(bufA, bufA);
    return false;
  }
  return crypto.timingSafeEqual(bufA, bufB);
}

module.exports = {
  applySecurityHeaders,
  sanitizeInput,
  isValidEmail,
  isValidDeviceId,
  timingSafeCompare
};
