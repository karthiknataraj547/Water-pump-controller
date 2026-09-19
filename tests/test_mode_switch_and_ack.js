const http = require('http');
const mqtt = require('mqtt');
const { generateToken } = require('../api/middleware/auth_guard');

const BROKER_URL = 'mqtt://broker.emqx.io:1883';
const API_PORT = 4893;
const testDeviceId = 'esp32_pump_AA69E0';
const testEmail = 'wizard_user_1789759456766@hydropulse.io';
const validJwt = generateToken('usr_1789759456837_755', testEmail, 'ADMIN');

async function run() {
  console.log('=== MODE SWITCHING AND HARDWARE ACK RESOLUTION TEST ===\n');

  // 1. Start test API server
  const apiHandler = require('../api/index.js');
  const server = http.createServer((req, res) => apiHandler(req, res));
  await new Promise(r => server.listen(API_PORT, r));
  console.log(`[1/4] Test API Server running on port ${API_PORT}`);

  // 2. Connect MQTT client to listen for commands
  const client = mqtt.connect(BROKER_URL, {
    clientId: 'test_mode_listener_' + Date.now(),
    clean: true
  });
  await new Promise(r => client.on('connect', r));
  console.log('[2/4] Connected to EMQX MQTT Broker');

  const captured = [];
  client.on('message', (topic, payload) => {
    captured.push({ topic, msg: payload.toString() });
  });

  await new Promise((resolve, reject) => {
    client.subscribe(['pump/+/command', 'pump/command', 'waterpump/esp32/control'], (err) => {
      if (err) reject(err);
      else resolve();
    });
  });
  console.log('[2/4] Subscribed to command topics on EMQX MQTT Broker');
  await new Promise(r => setTimeout(r, 600));

  // 3. Test SET_MODE: MANUAL
  console.log('[3/4] Testing SET_MODE to MANUAL...');
  const resManual = await postJson('/command', {
    command: 'SET_MODE',
    action: 'SET_MODE',
    deviceId: testDeviceId,
    parameters: { mode: 'MANUAL' }
  });
  console.log('  -> Response status:', resManual.status, 'Mode:', resManual.data?.mode);
  if (resManual.data?.mode !== 'MANUAL') throw new Error(`Mode should be MANUAL, got: ${resManual.data?.mode}`);

  await new Promise(r => setTimeout(r, 600));

  // Test SET_MODE: AUTO
  console.log('  -> Testing SET_MODE to AUTO...');
  const resAuto = await postJson('/command', {
    command: 'SET_MODE',
    action: 'SET_MODE',
    deviceId: testDeviceId,
    parameters: { mode: 'AUTO' }
  });
  console.log('  -> Response status:', resAuto.status, 'Mode:', resAuto.data?.mode);
  if (resAuto.data?.mode !== 'AUTO') throw new Error(`Mode should be AUTO, got: ${resAuto.data?.mode}`);

  await new Promise(r => setTimeout(r, 600));

  // 4. Test START_PUMP auto-switching mode to MANUAL
  console.log('[4/4] Testing START_PUMP auto-transitions to MANUAL...');
  const resStart = await postJson('/command', {
    command: 'START_PUMP',
    action: 'START',
    deviceId: testDeviceId
  });
  console.log('  -> Response status:', resStart.status, 'PumpRunning:', resStart.data?.pumpRunning, 'Mode:', resStart.data?.mode);
  if (resStart.data?.pumpRunning !== true) throw new Error('Pump should be running');
  if (resStart.data?.mode !== 'MANUAL') throw new Error('Mode should auto-transition to MANUAL');

  // Wait 2.0s for MQTT packets to arrive
  await new Promise(r => setTimeout(r, 2000));
  console.log(`\n  -> Total MQTT command packets captured: ${captured.length}`);
  console.log('  -> Captured:', JSON.stringify(captured, null, 2));
  const hasManualMsg = captured.some(c => c.msg.includes('MANUAL'));
  const hasAutoMsg = captured.some(c => c.msg.includes('AUTO'));
  console.log(`  -> Has MANUAL broadcast: ${hasManualMsg}`);
  console.log(`  -> Has AUTO broadcast: ${hasAutoMsg}`);

  if (!hasManualMsg || !hasAutoMsg) {
    throw new Error('MQTT packets missing mode broadcasts');
  }

  client.end(true);
  server.close();
  console.log('\n=== ALL MODE SWITCHING AND ACTUATION CHECKS PASSED ===');
  process.exit(0);
}

function postJson(path, body) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body);
    const req = http.request({
      hostname: 'localhost',
      port: API_PORT,
      path,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(data),
        'Authorization': `Bearer ${validJwt}`
      }
    }, (res) => {
      let buf = '';
      res.on('data', d => buf += d);
      res.on('end', () => {
        try {
          resolve(JSON.parse(buf));
        } catch (_) {
          resolve({ status: res.statusCode, raw: buf });
        }
      });
    });
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

run().catch(e => {
  console.error('Test Failed:', e.message);
  process.exit(1);
});
