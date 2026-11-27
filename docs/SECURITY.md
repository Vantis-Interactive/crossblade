# Security and Threat Model

Scope: the Phase 0–3 build (Free-for-All combat vertical slice plus economy, inventory, crates and progression). The design follows the directive's defence-in-depth requirement (spec §25). Security is built into each system rather than deferred to Phase 8. Phase 8 expands administration and moderation (backlog SEC-01 to SEC-08).

Status vocabulary follows BACKLOG.md. A mitigation listed as "tested" means a named test in `tests/specs/` exercises its logic and passed under Lune. None of the mitigations has yet been verified against a real exploit client in a live Roblox server (see "Security review of Phases 2–4").

## 1. Assets to protect

| Asset | Why it matters | Where it lives |
|---|---|---|
| Player profiles: currency, inventory, statistics, settings | Earned coins, crate-acquired weapons and levels have player value; Robux-purchased currency arrives in Phase 7; player trust | DataStore `Crossblade_PlayerData_<Environment>`, key `player_<UserId>` (`src/server/Data/ProfileStore.luau`) |
| Match integrity: eliminations, damage, scores | Fair play; later feeds rewards and ranked rating | Server memory (`MatchService`, `DamageService`, `HealthService`) |
| Combat state: health, ammunition, knife ownership, equip and cooldown timers | Direct competitive advantage if forged | Server memory (`HealthService`, `AmmunitionService`, `WeaponService`) |
| Economic idempotency records | Prevent duplicated grants and receipts | `PlayerData.ProcessedTransactions` (`src/server/Data/Transactions.luau`) |
| Audit and security evidence | Moderation decisions, appeals | `AuditService` in-memory ring buffer (durable storage: SEC-08) |
| Production data environment | Must never be written by development or test servers | `Config.Data.Environments` + `src/server/Core/Environment.luau` |

## 2. Trust boundaries

```
 UNTRUSTED                               | TRUSTED
 Client (LocalScripts, controllers,      | Server (ServerScriptService.Server)
 local physics of own character)         |   Net admission layer -> services -> pure domain rules
                                         |   DataStoreService, MemoryStoreService (matchmaking)
 ---- RemoteEvents / RemoteFunction ---->|
 <--- replicated state + server events --|
```

- **Everything from the client is untrusted.** That includes remote arguments, timestamps, positions, directions, claimed hits and zones, settings values, and the position and velocity of the client's own character. Roblox gives clients network ownership of their own character's physics, so the server sees whatever position the client reports.
- **ReplicatedStorage is public.** Every module in `ReplicatedStorage.Shared` (configuration, contracts, combat maths, hitbox geometry) is readable by any exploiter. Nothing in it grants authority: it holds data and pure functions that the server re-runs with its own inputs.
- **The server is the only authority** for health, damage, ammunition, equip state, knife state, pickups, spawn protection, scores and persisted data.
- **Teleport data is untrusted** (players can modify it). Places identify themselves from `PlaceConfig`, and reserved servers read their roster from MemoryStore by `game.PrivateServerId` (D-042).
- **Hub servers trust each other** through MemoryStore (tickets, assignments, match records, reconnect records). Any server in the experience can read and write those maps; no client can.

## 3. Attacker model

Assume an attacker with a third-party script executor in their own client. They can:

1. Call any RemoteEvent or RemoteFunction at any rate, with any number of arguments of any type: NaN, ±infinity, huge or sparse tables, Instances, wrong enums.
2. Read all replicated code and data, including every tolerance value in `Shared/Config`.
3. Move, teleport and spin their own character, change its local WalkSpeed and JumpPower, and fly or noclip locally. These replicate because the client owns its character's physics.
4. Fabricate timestamps (`ClientTime`), origins, directions and hit lists.
5. Run aim assistance: aimbot, triggerbot, or ESP (wallhack via replicated character positions).
6. Coordinate with other accounts for boosting or farming.

They **cannot** run code on the server, read ServerScriptService or ServerStorage, or write DataStores directly.

## 4. Threat register (spec §25)

Test names refer to `it(...)` blocks in `tests/specs/<file>`.

