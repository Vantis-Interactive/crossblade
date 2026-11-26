# Asset Manifest

Every asset used by the experience, with its source and licence. **No Roblox asset IDs have been uploaded or referenced yet.** Every visual in the current build is generated from primitive parts in code, including all 40 catalog weapons (tinted by collection), and the build contains no audio. Asset IDs must never be invented (directive §2.16): an asset is added here only once it exists and has been uploaded under the owner's account.

## Temporary development assets (must be replaced before public beta)

| ID | Asset | Where | Replaced by | Blocking phase |
|---|---|---|---|---|
| DEV-MAP-001 | "Foundry Yard" greybox arena, generated from data | `src/server/Maps/DevArena.luau` | Studio-authored maps in `ServerStorage.Maps` using the tag contract in MAP_DESIGN.md | Phase 9 |
| DEV-MAP-002 | "Outpost Yard" greybox arena (duels, Team Deathmatch), generated from data | `src/server/Maps/DevOutpost.luau` | Authored "Outpost" desert base (spec §17 map 3) | Phase 9 |
| DEV-MAP-003 | "Crossblade Hub" greybox social hub, generated from data | `src/server/Maps/DevHub.luau` | Authored modern stylized hub (spec §18) | Phase 9 |
| DEV-MARKER-001 | Neon panels for portals and stations, neon pickup shapes, invisible spawn and dummy-spot markers | `MapService.buildLayout` | Authored portal arches, kiosks and pickup models (must keep `CanQuery = false`) | Phase 9 |
| DEV-DUMMY-001 | Primitive training dummy (torso, head, legs, stand, health billboard) | `TrainingService.build` | Authored training target model; hit detection keeps using the standardized hitbox | Phase 9 |
| DEV-MODEL-001 | Primitive rifle model | `src/shared/Weapons/WeaponModels.luau` (`Rifle`) | Original rifle meshes per collectible | Phase 9 |
| DEV-MODEL-002 | Primitive pistol model | same (`Pistol`) | Original pistol meshes | Phase 9 |
| DEV-MODEL-003 | Primitive knife model | same (`Knife`) | Original knife meshes | Phase 9 |
| DEV-MODEL-004 | Primitive SMG model | same (`SMG`) | Original SMG meshes | Phase 9 |
| DEV-MODEL-005 | Primitive shotgun model | same (`Shotgun`) | Original shotgun meshes | Phase 9 |
| DEV-MODEL-006 | Primitive sniper rifle model | same (`Sniper`) | Original sniper meshes | Phase 9 |
| DEV-MODEL-007 | Primitive revolver model | same (`Revolver`) | Original revolver meshes | Phase 9 |
| DEV-SKIN-001 | Collection finish tints (part colours by `Finish`/`Accent`/`Steel` role) | `src/shared/Config/Collections.luau`, `WeaponModels.palette` | Authored skins and materials per collectible | Phase 9 |
| DEV-CONTENT-001 | 37 Phase 3 collectible definitions (original names, all on dev models) | `src/shared/Config/Weapons/Catalog.luau` (D-028) | Final 150-weapon launch catalog with authored models; names and ids may be kept | Phase 9 |
| DEV-ANIM-001 | Procedural arm poses and viewmodel motion (swing, inspect, reload) | `AnimationController.luau`, `ViewmodelController.luau` | Original animations uploaded to the owner's group | Phase 9 |
| DEV-FX-001 | Neon-part tracers, impacts, muzzle flashes and elimination pulse | `EffectsController.luau` | Final VFX (still non-graphic) | Phase 9 |

## Missing assets (features blocked, not faked)

| ID | Needed for | Status |
|---|---|---|
| AUD-001 | Weapon fire, reload and knife sounds | Not implemented. Needs licensed or original audio. `AudioProfile` is already a field on every catalog entry. |
| AUD-002 | Footsteps, ambience, music, announcer, UI sounds | Not implemented (spec §21). |
| ICON-001 | Game icon and thumbnails | Phase 11. |

## Licensing rules
- Only original assets, or assets licensed for commercial use in Roblox experiences, may be added.
- Record the source, author, licence and upload ID for every asset added to this file.
- Do not copy protected models, artwork, branding, sounds or interfaces from other games (directive §11).
