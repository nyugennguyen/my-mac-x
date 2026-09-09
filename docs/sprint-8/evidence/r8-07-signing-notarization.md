# R8-07 — Developer ID signing, notarization and staple

## Credential-aware pipeline

No signing secret, Apple Account credential or notary profile is accepted as a
command-line value or written to repository output. A human first creates a
`notarytool` keychain profile outside this repository. The pipeline consumes only
the profile name through `NOTARY_KEYCHAIN_PROFILE`; the Developer ID identity is
selected through `DEVELOPER_ID_APPLICATION` and remains in the user's keychain.

```bash
RELEASE_VERSION=0.1.0-beta.3 \
APP_VERSION=0.1.0 \
BUILD_NUMBER=3 \
SIGNING_MODE=developer-id \
DEVELOPER_ID_APPLICATION='Developer ID Application: …' \
scripts/release/build-app.sh

RELEASE_VERSION=0.1.0-beta.3 \
NOTARY_KEYCHAIN_PROFILE=mymacx-notary \
scripts/release/notarize-and-staple.sh
```

The second command submits a dedicated ZIP, waits for Apple's terminal response,
then staples and validates the ticket and runs Gatekeeper assessment. Any rejected,
invalid, unavailable or credential-missing state exits non-zero. The JSON response
is retained beside the app as `notary-result.json` without printing credentials.

## Current gate status

Prepared and locally verifiable. Developer ID, Apple notarization, staple and a
clean-machine Gatekeeper pass remain a human credential/hardware gate until their
actual command outputs are captured. An ad-hoc beta must never be described as
signed/notarized.
