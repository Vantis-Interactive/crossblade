# Player Data Schema

Current schema version: **2** (`Schema.CurrentVersion` in `src/server/Data/Schema.luau`). v2 was introduced in Phase 3; v1 records are migrated on load (§5).

Persistence is implemented by:

| File | Role |
|---|---|
| `src/server/Data/Schema.luau` | Default record, migration chain, reconcile |
| `src/server/Data/ProfileStore.luau` | Session-locked load and save (pure; adapter injected) |
| `src/server/Data/Transactions.luau` | Idempotent all-or-nothing mutations |
| `src/server/Data/DataStoreAdapter.luau` | Production adapter over `DataStoreService` |
| `src/server/Services/PlayerDataService.luau` | Player lifecycle, autosave, shutdown, kicks |
| `src/shared/Config/Data.luau` | Store names, intervals, retry policies, limits, environments |

## 1. Storage layout

| Item | Value |
|---|---|
| DataStore name | `Crossblade_PlayerData_<Environment>`, where `<Environment>` is `Development`, `Staging` or `Production` (`Environment.StoreName()`) |
| Key | `player_<UserId>` (`Config.Data.KeyPrefix`) |
| Write API | `UpdateAsync` only. Every write is a compare-and-transform. |
| UserIds association | Every write passes `{ UserId }` as the UpdateAsync `userIds` return, supporting Roblox right-to-erasure tooling (`DataStoreAdapter.UpdateAsync`) |

### Envelope

Each key holds an envelope that wraps the player data with the session lock:

```lua
{
	Data = <PlayerData>,             -- see §2
	Lock = { JobId = string, Time = number } | nil,  -- Time is os.time() seconds
}
```

`Lock = nil` means no server currently owns the session.

## 2. PlayerData fields (v2)

Values are the defaults produced by `Schema.Default(userId, now)`.

