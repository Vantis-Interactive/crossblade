# Security and Threat Model

Scope: the Phase 0–2 build (Free-for-All combat vertical slice). The design follows the directive's defence-in-depth requirement (spec §25). Security is built into each system rather than deferred to Phase 8. Phase 8 expands administration and moderation (backlog SEC-01 to SEC-08).

Status vocabulary follows BACKLOG.md. A mitigation listed as "tested" means a named test in `tests/specs/` exercises its logic and passed under Lune. None of the mitigations has yet been verified against a real exploit client in a live Roblox server (see "Security review of Phase 2").

## 1. Assets to protect

| Asset | Why it matters | Where it lives |
|---|---|---|
| Player profiles: currency, inventory, statistics, settings | Real-money value (Robux-purchased currency from Phase 7); player trust | DataStore `Crossblade_PlayerData_<Environment>`, key `player_<UserId>` (`src/server/Data/ProfileStore.luau`) |
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
                                         |   DataStoreService
 ---- RemoteEvents / RemoteFunction ---->|
 <--- replicated state + server events --|
```

- **Everything from the client is untrusted.** That includes remote arguments, timestamps, positions, directions, claimed hits and zones, settings values, and the position and velocity of the client's own character. Roblox gives clients network ownership of their own character's physics, so the server sees whatever position the client reports.
- **ReplicatedStorage is public.** Every module in `ReplicatedStorage.Shared` (configuration, contracts, combat maths, hitbox geometry) is readable by any exploiter. Nothing in it grants authority: it holds data and pure functions that the server re-runs with its own inputs.
- **The server is the only authority** for health, damage, ammunition, equip state, knife state, pickups, spawn protection, scores and persisted data.

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
| T14 | Item duplication | Phase 2 has no item grants beyond starter weapons. `Transactions.Apply` gives the all-or-nothing, idempotent mutation primitive for Phase 3. The session lock ensures that only one server can write a profile. | `src/server/Data/Transactions.luau`, `ProfileStore.luau` | Transactions: "repeated transaction requests cannot duplicate rewards", "is all-or-nothing: a failing mutation leaves the profile untouched". ProfileStore: "a second server cannot load while the first holds the session" | Low for Phase 2. Re-assess at ECO-01 and ECO-04. |
| T15 | Currency manipulation | No currency mutation exists in Phase 2. Earned and purchased balances are separate fields (`Currency.Earned` / `Currency.Purchased`). | `src/server/Data/Schema.luau` | — | Re-assess at ECO-01. |
| T16 | Match reward farming | No rewards in Phase 2. `GameModes.Private.AwardsProgression = false`. Anti-farming is ECO-06. | `src/shared/Config/GameModes.luau` | Foundation: "private matches cannot generate normal progression rewards" | Re-assess at ECO-06. |
| T17 | Ranked boosting | Not applicable to Phase 2 (RNK-07). | — | — | — |
| T18 | Duplicate purchase fulfilment | Not applicable to Phase 2 (MON-01). Receipts will be recorded through `Transactions.Apply`, using the `PurchaseId` as the transaction id, inside the session-locked profile. | `Transactions.luau`, `Schema` (`Purchases.Receipts`) | Transactions tests (primitive only) | Re-assess at MON-01. |
| T19 | Unauthorized administrator access | No administrator commands exist in Phase 2, so there is no attack surface. RBAC is SEC-01. | — | — | Re-assess at SEC-01. |
| T20 | Data loss or overwrite | A failed, refused, corrupt, future-version or migration-failed load never writes. Saves verify lock ownership. See DATA_SCHEMA.md. | `ProfileStore.luau`, `PlayerDataService.luau` | ProfileStore: "failed data loads cannot erase existing profiles (store outage)", "never overwrites corrupt records", "refuses data written by a newer schema version", "does not write when a migration fails", "refuses to save when another server has taken the lock" | Low. |
| T21 | Settings abuse (FOV or sensitivity outside competitive limits) | The server sanitizes every saved setting with `Settings.Sanitize`, clamping to `Config.Camera` limits. The client clamps the same way. | `src/shared/Settings.luau`, `PlayerDataService` (`SaveSettings`) | Foundation: "clamps field of view and sensitivity to competitive limits", "replaces invalid values with defaults" | Low. A modified client can render any FOV locally; this is cosmetic, but it can extend visual awareness. |
| T22 | Spawn-protection abuse | Protection ends immediately when the protected player fires, melees or throws (`SpawnService.EndProtection`, called from CombatService). Protected players take no damage. | `SpawnService.luau`, `DamageService.Apply` | Logic is not unit-tested (Roblox-bound). Needs Studio verification. | Low. |
| T23 | Pickup theft or remote triggering | Pickups have no client trigger. The server polls root proximity (radius 4, height 5) and consumes only when the pickup would have an effect. | `PickupService.luau`, `src/server/Domain/PickupState.luau` | Health: "are not consumed at full health or when dead", "ammo pickups are only consumed when rounds were actually added", "a player cannot exceed 150 HP from healing" | Low. Movement spoofing can reach pickups faster (T8). |
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

**Limitation:** records are lost when the server shuts down. Durable cross-server storage and the dashboard reader are SEC-08 and SEC-02.

## 8. Secrets and replicated code policy

- No secrets, API keys, webhook URLs, admin lists or privileged logic may be placed in `ReplicatedStorage`, `StarterPlayer` or anything else that replicates. Phase 2 has no secrets.
- Server code lives only under `ServerScriptService.Server` (`default.project.json`).
- `scripts/verify-place.luau` fails the build if any `Script` or `LocalScript` exists under `ReplicatedStorage`. It also asserts that every required server service is a ModuleScript under ServerScriptService.
- Future external credentials, such as analytics endpoints, must use Roblox Secrets (`HttpService:GetSecret`) and never source files.

## 9. Administration and moderation (planned)

No administrator, moderator or support commands exist yet, so none can be abused. The planned design is SEC-01 to SEC-06:
- Role-based access control (Owner, Administrator, Moderator, Support Agent, Content Manager, Read-Only Analyst), with every privileged action authorized on the server against a server-only role table.
- Every action audited with administrator, target, action, reason, timestamp and evidence.
- Two-person or confirmation safeguards for high-impact economic changes and mass sanctions.
- Use of Roblox's own moderation and communication features (TextChatService filtering, reporting) rather than bypassing them.

## 10. Security review of Phase 2: known gaps

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
