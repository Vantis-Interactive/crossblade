# Changelog

All notable changes to this project. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions are pre-release development milestones.

## [0.2.0] - 2026-11-26 (Phase 2: combat vertical slice, unverified in Studio)
### Added
- Free-for-All match loop: 15-minute rounds, 20-second intermission, 3-second respawn, scoreboard, kill feed, killstreak announcements, round results.
- Server-authoritative combat: fire, melee (slash and stab) and knife throw; lag-compensated validation against standardized hitboxes; line of sight; server-side damage.
- Starter loadout: Vanguard AR, Warden P9, Ranger Combat Knife; all ten archetypes configured.
- Ammunition with manual reload; health, ammunition and knife-station pickups.
- Spawn selection and five-second spawn protection.
- Scripted first/third-person camera with collision, recoil, FOV and sensitivity settings.
- Combat HUD, settings panel, notifications, non-graphic elimination effect.
- Anti-cheat suspicion scoring and movement validation; audit log.
- Greybox arena "Foundry Yard" (temporary).

## [0.1.0] - 2026-11-26 (Phases 0–1: foundation)
### Added
- Rojo project, pinned toolchain, Selene and StyLua configuration, CI workflow.
- Shared configuration framework; network contracts with schema validation and per-player rate limits.
- Dependency-ordered service and controller loader.
- Versioned player data schema v1 with session locking, autosave, shutdown flush, migrations and idempotent transactions.
- Lune test runtime and harness; static integrity tests; place-structure verifier.
- Documentation set and requirements traceability matrix.
