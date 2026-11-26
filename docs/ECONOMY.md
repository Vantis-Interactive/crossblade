# Economy

**Status: planned (Phase 3: ECO-01 to ECO-07).** Only the transaction foundation is implemented:
- `src/server/Data/Transactions.luau`, tested in `tests/specs/Transactions.spec.luau`
- the currency fields in data schema v1 (`Currency.Earned`, `Currency.Purchased`)

All values below are the specification's design values. They will move into `src/shared/Config` when EconomyService is built, and nothing in gameplay code will hardcode them.

## 1. Currency accounting

| Balance | Source | Notes |
|---|---|---|
| `Currency.Earned` | Gameplay rewards, duplicate compensation, challenges, login rewards | Never purchasable |
| `Currency.Purchased` | Robux developer products only (MONETIZATION.md) | Credited only through `ProcessReceipt` |

- Players see a single wallet (Earned + Purchased).
- The two balances are kept separate so purchases can be reconciled, refunds reversed, and paid-random-item rules applied (§5.4).
- **Spend order (planned):** earned coins first, then purchased.
- Every mutation runs through `Transactions.Apply(data, transactionId, ...)` (implemented):
  - It mutates a deep copy and commits only if the whole mutation succeeds, so a debit can never be applied without its grant (tested).
  - It records the transaction id, so replaying the same id is a no-op (tested).
  - The processed-id list is bounded (`Config.Data.Limits.ProcessedTransactions = 200`) and evicts the oldest ids.
  - Durability comes from the session lock: one server owns a profile, and processed ids are saved in the same record as the balances.

## 2. Gameplay rewards (spec §13; planned ECO-02)

| Action | Coins |
|---|---:|
| Gun elimination | 25 |
| Knife elimination (melee or thrown) | 35 |
| Headshot elimination bonus | +10 |
| Assist | 10 |
| Five-elimination streak | 50 |
| Duel victory | 100 |
| Team Deathmatch victory | 150 |

Other sources (planned): daily, weekly and seasonal challenges, achievements, login rewards, level-ups and events. All reward limits will be configurable.

**Open design question (ECO-06):** whether a `Finished` elimination (D-013) pays the full elimination reward.

## 3. Crates (spec §14; planned ECO-04)

| Category | Crate | Price (coins) |
|---|---|---:|
| Rarity | Basic | 250 |
| Rarity | Premium | 750 |
| Rarity | Legendary | 2,500 |
| Rarity | Mythical | 5,000 |
| Weapon type | Knife | 500 |
| Weapon type | Pistol | 500 |
| Weapon type | Rifle | 750 |
| Weapon type | Shotgun | 750 |
| Weapon type | Sniper | 1,000 |
| Themed | Inferno | 1,500 |
| Themed | Arctic | 1,500 |
| Themed | Cyberpunk | 2,000 |
| Themed | Galaxy | 2,500 |
| Seasonal | Halloween, Winter, Anniversary, event | Set per season |

### Standard rarity distribution

| Rarity | Probability |
|---|---:|
| Common | 40.0% |
| Uncommon | 25.0% |
| Rare | 18.0% |
| Epic | 10.0% |
| Legendary | 5.0% |
| Mythical | 1.8% |
| Celestial | 0.2% |
| **Total** | **100.0%** |

### Rules
- Each crate has its own **explicitly configured** reward pool with a probability per item. The disclosed probabilities must be exactly the ones the server's selection algorithm uses. They are generated from one config and never duplicated by hand.
- Rewards are selected on the server only. The opening animation reveals a result the server has already decided and committed; it never decides anything itself.
- A reduced-animation option is required. No near-miss animations and no deceptive odds.
- Before purchase, show every possible final reward and its individual numerical probability.
- A crate purchase is one transaction: debit, reward grant and any duplicate compensation commit together or not at all.

### Duplicate compensation (automatic, in coins)

