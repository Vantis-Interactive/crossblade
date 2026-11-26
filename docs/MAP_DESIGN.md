# Map Design

Maps plug into core systems only through **CollectionService tags** and a few model attributes, so a new map never requires combat-code changes (`src/server/Services/MapService.luau`).

## 1. Map contract (implemented)

### Tags

| Tag | Instance | Meaning |
|---|---|---|
| `Crossblade.Spawn` | BasePart | Spawn point; the part's CFrame gives position and facing. The character is placed 3.5 studs above it. Optional attribute `Team` = `"A"` or `"B"`: in team modes a player spawns only at their team's spawns when the map has any (`SpawnService`). |
| `Crossblade.HealthPickup` | BasePart | Health pack. **Requires** the attribute `Size` = `"Small"`, `"Medium"` or `"Large"`; anything else is ignored with a warning. |
| `Crossblade.AmmoPickup` | BasePart | Ammunition pickup |
| `Crossblade.KnifeStation` | BasePart | Knife replacement station |
| `Crossblade.Portal` | BasePart | Matchmaking portal (hub). **Requires** the attribute `Destination`, a key of `Config.Places.Destinations`. `PortalService` adds a "Join" ProximityPrompt. |
| `Crossblade.Station` | BasePart | Interaction station (hub). **Requires** the attribute `Station` = `"Armory"`, `"Crates"` or `"Tutorial"`. `PortalService` adds an "Open" / "Start Tutorial" ProximityPrompt. |
| `Crossblade.DummySpot` | BasePart | Training dummy position; the part's CFrame gives facing. `TrainingService` builds a dummy whose root sits 3 studs above it. |
| `Crossblade.DroppedKnife` | Model (runtime) | Added by ProjectileService to landed thrown knives; do not author it |
| `Crossblade.Dummy` | Model (runtime) | Added by TrainingService to built training dummies; do not author it |

### Map Model attributes

| Attribute | Type | Default if missing |
|---|---|---|
| `MapId` | string | none |
| `DisplayName` | string | `"Arena"` |
| `KillHeight` | number | `-50`: characters below this Y are eliminated (environmental) |
| `Modes` | string | **Required** for authored maps: comma-separated mode ids the map supports, e.g. `"FreeForAll,TeamDeathmatch"`. Maps without `MapId` and `Modes` are ignored with a warning. |

### Rules
- Pickup and marker parts must be `CanQuery = false` and `CanCollide = false`, so they never block line of sight or movement.
- Solid cover must be `CanQuery = true`, because server line-of-sight checks raycast against it.
- Characters are always excluded from line-of-sight checks.
- A map with no `Crossblade.Spawn` parts aborts server boot with an error.

### Map sources and rotation
- **Registry.** At boot `MapService` registers every greybox layout module in `src/server/Maps` and every Model in `ServerStorage.Maps` that has `MapId` and `Modes`. An authored map with the same `MapId` as a greybox replaces it.
- **Initial map.** `PlaceConfig.Map` if it names a registered map; otherwise the first map id, in sorted order, that supports the place's mode. With the current greyboxes: Free-for-All and Team Deathmatch start on `dev_foundry_yard`, duels on `dev_outpost_yard`, and the hub on `dev_hub`.
- **Swapping.** `MapService:Load(mapId)` destroys the current map, builds or clones the new one, applies greybox lighting, and fires `MapChanged`. PickupService and TrainingService rebuild, ProjectileService removes thrown knives, SpawnService clears its recent-death and spawn-reuse history, and PortalService adds prompts.
- **Voting.** At intermission, modes with `MapVote = true` offer up to 3 maps from `MapService:MapsForMode`, excluding the current map when there are others (D-035). The winner loads at the end of intermission and every player is respawned onto it. With the current greyboxes, Free-for-All has one map (so the vote offers Foundry Yard again), and Team Deathmatch alternates between Foundry Yard and Outpost Yard.

## 2. Development greyboxes (implemented, temporary)

