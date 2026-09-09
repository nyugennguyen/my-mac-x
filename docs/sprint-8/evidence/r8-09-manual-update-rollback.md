# R8-09 — Manual update and rollback verification

My Mac X v1 uses a manual update channel; there is no background updater or update
network path. Authenticity comes from the stable bundle identifier, Developer ID
TeamIdentifier, notarization and the published SHA-256 manifest.

## Preflight

1. Verify the downloaded DMG/ZIP against its adjacent checksum manifest.
2. Mount/open it and verify `codesign --verify --deep --strict` and
   `spctl --assess --type execute --verbose=4` on `MyMacX.app`.
3. Run `verify-update-rollback.sh CURRENT.app UPDATE.app ROLLBACK.app`. It rejects a
   bundle-ID or signing-team discontinuity and prints all three app versions.
4. Keep the prior notarized artifact and its checksum available until the beta is
   accepted. Never rollback to an unsigned or differently signed build.

## Config-preservation protocol (human)

1. Launch CURRENT, set one non-default layout/hotkey, quit, and record the redacted
   Diagnostics app/config version. Do not copy private config contents into evidence.
2. Replace `/Applications/MyMacX.app` with UPDATE using Finder; do not delete
   Application Support or Preferences. Launch, confirm the setting remains, perform
   one Window Action, quit.
3. Replace the app with ROLLBACK using Finder. Launch, confirm settings remain and
   perform the same action. If the newer build migrated config incompatibly, stop
   and restore the separately created config backup using the in-app import flow.
4. Record artifact hashes, versions, Gatekeeper results and PASS/FAIL below.

| Check | Result |
|---|---|
| Signature/team continuity | PENDING real Developer ID artifacts |
| Current → update preserves config | PENDING human run |
| Update → rollback preserves/restores config | PENDING human run |
| Window Action succeeds after each replacement | PENDING human run |
