/**
 * HydroPulse OTA Release Update Broadcaster
 * Broadcasts version.json manifest over Cloud MQTT brokers
 * with QoS 1 and Retain flag to trigger in-app updates instantly across all client apps.
 */

const fs = require('fs');
const path = require('path');
const mqtt = require(path.join(__dirname, '..', 'backend', 'node_modules', 'mqtt'));

const versionPath = path.join(__dirname, '..', 'version.json');
const versionData = JSON.parse(fs.readFileSync(versionPath, 'utf8'));

const TOPICS = [
  'hydropulse/app/update',
  'hydropulse/ota',
  'pump/app/update',
  'waterpump/app/update'
];

const BROKERS = [
  { url: 'mqtt://broker.emqx.io:1883', name: 'EMQX Cloud' },
  { url: 'mqtt://broker.hivemq.com:1883', name: 'HiveMQ Cloud' },
  { url: 'mqtt://test.mosquitto.org:1883', name: 'Mosquitto Public' }
];

const payloadString = JSON.stringify(versionData);

console.log('=== HydroPulse In-App OTA Update Broadcaster ===');
console.log(`Target Version: v${versionData.version} (Build ${versionData.build_number})`);
console.log(`Payload Size: ${payloadString.length} bytes`);
console.log(`Target Topics: ${TOPICS.join(', ')}`);

async function broadcastToBroker(broker) {
  return new Promise((resolve) => {
    console.log(`\nConnecting to ${broker.name} (${broker.url})...`);
    const client = mqtt.connect(broker.url, {
      clientId: `hydropulse_ota_publisher_${Date.now()}_${Math.floor(Math.random() * 1000)}`,
      clean: true,
      connectTimeout: 8000
    });

    const timeout = setTimeout(() => {
      console.warn(`[Timeout] Connection to ${broker.name} timed out after 8s.`);
      client.end(true);
      resolve({ broker: broker.name, success: false, reason: 'timeout' });
    }, 10000);

    client.on('connect', () => {
      console.log(`[Connected] ${broker.name}. Publishing retained update messages...`);
      let pending = TOPICS.length;

      TOPICS.forEach((topic) => {
        client.publish(topic, payloadString, { qos: 1, retain: true }, (err) => {
          if (err) {
            console.error(`[Error] Failed to publish to ${topic} on ${broker.name}:`, err.message);
          } else {
            console.log(`[Success] Published to ${topic} on ${broker.name} (QoS 1, Retained)`);
          }
          pending--;
          if (pending === 0) {
            clearTimeout(timeout);
            setTimeout(() => {
              client.end(false, () => {
                resolve({ broker: broker.name, success: true });
              });
            }, 500);
          }
        });
      });
    });

    client.on('error', (err) => {
      console.error(`[Error] ${broker.name} connection error:`, err.message);
      clearTimeout(timeout);
      client.end(true);
      resolve({ broker: broker.name, success: false, reason: err.message });
    });
  });
}

async function run() {
  const results = [];
  for (const broker of BROKERS) {
    const res = await broadcastToBroker(broker);
    results.push(res);
  }

  console.log('\n=== Broadcast Summary ===');
  results.forEach(r => {
    console.log(`- ${r.broker}: ${r.success ? 'PUBLISHED SUCCESSFULLY' : 'FAILED (' + r.reason + ')'}`);
  });
  console.log('\nOTA Update broadcast complete.');
  process.exit(0);
}

run();
