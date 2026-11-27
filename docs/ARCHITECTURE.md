# Architecture

Crossblade is a server-authoritative multiplayer arena game built in Luau and synced into Roblox with Rojo. This document describes how the code is organized and how its parts talk to each other. Per-topic detail lives in DATA_SCHEMA.md, NETWORK_CONTRACTS.md and SECURITY.md.

## 1. Principles

1. **The server is the authority.** Clients send intent (a slot name, a fire request with a proposed hit). The server owns health, ammunition, loadouts, cooldowns, damage, eliminations, pickups and persistence.
2. **Functional core, imperative shell (D-002).** Every rule is a pure module that touches no Roblox services and takes time, randomness and world queries as parameters. Services and controllers are thin shells that connect Roblox events to those rules. This is what lets the rules be unit-tested headlessly.
3. **Configuration over constants.** All tuning values live in `src/shared/Config`. Gameplay code reads from `Config`, never from literals.
4. **Declarative contracts.** Every remote is declared once, with a schema and a rate limit (D-020).
5. **Fail closed.** If data cannot be loaded safely, the player is removed and nothing is written. If a request is malformed, it is dropped and reported.

## 2. Repository layout

```
default.project.json     Rojo project: maps src/ into the DataModel
rokit.toml               pinned toolchain (rojo, lune, stylua, selene)
src/
  shared/                -> ReplicatedStorage.Shared (visible to clients: NO secrets)
    Config/              all tuning: Player, Camera, Combat, Pickups, Spawning, GameModes,
                         Data, AntiCheat, FeatureFlags, Rarity, Theme, Input, Weapons/{Archetypes,Catalog}
    Economy/             pure rules: CrateOdds (disclosure = selection), Leveling, Wallet
    Combat/              pure rules: Hitbox, DamageCalculator, HealthRules, AmmoState,
                         KnifeState, FireCadence, PositionHistory
    Net/                 Schema (payload validator), Contracts (every remote)
    Util/                Loader, Logger, Signal, RateLimiter, Retry, Trove, TableUtil
    Weapons/             WeaponCatalog (read API + validation), WeaponModels (temporary dev models)
    Settings.luau        player settings defaults + sanitization
    Bindings.luau        input remapping allow-lists, conflict rules, wire form (D-049)
    PlaceConfig.luau     this place's Role / Mode / TeamSize (D-030)
  server/                -> ServerScriptService.Server (never replicated)
    Main.server.luau     boot
    Core/                Net (remote admission), Environment (dev/staging/prod), CombatQuery (LOS raycasts),
                         MatchContext (public / reserved / owned-private server identity, D-042)
    Data/                Schema (v1 + migrations), ProfileStore (session locking),
                         Transactions (idempotent atomic mutations), DataStoreAdapter
    Domain/              pure server rules: HitValidator, DamageLedger, SpawnSelector,
                         MovementValidator, SuspicionScore, PickupState, MatchRules, Loadout,
                         CrateOpening, RewardPolicy, PaidRandomPolicy,
                         Teams, DuelRounds, MapVote, TutorialProgress,
                         MatchFormer, PartyState, ReservedRoster
    Matchmaking/         Queue (tickets, user index, assignments, leases), Matchmaker (leader tick),
                         MemoryStoreAdapter (MemoryStoreSortedMap behind the Queue.SortedMap interface)
    Services/            26 services (section 4)
    Maps/                temporary greybox layouts: DevArena, DevOutpost, DevHub (DEV-MAP-001..003)
  client/                -> StarterPlayerScripts.Client
    Main.client.luau     boot
    Core/                Net (client wrapper), UIState
    Controllers/         19 controllers (section 5)
    UI/Build.luau        themed UI construction helpers
  character/Health.server.luau  -> StarterCharacterScripts.Health (disables default regeneration)
tests/                   Lune test runtime, harness, specs
scripts/                 verify.sh (full pipeline), verify-place.luau (built place checks)
docs/                    this documentation set
```

## 3. Boot and lifecycle

