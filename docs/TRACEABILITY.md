# Requirements Traceability Matrix

Maps each major requirement in the master directive to its implementation and tests. Status values match BACKLOG.md. "Studio" means the Roblox runtime behaviour still needs the manual checks in TEST_PLAN.md §4.

| Spec § | Requirement | Implementation | Automated tests | Status |
|---|---|---|---|---|
| 2.4 | Never trust the client | `server/Core/Net.luau`, `Services/CombatService.luau`, `Domain/HitValidator.luau` | `NetSchema.spec`, `HitValidator.spec` | Done |
| 2.8 | No hardcoded balance values | `shared/Config/*` | `WeaponCatalog.spec`, `Foundation.spec` (mode config), `Health.spec` (pickups), `Ammo.spec` | Done |
| 2.10 | Error handling, retries, logging | `Util/Retry`, `Util/Logger`, `Core/Net` handler `pcall`, `Util/Loader` | `Foundation.spec` (Retry, Loader) | Done |
| 4 | Rojo, Selene, StyLua, tests | `default.project.json`, `rokit.toml`, `selene.toml`, `stylua.toml`, `tests/` | `scripts/verify.sh` | Done (Wally unused, D-004; TestEZ replaced, D-005) |
| 4 | Services communicate via documented interfaces, no cycles | `Util/Loader`, ARCHITECTURE.md §4 | `Integrity.spec` (declared dependencies, acyclic) | Done |
| 6 | 150 HP, standardized hitboxes, movement | `Config/Player`, `Combat/Hitbox`, `HealthService` | `Health.spec`, `Hitbox.spec` | Done, Studio |
| 6 | No slide, double jump, wall run, dash | Not implemented by design | none | Done |
| 6 | First/third person, collision, sensitivity, FOV limits, recoil | `Controllers/CameraController`, `Config/Camera`, `Shared/Settings` | `Foundation.spec` (Settings clamps) | Done, Studio |
| 6 | Camera cannot allow attacks through obstacles | `WeaponController` (head origin), `HitValidator` LOS (D-012) | `HitValidator.spec` > "rejects hits through walls" | Done, Studio |
| 6 | Touch and controller support | `Config/Input`, `Controllers/InputController` | none (manual M-15, M-16) | Done, Studio |
| 7 | No regeneration; pickups only; 25/50/100 HP; 10/20/30 s | `character/Health.server.luau`, `HealthService`, `Domain/PickupState`, `PickupService` | `Health.spec` | Done |
| 8 | Three-weapon loadout, switching | `WeaponService`, `WeaponController` | `Loadout.spec`, `WeaponCatalog.spec` | Done |
| 8 | Damage base values | `Config/Weapons/Archetypes` | `WeaponCatalog.spec` > "base damage values match the specification" | Done |
| 8 | Magazine and reserve values, manual reload | `Combat/AmmoState`, `AmmunitionService` | `Ammo.spec` | Done |
| 8 | Respawn restores the loadout | `SpawnService.Spawn` → `WeaponService.ResetForLife` → `AmmunitionService.Reset` | none (manual M-03) | Done, Studio |
| 8 | Knife slash, stab, throw, recovery, stations, inspect | `Combat/KnifeState`, `CombatService`, `ProjectileService`, `PickupService`, `ViewmodelController` | `Knife.spec`, `HitValidator.spec` (melee) | Done, Studio |
| 9 | Server validation list (ownership…damage) | `CombatService.onFire/onMelee/onThrow` | `HitValidator.spec`, `FireCadence.spec`, `Ammo.spec`, `Loadout.spec`, `NetSchema.spec` | Done |
| 9 | Bounded lag compensation | `Combat/PositionHistory`, `HitValidator.RewindTime`, `Config.Combat.LagCompensation` | `HitValidator.spec` > "Lag compensation…", `FireCadence.spec` (history) | Done |
| 9 | Rate limiting | `Util/RateLimiter`, `Core/Net`, `Combat/FireCadence` | `Foundation.spec`, `FireCadence.spec` | Done |
| 9 | Hit markers, damage indicators, kill feed, assists, streaks, directional damage | `HUDController`, `EffectsController`, `Domain/DamageLedger`, `Domain/MatchRules` | `Domain.spec` | Done, Studio |
| 9 | Killcam (optional), spectator | not implemented | none | Planned (CMB-16, RNK-05) |
| 9 | Non-graphic effects | `EffectsController.fadeCharacter`, `BreakJointsOnDeath = false` | none | Done, Studio |
| 10 | FFA 3 s respawn, 5 s protection ending on attack | `MatchService`, `SpawnService`, `Config/GameModes` | `Foundation.spec` (mode values) | Done, Studio |
| 10 | Intelligent spawn selection | `Domain/SpawnSelector`, `Config/Spawning` | `Domain.spec` > SpawnSelector | Done |
| 10 | Eliminator, weapon, HP and level shown | `MatchService.onEliminated` → `Eliminated`; `HUDController` | none | Done, Studio |
| 11 | Archetype-based collectibles, unique ids, profiles | `Config/Weapons/Catalog`, `Weapons/WeaponCatalog.Validate` | `WeaponCatalog.spec` | Done (3 of 150 weapons) |
| 11 | Rarity not equal to power; rarity not colour-only | D-008, `Config/Rarity` symbols | `WeaponCatalog.spec` | Done |
| 13–14 | Economy, crates, odds, compensation, PolicyService | not implemented | none | Planned (ECO-xx, MON-04) |
| 13 | Separate earned/purchased accounting; transaction ids | `Data/Schema` (`Currency.Earned/Purchased`), `Data/Transactions` | `Transactions.spec` | Foundation done |
| 15–16 | Progression, prestige, achievements, mastery, challenges | Schema fields reserved | none | Planned (PRG-xx) |
| 17 | Map contract via tags; boundaries; pickups; stations | `MapService`, `Maps/DevArena`, `HealthService` kill height | `verify-place` (structure) | Done (1 greybox map; DEV-MAP-001) |
| 18–19 | Hub, matchmaking, parties, teleports | not implemented | none | Planned (LOB-xx, NET-xx) |
| 20 | Tactical UI, responsive, scalable text, reduced motion, controller navigation | `Config/Theme`, `UI/Build`, `HUDController` (UIScale), `SettingsController` (GuiService selection) | none | Combat HUD and settings done, Studio; other screens planned |
| 21 | Audio | not implemented | none | **Blocked** (AUD-001/002) |
| 22 | Persistent statistics | `Data/Schema.Stats`; updates in `CombatService`, `MatchService`, `ProjectileService` | `ProfileStore.spec` (persistence) | Partial (counters done; leaderboards planned) |
| 24 | Versioned schema, session lock, autosave, shutdown save, retry, migration, duplicate-session protection, no default overwrite | `Data/Schema`, `Data/ProfileStore`, `PlayerDataService` | `ProfileStore.spec`, `Transactions.spec`, `Foundation.spec` (Reconcile) | Done, Studio |
| 24 | Separate dev/staging/prod data | `Core/Environment`, `Config.Data.Environments` | none | Done (PlaceIds must be configured) |
| 25 | Schema validation, rate limits, state validation, suspicion scoring, movement validation, security logging, no auto-ban on weak signals | `Core/Net`, `AntiCheatService`, `Domain/MovementValidator`, `Domain/SuspicionScore`, `AuditService`, `FeatureFlags.KickOnSuspicion = false` | `NetSchema.spec`, `Domain.spec` | Done (durable audit SEC-08 planned) |
| 25 | No secrets in replicated modules | Architecture rule; `verify-place` checks no Scripts in ReplicatedStorage | `verify-place.luau` | Done |
| 26 | Admin dashboard, RBAC | not implemented | none | Planned (SEC-01/02) |
| 27 | Tutorial | not implemented | none | Planned (LOB-06) |
| 31 | Performance targets | ARCHITECTURE.md §9 budgets | none | Not yet measured |
| 33 | Documentation set | `docs/*`, `README.md` | none | Done |
