# Weapon Catalog

Every combat statistic belongs to an **archetype** (`src/shared/Config/Weapons/Archetypes.luau`). Collectible weapons (`src/shared/Config/Weapons/Catalog.luau`) only reference an archetype and hold no combat fields, so rarity can never increase combat power (D-008).

- `WeaponCatalog.Validate()` rejects any collectible that defines combat fields.
- A test fails if any combat module mentions `Rarity` (`tests/specs/WeaponCatalog.spec.luau`, "no combat module reads rarity"). The scan covers `src/shared/Combat`, `src/server/Domain` and `src/server/Services`. It exempts only `CrateOpening.luau` and `CrateService.luau`, where rarity legitimately drives odds and duplicate compensation.

## 1. Firearm archetypes (implemented as configuration)

Damage is per bullet, or per pellet for the shotgun. Distances are in studs.

| Archetype | Slot | Damage | Pellets | Head × | Mode | RPM | Mag / Reserve | Reload s | Equip s | Range | Falloff start–end | Min dmg × | Hip / Aim spread ° | Aim FOV | Recoil pitch / yaw ° |
|---|---|---:|---:|---:|---|---:|---|---:|---:|---:|---|---:|---|---:|---|
| Assault Rifle | Primary | 25 | 1 | 1.5 | Automatic | 600 | 30 / 90 | 2.2 | 0.45 | 300 | 60–180 | 0.7 | 2.0 / 0.6 | 55 | 0.9 / 0.35 |
| SMG | Primary | 18 | 1 | 1.4 | Automatic | 850 | 25 / 75 | 1.9 | 0.35 | 180 | 25–90 | 0.6 | 2.6 / 1.1 | 62 | 0.7 / 0.45 |
| Shotgun | Primary | 12.5 | 8 | 1.0 | Semi | 70 | 6 / 18 | 3.0 | 0.5 | 80 | 10–40 | 0.3 | 6.0 / 4.5 | 68 | 4.0 / 1.0 |
| Sniper Rifle | Primary | 100 | 1 | 2.0 | Semi | 45 | 5 / 15 | 3.2 | 0.7 | 1000 | none | 1.0 | 8.0 / 0.0 | 25 | 5.0 / 0.8 |
| Pistol | Secondary | 35 | 1 | 1.5 | Semi | 400 | 12 / 36 | 1.6 | 0.3 | 200 | 30–100 | 0.65 | 1.5 / 0.5 | 65 | 1.6 / 0.4 |
| Revolver | Secondary | 60 | 1 | 1.6 | Semi | 120 | 6 / 18 | 2.6 | 0.35 | 250 | 40–140 | 0.7 | 2.0 / 0.4 | 60 | 3.5 / 0.6 |

- Base damage values and magazine/reserve sizes match the specification and are asserted by tests.
- Shotgun maximum: 8 × 12.5 = 100 at close range ("up to 100").
- Falloff is linear from 1.0 at the falloff start to the minimum multiplier at the falloff end. Damage is rounded to 0.1 (`src/shared/Combat/DamageCalculator.luau`).
- "Automatic" pistols are a planned variant archetype: same slot, different RPM and fire mode.

## 2. Knife archetypes

| Archetype | Stab dmg / cooldown s | Slash dmg / cooldown s | Throw dmg / cooldown s | Throw head × |
|---|---|---|---|---:|
| Dagger | 60 / 0.7 | 36 / 0.38 | 60 / 1.0 | 1.5 |
| Karambit | 45 / 0.5 | 30 / 0.3 | 45 / 0.9 | 1.5 |
| Butterfly Knife | 50 / 0.6 | 32 / 0.33 | 50 / 0.95 | 1.5 |
| Combat Knife | 75 / 0.9 | 45 / 0.45 | 75 / 1.1 | 1.5 |

Shared knife values (`knife()` helper in `Archetypes.luau`):
- Stab: reach 6.5, cone 50°.
- Slash: reach 7, cone 70°.
- Throw: speed 140, gravity 40, maximum flight 2.5 s, ground lifetime 30 s, recover radius 5.
- Equip time 0.25 s.

Stab equals the specified base damage (D-014).