Before anything else, `Server/Main.server.luau` calls `Core/MatchContext.Load()`. This is the only step allowed to yield before boot: a reserved server reads its match record (roster, mode, private settings) from MemoryStore by `game.PrivateServerId`, because `MatchService` and `MapService` need the mode and map at require/Init time. If the record cannot be read, `MatchContext.Failed` is set and every player is returned to the hub (fail closed, D-042). Public servers and player-owned private servers skip the lookup.

`Shared/Util/Loader` then boots both server and client:

1. Each module declares `Name` and an optional `Dependencies` list.
2. `Loader.Sort` topologically orders modules. Cycles and unknown dependencies are boot-time errors.
3. Each module's `Init(self, registry)` runs synchronously in dependency order. Init wires event handlers and must not yield. **An Init failure aborts boot.**
4. Each module's `Start(self)` runs in its own thread. A failing Start is logged and does not stop the others.

`registry` maps names to modules. A module may only use `registry.X` for names in its own `Dependencies` list. `tests/specs/Integrity.spec.luau` enforces this for every service and controller, because a missing declaration would otherwise be `nil` at runtime.

## 4. Server services

| Service | Owns | Depends on |
|---|---|---|
| Net (Core) | Creates all remotes, admits client requests (argument count, rate limit, schema), `Violation` signal | none |
| AuditService | Bounded in-memory security, data and admin audit trail | none |
| PlayerDataService | Session-locked profiles, autosave, shutdown flush, settings persistence, `ApplyTransaction` | Net, AuditService |
| AntiCheatService | Suspicion scoring, movement sampling and correction, review alerts | Net, AuditService |
| MapService | Loads the authored map or the greybox; tag-based queries | none |
| HealthService | Authoritative health per life, single death path, kill height | MapService, AuditService |
| AmmunitionService | Magazine, reserve and reload state per firearm | none |
| WeaponService | Loadout resolution (ownership), equip timing, knife state, world weapon models, `LoadoutState` | Net, PlayerDataService, AmmunitionService, AuditService |
| SpawnService | Spawn selection, spawn protection, life reset | Net, MapService, AntiCheatService, WeaponService, HealthService |
| DamageService | Damage application, assist ledger, single `Eliminated` event | Net, HealthService, SpawnService |
| MatchService | Match flow for every mode (Lobby, FFA, TDM, Duel), teams, rounds, map vote, scoreboard, kill feed, stats, `GetSnapshot`; reserved-server rules (roster teams, one match, reconnect-preserved entries, `BeginReserved`, `ForgetPlayer`) | Net, PlayerDataService, DamageService, SpawnService, HealthService, MapService, WeaponService |
| ProjectileService | Thrown-knife flight, impact, ground knives, recovery | Net, WeaponService, DamageService, HealthService, MatchService, PlayerDataService |
| PickupService | Health, ammunition and knife-station consumption | Net, MapService, HealthService, AmmunitionService, WeaponService, MatchService |
| CombatService | Fire, melee and throw request validation; lag-compensation history | Net, WeaponService, AmmunitionService, DamageService, HealthService, SpawnService, AntiCheatService, MatchService, PlayerDataService, ProjectileService |
| PolicyComplianceService | PolicyService lookups; fail-closed paid-random eligibility | AuditService |
| InventoryService | Ownership queries, validated loadout presets | Net, PlayerDataService, AuditService |
| ProgressionService | XP and levels inside economy transactions; Level attribute | PlayerDataService |
| EconomyService | Wallet state, match rewards (anti-farming, hourly caps), `EconomyState`/`Reward` | Net, PlayerDataService, MatchService, ProgressionService, InventoryService, PolicyComplianceService, AuditService |
| CrateService | Crate validation at boot, server RNG, atomic idempotent opening (coins or tokens) | Net, PlayerDataService, EconomyService, PolicyComplianceService, AuditService |
| TrainingService | Training dummies at DummySpot markers (standard hitbox, reset after knockdown) | MapService |
| PortalService | Portal and station prompts; whitelisted teleports with retry and failure recovery | Net, PlayerDataService, MapService, AuditService |
| TutorialService (hub only) | Tutorial sessions, server-observed steps, one-time reward | Net, PlayerDataService, EconomyService, TrainingService, WeaponService, PickupService, CrateService, InventoryService, HealthService, AmmunitionService, AuditService |
| PartyService (hub only) | In-server parties up to 8 (`Domain/PartyState`), `PartyState`, `Changed` signal | Net, PlayerDataService |
| MatchmakingService (hub only) | Queue join/leave, ticket heartbeats, assignment delivery, leader tick per destination, reconnect offers | Net, PlayerDataService, PartyService, PortalService, AuditService |
| PrivateMatchService (hub only) | Private match options and hosting (reserve server, write record, teleport party) | Net, PlayerDataService, PartyService, PortalService, MapService, AuditService |
| ReservedMatchService (arena only) | Reserved-server admission, start/cancel by arrival, reconnect records and expiry, return to hub | PlayerDataService, MatchService, PortalService, AuditService |
| ServerBrowserService (both) | Arena public servers advertise themselves; hub lists and joins them | Net, MapService, MatchService, PortalService |

