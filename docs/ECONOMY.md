# Economy

**Status: implemented in Phase 3 (ECO-01 to ECO-06; ECO-07 partial).** The Studio and multiplayer verification in TEST_PLAN.md is still pending. The rules are pure modules covered by `tests/specs/Economy.spec.luau`. The services are Roblox glue and have not yet run in Studio.

| Concern | Implementation |
|---|---|
| Configuration | `src/shared/Config/Economy.luau`, `Progression.luau`, `Crates.luau` |
| Wallet rules | `src/shared/Economy/Wallet.luau` |
| Crate distributions | `src/shared/Economy/CrateOdds.luau` (shared by client disclosure and server selection) |
| Level arithmetic | `src/shared/Economy/Leveling.luau` |
| Crate opening (atomic) | `src/server/Domain/CrateOpening.luau` |
| Reward rules and anti-farming | `src/server/Domain/RewardPolicy.luau` |
| Paid-random eligibility | `src/server/Domain/PaidRandomPolicy.luau`, `Services/PolicyComplianceService.luau` |
| Services | `EconomyService`, `CrateService`, `InventoryService`, `ProgressionService` |

In the tables below, **SPEC** values come from the master directive. **PROPOSED** values were not specified and are recorded in DECISIONS.md.

## 1. Currency accounting

| Balance | Source | Notes |
|---|---|---|
| `Currency.Earned` | Match rewards, level rewards, duplicate compensation, the tutorial reward | Credited only through `Wallet.CreditEarned`, which rejects negative or fractional amounts |
| `Currency.Purchased` | Robux developer products (MONETIZATION.md) | **No product exists yet.** The balance is always 0 until Phase 7 |

- The HUD shows one total (`Wallet.Total`). The Collection window shows both balances.
- **Spend order (D-026):** `Wallet.Debit` always spends earned coins first. Purchased coins are only used when the caller passes `allowPurchased = true`. For crates that flag comes from PolicyService (§5.4).
- **Atomicity:** every mutation runs through `PlayerDataService:ApplyTransaction(player, id, mutate)`, which wraps `Data/Transactions.Apply`. It mutates a deep copy, commits only if the whole function succeeds, records the id so a replay is a no-op, and returns `(outcome, err)`.
- **Durability:** economy mutations call `PlayerDataService:RequestSave`, a debounced save 6 s later (`Config.Data.PrioritySaveDelaySeconds`). The regular autosave still runs.

### Transaction ids

| Prefix | Format | Created by |
|---|---|---|
| `elim:` | `elim:{serverTag}:{matchId}:{deathSequence}:{userId}` | `EconomyService` on `MatchService.EliminationScored` |
| `match:` | `match:{serverTag}:{matchId}:{userId}` | `EconomyService` on `MatchService.MatchFinished` |
| `crate:` | `crate:{RequestId}` (client GUID) | `CrateService` (D-027) |
| `tutorial-reward` | fixed id, once per account | `EconomyService.GrantTutorialReward` (§8) |

`serverTag` is `game.JobId`, or `studio{os.time()}` in Studio. Re-processing the same event therefore cannot pay twice, and ids from different servers never collide.

## 2. Match rewards (implemented)

Each elimination becomes one grant per beneficiary (`RewardPolicy.Evaluate`), applied as a single transaction by `EconomyService:Grant`. One transaction covers the hourly cap check, the coin credit, XP, level rewards and the `Stats.CoinsEarned` update.

| Action | Coins | Source | XP | Source |
|---|---:|---|---:|---|
| Gun elimination | 25 | SPEC | 100 | PROPOSED (D-021) |
| Knife elimination (melee or thrown) | 35 | SPEC | 100 | PROPOSED |
| Headshot elimination bonus | +10 | SPEC | +20 | PROPOSED |
| Assist | 10 | SPEC | 40 | PROPOSED |
| Streak bonus at 5, 10, 15, … | +50 | SPEC ("five-elimination streak") | 0 | PROPOSED |
| "Finished off" elimination (D-013) | 10 | PROPOSED (D-025) | 40 | PROPOSED (D-025) |
| Match completed (every ranked entry) | 0 | none | 150 | PROPOSED |
| Free-for-All first place (≥1 elimination) | 0 | PROPOSED (D-029) | +250 | PROPOSED |
| Duel victory (every member of the winning team) | 100 | SPEC (`Rewards.DuelVictory`) | +250 | PROPOSED (D-039) |
| Team Deathmatch victory (every member of the winning team) | 150 | SPEC (`Rewards.TeamDeathmatchVictory`) | +250 | PROPOSED (D-039) |
| Tutorial completion reward (once per account) | 500 + 1 Basic Crate token | SPEC | 0 | none |