| # | Threat (spec §25) | Mitigation | Implementation | Test(s) | Residual risk |
|---|---|---|---|---|---|
| T1 | Unauthorized remote requests | Only remotes declared in `Contracts` exist. The server Net layer is the single place handlers attach. Each request must pass argument count (exactly 1), a per-player token bucket and schema validation before any handler runs, and handler errors are caught. | `src/shared/Net/Contracts.luau`, `src/server/Core/Net.luau` | NetSchema: "every client contract declares a payload schema and a rate limit". Integrity: "every remote referenced in code exists in the contracts with the right direction" | Low. Valid-shaped requests still reach handlers, which run their own state checks. |
| T2 | Malformed or malicious payloads | Declarative schemas reject wrong types, NaN, infinities, out-of-range numbers, non-integers, oversized vectors, unknown enum values, unknown struct fields, and sparse, keyed or oversized arrays. The validator is wrapped in `pcall` and fails closed. | `src/shared/Net/Schema.luau` | NetSchema: "rejects NaN, infinity and non-integers", "rejects unexpected fields (no smuggled data)", "rejects oversized, sparse and keyed arrays", "rejects non-table payloads and Instances-like values", "rejects out-of-range values and oversized vectors", "rejects unknown enum values and wrong types" | Low. |
| T3 | Fabricated eliminations | Clients never report kills or damage. A kill exists only when the server's `HealthService` health reaches 0 through `DamageService.Apply`, or through an environmental death. Each life fires `Died` at most once, and deaths from superseded or removed characters are ignored. | `HealthService.luau`, `DamageService.luau` | Health: "clamps damage to remaining health and reports death once". Domain: "environmental deaths count as deaths without crediting anyone" | Low. |
| T4 | Manipulated damage | Damage is computed on the server from archetype stats and the server-measured distance and zone (`DamageCalculator`). Client payloads have no damage field, and unknown fields are rejected (T2). Headshots need the ray to cross the head sphere with only `HeadshotTolerance` inflation; a body claim is never upgraded. Rarity cannot affect stats (D-008). | `src/shared/Combat/DamageCalculator.luau`, `src/server/Domain/HitValidator.luau`, `CombatService.luau` | HitValidator: "downgrades an unjustified headshot claim to a body hit", "never upgrades a body claim to a headshot". WeaponCatalog: "weapon rarity does not automatically increase combat power", "no combat module reads rarity" | Low. |
| T5 | Impossible attack rates | Per-weapon `FireCadence`: minimum spacing of `Interval × (1 − 0.25)` plus a token bucket (burst `Combat.FireTokenBurst = 3`, refilled at the true fire rate). Melee and throw have server cooldowns (`MeleeReadyAt`, `ThrowReadyAt`). Equip delay is enforced. Every remote also has its own rate limit (T1). | `src/shared/Combat/FireCadence.luau`, `CombatService.luau`, `WeaponService.luau` | FireCadence: "rejects shots that are impossibly close together", "bounds the sustained rate even when every shot exploits the jitter tolerance", "tolerates network jitter in packet spacing" | Low. The 0.08 s timer tolerance (`TIMER_TOLERANCE` in CombatService) allows marginally early melee and throws. |
| T6 | Invalid ammunition | Ammunition is server state only. `AmmoState.Consume` re-checks reload and magazine. Reload timing is evaluated lazily from `ReloadEndsAt`, and switching weapons cancels a reload. | `src/shared/Combat/AmmoState.luau`, `AmmunitionService.luau` | Ammo: "a player cannot fire without ammunition", "blocks firing during reload and completes exactly at the reload time", "cancelling a reload moves no rounds", "caps reserve refills at the maximum and rejects negative amounts" | Low. |
| T7 | Unauthorized weapons | Clients send slot names, never weapon ids. The weapon in each slot is resolved on the server from the persisted preset and verified against owned inventory. Unknown, wrong-slot or unowned weapons are replaced by the starter weapon and audited (`LoadoutRejected`). A thrown knife cannot attack until recovered or replaced, and recovery requires the exact throw id. | `src/server/Domain/Loadout.luau`, `WeaponService.ResetForLife`, `src/shared/Combat/KnifeState.luau` | Loadout: "a player cannot attack with an unowned weapon: unowned preset entries are replaced", "rejects unknown ids and weapons placed in the wrong slot". Knife: "a player cannot use a thrown knife before recovery", "rejects recovery of stale or foreign throw ids" | Low. |
| T8 | Speed manipulation | The server samples root positions every 0.25 s. Horizontal speed above `RunSpeed × 1.45 + 6` (≈ 37.9 studs/s for RunSpeed 22) is flagged, and suspicion is added only after 3 flags within 3 s. Falling is unrestricted; rising faster than 60 studs/s is flagged. | `src/server/Domain/MovementValidator.luau`, `AntiCheatService.luau` | Domain: "accepts running at full speed and free falling", "flags speed hacks and only reports suspicion after repeated flags" | Medium. Speeds inside the tolerance envelope (up to about 1.7× legitimate run speed) are not detected. Client-owned physics is a platform constraint. |
| T9 | Unauthorized teleportation | A single sample more than `CorrectionMultiplier = 3.0` times over the limit (≈ 113.7 studs/s horizontal, or 180 studs/s rise) returns the character to its last valid position (`MovementAntiCheatCorrection` flag) and reports `SpeedViolation`. Server-initiated teleports (spawns, corrections) open a 1.0 s grace period, and movement state is reset while dead, so respawns are never treated as teleports. | same | Domain: "corrects teleports back to the last valid position", "does not flag server-initiated teleports during the grace period" | Medium. Noclip through walls at legal speed is not detected. Hits through walls are still blocked by server line of sight (T12). |
| T10 | Invalid movement (fly, noclip) | Rise-speed check only. Shots and pickups use server positions, and line of sight is enforced. | same | as T8 | Medium. Hovering is not detected. Planned for SEC-07 tuning. |
| T11 | Hits on targets not there (lag-exploit) | Bounded lag compensation: targets are rewound to the client's `ClientTime`, clamped to at most 0.35 s in the past. Timestamps more than 0.05 s in the future are rejected. | `HitValidator.RewindTime`, `src/shared/Combat/PositionHistory.luau`, `CombatService` | HitValidator: "clamps rewind to the configured maximum", "rejects timestamps from the future", "validates a hit against where the target was, not where it is now", "rejects hits on a target that was not there at the rewound time" | Medium. An attacker can always claim the full 0.35 s rewind ("fake lag"). Bounded by design. |
| T12 | Shooting through walls or from a false origin | The origin must be within 4.5 studs of the shooter's standardized head, either rewound or current. The server raycasts line of sight from origin to hit against world geometry, excluding characters and `CanQuery = false` parts. Bullets originate at the head, not the camera (D-012). | `HitValidator.ValidateShot`, `src/server/Core/CombatQuery.luau` | HitValidator: "rejects shots whose origin is far from the shooter's head", "rejects hits through walls". Melee: "rejects attacks through walls" | Low to medium. A 4.5-stud origin allowance permits small peeks around thin cover. |
| T13 | Aimbot, triggerbot, ESP | Not prevented. Hits that follow the rules are legitimate to the server. | — | — | **High (accepted).** Needs behavioural statistics (accuracy and headshot anomaly detection, SEC-07) and moderation tooling (SEC-02, SEC-03). Spawn and position replication is inherent to Roblox. |
| T14 | Item duplication (crates, replayed requests) | Every crate open is one transaction `crate:{RequestId}`: debit, grant or compensation, statistics and history commit together or not at all. A replayed or retried RequestId returns the stored `CrateHistory` result and changes nothing (D-027). Ids must match `[A-Za-z0-9-]{8,64}`. The session lock ensures that only one server writes a profile. No trading, gifting or marketplace exists. | `CrateService.luau`, `src/server/Domain/CrateOpening.luau`, `Transactions.luau` | Economy: "a replayed request cannot charge or reward twice", "is atomic: insufficient funds leave the profile untouched". Transactions: "repeated transaction requests cannot duplicate rewards". ProfileStore: "a second server cannot load while the first holds the session" | Low. A crash after a grant but before the next save loses the grant and its id together; that is consistent, and narrowed by `RequestSave` (6 s). |
| T15 | Currency manipulation | Clients cannot send amounts. Every credit is computed on the server from config: rewards (`RewardPolicy`), compensation (`DuplicateCompensation`) and level rewards (`Leveling`). `Wallet.CreditEarned` and `Wallet.Debit` reject negative or fractional values. Prices come from server config, never from the request. Earned and purchased balances are separate. | `src/shared/Economy/Wallet.luau`, `EconomyService.luau`, `CrateService.luau` | Economy: "rejects fractional or negative amounts", "reports one total while keeping balances separate", "duplicate crate rewards provide exactly the configured compensation" | Low. |
| T15a | Client-chosen crate reward | The reward is selected on the server (`Random:NextNumber()` → `CrateOdds.Select`). The request carries only `CrateId` and `RequestId`, and the client animation displays the returned result. The disclosed odds are produced by the same function the server selects with. | `CrateService.luau`, `src/shared/Economy/CrateOdds.luau` | Economy: "stratified rolls reproduce every item's probability exactly", "seeded random rolls pass a chi-squared goodness-of-fit test", "rejects rolls outside [0, 1)" | Low. Roblox `Random` is not cryptographic; the seed is never exposed to clients. |
| T15b | Paid random items for ineligible players | Purchased coins are spendable on crates only when PolicyService returned `ArePaidRandomItemsRestricted == false`. A failed lookup, missing field or unexpected value counts as not allowed (fail closed, D-026), and the failure is audited as `PolicyLookupFailed`. Earned coins are always spent first. | `src/server/Domain/PaidRandomPolicy.luau`, `PolicyComplianceService.luau`, `Wallet.Debit` | Economy: "ineligible users cannot spend purchased coins on paid randomized rewards", "failed policy lookups block restricted purchases", "blocks restricted users", "eligible users spend earned coins first, then purchased" | Low. Purchased coins cannot yet be bought (MON-01), so the path is exercised by tests only. |
| T15c | Crates generating currency | Every crate is validated at boot: odds sum to 100, each rarity with odds has items, probabilities sum to 1, price is valid, compensation is configured, and expected compensation for an all-owned player is below the price. Invalid crates are disabled and audited (`CrateDisabled`). | `CrateOdds.Validate`, `CrateService.Init` | Economy: "every crate passes validation…", "crates cannot generate net coins for a player who owns everything", "validation rejects broken crates" | Low. The Basic crate sink is only 2% (ECONOMY.md §6; owner decision pending). |
| T16 | Match reward farming (self, cooperative and alt accounts, private servers, server hopping) | No reward without an attacker or for killing yourself. The same killer → victim pair is rewarded at most 3 times per 300 s, after which nobody is paid. No rewards with fewer than 2 loaded players, in `AwardsProgression = false` modes, or in player-owned private servers. Persisted hourly caps (2,000 coins and 20,000 XP), audited as `RewardCapped`. Reward ids are unique per server, round and death sequence, so an event cannot pay twice (D-024). | `src/server/Domain/RewardPolicy.luau`, `EconomyService.luau`, `Config/Economy.luau` | Economy: "stops rewarding repeated farming of the same victim", "caps match rewards per rolling hour", "pays nothing for self, environmental or disabled-mode eliminations". Foundation: "private matches cannot generate normal progression rewards" | Medium. Rotating many alt victims, each within the pair limit, is bounded only by the hourly cap. Behavioural detection is SEC-07. |
| T17 | Ranked boosting | Not applicable yet (RNK-07). | — | — | — |
| T18 | Duplicate purchase fulfilment | Not applicable yet: no developer products exist (MON-01). Receipts will be recorded through `Transactions.Apply`, using the `PurchaseId` as the transaction id, inside the session-locked profile. | `Transactions.luau`, `Schema` (`Purchases.Receipts`) | Transactions tests (primitive only) | Re-assess at MON-01. |
| T19 | Unauthorized administrator access | No administrator commands exist yet, so there is no attack surface. RBAC is SEC-01. | — | — | Re-assess at SEC-01. |
| T20 | Data loss or overwrite | A failed, refused, corrupt, future-version or migration-failed load never writes. Saves verify lock ownership. See DATA_SCHEMA.md. | `ProfileStore.luau`, `PlayerDataService.luau` | ProfileStore: "failed data loads cannot erase existing profiles (store outage)", "never overwrites corrupt records", "refuses data written by a newer schema version", "does not write when a migration fails", "refuses to save when another server has taken the lock" | Low. |
| T21 | Settings abuse (FOV or sensitivity outside competitive limits) | The server sanitizes every saved setting with `Settings.Sanitize`, clamping to `Config.Camera` limits. The client clamps the same way. | `src/shared/Settings.luau`, `PlayerDataService` (`SaveSettings`) | Foundation: "clamps field of view and sensitivity to competitive limits", "replaces invalid values with defaults" | Low. A modified client can render any FOV locally; this is cosmetic, but it can extend visual awareness. |
| T22 | Spawn-protection abuse | Protection ends immediately when the protected player fires, melees or throws (`SpawnService.EndProtection`, called from CombatService). Protected players take no damage. | `SpawnService.luau`, `DamageService.Apply` | Logic is not unit-tested (Roblox-bound). Needs Studio verification. | Low. |
| T23 | Pickup theft or remote triggering | Pickups have no client trigger. The server polls root proximity (radius 4, height 5) and consumes only when the pickup would have an effect. | `PickupService.luau`, `src/server/Domain/PickupState.luau` | Health: "are not consumed at full health or when dead", "ammo pickups are only consumed when rounds were actually added", "a player cannot exceed 150 HP from healing" | Low. Movement spoofing can reach pickups faster (T8). |
| T25 | Loadout spoofing (equipping weapons not owned) | `SetLoadout` carries weapon ids, but the server checks each slot's id with `WeaponCatalog.SlotFor` and the owned inventory, rejects the whole request on any failure, and audits `LoadoutChangeRejected`. Spawn-time resolution re-validates in any case (T7). | `InventoryService.luau`, `src/server/Domain/Loadout.luau` | Loadout: "a player cannot attack with an unowned weapon: unowned preset entries are replaced", "rejects unknown ids and weapons placed in the wrong slot" | Low. The `SetLoadout` handler itself needs Studio verification. |
| T26 | Level-reward re-payment (migration or prestige reset) | Level rewards are paid only above `HighestRewardedLevel`. The v1→v2 migration sets that value to the existing level. | `src/shared/Economy/Leveling.luau`, `src/server/Data/Schema.luau` | Economy: "pays level rewards once, including milestone bonuses", "upgrades a v1 profile without retroactive level rewards and keeps existing data" | Low. |
| T27 | Teammate damage, and player damage in the hub | Every player hit (firearm, melee, thrown knife) must pass `MatchService:CanDamage`: never in Lobby mode; both players allowed to fight; victim alive; opponents only, so teammates in Team Deathmatch and duels can never be damaged. Kill and assist credit is dropped for non-opponents as a second guard. The client excludes teammates from hit prediction, but that is a convenience, not the control. | `MatchService.CanDamage`, `CombatService.luau`, `ProjectileService.luau` | Modes: "assigns newcomers to the smaller team and respects capacity", "balances an ordered list and reports overflow" (team assignment only). `CanDamage` itself is Roblox-bound and needs Studio verification | Low. |
| T28 | Teleport manipulation (arbitrary PlaceId, spoofed teleport data) | The client sends only a destination id from a fixed enum; PlaceIds come solely from `Config.Places`. Teleport data is informational: each place reads its role and mode from its own `PlaceConfig` and never from teleport data (D-030). Requests are rate-limited (2 / 0.2 s) and refused while one is in progress. | `PortalService.luau`, `src/shared/Config/Places.luau`, `src/shared/PlaceConfig.luau` | Modes: "every destination points at an implemented mode". NetSchema: "rejects unknown enum values and wrong types" | Low. |
| T29 | Tutorial step spoofing and reward farming | Steps complete strictly in order. The client may complete only the current step, and only if it is client-checked. Combat and economy steps (dummy hits, reload, knife hit, knife recovery, both pickups, crate open, loadout change) complete only from server-observed events. The reward is one transaction `tutorial-reward` that also sets `Tutorial.RewardClaimed`; replays never grant it (D-036). | `src/server/Domain/TutorialProgress.luau`, `TutorialService.luau`, `EconomyService.GrantTutorialReward` | Modes: "only accepts the current step, and only from the right source", "grants the reward exactly once" | Low. Client-checked steps (movement, camera, weapon switch, the coins step, travel intent) can be spoofed, but they cannot skip the server-checked steps before the reward. |
| T30 | Skipping the mandatory tutorial | Hub portals, `JoinQueue`, `HostPrivate` and the server browser refuse `TutorialRequired` until `Tutorial.Completed` is true (for every party member). Since Phase 5, arenas also check on arrival and send players without a completed tutorial to the hub (D-051; Studio shows a notice only). | `PortalService.refusal`, `PortalService.Init` (arena gate), `MatchmakingService.refusal`, `PrivateMatchService.host` | Needs Studio and published-place verification | Low. A failed hub teleport leaves the player in the arena (the gate does not kick). |
| T31 | Training dummy abuse | Dummy hits pass the same `HitValidator` checks as player hits (against the dummy's current root). Dummies grant no coins, XP or statistics; their only effect is tutorial progress. A `DummyId` must name a living dummy, and each hit must name exactly one target (`HitTargetAmbiguous` otherwise). | `TrainingService.luau`, `CombatService.luau` | Needs Studio verification | Low. |
| T32 | Crate token misuse | Tokens are created only by the tutorial reward transaction and are spent inside the crate transaction (`NoToken` if none), so a token cannot be spent twice or minted by the client. Token opens move no currency and are not paid random items (D-037). | `src/server/Domain/CrateOpening.luau`, `EconomyService.GrantTutorialReward` | `Economy.spec` > "a free crate token opens a crate without moving any currency", "cannot open with a token that does not exist…", "a token for one crate cannot open another" | Low |
| T33 | Map vote manipulation | One vote per UserId, only for offered options, during intermission only; rate-limited 4 / 1 s. A departing player's vote is removed. | `src/server/Domain/MapVote.luau`, `MatchService` | MapVote: "counts one vote per player, rejects invalid maps, and picks the most voted" | Low. |
| T34 | Queue spoofing and double queueing | Clients send only a destination enum; membership comes from the server's party state, and only the leader (or a solo player) can queue. A per-user index in MemoryStore lets each player hold at most one live ticket across all hub servers; a conflicting enqueue rolls back the entries it claimed. | `MatchmakingService.refusal`, `src/server/Matchmaking/Queue.luau` (`Enqueue`) | Matchmaking: "prevents a player from holding two tickets across servers", "cancel removes the ticket and frees the players" | Low. |
| T35 | Joining a reserved server uninvited | Reserved servers admit only players on the match record's roster (`ReservedRoster.Admit`); everyone else is sent to the hub (or removed if the hub is unreachable) and audited `ReservedAdmissionRefused`. `MatchService` never spawns or scores non-roster players. | `ReservedMatchService.luau`, `src/server/Domain/ReservedRoster.luau`, `MatchService` (roster guard) | Matchmaking: "admits only rostered players" | Low. |
| T36 | Tampered teleport data | Teleport data is player-modifiable and is never read. A reserved server looks up its roster, mode and settings by `game.PrivateServerId` (returned by `ReserveServer` to the hub that reserved it); a missing or malformed record fails closed and returns every player (D-042). | `src/server/Core/MatchContext.luau`, `Main.server.luau` | Matchmaking: "derives a non-progression mode from the base mode and settings", "ladder reserved matches use the recorded mode unchanged" | Low. |
| T37 | Access code leakage | Reserved-server access codes exist only in server memory and MemoryStore (match records, assignments, reconnect records). No remote ever sends an access code to a client; reconnects go through the server (`RequestReconnect`). | `Matchmaker.luau`, `MatchmakingService.luau`, `ReservedMatchService.luau` | No automated test; verified by review of every server-to-client payload (NETWORK_CONTRACTS.md §3) | Low. Any server in the experience can read the maps; that is the trust boundary. |
| T38 | Party invite abuse | Invites need explicit acceptance, expire after 60 s, are leader-only, respect the 8-player cap and only target players in the same server. Party actions are rate-limited (6 / 2 s). | `src/server/Domain/PartyState.luau`, `PartyService.luau` | Matchmaking: "supports invite, accept, and a maximum of eight members", "requires a valid, unexpired invite", "only the leader invites, kicks and promotes; leader leaving promotes the next member" | Low. Invite spam to one player is bounded by the rate limit only. |
| T39 | Private-match progression farming | Private matches derive a mode with `AwardsProgression = false` (`MatchContext.ModeConfig`): `EconomyService` grants nothing and `MatchService.TracksStats()` is false, so statistics never change (D-040). Player-owned Roblox private servers are also excluded from rewards. | `MatchContext.luau`, `EconomyService.rewardsEnabled`, `MatchService` | Matchmaking: "derives a non-progression mode from the base mode and settings"; Foundation: "private matches cannot generate normal progression rewards" | Low. |
| T40 | JobId injection in JoinServer | `JobId` is bounded to 64 characters by the schema and must match `^[%w%-]+$`; the PlaceId comes from `Config.Places`, and the usual refusals (tutorial, Studio, unconfigured) apply. An unknown JobId only makes the teleport fail. | `ServerBrowserService.luau`, `PortalService.JoinInstance` | No dedicated test (schema `String(64)` is generic and covered by NetSchema); needs published-place verification | Low. |
| T41 | Remapping onto system, movement or menu keys | Overrides are accepted only for inputs on the allow-lists (no W/A/S/D, Space, Escape, ButtonA, ...), and colliding overrides are dropped by order-independent conflict resolution (D-049). The server sanitizes before saving. | `src/shared/Bindings.luau`, `Settings.Sanitize` | Matchmaking: "never allows movement, jump, menu or unknown keys", "rejects an override that collides with another action", "round-trips through the network form and through Settings.Sanitize" | Low. |
| T42 | MemoryStore outage | Every MemoryStore call is wrapped: enqueue failures refuse with `QueueUnavailable`; a reserved server that cannot read its record fails closed; server browser returns an empty list (`Unavailable`); a failed `ReserveServer` keeps tickets queued. No progression or currency depends on MemoryStore. | `MatchmakingService.luau`, `MatchContext.Load`, `ServerBrowserService.luau`, `Matchmaker.luau` | Matchmaking: "keeps tickets queued when reserving a server fails" | Low. Matchmaking is unavailable during an outage. |
| T43 | Leader split-brain (two hubs forming matches from the same queue) | A 15 s lease per destination (`Queue.AcquireLease`) normally allows one leader. As a second, clock-independent guard, a leader must atomically claim every ticket of a match (`Queue.Claim`, per-key `UpdateAsync`) before reserving a server. If any ticket is held by another live claim, the leader releases its own claims and skips the match. Claims older than 30 s are treated as abandoned. | `src/server/Matchmaking/Queue.luau`, `Matchmaking/Matchmaker.luau` | Matchmaking: "only one server holds the leader lease until it expires", "two leaders can never claim the same ticket", "a leader skips a match whose tickets another leader already claimed" | Low. Clock skew can still let two hubs run ticks concurrently, but they cannot assign the same ticket. |
| T24 | Unexpected health increase (regeneration exploit or engine script) | The default Roblox regeneration script is overridden (`src/character/Health.server.luau`). HealthService reverts any increase it did not make and audits `UnexpectedHealthIncrease`. | `HealthService.luau` | Health: "uses 150 maximum health" (config). Revert path needs Studio verification. | Low. |

## 5. The exploitable envelope (validation tolerances)

Exploiters can read these values. They are the maximum advantage a perfectly tuned cheat can extract without failing validation. All are configuration values in `src/shared/Config/Combat.luau` unless noted.

| Parameter | Value | Effect |
|---|---|---|
| `LagCompensation.MaxRewindSeconds` | 0.35 s | Maximum rewind any shot can claim |
| `LagCompensation.MaxFutureSeconds` | 0.05 s | Client clock lead tolerated before a shot is rejected |
| `LagCompensation.SampleRate` / `HistorySeconds` | 20 Hz / 1.0 s | History resolution (interpolated) |
| `Validation.MaxOriginDeviation` | 4.5 studs | Distance allowed between the reported origin and the standardized head |
| `Validation.HitboxTolerance` | 0.9 studs | Body capsule inflation when verifying a hit; also the range allowance |
| `Validation.HeadshotTolerance` | 0.45 studs | Head sphere inflation for confirming headshots |
| `Validation.DirectionToleranceDegrees` | 4.0° plus weapon spread | Angle allowed between the reported direction and origin→hit. Spread used is `max(HipSpread, AimSpread)` |
| `Validation.LineOfSightEndPadding` | 0.5 studs | Line of sight stops short of the hit point |
| `Melee.RangeTolerance` / `ConeToleranceDegrees` | 1.5 studs / 15° | Extra reach and cone for knife attacks |
| `FireCadence` jitter tolerance | 25% (default in `FireCadence.new`) | Minimum shot spacing is 75% of the interval; the sustained rate is still bounded by the token bucket |
| `Combat.FireTokenBurst` | 3 | Shots that can bunch together after a pause |
| `CombatService` `TIMER_TOLERANCE` | 0.08 s (constant in code) | Early acceptance for equip and melee timers |
| Movement allowance (`Config/AntiCheat.luau`) | `RunSpeed × 1.45 + 6` studs/s; correction at 3× that | See T8 and T9 |

Tightening any value reduces cheat headroom but increases false rejections for high-latency players. Tune them against real play data (SEC-07) rather than guessing.

## 6. Anti-cheat response policy

Implemented in `src/server/Services/AntiCheatService.luau` and `src/server/Domain/SuspicionScore.luau`.

- **Signals are evidence, not verdicts.** Each signal adds a weight to a per-player score that decays by `DecayPerMinute = 10` points per minute.
- **No automatic bans exist anywhere in the codebase.** The directive forbids automatic permanent bans based on weak signals (spec §25).
- `ReviewThreshold = 60`: crossing it records one audited `Security:SuspicionReviewThreshold` alert, with score, last signal and detail. The alert re-arms after the score falls below 30.
- `KickThreshold = 150`: removes the player from the current server, which is not a ban, **only if** `FeatureFlags.KickOnSuspicion` is `true`. It is currently `false` until thresholds are tuned (SEC-07).
- Movement correction applies only to grossly impossible movement (§4 T9), and only while `FeatureFlags.MovementAntiCheatCorrection` is `true`, as it currently is.

Signal weights (`Config.AntiCheat.Suspicion.Weights`):

| Signal | Weight | Raised by |
|---|---|---|
| `RateLimitExceeded` | 2 | Net admission (token bucket) |
| `MalformedPayload` | 5 | Net admission (argument count or schema) |
| `InvalidShot` | 3 | CombatService: failed hit or melee validation, future timestamp, too many or duplicate pellets, throw origin mismatch |
| `ImpossibleFireRate` | 4 | CombatService: `FireCadence` returned `RateExceeded` (`TooSoon` is dropped silently because jitter can cause it) |
| `UnownedWeapon` | 15 | CombatService: no firearm resolvable in the requested slot |
| `SpeedViolation` | 6 | AntiCheatService movement sampling |

**False-positive policy.** Network jitter, packet loss and legitimate Roblox physics (ramps, falling, collisions, server corrections) all produce occasional invalid samples. The movement validator therefore ignores falling, requires repeated flags, grants grace after server teleports, and resets while the player is dead. `InvalidShot` has a low weight, so occasional latency rejections decay away. Any future sanction tooling must require human review of the evidence (SEC-04).

## 7. Audit logging

`src/server/Services/AuditService.luau` records `{Time, Category, Event, UserId, Context}` to a bounded in-memory ring buffer (500 records per server) and writes a warning-level log line. Events currently recorded:

| Category | Event | Source |
|---|---|---|
| Security | `SuspicionReviewThreshold`, `RemovedForSuspicion` | AntiCheatService |
| Security | `LoadoutRejected` | WeaponService (unowned, unknown or wrong-slot weapon in a saved preset) |
| Security | `UnexpectedHealthIncrease` | HealthService |
| Data | `KickedForData`, `FinalSaveFailed` | PlayerDataService |
| Security | `LoadoutChangeRejected` | InventoryService (SetLoadout with an unowned, unknown or wrong-slot weapon) |
| Economy | `CrateOpened` (crate, weapon, rarity, duplicate, compensation, fromPurchased) | CrateService |
| Economy | `CrateDisabled` (crate, problems) | CrateService at boot |
| Economy | `RewardCapped` (tx, applied/requested coins and XP) | EconomyService |
| Economy | `PolicyLookupFailed` | PolicyComplianceService |
| Economy | `TutorialRewardGranted` (coins, crate, count) | EconomyService |
| Data | `TutorialCompleted` | TutorialService |
| Data | `TeleportFailed` (destination, error) | PortalService |
| Data | `ReservedTeleportFailed` (place, players, error) | PortalService (`TeleportReserved`) |
| Data | `MatchTeleportFailed` (destination, retries) | MatchmakingService (assignment delivery) |
| Security | `ReservedAdmissionRefused` (reason) | ReservedMatchService |
| Data | `PrivateMatchHosted` (mode, map, players) | PrivateMatchService |

**Limitation:** records are lost when the server shuts down. Durable cross-server storage and the dashboard reader are SEC-08 and SEC-02.

## 8. Secrets and replicated code policy

- No secrets, API keys, webhook URLs, admin lists or privileged logic may be placed in `ReplicatedStorage`, `StarterPlayer` or anything else that replicates. The current build has no secrets.
- Server code lives only under `ServerScriptService.Server` (`default.project.json`).
- `scripts/verify-place.luau` fails the build if any `Script` or `LocalScript` exists under `ReplicatedStorage`. It also asserts that every required server service is a ModuleScript under ServerScriptService.
- Future external credentials, such as analytics endpoints, must use Roblox Secrets (`HttpService:GetSecret`) and never source files.

### Structural controls (static tests in `tests/specs/Integrity.spec.luau`)
These catch wiring mistakes that would otherwise disable a security control at runtime:
- Every remote used in code is declared in `Contracts` in the right direction, and every declared remote is used.
- Every service and controller declares the registry dependencies it uses, and each place role (Hub, Arena) boots without cycles or missing dependencies.
- **Signal wiring:** every `Module.Signal:Fire` targets a signal that module declares with `Signal.new()`, and every `registry.Service.Signal:Connect` (or a local bound from the registry) targets a declared signal. This check caught a missing `PickupConsumed` declaration during Phase 4 that would have broken the tutorial's server-checked Pickups step.

## 9. Administration and moderation (planned)

No administrator, moderator or support commands exist yet, so none can be abused. The planned design is SEC-01 to SEC-06:
- Role-based access control (Owner, Administrator, Moderator, Support Agent, Content Manager, Read-Only Analyst), with every privileged action authorized on the server against a server-only role table.
- Every action audited with administrator, target, action, reason, timestamp and evidence.
- Two-person or confirmation safeguards for high-impact economic changes and mass sanctions.
- Use of Roblox's own moderation and communication features (TextChatService filtering, reporting) rather than bypassing them.

## 10. Security review of Phases 2–5: known gaps

These gaps are stated plainly so that none is mistaken for a completed control:

1. **No live adversarial testing.** All mitigations are verified by unit tests of their pure logic and by static integrity checks. None has been exercised against a real exploit executor on a live server.
2. **Client-owned character physics.** Movement inside the tolerance envelope (§5), hovering and noclip at legal speed are not detected (T8–T10).
3. **Aim assistance and ESP** are not mitigated (T13). They need statistical detection and moderation (SEC-07, SEC-02).
4. **Fake-lag headroom.** Any shot may claim the full 0.35 s rewind (T11).
5. **Thrown knives are simulated without rewind** (D-011). This is a fairness gap rather than an exploit; the server simulates the projectile.
6. **`KickOnSuspicion` is off.** The only automated response is movement correction, plus a review alert that nobody can yet act on because there is no dashboard (SEC-02).
7. **Audit records are not durable** (SEC-08).
8. **Studio ephemeral data mode** (D-009) cannot run on live servers: `studioEphemeralAdapter` asserts `RunService:IsStudio()`, and `createAdapter` only selects it inside an `IsStudio()` branch.
9. **Environment mapping is empty.** `Config.Data.Environments` has no PlaceIds yet, so every live server uses the `Development` store. This is safe by design, but production data separation will only exist once the PlaceIds are configured (DEPLOYMENT.md).
10. **Selene runs with a minimal Roblox std** (D-006), so member-level API misuse is not linted.
11. **Economy reconciliation is not built** (SEC-05). Evidence today is the in-memory `Economy` audit events and per-profile `CrateHistory` (the latest 50 opens).
12. **Repeat-victim history is per server and in memory.** It resets when the victim moves to another server. The persisted hourly cap is the cross-server bound.
13. **The economy services are untested in Studio.** The rules are unit-tested; the service glue (RemoteFunction handlers, PolicyService calls, `RequestSave`) still needs the Studio checklist.
14. **Phase 4 glue is Roblox-bound.** `CanDamage`, team spawns, duel spectating, teleports and the tutorial's event hooks are untested outside Studio; teleports cannot run in Studio at all.
15. ~~The tutorial gate exists only at hub portals~~: arenas check on arrival since Phase 5 (T30, D-051).
16. ~~Crate token opens have no unit test~~: covered by `Economy.spec` since Phase 4 (T32).
17. **Matchmaking is untested end to end.** `ReserveServer`, `TeleportAsync` with access codes and cross-server MemoryStore behaviour need a published test universe; Studio can exercise none of them (DEPLOYMENT.md).
18. ~~Assignment delivery has no in-flight guard~~: fixed. `MatchmakingService` marks a ticket as delivering until its teleport attempt completes.
19. **Lease timing depends on server clocks** (T43).
20. **Parties are per server** (D-044): there is no cross-server invite path to secure yet.
