# Decision Log

Architecture and design decisions, newest last. Each entry records the context, the decision, and its consequences. Decisions that change an established gameplay requirement need owner approval first (directive §2); none of the entries below do, unless marked **Needs owner approval**.

| ID | Title | Status |
|---|---|---|
| D-001 | Working title "Crossblade" | Proposed: **Needs owner approval** |
| D-002 | Functional core, imperative shell | Accepted |
| D-003 | Client proposes, server verifies, against standardized hitboxes | Accepted |
| D-004 | Zero third-party runtime dependencies | Accepted |
| D-005 | TestEZ-compatible harness on Lune instead of vendored TestEZ | Accepted |
| D-006 | Minimal Selene Roblox standard library | Accepted (temporary) |
| D-007 | Fully scripted camera | Accepted |
| D-008 | Combat stats belong to archetypes, never collectibles | Accepted |
| D-009 | Studio-only, non-persistent data mode | Accepted |
| D-010 | Generated greybox map, primitive weapon models and procedural poses as tracked temporary assets | Accepted (temporary) |
| D-011 | Thrown knives simulated without lag-compensated rewind | Accepted (revisit in Phase 6) |
| D-012 | Shots originate at the standardized head, not the camera | Accepted |
| D-013 | Deaths without a direct killer credit the top recent attacker | Accepted |
| D-014 | Knife stab uses the specified base damage; slash is faster and weaker | Accepted |
| D-015 | Ammunition pickup grants one magazine per firearm | Accepted |
| D-016 | A Free-for-All "win" is first place with at least one elimination | Accepted |
| D-017 | Session lock timeout of 300 s with 60 s autosave | Accepted |
| D-018 | Client predicts ammunition; server state always overwrites it | Accepted |
| D-019 | Dropped knives despawn after 30 s | Accepted |
| D-020 | Network contracts are declarative and exhaustive | Accepted |
| D-021 | Proposed XP amounts | Proposed: **Needs owner approval** |
| D-022 | Proposed level curve and level rewards | Proposed: **Needs owner approval** |
| D-023 | Proposed odds for non-standard crates | Proposed: **Needs owner approval** |
| D-024 | Proposed anti-farming limits | Proposed: **Needs owner approval** |
| D-025 | "Finished off" kills pay the assist rate | Accepted |
| D-026 | Crates spend earned coins first; purchased coins only when policy allows | Accepted |
| D-027 | Crate idempotency via a client RequestId and CrateHistory | Accepted |
| D-028 | Phase 3 placeholder collectible content | Accepted (temporary) |
| D-029 | Free-for-All first place awards XP only | Proposed: **Needs owner approval** |
| D-030 | Multiple places from one codebase via PlaceConfig and per-place projects | Accepted |
| D-031 | One generic MatchService; the hub runs a non-scoring Lobby mode | Accepted |
| D-032 | MinPlayers is a start threshold; capacity is the place server size | Proposed: **Needs owner approval** |
| D-033 | Duel round time limit and tie-breaks | Proposed: **Needs owner approval** |
| D-034 | Duel overflow and late joiners spectate until the next match | Accepted |
| D-035 | Map vote: up to 3 maps excluding the current one; ties random | Accepted |
| D-036 | Tutorial reward at the Coins step; first-timers must finish before portals | Accepted |
| D-037 | Tutorial crate delivered as a free crate token | Accepted |
| D-038 | Teleports rely on the session-lock retry at the destination | Accepted (revisit in Phase 5) |
| D-039 | Team victory XP equals first-place XP | Proposed: **Needs owner approval** |
| D-040 | Hub practice and non-progression modes never change persistent statistics | Accepted |
| D-041 | MemoryStore matchmaking: group tickets, user index, assignments, leased leader | Accepted |
| D-042 | Reserved servers read their roster by PrivateServerId; teleport data never trusted | Accepted |
| D-043 | Queue sizes: TDM 5v5 with a relaxed start; exact duel sizes | Proposed: **Needs owner approval** |
| D-044 | Parties are per hub server; no cross-server invites yet | Accepted (revisit) |
| D-045 | Matchmaking and reconnection timings | Proposed: **Needs owner approval** |
| D-046 | Duel disconnects cost the round; forfeit after the reconnect window | Accepted |
| D-047 | Reserved servers host exactly one match | Accepted |
| D-048 | Private match bounds | Proposed: **Needs owner approval** |
| D-049 | Remapping allow-list and order-independent conflict resolution | Accepted |
| D-050 | Greedy match forming | Accepted |
| D-051 | Arenas return players who have not finished the tutorial | Accepted |

