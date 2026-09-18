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
  path.join(rootDir, 'releases', 'HydroPulse_v2.2.9_build33.apk'),
  path.join(rootDir, 'releases', 'HydroPulse_WaterPumpController.apk'),
  path.join(rootDir, 'website', 'releases', 'HydroPulse_v2.2.9_build33.apk'),
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
  version: '2.2.9',
  build_number: 33,
  release_date: '2026-09-19',
  min_supported_version: '1.0.0',
  download_url: 'https://water-pump-controller.vercel.app/releases/HydroPulse_v2.2.9_build33.apk',
  website_url: 'https://water-pump-controller.vercel.app',
  sha256: sha256,
  title: 'HydroPulse v2.2.9 - Hardware Auto-Provisioning, Cloud Gateway Pairing & Fast OTA Update Engine',
  changelog: [
    'Hardware Provisioning & Cloud Registration: Resolved ESP32 BLE provisioning post-registration bug where newly provisioned hardware failed to register on the cloud backend and appear on user accounts.',
    'Multi-Tenant Hardware Ownership: Real-time user-hardware claiming with seamless state sync between Flutter mobile app and web console.',
    'Direct In-App OTA Update Engine: Instant multi-mirror package delivery (Vercel Edge CDN, GitHub Raw, and direct cloud API) with real-time HiveMQ MQTT broadcast notifications.',
    'Unpaired State System Access: Complete access to System Settings, App Update Engine, and App Info diagnostics prior to hardware pairing.',
    'Industrial Console & 3D Reservoir Telemetry: Engineering-grade Linear/Tesla Energy obsidian interface with calibrated 0-5000L volumetric tracking.'
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
