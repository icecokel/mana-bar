#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
umask 077
test_directory="$PWD/.build/signing-check-$$"
mkdir -p "$test_directory" .build/module-cache
/usr/bin/security list-keychains -d user > "$test_directory/search-before"

for remaining_file in password manabar-signing.keychain-db; do
  partial_directory="$test_directory/partial-$remaining_file"
  mkdir -p "$partial_directory/scripts" "$partial_directory/.manabar-signing"
  cp scripts/sign.sh "$partial_directory/scripts/"
  printf 'preserve-existing-signing-state\n' > "$partial_directory/.manabar-signing/$remaining_file"
  if "$partial_directory/scripts/sign.sh" unused > "$partial_directory/result" 2>&1; then
    printf 'Incomplete signing state was overwritten.\n' >&2
    exit 1
  fi
  /usr/bin/grep -q 'Incomplete signing identity' "$partial_directory/result"
  test "$(cat "$partial_directory/.manabar-signing/$remaining_file")" = 'preserve-existing-signing-state'
done

swiftc -swift-version 6 -module-cache-path .build/module-cache -framework Security \
  Tests/SigningProbe/main.swift -o "$test_directory/Probe"
./scripts/sign.sh "$test_directory/Probe" app.manabar.signing-check
/usr/bin/codesign -d -r- "$test_directory/Probe" > "$test_directory/first-signature" 2>&1
requirement=$(sed -n 's/^designated => //p' "$test_directory/first-signature")
first_hash=$(/usr/bin/codesign -d --verbose=4 "$test_directory/Probe" 2>&1 | sed -n 's/^CDHash=//p')
"$test_directory/Probe" "$test_directory/probe.keychain-db" seed

# An already unlocked keychain does not validate the saved password.
/usr/bin/security lock-keychain "$PWD/.manabar-signing/manabar-signing.keychain-db"
swiftc -swift-version 6 -D SECOND_BUILD -module-cache-path .build/module-cache -framework Security \
  Tests/SigningProbe/main.swift -o "$test_directory/Probe"
./scripts/sign.sh "$test_directory/Probe" app.manabar.signing-check
/usr/bin/codesign --verify --strict --test-requirement "=$requirement" "$test_directory/Probe"
second_hash=$(/usr/bin/codesign -d --verbose=4 "$test_directory/Probe" 2>&1 | sed -n 's/^CDHash=//p')
test -n "$first_hash" && test -n "$second_hash" && test "$first_hash" != "$second_hash"
"$test_directory/Probe" "$test_directory/probe.keychain-db" read
/usr/bin/security list-keychains -d user > "$test_directory/search-after"
cmp "$test_directory/search-before" "$test_directory/search-after"
printf 'Signing identity, keychain ACL continuity, and unchanged user search list checks passed.\n'
