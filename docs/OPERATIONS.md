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
| Boot | `[Boot] server booted {role, mode, modules, ms}` | All services for this place's role initialized. An `Init failed` error aborts boot. |
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
| Match lifecycle | `[Match] match service ready {mode, kind}`, `match started`, `duel started`, `match finished {match, mode, winner}` | Match loop health |
| Match tick error | `[Match] match tick failed {error}` | The match loop caught an error; the next tick retries. Repeated errors mean a stuck match (§3.10) |
| Stranded player | `[Match] respawning stranded player {player}` | Watchdog respawned a loaded player with no character; occasional is fine, frequent points to a spawn bug |
| Map loaded | `[Map] map loaded {map}` | Initial map or vote winner |
| Authored map ignored | `[Map] authored map ignored: needs MapId and Modes attributes` | A `ServerStorage.Maps` Model is missing required attributes |
| Teleport failed | `[Portal] teleport failed` / `teleport init failed {result, message}` plus `[Audit] Data:TeleportFailed` | See §3.9 |
| Tutorial | `[Audit] Economy:TutorialRewardGranted {coins, crate, count}`, `[Audit] Data:TutorialCompleted` | Reward granted once; tutorial finished |
| Economy ready | `[Economy] economy ready {rewardsEnabled}` | `false` means a private-server or no-progression mode; no rewards will be paid |
| Crates validated | `[Crate] crates validated {active}` | Number of crates offered; 13 with the current configuration |
| Crate disabled | `[Crate] crate failed validation and is disabled` plus `[Audit] Economy:CrateDisabled {crate, problems}` | A crate's odds, pool, price or EV check failed at boot; it is not offered |
| Crate opened | `[Audit] Economy:CrateOpened {crate, weapon, rarity, duplicate, compensation, fromPurchased}` | One per successful (non-replayed) open |
| Reward capped | `[Audit] Economy:RewardCapped {tx, coins, xp}` | A player hit the hourly match-reward cap; frequent occurrences for one player suggest farming |
| Policy lookup failed | `[Policy] policy lookup failed; paid random items blocked (fail closed)` plus `[Audit] Economy:PolicyLookupFailed` | Purchased coins cannot be spent on crates by that player this session |
| Loadout change rejected | `[Audit] Security:LoadoutChangeRejected {slot, weapon}` | A SetLoadout request referenced an unowned or wrong-slot weapon (possible tampering) |
| Priority save failed | `[PlayerData] priority save failed; autosave will retry` | Post-economy save failed; autosave will persist it |
| Reserved record | `[MatchContext] reserved match record loaded {mode, private}` / `reserved server has no readable match record; players will be returned` | Reserved-server boot; the second means the server fails closed (§3.16) |
| Matchmaking leader | `[Matchmaking] matchmaking tick {destination, formed, failed}` / `leader tick failed {destination, error}` | Logged by the lease holder when it formed or failed to reserve matches |
| Matchmaking in Studio | `[Matchmaking] Studio: matchmaking leader disabled (cannot reserve servers)` | Expected in Studio |
| Reserved match | `[Reserved] reserved match starting` / `reserved match cancelled: players did not arrive` | Arrival decision on a reserved server (§3.16) |
| Match teleport failed | `[Audit] Data:MatchTeleportFailed {destination, retries}` | Owner hub could not teleport a matched group; ticket requeued or cancelled (§3.14) |
| Reserved teleport failed | `[Audit] Data:ReservedTeleportFailed {place, players, error}` | `PortalService.TeleportReserved` gave up after retries |
| Admission refused | `[Audit] Security:ReservedAdmissionRefused {reason}` | Someone not on the roster (or past the reconnect window) reached a reserved server |
| Private match | `[Audit] Data:PrivateMatchHosted {mode, map, players}` | A private match was reserved |
| Instance join failed | `[Portal] instance join failed` | Server browser join failed (server closed or full) |

### Planned (Phase 10 / Phase 12)

- Aggregated metrics across servers: AnalyticsService custom events, plus an external sink through a Roblox Secret (never a hard-coded URL).
- Dashboards: concurrent players, profile load success rate, save failure rate, request budget headroom, suspicion alerts per hour, remote handler error rate, server FPS and heartbeat, memory.
- Alerting thresholds: profile load failure > 1% over 5 minutes is SEV-1; final save failures > 0.1% is SEV-1; handler error rate spikes are SEV-2.
- Durable audit storage and a review UI (SEC-08, SEC-02).

## 3. Runbooks

### 3.1 DataStore outage

