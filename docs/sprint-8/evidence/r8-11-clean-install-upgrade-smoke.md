# R8-11 — Clean install and upgrade smoke test

This is a human-only acceptance protocol on a supported clean macOS 14+ account or
machine. Use only the exact Developer ID signed, notarized, stapled artifact and
published SHA-256 manifest. An ad-hoc demo build is ineligible.

## Clean install

1. Verify SHA-256, mount the DMG, copy My Mac X to Applications, eject the DMG.
2. Run `spctl --assess --type execute --verbose=4 /Applications/MyMacX.app` and
   `xcrun stapler validate /Applications/MyMacX.app`; record outputs.
3. Launch from Finder. Confirm no Gatekeeper bypass is requested and the menu-bar
   app starts without a Dock icon or unexpected window.
4. Follow onboarding, deny Accessibility once, then grant it in System Settings.
   Confirm status refresh and perform one hotkey, one Super Mode action and one
   Notch Snap action. Confirm no Screen Recording request occurs.
5. Quit/relaunch and reboot/login once; confirm settings persist and no duplicate
   app instance/status item appears.

## Upgrade and rollback

Run the full R8-09 protocol with the previously released beta as CURRENT, this
candidate as UPDATE and the retained previous artifact as ROLLBACK. Confirm settings
and Accessibility trust behave as documented; macOS can legitimately require TCC
approval again if bundle identity or designated requirement changed, which is a
release failure unless intentionally approved.

## Evidence record

| Field | Result |
|---|---|
| macOS version / hardware | PENDING human clean machine |
| Artifact filename / SHA-256 | PENDING signed artifact |
| Notary/staple/Gatekeeper | PENDING |
| Permission lifecycle | PENDING |
| Hotkey / Super Mode / Notch Snap | PENDING |
| Relaunch / login / single instance | PENDING |
| Upgrade / rollback config preservation | PENDING |

Do not mark R8-11 or Gate G8 passed until every row has real evidence and no open
P0/P1 issue remains.
