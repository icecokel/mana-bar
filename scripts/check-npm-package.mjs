import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { accessSync, constants, mkdirSync, readFileSync, rmSync } from 'node:fs';
import { resolve } from 'node:path';

const manifest = JSON.parse(readFileSync('package.json', 'utf8'));
const archive = resolve('.build', `${manifest.name.replace('@', '').replace('/', '-')}-${manifest.version}.tgz`);
const entries = execFileSync('/usr/bin/tar', ['-tzf', archive], { encoding: 'utf8' }).trim().split('\n');
for (const entry of entries) {
  assert(!entry.split('/').includes('..'), `Unexpected archive path: ${entry}`);
  assert(/^package\/(?:app\/ManaBar\.app\/|bin\/mana-bar\.mjs$|package\.json$|README\.md$|LICENSE$|THIRD_PARTY_NOTICES\.txt$)/.test(entry),
    `Unexpected package file: ${entry}`);
  assert(!/(?:^|\/)(?:\.manabar-signing|\.build|\.npmrc|password)(?:\/|$)|\.(?:p12|pem|keychain-db|log)$/.test(entry),
    `Private development file in package: ${entry}`);
}
for (const required of [
  'bin/mana-bar.mjs', 'README.md', 'LICENSE', 'THIRD_PARTY_NOTICES.txt',
  'app/ManaBar.app/Contents/MacOS/ManaBar',
  'app/ManaBar.app/Contents/Resources/Fonts/OFL-Cinzel.txt',
  'app/ManaBar.app/Contents/Resources/Fonts/OFL-Pretendard.txt',
  'app/ManaBar.app/Contents/_CodeSignature/CodeResources',
]) assert(entries.includes(`package/${required}`), `Missing package file: ${required}`);

const destination = resolve('.build/npm-package-check');
rmSync(destination, { recursive: true, force: true });
mkdirSync(destination, { recursive: true });
execFileSync('/usr/bin/tar', ['-xzf', archive, '-C', destination]);
const bundle = resolve(destination, 'package/app/ManaBar.app');
const packedManifest = JSON.parse(readFileSync(resolve(destination, 'package/package.json'), 'utf8'));
assert.equal(packedManifest.name, manifest.name);
assert.equal(packedManifest.version, manifest.version);
assert.equal(packedManifest.license, 'MIT');
assert.deepEqual(packedManifest.os, ['darwin']);
assert.deepEqual(packedManifest.cpu, ['arm64']);
assert(!packedManifest.private && !packedManifest.scripts, 'Publish only the prebuilt package, without development scripts.');
const executable = resolve(bundle, 'Contents/MacOS/ManaBar');
const cli = resolve(destination, 'package/bin/mana-bar.mjs');
accessSync(executable, constants.X_OK);
accessSync(cli, constants.X_OK);
assert.equal(execFileSync('/usr/bin/lipo', ['-archs', executable], { encoding: 'utf8' }).trim(), 'arm64');
execFileSync('/usr/bin/codesign', ['--verify', '--strict', bundle]);
assert.equal(execFileSync(process.execPath, [cli, '--version'], { encoding: 'utf8' }).trim(), manifest.version);
execFileSync(executable, ['--render-preview', resolve('.build/npm-package-preview.png')]);
console.log(`Verified ${manifest.name}@${manifest.version}: package contents, arm64 app, permissions, signature, CLI, and bundled resources.`);
