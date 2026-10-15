#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
umask 077

bundle_path="${1:?App or executable path required}"
bundle_identifier="${2:-app.manabar.prototype}"
signing_directory="$PWD/.manabar-signing"
mkdir -p "$signing_directory" .build/module-cache
chmod 700 "$signing_directory"

if [ ! -f "$signing_directory/identity.p12" ]; then
  if [ -e "$signing_directory/certificate.pem" ] || [ -e "$signing_directory/key.pem" ] \
      || [ -e "$signing_directory/password" ] || [ -e "$signing_directory/manabar-signing.keychain-db" ]; then
    printf 'Incomplete signing identity. Preserve .manabar-signing and repair it before rebuilding.\n' >&2
    exit 1
  fi
  cat > "$signing_directory/openssl.cnf" <<'CONFIG'
[req]
prompt = no
distinguished_name = identity
x509_extensions = signing
[identity]
CN = ManaBar Local Development
[signing]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
CONFIG
  /usr/bin/openssl rand -base64 32 > "$signing_directory/password"
  /usr/bin/openssl req -new -x509 -newkey rsa:2048 -sha256 -days 3650 \
    -passout "file:$signing_directory/password" \
    -config "$signing_directory/openssl.cnf" -keyout "$signing_directory/key.pem" \
    -out "$signing_directory/certificate.pem" 2> "$signing_directory/generation.log"
  /usr/bin/openssl pkcs12 -export -inkey "$signing_directory/key.pem" \
    -passin "file:$signing_directory/password" \
    -in "$signing_directory/certificate.pem" -out "$signing_directory/identity.p12" \
    -passout "file:$signing_directory/password"
fi

if [ ! -x .build/prepare-signing ] || [ scripts/prepare-signing.swift -nt .build/prepare-signing ]; then
  swiftc -swift-version 6 -module-cache-path .build/module-cache -framework Security \
    scripts/prepare-signing.swift -o .build/prepare-signing
fi
.build/prepare-signing "$signing_directory"
certificate_hash=$(/usr/bin/openssl x509 -in "$signing_directory/certificate.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')
/usr/bin/codesign --force --sign "$certificate_hash" --timestamp=none \
  --keychain "$signing_directory/manabar-signing.keychain-db" --identifier "$bundle_identifier" \
  --requirements "=designated => identifier \"$bundle_identifier\" and certificate leaf = H\"$certificate_hash\"" \
  "$bundle_path"
/usr/bin/codesign --verify --strict "$bundle_path"
