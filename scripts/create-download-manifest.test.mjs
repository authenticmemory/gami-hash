import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

test('release assembly checks both Windows executables and requires Linux signature files', () => {
  const root = mkdtempSync(join(tmpdir(), 'hash-manifest-test-'));
  const run = tag => execFileSync(process.execPath, ['scripts/create-download-manifest.mjs', root], { env: { ...process.env, GITHUB_REF_NAME: tag }, stdio: 'pipe' });
  try {
    for (const platform of ['windows', 'linux']) {
      const dir = join(root, platform, 'bin');
      mkdirSync(dir, { recursive: true });
      const names = platform === 'windows' ? ['Authentic Memory Hashing Tool-amd64-installer.exe', 'gami-hash.exe'] : ['gami-hash-linux-amd64.tar.gz'];
      const lines = names.map(name => {
        writeFileSync(join(dir, name), name);
        return `${createHash('sha256').update(name).digest('hex')}  ${name}`;
      });
      const checksum = platform === 'windows' ? 'SHA256SUMS-windows.txt' : `${names[0]}.sha256`;
      writeFileSync(join(dir, checksum), lines.join('\n') + '\n');
      if (platform === 'linux') for (const name of [names[0], checksum]) writeFileSync(join(dir, `${name}.asc`), 'fixture signature; cryptographic verification occurs in signing jobs');
    }
    run('v1.0.0');
    const manifest = JSON.parse(readFileSync(join(root, 'downloads/gami-hash-downloads.json')));
    assert.equal(manifest.artifacts.length, 2);
    assert.equal(manifest.artifacts[0].archive, 'gami-hash-windows-amd64-installer.exe');
    const installer = manifest.artifacts[0].files.find(f => f.name === manifest.artifacts[0].archive);
    assert.match(readFileSync(join(root, 'downloads/SHA256SUMS-windows.txt'), 'utf8'), new RegExp(`${installer.sha256}  gami-hash-windows-amd64-installer.exe`));
    assert.throws(() => run('test-v1.0.0'));
    writeFileSync(join(root, 'windows/bin/gami-hash.exe'), 'tampered');
    assert.throws(() => run('v1.0.0'), /Checksum mismatch/);
    writeFileSync(join(root, 'windows/bin/gami-hash.exe'), 'gami-hash.exe');
    rmSync(join(root, 'linux/bin/gami-hash-linux-amd64.tar.gz.asc'));
    assert.throws(() => run('v1.0.0'));
  } finally { rmSync(root, { recursive: true, force: true }); }
});
