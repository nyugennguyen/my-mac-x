# U6-07 — Import and export

The reachable Settings workflow uses a strict 256 KiB versioned archive, exact-key validation and v1/v2 migration. Import validates completely, hot-applies Hotkeys, Super Mode, Launch at Login, app rules, and Display Profiles, then refreshes the UI after asynchronous completion. Failure keeps the prior presented configuration and performs best-effort rollback. Export contains no path, permission, diagnostic, credential, or window-identity fields.
