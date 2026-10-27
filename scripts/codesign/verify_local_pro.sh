#!/usr/bin/env bash
set -euo pipefail
app_path=${1:?Usage: verify_local_pro.sh APP_PATH}
script_dir=$(cd "$(dirname "$0")" && pwd)
identity=$(openssl x509 -in "$script_dir/local-pro-certificate.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')
codesign --verify --deep --strict --all-architectures --verbose=2 \
    -R "=identifier \"com.lwouis.alt-tab-macos\" and certificate leaf = H\"$identity\"" "$app_path"

# A valid signature alone does not prove Sparkle can talk to this self-signed host.
# A Developer ID-signed helper imposes its own Apple Team ID on XPC peers.
for helper in Autoupdate Updater.app; do
    path="$app_path/Contents/Frameworks/Sparkle.framework/Versions/Current/$helper"
    codesign --verify --strict --all-architectures "$path"
    for arch in arm64 x86_64; do
        metadata=$(codesign --display --verbose=4 --arch "$arch" "$path" 2>&1)
        if ! grep -qx 'Signature=adhoc' <<< "$metadata" || \
           ! grep -qx 'TeamIdentifier=not set' <<< "$metadata"; then
            echo "error: $helper ($arch) must be ad-hoc signed without an Apple Team ID" >&2
            exit 1
        fi
    done
done