---

### D-001: Working title "Crossblade"
**Context.** The directive leaves the name as `[GAME_NAME]`. The repository is `crossblade`.
**Decision.** Use "Crossblade" as the working title in code (`Crossblade_PlayerData` store names, `CrossbladeRemotes`, UI names) and documentation.
**Consequences.** Renaming before launch is a search-and-replace in code and docs, **except data store names**. `Config.Data.StoreBaseName` must be finalized before the first production write, because changing it later orphans saved data. **Needs owner approval** of the final name before the first production release.

### D-002: Functional core, imperative shell
**Context.** Roblox services cannot run outside Studio, and Studio playtests can't be automated in this environment. The directive requires every system to be tested.
**Decision.** All game rules live in pure modules with injected dependencies: `src/shared/Combat`, `src/server/Domain`, `src/server/Data`, plus `Schema`, `Loader` and `RateLimiter`. Services and controllers are thin adapters that wire Roblox events to those rules.
**Consequences.** Rules are unit-tested headlessly under Lune (`tests/`). Roblox-facing glue still needs Studio and multiplayer verification (see TEST_PLAN.md §4). Static integrity tests cover the glue's most common failure modes.

### D-003: Client proposes, server verifies, against standardized hitboxes
**Context.** Pure server-side raycasting feels unresponsive at Roblox latencies. Trusting client hits is insecure. Avatar geometry varies widely between players.
**Decision.** The client detects hits predictively against a standardized capsule-plus-sphere hitbox (`Config.Player.Hitbox`) and reports origin, direction, hit position and zone. The server rewinds the target, by at most `MaxRewindSeconds = 0.35`, re-intersects the ray with the same geometry plus a bounded tolerance, decides the zone itself, and checks line of sight. Damage is always computed on the server.
**Consequences.** Combat is identical for every avatar. Cheats are limited to what the tolerances permit: 0.9-stud body inflation and 0.45-stud head inflation, plus origin, direction and rewind bounds. All tolerances are configuration values.

### D-004: Zero third-party runtime dependencies
**Context.** The directive allows only vetted dependencies. The Wally index is hosted on GitHub, which this environment cannot reach.
**Decision.** Ship with no runtime packages. `wally.toml` exists with empty dependency tables.
**Consequences.** Utilities such as Signal, Trove and Retry are small, local and tested. Adding a package later requires a new decision entry.

### D-005: TestEZ-compatible harness on Lune instead of vendored TestEZ
**Context.** TestEZ requires a Roblox runtime or a vendored copy downloaded from GitHub, and neither was available.
**Decision.** `tests/lib/Harness.luau` provides `describe`, `it`, `expect` and `beforeEach` with TestEZ-style matchers. `tests/lib/Runtime.luau` emulates Rojo's instance tree, `script`, `require` and `GetService`.
**Consequences.** Specs read like TestEZ specs and could be ported to TestEZ in Studio if needed. The harness was verified to fail correctly on a deliberately failing spec.

### D-006: Minimal Selene Roblox standard library
**Context.** `selene generate-roblox-std` could not download the Roblox API dump. Selene's TLS stack does not trust this environment's proxy CA, and disabling verification is not permitted.
**Decision.** `roblox_min.yml` declares the Roblox globals on top of Selene's built-in `luau` std.
**Consequences.** Undefined-global, unused-variable and other structural lints work. Member-level API checks do not. **Follow-up:** run `selene generate-roblox-std` on a machine with direct internet access and set `std = "roblox"`.

