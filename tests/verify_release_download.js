const fs = require('fs');
const path = require('path');
const http = require('http');
const crypto = require('crypto');

const rootDir = path.resolve(__dirname, '..');
const expectedSha = '1bdbebbd702b7fc2bd359f87234e39d9ec5e836f35a81ee1618892d8053b53e8';
const expectedSize = 58427184;

const files = [
  path.join(rootDir, 'releases', 'HydroPulse_v2.2.8_build32.apk'),
  path.join(rootDir, 'releases', 'HydroPulse_WaterPumpController.apk'),
  path.join(rootDir, 'website', 'releases', 'HydroPulse_v2.2.8_build32.apk'),
  path.join(rootDir, 'website', 'releases', 'HydroPulse_WaterPumpController.apk')
];

console.log('=== Checking Local Release Files ===');
for (const f of files) {
  if (!fs.existsSync(f)) throw new Error('Missing file: ' + f);
  const stats = fs.statSync(f);
  if (stats.size !== expectedSize) throw new Error('Size mismatch for ' + f + ': ' + stats.size);
  const hash = crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
  if (hash !== expectedSha) throw new Error('SHA-256 mismatch for ' + f + ': ' + hash);
  console.log('PASS: ' + path.basename(f) + ' (' + (stats.size / 1024 / 1024).toFixed(2) + ' MB, SHA verified)');
}

console.log('\n=== Testing HTTP Download Stream ===');
const server = http.createServer((req, res) => {
  const relPath = req.url.split('?')[0].replace(/^\//, '');
  const filePath = path.join(rootDir, 'website', relPath);
  if (!fs.existsSync(filePath)) {
    res.writeHead(404);
    return res.end('Not found: ' + filePath);
  }
  const stat = fs.statSync(filePath);
  res.writeHead(200, {
    'Content-Type': 'application/vnd.android.package-archive',
    'Content-Length': stat.size,
    'Content-Disposition': 'attachment; filename="HydroPulse_v2.2.8_build32.apk"'
  });
  fs.createReadStream(filePath).pipe(res);
});

server.listen(4892, () => {
  console.log('Test Server listening on http://localhost:4892');
  http.get('http://localhost:4892/releases/HydroPulse_v2.2.8_build32.apk', (res) => {
    console.log('HTTP Status:', res.statusCode);
    console.log('Content-Type:', res.headers['content-type']);
    console.log('Content-Length:', res.headers['content-length']);

    const hashStream = crypto.createHash('sha256');
    let totalBytes = 0;

    res.on('data', (chunk) => {
      totalBytes += chunk.length;
      hashStream.update(chunk);
    });

    res.on('end', () => {
      const downloadedHash = hashStream.digest('hex');
      console.log('Total Downloaded Bytes:', totalBytes);
      console.log('Downloaded Hash:', downloadedHash);

      if (totalBytes !== expectedSize) {
        console.error('FAIL: Size mismatch!');
        process.exit(1);
      }
      if (downloadedHash !== expectedSha) {
        console.error('FAIL: SHA mismatch!');
        process.exit(1);
      }
      console.log('\nSUCCESS: HTTP APK Download verified with 100% data integrity!');
      server.close();
      process.exit(0);
    });
  }).on('error', (e) => {
    console.error(e);
    server.close();
    process.exit(1);
  });
});
