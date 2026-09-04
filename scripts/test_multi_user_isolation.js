/**
 * Verification Test: Multi-User Cloud Hardware Isolation
 */

const http = require('http');

function request(options, data) {
  return new Promise((resolve, reject) => {
    const req = http.request(options, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, data: JSON.parse(body) });
        } catch {
          resolve({ status: res.statusCode, data: body });
        }
      });
    });
    req.on('error', reject);
    if (data) req.write(typeof data === 'string' ? data : JSON.stringify(data));
    req.end();
  });
}

async function runTests() {
  console.log('=== Multi-User Cloud Hardware Isolation Test Suite ===\n');

  // 1. Unauthenticated /devices request
  const unauthRes = await request({
    hostname: 'localhost',
    port: 3001,
    path: '/devices',
    method: 'GET'
  });
  console.log('1. Unauthenticated /devices:');
  console.log('   Expected: [] | Actual:', unauthRes.data?.data);
  if (Array.isArray(unauthRes.data?.data) && unauthRes.data.data.length === 0) {
    console.log('   ✓ PASS: Unauthenticated users receive 0 devices.\n');
  } else {
    console.error('   ✗ FAIL: Leaked devices to unauthenticated caller!\n');
    process.exit(1);
  }

  // 2. User A: karthiknataraj547@gmail.com login & devices check
  const userARes = await request({
    hostname: 'localhost',
    port: 3001,
    path: '/api/v1/auth/login',
    method: 'POST',
    headers: { 'Content-Type': 'application/json' }
  }, { email: 'karthiknataraj547@gmail.com', password: 'Password123!' });

  const tokenA = userARes.data?.data?.tokens?.accessToken;
  console.log('2. User A (karthiknataraj547@gmail.com) Login:', tokenA ? '✓ SUCCESS' : '✗ FAILED');

  const devARes = await request({
    hostname: 'localhost',
    port: 3001,
    path: '/devices',
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${tokenA}`,
      'x-user-email': 'karthiknataraj547@gmail.com'
    }
  });
  console.log('   User A Devices count:', devARes.data?.data?.length);
  const devAIds = (devARes.data?.data || []).map(d => d.id);
  console.log('   User A Devices:', devAIds);
  if (devAIds.includes('esp32_pump_94B97E') && !devAIds.includes('esp32_pump_main')) {
    console.log('   ✓ PASS: User A sees their own hardware.\n');
  } else {
    console.error('   ✗ FAIL: User A devices mismatch!\n');
    process.exit(1);
  }

  // 3. User B: karthikwzatco@gmail.com register/login & devices check
  const userBReg = await request({
    hostname: 'localhost',
    port: 3001,
    path: '/api/v1/auth/register',
    method: 'POST',
    headers: { 'Content-Type': 'application/json' }
  }, {
    email: 'karthikwzatco@gmail.com',
    password: 'Password123!',
    firstName: 'Karthik',
    lastName: 'Wzatco'
  });

  const tokenB = userBReg.data?.data?.tokens?.accessToken;
  console.log('3. User B (karthikwzatco@gmail.com) Auth Token:', tokenB ? '✓ OBTAINED' : '✗ FAILED');

  // Clean up any previously created test devices for User B to ensure clean initial state
  const preCheckB = await request({
    hostname: 'localhost',
    port: 3001,
    path: '/devices',
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${tokenB}`,
      'x-user-email': 'karthikwzatco@gmail.com'
    }
  });
  for (const d of (preCheckB.data?.data || [])) {
    if (d.id === 'esp32_wzatco_farm_01') {
      await request({
        hostname: 'localhost',
        port: 3001,
        path: `/devices/${d.id}`,
        method: 'DELETE',
        headers: {
          'Authorization': `Bearer ${tokenB}`,
          'x-user-email': 'karthikwzatco@gmail.com'
        }
      });
    }
  }

  const devBRes = await request({
    hostname: 'localhost',
    port: 3001,
    path: '/devices',
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${tokenB}`,
      'x-user-email': 'karthikwzatco@gmail.com'
    }
  });
  console.log('   User B Initial Devices count:', devBRes.data?.data?.length);
  console.log('   User B Initial Devices:', devBRes.data?.data);
  if (Array.isArray(devBRes.data?.data) && devBRes.data.data.length === 0) {
    console.log('   ✓ PASS: User B initially has ZERO devices (no User A leakage!)\n');
  } else {
    console.error('   ✗ CRITICAL FAIL: User B can see User A hardware!\n');
    process.exit(1);
  }

  // 4. User B claims their own new hardware
  const claimB = await request({
    hostname: 'localhost',
    port: 3001,
    path: '/devices/claim',
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${tokenB}`,
      'x-user-email': 'karthikwzatco@gmail.com'
    }
  }, {
    deviceId: 'esp32_wzatco_farm_01',
    name: 'Wzatco Farm Pump Controller',
    macAddress: '24:6F:28:CC:11:22'
  });
  console.log('4. User B Claims Device:', claimB.status === 201 ? '✓ SUCCESS' : '✗ FAILED');

  // 5. User B re-checks devices
  const devBUpdated = await request({
    hostname: 'localhost',
    port: 3001,
    path: '/devices',
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${tokenB}`,
      'x-user-email': 'karthikwzatco@gmail.com'
    }
  });
  const devBIds = (devBUpdated.data?.data || []).map(d => d.id);
  console.log('5. User B Devices after claim:', devBIds);
  if (devBIds.length === 1 && devBIds[0] === 'esp32_wzatco_farm_01') {
    console.log('   ✓ PASS: User B sees only their newly claimed device.\n');
  } else {
    console.error('   ✗ FAIL: User B devices unexpected:', devBIds);
    process.exit(1);
  }

  // 6. User A re-checks devices to ensure User B device is NOT visible to User A
  const devAFinal = await request({
    hostname: 'localhost',
    port: 3001,
    path: '/devices',
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${tokenA}`,
      'x-user-email': 'karthiknataraj547@gmail.com'
    }
  });
  const devAFinalIds = (devAFinal.data?.data || []).map(d => d.id);
  console.log('6. User A Final Devices re-check:', devAFinalIds);
  if (devAFinalIds.includes('esp32_pump_94B97E') && !devAFinalIds.includes('esp32_wzatco_farm_01')) {
    console.log('   ✓ PASS: User A does NOT see User B device. Complete multi-tenant isolation!\n');
  } else {
    console.error('   ✗ FAIL: Cross-contamination detected in User A view!\n');
    process.exit(1);
  }

  // 7. Cleanup User B test device
  await request({
    hostname: 'localhost',
    port: 3001,
    path: '/devices/esp32_wzatco_farm_01',
    method: 'DELETE',
    headers: {
      'Authorization': `Bearer ${tokenB}`,
      'x-user-email': 'karthikwzatco@gmail.com'
    }
  });

  console.log('>>> ALL 6 MULTI-USER ISOLATION TESTS PASSED PERFECTLY! <<<');
  process.exit(0);
}

runTests().catch(err => {
  console.error('Test error:', err);
  process.exit(1);
});
