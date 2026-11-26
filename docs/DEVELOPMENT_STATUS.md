# Development Status

_Last updated: 2026-11-26_

## Summary

Phases 0, 1 and 2 are implemented. The Free-for-All combat vertical slice is code-complete, and its rules pass 126 automated tests. **It has not yet been played in Roblox Studio or on a live server.** This environment has no Roblox Studio, so the Roblox runtime behaviour of the services and controllers still needs the manual checks in TEST_PLAN.md §4 before Phase 2 can be signed off as "playable multiplayer verified".

| Phase | State |
|---|---|
| 0: Architecture and planning | Complete |
| 1: Core foundation | Implemented; pure parts tested; Studio verification pending |
| 2: Combat vertical slice | Implemented; pure parts tested; Studio and multiplayer verification pending |
| 3–12 | Not started (see BACKLOG.md) |

## What works (verified by automated tests)
- Health rules (150 cap, no healing of the dead), pickup consumption and respawn timing.
- Ammunition, reload timing and cancellation, reserve caps; the three-slot loadout resolved from the owned inventory.
- Knife state: throw, recovery by id only, station replacement.
- Hit validation against rewound standardized hitboxes: origin, range, direction, line of sight, headshot rules, timestamp bounds, melee reach and cone.
- Fire-rate enforcement that tolerates jitter but bounds the sustained rate.
- Spawn scoring, movement plausibility, suspicion decay, assists, ranking and streaks.
- Session-locked persistence: creation, no default overwrite, lock contention, stale takeover, outage retry, corrupt and future-version refusal, migrations, lock loss on save; idempotent all-or-nothing transactions.
- Remote payload validation against malformed and hostile input; every remote declared and used.
- Source integrity: every file compiles; every require resolves; every service and controller declares its dependencies; no cycles.

## Implemented but not yet verified in Roblox
Everything in `src/server/Services` and `src/client/Controllers`: DataStore I/O, character spawning and protection, weapon models and poses, the scripted camera, input bindings (including touch and gamepad), the HUD, effects, projectile flight, pickup proximity, match rounds.

## Known limitations
- **Temporary assets:** greybox map, primitive weapon models, procedural poses and effects (ASSET_MANIFEST.md).
- **No audio:** no licensed sound assets exist (AUD-001/002). The feature is blocked, not faked.
- **One place only:** hub, tutorial and other modes are not built.
- **No economy, crates, progression or monetization yet** (Phase 3+). Kill rewards are not granted.
- **Selene uses a minimal Roblox std** (D-006). Member-level API linting is unavailable until the full std is generated.
- **Thrown knives have no lag compensation** (D-011).
- **Ammo counter flicker** when server state arrives with shots in flight (D-018, CMB-14).
- **Audit log is per-server and in-memory** (SEC-08).
- **Feature flags are static** and need a deploy to change (Phase 12 remote config).
- R15 avatars are required for procedural poses. Combat itself is avatar-independent.

## Blockers needing the owner
1. **Approve the final game name** before the first production DataStore write (D-001).
2. **Roblox Studio access** to run the Phase 2 manual checklist, and a published place with API access enabled.
3. **Production, staging and development PlaceIds** for `Config.Data.Environments`.
4. **Licensed or original audio and art** to replace temporary assets.
5. **Authorization** before any public publish, live purchase or production data change (directive §2.17). None has been performed.

## Recommended next steps
1. Run the TEST_PLAN.md §4 checklist in Studio with 3+ players and fix what it finds.
2. Phase 3: EconomyService and CrateService on `Transactions.Apply`, with the economy simulation (ECO-07) before any crate is enabled.
3. Generate the full Selene Roblox std on a machine with direct internet access (D-006).
