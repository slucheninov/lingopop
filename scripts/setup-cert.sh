#!/usr/bin/env bash
# Creates a self-signed code-signing cert "LingoPop Dev" in the login keychain
# so rebuilds preserve TCC (Accessibility) grants instead of resetting them on
# every cdhash change (which is what happens with ad-hoc `--sign -`).

set -euo pipefail

CERT_NAME="LingoPop Dev"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    echo "Certificate '$CERT_NAME' already exists."
    exit 0
fi

cat > "$WORK_DIR/cert.conf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext

[dn]
CN = $CERT_NAME

[ext]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$WORK_DIR/key.pem" \
    -out "$WORK_DIR/cert.pem" \
    -days 3650 \
    -config "$WORK_DIR/cert.conf"

P12_PASS="lingopop"
openssl pkcs12 -export \
    -inkey "$WORK_DIR/key.pem" \
    -in "$WORK_DIR/cert.pem" \
    -out "$WORK_DIR/cert.p12" \
    -name "$CERT_NAME" \
    -password "pass:$P12_PASS"

LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

security import "$WORK_DIR/cert.p12" \
    -k "$LOGIN_KEYCHAIN" \
    -P "$P12_PASS" \
    -T /usr/bin/codesign \
    -T /usr/bin/security

security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s -k "" \
    "$LOGIN_KEYCHAIN" >/dev/null 2>&1 || true

echo
echo "Certificate '$CERT_NAME' installed."
security find-identity -v -p codesigning | grep "$CERT_NAME" || true