### D-007: Fully scripted camera
**Context.** Recoil, shoulder collision, consistent aim and the first/third-person toggle are hard to control precisely through the default camera module.
**Decision.** `CameraController` runs `CameraType.Scriptable` with its own yaw and pitch, covering mouse, gamepad and touch input.
**Consequences.** Full control over recoil and collision. Accessibility features of the default camera, such as the touch camera and the VR path, must be reproduced explicitly; VR is out of scope.

### D-008: Combat stats belong to archetypes, never collectibles
**Context.** The directive says higher rarity must not automatically mean more combat power.
**Decision.** Catalog entries reference an archetype and hold no combat fields. `WeaponCatalog.Validate()` rejects any collectible that defines combat fields. A test asserts that no combat module mentions `Rarity`.
**Consequences.** A weapon's rarity changes appearance only. Balance changes are made per archetype.

### D-009: Studio-only, non-persistent data mode
**Context.** Local Studio sessions often have no DataStore access.
**Decision.** In Studio only, a failed DataStore probe switches `PlayerDataService` to `StudioEphemeral` mode. Data stays in memory, a warning is logged, and players see a notification that nothing will be saved. The mode asserts `RunService:IsStudio()` and cannot activate on live servers, which fail closed by kicking players.
**Consequences.** Developers can playtest without publishing. This is never a silent substitute for persistence.

### D-010: Generated greybox map, primitive weapon models and procedural poses as tracked temporary assets
**Context.** No original models, animations or audio exist yet. Asset IDs must never be invented.
**Decision.** Phase 2 uses a data-driven greybox arena, primitive-part weapon models and procedural arm poses. All are listed in ASSET_MANIFEST.md. Audio is not implemented because no licensed assets exist.
**Consequences.** The slice is playable but visually placeholder. Replacements need no combat-code changes: maps use tags, weapons use `ModelProfile`, and animations use `AnimationProfile`.

### D-011: Thrown knives simulated without lag-compensated rewind
**Context.** A thrown knife starts on the server when the request arrives.
**Decision.** Knife flight tests against current target positions.
**Consequences.** High-latency throwers see slightly less forgiving hits. Revisit in Phase 6 with the ranked latency work.

### D-012: Shots originate at the standardized head, not the camera
**Context.** The directive requires that camera perspective must not allow attacks through obstacles.
**Decision.** The aim point comes from the screen-centre ray. Bullets travel from the standardized head toward it, and the server checks line of sight from that origin.
**Consequences.** A third-person camera that sees around a corner cannot shoot around it; the bullet hits the cover.

### D-013: Deaths without a direct killer credit the top recent attacker
**Context.** Resetting or falling out of bounds could otherwise deny an opponent's elimination.
**Decision.** If a death has no direct cause, the player who dealt the most damage within the assist window gets a `Finished` elimination.
**Consequences.** Kill-denial by resetting does not work. Future economy rewards must decide whether `Finished` kills earn full rewards (backlog ECO-06).

### D-014: Knife stab uses the specified base damage; slash is faster and weaker
**Context.** The specification gives one base damage per knife but requires both slash and stab.
**Decision.** Stab, the alternate attack, deals the specified base damage. Slash, the primary attack, deals about 60% with a shorter cooldown. A throw deals base damage with a configurable headshot multiplier.
**Consequences.** All values are configurable in `Config/Weapons/Archetypes.luau`.

### D-015: Ammunition pickup grants one magazine per firearm
**Decision.** `Config.Pickups.Ammo.MagazinesPerPickup = 1`, capped at each weapon's maximum reserve. A pickup is not consumed if it would add nothing.

### D-016: A Free-for-All "win" is first place with at least one elimination
**Decision.** At round end, first place with at least one elimination counts as a win, and everyone else records a loss. Phase 3 rewards build on this definition.

### D-017: Session lock timeout of 300 s with 60 s autosave
**Decision.** Autosave refreshes the lock every 60 s, so a live session never looks stale. A crashed server's lock becomes claimable after 5 minutes.

