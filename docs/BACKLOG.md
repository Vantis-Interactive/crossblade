# Development Backlog

Ordered by dependency. Status: **Done** means implemented and covered by automated tests that ran in this repository. **Done, needs Studio verification** means implemented, with its pure logic tested, but its Roblox runtime behaviour not yet confirmed in a Studio or multiplayer session. Everything else is **Planned**.

## Phase 0: Architecture and planning

| ID | Item | Status |
|---|---|---|
| ARC-01 | Repository structure, Rojo project, pinned toolchain | Done |
| ARC-02 | Service and controller architecture with a dependency-ordered loader | Done |
| ARC-03 | Data schema v1 | Done |
| ARC-04 | Network contracts | Done |
| ARC-05 | Threat model | Done (SECURITY.md) |
| ARC-06 | Asset manifest | Done |
| ARC-07 | Test strategy | Done (TEST_PLAN.md) |
| ARC-08 | CI workflow | Done (`.github/workflows/ci.yml`; not yet run on GitHub) |

## Phase 1: Core foundation

| ID | Item | Status |
|---|---|---|
| FND-01 | Service initialization and lifecycle (`Shared/Util/Loader`) | Done |
| FND-02 | Player lifecycle and persistent data (session lock, autosave, shutdown, migration) | Done, needs Studio verification |
| FND-03 | Character configuration (150 HP, standardized movement, no regeneration, no dismemberment) | Done, needs Studio verification |
| FND-04 | Input abstraction (keyboard/mouse, gamepad, touch) | Done, needs Studio verification |
| FND-05 | Configuration framework (`Shared/Config`) | Done |
| FND-06 | Remote communication with validation and rate limiting | Done |
| FND-07 | Logging and error handling | Done |

## Phase 2: Combat vertical slice

| ID | Item | Status |
|---|---|---|
| CMB-01 | 150 HP, no regeneration, cap enforced | Done |
| CMB-02 | Hybrid first/third-person camera with collision | Done, needs Studio verification |
| CMB-03 | Primary (Vanguard AR), secondary (Warden P9), knife (Ranger Combat Knife) | Done |
| CMB-04 | Limited ammunition and manual reload | Done |
| CMB-05 | Knife slash, stab, throw, recovery and stations | Done, needs Studio verification |
| CMB-06 | Health and ammunition pickups | Done |
| CMB-07 | Lag-compensated server hit validation | Done |
| CMB-08 | Free-for-All arena (greybox), match loop, respawning | Done, needs Studio verification |
| CMB-09 | Spawn selection and spawn protection | Done |
| CMB-10 | Combat HUD (health, ammo, slots, crosshair, hit markers, kill feed, scoreboard, elimination screen, damage direction) | Done, needs Studio verification |
| CMB-11 | Assists, killstreak announcements | Done |
| CMB-12 | Weapon inspect (procedural) | Done, needs Studio verification |
| CMB-13 | Audio | **Blocked**: no licensed assets (AUD-001/002) |
| CMB-14 | Shot-id acknowledgement to remove the ammo counter flicker (D-018) | Planned |
| CMB-15 | Map voting between rotations | Planned (Phase 4; needs at least 2 maps) |
| CMB-16 | Killcam | Planned (Phase 6, feasibility study) |

## Phase 3: Economy and collection

| ID | Item | Status |
|---|---|---|
| ECO-01 | EconomyService: earned/purchased wallet on `Transactions.Apply` | Planned |
| ECO-02 | Elimination, assist, streak and victory coin rewards (spec §13 values) | Planned |
| ECO-03 | InventoryService and loadout editing (server validates ownership via `Domain/Loadout`) | Planned |
| ECO-04 | CrateService: per-crate pools, server RNG, duplicate compensation, odds disclosure | Planned |
| ECO-05 | ProgressionService: XP and levels | Planned |
| ECO-06 | Anti-farming: self/cooperative/private-server farming limits; reward policy for `Finished` kills (D-013) | Planned |
| ECO-07 | Economy simulation tooling (Lune) before any crate goes live | Planned |

## Phase 4: Lobby and casual modes
LOB-01 social hub place · LOB-02 armory · LOB-03 crate shop · LOB-04 matchmaking portals · LOB-05 shooting range · LOB-06 tutorial · MOD-01 casual duels · MOD-02 Team Deathmatch · MOD-03 map voting. All Planned.

## Phase 5: Multiplayer infrastructure
NET-01 MemoryStore queues · NET-02 parties (up to 8) · NET-03 server browser · NET-04 reserved servers and teleport recovery · NET-05 reconnection · NET-06 private matches (no progression; flag already modelled in `GameModes.Private`) · NET-07 input remapping UI. All Planned.

## Phase 6: Competitive
RNK-01 rating system · RNK-02 divisions · RNK-03 ranked matchmaking · RNK-04 leaderboards · RNK-05 spectator · RNK-06 match history · RNK-07 anti-boosting and abandonment penalties · RNK-08 projectile rewind (D-011). All Planned.

## Phase 7: Progression and monetization
PRG-01 prestige · PRG-02 achievements · PRG-03 mastery · PRG-04 challenges · MON-01 ProcessReceipt fulfilment (idempotent) · MON-02 VIP · MON-03 battle pass · MON-04 PolicyService gating for paid random items (fail closed) · MON-05 purchase recovery. All Planned.

## Phase 8: Security and administration
SEC-01 RBAC admin roles · SEC-02 admin dashboard · SEC-03 reports · SEC-04 sanctions and appeals · SEC-05 economy reconciliation · SEC-06 server-side command audit · SEC-07 tune anti-cheat thresholds on real play data, then decide on `KickOnSuspicion` · SEC-08 durable cross-server audit storage. All Planned.

## Phases 9–12
Content (150 weapons, 10 maps, animations, audio, VFX), testing and optimization, release preparation, live operations. All Planned; see OPERATIONS.md and DEPLOYMENT.md.