Self-eliminations and environmental deaths with no attacker pay nothing. A streak bonus is paid when the killer's streak, after the kill, is a multiple of `Rewards.Streak.Every = 5`.

**Match end (`MatchService.MatchFinished` → `EconomyService.onMatchFinished`).** One grant per ranked participant, transaction `match:…`, subject to the same eligibility and hourly caps. Every participant gets match-completion XP. In team modes, members of the winning team (`WinnerTeam`) also get the mode's `VictoryReward` coins (`Config.GameModes.<mode>.VictoryReward` names the key in `Config.Economy.Rewards`) and +250 XP; a draw pays only match-completion XP. Free-for-All keeps its first-place rule. The coin values are in the table above. Team kills cannot happen (`MatchService.CanDamage`), and eliminations scored in non-progression modes (the hub's Lobby mode, private matches) pay nothing.

Planned sources not built yet: challenges, achievements, login rewards and events (Phase 7).

## 3. Levels (implemented; PROPOSED values, D-022)

`Config.Progression`; arithmetic in `Shared/Economy/Leveling.luau`.

- XP needed to go from level L to L+1 is `1000 + 100 × (L − 1)`. That makes 1,000 XP for level 2 and 1,100 for level 3. Reaching the maximum level of 100, which is also the prestige threshold, takes 584,100 XP in total.
- Each level reached pays 100 coins, with a 400-coin bonus at every 10th level (500 total at levels 10, 20, …).
- Level rewards are paid only for levels above `Progression.HighestRewardedLevel`, so they are paid exactly once. That stays true after a future prestige resets `Level`.
- Level rewards are credited inside the same transaction as the XP (`ProgressionService:ApplyXP`) and are **not** subject to the hourly cap.

## 4. Crates (implemented)

Configuration lives in `src/shared/Config/Crates.luau`.

**Pool:** every non-starter catalog weapon that matches the crate's filter and whose rarity has odds above zero. **Per-item probability:** the rarity's odds divided by the number of pool items of that rarity (`CrateOdds.Build`). Items are ordered by rarity rank, then id. The same ordered distribution drives the disclosure list and the server's cumulative selection (`CrateOdds.Select` with one `Random:NextNumber()` roll in [0, 1)).

| Crate | Category | Price (SPEC) | Filter | Odds (%) | Odds source | Pool items |
|---|---|---:|---|---|---|---:|
| Basic | Rarity | 250 | all | C40 U25 R18 E10 L5 M1.8 X0.2 | SPEC standard | 37 |
| Premium | Rarity | 750 | all | U40 R30 E18 L8 M3.5 X0.5 | PROPOSED (D-023) | 31 |
| Legendary | Rarity | 2,500 | all | L85 M13 X2 | PROPOSED | 14 |
| Mythical | Rarity | 5,000 | all | M92 X8 | PROPOSED | 9 |
| Knife | Weapon | 500 | Slot = Knife | standard | SPEC | 7 |
| Pistol | Weapon | 500 | Slot = Secondary | standard | SPEC | 7 |
| Rifle | Weapon | 750 | AssaultRifle | standard | SPEC | 7 |
| Shotgun | Weapon | 750 | Shotgun | C40 U25 R18 E10 L5 M2 | PROPOSED (no Celestial shotgun exists) | 6 |
| Sniper | Weapon | 1,000 | SniperRifle | standard | SPEC | 7 |
| Inferno | Themed | 1,500 | Collection = Inferno | R60 E28 L10 M2 | PROPOSED | 5 |
| Arctic | Themed | 1,500 | Collection = Arctic | R60 E28 L10 M2 | PROPOSED | 6 |
| Cyberpunk | Themed | 2,000 | Collection = Cyberpunk | R60 E28 L10 M2 | PROPOSED | 5 |
| Galaxy | Themed | 2,500 | Collection = Galaxy | R60 E28 L10 M2 | PROPOSED | 5 |

