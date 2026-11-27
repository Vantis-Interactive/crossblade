# Crossblade

Crossblade (working title, see docs/DECISIONS.md D-001) is a fast-paced, skill-based multiplayer PvP arena game for Roblox with guns and knives. It is free-to-play, has no pay-to-win mechanics, and uses non-graphic combat.

**Status:** Phases 0–5 are implemented: the foundation, the combat slice, economy and collection, the hub with its tutorial and casual modes, and multiplayer infrastructure. That last phase adds matchmaking, parties, reserved servers, reconnection, private matches and remapping. Their rules pass the automated suite. It has **not yet been playtested in Roblox Studio**. See [docs/DEVELOPMENT_STATUS.md](docs/DEVELOPMENT_STATUS.md).

## Quick start

Install the pinned toolchain with [Rokit](https://github.com/rojo-rbx/rokit):

```bash
rokit install
```

Or build the same versions from crates.io:

```bash
cargo install rojo --version 7.7.1 --locked && cargo install lune --version 0.11.1 --locked && cargo install stylua --version 2.6.0 --locked --features luau && cargo install selene --version 0.31.0 --locked --no-default-features --features roblox
```

Run every check (format, lint, tests, build, place verification):

```bash
./scripts/verify.sh
```

Live-sync into Studio (then connect with the Rojo Studio plugin):

```bash
rojo serve
```

Or build a place file (the default project is a Free-for-All arena):

```bash
mkdir -p build && rojo build -o build/crossblade.rbxl
```

Each place has its own project (`hub`, `ffa`, `tdm`, `duel1v1`, `duel2v2`):

```bash
rojo build places/hub.project.json -o build/hub.rbxl
```

In Studio, set Game Settings > Avatar to **R15**, enable **Studio Access to API Services** for persistence, then use **Test > Start Server** with 2 or more players. Without API access, the game runs in an explicit non-persistent Studio mode (D-009).

## Controls (defaults)

| Action | Keyboard / mouse | Gamepad | Touch |
|---|---|---|---|
| Fire / knife slash | Left mouse | R2 | FIRE |
| Aim / knife stab | Right mouse | L2 | AIM |
| Reload | R | X | RLD |
| Next weapon | Q / mouse wheel | Y | SWAP |
| Primary / secondary / knife | 1 / 2 / 3 | D-pad right (knife) | slot buttons |
| Throw knife | G | B | THROW |
| Inspect | F | D-pad down | none |
| Sprint | Left Shift | L3 | none |
| Toggle camera | V | R3 | CAM |
| Scoreboard | Tab (hold) | D-pad left | SCORE |
| Settings | P | Select | SETTINGS |
| Collection (armory, crates) | I | D-pad up | COLLECTION |
| Play / leave match | none | none | PLAY / HUB |
| Interact (portal, station) | E | X (prompt) | tap prompt |

## Documentation

| Document | Contents |
|---|---|
| [GAME_DESIGN](docs/GAME_DESIGN.md) | Pillars, loop, modes, mechanics |
| [ARCHITECTURE](docs/ARCHITECTURE.md) | Code layout, services, data flow |
| [DATA_SCHEMA](docs/DATA_SCHEMA.md) | Player data v1, session locking, migrations |
| [NETWORK_CONTRACTS](docs/NETWORK_CONTRACTS.md) | Every remote, payload and rate limit |
| [WEAPON_CATALOG](docs/WEAPON_CATALOG.md) | Archetypes, stats, catalog rules |
| [ECONOMY](docs/ECONOMY.md) | Currency, rewards, crates, progression |
| [MAP_DESIGN](docs/MAP_DESIGN.md) | Map tag contract, greybox arena |
| [UI_GUIDELINES](docs/UI_GUIDELINES.md) | Theme, HUD, accessibility, bindings |
| [SECURITY](docs/SECURITY.md) | Threat model and mitigations |
| [MONETIZATION](docs/MONETIZATION.md) | Products and compliance (planned) |
| [TEST_PLAN](docs/TEST_PLAN.md) | Strategy, results, manual checklist |
| [TRACEABILITY](docs/TRACEABILITY.md) | Requirement → code → test matrix |
| [DEPLOYMENT](docs/DEPLOYMENT.md) | Toolchain, environments, release, rollback |
| [OPERATIONS](docs/OPERATIONS.md) | Runbooks and live-ops |
| [DECISIONS](docs/DECISIONS.md) | Architecture decision log |
| [BACKLOG](docs/BACKLOG.md) | Phase-ordered work items |
| [ASSET_MANIFEST](docs/ASSET_MANIFEST.md) | Assets, temporary placeholders, licensing |
| [DEVELOPMENT_STATUS](docs/DEVELOPMENT_STATUS.md) | Current state, blockers, next steps |
| [CHANGELOG](docs/CHANGELOG.md) | Release history |