| Field | Type | Default | Purpose | Used from |
|---|---|---|---|---|
| `UserId` | number | the player's UserId | Integrity check: loads fail with `UserIdMismatch` if it differs | Phase 1 |
| `SchemaVersion` | integer | `2` | Migration driver | Phase 1 |
| `CreatedAt` | number (os.time) | creation time | Support and analytics | Phase 1 |
| `UpdatedAt` | number (os.time) | creation time; set on every save | Support and recovery | Phase 1 |
| `Currency.Earned` | integer | `0` | Coins from match rewards, level rewards and duplicate compensation (spec §13: separate accounting). Credited only via `Wallet.CreditEarned` | Phase 3 (implemented) |
| `Currency.Purchased` | integer | `0` | Coins bought with Robux. Spendable on crates only when policy-eligible (D-026). No product credits it yet. | Phase 7 |
| `Progression.LifetimeXP` | integer | `0` | XP total; level is derived from it (`Leveling.Info`) | Phase 3 (implemented) |
| `Progression.Level` | integer | `1` | Level; replicated to the `Level` player attribute on load and after each grant | Phase 3 (implemented) |
| `Progression.HighestRewardedLevel` | integer | `1` | **v2.** Highest level whose level reward has been paid. Rewards are paid only above it, so each is paid once (D-022) | Phase 3 (implemented) |
| `Progression.Prestige` | integer | `0` | Prestige count | Phase 7 |
| `Inventory.Weapons` | map weaponId → `{AcquiredAt, Source}` | the three starter weapons, `Source = "Starter"` | Ownership: checked by `Domain/Loadout` on every spawn and by `InventoryService` on loadout changes. Crate grants use `Source = "Crate:<crateId>"` | Phase 2/3 |
| `Customization` | map | `{}` | Skins, charms and attachments per weapon | Planned (not yet used) |
| `Loadouts.ActivePreset` | integer | `1` | Selected preset index | Phase 2 |
| `Loadouts.Presets` | array of `{Primary, Secondary, Knife}` | one preset with the starter weapons | Saved loadouts. Edited through `SetLoadout` (InventoryService) after ownership and slot validation | Phase 2/3 |
| `Achievements` | map | `{}` | Unlocked achievements | Phase 7 |
| `Titles.Owned` / `Titles.Equipped` | map / string | `{}` / `""` | Player titles | Phase 7 |
| `Mastery` | map | `{}` | Weapon mastery progress | Phase 7 |
| `Competitive` | `{Rating, Deviation, Season, CurrentDivision, HighestDivision}` | `1000, 350, 0, "", ""` | Ranked rating | Phase 6 |
| `Stats.Eliminations` | integer | `0` | Incremented by MatchService | Phase 2 |
| `Stats.Deaths` | integer | `0` | MatchService | Phase 2 |
| `Stats.Assists` | integer | `0` | MatchService | Phase 2 |
| `Stats.ShotsFired` / `ShotsHit` / `Headshots` | integer | `0` | CombatService. One shot counts as one shot fired and at most one hit, regardless of pellets. | Phase 2 |
| `Stats.KnifeEliminations` | integer | `0` | MatchService (Knife or ThrownKnife kills) | Phase 2 |
| `Stats.KnivesThrown` / `KnivesHit` | integer | `0` | CombatService / ProjectileService | Phase 2 |
| `Stats.DamageDealt` | number | `0` | CombatService / ProjectileService | Phase 2 |
| `Stats.HighestKillstreak` | integer | `0` | MatchService | Phase 2 |
| `Stats.Wins` / `Losses` / `MatchesPlayed` | integer | `0` | MatchService at round end (D-016) | Phase 2 |
| `Stats.CoinsEarned` / `CratesOpened` | integer | `0` | Economy statistics: every earned-coin credit, and every crate opened | Phase 3 (implemented) |
| `WeaponStats` | map | `{}` | Per-weapon statistics | Planned (Phase 7; not yet used) |
| `MatchHistory` | array | `{}` | Recent matches (must be bounded when implemented) | Phase 6 |
| `Challenges` | map | `{}` | Challenge progress | Phase 7 |
| `BattlePass` | map | `{}` | Season progress | Phase 7 |
| `Purchases.Receipts` | map | `{}` | Durable purchase records | Phase 7 |
| `Entitlements` | map | `{}` | VIP, pass ownership and similar | Phase 7 |
| `Settings` | `Settings` table | `Settings.Defaults()` | FOV, sensitivity, aim sensitivity, perspective, crosshair style/colour/size, reduced motion, damage numbers. Sanitized by the server on save. | Phase 2 |
| `Tutorial.Completed` / `RewardClaimed` | boolean | `false` / `false` | One-time tutorial reward | Phase 4 |
| `LoginRewards.LastClaimDay` / `Streak` | integer | `0` / `0` | Login rewards | Planned (Phase 7; not yet used) |
| `Moderation.Warnings` | integer | `0` | Moderation status | Phase 8 |
| `ProcessedTransactions` | map txId → os.time | `{}` | Idempotency record (`elim:`, `round:` and `crate:` ids; ECONOMY.md §1), bounded to `Config.Data.Limits.ProcessedTransactions = 200` | Phase 3 (implemented) |
| `CrateHistory` | array of crate results | `{}` | **v2.** `{RequestId, CrateId, WeaponId, Rarity, Duplicate, Compensation, FromEarned, FromPurchased, Time}`, newest last, bounded to `Config.Economy.CrateHistoryLimit = 50`. Used to answer a replayed `OpenCrate` with the original result (D-027) | Phase 3 (implemented) |
| `Economy.HourStart` / `HourCoins` / `HourXP` | integer | `0` / `0` / `0` | **v2.** Rolling-hour match-reward counters for the anti-farming caps (D-024). Persisted so server hopping does not reset them | Phase 3 (implemented) |

Fields marked for a later phase exist now so that existing records already have the right shape. Later phases may also add fields through migrations or Reconcile.

## 3. Session locking

Configuration (`Config.Data`): `AutosaveIntervalSeconds = 60`, `SessionLockTimeoutSeconds = 300` (D-017), load retry policy `6 attempts, backoff 1 s doubling to a maximum of 8 s`, save retry policy `4 attempts, 1 s to 6 s`, with up to 25% jitter (`Shared/Util/Retry.luau`).

### Load (`ProfileStore:Load`)

Each attempt calls `UpdateAsync(key, transform)`. The transform resets its outcome variables on every invocation, because Roblox may call it more than once.

1. **Key empty** (`old == nil`): create `Schema.Default`, write it with `Lock = {JobId = this server, Time = now}`. Outcome `Loaded`, `Created = true`.
2. **Not a table, or `old.Data` not a table:** return `nil` (no write). Outcome `Corrupt`. Not retried.
3. **Lock held by another JobId and `now − Lock.Time < 300`:** return `nil` (no write). Outcome `Locked`. Retried with backoff, because the other server is usually finishing its release save.
4. **Lock absent, own, or stale (≥ 300 s old):** run `Schema.Migrate` (§5). On failure, return `nil` (no write), with outcome `FutureVersion` or `MigrationFailed`; these are not retried. On success, write the migrated and reconciled data with a fresh lock. Outcome `Loaded`.
5. An adapter error (DataStore outage) counts as `StoreError` and is retried.

### Save (`ProfileStore:Save(profile, release)`)