C = Common, U = Uncommon, R = Rare, E = Epic, L = Legendary, M = Mythical, X = Celestial. Seasonal crates (Halloween, Winter, Anniversary) are not configured; they arrive with seasonal content in Phase 12.

### Duplicate compensation (SPEC, `Config.Economy.DuplicateCompensation`)

| Rarity | Coins |
|---|---:|
| Common | 50 |
| Uncommon | 100 |
| Rare | 250 |
| Epic | 500 |
| Legendary | 1,000 |
| Mythical | 2,500 |
| Celestial | 5,000 |

A duplicate is converted automatically into exactly this many earned coins. This is tested for every rarity in "duplicate crate rewards provide exactly the configured compensation".

### Opening flow (`CrateService`, `CrateOpening.Open`)

1. The crate must be active, meaning it passed boot validation (§6). The RequestId must be at least 8 characters of `[A-Za-z0-9-]`, and the profile must be loaded.
2. `allowPurchased = PolicyComplianceService:PurchasedCurrencyAllowedForCrates(player)`.
3. The server rolls `Random:NextNumber()`. Inside one transaction `crate:{RequestId}` it then:
   - debits the price (fails with `InsufficientFunds`, or `InsufficientEarnedFunds` when only purchased coins would cover it),
   - selects the item,
   - grants the weapon **or** credits the duplicate compensation,
   - increments `Stats.CratesOpened` and `Stats.CoinsEarned`,
   - appends to `CrateHistory`, which keeps the latest 50 entries.
4. If the id was already applied, the stored `CrateHistory` result is returned with `Replayed = true`. Nothing is charged and nothing is granted again.
5. On success it records the `CrateOpened` audit event, calls `RequestSave`, and pushes `EconomyState`.

The client generates one GUID per purchase and reuses it for its single retry (`InventoryController.OpenCrate`). A lost response therefore cannot cause a second charge.

**Free crate tokens.** `UseToken = true` spends one `CrateTokens[crateId]` instead of the price, inside the same transaction (`NoToken` if there is none). Tokens are created only by the tutorial reward (§8). No currency moves, so a token open is not a paid randomized item and the policy check does not apply (D-037). Everything else (selection, duplicate compensation, history, statistics, idempotency) is identical. The result carries `UsedToken = true`.

## 5. Anti-farming and eligibility (implemented; limits PROPOSED, D-024)

1. **Repeated victims.** The same killer → victim pair is rewarded at most `RepeatVictim.MaxRewarded = 3` times per `WindowSeconds = 300`. Past that, the elimination pays **nobody**, including assisters (`RewardPolicy.Evaluate`). Pair history is per server and in memory.
2. **Hourly caps.** Match rewards are capped at 2,000 coins and 20,000 XP per rolling hour (`RewardPolicy.ApplyHourlyCap`). The counters (`Economy.HourStart`, `HourCoins`, `HourXP`) are persisted in the profile, so changing servers does not reset them. Each truncated grant records a `RewardCapped` audit event and sets `Capped = true` in the `Reward` message.
3. **Population.** No rewards are paid with fewer than 2 players who have loaded profiles (`MinPlayersForRewards`).
4. **Paid random items (D-026).** Crates are randomized items. Purchased coins can be spent on them only when PolicyService returned `ArePaidRandomItemsRestricted == false`. A failed lookup, missing field or unexpected value is treated as not allowed (fail closed). Earned coins, which come from gameplay, always work, so every player has a free path to crates.
5. **Private matches and private servers.** No rewards in modes with `AwardsProgression = false` (`GameModes.Private`). No rewards in player-owned private servers (`game.PrivateServerOwnerId ~= 0`, `DisableInOwnedPrivateServers = true`).
6. **No trading, gifting, marketplace or external sale** exists. Items cannot leave an account.
7. **Reconciliation** (SEC-05) is planned. Today's evidence is the `Economy` audit events (`CrateOpened`, `RewardCapped`, `PolicyLookupFailed`, `CrateDisabled`) and per-profile `CrateHistory`.

