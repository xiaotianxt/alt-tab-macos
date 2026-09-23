#!/usr/bin/env bash
set -euo pipefail
umask 077

app_path=${1:?Usage: sign_local_pro.sh APP_PATH}
: "${LOCAL_PRO_SIGNING_P12:?Missing signing identity}"
: "${LOCAL_PRO_SIGNING_PASSWORD:?Missing signing identity password}"
script_dir=$(cd "$(dirname "$0")" && pwd)
certificate="$script_dir/local-pro-certificate.pem"
identity=$(openssl x509 -in "$certificate" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')
requirement="identifier \"com.lwouis.alt-tab-macos\" and certificate leaf = H\"$identity\""
temporary_dir=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/alttab-signing.XXXXXX")
trap 'rm -rf "$temporary_dir"' EXIT

# Direct signing avoids Keychain trust authorization UI on headless macOS runners.
# Pin both the tool version and archive hash before giving it access to the key.
tool_archive=apple-codesign-0.29.0-macos-universal.tar.gz
curl --fail --silent --show-error --location \
    "https://github.com/indygreg/apple-platform-rs/releases/download/apple-codesign/0.29.0/$tool_archive" \
    -o "$temporary_dir/$tool_archive"
printf '%s  %s\n' d98372d5524226ccf9dc0eda03d4e4f5826182dabb2fc3f2bd303ed9113a748d \
    "$temporary_dir/$tool_archive" | shasum -a 256 -c -
tar -xzf "$temporary_dir/$tool_archive" -C "$temporary_dir"

printf '%s' "$LOCAL_PRO_SIGNING_P12" | /usr/bin/base64 -D > "$temporary_dir/identity.p12"
printf '%s' "$LOCAL_PRO_SIGNING_PASSWORD" > "$temporary_dir/password"
unset LOCAL_PRO_SIGNING_P12 LOCAL_PRO_SIGNING_PASSWORD
csreq -r "=$requirement" -b "$temporary_dir/requirement.bin"

# Nested frameworks/helpers retain their build-time signatures and entitlements.
"$temporary_dir/apple-codesign-0.29.0-macos-universal/rcodesign" sign --config-file /dev/null \
    --p12-file "$temporary_dir/identity.p12" --p12-password-file "$temporary_dir/password" \
    --timestamp-url none --exclude '**' --code-signature-flags runtime \
    --code-requirements-file "$temporary_dir/requirement.bin" \
    --entitlements-xml-file "$script_dir/../../alt_tab_macos.entitlements" "$app_path"
codesign --verify --deep --strict --all-architectures --verbose=2 -R "=$requirement" "$app_path"
