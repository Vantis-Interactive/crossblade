# Deployment

**Status:** nothing has been published. No Roblox experience, place, DataStore, developer product, game pass or PlaceId exists or is configured for Crossblade. Everything below describes the procedure. The only steps executed so far are the local build and verification in §2.

## 1. Toolchain

Pinned versions (`rokit.toml`):

| Tool | Version | Purpose |
|---|---|---|
| Rojo | 7.7.1 | Sync and build `default.project.json` into Roblox |
| Lune | 0.11.1 | Test runner and place verifier |
| StyLua | 2.6.0 | Formatting |
| Selene | 0.31.0 | Linting |

### Option A: Rokit

```bash
rokit install
```

### Option B: Cargo (use when GitHub release downloads are blocked)

All four tools are on crates.io. This is how the current build was verified.

```bash
cargo install lune --version 0.11.1 --locked
```

```bash
cargo install stylua --version 2.6.0 --locked --features luau
```

```bash
cargo install selene --version 0.31.0 --locked --no-default-features --features roblox
```

```bash
cargo install rojo --version 7.7.1 --locked
```

**Selene standard library:** the repository uses `roblox_min.yml` (D-006). On a machine with direct internet access, run `selene generate-roblox-std` and set `std = "roblox"` in `selene.toml` for member-level checks.

## 2. Local workflow

| Task | Command |
|---|---|
| Full verification (format, lint, tests, build, place check) | `./scripts/verify.sh` |
| Tests only | `lune run tests/run` (optional filter: `lune run tests/run ProfileStore`) |
| Build a place file | `rojo build -o build/crossblade.rbxl` |
| Live sync into Studio | `rojo serve`, then connect with the Rojo Studio plugin |
| Format | `stylua src tests scripts` |

`scripts/verify.sh` runs, in order: `stylua --check`, `selene src`, `selene` in `tests/`, `lune run tests/run`, `rojo build`, and `lune run scripts/verify-place build/crossblade.rbxl`. Its last line is `ALL CHECKS PASSED` only if every step succeeded.

## 3. Studio setup checklist

1. Open `build/crossblade.rbxl`, or a published place with `rojo serve` connected.
2. **Game Settings → Avatar:** set the avatar type to **R15**. Procedural weapon poses are R15-only (`AnimationController`). Combat hitboxes are standardized and do not depend on the rig.
3. **Game Settings → Security:** enable **Studio Access to API Services**, or accept Studio ephemeral mode (D-009): players are warned that nothing is saved.
4. **Test → Players:** start a local server with 2 or more players to exercise combat (TEST_PLAN.md §4).
5. Before any non-Studio server runs: publish the place, then add its PlaceId to `Config.Data.Environments` (`src/shared/Config/Data.luau`) with `"Staging"` or `"Production"`. **Unlisted places use the Development store.**
6. Optional authored map: put a Model in `ServerStorage.Maps` with the tags described in MAP_DESIGN.md. It replaces the generated greybox (DEV-MAP-001).

## 4. Environment separation

| Environment | Roblox target | Data store | Who may deploy |
|---|---|---|---|
| Development | Studio and any unmapped place | `Crossblade_PlayerData_Development` | Any developer |
| Staging | A separate private experience or place (to be created) | `Crossblade_PlayerData_Staging` | Engineering lead |
| Production | The public experience (to be created) | `Crossblade_PlayerData_Production` | **Owner authorization required** |

Separate experiences for Staging and Production are recommended over separate places in one experience. DataStores are scoped per experience, which adds a second layer of isolation on top of the store-name suffix.

## 5. Release procedure (planned)

1. Confirm `./scripts/verify.sh` passes on the release commit and CI is green.
2. Update `CHANGELOG.md` and `DEVELOPMENT_STATUS.md`. Bump `Schema.CurrentVersion` only together with a migration (DATA_SCHEMA.md §5).
3. Publish to **Staging**. Run the TEST_PLAN.md Studio and multiplayer checklist on real devices: desktop, mobile and console.
4. Load-test data paths in Staging (autosave budget, shutdown save).
5. **Owner sign-off.**
6. Publish to **Production** with Roblox's update options. Prefer a gradual migration so that old servers drain. Older servers refuse newer schema data (`FutureVersion`), which is the intended protection.
7. Monitor (OPERATIONS.md §2) for at least one hour.

## 6. Rollback plan

| Situation | Action |
|---|---|
| Code defect, no schema change | Restore the previous place version from version history, or re-publish the previous release tag, and shut down servers. |
| Code defect after a schema bump | **Do not roll back below the new schema version.** Older servers would kick every migrated player with `FutureVersion`. Roll forward with a fix that keeps the new version. |
| Feature misbehaving | Disable it with its `FeatureFlags` entry. In Phase 2 this requires a re-publish; remote flags come in Phase 12 (OPERATIONS.md §3.4). |
| Data corruption | Stop writes by shutting down servers, then restore affected keys from DataStore version history (DATA_SCHEMA.md §9). |

## 7. Actions that require explicit owner authorization

The directive (spec §2.17, §30 Phase 11) forbids these without the owner's explicit approval:

- Publishing the experience publicly, or changing its visibility.
- Creating, pricing or enabling developer products, game passes or any live purchase.
- Any write to Production data, including manual repairs, migrations run against production, and bulk operations.
- Mapping a PlaceId to `"Production"` in `Config.Data.Environments`.
- Content maturity questionnaire submission and store listing changes.
