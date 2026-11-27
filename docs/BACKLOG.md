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
| ECO-01 | EconomyService: earned/purchased wallet on `Transactions.Apply` | Done, needs Studio verification |
| ECO-02 | Elimination, assist, streak and victory coin rewards (spec §13 values) | Done (rules tested), needs Studio verification |
| ECO-03 | InventoryService and loadout editing (ownership validated server-side) | Done, needs Studio verification |
| ECO-04 | CrateService: per-crate pools, server RNG, duplicate compensation, odds disclosure | Done (rules tested), needs Studio verification |
| ECO-05 | ProgressionService: XP, levels, one-time level rewards | Done (rules tested) |
| ECO-06 | Anti-farming: repeat-victim limit, hourly caps, population minimum, owned private servers, `Finished` reward policy | Done (rules tested) |
| ECO-07 | Economy validation | Partial: boot-time pool/odds/EV validation and tests are done; a standalone long-horizon economy simulation tool is planned |
| ECO-08 | Weapon customization (skins, charms, stickers, attachments) | Planned. The Phase 3 foundation is the collection finish on each weapon; the `Customization` schema field is reserved |
| ECO-09 | Seasonal crates (Halloween, Winter, Anniversary) | Planned (Phase 12, needs seasonal content) |
| ECO-10 | Sink-margin decision for crates (ECONOMY.md §4) | **Owner decision** |

## Phase 4: Lobby and casual modes

| ID | Item | Status |
|---|---|---|
| LOB-01 | Social hub place: plaza, portals, stations, range, training zone, parkour (greybox) | Done, needs Studio verification |
| LOB-02 | Armory station (opens Collection > Armory) | Done, needs Studio verification |
| LOB-03 | Crate shop station (opens Collection > Crates) | Done, needs Studio verification |
| LOB-04 | Matchmaking portals and PLAY menu (teleport to mode places) | Done; **needs published PlaceIds** to actually teleport |
| LOB-05 | Shooting range with training dummies | Done, needs Studio verification |
| LOB-06 | Guided tutorial (12 steps, one-time reward, required before matches) | Done (rules tested), needs Studio verification |
| LOB-07 | VIP lounge, battle pass station, quest stations, leaderboards, weapon exhibitions, seasonal decorations, announcements board, player profile inspection | Planned (Phases 6, 7, 12; they depend on those systems) |
| MOD-01 | Casual duels 1v1 and team (2v2 place; 3v3/4v4 via TeamSize) with spectating | Done (rules tested), needs Studio verification |
| MOD-02 | Team Deathmatch | Done (rules tested), needs Studio verification |
| MOD-03 | Map voting between matches (second greybox map added) | Done (rules tested), needs Studio verification |

## Phase 5: Multiplayer infrastructure

| ID | Item | Status |
|---|---|---|
| NET-01 | MemoryStore matchmaking queues (TDM, Duel 1v1, Duel 2v2): duplicate prevention, expiry, cancel, leader lease | Done (rules tested against a MemoryStore double); **needs published places** |
| NET-02 | Parties up to 8 (hub, same server) | Done, needs Studio verification. Cross-server invites planned |
| NET-03 | Public server browser (FFA, TDM) | Done; needs published places |
| NET-04 | Reserved servers, failed-teleport requeue, arrival timeout, return to hub | Done (rules tested); needs published places |
| NET-05 | Reconnection to an unfinished reserved match | Done (rules tested); needs published places |
| NET-06 | Private matches (party-hosted; map, duration, score limit; no progression) | Done (rules tested); needs published places |
| NET-07 | Keyboard and gamepad remapping | Done (rules tested), needs Studio verification |
| NET-08 | Latency-aware matchmaking | **Not implemented**: Roblox exposes no cross-server latency estimate to a matchmaker. Region-aware queues would need a documented approach first |
| NET-09 | Tutorial gate in arenas | Done |

## Phase 6: Competitive
RNK-01 rating system · RNK-02 divisions · RNK-03 ranked matchmaking · RNK-04 leaderboards · RNK-05 spectator · RNK-06 match history · RNK-07 anti-boosting and abandonment penalties · RNK-08 projectile rewind (D-011). All Planned.

## Phase 7: Progression and monetization
PRG-01 prestige · PRG-02 achievements · PRG-03 mastery · PRG-04 challenges · MON-01 ProcessReceipt fulfilment (idempotent) · MON-02 VIP · MON-03 battle pass · MON-04 PolicyService gating for paid random items (fail closed; **done for crate spending in Phase 3**) · MON-05 purchase recovery. All Planned except MON-04, which is implemented for crate spending.

## Phase 8: Security and administration
SEC-01 RBAC admin roles · SEC-02 admin dashboard · SEC-03 reports · SEC-04 sanctions and appeals · SEC-05 economy reconciliation · SEC-06 server-side command audit · SEC-07 tune anti-cheat thresholds on real play data, then decide on `KickOnSuspicion` · SEC-08 durable cross-server audit storage. All Planned.

## Phases 9–12
Content (150 weapons, 10 maps, animations, audio, VFX), testing and optimization, release preparation, live operations. All Planned; see OPERATIONS.md and DEPLOYMENT.md.
