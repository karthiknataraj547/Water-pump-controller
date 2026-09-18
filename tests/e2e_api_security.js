/**
 * HydroPulse Test Suite 1: Authentication, REST API & Security Testing
 * Covers TC-AUTH-001 through TC-AUTH-010, Sections 14, 15, 23, 25, and 26.
 */

const http = require('http');
const path = require('path');
const handler = require('../api/index.js');

const PORT = 3199;
const server = http.createServer((req, res) => {
  handler(req, res);
});

function request(path, method = 'GET', body = null, headers = {}) {
  return new Promise((resolve, reject) => {
    const postData = body ? (typeof body === 'string' ? body : JSON.stringify(body)) : null;
    const req = http.request({
      hostname: '127.0.0.1',
      port: PORT,
      path,
      method,
      headers: {
        'Content-Type': 'application/json',
        ...(postData ? { 'Content-Length': Buffer.byteLength(postData) } : {}),
        ...headers
      }
    }, res => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        let parsed = null;
        try { parsed = JSON.parse(data); } catch (_) { parsed = data; }
        resolve({
          status: res.statusCode,
          headers: res.headers,
          data: parsed,
          raw: data
        });
      });
    });
    req.on('error', reject);
    if (postData) req.write(postData);
    req.end();
  });
}

const results = [];
function record(id, title, passed, details = '') {
  results.push({ id, title, passed, details });
  const icon = passed ? '✓ PASS' : '✗ FAIL';
  console.log(`[${icon}] ${id}: ${title} ${details ? '(' + details + ')' : ''}`);
}

