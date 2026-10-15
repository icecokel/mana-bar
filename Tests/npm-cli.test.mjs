import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const cli = new URL('../bin/mana-bar.mjs', import.meta.url);
const app = fileURLToPath(new URL('../app/ManaBar.app', import.meta.url));
const compatible = `
  Object.defineProperty(process, 'platform', { value: 'darwin' });
  Object.defineProperty(process, 'arch', { value: 'arm64' });
  require('node:os').release = () => '22.0.0';
`;

function invoke(args = [], setup = '') {
  const script = `
    import { createRequire, syncBuiltinESMExports } from 'node:module';
    const require = createRequire(import.meta.url);
    ${setup}
    syncBuiltinESMExports();
    process.argv = [process.execPath, ${JSON.stringify(fileURLToPath(cli))}, ...${JSON.stringify(args)}];
    await import(${JSON.stringify(cli.href)});
  `;
  return spawnSync(process.execPath, ['--input-type=module', '--eval', script], { encoding: 'utf8' });
}

test('help and package version work without launching an app on unsupported platforms', () => {
  const unsupported = `Object.defineProperty(process, 'platform', { value: 'linux' });`;
  const help = invoke(['--help'], unsupported);
  assert.equal(help.status, 0, help.stderr);
  assert.match(help.stdout, /Usage: mana-bar/);
  const version = invoke(['--version'], unsupported);
  const metadata = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
  assert.equal(version.status, 0, version.stderr);
  assert.equal(version.stdout.trim(), metadata.version);
});

test('unknown arguments fail before launching an app', () => {
  const result = invoke(['--unknown']);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Unknown argument/);
});

test('unsupported platform, architecture, and macOS versions fail', () => {
  for (const [setup, message] of [
    [`Object.defineProperty(process, 'platform', { value: 'linux' });`, /requires macOS/],
    [compatible + `Object.defineProperty(process, 'arch', { value: 'x64' });`, /arm64 Node.js/],
    [compatible + `require('node:os').release = () => '21.6.0';`, /macOS 13 or later/],
  ]) {
    const result = invoke([], setup);
    assert.equal(result.status, 1, result.stderr);
    assert.match(result.stderr, message);
  }
});

test('missing bundle fails before calling open', () => {
  const result = invoke([], compatible + `
    require('node:fs').accessSync = () => { throw new Error('missing fixture'); };
    require('node:child_process').spawnSync = () => { throw new Error('must not launch'); };
  `);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /bundled ManaBar app is missing/);
  assert.doesNotMatch(result.stderr, /must not launch/);
});

test('open errors return failure without launching a real app', () => {
  for (const result of [
    `{ status: 1 }`,
    `{ status: null, signal: 'SIGTERM' }`,
    `{ error: new Error('fixture open failure') }`,
  ]) {
    const failure = invoke([], compatible + `
      require('node:fs').accessSync = () => {};
      require('node:child_process').spawnSync = () => (${result});
    `);
    assert.equal(failure.status, 1);
    assert.match(failure.stderr, /Could not open ManaBar/);
  }
});

test('launcher uses the packaged app and argument array without a shell', () => {
  const result = invoke([], compatible + `
    require('node:fs').accessSync = () => {};
    require('node:child_process').spawnSync = (command, args, options) => {
      console.log(JSON.stringify({ command, args, options }));
      return { status: 0 };
    };
  `);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout), {
    command: '/usr/bin/open',
    args: ['-a', app, '--args', '--show-panel'],
    options: { stdio: 'inherit' },
  });
});
