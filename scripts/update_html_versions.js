const fs = require('fs');
const path = require('path');

const rootDir = path.resolve(__dirname, '..');
const filesToUpdate = [
  path.join(rootDir, 'app.html'),
  path.join(rootDir, 'website', 'app.html')
];

for (const filePath of filesToUpdate) {
  if (!fs.existsSync(filePath)) {
    console.warn('File not found:', filePath);
    continue;
  }
  let content = fs.readFileSync(filePath, 'utf8');

  // Replace version numbers and APK filenames
  content = content.replace(/HydroPulse_v2\.3\.1_build35\.apk/g, 'HydroPulse_v2.3.2_build36.apk');
  content = content.replace(/HydroPulse v2\.3\.1 \(Build 35\)/g, 'HydroPulse v2.3.2 (Build 36)');
  content = content.replace(/v2\.3\.1 \(Build 35\)/g, 'v2.3.2 (Build 36)');
  content = content.replace(/v2\.3\.1 • Build 35/g, 'v2.3.2 • Build 36');
  content = content.replace(/System Console v2\.3\.1/g, 'System Console v2.3.2');
  content = content.replace(/OTA ENGINE v2\.3\.1/g, 'OTA ENGINE v2.3.2');
  content = content.replace(/sidebar-update-chip" style="margin-left: auto; font-size: 9px; padding: 2px 6px;">v2\.3\.1<\/span>/g, 'sidebar-update-chip" style="margin-left: auto; font-size: 9px; padding: 2px 6px;">v2.3.2</span>');
  content = content.replace(/Download Android APK v2\.3\.1/g, 'Download Android APK v2.3.2');
  content = content.replace(/Download APK \(v2\.3\.1\)/g, 'Download APK (v2.3.2)');
  content = content.replace(/Download APK v2\.3\.1/g, 'Download APK v2.3.2');
  content = content.replace(/What's New in v2\.3\.1 \(Build 35\):/g, "What's New in v2.3.2 (Build 36):");

  fs.writeFileSync(filePath, content, 'utf8');
  console.log('Updated version references in:', filePath);
}