All three are generated from data and are covered by `tests/specs/DevArena.spec.luau`, which checks for every map: its modes exist and are implemented; no pickup, station or dummy spot is inside geometry; no spawn is inside or within 2 studs of geometry; every marker (including portals) is inside the perimeter and above the kill height; and maps supporting a team mode have balanced team spawns, at least 4 per team.

### 2.1 "Foundry Yard" (`dev_foundry_yard`)

Source: `src/server/Maps/DevArena.luau`. Tracked as DEV-MAP-001 (D-010).

| Property | Value |
|---|---|
| Play area | 180 × 180 floor, top surface at Y = 0 |
| Boundary | Four 16-high steel walls at ±91 |
| Kill height | −40 |
| Lighting | ClockTime 14.5, Brightness 2, Ambient (90, 92, 88), OutdoorAmbient (120, 122, 116) |
| Modes | FreeForAll, TeamDeathmatch |
| Symmetry | Cover is placed with 4-fold rotational symmetry (`quad()`); pickups are mirrored across both axes |

**Structures**
- **Central platform:** 28 × 6 × 28 (top at Y = 6), with two wedge ramps (10 × 6 × 14) on the north and south faces and two low parapets (8 × 2.5 × 1) for partial cover. This is the contested position holding the Large health pack.
- **Mid-quadrant L-walls:** 18 × 8 × 2 plus 2 × 8 × 12, ×4 rotated.
- **Crate clusters:** 5 × 5 × 5 and 5 × 3 × 5 (head-height and waist-height cover), plus 4 × 4 × 4 crates near the east/west lanes.
- **Lane pillars:** 3 × 12 × 3 at two depths per quadrant, to break up long sightlines.
- **Corner towers:** 12 × 5 × 12, elevated and exposed for long-range play. With JumpPower 50 and gravity 196.2, jump height is v²/2g = 2500/392.4 ≈ 6.4 studs. The 5-stud tower is therefore reached from a 4 × 2.5 × 4 step crate, a 2.5-stud rise each way.

**Markers**

| Kind | Count | Placement |
|---|---:|---|
| Spawns | 16 | Ring around the centre at alternating radii 80 and 66, each facing the centre. East half (X ≥ 0) is team Alpha, west half Bravo: 8 each |
| Small health | 4 | (±20, ±34) |
| Medium health | 2 | (±55, 0) |
| Large health | 1 | Platform centre (0, 7.5, 0) |
| Ammo | 4 | (±50, ±55) |
| Knife stations | 2 | (0, ±45) |

**Layout fixes (2026-11-26):** the Small health packs moved from (±30, ±40), where two sat inside rotated L-wall copies, to (±20, ±34). The outer lane pillar moved from (70, 70) to (58, 68) so it no longer clips the corner tower.

### 2.2 "Outpost Yard" (`dev_outpost_yard`)

Source: `src/server/Maps/DevOutpost.luau`. Tracked as DEV-MAP-002.

| Property | Value |
|---|---|
| Modes | CasualDuel1v1, CasualDuelTeam, TeamDeathmatch |
| Play area | 120 × 120 sand floor, top at Y = 0 |
| Boundary | Four 14-high steel walls at ±61 |
| Kill height | −40 |
| Lighting | ClockTime 16.5, Brightness 2.2 |
| Symmetry | Mirrored across X, so both teams get identical cover |

**Structures:** raised centre 12 × 6 × 12 (6 studs, reached by two 8 × 6 × 10 wedge ramps at Z = ±11, not by jumping); mid cover 2 × 6 × 14 at X = ±20; crates 5 × 4 × 5 at (±30, ±20); flank walls 16 × 8 × 2 at (±38, ±32); spawn shields 2 × 3 × 8 at (±42, 0).

| Kind | Count | Placement |
|---|---:|---|
| Spawns | 8 | Alpha at X = −50, Bravo at X = +50, Z = −15, −5, 5, 15 |
| Small health | 2 | (±28, 0) |
| Medium health | 1 | Centre top (0, 7.5, 0) |
| Ammo | 4 | (±14, ±24) |
| Knife stations | 2 | (±50, 28) |

