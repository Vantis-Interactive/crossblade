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
