# Game Design

Working title: **Crossblade** (D-001, pending owner approval).

A fast, skill-based multiplayer PvP arena game with guns and knives, a deep weapon collection and persistent progression. It is free to play, and paid content never grants a combat advantage.

Each section separates **Implemented (Phases 2–4)** from **Specified / planned**. Implemented numbers come from source files, which are cited. Planned numbers are the directive's values and become configuration when their phase is built.

## 1. Pillars

| Pillar | What it means in practice |
|---|---|
| Skill decides fights | Identical health, movement and hitboxes for every player. Rarity and purchases never change combat stats (D-008). |
| Responsive but fair | Client-predicted feedback, with all damage validated and applied by the server (D-003). |
| Readable, non-graphic combat | Eliminations fade out with a light pulse. No blood, no gore, no dismemberment. |
| Collect and express | Collecting weapons and cosmetics is the long-term goal. Cosmetics are visual only. |
| Live service | Seasons, events and rotating content are driven by configuration, not code changes. |

## 2. Core loop

```
Enter match -> Eliminate opponents -> Earn coins and XP -> Open crates -> Unlock weapons
    ^                                                                        |
    +------------------------ Customize loadout <----------------------------+
```

**Implemented (Phases 2–4):** the full loop, entered from the social hub.
- Entering a match, eliminating opponents, scoreboard and statistics.
- Coins and XP for eliminations, assists, streaks and match completion.
- Crates bought with coins that unlock weapons, with duplicates converted to coins.
- Loadout editing in the Collection window (ECONOMY.md, WEAPON_CATALOG.md).

- A social hub with an armory station, crate shop station, shooting range, tutorial and matchmaking portals (section 11).

All of this awaits Studio verification. **Planned:** challenges, achievements and the battle pass (Phase 7).

## 3. Game modes

Mode values live in `src/shared/Config/GameModes.luau`. Each mode has a `Kind` that selects its flow in the single generic `MatchService` (D-031), and `MatchService` refuses to start any mode with `Implemented = false`. Each place runs exactly one mode, chosen by its `PlaceConfig` (D-030; DEPLOYMENT.md).

| Mode | Kind | Status | Start / capacity | Format | Respawn | Spawn protection | Progression |
|---|---|---|---|---|---|---|---|
| Social Hub | Lobby | **Implemented** | 1 / 40 | No matches; weapons work on training dummies only | 2 s | 0 | **None** |
| Free-for-All | FreeForAll | **Implemented** | 1 / 20 | 900 s, 20 s intermission | 3 s | 5 s | Yes |
| Team Deathmatch | TeamDeathmatch | **Implemented** | 2 / 16 (D-032) | 10 s countdown, 600 s or first to 50 team eliminations, 20 s intermission | 5 s | 5 s | Yes |
| Casual Duel 1v1 | Duel | **Implemented** | 2 / 2 | 5 s countdown, best of five (`RoundsToWin = 3`), 120 s rounds, 4 s between rounds, 15 s intermission | Spectate until next round | 5 s per round | Yes |
| Casual Team Duel | Duel | **Implemented** | 2 × TeamSize / 8 | Best of seven (`RoundsToWin = 4`), 150 s rounds; TeamSize 2 by default, 3v3 / 4v4 via `PlaceConfig.TeamSize` | Spectate until next round | 5 s per round | Yes |
| Ranked Duel 1v1 / 2v2 | Duel | Planned (RNK-01 to RNK-07) | 2 / 4 | Best of nine (`RoundsToWin = 5`) | Spectate | 0 | Rating plus seasonal rewards |
| Private Match | FreeForAll | Planned (NET-06) | 1 / 16 | Host-configured | 3 s | 5 s | **None**: no coins, XP, rating or challenge progress (`AwardsProgression = false`, tested) |

`MinPlayers` is the start threshold; capacity is the place's Roblox server size (D-032). Team Deathmatch starts with 2 players so it can be tested, and 5v5 / 8v8 places set a server size of 10 / 16.