## 6. Sustainability analysis

**The requirement:** crates must not allow sustainable unlimited currency generation. The worst case is a player who owns every item in a pool, so every roll is a duplicate.

`CrateService` validates every crate at boot with `CrateOdds.Validate`:
- odds sum to 100,
- every rarity with odds has at least one item,
- item probabilities sum to 1,
- price is a positive integer,
- compensation exists for every rarity,
- `ExpectedCompensation(all owned) < Price × (1 − MinimumSinkMargin)`.

A failing crate is disabled, logged, and recorded as a `CrateDisabled` audit event, and it is never offered.

Expected compensation per roll for a player who owns everything, computed from the real distributions:

| Crate | Price | EV compensation | Sink (1 − EV/price) |
|---|---:|---:|---:|
| Basic | 250 | 245.00 | 2.0% |
| Premium | 750 | 397.50 | 47.0% |
| Legendary | 2,500 | 1,275.00 | 49.0% |
| Mythical | 5,000 | 2,700.00 | 46.0% |
| Knife | 500 | 245.00 | 51.0% |
| Pistol | 500 | 245.00 | 51.0% |
| Rifle | 750 | 245.00 | 67.3% |
| Shotgun | 750 | 240.00 | 68.0% |
| Sniper | 1,000 | 245.00 | 75.5% |
| Inferno | 1,500 | 440.00 | 70.7% |
| Arctic | 1,500 | 440.00 | 70.7% |
| Cyberpunk | 2,000 | 440.00 | 78.0% |
| Galaxy | 2,500 | 440.00 | 82.4% |

The Basic figure works out as `0.4×50 + 0.25×100 + 0.18×250 + 0.1×500 + 0.05×1000 + 0.018×2500 + 0.002×5000 = 245`. Within a rarity, per-item splitting does not change the EV.

**Open owner decision.** Every crate is net-negative, so none can generate coins and all pass at `Config.Economy.MinimumSinkMargin = 0`, which is the current setting. The Basic crate as specified still sinks only 2%. It works as an almost free re-roll for completed collections, with high variance: a Celestial duplicate pays 20 times the price. The recommended fix is to set `MinimumSinkMargin` to 0.10 or more and choose one of the following, each of which changes spec values:
- (a) Basic price of at least 273,
- (b) lower duplicate compensation for Basic-crate rolls,
- (c) Basic odds shifted toward lower tiers.

With a 0.10 margin today, Basic would fail validation and be disabled automatically, while every other crate passes.

Partial ownership only lowers the EV, because new items pay no compensation, so the all-owned case is the upper bound.

## 7. Pre-activation checklist for any new crate

- [x] Pool and probabilities generated from one configuration (`CrateOdds.Build`); disclosure uses the same function (tested: stratified and chi-squared checks).
- [x] Price, compensation and EV checked automatically at boot (`CrateOdds.Validate`).
- [x] PolicyService gating, including the fail-closed path (tested at rule level).
- [x] Reveal displays only the server-committed result; reduced-motion path implemented (Studio verification pending).
- [ ] Standalone economy simulation tool covering earning rates and spend over time (ECO-07; not built).
- [ ] Owner decision on the sink margin (§6).

## 8. Tutorial reward (implemented, Phase 4)

`Config.Tutorial.Reward` (SPEC): 500 coins and one Basic Crate. `TutorialService` calls `EconomyService.GrantTutorialReward` when the tutorial's Coins step completes (D-036). That function runs one transaction, `tutorial-reward`, which fails with `AlreadyClaimed` if `Tutorial.RewardClaimed` is already true, and otherwise sets `RewardClaimed`, credits 500 earned coins (also counted in `Stats.CoinsEarned`), and adds one token to `CrateTokens.basic`. It is audited as `TutorialRewardGranted` and announced with a `Reward` message (reason `Tutorial`). The fixed transaction id and the flag, written in the same transaction, together make the reward claimable exactly once per account, including across replays and servers. The hourly match-reward cap does not apply to it.

Economic impact: a one-time 500 coins plus one Basic Crate (expected value 245 coins if every item were already owned) per account.
