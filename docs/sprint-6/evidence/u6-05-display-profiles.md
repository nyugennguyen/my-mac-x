# U6-05 — Display Profiles

Profiles persist by validated `StableDisplayID`; production derives reconnect-stable IDs from public CoreGraphics display UUIDs and can create profiles for currently connected displays. `WindowActionEngine` resolves profile Layout membership and gap before pure calculation, and runtime profile/gap changes hot-apply. Profile, Settings, and Window Action tests pass.
