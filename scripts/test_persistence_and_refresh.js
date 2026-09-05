/**
 * Verification Test: Baseline Database Persistence, Registration Upsert, and Device Retention
 */
const http = require('http');
const path = require('path');
const fs = require('fs');

// Require the handler directly to test in-process server
const handler = require('../api/index.js');

const server = http.createServer((req, res) => {
  handler(req, res);
});

function request(path, method, body, headers = {}) {
  return new Promise((resolve, reject) => {
    const postData = body ? (typeof body === 'string' ? body : JSON.stringify(body)) : null;
    const req = http.request({
      hostname: '127.0.0.1',
      port: 3099,
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
        try {
          resolve({ status: res.statusCode, data: JSON.parse(data) });
        } catch {
          resolve({ status: res.statusCode, data });
        }
      });
    });
    req.on('error', reject);
    if (postData) req.write(postData);
    req.end();
  });
}

server.listen(3099, '127.0.0.1', async () => {
  console.log('=== Starting Persistence & Device Retention Verification ===\n');

  try {
    // 1. Check Baseline User Login
    console.log('1. Testing baseline admin login (karthiknataraj547@gmail.com)...');
    const loginRes = await request('/api/v1/auth/login', 'POST', {
      email: 'karthiknataraj547@gmail.com',
      password: 'Password123!'
    });
    console.log('   Status:', loginRes.status);
    console.log('   User email:', loginRes.data?.data?.user?.email);
    console.log('   Has accessToken:', !!loginRes.data?.data?.tokens?.accessToken);
    if (loginRes.status !== 200 || !loginRes.data?.data?.tokens?.accessToken) {
      throw new Error('Baseline admin login failed!');
    }
    const token = loginRes.data.data.tokens.accessToken;
    console.log('   ✓ PASS: Baseline admin user logged in successfully.\n');

    // 2. Check Baseline Device Retrieval
    console.log('2. Testing baseline device retrieval (GET /devices?email=karthiknataraj547@gmail.com)...');
    const devRes = await request('/devices?email=karthiknataraj547@gmail.com', 'GET', null, {
      'Authorization': `Bearer ${token}`,
      'x-user-email': 'karthiknataraj547@gmail.com'
    });
    console.log('   Status:', devRes.status);
    console.log('   Devices count:', devRes.data?.data?.length);
    console.log('   Device 0 ID:', devRes.data?.data?.[0]?.id);
    if (devRes.status !== 200 || devRes.data?.data?.length === 0 || devRes.data?.data?.[0]?.id !== 'esp32_pump_94B97E') {
      throw new Error('Baseline device retrieval failed!');
    }
    console.log('   ✓ PASS: Baseline Agricultural Borewell Pump retrieved successfully.\n');

    // 3. Test Dynamic User Registration (Fresh Account)
    const freshEmail = `user_${Date.now()}@hydropulse.io`;
    console.log(`3. Testing fresh user registration (${freshEmail})...`);
    const regRes = await request('/auth/register', 'POST', {
      firstName: 'New',
      lastName: 'Tester',
      email: freshEmail,
      password: 'SecurePassword123!'
    });
    console.log('   Status:', regRes.status);
    console.log('   Has accessToken:', !!regRes.data?.data?.tokens?.accessToken);
    if (regRes.status !== 201) throw new Error('Fresh user registration failed!');
    console.log('   ✓ PASS: Fresh user registration succeeded.\n');

    // 4. Test Registration Upsert / Recovery
    console.log(`4. Testing user registration upsert/re-register (${freshEmail})...`);
    const upRes = await request('/auth/register', 'POST', {
      firstName: 'New',
      lastName: 'TesterUpdated',
      email: freshEmail,
      password: 'NewPassword456!'
    });
    console.log('   Status:', upRes.status);
    console.log('   Message:', upRes.data?.message);
    if (upRes.status !== 200) throw new Error('Registration upsert failed!');
    console.log('   ✓ PASS: Registration upsert succeeded without 400 deadlock.\n');

    // 5. Test Login with Updated Password
    console.log(`5. Testing login with updated password (${freshEmail})...`);
    const newLoginRes = await request('/auth/login', 'POST', {
      email: freshEmail,
      password: 'NewPassword456!'
    });
    console.log('   Status:', newLoginRes.status);
    if (newLoginRes.status !== 200) throw new Error('Login with updated password failed!');
    console.log('   ✓ PASS: Logged in with updated password.\n');

    // 6. Test Token Refresh
    console.log('6. Testing token refresh (/auth/refresh)...');
    const refRes = await request('/auth/refresh', 'POST', {
      refreshToken: newLoginRes.data.data.tokens.refreshToken
    });
    console.log('   Status:', refRes.status);
    console.log('   New accessToken:', !!refRes.data?.data?.accessToken);
    if (refRes.status !== 200 || !refRes.data?.data?.accessToken) throw new Error('Token refresh failed!');
    console.log('   ✓ PASS: Token refresh succeeded.\n');

    // 7. Test Root Route Rewriting Flexibility (/health, /auth/login)
    console.log('7. Testing /health endpoint...');
    const healthRes = await request('/health', 'GET');
    console.log('   Status:', healthRes.status);
    console.log('   Registered users:', healthRes.data?.registeredUsers);
    if (healthRes.status !== 200 || healthRes.data?.registeredUsers < 2) throw new Error('Health check failed!');
    console.log('   ✓ PASS: Health check confirmed active registered users.\n');

    console.log('=== ALL PERSISTENCE AND ROUTING TESTS PASSED! ===');
    process.exit(0);
  } catch (err) {
    console.error('✗ TEST FAILED:', err.message);
    process.exit(1);
  } finally {
    server.close();
  }
});
