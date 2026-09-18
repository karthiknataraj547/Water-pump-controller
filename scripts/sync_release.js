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
  path.join(rootDir, 'releases', 'HydroPulse_v2.2.7_build31.apk'),
  path.join(rootDir, 'releases', 'HydroPulse_WaterPumpController.apk'),
  path.join(rootDir, 'website', 'releases', 'HydroPulse_v2.2.7_build31.apk'),
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
  version: '2.2.7',
  build_number: 31,
  release_date: '2026-09-18',
  min_supported_version: '1.0.0',
  download_url: 'https://water-pump-controller.vercel.app/releases/HydroPulse_v2.2.7_build31.apk',
  website_url: 'https://water-pump-controller.vercel.app',
  sha256: sha256,
  title: 'HydroPulse v2.2.7 - Security Architecture, Multi-Tenant Gateway & Resilient Provisioning',
  changelog: [
    'Hardware Provisioning & Cloud Auto-Sync: Fixed post-provisioning hardware discovery and multi-tenant binding. Added instant 1-click Quick-Link and manual ESP32 AA69E0 gateway pairing with persistent user account ownership.',
    'Realistic IoT Online/Offline SLA: Upgraded heartbeat threshold to robust 30s active / 60s stale timing, eliminating false offline flapping and network latency jitter.',
    'Modular Backend Security Middleware Pipeline: Embedded Helmet HTTP security headers (nosniff, frameguard, strict-CSP), recursive prototype pollution defense, XSS payload neutralization, and constant-time HMAC-SHA256 JWT auth guard.',
    'Tiered Rate Limiter: Implemented sliding-window rate limiting for authentication brute-force defense (10 attempts/5m), hardware claim throttling, and pump actuator control protection with standard Retry-After headers.',
    'Complete Industrial UI Overhaul: Engineering-grade Linear and Tesla Energy-inspired aesthetic with true obsidian deep slate (#090D14) theme and crisp semantic status accents.',
    'Precision Architectural Reservoir: Calibrated cross-section fluid visualizer with 0-5000L volumetric markings, auto-stop (95%) and auto-start (25%) limits, and calm fluid meniscus.',
    'Network Signal Flow Topology: Live Wi-Fi RSSI meter and 3D spatial radio network topology stage with zero-flicker node tracking.'
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