1. Inactive profiles (released or lock lost) are never saved: result `Inactive`.
2. A deep copy of `profile.Data` is taken before the write.
3. Transform: if `old.Lock.JobId` belongs to another server, return `nil` (no write); result `LockLost`, and the profile is marked inactive with `LockLost = true`. Otherwise write `{Data = snapshot (UpdatedAt = now), Lock = release and nil or {JobId, Time = now}}`.
4. Adapter errors are retried. After the final failure the result is `StoreError`.

### Lifecycle (`PlayerDataService`)

| Event | Behaviour |
|---|---|
| `PlayerAdded` | Load. On success: store the profile, set the `Level` and `DataLoaded` attributes, fire `ProfileLoaded`. On failure: kick with the message for that failure. A player who leaves during the load has their profile released immediately. |
| Autosave (every 60 s) | Save without release, which refreshes the lock. Deferred when `UpdateAsync` request budget < 5 (persistent mode only). `LockLost`: remove the profile and kick. `StoreError`: retry next cycle. |
| `PlayerRemoving` | Fire `ProfileReleasing`, then save with release. Failures are logged and audited (`FinalSaveFailed`). |
| `BindToClose` | Release every loaded profile in parallel; wait up to 25 s. |

## 4. Failure modes

| Outcome | Data written? | Player experience | Test (`tests/specs/ProfileStore.spec.luau` unless noted) |
|---|---|---|---|
| `Loaded` (new) | Default created | Plays | "creates a default profile with the starter loadout for a new player" |
| `Loaded` (existing) | Lock refreshed; data unchanged apart from migration and reconcile | Plays | "loads existing data without overwriting it with defaults" |
| `Locked` (live lock elsewhere) | No | Retried; then kicked: "Your data is still being saved by another server…" | "refuses to load a profile locked by another live server and does not write", "acquires the lock once the other server releases it during retries", "a second server cannot load while the first holds the session" |
| Stale lock | Lock taken over | Plays | "takes over an abandoned (stale) lock from a crashed server" |
| `Corrupt` | No (record preserved) | Kicked: "…contact support; nothing was changed." | "never overwrites corrupt records" |
| `FutureVersion` | No | Kicked: "This server is out of date…" | "refuses data written by a newer schema version" |
| `MigrationFailed` | No | Kicked: "…could not be upgraded safely…" | "does not write when a migration fails" |
| `StoreError` | No | Retried; then kicked: "Roblox data services are unavailable…" | "failed data loads cannot erase existing profiles (store outage)", "recovers from a transient outage via retry" |
| `LockLost` (on save) | No | Kicked: "Your session was opened on another server." | "refuses to save when another server has taken the lock" |
| Release | Yes, lock cleared | — | "saves while keeping the lock, and releases it on leave" |

## 5. Migrations

`Schema.Migrate(data, userId, now)`:

1. Rejects non-tables (`NotATable`) and missing or invalid versions (`InvalidVersion`).
2. Rejects `SchemaVersion > CurrentVersion` (`FutureVersion`). Data is never downgraded, which protects records during staggered server updates.
3. Applies `Migrations[n]` (from version *n* to *n + 1*) in order on a deep copy. A missing step (`MissingMigration<n>`) or a step that throws or returns a non-table (`MigrationFailed<n>`) aborts the load without writing.
4. Checks `UserId` matches (`UserIdMismatch`).
5. Runs Reconcile against `Schema.Default`.

### v1 → v2 (implemented, Phase 3)

```lua
Schema.Migrations[1] = function(data)
	data.Progression.HighestRewardedLevel = data.Progression.Level
	return data
end
```

**Why Reconcile alone was not enough.** `CrateHistory` and `Economy` have safe defaults and are added by Reconcile. `HighestRewardedLevel` does not. Its template default is `1`, so reconciling a level-30 v1 player would set it to 1, and the next XP grant would pay level rewards for levels 2 to 30 retroactively. The migration sets it to the player's current level first; Reconcile then fills only the missing tables. Test: Economy spec, "upgrades a v1 profile without retroactive level rewards and keeps existing data".

### Adding a future version (procedure)

1. Bump `Schema.CurrentVersion`.
2. Add `Schema.Migrations[n]`, a pure step that transforms a version-*n* record and returns it.
3. Update `Schema.Default` to produce the new shape directly.
4. Add tests: the old record migrates; a failing migration does not write; newer data is refused.
5. Deploy to Staging. Load a copy of real-shaped old records, then promote. Never delete a migration step; old records may appear at any time.

Migrations are only needed for structural changes: renames, type changes, moves and derived values. Purely additive fields are handled by Reconcile.

### Reconcile rule

`TableUtil.Reconcile(target, template)` adds any key present in the default template but missing from the record, recursing into nested tables. **It never overwrites an existing value**, even one whose type differs from the template. Test: Foundation spec "adds missing keys without overwriting existing values".