`PortalService` additionally provides `TeleportReserved` (group teleport with an access code), `JoinInstance` (server browser) and `SendToHub` (return to hub, kick if the hub is unreachable and the caller asks), and enforces the tutorial gate on arrival in arenas (D-051).

Services required by the directive but not yet built (RankedService, LeaderboardService, MonetizationService and the rest) are deliberately absent. No placeholder modules exist (directive §2.7); see BACKLOG.md.

### Cross-service events

```
HealthService.Died(player, cause?, position)
        │
        ▼
DamageService ──► Eliminated{Victim, Killer?, WeaponId, Kind, Headshot, Assists, Position}
                         │
                         ▼
                   MatchService ──► KillFeed / Eliminated / Announcement / Scoreboard (network)
                                └─► PlayerDataService:Update (persistent stats)
                                └─► SpawnService:RecordDeath, respawn after mode delay
WeaponService.KnifeReplaced(player, throwId) ──► ProjectileService removes that knife
PlayerDataService.ProfileLoaded(player, profile) ──► MatchService joins and spawns the player
                                                 └─► EconomyService pushes EconomyState
MatchService.EliminationScored(event, streak, matchId, seq) ──► EconomyService: RewardPolicy → one transaction per beneficiary
MatchService.MatchFinished(result) ──► EconomyService: match XP and victory coins
                                  └─► ReservedMatchService: clear reconnect records, return everyone to the hub
PartyService.Changed(userIds) ──► MatchmakingService cancels those players' tickets
Net.Violation(player, kind, remote, detail) ──► AntiCheatService:Report
```

## 5. Client controllers

| Controller | Responsibility |
|---|---|
| SnapshotController | Fetches the initial session snapshot once the profile is loaded |
| InputController | Action bindings for keyboard/mouse, gamepad and touch (ContextActionService); input family detection |
| SettingsController | Applies, persists and edits settings; settings panel |
| CameraController | Scripted first/third-person camera, collision, FOV, sensitivity, recoil (D-007) |
| ViewmodelController | First-person weapon model and procedural motion (DEV-ANIM-001) |
| EffectsController | Tracers, impacts, muzzle flash, damage numbers, non-graphic elimination fade |
| AnimationController | Procedural arm and torso aim poses for every character (DEV-ANIM-001) |
| WeaponController | Predictive firing, melee targeting, throwing, reload, equip; mirrors `LoadoutState` |
| HUDController | Combat HUD, scoreboard, kill feed, elimination screen, damage direction |
| NotificationController | Toast messages, reward and level-up notices |
| InventoryController | Client mirror of wallet, level, inventory and loadout; crate and loadout requests |
| ArmoryController | Collection window: Armory tab (owned weapons, stats, equip) and tab host |
| CrateController | Crates tab: per-item odds before purchase, open (coins or token), result reveal |
| SpectatorController | Duel spectating of surviving players |
| VoteController | Map vote panel during intermission |
| LobbyController | Portal and station prompts, PLAY / HUB menu, teleport status |
| TutorialController (hub only) | Tutorial panel and client-checked steps |
| MatchmakingController | Queue banner (cancel), reconnect banner, server browser, private host panel |
| PartyController | Party panel: members, leader actions, invites |

`MatchmakingController` and `PartyController` declare no `Roles`: they load in every place and build their UI only when `PlaceConfig.Role == "Hub"`. `LobbyController` runs in every place and depends on both (it opens them from the PLAY menu). Marking them hub-only would leave the arena's controller graph with unknown dependencies and abort client boot there; the per-role boot test in `Integrity.spec` guards this.