server.listen(PORT, '127.0.0.1', async () => {
  console.log('================================================================');
  console.log('       HYDROPULSE E2E TEST SUITE 1: AUTH, API & SECURITY       ');
  console.log('================================================================\n');

  try {
    // -------------------------------------------------------------------------
    // 1. AUTHENTICATION TEST CASES (TC-AUTH-001 to TC-AUTH-010)
    // -------------------------------------------------------------------------
    console.log('--- Phase 1: Authentication Testing (TC-AUTH-001 - TC-AUTH-010) ---');

    // TC-AUTH-001: Valid Login with baseline user
    const resAuth1 = await request('/auth/login', 'POST', {
      email: 'karthiknataraj547@gmail.com',
      password: 'karthik@547'
    });
    const auth1Passed = resAuth1.status === 200 && resAuth1.data?.data?.tokens?.accessToken && resAuth1.data?.data?.user?.email;
    record('TC-AUTH-001', 'Valid Login', auth1Passed, `Status: ${resAuth1.status}`);
    const validToken = resAuth1.data?.data?.tokens?.accessToken;

    // TC-AUTH-002: Invalid Password
    const resAuth2 = await request('/auth/login', 'POST', {
      email: 'karthiknataraj547@gmail.com',
      password: 'WrongPassword999!'
    });
    const auth2Passed = resAuth2.status === 401 && !resAuth2.raw.includes('password123');
    record('TC-AUTH-002', 'Invalid Password Rejected', auth2Passed, `Status: ${resAuth2.status}, error: ${resAuth2.data?.message}`);

    // TC-AUTH-003: Invalid / Non-existent Username
    const resAuth3 = await request('/auth/login', 'POST', {
      email: 'nonexistent_user_9999@randomdomain.xyz',
      password: 'SomePassword123!'
    });
    const auth3Passed = resAuth3.status === 401 || resAuth3.status === 404;
    record('TC-AUTH-003', 'Non-existent Username Rejected', auth3Passed, `Status: ${resAuth3.status}`);

    // TC-AUTH-004: Empty Username / Email
    const resAuth4 = await request('/auth/login', 'POST', {
      email: '',
      password: 'SomePassword123!'
    });
    const auth4Passed = resAuth4.status === 400;
    record('TC-AUTH-004', 'Empty Username Validation', auth4Passed, `Status: ${resAuth4.status}`);

    // TC-AUTH-005: Empty Password
    const resAuth5 = await request('/auth/login', 'POST', {
      email: 'karthiknataraj547@gmail.com',
      password: ''
    });
    const auth5Passed = resAuth5.status === 400;
    record('TC-AUTH-005', 'Empty Password Validation', auth5Passed, `Status: ${resAuth5.status}`);

    // TC-AUTH-006: Both Fields Empty
    const resAuth6 = await request('/auth/login', 'POST', {
      email: '',
      password: ''
    });
    const auth6Passed = resAuth6.status === 400;
    record('TC-AUTH-006', 'Both Fields Empty Validation', auth6Passed, `Status: ${resAuth6.status}`);

    // TC-AUTH-007: Password Security & Masking
    const resProfile = await request('/auth/profile', 'GET', null, {
      'Authorization': `Bearer ${validToken}`
    });
    const profileDataStr = JSON.stringify(resProfile.data);
    const auth7Passed = !profileDataStr.includes('Password123!') && !profileDataStr.includes('passwordHash');
    record('TC-AUTH-007', 'Password Hashing & Response Masking', auth7Passed, 'No passwords or passwordHash leaked in profile response');

    // TC-AUTH-008: Logout / Token Invalidation
    const resAuth8 = await request('/auth/logout', 'POST', {}, {
      'Authorization': `Bearer ${validToken}`
    });
    const auth8Passed = resAuth8.status === 200;
    record('TC-AUTH-008', 'Logout Session Cleared', auth8Passed, `Status: ${resAuth8.status}`);

    // TC-AUTH-009: Expired / Corrupt Session Token
    const corruptToken = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE1MTYyMzkwMjJ9.InvalidSignature';
    const resAuth9 = await request('/auth/profile', 'GET', null, {
      'Authorization': `Bearer ${corruptToken}`
    });
    const auth9Passed = resAuth9.status === 401;
    record('TC-AUTH-009', 'Expired / Corrupt Token Rejection', auth9Passed, `Status: ${resAuth9.status}`);

    // TC-AUTH-010: Rate Limiting on Auth Endpoints (Isolated IP)
    console.log('Testing rate-limiting protection on /auth/login with simulated IP...');
    let rateLimited = false;
    for (let i = 0; i < 20; i++) {
      const res = await request('/auth/login', 'POST', { email: 'bad@try.com', password: 'bad' }, {
        'X-Forwarded-For': '198.51.100.42'
      });
      if (res.status === 429) {
        rateLimited = true;
        break;
      }
    }
    record('TC-AUTH-010', 'Rate Limiting / Brute-force Throttling', rateLimited, '429 Rate Limit returned upon threshold exceeded');

    // -------------------------------------------------------------------------
    // 2. BACKEND API & MOTOR COMMAND MATRIX (Sections 14 & 15)
    // -------------------------------------------------------------------------
    console.log('\n--- Phase 2: Backend API & Motor Command Validation (Sections 14 & 15) ---');

    // TC-API-001: Health Endpoint (200 OK)
    const resHealth = await request('/health', 'GET');
    record('TC-API-001', 'GET /health Returns 200 OK', resHealth.status === 200, `Environment: ${resHealth.data?.environment || 'ok'}`);

    // TC-API-002: Version Endpoint (200 OK)
    const resVersion = await request('/version.json', 'GET');
    record('TC-API-002', 'GET /version.json Returns 200 OK', resVersion.status === 200 && Boolean(resVersion.data?.version?.startsWith('2.2.')));

    // TC-API-003: 404 on Unknown API Endpoint
    const res404 = await request('/api/v1/unknown_resource_xyz', 'GET');
    record('TC-API-003', 'Unknown Endpoint Returns 404', res404.status === 404);

    // TC-API-004: Malformed JSON payload handling
    const resMalformed = await request('/auth/login', 'POST', 'INVALID_NOT_A_JSON{}}{');
    record('TC-API-004', 'Malformed JSON Payload Handled Gracefully', resMalformed.status === 400);

    // TC-MOTOR-API-001: Motor Command with Unauthorized Caller
    const resMotorUnauth = await request('/devices/esp32_pump_AA69E0/pump', 'POST', { action: 'START' });
    record('TC-MOTOR-API-001', 'Motor Command Unauthenticated Rejection', resMotorUnauth.status === 401);

    // TC-MOTOR-API-002: Motor Command for Unknown Device
    const resMotorUnknown = await request('/devices/esp32_nonexistent_xyz999/pump', 'POST', { action: 'START' }, {
      'Authorization': `Bearer ${validToken}`
    });
    record('TC-MOTOR-API-002', 'Motor Command Unknown Device Rejection', resMotorUnknown.status === 404 || resMotorUnknown.status === 400);

    // TC-MOTOR-API-003: Motor Command When Device is OFFLINE
    const resMotorOffline = await request('/devices/esp32_pump_AA69E0/pump', 'POST', { action: 'START' }, {
      'Authorization': `Bearer ${validToken}`
    });
    const motorOfflinePassed = resMotorOffline.status === 400 || resMotorOffline.status === 503 || resMotorOffline.data?.message?.includes('offline') || resMotorOffline.data?.error?.includes('offline');
    record('TC-MOTOR-API-003', 'START Command on Offline Device Rejection', motorOfflinePassed, `Response: ${resMotorOffline.status} - ${resMotorOffline.data?.message || resMotorOffline.data?.error}`);

    // TC-MOTOR-API-004: Invalid Motor Action
    const resMotorBadAction = await request('/devices/esp32_pump_AA69E0/pump', 'POST', { action: 'INVALID_ACTION' }, {
      'Authorization': `Bearer ${validToken}`
    });
    record('TC-MOTOR-API-004', 'Invalid Motor Action Rejection', resMotorBadAction.status === 400);

    // -------------------------------------------------------------------------
    // 3. DATABASE PERSISTENCE & MULTI-USER ISOLATION (Sections 23 & 25)
    // -------------------------------------------------------------------------
    console.log('\n--- Phase 3: Database Persistence & Multi-Tenant Isolation (Sections 23 & 25) ---');

    // TC-DB-001: Register User A
    const userAEmail = `user_a_${Date.now()}@hydropulse.io`;
    const resRegA = await request('/auth/register', 'POST', {
      email: userAEmail,
      password: 'UserAPass123!',
      firstName: 'Alice',
      lastName: 'Hydropulse'
    });
    const tokenA = resRegA.data?.data?.tokens?.accessToken;
    record('TC-DB-001', 'User A Registered & Persisted', resRegA.status === 201 && tokenA);

    // TC-DB-002: Register User B
    const userBEmail = `user_b_${Date.now()}@hydropulse.io`;
    const resRegB = await request('/auth/register', 'POST', {
      email: userBEmail,
      password: 'UserBPass123!',
      firstName: 'Bob',
      lastName: 'Hydropulse'
    });
    const tokenB = resRegB.data?.data?.tokens?.accessToken;
    record('TC-DB-002', 'User B Registered & Persisted', resRegB.status === 201 && tokenB);

    // TC-DB-003: User A and User B Device Isolation
    const resDevA = await request('/devices', 'GET', null, { 'Authorization': `Bearer ${tokenA}` });
    const resDevB = await request('/devices', 'GET', null, { 'Authorization': `Bearer ${tokenB}` });
    const listA = resDevA.data?.data || [];
    const listB = resDevB.data?.data || [];
    const isolationPassed = Array.isArray(listA) && Array.isArray(listB) && listA.length === 0 && listB.length === 0;
    record('TC-DB-003', 'Multi-User Device Tenant Isolation', isolationPassed, `User A devices: ${listA.length}, User B devices: ${listB.length}`);

    // -------------------------------------------------------------------------
    // 4. SECURITY VULNERABILITY AUDIT (Section 26)
    // -------------------------------------------------------------------------
    console.log('\n--- Phase 4: Security Vulnerability & Injection Testing (Section 26) ---');

    // TC-SEC-001: SQL / NoSQL Injection Payload in Login
    const sqlInjectionPayloads = [
      "' OR '1'='1",
      "admin' --",
      "{\"email\": {\"$gt\": \"\"}, \"password\": \"test\"}",
      "1; DROP TABLE users;"
    ];
    let sqlInjPassed = true;
    for (const inj of sqlInjectionPayloads) {
      const resInj = await request('/auth/login', 'POST', { email: inj, password: 'password123' });
      if (resInj.status === 200) {
        sqlInjPassed = false;
        break;
      }
    }
    record('TC-SEC-001', 'SQL / NoSQL Injection Resistance', sqlInjPassed, 'All SQL injection payloads safely rejected');

    // TC-SEC-002: Stored / Reflected XSS Payload Sanitization
    const xssPayload = "<script>alert('xss_attack_vector')</script>";
    const resXss = await request('/auth/register', 'POST', {
      email: `xss_test_${Date.now()}@safe.io`,
      password: 'Password123!',
      firstName: xssPayload,
      lastName: 'Sanitized'
    });
    const xssPassed = !resXss.raw.includes("<script>alert('xss_attack_vector')</script>") || resXss.data?.data?.user?.firstName !== xssPayload;
    record('TC-SEC-002', 'XSS Injection Handling', xssPassed, 'XSS script tags neutralized or sanitized');

    // TC-SEC-003: Sensitive System Secrets Exposure Audit
    const responsesToCheck = [resAuth1.raw, resProfile.raw, resHealth.raw, resVersion.raw];
    const sensitiveStrings = ['hydropulse_jwt_secret', 'super_secret', 'postgresql://', 'iot_password'];
    let leakDetected = false;
    for (const raw of responsesToCheck) {
      for (const secret of sensitiveStrings) {
        if (raw && raw.includes(secret)) {
          leakDetected = true;
          break;
        }
      }
    }
    record('TC-SEC-003', 'Zero Sensitive Secrets Exposure Audit', !leakDetected, 'No database passwords or JWT secret keys exposed in HTTP output');

    // -------------------------------------------------------------------------
    // SUMMARY
    // -------------------------------------------------------------------------
    console.log('\n================================================================');
    console.log('                  SUITE 1 EXECUTION SUMMARY                     ');
    console.log('================================================================');
    const total = results.length;
    const passed = results.filter(r => r.passed).length;
    const failed = total - passed;
    console.log(`Total Test Cases: ${total}`);
    console.log(`Passed:          ${passed}`);
    console.log(`Failed:          ${failed}`);
    console.log(`Success Rate:    ${((passed / total) * 100).toFixed(1)}%`);
    console.log('================================================================\n');

    server.close(() => {
      process.exit(failed === 0 ? 0 : 1);
    });
  } catch (err) {
    console.error('Test Suite encountered unhandled exception:', err);
    server.close(() => process.exit(1));
  }
});