### D-018: Client predicts ammunition; server state always overwrites it
**Decision.** The HUD decrements ammunition immediately for responsiveness. Every `LoadoutState` from the server replaces the local state.
**Consequences.** The ammunition counter can briefly tick up when a state arrives while shots are still in flight. Shot-id acknowledgement would remove this (backlog CMB-14).

### D-019: Dropped knives despawn after 30 s
**Decision.** `GroundLifetimeSeconds = 30`. After that the owner must use a knife station or respawn. A thrown knife is never returned to the owner for free.

### D-020: Network contracts are declarative and exhaustive
**Decision.** Every remote is declared in `Shared/Net/Contracts.luau` with its payload schema and rate limit. The server Net layer is the only code that connects `OnServerEvent`. An integrity test fails if code uses an undeclared remote or if a declared remote is unused.

### D-021: Proposed XP amounts
**Context.** The specification lists XP sources but no amounts.
**Decision.** In `Config.Economy.Experience`: elimination 100, headshot bonus 20, assist 40, finished-off kill 40, match completed 150, first place 250.
**Consequences.** These are configuration values only; changing them needs no code change.

### D-022: Proposed level curve and level rewards
**Decision.** XP to go from level L to L+1 is `1000 + 100 × (L − 1)`, so reaching level 100 takes 584,100 XP. Each level pays 100 coins, plus 400 more on every 10th level. Level rewards are paid only above `Progression.HighestRewardedLevel`, so they can never be paid twice, including after a future prestige reset (`Shared/Economy/Leveling`).

### D-023: Proposed odds for non-standard crates
**Context.** The specification gives one "standard" distribution. Basic and the knife, pistol, rifle and sniper crates use it.
**Decision.** Proposed distributions in `Config/Crates.luau`:
- Premium: Uncommon 40 / Rare 30 / Epic 18 / Legendary 8 / Mythical 3.5 / Celestial 0.5.
- Legendary: Legendary 85 / Mythical 13 / Celestial 2.
- Mythical: Mythical 92 / Celestial 8.
- Shotgun: standard, with Celestial's 0.2% moved to Mythical, because no Celestial shotgun exists.
- Themed: Rare 60 / Epic 28 / Legendary 10 / Mythical 2.
Every crate passes boot-time validation; each one's expected duplicate compensation is below its price.

### D-024: Proposed anti-farming limits
**Decision.** The same killer→victim pair is rewarded at most 3 times per 300 s, and the whole elimination pays nothing beyond that. Match rewards are capped at 2,000 coins and 20,000 XP per rolling hour; the counters are persisted, so hopping servers does not reset them. Rewards require at least 2 players with loaded profiles. Player-owned private servers award nothing. All values live in `Config.Economy.AntiFarming`.

### D-025: "Finished off" kills pay the assist rate
**Decision.** A `Finished` elimination (D-013) pays 10 coins and 40 XP, not a full elimination reward. This keeps kill-denial resistance without making environmental deaths farmable.

### D-026: Crates spend earned coins first; purchased coins only when policy allows
**Context.** Coins bought with Robux and spent on crates make crates paid randomized items under platform policy.
**Decision.** `Wallet.Debit` always spends earned coins first. Purchased coins are spendable on crates only when `PolicyService` was queried successfully and reported `ArePaidRandomItemsRestricted = false`. Any failure or unexpected value blocks purchased-coin use (fail closed, `Domain/PaidRandomPolicy`). Earned coins remain the free, gameplay-based path.

### D-027: Crate idempotency via a client RequestId and CrateHistory
**Decision.** The client generates a GUID per purchase and reuses it on retry. The server applies the purchase as transaction `crate:<RequestId>`. A replay returns the stored result from `CrateHistory` (bounded at 50) and is never charged or rewarded again.

### D-028: Phase 3 placeholder collectible content
**Decision.** 37 collectible definitions with original names cover every archetype, rarity and themed collection, so every crate has a real reward pool. They stay within the launch distribution limits per rarity and slot, which is tested. Models are primitive dev models tinted by collection (ASSET_MANIFEST.md). Phase 9 replaces the models and extends the catalog to 150.