## 6. Combat flow (one rifle shot)

```
Client (WeaponController)                         Server
─────────────────────────                         ──────
screen-centre ray -> aim point
origin = standardized head (D-012)
spread applied per pellet
predict hits vs Shared/Combat/Hitbox
local tracer, recoil, ammo -1
FireWeapon{Slot, ShotId, ClientTime, Origin,  ──► Net: argument count, rate limit, schema
           Direction, Hits[]}                     CombatService:
                                                    alive and in an active match
                                                    slot == server-equipped slot
                                                    equip delay elapsed
                                                    FireCadence (spacing + sustained rate)
                                                    AmmunitionService:Consume
                                                    spawn protection ends (attacker)
                                                    RewindTime(clamped to 0.35 s)
                                                    per hit: HitValidator vs rewound hitbox + LOS
                                                    DamageCalculator (archetype stats)
                                                    DamageService:Apply
                         ◄── HitConfirmed (shooter), DamageTaken (victim),
                             ShotFired (others, unreliable), KillFeed...
hit marker only on HitConfirmed
```

## 7. Persistence

`ProfileStore` implements session locking over an adapter with `UpdateAsync` semantics. `DataStoreAdapter` wraps the real DataStore, and `tests/lib/MemoryDataStore` is a test double that never ships. Store names are suffixed with the environment (`Core/Environment`). Unknown places resolve to Development, so production data is only reachable from configured production PlaceIds. See DATA_SCHEMA.md.

## 8. Places

One experience, several places, one codebase (D-030):

| Project | Role | Mode | Notes |
|---|---|---|---|
| `places/hub.project.json` | Hub | Lobby | Tutorial, portals, stations, range |
| `places/ffa.project.json` | Arena | FreeForAll | Same as `default.project.json` plus PlaceConfig |
| `places/tdm.project.json` | Arena | TeamDeathmatch | |
| `places/duel1v1.project.json` | Arena | CasualDuel1v1 | |
| `places/duel2v2.project.json` | Arena | CasualDuelTeam | `TeamSize = 2`; 3v3/4v4 are copies with another TeamSize |

`ReplicatedStorage.PlaceConfig` (attributes `Role`, `Mode`, `TeamSize`, optional `Map`) is read by `Shared/PlaceConfig`. Modules may declare `Roles`, and both `Main` scripts skip modules that are not for the current role. The integrity tests check each role's module subset boots. Travel goes through `PortalService` to the PlaceIds in `Config.Places`. The tutorial runs inside the hub rather than in its own place: it needs the hub's range, pickups and stations.

## 9. Matchmaking and reserved servers (Phase 5)

All cross-server state lives in MemoryStore sorted maps (`Config.Matchmaking.StoreNames`), accessed through `Matchmaking/MemoryStoreAdapter` (lazily created maps, so constructing one can never fail during Init). The pure logic (`Matchmaking/Queue`, `Matchmaking/Matchmaker`, `Domain/MatchFormer`, `Domain/ReservedRoster`, `Domain/PartyState`) is unit-tested against `tests/lib/MemorySortedMap.luau` (D-041).

| Map | Key | Value | TTL |
|---|---|---|---|
| `CB_MM_Tickets_<destination>` | ticket id (sort key `CreatedAt`) | ticket `{ Id, Destination, Members, CreatedAt, HubJobId, Retries }` | 120 s, refreshed every 30 s |
| `CB_MM_Users` | `u<userId>` | `{ TicketId, Destination, ExpiresAt }` (duplicate prevention) | 120 s, refreshed with the ticket |
| `CB_MM_Assign` | ticket id | `{ PlaceId, AccessCode, PrivateServerId }` or `{ Rejected = true, Reason }` | 120 s |
| `CB_MM_Leases` | `lead:<destination>` | `{ Holder = JobId, ExpiresAt }` | 15 s |
| `CB_MM_Matches` | `PrivateServerId` | match record (mode, teams, access code, private settings) | 3 h |
| `CB_MM_Active` | `u<userId>` | reconnect record `{ PlaceId, AccessCode, Destination, ExpiresAt }` | 3 h |
| `CB_MM_Servers_<destination>` | `JobId` (sort key `-players`) | `{ JobId, Players, MaxPlayers, Map, Phase, UpdatedAt }` | 45 s, refreshed every 15 s |

