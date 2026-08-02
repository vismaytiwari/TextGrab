#!/usr/bin/env bash
set -euo pipefail

# Creates a local, self-signed code-signing identity ("TextGrab Dev") in the
# login keychain, so `make app` can sign with something STABLE.
#
# Why it matters: macOS binds the Screen Recording permission to an app's code
# signature. Ad-hoc signing (`codesign -s -`) produces a new hash on every build,
# so the grant is dropped and the capture silently stops working until you
# re-approve it. A fixed identity keeps the signature the same across rebuilds.
#
# Local and reversible — remove it any time with:
#   security delete-identity -c "TextGrab Dev"

CERT_CN="TextGrab Dev"

if security find-identity -p codesigning 2>/dev/null | grep -q "$CERT_CN"; then
  echo "Identity '$CERT_CN' already exists — nothing to do."
  exit 0
fi

PW="tg-transit"           # transit-only password for the temporary PKCS#12
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
  -subj "/CN=$CERT_CN" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

# -legacy + -macalg sha1 + a non-empty password: required for Apple's Security
# framework to parse the PKCS#12 (OpenSSL 3 defaults are incompatible).
openssl pkcs12 -export -legacy -macalg sha1 \
  -out "$WORK/id.p12" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -passout "pass:$PW" 2>/dev/null

# -A lets codesign use the key without a keychain prompt on every build.
security import "$WORK/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$PW" -A

echo "Created code-signing identity '$CERT_CN'."
echo
echo "It is self-signed, so it reports NOT_TRUSTED — that is expected and fine."
echo "Next 'make app' will use it. Because this changes the signature once, macOS"
echo "will ask for Screen Recording one final time; after that rebuilds keep it."