## 3. Shots to eliminate (150 HP, inside falloff start, every bullet hitting)

Time to eliminate (TTE) = (shots − 1) × 60 / RPM. It excludes reaction time and travel.

| Archetype | Body dmg | Body shots | Body TTE | Head dmg | Head shots | Head TTE |
|---|---:|---:|---:|---:|---:|---:|
| Assault Rifle | 25 | 6 | 0.50 s | 37.5 | 4 | 0.30 s |
| SMG | 18 | 9 | 0.56 s | 25.2 | 6 | 0.35 s |
| Shotgun (all 8 pellets) | 100 | 2 | 0.86 s | 100 | 2 | 0.86 s |
| Sniper Rifle | 100 | 2 | 1.33 s | 200 | 1 | instant |
| Pistol | 35 | 5 | 0.60 s | 52.5 | 3 | 0.30 s |
| Revolver | 60 | 3 | 1.00 s | 96 | 2 | 0.50 s |

| Knife | Stabs | Stab TTE | Slashes | Slash TTE | Best thrown hit |
|---|---:|---:|---:|---:|---|
| Dagger | 3 | 1.40 s | 5 | 1.52 s | 90 (head) |
| Karambit | 4 | 1.50 s | 5 | 1.20 s | 67.5 (head) |
| Butterfly Knife | 3 | 1.20 s | 5 | 1.32 s | 75 (head) |
| Combat Knife | 2 | 0.90 s | 4 | 1.35 s | 112.5 (head) |

No single thrown knife is lethal from full health.

**Balance note for review:** the sniper's 1.33 s for a two-shot body elimination equals its bolt interval. The headshot is the only one-shot elimination in the game.

## 4. Implemented collectibles

The catalog holds 40 weapons: 3 starters plus 37 collectibles (D-028). Names are original. Models are temporary primitive-part dev models tinted by collection (ASSET_MANIFEST.md DEV-MODEL-001 to 007). No audio exists yet (AUD-001).

`ModelProfile`, `AnimationProfile` and `AudioProfile` are derived from the archetype by the catalog's `add()` helper:

| Archetype | ModelProfile | AnimationProfile | AudioProfile |
|---|---|---|---|
| AssaultRifle | Rifle | TwoHanded | AssaultRifle |
| SubmachineGun | SMG | TwoHanded | SubmachineGun |
| Shotgun | Shotgun | TwoHanded | Shotgun |
| SniperRifle | Sniper | TwoHanded | SniperRifle |
| Pistol | Pistol | OneHanded | Pistol |
| Revolver | Revolver | OneHanded | Revolver |
| Dagger, Karambit, ButterflyKnife, CombatKnife | Knife | Knife | archetype id |

### Starters (`Starter = true`, `Catalog.StarterLoadout`; never in crate pools)

| Id | Name | Archetype | Rarity | Collection |
|---|---|---|---|---|
| `classic_ar_vanguard` | Vanguard AR | AssaultRifle | Common | Classic |
| `classic_pistol_warden` | Warden P9 | Pistol | Common | Classic |
| `classic_knife_ranger` | Ranger Combat Knife | CombatKnife | Common | Classic |

### Collectibles (37)