Symptoms: `StoreError` kicks on join ("Roblox data services are unavailable right now"), autosave failures, final-save failures.

If the DataStore cannot even be initialized when a live server boots, the server still boots. It logs `DataStore initialisation failed on a live server`, and every profile load then fails closed: the player is kicked and nothing is written.

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

### 3.6 Disabling or changing a crate

1. **To withdraw a crate**, remove its entry from `src/shared/Config/Crates.luau`, run `./scripts/verify.sh`, and publish. There is no runtime toggle yet (Phase 12 remote config). A crate that fails validation (`CrateOdds.Validate`) is disabled automatically at boot and audited as `CrateDisabled`. Raising `Config.Economy.MinimumSinkMargin` is therefore a fast, conservative lever: crates whose expected compensation exceeds the new margin stop being offered after restart.
2. **To change odds, prices or compensation**, edit `Crates.luau` or `Economy.luau`. Values marked SPEC need owner approval and a DECISIONS.md entry. Run the tests: "every crate passes validation…" and "crates cannot generate net coins for a player who owns everything" must pass. Update the EV table in ECONOMY.md §6.
3. Removing a crate never affects owned weapons. History entries that reference it remain valid.
4. Odds shown to players always come from the deployed configuration, because client and server share `CrateOdds`. Never announce odds that differ from the config.

### 3.7 Suspected reward farming

1. Look for repeated `Economy:RewardCapped` for the same player, or one victim repeatedly appearing for one killer in the kill feed.
2. Pairs beyond 3 rewarded eliminations per 300 s already earn nothing. The hourly cap bounds the rest.
3. Review as in §3.3. Reconciliation tooling (SEC-05) and per-grant durable records are not built yet.

### 3.8 Server boot failure

`Loader.Boot` aborts if any service `Init` fails (`<Service>.Init failed: ...`). This is intentional: a half-wired server is worse than none. Roll back to the last good release (DEPLOYMENT.md §6), then fix the failing Init. Typical causes are configuration validation: a map with no spawn points, no map supporting the place's mode (`no map supports mode ...`), or a `PlaceConfig.Mode` whose mode is not implemented (`MatchService`).

### 3.9 Teleport failures

1. Player-facing: the toast "The teleport failed. Please try again." The player stays fully playable in the current place; nothing is lost.
2. `PortalService` already retries `TeleportAsync` 3 times with backoff; `TeleportInitFailed` (for example a full destination server) also reports to the player.
3. Check `Data:TeleportFailed` audit context and the Roblox status page. Widespread failures for one destination usually mean a wrong or unpublished PlaceId in `Config.Places`.
4. Arrivals that are kicked with "still being saved by another server" are session-lock contention on the destination (D-038); the destination retries the load for about 20 s before kicking. Frequent occurrences mean the source server is slow to release (§3.2).
5. Matchmaking teleports to reserved servers are covered in §3.14.

### 3.10 Stuck match or player

1. Players without a character are respawned by the MatchService watchdog every 2 s, except duel spectators while a duel round is running.
2. A duel that cannot finish (for example a stalled round) ends at the round time limit (D-033). A team whose players all leave forfeits.
3. Waiting or Countdown that never starts means fewer loaded players than the start threshold (`PlayersNeeded` in `MatchState`): Duel needs 2 × TeamSize, Team Deathmatch 2.
4. If `match tick failed` repeats, collect the error and restart the affected servers after fixing.

### 3.11 Disabling a mode or destination

1. **Fastest:** set the destination's PlaceId to 0 in `src/shared/Config/Places.luau` and re-publish the hub. Portals and the PLAY menu then refuse it with `NotConfigured`; players already in that place finish normally.
2. To stop the place itself, shut down its servers from the Roblox dashboard, or set the mode's `Implemented = false` in `Config/GameModes.luau` and re-publish that place (its servers then refuse to boot, so prefer the PlaceId route).

### 3.12 Map rotation issues

1. A vote winner that fails to load (for example an authored map without spawn points) is rejected before anything is replaced: `MapService.Load` validates the new map first, and `MatchService` logs `voted map failed to load; keeping the current map` and continues on the current map. Fix or remove the broken map from `ServerStorage.Maps` and re-publish.
2. To take a map out of rotation, remove its mode from the map's `Modes` (attribute for authored maps, `Modes` field for greybox layouts) and re-publish.
3. After a map change, pickups, training dummies, thrown knives and spawn history are rebuilt automatically on `MapChanged`.

### 3.13 Tutorial reward questions