### D-029: Free-for-All first place awards XP only
**Context.** The specification gives duel and Team Deathmatch victory coins but nothing for Free-for-All.
**Decision.** First place with at least one elimination earns 250 XP and `FreeForAllFirstPlace = 0` coins until a value is approved.

### D-030: Multiple places from one codebase via PlaceConfig and per-place projects
**Context.** The specification calls for one experience with a hub and separate arena places per mode.
**Decision.** `places/*.project.json` build five places (hub, FFA, TDM, Duel 1v1, Team Duel 2v2) from the same `src/`. Each adds a `ReplicatedStorage.PlaceConfig` Configuration with `Role`, `Mode` and optionally `TeamSize`, which `Shared/PlaceConfig` reads. Services and controllers may declare `Roles`; `Main` filters on them. `default.project.json` stays a Free-for-All arena.
**Consequences.** One codebase and one test suite serve every place. 3v3 and 4v4 team duels are new project files with a different `TeamSize`, and need no code changes.

### D-031: One generic MatchService; the hub runs a non-scoring Lobby mode
**Decision.** Phases, teams, rounds and voting are driven by `Config.GameModes[...].Kind`. In the hub, `Lobby` mode keeps every combat system running for practice. `CanDamage` is always false for players, so weapons only affect training dummies.

### D-032: MinPlayers is a start threshold; capacity is the place server size
**Context.** Team Deathmatch "supports 5v5 and 8v8". Requiring 10 players to start would make small servers unplayable.
**Decision.** TDM starts with 2 players and keeps balancing teams as people join. 5v5 and 8v8 are separate places with Roblox server sizes of 10 and 16. **Needs owner approval.**

### D-033: Duel round time limit and tie-breaks
**Decision.** Rounds last 120 s (1v1) or 150 s (team). At the limit, the team with more survivors wins, then the team with more total health. A full tie replays the round. **Needs owner approval.**

### D-034: Duel overflow and late joiners spectate until the next match
**Decision.** When a duel starts, players beyond `2 × TeamSize` spectate. So does anyone joining mid-match. They enter the next match in join order.

### D-035: Map vote: up to 3 maps excluding the current one; ties random
**Decision.** `Domain/MapVote` offers up to 3 eligible maps other than the current one, falling back to the current map when it is the only one. Each player has one vote and can change it. Ties, including no votes at all, are broken randomly.

### D-036: Tutorial reward at the Coins step; first-timers must finish before portals
**Context.** The specification says first-time players must complete the tutorial, and that steps 10–11 teach crate opening and loadout customization.
**Decision.** The reward is granted once, when the "Coins" step completes, so the later steps can teach spending it. `PortalService` refuses hub teleports until `Tutorial.Completed`. Combat steps complete only from server-observed events.

### D-037: Tutorial crate delivered as a free crate token
**Decision.** "One Basic Crate" is stored as `CrateTokens.basic += 1`. Opening with a token moves no currency, so it is not a paid randomized purchase and needs no policy gate.

### D-038: Teleports rely on the session-lock retry at the destination
**Decision.** The profile is released on `PlayerRemoving` as usual. The destination's `ProfileStore.Load` retries while the lock is still held, with up to 6 attempts and backoff. This avoids a release-then-teleport-fails gap. Phase 5 reserved-server matchmaking may add an explicit handoff.

### D-039: Team victory XP equals first-place XP
**Decision.** TDM and duel winners receive `Experience.FirstPlace` (250 XP) plus the specified victory coins (150 and 100). **Needs owner approval.**

### D-040: Hub practice and non-progression modes never change persistent statistics
**Decision.** `MatchService.TracksStats()` returns the mode's `AwardsProgression`. Combat, projectile and match statistics are written only when it is true, so dummy practice cannot inflate accuracy and private matches cannot change stats.

