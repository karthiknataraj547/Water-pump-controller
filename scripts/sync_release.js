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
  path.join(rootDir, 'releases', 'HydroPulse_v2.2.3_build27.apk'),
  path.join(rootDir, 'releases', 'HydroPulse_WaterPumpController.apk'),
  path.join(rootDir, 'website', 'releases', 'HydroPulse_v2.2.3_build27.apk'),
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
  version: '2.2.3',
  build_number: 27,
  release_date: '2026-09-12',
  min_supported_version: '1.0.0',
  download_url: 'https://water-pump-controller.vercel.app/releases/HydroPulse_v2.2.3_build27.apk',
  website_url: 'https://water-pump-controller.vercel.app',
  sha256: sha256,
  title: 'HydroPulse v2.2.3 - Instant Launch & Skia Pipeline Fix',
  changelog: [
    'Fixed Black/Blank Screen: Re-architected startup to synchronous execution with post-frame background auth resolution.',
    'Eliminated KeyStore Deadlock: Protected Flutter secure storage initialization against blocking hangs.',
    'ColorOS/Android 14 Skia Mode: Disabled Impeller Vulkan presentation to eliminate vendor-specific black swapchains.',
    'Sideload Installation Conflict Fix: Standardized release keystore configuration across all distribution channels.',
    'Zero-Delay First Frame: Mounts full HydroPulse theme and Login UI in under 16ms.'
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
