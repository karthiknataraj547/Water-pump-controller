const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const rootDir = path.resolve(__dirname, '..');
const sourceApk = path.join(rootDir, 'frontend', 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');

if (!fs.existsSync(sourceApk)) {
  console.error('Source APK not found at:', sourceApk);
  process.exit(1);
}

const stats = fs.statSync(sourceApk);
const fileBuffer = fs.readFileSync(sourceApk);
const sha256 = crypto.createHash('sha256').update(fileBuffer).digest('hex');

console.log('Source APK Size:', stats.size, 'bytes');
console.log('Source APK SHA-256:', sha256);

const targetPaths = [
  path.join(rootDir, 'releases', 'HydroPulse_v2.3.1_build35.apk'),
  path.join(rootDir, 'releases', 'HydroPulse_WaterPumpController.apk'),
  path.join(rootDir, 'website', 'releases', 'HydroPulse_v2.3.1_build35.apk'),
  path.join(rootDir, 'website', 'releases', 'HydroPulse_WaterPumpController.apk')
];

targetPaths.forEach((dest) => {
  const dir = path.dirname(dest);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  fs.copyFileSync(sourceApk, dest);
  console.log('Copied to:', dest);
});

// Update version.json manifests
const versionManifest = {
  version: '2.3.1',
  build_number: 35,
  release_date: '2026-09-19',
  min_supported_version: '1.0.0',
  download_url: 'https://water-pump-controller.vercel.app/releases/HydroPulse_v2.3.1_build35.apk',
  website_url: 'https://water-pump-controller.vercel.app',
  sha256: sha256,
  title: 'HydroPulse v2.3.1 - Zero-Lockout Pump Control & Manual Override Actuation',
  changelog: [
    'Zero-Lockout Manual Actuation: Starting or toggling the pump immediately transitions system to MANUAL mode without getting blocked by AUTO mode safety deadlocks.',
    'Permissive Command Dispatch: Removed artificial offline UI blockers, allowing dual-channel command transmission (EMQX MQTT + REST relay) with 5-second hardware ACK SLA.',
    'Backend REST Relay Forwarding: Cloud /command endpoint now automatically forwards actuation commands to EMQX MQTT topics without offline rejection.',
    'Firmware Manual Override: ESP32 Gateway automatically switches systemMode to MANUAL on explicit remote start, preventing sub-node disconnection cutoffs.',
    'Offline Queueing & Multi-Topic Broadcast: Commands enqueued during brief network changes flush instantly upon broker connection.'
  ],
  is_critical: false,
  updatedAt: new Date().toISOString(),
  file_size: stats.size
};

const manifestFiles = [
  path.join(rootDir, 'version.json'),
  path.join(rootDir, 'website', 'version.json'),
  path.join(rootDir, 'website', 'api', 'version.json'),
  path.join(rootDir, 'api', 'version.json')
];

manifestFiles.forEach((mPath) => {
  const dir = path.dirname(mPath);
  if (fs.existsSync(dir)) {
    fs.writeFileSync(mPath, JSON.stringify(versionManifest, null, 4), 'utf8');
    console.log('Updated manifest:', mPath);
  }
});

console.log('\nRelease synchronization completed successfully!');
