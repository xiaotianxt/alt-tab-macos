# Local Pro signing

Local Pro releases use a dedicated self-signed code-signing certificate, not an Apple Developer ID. The public certificate is `local-pro-certificate.pem`; it expires on 2046-09-18. Never regenerate it during a build.

GitHub Actions repository secrets:

- `LOCAL_PRO_SIGNING_P12`: base64-encoded, password-protected PKCS#12 containing the certificate and private key.
- `LOCAL_PRO_SIGNING_PASSWORD`: PKCS#12 password.
- `SPARKLE_ED_PRIVATE_KEY`: independent Sparkle archive-signing key; unchanged by this migration.

`sign_local_pro.sh` uses `rcodesign` 0.29.0, downloaded from its upstream release and verified against a pinned SHA-256 checksum. It signs directly from the PKCS#12 without importing into Keychain or modifying certificate trust settings. Credentials are held in a mode-0700 temporary directory and removed on exit; the password is passed by file, never as a command argument. Nested code retains its build-time signatures; the app is re-signed with its existing entitlements and hardened runtime, then verified recursively using Apple's `codesign`. No certificate installation or trust-store change is required on the user's Mac or CI runner.

The app's designated requirement pins both `com.lwouis.alt-tab-macos` and the exact signing certificate. Do not replace it with an identifier-only requirement, rotate the certificate, change the bundle ID, or fall back to ad-hoc signing. Updates must satisfy the identity requirement saved when Accessibility permission was granted. This signing does not provide Apple notarization or Developer ID Gatekeeper approval.

## Versions and migration

`LOCAL_PRO_REVISION` in `.github/workflows/local-pro.yml` is the fork's packaging revision. The release tag is `<upstream-tag>-local-pro.<revision>` and the app/Sparkle version is `<upstream-version>.<revision>`. Increase the revision for a new fork build of the same upstream release; never overwrite an existing release. Appcasts reference the immutable release asset URL.

The first persistent-identity release is `v11.7.1-local-pro.1` (app version `11.7.1.1`). Users migrating from an ad-hoc build must remove and re-add AltTab in Accessibility once. Signature continuity can be verified without changing system trust:

```sh
identity=$(openssl x509 -in scripts/codesign/local-pro-certificate.pem -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')
codesign --verify --deep --strict --all-architectures \
  -R "=identifier \"com.lwouis.alt-tab-macos\" and certificate leaf = H\"$identity\"" \
  /Applications/AltTab.app
codesign -dr - /Applications/AltTab.app
```

Actual TCC permission retention must also be checked across a subsequent installed update. Do not claim that signature verification alone proves that end-to-end behavior.

## Recovery

Keep a secure backup of the original PKCS#12 and password: GitHub secrets cannot be downloaded. Restore the same identity if secrets are lost. A new certificate with the same subject name is a different identity and requires a deliberate permission migration. Protect repository write access and review workflow changes: anyone able to run arbitrary release code can compromise CI-held signing keys.
