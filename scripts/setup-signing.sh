#!/bin/bash
set -euo pipefail
umask 077
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SIGNING_DIR="$HOME/Library/Application Support/WhisperPaste"
CONFIG="$SIGNING_DIR/signing.plist"
LABEL='Whisper Paste Local Signing'
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp/}whisper-paste-signing.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
trap 'exit 130' INT TERM

if [ -f "$CONFIG" ]; then
    IDENTITY=$(/usr/libexec/PlistBuddy -c 'Print Identity' "$CONFIG")
    KEYCHAIN=$(/usr/libexec/PlistBuddy -c 'Print Keychain' "$CONFIG")
else
    KEYCHAIN=$(/usr/bin/security default-keychain -d user | sed 's/^ *"//; s/"$//')
    if /usr/bin/security find-certificate -c "$LABEL" -p "$KEYCHAIN" > "$WORK_DIR/cert.pem" 2>/dev/null; then
        echo 'Reusing the existing Whisper Paste certificate.'
    else
        /usr/bin/openssl rand -base64 32 > "$WORK_DIR/passphrase"
        /usr/bin/openssl rand -base64 32 > "$WORK_DIR/archive-passphrase"
        cat > "$WORK_DIR/openssl.cnf" <<'EOF'
[req]
prompt = no
distinguished_name = subject
x509_extensions = code_signing
[subject]
CN = Whisper Paste Local Signing
[code_signing]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
EOF
        /usr/bin/openssl req -new -newkey rsa:2048 -x509 -sha256 -days 3650 \
            -config "$WORK_DIR/openssl.cnf" -keyout "$WORK_DIR/key.pem" \
            -out "$WORK_DIR/cert.pem" -passout "file:$WORK_DIR/passphrase" 2>/dev/null
        /usr/bin/openssl pkcs12 -export -name "$LABEL" -inkey "$WORK_DIR/key.pem" \
            -in "$WORK_DIR/cert.pem" -out "$WORK_DIR/identity.p12" \
            -passin "file:$WORK_DIR/passphrase" -passout "file:$WORK_DIR/archive-passphrase"
        swift -suppress-warnings "$PROJECT_DIR/scripts/import-signing-identity.swift" \
            "$KEYCHAIN" "$WORK_DIR/identity.p12" "$WORK_DIR/archive-passphrase"
        # No exported private key or wrapping password survives setup.
        rm -f "$WORK_DIR/key.pem" "$WORK_DIR/identity.p12" "$WORK_DIR/passphrase" "$WORK_DIR/archive-passphrase"
    fi
    IDENTITY=$(/usr/bin/openssl x509 -in "$WORK_DIR/cert.pem" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')
fi

# Check an actual signature before storing the configuration. This does not add
# certificate trust settings or require an Apple account, network access or sudo.
cp /usr/bin/true "$WORK_DIR/signing-probe"
/usr/bin/codesign --force --sign "$IDENTITY" --keychain "$KEYCHAIN" --timestamp=none \
    --identifier io.github.sungho-ham.whisper-paste.signing-probe "$WORK_DIR/signing-probe"
/usr/bin/codesign --verify --strict "$WORK_DIR/signing-probe"
"$WORK_DIR/signing-probe"
/usr/bin/codesign -d -r- "$WORK_DIR/signing-probe" 2>&1

if [ ! -f "$CONFIG" ]; then
    mkdir -p "$SIGNING_DIR"
    /usr/libexec/PlistBuddy -c 'Clear dict' "$WORK_DIR/signing.plist" >/dev/null
    /usr/libexec/PlistBuddy -c "Add Identity string $IDENTITY" "$WORK_DIR/signing.plist"
    /usr/libexec/PlistBuddy -c "Add Keychain string $KEYCHAIN" "$WORK_DIR/signing.plist"
    mv "$WORK_DIR/signing.plist" "$CONFIG"
fi
echo "Persistent signing configured: $CONFIG"
echo "Certificate fingerprint: $IDENTITY"
