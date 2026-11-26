# Test Plan

## 1. Strategy

| Layer | What it covers | Tooling | Runs where |
|---|---|---|---|
| Unit | Pure rule modules: combat math, ammo, knives, validation, spawn scoring, persistence, transactions, schema, config | Lune + `tests/lib/Harness` (TestEZ-style) | Locally and in CI (`lune run tests/run`) |
| Map data | Greybox layout: marker counts, no pickup or spawn inside geometry, everything inside the perimeter | `tests/specs/DevArena.spec.luau` | Locally and in CI |
| Mode rules | Team balancing, TDM outcome, duel rounds, forfeits and time limit, map voting, tutorial step machine and one-time reward, mode and place configuration | `tests/specs/Modes.spec.luau` | Locally and in CI |
| Static integrity | All source, including Roblox-only code: Luau compilation, require-path resolution, declared dependencies, acyclic graphs, remote-name/contract agreement | `tests/specs/Integrity.spec.luau` | Locally and in CI |
| Lint / format | Undefined globals, unused variables, suspicious patterns; formatting | Selene (`roblox_min` std, D-006), StyLua | Locally and in CI |
| Build / structure | Rojo build succeeds; built place has the required instances and properties; no executable scripts in ReplicatedStorage | `rojo build`, `scripts/verify-place.luau` | Locally and in CI |
| Studio playtest | Roblox runtime behaviour of services and controllers | Roblox Studio | **Manual; not yet executed** (section 4) |
| Multiplayer | Replication, lag compensation under real latency, concurrency | Studio "Start Server + N Players", private test server | **Manual; not yet executed** |
| Device / performance | 60 FPS desktop, 30 FPS low-end mobile, console | MicroProfiler, Developer Console | **Not yet executed** |

Run everything with `./scripts/verify.sh`.

## 2. Latest automated run

Executed in this repository on 2026-11-26 with Lune 0.11.1, Selene 0.31.0, StyLua 2.6.0 and Rojo 7.7.1:

- `stylua --check src tests scripts`: pass
- `selene src` and `selene tests`: 0 errors, 0 warnings
- `lune run tests/run`: **192 passed, 0 failed, across 17 spec files**
- `rojo build` for the default project and all five places (hub, FFA, TDM, Duel 1v1, Team Duel 2v2): pass. `scripts/verify-place.luau`: pass for each place, including its `PlaceConfig` role and mode (21 server services; TutorialService boots only in the hub)

Phase 3 economy guarantees were mutation-tested. Letting purchased coins bypass the policy check, skewing crate selection away from the disclosed odds, and doubling duplicate compensation were each caught by `Economy.spec`.

Phase 4 added a signal-wiring integrity test. On its first run it found a real defect: `PickupService.PickupConsumed` was fired and connected but never declared, which would have stalled the tutorial's Pickups step at runtime. It was fixed, and removing the declaration again makes the test fail.

The harness's ability to fail was checked with a deliberately failing spec. The integrity checks were mutation-tested: a bad server require, a bad client require, an undeclared registry dependency and an unknown remote were each injected and each was caught.

## 3. Mandatory acceptance tests (directive §32)