### Match phases (`src/server/Services/MatchService.luau`)

| Phase | Meaning |
|---|---|
| Lobby | Hub only. Always on. Players can never damage each other (`CanDamage` is always false). |
| Waiting | Fewer loaded players than the start threshold (Duel: `2 × TeamSize`). Players can move; combat is disabled. |
| Countdown | Enough players; the match starts when the countdown ends. It falls back to Waiting if players leave. |
| Active | Combat is allowed for participants. In duels only players still alive in the current round can fight. |
| RoundEnd | Duel only: a 4 s pause between rounds. |
| Intermission | Results and map vote; combat disabled; then the next match. |

Combat permission is decided by `MatchService:IsCombatAllowed` (may this player use weapons) and `MatchService:CanDamage` (may this attacker hurt this victim: both allowed, victim alive, and opponents). In team modes, teammates are never opponents, so friendly fire is impossible.

### Free-for-All (implemented)
- Every player competes independently. A match lasts 15 minutes, then a 20-second intermission shows the top results, runs the map vote and disables combat; then a new match starts and everyone respawns.
- Ranking: eliminations (descending), then deaths (ascending), assists (descending), damage (descending), and earliest join (`src/server/Domain/MatchRules.luau`).
- A win means first place with at least one elimination (D-016).
- Rewards: each elimination pays coins and XP under the anti-farming rules. Every ranked entry gets match-completion XP, and first place with at least one elimination gets bonus XP; no coin value is specified for that (D-029).

### Team Deathmatch (implemented)
- Two teams, Alpha (`A`) and Bravo (`B`). At match start, loaded players are balanced alternately in join order (`Domain/Teams.Balance`). Late joiners go to the smaller team (`Teams.Pick`).
- Each elimination by a team member adds one point to that team. The first team to 50 wins; at 600 s the higher score wins, and equal scores are a draw (`Teams.DeathmatchWinner`).
- Players respawn after 5 s at their team's spawns when the map has team-tagged spawns.
- Winners get the Team Deathmatch victory reward (ECONOMY.md §2). A draw records neither a win nor a loss.

### Casual duels (implemented)
- At match start, loaded players fill two teams of `TeamSize` in join order. Anyone beyond that spectates until the next match (D-034), and so does anyone who joins while a duel is running.
- Each round, every participant respawns at their team's spawns with 5 s of protection. There are no respawns within a round. Eliminated players spectate surviving participants, teammates first, and cycle targets with FIRE / AIM (`SpectatorController`).
- The last team with a living member wins the round. At the round time limit the team with more survivors wins, then the team with more total health; a full tie replays the round (D-033, `Domain/DuelRounds`).
- A team whose players all leave forfeits the match. The first team to `RoundsToWin` round wins takes the match and the duel victory reward.

### Map voting (implemented)
At intermission, modes with `MapVote = true` offer up to 3 maps that support the mode, excluding the current map when others exist (D-035, `Domain/MapVote`). Players vote with the vote panel and may change their vote. The most votes wins and ties are broken randomly; with no votes, a random option wins. The new map loads at the end of intermission and everyone is respawned onto it.

## 4. Player mechanics

`src/shared/Config/Player.luau`, `Camera.luau`

| Property | Value |
|---|---|
| Maximum health | 150 |
| Walk speed | 16 studs/s |
| Run speed (hold sprint) | 22 studs/s |
| Jump power | 50 (about 6.4-stud jump at gravity 196.2) |
| Hitbox | Standardized capsule (body) plus sphere (head) in root space: body from −2.4 to +1.1 with radius 1.15; head at +1.85 with radius 0.75 |

- Movement is limited to walking, running and jumping. There is no sliding, double jumping, wall running, dashing or supernatural movement.
- Avatars are cosmetic. Combat uses only the standardized hitbox, so avatar size and accessories never matter (D-003). R15 rigs get procedural weapon poses; other rigs still play, but without the pose (DEV-ANIM-001).

