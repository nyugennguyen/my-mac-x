# R8-06 — Hardened Runtime and minimal entitlements

## Result

The Release configuration explicitly enables Hardened Runtime, disables Xcode's
automatic base-entitlement injection, and uses `Configs/MyMacX.entitlements`.
The manifest is intentionally empty: Accessibility and Input Monitoring are TCC
permissions, not code-signing entitlements, and this direct-distribution target is
not App Sandbox enabled.

`scripts/release/build-app.sh` builds without signing, then applies either a real
Developer ID Application signature with secure timestamp or an explicit ad-hoc
demo signature. Both modes use `--options runtime` and the reviewed entitlement
manifest. The script captures the embedded entitlement output and performs strict,
deep signature verification.

## Automated checks

Run:

```bash
plutil -lint Configs/MyMacX.entitlements
RELEASE_VERSION=0.1.0-beta.3 BUILD_NUMBER=3 SIGNING_MODE=adhoc scripts/release/build-app.sh
codesign -d --verbose=4 --entitlements :- build/release/0.1.0-beta.3/MyMacX.app
codesign --verify --deep --strict --verbose=2 build/release/0.1.0-beta.3/MyMacX.app
```

An ad-hoc signature proves bundle sealing and runtime-option configuration only. It
does not satisfy Developer ID, notarization, Gatekeeper or clean-machine release
acceptance.

## 2026-09-09 beta build evidence

- Release clean build: PASS, universal `arm64` + `x86_64` Mach-O.
- Strict/deep code-signature verification: PASS.
- Signature: ad-hoc; TeamIdentifier not set; Runtime Version `26.5.0`.
- Embedded entitlement manifest: empty dictionary as designed.
- Developer ID/Gatekeeper/notarization: NOT RUN and not claimed.
