# Development Status

_Last updated: 2026-11-26_

## Summary

Phases 0–5 are implemented: the foundation, the combat slice, the economy and collection layer, the hub with its tutorial and casual modes, and multiplayer infrastructure. That last phase adds cross-server matchmaking, parties, reserved match servers, reconnection, private matches, the server browser and control remapping. Their rules pass 225 automated tests. **It has not yet been played in Roblox Studio or on a live server.** This environment has no Roblox Studio, so the Roblox runtime behaviour of the services and controllers still needs the manual checks in TEST_PLAN.md §4 before Phase 2 can be signed off as "playable multiplayer verified".

| Phase | State |
|---|---|
| 0: Architecture and planning | Complete |
| 1: Core foundation | Implemented; pure parts tested; Studio verification pending |
| 2: Combat vertical slice | Implemented; pure parts tested; Studio and multiplayer verification pending |
| 3: Economy and collection | Implemented; rules tested; Studio verification pending; several values proposed (D-021–D-024, D-029) |
| 4: Lobby and casual modes | Implemented; rules tested; all five places build and verify; Studio and multiplayer verification pending; teleports need published PlaceIds |
| 5: Multiplayer infrastructure | Implemented; rules tested against a MemoryStore double; **end-to-end requires published places** (Studio cannot reserve servers or teleport) |
| 6–12 | Not started (see BACKLOG.md) |

## What works (verified by automated tests)
- Health rules (150 cap, no healing of the dead), pickup consumption and respawn timing.
- Ammunition, reload timing and cancellation, reserve caps; the three-slot loadout resolved from the owned inventory.
- Knife state: throw, recovery by id only, station replacement.
- Hit validation against rewound standardized hitboxes: origin, range, direction, line of sight, headshot rules, timestamp bounds, melee reach and cone.
- Fire-rate enforcement that tolerates jitter but bounds the sustained rate.
- Spawn scoring, movement plausibility, suspicion decay, assists, ranking and streaks.
- Session-locked persistence: creation, no default overwrite, lock contention, stale takeover, outage retry, corrupt and future-version refusal, migrations, lock loss on save; idempotent all-or-nothing transactions.
- Remote payload validation against malformed and hostile input; every remote declared and used.
- Economy: specified coin rewards, assists and streaks; anti-farming (repeat-victim limit, hourly caps, population, private servers); one-time level rewards.
- Crates: every crate validates (pool, odds, price, compensation, EV below price); selection provably equals the disclosed odds; exact duplicate compensation; atomic, idempotent purchases; purchased coins blocked unless policy allows (fail closed).
- Schema v2 migration preserves v1 data without retroactive level rewards.
- Modes: team balancing, Team Deathmatch outcomes, duel rounds, forfeits and time limits, map voting, and the tutorial step machine with its one-time reward.
- Every greybox map (3) has no pickup, spawn or station inside geometry, and team maps have balanced team spawns.
- Each place builds with the right role and mode, and each role's service graph boots.
- Matchmaking: party-preserving match forming, no double queueing across servers, ticket expiry and cancel, requeue after failed teleports, leader leases, server reservation failures, reserved-server admission, start/cancel rules and reconnect windows, private-match mode with no progression, and remapping rules and their wire format.
- Source integrity: every file compiles; every require resolves; every service and controller declares its dependencies; no cycles.

## Implemented but not yet verified in Roblox
Everything in `src/server/Services` and `src/client/Controllers`: DataStore I/O, character spawning and protection, weapon models and poses, the scripted camera, input bindings (including touch and gamepad), the HUD, effects, projectile flight, pickup proximity, match rounds.

## Known limitations
- **Temporary assets:** greybox map, primitive weapon models, procedural poses and effects (ASSET_MANIFEST.md).
- **No audio:** no licensed sound assets exist (AUD-001/002). The feature is blocked, not faked.
- **Teleports and matchmaking need publishing:** places and PlaceIds (`Config.Places`) are not configured, so portals, queues, the server browser, private matches and reconnects refuse with explicit messages. Studio cannot reserve servers or teleport at all.
- **No cross-server party invites and no latency-aware matching** (D-044, NET-08).
- **Hub extras** (VIP lounge, battle pass station, quests, leaderboards, exhibitions, announcements, profile inspection) are not built; they depend on Phases 6–7 and 12.
- **No Robux purchases, VIP, battle pass, prestige, achievements or challenges yet** (Phase 7). Purchased-coin balances exist in the schema but nothing grants them.
- **Weapon customization** is limited to the collection finish colour (ECO-08).
- **Collectible content is placeholder:** 37 original names on primitive models (D-028).
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
5. **Crate economy values.** With the specified odds and duplicate compensation, a 250-coin Basic crate returns 245 coins of expected compensation to a player who owns everything. That is only a 2% coin sink (ECONOMY.md §4). Approve one of the proposed adjustments before any crate goes live; each changes specified values.
6. **Proposed Phase 5 values:** queue sizes (D-043), timings (D-045), private match bounds (D-048).
7. **Proposed Phase 4 values:** TDM start threshold (D-032), duel round time limits and tie-breaks (D-033), team victory XP (D-039).
8. **Publish the five places** and fill `Config.Places` PlaceIds and per-place server sizes (DEPLOYMENT.md).
9. **Proposed Phase 3 values:** XP amounts (D-021), level curve and rewards (D-022), non-standard crate odds (D-023), anti-farming limits (D-024) and Free-for-All first-place reward (D-029). They are configuration values; approve or adjust them.
10. **Authorization** before any public publish, live purchase or production data change (directive §2.17). None has been performed.

## Recommended next steps
1. Run the TEST_PLAN.md §4 checklist (M-01–M-36 in Studio; M-37–M-42 need a published private test universe) and fix what it finds.
2. Decide the proposed values and the crate sink margin.
3. Publish the places (private) so teleports can be tested end to end.
4. Phase 6: ranked duels (rating system, divisions, skill-based queues, seasons), leaderboards, match history, abandonment penalties and anti-boosting.
5. Generate the full Selene Roblox std on a machine with direct internet access (D-006).
