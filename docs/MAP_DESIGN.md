# Map Design

Maps plug into core systems only through **CollectionService tags** and a few model attributes, so a new map never requires combat-code changes (`src/server/Services/MapService.luau`).

## 1. Map contract (implemented)

### Tags

| Tag | Instance | Meaning |
|---|---|---|
| `Crossblade.Spawn` | BasePart | Spawn point; the part's CFrame gives position and facing. The character is placed 3.5 studs above it. |
| `Crossblade.HealthPickup` | BasePart | Health pack. **Requires** the attribute `Size` = `"Small"`, `"Medium"` or `"Large"`; anything else is ignored with a warning. |
| `Crossblade.AmmoPickup` | BasePart | Ammunition pickup |
| `Crossblade.KnifeStation` | BasePart | Knife replacement station |
| `Crossblade.DroppedKnife` | Model (runtime) | Added by ProjectileService to landed thrown knives; do not author it |

### Map Model attributes

| Attribute | Type | Default if missing |
|---|---|---|
| `MapId` | string | none |
| `DisplayName` | string | `"Arena"` |
| `KillHeight` | number | `-50`: characters below this Y are eliminated (environmental) |

### Rules
- Pickup and marker parts must be `CanQuery = false` and `CanCollide = false`, so they never block line of sight or movement.
- Solid cover must be `CanQuery = true`, because server line-of-sight checks raycast against it.
- Characters are always excluded from line-of-sight checks.
- A map with no `Crossblade.Spawn` parts aborts server boot with an error.

### Map source priority
1. The first Model found in `ServerStorage.Maps`, which is cloned into Workspace (a Studio-authored map).
2. Otherwise the generated development greybox (DEV-MAP-001).

## 2. Development greybox: "Foundry Yard" (implemented, temporary)

Source: `src/server/Maps/DevArena.luau`. Tracked as DEV-MAP-001 (D-010).

| Property | Value |
|---|---|
| Play area | 180 × 180 floor, top surface at Y = 0 |
| Boundary | Four 16-high steel walls at ±91 |
| Kill height | −40 |
| Lighting | ClockTime 14.5, Brightness 2, Ambient (90, 92, 88), OutdoorAmbient (120, 122, 116) |
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
| Spawns | 16 | Ring around the centre at alternating radii 80 and 66, each facing the centre |
| Small health | 4 | (±20, ±34) |
| Medium health | 2 | (±55, 0) |
| Large health | 1 | Platform centre (0, 7.5, 0) |
| Ammo | 4 | (±50, ±55) |
| Knife stations | 2 | (0, ±45) |

**Layout fixes (2026-11-26):** the Small health packs moved from (±30, ±40), where two sat inside rotated L-wall copies, to (±20, ±34). The outer lane pillar moved from (70, 70) to (58, 68) so it no longer clips the corner tower.

## 3. Per-map checklist (every authored map)

- [ ] At least 16 spawns for FFA, spread so no spawn sees another at short range. Team modes add team spawn groups later (MOD-02).
- [ ] Health pickups: a mix of Small, Medium and Large. The Large pack sits in a contested or exposed position.
- [ ] At least one ammo pickup per quadrant, and at least two knife stations.
- [ ] Short-range routes (corners, interiors) and at least one long sightline that cover can break.
- [ ] No unreachable elevated positions: at most 6 studs of rise per step at the current jump settings.
- [ ] Boundaries: solid perimeter plus `KillHeight` set below the lowest walkable surface.
- [ ] Map Model has `MapId`, `DisplayName` and `KillHeight` attributes.
- [ ] Performance: anchored geometry, merged or instanced where possible, shadows disabled on small decorative parts, part count within the mobile budget (TEST_PLAN.md).
- [ ] Original art only; record any imported assets in ASSET_MANIFEST.md.

## 4. Authoring a map in Studio

1. Build the map as one Model. Tag spawn, pickup and station parts with the tags in §1 (Studio Tag Editor or `CollectionService:AddTag`).
2. Set the attributes on the Model, and the `Size` attribute on each health pickup.
3. Place the Model in `ServerStorage.Maps`. The first Model found there replaces the greybox at boot.
4. Playtest: every pickup should be collectable, every spawn reachable, and no pickup inside geometry.

Multi-map rotation and map voting are planned (CMB-15/MOD-03). MapService will then choose among several Models instead of taking the first.

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

The central social hub (LOB-01) is a separate place with PvP disabled; designated practice areas are isolated.