**Ticket lifecycle.** The party leader sends `JoinQueue`. The hub checks party limits and tutorial completion, and `Queue.Enqueue` claims a user-index entry per member, rolling back on any conflict, before writing the ticket. While queued, the owning hub heartbeats ticket and index entries; an abandoned ticket (crashed hub) expires on its own. `LeaveQueue`, a party change or a member leaving cancels the ticket.

**Leader tick.** Every 3 s, each hub tries `Queue.AcquireLease` for each queued destination; only the holder runs `Matchmaker.Tick`. It reads up to 100 unclaimed tickets oldest first, forms matches with `MatchFormer` (parties never split; oldest ticket always included; relaxed start for TDM, D-043; greedy, D-050), atomically claims every ticket of the match (`Queue.Claim`; if another live claim holds any of them, it releases its own claims and skips the match, so overlapping leaders can never assign a ticket twice), calls `TeleportService:ReserveServer`, writes the match record under the returned `PrivateServerId`, then writes an assignment per ticket and removes the ticket. Tickets larger than a team are rejected with an assignment `{ Rejected = true, Reason = "PartyTooLarge" }`. A failed `ReserveServer` leaves the tickets queued for the next tick.

**Assignment delivery.** Every 2 s the owning hub polls assignments for its tickets and teleports the members with `TeleportOptions.ReservedServerAccessCode`. On failure the ticket is requeued with its original `CreatedAt` (front of the line) up to `MaxTeleportRetries` (2), then cancelled.

**Reserved server lifecycle** (`ReservedMatchService`, `MatchService`). The server loads its record before boot. Only rostered players are admitted; others are sent to the hub. Each admitted player gets a reconnect record. The match starts when everyone has arrived, or at the 45 s deadline if playable (both teams present in team modes); otherwise it is cancelled and everyone returns to the hub. The server runs exactly one match (phase `Closed` afterwards, D-047) and returns everyone to the hub 15 s after it ends, clearing reconnect records.

**Reconnect flow.** On disconnect, the player's entry and team are kept for 90 s (D-045). In a duel, the disconnect costs the current round, and absent duelists sit out each round start (D-046). On loading into the hub, `MatchmakingService` reads `CB_MM_Active` and offers `ReconnectOffer`; `RequestReconnect` teleports back with the stored access code. When the window expires, `MatchService:ForgetPlayer` removes the player (a duel team left empty forfeits).

**Private matches.** `PrivateMatchService` reserves a server of the base mode's place and writes a record with `Private = true`, `BaseMode` and `Settings`. On that server `MatchContext.ModeConfig` derives a mode with `AwardsProgression = false` and no map vote, using the chosen duration and score limit.

**Server browser.** Public arena servers (not reserved, not player-owned, not Studio) advertise into `CB_MM_Servers_<mode>` and remove their entry on shutdown. The hub lists non-full servers (`GetServers`) and joins one with `TeleportOptions.ServerInstanceId` (`JoinServer`).

**Not implemented.** Cross-server party invites (D-044) and latency-aware matching: Roblox gives the matchmaker no cross-server latency data.

## 10. Performance notes

- Lag-compensation history: 20 Hz × 1 s per player (22-entry ring buffer).
- Movement sampling: 4 Hz per player.
- Pickup polling: 10 Hz over at most 20 players × the map's pickups.
- Scoreboard broadcasts are batched to at most 2 Hz. Cosmetic shot replication uses `UnreliableRemoteEvent`.
- Autosave: one `UpdateAsync` per player per 60 s, skipped when the request budget is low.
- Matchmaking MemoryStore traffic per hub: one lease `UpdateAsync` per queued destination every 3 s, an assignment `GetAsync` per local ticket every 2 s, heartbeats per local ticket every 30 s, plus one `GetRangeAsync` per leader tick. Each public arena writes one directory entry every 15 s.
- These have not been profiled on devices yet (TEST_PLAN.md §4).