| # | Requirement | Status | Evidence |
|---|---|---|---|
| 1 | A player cannot exceed 150 HP | **Pass** | `Health.spec` > "a player cannot exceed 150 HP from healing"; "heal up to the cap…" |
| 2 | A player cannot attack with an unowned weapon | **Pass** (rule) | `Loadout.spec` > "a player cannot attack with an unowned weapon…". Clients send slot names only; weapons are resolved server-side (`WeaponService.ResetForLife`) |
| 3 | A player cannot fire without ammunition | **Pass** | `Ammo.spec` > "a player cannot fire without ammunition"; enforced in `CombatService.onFire` via `AmmunitionService:Consume` |
| 4 | A player cannot use a thrown knife before recovery | **Pass** | `Knife.spec` > "a player cannot use a thrown knife before recovery"; "rejects recovery of stale or foreign throw ids" |
| 5 | Duplicate crate rewards give exactly the configured compensation | **Pass** | `Economy.spec` > "duplicate crate rewards provide exactly the configured compensation" (every rarity) |
| 6 | Repeated transaction requests cannot duplicate rewards | **Pass** | `Transactions.spec` > "repeated transaction requests cannot duplicate rewards"; `Economy.spec` > "a replayed request cannot charge or reward twice", "is atomic: insufficient funds leave the profile untouched" |
| 7 | Replayed Robux receipts cannot duplicate purchases | **Not implemented** | Phase 7 (MON-01); will be built on `Transactions.Apply` keyed by `PurchaseId` |
| 8 | Ineligible users cannot purchase paid randomized rewards | **Pass** (crate spending) | `Economy.spec` > "ineligible users cannot spend purchased coins on paid randomized rewards"; "blocks restricted users". Robux coin purchases themselves are Phase 7 (MON-01) |
| 9 | Failed policy lookups block restricted purchases | **Pass** | `Economy.spec` > "failed policy lookups block restricted purchases" |
| 10 | Private matches cannot generate normal progression rewards | **Pass** (rule) | `Foundation.spec` > "private matches cannot generate normal progression rewards" (mode flag); `Economy.spec` > "pays nothing for self, environmental or disabled-mode eliminations". `EconomyService.rewardsEnabled` also disables rewards in player-owned private servers. End-to-end private matches arrive in Phase 5 (NET-06) |
| 11 | Failed data loads cannot erase existing profiles | **Pass** | `ProfileStore.spec` > "failed data loads cannot erase existing profiles (store outage)", "never overwrites corrupt records", "refuses data written by a newer schema version", "does not write when a migration fails", "refuses to load a profile locked by another live server and does not write" |
| 12 | Unauthorized players cannot execute administrator commands | **Not implemented** | No administrator commands exist yet; Phase 8 (SEC-01) |
| 13 | Matchmaking failures recover without trapping players | **Not implemented** | Phase 5 (NET-01/04) |
| 14 | Ranked rewards cannot be granted multiple times | **Not implemented** | Phase 6 |
| 15 | Weapon rarity does not automatically increase combat power | **Pass** | `WeaponCatalog.spec` > "weapon rarity does not automatically increase combat power", "no combat module reads rarity" |

## 4. Manual Studio and multiplayer checklist (Phase 2 exit criteria; not yet executed)

Setup: publish the place, set the avatar type to R15, enable Studio Access to API Services, then run **Test > Start Server with 3 Players** with network simulation on (Studio settings: Network > Incoming Replication Lag 0.1 s).

