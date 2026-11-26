# Operations Handbook

**Status:** Crossblade is not live. This handbook defines the procedures and lists the signals the current code emits. Dashboards, paging and remote configuration do not exist yet; their phases are marked.

## 1. Incident severity

| Severity | Definition | Examples | Response target |
|---|---|---|---|
| SEV-1 | Data loss or corruption risk, or the game unplayable for most players | Profiles failing to save, mass `Corrupt` kicks, servers failing to boot | Immediate; owner informed |
| SEV-2 | Core loop broken for many players, or an active exploit | Combat not registering, a widespread speed or damage exploit, matchmaking trapping players | Within 1 hour |
| SEV-3 | Degraded feature with a workaround | HUD element broken, pickups not respawning on one map | Next business day |
| SEV-4 | Cosmetic issue | Visual effect glitch | Backlog |

Every SEV-1 and SEV-2 incident gets a blameless post-incident review recorded in `docs/DECISIONS.md` (if a decision changes) or `CHANGELOG.md`.

## 2. Monitoring plan

### Signals available now

All are emitted through `Shared/Util/Logger.luau` and visible in the Roblox Developer Console (server log) for each server:

| Signal | Log scope / message | Meaning |
|---|---|---|
| Boot | `[Boot] server booted {modules, ms}` | All services initialized. An `Init failed` error aborts boot. |
| Data store selected | `[PlayerData] using DataStore {store, environment}` | Confirms the environment and store name |
| Studio ephemeral mode | `[PlayerData] DataStores unavailable in Studio; running in NON-PERSISTENT mode` | Studio only (D-009) |
| Load failure | `[PlayerData] profile load failed {player, failure, detail}` plus `[Audit] Data:KickedForData` | See DATA_SCHEMA.md §4 |
| Autosave deferred | `[PlayerData] autosave deferred: low request budget` | DataStore budget pressure |
| Autosave failed | `[PlayerData] autosave failed; will retry next cycle` | Transient store error |
| Final save failed | `[PlayerData] final save failed` plus `[Audit] Data:FinalSaveFailed` | **SEV-1 if widespread** |
| Security alert | `[Audit] Security:SuspicionReviewThreshold {userId, score, lastSignal, detail}` | Player needs review |
| Loadout rejected | `[Audit] Security:LoadoutRejected` | Saved preset referenced an unowned or invalid weapon |
| Health anomaly | `[Audit] Security:UnexpectedHealthIncrease` | Something other than HealthService raised health |
| Handler errors | `[Net] handler <Remote> failed` / `invoke ... failed` | Server bug triggered by a client request |
| Round lifecycle | `[Match] round started` / `round finished` | Match loop health |

### Planned (Phase 10 / Phase 12)

- Aggregated metrics across servers: AnalyticsService custom events, plus an external sink through a Roblox Secret (never a hard-coded URL).
- Dashboards: concurrent players, profile load success rate, save failure rate, request budget headroom, suspicion alerts per hour, remote handler error rate, server FPS and heartbeat, memory.
- Alerting thresholds: profile load failure > 1% over 5 minutes is SEV-1; final save failures > 0.1% is SEV-1; handler error rate spikes are SEV-2.
- Durable audit storage and a review UI (SEC-08, SEC-02).

## 3. Runbooks

### 3.1 DataStore outage

Symptoms: `StoreError` kicks on join ("Roblox data services are unavailable right now"), autosave failures, final-save failures.

1. Check the Roblox status page for DataStore incidents.
2. **Do not** add fallbacks that let players play without a loaded profile. The fail-closed behaviour is what protects existing data (spec §24).
3. Loaded players keep playing. Autosave retries every 60 s, and the lock stays valid for 300 s.
4. If an outage outlasts the session lock timeout, players on other servers may be able to take over stale locks. The locked server then sees `LockLost` on its next save and kicks the player, so no double-write occurs.
5. After recovery, sample affected players' records (version history) for lost progress. Restore per DATA_SCHEMA.md §9 with owner approval for production.

### 3.2 Session lock contention ("Locked" kicks)