| Rarity | Compensation |
|---|---:|
| Common | 50 |
| Uncommon | 100 |
| Rare | 250 |
| Epic | 500 |
| Legendary | 1,000 |
| Mythical | 2,500 |
| Celestial | 5,000 |

## 4. Sustainability analysis

**The requirement:** crates must not allow sustainable unlimited currency generation. The worst case is a player who **owns every item**, so every roll is a duplicate.

Expected compensation for one roll at the standard distribution:

| Rarity | p | Compensation | p × comp |
|---|---:|---:|---:|
| Common | 0.400 | 50 | 20.0 |
| Uncommon | 0.250 | 100 | 25.0 |
| Rare | 0.180 | 250 | 45.0 |
| Epic | 0.100 | 500 | 50.0 |
| Legendary | 0.050 | 1,000 | 50.0 |
| Mythical | 0.018 | 2,500 | 45.0 |
| Celestial | 0.002 | 5,000 | 10.0 |
| **EV** | | | **245.0** |

**Result:** a Basic crate (250 coins) returns 245 coins on average to a player who owns everything. The loop is **not net-positive**, losing 5 coins (2%) per crate, so it cannot generate unlimited currency. However:

1. **The margin is too thin.**
   - Variance is high: a Celestial duplicate returns 5,000 coins, 20 times the price. A lucky streak gives large short-term gains.
   - Basic crates become an almost free re-roll machine for completed collections.
   - The sink is only 2%, which does little to remove coins from the economy.
2. **Any crate whose pool is weighted toward higher rarities must be checked separately.** For example, a pool with more Legendary or Mythical weight at the same price could exceed 100% return.
3. **Partial ownership lowers the EV.** New items pay no compensation, so the all-owned case is the upper bound.

**Design constraint (ECO-04/ECO-07):** for every crate,

`EV_comp(all owned) <= price × (1 − sink margin)`

with a proposed sink margin of 10% or more. This is validated automatically at crate activation and by the economy simulation tool. Under that rule the Basic crate as specified (98% return) fails. The owner must choose one of these options before Phase 3 activation (it changes spec values, so it needs approval):
- (a) raise the Basic price to at least 273,
- (b) scale duplicate compensation for Basic-crate rolls,
- (c) shift Basic odds toward lower tiers.

Premium (750) at the standard distribution returns 245 (33%) and passes. Weapon-type crates at 500 or more pass at the standard distribution, but must be re-checked against their actual pools.

## 5. Anti-farming (planned ECO-06)

1. **Self-farming:** eliminations by the same attacker on the same victim pay a diminishing reward within a rolling window. Repeated alternating kills between the same two players (cooperative farming) are detected and pay nothing once over a configurable threshold.
2. **Private servers:** private matches award no coins, XP, rating or challenge progress (`GameModes.Private.AwardsProgression = false`, implemented and tested as configuration).
3. **Daily earning caps:** configurable soft caps on gameplay coins per day, with challenges and achievements outside the cap.
4. **Paid random items:** crates are randomized items, and coins can be bought with Robux. A player who is ineligible for paid random items under `PolicyService` (fail closed) can open crates **only with earned coins**. This is enforced by the separate earned/purchased balances (MONETIZATION.md §4).
5. **Reconciliation:** audit records per transaction id allow balances to be rebuilt and anomalies flagged (SEC-05).
6. **No trading, gifting, marketplace or external sale** exists. Items cannot leave an account.

## 6. Pre-activation checklist for any crate

- [ ] The reward pool is explicitly configured; probabilities sum to exactly 1.
- [ ] Disclosure UI is generated from the same configuration.
- [ ] Price and compensation values pass the §4 constraint (automated check).
- [ ] The economy simulation (ECO-07) has run with current balances and drop rates.
- [ ] PolicyService gating is verified for ineligible accounts, including the fail-closed path.
- [ ] Reduced-animation path is verified; the reveal displays only the server-committed result.
