/**
 * Automated Verification Script:
 * 1. Register new user account.
 * 2. Verify no mock devices or any devices are added to the user.
 * 3. Log out.
 * 4. Log in again with Email & Password -> Success.
 * 5. Log in again with User ID & Password -> Success.
 * 6. Log in with case-insensitive email -> Success.
 * 7. Negative checks (wrong password, non-existent user).
 */

const http = require('http');
const path = require('path');
const fs = require('fs');
const handler = require('../api/index.js');

const PORT = 3388;
const server = http.createServer((req, res) => {
  handler(req, res);
});

function request(urlPath, method = 'GET', body = null, headers = {}) {
  return new Promise((resolve, reject) => {
    const postData = body ? (typeof body === 'string' ? body : JSON.stringify(body)) : null;
    const req = http.request({
      hostname: '127.0.0.1',
      port: PORT,
      path: urlPath,
      method,
      headers: {
        'Content-Type': 'application/json',
        ...(postData ? { 'Content-Length': Buffer.byteLength(postData) } : {}),
        'X-Forwarded-For': '192.168.1.150', // Bypass rate limiter
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
  console.log(`[${icon}] ${id}: ${title} ${details ? '--> ' + details : ''}`);
}

server.listen(PORT, '127.0.0.1', async () => {
  console.log('================================================================');
  console.log('  TESTING: FIX AUTH RELOGIN & ZERO MOCK DEVICE ATTACHMENT       ');
  console.log('================================================================\n');

  try {
    const uniqueTime = Date.now();
    const testEmail = `relogin_tester_${uniqueTime}@hydropulse.io`;
    const testPassword = 'TestPassword@2026';
    const testName = 'Relogin Tester';

    // 1. Account Creation
    console.log('--- Step 1: Create Account ---');
    const regRes = await request('/auth/register', 'POST', {
      email: testEmail,
      password: testPassword,
      firstName: 'Relogin',
      lastName: 'Tester',
      name: testName
    });

    const regPassed = (regRes.status === 200 || regRes.status === 201) &&
                      regRes.data?.data?.user?.email === testEmail;
    const userId = regRes.data?.data?.user?.id;
    const initialToken = regRes.data?.data?.tokens?.accessToken;
    record('TC-01', 'Register New Account', regPassed, `HTTP ${regRes.status}, User ID: ${userId}`);

    // 2. Check Devices: MUST BE STRICTLY 0!
    console.log('\n--- Step 2: Verify NO Mock or Any Devices are Added ---');
    const devRes = await request('/api/v1/devices', 'GET', null, {
      'Authorization': `Bearer ${initialToken}`
    });
    const deviceCount = devRes.data?.data?.length ?? -1;
    record('TC-02', 'Zero Mock / Any Devices for New Account', deviceCount === 0, `Devices found: ${deviceCount} (Expected 0)`);

    // 3. Logout
    console.log('\n--- Step 3: Logout Account ---');
    const logoutRes = await request('/auth/logout', 'POST', null, {
      'Authorization': `Bearer ${initialToken}`
    });
    record('TC-03', 'Logout Account', logoutRes.status === 200, `HTTP ${logoutRes.status}`);

    // 4. Re-login using Email
    console.log('\n--- Step 4: Re-login using Email ---');
    const reloginEmailRes = await request('/auth/login', 'POST', {
      email: testEmail,
      password: testPassword
    });
    const reloginEmailPassed = reloginEmailRes.status === 200 &&
                               reloginEmailRes.data?.data?.tokens?.accessToken &&
                               reloginEmailRes.data?.data?.user?.email === testEmail;
    record('TC-04', 'Re-login using Email & Password', reloginEmailPassed, `HTTP ${reloginEmailRes.status}`);

    // 5. Re-login using User ID (the user ID e.g. usr_...)
    console.log('\n--- Step 5: Re-login using User ID ---');
    const reloginIdRes = await request('/auth/login', 'POST', {
      email: userId, // User ID entered into the identifier/email field
      password: testPassword
    });
    const reloginIdPassed = reloginIdRes.status === 200 &&
                            reloginIdRes.data?.data?.tokens?.accessToken &&
                            reloginIdRes.data?.data?.user?.id === userId;
    record('TC-05', 'Re-login using User ID & Password', reloginIdPassed, `HTTP ${reloginIdRes.status}, Resolved user: ${reloginIdRes.data?.data?.user?.email}`);

    // 6. Case-insensitive email login
    console.log('\n--- Step 6: Re-login using Uppercase Email ---');
    const upperEmailRes = await request('/auth/login', 'POST', {
      email: testEmail.toUpperCase(),
      password: testPassword
    });
    record('TC-06', 'Re-login using UPPERCASE Email', upperEmailRes.status === 200, `HTTP ${upperEmailRes.status}`);

    // 7. Negative tests
    console.log('\n--- Step 7: Negative Checks ---');
    const wrongPwdRes = await request('/auth/login', 'POST', {
      email: testEmail,
      password: 'IncorrectPassword999!'
    });
    record('TC-07', 'Reject Incorrect Password', wrongPwdRes.status === 401, `HTTP ${wrongPwdRes.status}, Message: ${wrongPwdRes.data?.message}`);

    const ghostUserRes = await request('/auth/login', 'POST', {
      email: 'nonexistent_ghost_9999@hydropulse.io',
      password: testPassword
    });
    record('TC-08', 'Reject Non-Existent User', ghostUserRes.status === 401, `HTTP ${ghostUserRes.status}`);

    // 8. Re-verify database persistence in file
    console.log('\n--- Step 8: Database Persistence Check ---');
    const dbPath = path.join(__dirname, '..', 'api', 'database.json');
    const dbData = JSON.parse(fs.readFileSync(dbPath, 'utf8'));
    const savedUser = dbData.users.find(u => u.email === testEmail || u.id === userId);
    record('TC-09', 'Persisted to api/database.json', !!savedUser, savedUser ? `Found User ID: ${savedUser.id}, Email: ${savedUser.email}` : 'Not found on disk');

    // Print summary
    console.log('\n================================================================');
    console.log('                       TEST SUMMARY                             ');
    console.log('================================================================');
    const total = results.length;
    const passed = results.filter(r => r.passed).length;
    console.log(`Total: ${total} | Passed: ${passed} | Failed: ${total - passed}`);
    console.log(`Success Rate: ${(passed / total * 100).toFixed(1)}%`);
    console.log('================================================================\n');

    if (total === passed) {
      console.log('ALL TESTS PASSED SUCCESSFULLY.');
    } else {
      console.error('SOME TESTS FAILED.');
      process.exitCode = 1;
    }

  } catch (err) {
    console.error('Test error:', err);
    process.exitCode = 1;
  } finally {
    server.close();
    process.exit(process.exitCode || 0);
  }
});