**Camera (implemented):** free first-person/third-person toggle; over-the-shoulder third person with camera collision; FOV 70–100 (default 80); sensitivity 0.1–3.0; aim-sensitivity multiplier 0.1–1.5; recoil kick with 6°/s recovery; configurable crosshair style, colour and size. Shots always originate at the standardized head, so a third-person camera cannot shoot around cover (D-012).

## 5. Health and recovery

`src/shared/Config/Pickups.luau`, `src/shared/Combat/HealthRules.luau`

- Every life starts at 150 HP. There is **no automatic regeneration**: the default Roblox regeneration script is replaced by an empty `Health` script, and `HealthService` reverts any unexpected increase.
- Health comes back only from map pickups, which the server validates and consumes. Health can never exceed 150 (tested).

| Pack | Restores | Respawn |
|---|---:|---:|
| Small | 25 HP | 10 s |
| Medium | 50 HP | 20 s |
| Large | 100 HP | 30 s |

Pickups are not consumed by players at full health or by dead players. The pickup radius is 4 studs horizontally and 5 studs vertically, polled every 0.1 s.

## 6. Loadouts

Each player carries a **primary firearm, a secondary firearm and one knife**, and can switch at any time. Switching cancels an in-progress reload and applies the weapon's equip time.

- **Implemented:** the starter loadout (Vanguard AR, Warden P9, Ranger Combat Knife). The server resolves the weapon in each slot from the player's saved preset **and** owned inventory. Unowned, unknown or wrong-slot weapons are replaced with the starter weapon and audited (`src/server/Domain/Loadout.luau`, tested). Clients only ever send slot names.
- **Implemented (Phase 3):** editing the active preset in the Collection window's Armory tab. `InventoryService` validates ownership and slot; the change applies on the next spawn. **Planned:** multiple presets (purchasable extra presets in MONETIZATION.md) and the lobby armory (LOB-02).
- **Ammunition:** limited magazine plus reserve, with manual reload (auto-reload when the magazine empties). Ammo pickups add one magazine per firearm, capped at the maximum reserve, and respawn after 15 s (D-015). Respawning restores the full starting loadout.

Full statistics are in WEAPON_CATALOG.md.

## 7. Knife rules

`src/shared/Combat/KnifeState.luau`, `src/server/Services/ProjectileService.luau`

| Action | Input (KB/M) | Behaviour |
|---|---|---|
| Slash | Primary fire | Fast and lighter: about 60% of base damage, 7-stud reach, 70° cone (D-014) |
| Stab | Aim button | The specified base damage, 6.5-stud reach, 50° cone |
| Throw | G | Server-simulated projectile at 140 studs/s with gravity 40, maximum flight 2.5 s; base damage, ×1.5 on headshot |
| Recover | Walk within 5 studs | Only the owner can recover their own thrown knife |
| Replace | Stand at a knife station | Grants a fresh knife (2 s per-player cooldown) and removes the old one from the world |

- Each player has exactly one knife. While it is thrown, the player **cannot slash, stab or throw** until it is recovered, replaced or the player respawns (tested).
- A dropped knife despawns after 30 s, after which a station or respawn is required (D-019).
- **Planned:** knife inspection with final animations (the current version is procedural, DEV-ANIM-001), and knife trails and elimination counters as cosmetics (Phase 7/9).

## 8. Eliminations, respawning and protection

- **Implemented:** kill feed (killer, weapon, headshot marker), assist credit (at least 40 damage within 10 s), killstreak announcements at 3, 5, 7, 10, 15 and 20, and directional damage indicators.
- The elimination screen shows the killer, their weapon, their remaining health and their level.
- A death with no direct killer (reset or out of bounds) credits the top recent attacker as "finished off" (D-013).
- **Spawn selection** favours spawns far from living opponents and penalizes spawns near recent eliminations, spawns used recently, and spawns in an opponent's line of sight. It picks randomly among near-best spawns (`Config/Spawning.luau`).
- **Spawn protection:** 5 s in casual modes, shown with a visible force field. It ends immediately when the protected player fires, attacks or throws. Protected players take no damage.
- **Implemented:** duel spectating (section 3). **Planned:** ranked spectating features (RNK-05) and an optional killcam (CMB-16, feasibility to be decided).

