#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { accessSync, constants, readFileSync, realpathSync } from 'node:fs';
import { release } from 'node:os';
import { fileURLToPath } from 'node:url';

export function run(args = process.argv.slice(2)) {
  if (args.length === 1 && args[0] === '--help') {
    console.log('Usage: mana-bar [--help | --version]\n\nOpen ManaBar from this npm package. Requires Apple Silicon and macOS 13 or later.');
    return;
  }
  if (args.length === 1 && args[0] === '--version') {
    const metadata = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
    console.log(metadata.version);
    return;
  }
  if (args.length) throw new Error('Unknown argument. Run mana-bar --help for usage.');
  if (process.platform !== 'darwin') throw new Error('ManaBar requires macOS 13 or later on Apple Silicon.');
  if (process.arch !== 'arm64') {
    throw new Error('ManaBar requires Apple Silicon and arm64 Node.js. Intel and Node.js running under Rosetta are unsupported.');
  }
  if (!(Number(release().split('.')[0]) >= 22)) throw new Error('ManaBar requires macOS 13 or later.');

  const app = fileURLToPath(new URL('../app/ManaBar.app', import.meta.url));
  try {
    accessSync(`${app}/Contents/MacOS/ManaBar`, constants.X_OK);
  } catch {
    throw new Error('The bundled ManaBar app is missing or is not executable. Reinstall this npm package.');
  }
  const result = spawnSync('/usr/bin/open', ['-a', app, '--args', '--show-panel'], { stdio: 'inherit' });
  if (result.error) throw new Error(`Could not open ManaBar: ${result.error.message}`);
  if (result.status !== 0) throw new Error(`Could not open ManaBar (open ${result.signal ? `signal ${result.signal}` : `exit ${result.status}`}).`);
}

if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url))) {
  try {
    run();
  } catch (error) {
    console.error(`ManaBar: ${error.message}`);
    process.exitCode = 1;
  }
}