| ID | Procedure | Expected |
|---|---|---|
| M-01 | Join | Profile loads; spawn at a tagged spawn with ForceField; HUD shows 150 HP, `30 / 90`, Vanguard AR |
| M-02 | Without API access | Warning toast "Progress … will NOT be saved"; game still playable (D-009) |
| M-03 | Fire at player B for 6 body hits within 60 studs | B eliminated (6 × 25 = 150); kill feed, elimination screen on B with killer HP and level; B respawns after 3 s |
| M-04 | Headshot | Hit marker turns yellow; damage 37.5 |
| M-05 | Third-person: camera sees B past a corner while the character is behind cover | Shots hit the cover, no damage (D-012) |
| M-06 | Fire until empty | Auto-reload; cannot fire during reload; reserve decreases |
| M-07 | Switch to the knife during a reload | Reload cancelled, no rounds moved |
| M-08 | Throw the knife (G) | Knife flies; slash and stab disabled; slot shows THROWN; walking over the knife recovers it; a knife station also replaces it |
| M-09 | Health pickup at 150 HP | Not consumed; at 60 HP Small heals to 85 and goes dim for 10 s |
| M-10 | Attack during spawn protection | Protection ends immediately (ForceField removed) |
| M-11 | Walk off the map | Eliminated at kill height; if recently damaged, the attacker gets a "finished off" kill |
| M-12 | Change FOV, sensitivity and crosshair; Save; rejoin | Settings persist |
| M-13 | Stop the server (BindToClose) | All profiles saved and released; rejoin loads them |
| M-14 | Join the same account on two servers | Second server kicks with the "still being saved" message until the first releases |
| M-15 | Gamepad | R2 fire, L2 aim, X reload, Y swap, B throw, R3 camera, Select settings, D-pad left scoreboard |
| M-16 | Touch (device emulator) | Touch buttons FIRE, AIM, RLD, SWAP, THROW, CAM; drag to look; slot buttons tap to equip |
| M-17 | Exploit simulation: fire remote with a 9999-pellet table, NaN origin, extra fields | Dropped; suspicion logged; no damage |
| M-18 | 15-minute round end | Results panel; combat disabled; new round in 20 s with stats reset |
| M-19 | Eliminate a player with a rifle, then with a knife | Toasts "+25 coins +100 XP (Elimination)" and "+35 coins (Knife elimination)"; HUD coins and XP update |
| M-20 | Eliminate the same player 4 times within 5 minutes | The 4th elimination pays nothing (D-024) |
| M-21 | Open the Collection window (I / D-pad up / COLLECTION) > Crates > Basic | Every item is listed with its exact percentage before the OPEN button; percentages add up per rarity |
| M-22 | Open a Basic crate with enough coins | Reveal shows the server's result; a new weapon appears in the Armory; a duplicate shows "+N coins" with the exact table value |
| M-23 | Disconnect the network mid-open (Studio: pause the server), then resume | At most one charge; a retry returns the same result |
| M-24 | Equip a crate weapon in the Armory, then respawn | The new weapon is in hand; its model is tinted by its collection |
| M-25 | Rejoin after M-22 | Coins, inventory, crate history and loadout persisted |
| M-26 | Hub (build/hub.rbxl), new account | Tutorial starts automatically; PLAY > any mode says "Finish the tutorial…" |
| M-27 | Tutorial steps 1–12 | Each advances only by doing it; steps 4–8 need real hits, reloads, recovery and pickups; reward toast "+500 coins"; Crates tab shows "OPEN FREE (1 TOKEN)" |
| M-28 | Shoot a player in the hub | No damage; dummies show damage numbers and reset after being knocked down |
| M-29 | Replay the tutorial from the Training station | No second reward; EXIT available |
| M-30 | TDM place (build/tdm.rbxl), 4 players | Teams Alpha/Bravo balanced; no friendly damage; team score climbs; first to 50 or time ends; victory toast "+150 coins" for winners |
| M-31 | Duel 1v1 place, 2 players | Countdown; rounds; eliminated player spectates (FIRE/AIM switch); first to 3 wins; leaving forfeits |
| M-32 | Team duel place, 5 players | 4 play 2v2 and the 5th spectates until the next match |
| M-33 | Map vote at match end | Panel lists up to 3 maps; votes update live; winning map loads and everyone respawns on it |
| M-34 | Published places with PlaceIds configured | Portals and PLAY teleport to the right place; a full or failed destination shows a failure message and the player stays playable |

## 5. Planned test additions by phase

- **Phase 3 (done):** stratified and chi-squared odds checks, exact duplicate compensation, EV validation, atomic and idempotent purchase. **Still planned:** a long-horizon economy simulation of coin inflow and sinks per player archetype (ECO-07).
- **Phase 5:** MemoryStore queue failure injection, teleport failure recovery.
- **Phase 7:** ProcessReceipt replay, interrupted-session fulfilment, PolicyService failure means blocked.
- **Phase 8:** RBAC denial for every admin command.
- **Phase 10:** load testing at 20 players, device profiling, accessibility review.
