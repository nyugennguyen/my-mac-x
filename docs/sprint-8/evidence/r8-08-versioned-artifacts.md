# R8-08 — Immutable DMG, ZIP and checksums

`scripts/release/package-artifacts.sh` produces the following versioned files and
refuses to overwrite any existing one:

- `MyMacX-<release-version>.dmg`, with `MyMacX.app` and an Applications symlink;
- `MyMacX-<release-version>.zip`, preserving bundle metadata/resource forks; and
- `MyMacX-<release-version>.sha256`, covering both transport artifacts.

The app signature is verified before packaging. `verify-artifacts.sh` then checks
both hashes, the DMG structure, ZIP integrity and the source app signature.

```bash
RELEASE_VERSION=0.1.0-beta.3 scripts/release/package-artifacts.sh
RELEASE_VERSION=0.1.0-beta.3 scripts/release/verify-artifacts.sh
```

Publishing remains a separate human action. The artifact filenames, bytes and
checksum manifest must be retained together; a changed build requires a new release
version/build number rather than overwriting a published path.

## 2026-09-09 final demo artifact evidence

The final post-review ad-hoc `0.1.0-beta.3` (build 3) artifacts were created and verified locally.
DMG CRC, ZIP structure, strict signatures of the source app and each embedded app bundle, and both
SHA-256 entries passed:

```text
7e9777d3ec22f22ad6a8664bd6f7f792a7dfff4b7557997e385066e8047c9f91  MyMacX-0.1.0-beta.3.dmg
61960989412009b3ecd7ae48c05671f7e79bc2e9e21cbaa4f5d967439809c936  MyMacX-0.1.0-beta.3.zip
```

These files are suitable for a controlled local demo, not external distribution:
they are ad-hoc signed, not Developer ID signed and not notarized.
