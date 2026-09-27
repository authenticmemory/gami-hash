import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const [root = 'release'] = process.argv.slice(2);
const tag = process.env.GITHUB_REF_NAME;
if (!/^v\d+\.\d+\.\d+$/.test(tag || '')) throw new Error('Expected a stable vX.Y.Z release tag');
const output = join(root, 'downloads');
mkdirSync(output, { recursive: true });
const artifacts = [];
for (const platform of ['windows-x64', 'linux-x64']) {
  const linux = platform === 'linux-x64';
  const source = join(root, linux ? 'linux' : 'windows', 'bin');
  // GitHub normalizes spaces in uploaded filenames. Publish a stable ASCII name
  // and update its checksum entry without changing the signed executable bytes.
  const originalInstaller = 'Authentic Memory Hashing Tool-amd64-installer.exe';
  const archive = linux ? 'gami-hash-linux-amd64.tar.gz' : 'gami-hash-windows-amd64-installer.exe';
  const checksum = linux ? `${archive}.sha256` : 'SHA256SUMS-windows.txt';
  const signature = linux ? `${archive}.asc` : null;
  const names = linux ? [archive, checksum, signature, `${checksum}.asc`] : [archive, 'gami-hash.exe', checksum];
  const checksums = readFileSync(join(source, checksum), 'utf8').split(/\r?\n/);
  const files = names.map(name => {
    const sourceName = !linux && name === archive ? originalInstaller : name;
    let data = readFileSync(join(source, sourceName));
    if (!linux && name === checksum) data = Buffer.from(data.toString('utf8').replace(originalInstaller, archive));
    if (!data.length) throw new Error(`Empty release file: ${name}`);
    const sha256 = createHash('sha256').update(data).digest('hex');
    if ((name.endsWith('.exe') || name.endsWith('.tar.gz')) && !checksums.includes(`${sha256}  ${sourceName}`)) throw new Error(`Checksum mismatch: ${name}`);
    writeFileSync(join(output, name), data);
    return { name, sha256 };
  });
  artifacts.push({ platform, archive, checksum, signature, files });
}
writeFileSync(join(output, 'gami-hash-downloads.json'), JSON.stringify({ schema: 1, tag, artifacts }, null, 2));
