# Changelog

All notable changes to this project. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions are pre-release development milestones.

## [0.4.0] - 2026-11-26 (Phase 4: hub and casual modes, unverified in Studio)
### Added
- Five places from one codebase (hub, Free-for-All, Team Deathmatch, Duel 1v1, Team Duel 2v2) via `places/*.project.json` and `PlaceConfig`.
- Team Deathmatch and casual duels (rounds, spectating, forfeits, round time limits), with victory rewards.
- Map voting between matches; second arena greybox "Outpost Yard"; hub greybox.
- Social hub: matchmaking portals and PLAY menu, armory and crate stations, shooting range with training dummies, training zone, parkour.
- Guided 12-step tutorial with server-verified steps and a one-time reward (500 coins plus a free Basic Crate token); required before matches.
- Crate tokens; teleport handling with explicit refusals and failure recovery.
- Integrity tests for per-role boot graphs and signal wiring.
### Changed
- MatchService rewritten as one generic flow for every mode; the hub runs a non-scoring Lobby mode.
- Hits may target training dummies; player damage is now team-aware (`CanDamage`).
### Fixed
- `PickupService.PickupConsumed` was fired but never declared (found by the new signal-wiring test).

## [0.3.0] - 2026-11-26 (Phase 3: economy and collection, unverified in Studio)
### Added
- Earned/purchased wallet; coin and XP rewards for eliminations, assists, headshots, streaks and match completion, each applied as one idempotent transaction.
- Anti-farming: repeat-victim limit, persisted hourly caps, population minimum, no rewards in player-owned private servers or modes without progression.
- Levels 1–100 with one-time level rewards.
- 13 crates (rarity, weapon and themed) with boot-time validation, server-side selection, exact per-item odds shown before purchase, duplicate compensation, and idempotent purchases keyed by a client request id.
- Fail-closed PolicyService gating: purchased coins are only spendable on crates for eligible players.
- 37 collectible weapons (placeholder content) and dev model profiles for every archetype, tinted by collection.
- Collection window (Armory and Crates), HUD wallet and level, reward notifications.
### Changed
- Player data schema v2 (crate history, hourly reward counters, highest rewarded level) with a migration from v1.

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
