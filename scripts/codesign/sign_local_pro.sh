#!/usr/bin/env bash
set -euo pipefail
umask 077

app_path=${1:?Usage: sign_local_pro.sh APP_PATH}
: "${LOCAL_PRO_SIGNING_P12:?Missing signing identity}"
: "${LOCAL_PRO_SIGNING_PASSWORD:?Missing signing identity password}"
[[ ${GITHUB_ACTIONS:-} == true && ${RUNNER_ENVIRONMENT:-} == github-hosted ]] || {
    echo 'Run only on an ephemeral GitHub-hosted runner.' >&2
    exit 1
}
script_dir=$(cd "$(dirname "$0")" && pwd)
certificate="$script_dir/local-pro-certificate.pem"
identity=$(openssl x509 -in "$certificate" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')
requirement="identifier \"com.lwouis.alt-tab-macos\" and certificate leaf = H\"$identity\""
temporary_dir=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/alttab-signing.XXXXXX")
keychain="$temporary_dir/signing.keychain-db"
keychain_created=false
trust_added=false
cleanup() {
    local status=$?
    if $trust_added; then
        sudo security remove-trusted-cert -d "$certificate" || status=1
    fi
    if $keychain_created; then
        security delete-keychain "$keychain" || status=1
    fi
    rm -rf "$temporary_dir" || status=1
    exit "$status"
}
trap cleanup EXIT

printf '%s' "$LOCAL_PRO_SIGNING_P12" | /usr/bin/base64 -D > "$temporary_dir/identity.p12"
keychain_password=$(openssl rand -hex 32)
security create-keychain -p "$keychain_password" "$keychain"
keychain_created=true
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$temporary_dir/identity.p12" -k "$keychain" \
    -P "$LOCAL_PRO_SIGNING_PASSWORD" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s \
    -k "$keychain_password" "$keychain" >/dev/null
# macOS requires signing-time trust; scope it to code signing on this disposable runner.
# Installed apps use the pinned requirement below and need no client trust-store change.
sudo security add-trusted-cert -d -r trustRoot -p codeSign -k "$keychain" "$certificate"
trust_added=true
rm "$temporary_dir/identity.p12"
unset LOCAL_PRO_SIGNING_P12 LOCAL_PRO_SIGNING_PASSWORD keychain_password

# Pin the certificate, not a build-specific cdhash or a global trust-store entry.
# Nested frameworks/helpers retain the signatures already verified by the build.
codesign --force --sign "$identity" --keychain "$keychain" --timestamp=none --options runtime \
    --requirements "=designated => $requirement" \
    --entitlements "$script_dir/../../alt_tab_macos.entitlements" "$app_path"
codesign --verify --deep --strict --all-architectures --verbose=2 -R "$requirement" "$app_path"
