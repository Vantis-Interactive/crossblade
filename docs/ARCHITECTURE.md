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
  server/                -> ServerScriptService.Server (never replicated)
    Main.server.luau     boot
    Core/                Net (remote admission), Environment (dev/staging/prod), CombatQuery (LOS raycasts)
    Data/                Schema (v1 + migrations), ProfileStore (session locking),
                         Transactions (idempotent atomic mutations), DataStoreAdapter
    Domain/              pure server rules: HitValidator, DamageLedger, SpawnSelector,
                         MovementValidator, SuspicionScore, PickupState, MatchRules, Loadout,
                         CrateOpening, RewardPolicy, PaidRandomPolicy
    Services/            18 services (section 4)
    Maps/DevArena.luau   temporary greybox layout (DEV-MAP-001)
  client/                -> StarterPlayerScripts.Client
    Main.client.luau     boot
    Core/                Net (client wrapper), UIState
    Controllers/         13 controllers (section 5)
    UI/Build.luau        themed UI construction helpers
  character/Health.server.luau  -> StarterCharacterScripts.Health (disables default regeneration)
tests/                   Lune test runtime, harness, specs
scripts/                 verify.sh (full pipeline), verify-place.luau (built place checks)
docs/                    this documentation set
```

## 3. Boot and lifecycle

`Shared/Util/Loader` boots both server and client:

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
| MatchService | Free-for-All rounds, scoreboard, kill feed, eliminations, respawn scheduling, stats, `GetSnapshot` | Net, PlayerDataService, DamageService, SpawnService, HealthService, MapService, WeaponService |
| ProjectileService | Thrown-knife flight, impact, ground knives, recovery | Net, WeaponService, DamageService, HealthService, MatchService, PlayerDataService |
| PickupService | Health, ammunition and knife-station consumption | Net, MapService, HealthService, AmmunitionService, WeaponService, MatchService |
| CombatService | Fire, melee and throw request validation; lag-compensation history | Net, WeaponService, AmmunitionService, DamageService, HealthService, SpawnService, AntiCheatService, MatchService, PlayerDataService, ProjectileService |
| PolicyComplianceService | PolicyService lookups; fail-closed paid-random eligibility | AuditService |
| InventoryService | Ownership queries, validated loadout presets | Net, PlayerDataService, AuditService |
| ProgressionService | XP and levels inside economy transactions; Level attribute | PlayerDataService |
| EconomyService | Wallet state, match rewards (anti-farming, hourly caps), `EconomyState`/`Reward` | Net, PlayerDataService, MatchService, ProgressionService, InventoryService, PolicyComplianceService, AuditService |
| CrateService | Crate validation at boot, server RNG, atomic idempotent opening | Net, PlayerDataService, EconomyService, PolicyComplianceService, AuditService |

Services required by the directive but not yet built (MatchmakingService, RankedService, MonetizationService and the rest) are deliberately absent. No placeholder modules exist (directive §2.7); see BACKLOG.md.

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
MatchService.EliminationScored(event, streak, round, seq) ──► EconomyService: RewardPolicy → one transaction per beneficiary
MatchService.RoundFinished(ranked, round) ──► EconomyService: match-completion XP
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
| CrateController | Crates tab: per-item odds before purchase, open, result reveal |

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

The directive calls for one experience with multiple places (hub, arenas, tutorial). Phase 2 has one place, the Free-for-All arena, built from `default.project.json`. The shared, server and client trees are written so later places can reuse them: MatchService takes its mode from `Config.GameModes`, and maps are discovered by tags. Multi-place layout and teleport flows are Phase 4–5 (LOB-xx, NET-xx).

## 9. Performance notes

- Lag-compensation history: 20 Hz × 1 s per player (22-entry ring buffer).
- Movement sampling: 4 Hz per player.
- Pickup polling: 10 Hz over at most 20 players × the map's pickups.
- Scoreboard broadcasts are batched to at most 2 Hz. Cosmetic shot replication uses `UnreliableRemoteEvent`.
- Autosave: one `UpdateAsync` per player per 60 s, skipped when the request budget is low.
- These have not been profiled on devices yet (TEST_PLAN.md §4).