| Id | Name | Archetype | Rarity | Collection |
|---|---|---|---|---|
| `classic_dagger_field` | Field Dagger | Dagger | Common | Classic |
| `tactical_karambit_trench` | Trench Karambit | Karambit | Uncommon | Tactical |
| `inferno_butterfly_ember` | Ember Flicker | ButterflyKnife | Rare | Inferno |
| `arctic_knife_glacier` | Glacier Bowie | CombatKnife | Epic | Arctic |
| `cyber_karambit_talon` | Neon Talon | Karambit | Legendary | Cyberpunk |
| `galaxy_dagger_nebula` | Nebula Stiletto | Dagger | Mythical | Galaxy |
| `celestial_butterfly_starfall` | Starfall Butterfly | ButterflyKnife | Celestial | Celestial |
| `classic_pistol_courier` | Courier P7 | Pistol | Common | Classic |
| `arctic_revolver_snowline` | Snowline Revolver | Revolver | Uncommon | Arctic |
| `cyber_pistol_circuit` | Circuit Sidearm | Pistol | Rare | Cyberpunk |
| `inferno_revolver_cinder` | Cinder .44 | Revolver | Epic | Inferno |
| `galaxy_pistol_quasar` | Quasar Sidearm | Pistol | Legendary | Galaxy |
| `arctic_revolver_permafrost` | Permafrost Magnum | Revolver | Mythical | Arctic |
| `celestial_pistol_halo` | Halo Sidearm | Pistol | Celestial | Celestial |
| `tactical_ar_sentinel` | Sentinel AR | AssaultRifle | Common | Tactical |
| `inferno_ar_kindling` | Kindling Carbine | AssaultRifle | Uncommon | Inferno |
| `arctic_ar_whiteout` | Whiteout AR | AssaultRifle | Rare | Arctic |
| `cyber_ar_voltage` | Voltage AR | AssaultRifle | Epic | Cyberpunk |
| `inferno_ar_wildfire` | Wildfire Rifle | AssaultRifle | Legendary | Inferno |
| `galaxy_ar_eclipse` | Eclipse Rifle | AssaultRifle | Mythical | Galaxy |
| `celestial_ar_aurora` | Aurora Rifle | AssaultRifle | Celestial | Celestial |
| `classic_shotgun_breacher` | Breacher 12 | Shotgun | Common | Classic |
| `cyber_shotgun_static` | Static Scattergun | Shotgun | Uncommon | Cyberpunk |
| `arctic_shotgun_icebreaker` | Icebreaker | Shotgun | Rare | Arctic |
| `galaxy_shotgun_meteor` | Meteor Scatter | Shotgun | Epic | Galaxy |
| `arctic_shotgun_avalanche` | Avalanche | Shotgun | Legendary | Arctic |
| `cyber_shotgun_overclock` | Overclock | Shotgun | Mythical | Cyberpunk |
| `tactical_sniper_longwatch` | Longwatch | SniperRifle | Common | Tactical |
| `galaxy_sniper_orbit` | Orbit Marksman | SniperRifle | Uncommon | Galaxy |
| `inferno_sniper_flare` | Flare Lance | SniperRifle | Rare | Inferno |
| `arctic_sniper_polar` | Polar Lance | SniperRifle | Epic | Arctic |
| `cyber_sniper_railspike` | Railspike | SniperRifle | Legendary | Cyberpunk |
| `inferno_sniper_hellfire` | Hellfire Bolt | SniperRifle | Mythical | Inferno |
| `celestial_sniper_seraph` | Seraph Long Rifle | SniperRifle | Celestial | Celestial |
| `classic_smg_pathfinder` | Pathfinder SMG | SubmachineGun | Common | Classic |
| `galaxy_smg_pulsar` | Pulsar SMG | SubmachineGun | Rare | Galaxy |
| `shadow_smg_spectre` | Spectre SMG | SubmachineGun | Epic | Shadow |

### Counts versus the launch target (starters included)

| Rarity | Primary (now / target) | Secondary | Knives | Total now |
|---|---|---|---|---:|
| Common | 5 / 15 | 2 / 10 | 2 / 10 | 9 |
| Uncommon | 3 / 12 | 1 / 8 | 1 / 10 | 5 |
| Rare | 4 / 10 | 1 / 7 | 1 / 8 | 6 |
| Epic | 4 / 10 | 1 / 6 | 1 / 9 | 6 |
| Legendary | 3 / 7 | 1 / 5 | 1 / 6 | 5 |
| Mythical | 3 / 4 | 1 / 3 | 1 / 5 | 5 |
| Celestial | 2 / 2 | 1 / 1 | 1 / 2 | 4 |
| **Total** | **24 / 60** | **8 / 40** | **8 / 50** | **40** |

No count exceeds the launch target. This is tested in "stays within the launch distribution limits per rarity and slot". No Celestial shotgun exists, because the launch target allows only 2 Celestial primaries, already used by Aurora Rifle and Seraph Long Rifle.

### Collections (`src/shared/Config/Collections.luau`, cosmetic only)