## 9. Progression, economy and collection

**Implemented (Phase 3):**
- **Coins:** earned and purchased balances kept separately, shown as one wallet.
- **Match rewards:** see ECONOMY.md §2.
- **Levels 1–100:** XP from `1000 + 100 × (level − 1)` per level; 100 coins per level plus 400 at every 10th level, each paid once (D-022).
- **Crates:** 13 crates with exact per-item odds shown before purchase; duplicates converted to coins.
- **Collection:** 40 weapons (3 starters plus 37 collectibles) across 8 collections (WEAPON_CATALOG.md).

**Planned:** prestige (at level 100), competitive divisions, achievements, titles and weapon mastery (PRG-01 to PRG-03, RNK-01/02). Schema v2 already has fields for them (DATA_SCHEMA.md). Monetization is in MONETIZATION.md.

## 10. Explicit exclusions (spec §29)

The following require new owner authorization:

- Clan or guild systems
- Player trading, player marketplaces, item gifting, auctions or external sales
- Automatic health regeneration
- Unlimited ammunition
- Pay-to-win mechanics: no paid damage, health or other competitive advantages
- Custom replacement player characters (existing Roblox avatars are used)
- Advanced parkour movement during combat
- Graphic violence (blood, injuries, dismemberment)
- Real-money item cash-outs
- Unapproved external dependencies (D-004)

## 11. Social hub and tutorial (implemented, Phase 4)

The hub is its own place (`places/hub.project.json`, Lobby mode, map DEV-MAP-003; MAP_DESIGN.md §2.3). Every destination there is also reachable from the interface (UI_GUIDELINES.md §10).

| Destination | How it works |
|---|---|
| Matchmaking portals | Four portals (Free-for-All, Team Deathmatch, Duel 1v1, Team Duel 2v2). A portal prompt or the PLAY menu sends a destination id; the server teleports the player to that place (`PortalService`). |
| Armory | Station prompt opens the Collection window on the Armory tab. |
| Crate shop | Station prompt opens the Collection window on the Crates tab. |
| Shooting range | Six training dummies with 150 HP each that reset 2 s after being knocked down. They give no coins, XP or statistics (`TrainingService`). |
| Training zone | One small health pack, one ammo pack and a knife station. |
| Tutorial | Station prompt starts (or replays) the tutorial. |
| Parkour course | Six platforms, each 2 studs higher than the previous one. |

Players cannot damage each other anywhere in the hub. Hub practice never changes persistent statistics (D-040).

**Planned hub features (not built):** VIP lounge and battle pass station (Phase 7), quest stations (Phase 7), leaderboards (Phase 6), weapon exhibitions, seasonal decorations and public announcements (Phase 12), and player profile inspection (Phase 6).

### Tutorial (`Config/Tutorial.luau`, `TutorialService`, `Domain/TutorialProgress`)
Twelve steps in order: movement, camera, weapon selection, aim and shoot, reload, knife attacks, knife throw and recovery, health and ammo pickups, coins, crate opening, loadout customization, matchmaking.

- Steps the client can observe (movement, camera, weapon switching, the informational coins step, travel intent) are reported by the client. Combat and economy steps complete only from server-observed events: a firearm hit on a dummy, a reload, a knife hit on a dummy, a knife recovery, both a health and an ammo pickup, a crate opening, and a loadout change.
- Before the pickups step the server drains 60 HP (never lethally) and empties firearm reserves, so both packs are useful.
- **Reward (SPEC):** 500 coins and one free Basic Crate, granted once per account when the coins step completes (D-036). The crate arrives as a free crate token (D-037) so the next step can teach opening it.
- First-time players start the tutorial automatically and **must complete it** before the hub's portals will send them to a match. Players who have completed it can replay it from the Training station and exit a replay at any time; replays never grant the reward again.

