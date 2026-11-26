# Game Design

Working title: **Crossblade** (D-001, pending owner approval).

A fast, skill-based multiplayer PvP arena game with guns and knives, a deep weapon collection and persistent progression. It is free to play, and paid content never grants a combat advantage.

Each section separates **Implemented (Phase 2)** from **Specified / planned**. Implemented numbers come from source files, which are cited. Planned numbers are the directive's values and become configuration when their phase is built.

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

**Implemented (Phase 2):** entering a match, eliminating opponents, scoreboard and statistics.
**Planned:** coins, XP, crates, unlocks and loadout editing (Phase 3: ECO-01 to ECO-05).

## 3. Game modes

Mode values live in `src/shared/Config/GameModes.luau`. `MatchService` refuses to start any mode with `Implemented = false`.

| Mode | Status | Players | Duration / format | Respawn | Spawn protection | Progression |
|---|---|---|---|---|---|---|
| Free-for-All | **Implemented** | 1–20 per server (`MinPlayers = 1`, `MaxPlayers = 20`) | 900 s rounds, 20 s intermission | 3 s | 5 s | Yes |
| Team Deathmatch | Planned (MOD-02) | 5v5 and 8v8 (config: 10–16) | 600 s, first to 50 team eliminations | 5 s | 5 s | Yes |
| Casual Duel 1v1 | Planned (MOD-01) | 2 | Best of five (`RoundsToWin = 3`) | Spectate until next round | 5 s | Yes |
| Casual Duel 2v2–4v4 | Planned (MOD-01) | 4–8 | Best of seven (`RoundsToWin = 4`) | Spectate | 5 s | Yes |
| Ranked Duel 1v1 / 2v2 | Planned (RNK-01 to RNK-07) | 2–4 | Best of nine (`RoundsToWin = 5`) | Spectate | 0 | Rating plus seasonal rewards |
| Private Match | Planned (NET-06) | 1–16 | Host-configured | Host-configured | 5 s | **None**: no coins, XP, rating or challenge progress (`AwardsProgression = false`, tested) |

### Free-for-All (implemented)
- Every player competes independently. A round lasts 15 minutes, then shows a 20-second intermission with the top 10 results and combat disabled, then a new round starts and everyone respawns.
- Ranking: eliminations (descending), then deaths (ascending), assists (descending), damage (descending), and earliest join (`src/server/Domain/MatchRules.luau`).
- A win means first place with at least one elimination (D-016).
- **Not yet implemented:** map voting between rotations (CMB-15/MOD-03), which needs at least two maps, and coin/XP rewards (Phase 3).

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
- **Planned:** loadout editing, presets and the armory (ECO-03, LOB-02).
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
- **Planned:** spectator mode for duels (RNK-05) and an optional killcam (CMB-16, feasibility to be decided).

## 9. Progression, economy and collection (planned)

Six independent progression systems: player levels (prestige at 100), prestige, competitive divisions, achievements, titles and weapon mastery (Phase 3/6/7: ECO-05, PRG-01 to PRG-03, RNK-01/02). Economy and crates are in ECONOMY.md; monetization is in MONETIZATION.md. Data schema v1 already has fields for all of them (DATA_SCHEMA.md), so these features can be added without a breaking migration.

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