### D-041: MemoryStore matchmaking: group tickets, user index, assignments, leased leader
**Decision.** A queued group (a party or a solo player) is one ticket in `CB_MM_Tickets_<destination>`, sorted by creation time. A per-user index entry (`CB_MM_Users`) prevents anyone holding two live tickets across servers; conflicting enqueues roll back. Tickets and index entries expire (120 s) unless the owning hub heartbeats them (every 30 s), so a crashed hub cannot strand anyone. One hub per destination holds a 15 s lease (`CB_MM_Leases`), forms matches, reserves servers, writes the match record (`CB_MM_Matches`, keyed by PrivateServerId) and an assignment per ticket (`CB_MM_Assign`). The owning hub then teleports the group. A failed teleport requeues the ticket with its original creation time, up to twice. The logic lives in `Matchmaking/Queue` and `Matchmaking/Matchmaker` and is tested against an in-memory sorted-map double.

### D-042: Reserved servers read their roster by PrivateServerId; teleport data never trusted
**Decision.** `TeleportService:ReserveServer` returns an access code and a PrivateServerId. The record is stored under the PrivateServerId, and the reserved server reads it in `Core/MatchContext.Load` before any service boots. Teleport data can be tampered with by clients, so it is informational only. A reserved server that cannot read its record returns every player to the hub.

### D-043: Queue sizes: TDM 5v5 with a relaxed start; exact duel sizes
**Decision.** TDM queues form 5v5 matches. Once the oldest ticket has waited 45 s, a match may start with 4 or more players across two teams. Duel queues need exactly 2 (1v1) or 4 (2v2) players. Public TDM servers remain available through the server browser. **Needs owner approval.**

### D-044: Parties are per hub server; no cross-server invites yet
**Decision.** Parties of up to 8 form among players in the same hub server, and an invite must be accepted before it expires (60 s). Any player in the server can be invited. Cross-server friend invites (via MessagingService) are not implemented yet. Players can join a friend's hub server through Roblox's own join feature, then party up.

### D-045: Matchmaking and reconnection timings
**Decision.** Rostered players have 45 s to arrive. A disconnected player may reconnect within 90 s. Players return to the hub 15 s after a reserved match ends. Ticket TTL is 120 s with a 30 s heartbeat. All values are in `Config.Matchmaking`. **Needs owner approval.**

### D-046: Duel disconnects cost the round; forfeit after the reconnect window
**Decision.** On a reserved duel server, a disconnect eliminates the player for the current round, and absent duelists sit out each round until they return. When the reconnect window expires, the player is removed from the roster, and a team with nobody left forfeits. Ranked abandonment penalties are Phase 6.

### D-047: Reserved servers host exactly one match
**Decision.** After the match ends, the phase becomes `Closed`, reconnect records are cleared, and everyone returns to the hub. Late joiners to a closed server are returned straight away.

### D-048: Private match bounds
**Decision.** Private matches can be hosted on Free-for-All or Team Deathmatch, with any map eligible for that mode, 3–30 minutes, and a score limit of 5–200 (TDM). The host's party is the roster. Private matches use a derived mode with `AwardsProgression = false` and no map vote. **Needs owner approval.**

### D-049: Remapping allow-list and order-independent conflict resolution
**Decision.** Players can rebind any action to allow-listed keys only. Movement, jump, Escape and other system keys are never bindable. Candidate overrides are applied first, then any override colliding with another action's effective binding is dropped repeatedly until stable. Swaps therefore work, and when two overrides take the same key exactly one keeps it. The client previews the same rules (`Shared/Bindings`) that the server applies.

### D-050: Greedy match forming
**Decision.** `Domain/MatchFormer` places tickets oldest first, keeps parties together, and always includes the oldest ticket. It is greedy, so in rare party-size combinations it can miss a packing that would have worked; the next tick tries again as tickets change.

### D-051: Arenas return players who have not finished the tutorial
**Decision.** Closing the bypass noted in Phase 4: an arena's `PortalService` sends any player whose `Tutorial.Completed` is false back to the hub. In Studio, it shows a notice instead.
