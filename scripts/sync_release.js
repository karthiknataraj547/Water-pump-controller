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
  path.join(rootDir, 'releases', 'HydroPulse_v2.3.2_build36.apk'),
  path.join(rootDir, 'releases', 'HydroPulse_WaterPumpController.apk'),
  path.join(rootDir, 'website', 'releases', 'HydroPulse_v2.3.2_build36.apk'),
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
  version: '2.3.2',
  build_number: 36,
  release_date: '2026-09-19',
  min_supported_version: '1.0.0',
  download_url: 'https://water-pump-controller.vercel.app/releases/HydroPulse_v2.3.2_build36.apk',
  website_url: 'https://water-pump-controller.vercel.app',
  sha256: sha256,
  title: 'HydroPulse v2.3.2 - Interactive Mode Toggle & Fast Command SLA',
  changelog: [
    'Interactive Mode Badges: Tapping the mode indicator on Dashboard and Tank Control screens now instantly switches between AUTO and MANUAL modes with haptic feedback.',
    'Zero-Lockout Pump Start: Starting the pump from the Pump Control screen automatically sets mode to MANUAL and actuates the motor with zero safety cutoff lockout.',
    'Fast-Path Hardware ACK SLA: Sub-second command acknowledgment matching exact commandId, raw fast-path, verified hardware state reflection, or cloud REST response.',
    'Dual-Channel Cloud Forwarding: Mode and actuation commands dispatch across both EMQX MQTT and cloud REST relay simultaneously, completely eliminating 5-second command timeouts.',
    'Firmware Safe Remote Start: Gateway automatically switches systemMode to MANUAL on user remote start, preventing sub-node disconnection cutoffs.'
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