### 2.3 "Crossblade Hub" (`dev_hub`)

Source: `src/server/Maps/DevHub.luau`. Tracked as DEV-MAP-003. Mode: Lobby only.

| Area | Layout |
|---|---|
| Play area | 220 × 220 slate floor, 12-high walls at ±111, kill height −30, ClockTime 13 |
| Plaza spawn | 8 spawns on a radius-12 ring at the centre |
| Portals (north) | Four arches at X = −45, −15, 15, 45 (Free-for-All, Team Deathmatch, Duel 1v1, Team Duel 2v2); portal markers at Z = −80 |
| Armory station | (−60, 2.5, 0) with a backboard |
| Crate shop station | (60, 2.5, 0) with a backboard |
| Tutorial station | (55, 2.5, 40) with a backboard |
| Shooting range (south) | Firing-line rail at Z = 60, side walls at X = ±42, backstop 84 × 12 × 2 at Z = 104; six dummy spots at X = −30, −18, −6, 6, 18, 30 alternating between Z = 95 and Z = 88, facing the firing line |
| Training zone | Small health (70, 55), ammo (80, 55), knife station (90, 55) |
| Parkour course | Six 6 × 1 × 6 platforms starting at (60, 1.5, −40), each 8 studs further east and 2 studs higher |

Portal markers are 10 × 12 × 0.5 translucent neon panels; station markers are 3 × 5 × 0.6 neon panels; dummy spots are invisible. All are `CanQuery = false` and `CanCollide = false`.

## 3. Per-map checklist (every authored map)

- [ ] At least 16 spawns for FFA, spread so no spawn sees another at short range. Maps supporting a team mode tag balanced `Team = "A"` / `"B"` spawn groups (at least 4 each).
- [ ] Health pickups: a mix of Small, Medium and Large. The Large pack sits in a contested or exposed position.
- [ ] At least one ammo pickup per quadrant, and at least two knife stations.
- [ ] Short-range routes (corners, interiors) and at least one long sightline that cover can break.
- [ ] No unreachable elevated positions: at most 6 studs of rise per step at the current jump settings.
- [ ] Boundaries: solid perimeter plus `KillHeight` set below the lowest walkable surface.
- [ ] Map Model has `MapId`, `DisplayName`, `KillHeight` and `Modes` attributes.
- [ ] Performance: anchored geometry, merged or instanced where possible, shadows disabled on small decorative parts, part count within the mobile budget (TEST_PLAN.md).
- [ ] Original art only; record any imported assets in ASSET_MANIFEST.md.

## 4. Authoring a map in Studio

1. Build the map as one Model. Tag spawn, pickup and station parts with the tags in §1 (Studio Tag Editor or `CollectionService:AddTag`).
2. Set the attributes on the Model, and the `Size` attribute on each health pickup.
3. Set `Modes` to the comma-separated mode ids the map supports, then place the Model in `ServerStorage.Maps`. It joins the registry and the map vote for those modes; use the same `MapId` as a greybox to replace that greybox.
4. Playtest: every pickup should be collectable, every spawn reachable, and no pickup inside geometry. Authored maps are not covered by `DevArena.spec` (it reads layout modules), so check them manually against §3.

## 5. Planned arena collection (spec §17; Phase 9)

| # | Map | Theme |
|---:|---|---|
| 1 | Downtown | Urban city and rooftops |
| 2 | Lockdown | Abandoned prison |
| 3 | Outpost | Desert military base |
| 4 | Frostbite | Arctic research facility |
| 5 | Neon District | Cyberpunk city |
| 6 | Shipwreck | Tropical island and cargo ship |
| 7 | Blacksite | Underground laboratory |
| 8 | Foundry | Industrial factory |
| 9 | Skyfall | Floating platforms |
| 10 | Overgrowth | Jungle ruins |

The central social hub is a separate place with player damage disabled everywhere (§2.3). Its practice area uses training dummies only.
