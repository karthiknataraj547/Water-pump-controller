/**
 * Automated Verification Script: Account Creation, Auth, Database Persistence,
 * Mock Hardware Prevention & Similar IDs Audit.
 *
 * Requirements:
 * 1. Create account with Name: Karthik N, Email: karthiknataraj547@gmail.com, Password: karthik@547.
 * 2. Verify login functionality, negative login checks, and database persistence.
 * 3. Verify logout and re-login to the same account.
 * 4. Verify NO hardware is added prior as a mock (clean device list check).
 * 5. Check similar IDs across database and produce full list.
 */

const http = require('http');
const fs = require('fs');
const path = require('path');
const handler = require('../api/index.js');

const PORT = 3299;
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
        'X-Forwarded-For': '192.168.1.100', // Bypass rate-limiter for test harness
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

const testResults = [];
function record(id, title, passed, details = '') {
  testResults.push({ id, title, passed, details });
  const icon = passed ? '✓ PASS' : '✗ FAIL';
  console.log(`[${icon}] ${id}: ${title} ${details ? '--> ' + details : ''}`);
}

server.listen(PORT, '127.0.0.1', async () => {
  console.log('================================================================');
  console.log('  HYDROPULSE AUTH, DATABASE & MOCK HARDWARE AUDIT TEST SUITE   ');
  console.log('================================================================\n');

  try {
    // -------------------------------------------------------------------------
    // Phase 1: Account Creation with requested credentials
    // -------------------------------------------------------------------------
    console.log('--- Phase 1: Account Creation (Karthik N / karthik@547) ---');
    const targetEmail = 'karthiknataraj547@gmail.com';
    const targetPassword = 'karthik@547';
    const targetName = 'Karthik N';

    const regRes = await request('/auth/register', 'POST', {
      name: targetName,
      firstName: 'Karthik',
      lastName: 'N',
      email: targetEmail,
      password: targetPassword
    });

    const regPassed = (regRes.status === 200 || regRes.status === 201) &&
                      regRes.data?.data?.tokens?.accessToken &&
                      regRes.data?.data?.user?.email === targetEmail;
    record('TC-REG-001', 'Account Registration/Update', regPassed, `HTTP ${regRes.status}, User: ${regRes.data?.data?.user?.firstName} ${regRes.data?.data?.user?.lastName}`);

    const accessToken1 = regRes.data?.data?.tokens?.accessToken;

    // -------------------------------------------------------------------------
    // Phase 2: Database Persistence & Hash Verification
    // -------------------------------------------------------------------------
    console.log('\n--- Phase 2: Database Persistence & Cryptographic Integrity ---');
    const dbPath = path.join(__dirname, '..', 'api', 'database.json');
    const dbData = JSON.parse(fs.readFileSync(dbPath, 'utf8'));
    const userInDb = dbData.users.find(u => u.email === targetEmail);

    const dbPersistPassed = !!userInDb &&
                            userInDb.firstName === 'Karthik' &&
                            userInDb.lastName === 'N' &&
                            !!userInDb.passwordHash &&
                            userInDb.salt?.length === 32;
    record('TC-DB-001', 'Database Persistence in api/database.json', dbPersistPassed,
      userInDb ? `Stored ID: ${userInDb.id}, Salt: ${userInDb.salt?.substring(0, 8)}..., Hash: ${userInDb.passwordHash?.substring(0, 12)}...` : 'User not found in DB');

    // -------------------------------------------------------------------------
    // Phase 3: Login Verification with New Password
    // -------------------------------------------------------------------------
    console.log('\n--- Phase 3: Login Verification with New Password ---');
    const loginRes = await request('/auth/login', 'POST', {
      email: targetEmail,
      password: targetPassword
    });
    const loginPassed = loginRes.status === 200 &&
                        loginRes.data?.data?.tokens?.accessToken &&
                        loginRes.data?.data?.user?.email === targetEmail;
    record('TC-LOGIN-001', 'Valid Login with karthik@547', loginPassed, `HTTP ${loginRes.status}, Token: ${loginRes.data?.data?.tokens?.accessToken?.substring(0, 20)}...`);

    const activeToken = loginRes.data?.data?.tokens?.accessToken;

    // Negative Login Tests
    const wrongPwdRes = await request('/auth/login', 'POST', {
      email: targetEmail,
      password: 'wrong_password_999'
    });
    record('TC-LOGIN-002', 'Reject Invalid Password', wrongPwdRes.status === 401, `HTTP ${wrongPwdRes.status}, Message: ${wrongPwdRes.data?.message}`);

    const oldPwdRes = await request('/auth/login', 'POST', {
      email: targetEmail,
      password: 'Password123!' // Old password prior to update
    });
    record('TC-LOGIN-003', 'Reject Obsolete Password', oldPwdRes.status === 401, `HTTP ${oldPwdRes.status} (Old password correctly revoked)`);

    const emptyEmailRes = await request('/auth/login', 'POST', {
      email: '',
      password: targetPassword
    });
    record('TC-LOGIN-004', 'Reject Empty Email', emptyEmailRes.status === 400, `HTTP ${emptyEmailRes.status}`);

    const emptyPwdRes = await request('/auth/login', 'POST', {
      email: targetEmail,
      password: ''
    });
    record('TC-LOGIN-005', 'Reject Empty Password', emptyPwdRes.status === 400, `HTTP ${emptyPwdRes.status}`);

    const nonExistentRes = await request('/auth/login', 'POST', {
      email: 'nonexistent_karthik_ghost@gmail.com',
      password: targetPassword
    });
    record('TC-LOGIN-006', 'Reject Unregistered Email', nonExistentRes.status === 401, `HTTP ${nonExistentRes.status}`);

    // -------------------------------------------------------------------------
    // Phase 4: Logout and Re-Login Cycle
    // -------------------------------------------------------------------------
    console.log('\n--- Phase 4: Logout and Re-Login Cycle ---');
    const logoutRes = await request('/auth/logout', 'POST', null, {
      'Authorization': `Bearer ${activeToken}`
    });
    record('TC-LOGOUT-001', 'Logout Session Termination', logoutRes.status === 200, `HTTP ${logoutRes.status}, Message: ${logoutRes.data?.message}`);

    // Re-login after logout
    const reloginRes = await request('/auth/login', 'POST', {
      email: targetEmail,
      password: targetPassword
    });
    const reloginPassed = reloginRes.status === 200 && reloginRes.data?.data?.tokens?.accessToken;
    record('TC-LOGIN-007', 'Re-login to Same Account After Logout', reloginPassed, `HTTP ${reloginRes.status}`);
    const freshToken = reloginRes.data?.data?.tokens?.accessToken;

    // Verify user profile
    const profileRes = await request('/auth/profile', 'GET', null, {
      'Authorization': `Bearer ${freshToken}`
    });
    const profilePassed = profileRes.status === 200 &&
                          profileRes.data?.data?.user?.email === targetEmail &&
                          profileRes.data?.data?.user?.firstName === 'Karthik' &&
                          profileRes.data?.data?.user?.lastName === 'N';
    record('TC-PROFILE-001', 'User Profile Integrity', profilePassed,
      `Name: ${profileRes.data?.data?.user?.firstName} ${profileRes.data?.data?.user?.lastName}, Role: ${profileRes.data?.data?.user?.role}`);

    // -------------------------------------------------------------------------
    // Phase 5: Hardware & Mock Device Audit
    // -------------------------------------------------------------------------
    console.log('\n--- Phase 5: Hardware & Mock Device Audit ---');
    // Check devices for karthiknataraj547@gmail.com
    const devRes = await request('/api/v1/devices', 'GET', null, {
      'Authorization': `Bearer ${freshToken}`
    });

    const devices = Array.isArray(devRes.data?.data) ? devRes.data.data : [];
    const mockDeviceIds = ['esp32_pump_94B97E', 'esp32_pump_000000', 'esp32_1789210772705', 'esp32_1789210772713', 'esp32_1789210772719', 'esp32_e2e_1789211088759'];
    const foundMockDevices = devices.filter(d => mockDeviceIds.includes(d.id));
    const noMocksPassed = foundMockDevices.length === 0;

    record('TC-HARDWARE-001', 'No Mock Devices Attached to User', noMocksPassed,
      `User Device Count: ${devices.length}. Found Mocks: ${foundMockDevices.length} (${foundMockDevices.map(d=>d.id).join(', ') || 'None'})`);

    // Only genuine hardware should exist
    const realHardware = devices.find(d => d.id === 'esp32_pump_AA69E0');
    record('TC-HARDWARE-002', 'Genuine ESP32 Hardware Identification', !!realHardware,
      realHardware ? `Found real gateway: ${realHardware.id} (${realHardware.name}, MAC: ${realHardware.macAddress})` : 'Real hardware not found');

    // Test a completely fresh newly created account: must have EXACTLY 0 devices!
    const freshUserEmail = `fresh_user_${Date.now()}@hydropulse.io`;
    const freshReg = await request('/auth/register', 'POST', {
      name: 'Fresh User',
      email: freshUserEmail,
      password: 'FreshPassword123!'
    });
    const brandNewToken = freshReg.data?.data?.tokens?.accessToken;
    const freshDevRes = await request('/api/v1/devices', 'GET', null, {
      'Authorization': `Bearer ${brandNewToken}`
    });
    const freshDevCount = freshDevRes.data?.data?.length ?? -1;
    record('TC-HARDWARE-003', 'Zero Mock Hardware for Brand New Accounts', freshDevCount === 0,
      `Fresh account (${freshUserEmail}) devices count: ${freshDevCount} (Strictly 0 mock devices)`);

    // -------------------------------------------------------------------------
    // Phase 6: Similar IDs & Cross-Account Isolation Audit
    // -------------------------------------------------------------------------
    console.log('\n--- Phase 6: Similar IDs & Cross-Account Isolation Audit ---');

    // Test case normalization (Case insensitivity)
    const upperEmailLogin = await request('/auth/login', 'POST', {
      email: 'KARTHIKNATARAJ547@GMAIL.COM',
      password: targetPassword
    });
    record('TC-SIMILAR-001', 'Case-Insensitive Email Login Normalization', upperEmailLogin.status === 200,
      `HTTP ${upperEmailLogin.status} (UPPERCASE email correctly resolved to canonical lowercase)`);

    // Check all similar IDs in the database
    const allDbUsers = dbData.users;
    const similarKarthikUsers = allDbUsers.filter(u => u.email.toLowerCase().includes('karthik'));

    console.log(`\nFound ${similarKarthikUsers.length} accounts matching 'karthik':`);
    similarKarthikUsers.forEach((u, i) => {
      console.log(`  ${i+1}. Email: ${u.email} | ID: ${u.id} | Name: ${u.firstName} ${u.lastName} | Role: ${u.role}`);
    });

    // Test cross-account isolation:
    // Verify that karthikwzatco@gmail.com (usr_1788524453070_628) cannot see karthiknataraj547's devices
    const wzatcoDevRes = await request('/api/v1/devices?email=karthikwzatco@gmail.com', 'GET');
    const wzatcoDevices = wzatcoDevRes.data?.data || [];
    const leakCheck = wzatcoDevices.some(d => d.id === 'esp32_pump_AA69E0');
    record('TC-ISOLATION-001', 'Cross-Account Device Isolation', !leakCheck,
      `karthikwzatco devices: ${wzatcoDevices.length}, Contains karthiknataraj device: ${leakCheck}`);

    // Print summary table
    console.log('\n================================================================');
    console.log('                       AUDIT TEST SUMMARY                       ');
    console.log('================================================================');
    const total = testResults.length;
    const passed = testResults.filter(r => r.passed).length;
    const failed = total - passed;

    console.log(`Total Tests Executed : ${total}`);
    console.log(`Tests Passed         : ${passed}`);
    console.log(`Tests Failed         : ${failed}`);
    console.log(`Success Rate         : ${(passed / total * 100).toFixed(1)}%`);
    console.log('================================================================\n');

  } catch (err) {
    console.error('Audit suite fatal error:', err);
  } finally {
    server.close();
  }
});
