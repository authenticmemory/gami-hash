import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const [root = 'release'] = process.argv.slice(2);
const tag = process.env.GITHUB_REF_NAME;
if (!/^v\d+\.\d+\.\d+$/.test(tag || '')) throw new Error('Expected a stable vX.Y.Z release tag');
const output = join(root, 'downloads');
mkdirSync(output, { recursive: true });
const artifacts = [];
for (const platform of ['windows-x64', 'linux-x64', 'linux-x64-gui']) {
  const linux = platform.startsWith('linux-');
  const gui = platform === 'linux-x64-gui';
  const source = gui ? join(root, 'linux-gui') : join(root, linux ? 'linux' : 'windows', 'bin');
  // GitHub normalizes spaces in uploaded filenames. Publish a stable ASCII name
  // and update its checksum entry without changing the signed executable bytes.
  const originalInstaller = 'Authentic Memory Hashing Tool-amd64-installer.exe';
  const archive = gui ? 'gami-hash-linux-amd64-gui.deb' : linux ? 'gami-hash-linux-amd64.tar.gz' : 'gami-hash-windows-amd64-installer.exe';
  const checksum = gui ? 'SHA256SUMS-linux-gui.txt' : linux ? `${archive}.sha256` : 'SHA256SUMS-windows.txt';
  const signature = linux ? `${archive}.asc` : null;
  const names = linux ? [archive, checksum, signature, `${checksum}.asc`] : [archive, 'gami-hash.exe', checksum];
  let sourceRpm;
  if (gui) {
    sourceRpm = readdirSync(source).find(name => /^gami-hash-.*\.x86_64\.rpm$/.test(name));
    if (!sourceRpm) throw new Error('Missing Linux GUI RPM');
    names.push('gami-hash-linux-amd64-gui.tar.gz', 'gami-hash-linux-amd64-gui.tar.gz.asc', 'gami-hash-linux-amd64-gui.rpm', `${sourceRpm}.asc`);
    writeFileSync(join(output, 'gami-hash-linux-amd64-gui.rpm'), readFileSync(join(source, sourceRpm)));
  }
  const checksums = readFileSync(join(source, checksum), 'utf8').split(/\r?\n/);
  const files = names.map(name => {
    const sourceName = !linux && name === archive ? originalInstaller : gui && name === 'gami-hash-linux-amd64-gui.rpm' ? sourceRpm : gui && name === 'gami-hash-linux-amd64-gui.rpm.asc' ? `${sourceRpm}.asc` : name;
    let data = readFileSync(join(source, sourceName));
    if (!linux && name === checksum) data = Buffer.from(data.toString('utf8').replace(originalInstaller, archive));
    if (!data.length) throw new Error(`Empty release file: ${name}`);
    const sha256 = createHash('sha256').update(data).digest('hex');
    if ((name.endsWith('.exe') || name.endsWith('.tar.gz') || name.endsWith('.deb')) && !checksums.includes(`${sha256}  ${sourceName}`)) throw new Error(`Checksum mismatch: ${name}`);
    writeFileSync(join(output, name), data);
    return { name, sha256 };
  });
  artifacts.push({ platform, archive, checksum, signature, files });
}
writeFileSync(join(output, 'gami-hash-downloads.json'), JSON.stringify({ schema: 1, tag, artifacts }, null, 2));