1. The tutorial reward (500 coins and one Basic Crate token) is granted once per account, in transaction `tutorial-reward`, and recorded as `Economy:TutorialRewardGranted`.
2. `Tutorial.RewardClaimed = true` in the profile means it was granted; replays never grant it again. The crate token is listed in `EconomyState.CrateTokens` until spent.
3. A player who says they never received it but has `RewardClaimed = true` already has it; check `CrateHistory` for a token open (`UsedToken = true`). Manual grants require the owner-approved support process (DATA_SCHEMA.md §9).

### 3.14 Queue stuck or matches not forming

1. Players see `SEARCHING` indefinitely. First check that the destination's PlaceId is set in `Config.Places`; a 0 PlaceId refuses queueing with `NotConfigured`, but a hub built before the PlaceId was filled must be re-published.
2. Check for `[Matchmaking] matchmaking tick` lines on some hub server. If none appear, no hub holds the lease (`CB_MM_Leases`, key `lead:<destination>`): leases expire after 15 s, so a crashed leader is replaced automatically within one lease period. Persistent absence suggests MemoryStore errors (`leader tick failed`).
3. `failed` counts in the tick line mean `ReserveServer` errors; tickets stay queued and are retried every 3 s.
4. Duels form only with exact team sizes; Team Deathmatch starts with 4+ players after the oldest ticket waited 45 s (D-043). Too few players in the queue is the usual cause.
5. `Data:MatchTeleportFailed`: the group is requeued at the front up to 2 times, then cancelled with `TeleportFailed`. If one destination fails repeatedly, check the place is published and not shut down.
6. A ticket is delivered at most once at a time: `MatchmakingService` sets `Delivering` while its teleport attempt runs, and later polls skip it.

### 3.15 Stale tickets and abandoned queues

No manual cleanup is needed. Tickets and user-index entries expire 120 s after the last heartbeat, which the owning hub sends every 30 s. If a hub crashes, its players are freed within about 2 minutes. A player told `AlreadyQueued` after leaving a hub abruptly can queue again once the old entry expires.

### 3.16 Reserved match cancelled or failed

1. `reserved match cancelled: players did not arrive`: the roster was not complete at the 45 s deadline and the match was unplayable (a team missing, or nobody in FFA private). Everyone present is returned to the hub.
2. `reserved server has no readable match record`: the record in `CB_MM_Matches` was missing (expired after 3 h, or MemoryStore unavailable at boot). Everyone is returned to the hub (or removed with a message if the hub cannot be reached). Repeated occurrences on fresh servers point to MemoryStore errors.
3. Reserved servers host one match (D-047), then send everyone to the hub after 15 s. A server stuck in phase `Closed` with players means the hub teleport failed and the players were removed with "Match complete".

### 3.17 Reconnect issues

1. A disconnected player has 90 s (D-045) to rejoin. The hub shows `REJOIN` only if `CB_MM_Active` (key `u<userId>`) holds an unexpired record when their profile loads in the hub.
2. After the window, the player is removed from the match (`ForgetPlayer`); a duel team with nobody left forfeits. Reconnect records are cleared when the match ends.
3. Rejoining duelists spectate until the next round (D-046). Rejoining Team Deathmatch players keep their team and score.
4. `Security:ReservedAdmissionRefused {reason = "ReconnectExpired"}` means they came back too late.

### 3.18 Private match support

1. Private matches never award coins, XP or statistics (`AwardsProgression = false`, `MatchContext.ModeConfig`). Players asking for missing rewards from a private match are seeing designed behaviour.
2. Hosting requires the party leader, a completed tutorial for every member, a published place for the base mode, and is refused in Studio. Each host is audited as `Data:PrivateMatchHosted`.

### 3.19 Server browser empty

1. Only public arena servers outside Studio advertise. Reserved and player-owned private servers are never listed (`ServerBrowserService.advertised`).
2. Entries expire 45 s after the last heartbeat (every 15 s), and full servers are filtered out. An empty list with players online usually means every server is full, or `GetServers` returned `Unavailable` (MemoryStore error).
3. Joining a listed server that has since filled or closed fails with `instance join failed`; the player stays in the hub.

### 3.20 MemoryStore outage

Effects:
- Queueing refuses with `QueueUnavailable`.
- Leader ticks fail and log.
- The browser shows nothing.
- New reserved servers fail closed and return players to the hub.
- Reconnect offers are not shown.

Profiles, currency and progression are unaffected (DataStore). Direct joins to public servers (FFA PLAY, portals) keep working. No action is needed beyond monitoring the Roblox status page; everything recovers when MemoryStore does, because all records are TTL-based.

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