1. One-off occurrences are normal when a player rejoins quickly. The load retries with backoff for about 20 s while the previous server releases the lock.
2. If one player is kicked repeatedly: their previous server may be stuck or slow to shut down. Locks become claimable 300 s after their last refresh. Advise the player to wait 5 minutes.
3. Widespread lock kicks point to a server that is alive but not releasing. Check for `final save failed` errors and shut down affected servers. Never clear locks in bulk while servers that may hold those players are running.

### 3.3 Suspicion alert review

1. Find `Security:SuspicionReviewThreshold` records (server log today; dashboard from SEC-02).
2. Review the evidence: signal kinds, recent `InvalidShot` reasons, movement corrections, and the player's statistics (`Stats.ShotsHit / ShotsFired`, `Headshots`).
3. Discount latency patterns. Sporadic `InvalidShot` reasons such as `MissedRewoundHitbox` or `NoLineOfSight` from high-ping players are expected. Repeated `OriginMismatch`, `TooManyPellets`, `DuplicatePellet`, `FutureTimestamp`, `MalformedPayload` or `Impossible` movement signals are strong indicators.
4. Sanctions are manual and require recorded evidence. There are no automatic bans (SECURITY.md §6). Sanction and appeal tooling is SEC-04.
5. Feed confirmed false positives back into threshold tuning (SEC-07).

### 3.4 Emergency feature disablement

Flags live in `src/shared/Config/FeatureFlags.luau`:

| Flag | Default | Effect when false |
|---|---|---|
| `ThrownKnives` | true | Client and server ignore knife throws; slash and stab still work |
| `DamageNumbers` | true | Default for the damage-number setting |
| `MovementAntiCheatCorrection` | true | Impossible movement is reported but not corrected |
| `KickOnSuspicion` | false | When true, players above `KickThreshold` (150) are removed from the server (not banned) |

**Current limitation:** flags are static source values. Changing one requires editing the file, running `./scripts/verify.sh`, and re-publishing, which takes effect as servers restart. Remote, versioned flag overrides with rollback are a Phase 12 deliverable (spec §28). Every flag must leave the game playable when toggled.

### 3.5 Balance change workflow

1. Edit the archetype in `src/shared/Config/Weapons/Archetypes.luau`, or other configuration such as `Pickups`, `GameModes` or `Combat`. Never put stats on catalog entries (D-008). `WeaponCatalog.Validate` rejects them.
2. Update the tests that pin values from the specification (`tests/specs/WeaponCatalog.spec.luau`, `Ammo.spec.luau`, `Health.spec.luau`, `Foundation.spec.luau`). A change from a specification value needs owner approval (directive §2) and a `DECISIONS.md` entry.
3. Run `./scripts/verify.sh`.
4. Playtest in Studio with at least 2 players; check time-to-eliminate and handling.
5. Record the change in `CHANGELOG.md` and the patch notes. Deploy per DEPLOYMENT.md.

### 3.6 Server boot failure

`Loader.Boot` aborts if any service `Init` fails (`<Service>.Init failed: ...`). This is intentional: a half-wired server is worse than none. Roll back to the last good release (DEPLOYMENT.md §6), then fix the failing Init, typically a configuration validation such as a map with no spawn points (`MapService`).

## 4. Live-operations cadence (planned)

From spec §28. **None of this is implemented.** It depends on Phases 3, 7 and 12 (versioned content configuration, scheduled releases, remote flags, promo codes and announcements).

| Cadence | Activities |
|---|---|
| Daily | Rotating challenges, shop rotation, login rewards |
| Weekly | New content, rotating crates, weekly challenges |
| Monthly | Major update, new maps, weapon balance changes, feature improvements |
| Every 60 days | New season, battle pass, ranked season transition, seasonal rewards |
| Special events | Holiday events, anniversary, limited-time modes, community milestones |

Release schedules must be configuration, not code (spec §28). Every scheduled content release needs a rollback path: disable it by flag, or revert it by content version.

## 5. Player feedback and quality

Planned workflow (Phase 12): an in-game report entry point (SEC-03), tagging and triage by severity (§1), a weekly review of top issues, and post-release quality reviews after every monthly update.