## 6. Transactions and idempotency

`Transactions.Apply(data, transactionId, now, limit, mutate)` (exposed as `PlayerDataService:ApplyTransaction`):

- If `transactionId` is already in `ProcessedTransactions`, it returns `AlreadyApplied` and changes nothing.
- Otherwise `mutate` runs on a deep copy. If it throws, it returns `Failed` and the profile is untouched, which satisfies the requirement that a crate purchase, reward grant and duplicate compensation cannot be partially applied.
- On success the draft is committed in place, the id is recorded with its timestamp, and the processed list is pruned to the newest `limit` (200) entries.
- `PlayerDataService:ApplyTransaction` returns `(outcome, err)`. `err` is the mutation's error string, such as `InsufficientFunds`, `InsufficientEarnedFunds` or `NotLoaded`, which CrateService passes back to the client.

**Prompt saves.** Economy mutations call `PlayerDataService:RequestSave(player)`. It schedules one save `Config.Data.PrioritySaveDelaySeconds = 6` seconds later; further calls in that window are ignored. A `LockLost` result kicks the player and a `StoreError` is left to autosave. The 6-second delay keeps within the DataStore per-key write throttle.

Tests (`tests/specs/Transactions.spec.luau`): "repeated transaction requests cannot duplicate rewards", "is all-or-nothing: a failing mutation leaves the profile untouched", "keeps the processed transaction list bounded, evicting the oldest".

**Scope note.** This makes in-memory mutations atomic and idempotent. Durability comes from the session lock (one writer) and from saving the processed ids in the same record as the balances they changed. A crash between a mutation and the next save loses both together. That is consistent, but it means grants made since the last save are lost. Phase 3 shortens that window with `RequestSave`. Phase 7 receipt handling must return `PurchaseGranted` only after a successful save (MON-01).

## 7. Environments

| Environment | Selected when | Store |
|---|---|---|
| Development | `RunService:IsStudio()`, **or** a PlaceId not listed in `Config.Data.Environments` | `Crossblade_PlayerData_Development` |
| Staging | PlaceId mapped to `"Staging"` | `Crossblade_PlayerData_Staging` |
| Production | PlaceId mapped to `"Production"` | `Crossblade_PlayerData_Production` |

`Config.Data.Environments` is currently empty: no place has been published or mapped. Unknown places default to Development, so a misconfigured place can never write production data.

**Studio ephemeral mode (D-009).** In Studio, `PlayerDataService` probes the store with one `GetAsync`. If DataStores are unreachable, it switches to an in-memory adapter, logs a warning, and notifies each player that progress will not be saved. The adapter asserts `RunService:IsStudio()`.

## 8. Size and limits

- The Roblox DataStore value limit is 4 MB per key. The default record is a few kilobytes; `CrateHistory` adds at most 50 small entries.
- Unbounded growth must be prevented in every list. Current bounds: `ProcessedTransactions` ≤ 200, `CrateHistory` ≤ 50. **Required when implemented:** `MatchHistory` (suggested ≤ 20 entries), `Purchases.Receipts` (keep it bounded or move receipts to a separate keyed store), and `WeaponStats` and `Customization`, which grow at most with catalog size (150 weapons).
- Request budget: autosave checks `GetRequestBudgetForRequestType(UpdateAsync)` and defers when it is below 5. Final saves are never deferred.

## 9. Recovery procedures

Phase 8 will provide tooling. Until then, these are manual procedures for the owner or an engineer with Open Cloud or Studio command-bar access to the store:

| Situation | Procedure |
|---|---|
| Player kicked with "Locked" repeatedly | Normally self-heals once the lock is stale (≤ 5 minutes after a crashed server). If it persists, check for a stuck server (OPERATIONS.md runbook). Clearing `Lock` manually is safe only when no server has the player loaded. |
| `Corrupt` record | The record is preserved untouched. Export it, repair the JSON by hand to a valid envelope at the current schema version (`{Data = {...}, Lock = nil}`), and write it back. Use DataStore key versioning (`ListVersionsAsync` / `GetVersionAsync`) to recover the last good version. |
| `FutureVersion` kicks after a rollback | Expected: older servers refuse newer data. Roll forward, or shut down old servers so players reach servers on the current version. Never write v(n+1) data back as v(n). |
| Player reports lost progress | Use DataStore version history for `player_<UserId>` to find the last good version and restore it with an audited manual write. Planned tooling: SEC-05 (economy reconciliation) and SEC-08. |
| Right-to-erasure request | Remove the key `player_<UserId>` from all three environment stores. UserIds are associated on every write. |
