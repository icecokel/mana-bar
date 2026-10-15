#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build.sh
staging_directory="$PWD/.build/npm-package"
rm -rf "$staging_directory"
mkdir -p "$staging_directory/bin" "$staging_directory/app"
cp bin/mana-bar.mjs "$staging_directory/bin/"
chmod 755 "$staging_directory/bin/mana-bar.mjs"
/usr/bin/ditto .build/ManaBar.app "$staging_directory/app/ManaBar.app"
cp scripts/npm-README.md "$staging_directory/README.md"
cp Assets/CREDITS.txt "$staging_directory/THIRD_PARTY_NOTICES.txt"
if [ -f LICENSE ]; then
  cp LICENSE "$staging_directory/LICENSE"
fi

node --input-type=module <<'JS'
import { readFileSync, writeFileSync } from 'node:fs';
const manifest = JSON.parse(readFileSync('package.json', 'utf8'));
// Consumers receive a prebuilt app and never run the development scripts.
delete manifest.scripts;
delete manifest.private;
writeFileSync('.build/npm-package/package.json', JSON.stringify(manifest, null, 2) + '\n');
JS

npm pack "$staging_directory" --pack-destination "$PWD/.build" --ignore-scripts
node scripts/check-npm-package.mjs