| Collection | Finish (RGB) | Accent (RGB) |
|---|---|---|
| Classic | 70, 74, 72 | 96, 110, 62 |
| Tactical | 88, 92, 70 | 150, 140, 100 |
| Inferno | 120, 40, 26 | 255, 140, 40 |
| Arctic | 210, 222, 230 | 120, 190, 235 |
| Cyberpunk | 30, 26, 48 | 255, 60, 200 |
| Shadow | 22, 22, 26 | 110, 90, 150 |
| Galaxy | 36, 30, 80 | 150, 120, 255 |
| Celestial | 235, 225, 190 | 120, 235, 235 |

`WeaponModels.Build` colours each part by role: `Finish` uses the collection finish, `Accent` the collection accent, and `Steel` a fixed steel. Model profiles available: Rifle, SMG, Shotgun, Sniper, Pistol, Revolver, Knife. Every catalog entry's collection and model profile must exist, which is tested. Elemental and seasonal collections are not configured yet.

## 5. Catalog entry schema

| Field | Type | Rule |
|---|---|---|
| `Id` | string | Unique; equals the table key; lowercase `collection_type_name` |
| `DisplayName` | string | Original name; no third-party branding |
| `Archetype` | string | Key in `Archetypes`; determines the slot and every combat stat |
| `Rarity` | RarityId | Key in `Config.Rarity.Tiers`; cosmetic only |
| `Collection` | string | One of the collections below |
| `ModelProfile` | string | Visual model key (`Shared/Weapons/WeaponModels.Profiles` today; authored models later) |
| `AnimationProfile` | string | `TwoHanded`, `OneHanded` or `Knife` (more later) |
| `AudioProfile` | string | Key into the future audio set |
| `Starter` | boolean | Granted to every new profile |

Forbidden fields: `Damage`, `Firearm`, `Knife`, `Stats`, `RoundsPerMinute`, `HeadshotMultiplier`. Validation rejects them.

## 6. Rarity tiers (`src/shared/Config/Rarity.luau`)

| Rank | Tier | Symbol | Colour (RGB) |
|---:|---|---|---|
| 1 | Common | ● | 170, 174, 168 |
| 2 | Uncommon | ◆ | 110, 190, 90 |
| 3 | Rare | ▲ | 70, 140, 230 |
| 4 | Epic | ★ | 160, 90, 220 |
| 5 | Legendary | ✦ | 235, 165, 40 |
| 6 | Mythical | ✸ | 225, 70, 90 |
| 7 | Celestial | ❂ | 120, 235, 235 |

Every tier has a unique symbol, so rarity is never shown by colour alone (tested).

## 7. Launch target: 150 collectibles (planned, Phase 9)

| Rarity | Primary | Secondary | Knives | Total |
|---|---:|---:|---:|---:|
| Common | 15 | 10 | 10 | 35 |
| Uncommon | 12 | 8 | 10 | 30 |
| Rare | 10 | 7 | 8 | 25 |
| Epic | 10 | 6 | 9 | 25 |
| Legendary | 7 | 5 | 6 | 18 |
| Mythical | 4 | 3 | 5 | 12 |
| Celestial | 2 | 1 | 2 | 5 |
| **Total** | **60** | **40** | **50** | **150** |

**Collections (all original designs):** Classic, Tactical, Inferno, Arctic, Cyberpunk, Shadow, Galaxy and Celestial are configured. Elemental and Seasonal (Halloween, Winter, Anniversary, event collections) are planned. Do not copy protected models, artwork, branding or sounds from other games.

## 8. Adding a weapon

1. Pick an existing archetype. A new archetype is a balance change: add it to `Archetypes.luau` with every field, and get design sign-off.
2. Add a catalog entry following §5. Do not add combat fields.
3. Add or point to a `ModelProfile`. For authored meshes, record the upload in ASSET_MANIFEST.md with source and licence. Never reference an asset ID that has not actually been uploaded.
4. Assign `AnimationProfile` and `AudioProfile`.
5. Run `lune run tests/run`. `WeaponCatalog.spec` validates structure, starter-loadout consistency and rarity independence.
6. Crate pools pick the weapon up automatically from its slot, archetype, collection and rarity (`CrateOdds.Build`). Re-run `lune run tests/run`: "every crate passes validation" re-checks every crate's odds, pool coverage and expected compensation.
