# Monetization

**Status: planned (Phase 7: MON-01 to MON-05).**
- **No developer products, game passes or subscriptions exist.**
- **No product IDs are configured anywhere in the repository.**
- Live purchases must not be enabled without owner authorization (directive §2.17).

The data schema already reserves `Purchases.Receipts`, `Entitlements` and `Currency.Purchased`.

## 1. Principles
- Free to play. All combat content is earnable through gameplay.
- **No pay-to-win:** no paid damage, health, fire rate, accuracy, movement or other competitive advantage. Combat stats belong to archetypes, which purchases cannot change (D-008).
- No deceptive scarcity, misleading prices, fake discounts or manipulative purchase flows.
- **Prohibited:** player-to-player trading, gifting, player marketplaces, auctions, external item sales and real-money cash-out.

## 2. Provisional product catalog (spec §23)

| Product | Robux | Type (planned) |
|---|---:|---|
| 500 coins | 49 | Developer product |
| 1,500 coins | 129 | Developer product |
| 5,000 coins | 399 | Developer product |
| 15,000 coins | 999 | Developer product |
| 50,000 coins | 2,999 | Developer product |
| Permanent VIP | 499 | Game pass |
| Seasonal battle pass | 399 | Developer product (per season entitlement) |
| Premium battle pass bundle | 799 | Developer product |
| Additional loadout presets | 99 | Game pass or product |
| Direct weapon cosmetics | 99–499 | Developer products |
| Elimination effects | 149–399 | Developer products |
| Private server | 99 / month | Roblox private server subscription |

Actual prices and IDs must be created in the Roblox dashboard, recorded in configuration, and verified before launch. Do not invent IDs.

## 3. VIP and battle pass contents

**VIP:** VIP name tag, VIP lobby lounge, exclusive cosmetics, cosmetic rewards and additional loadout presets. All of it is cosmetic or convenience.

**Battle pass:**
- 60-day seasons with 50 tiers.
- A free track for everyone and a premium track.
- Tiers unlock from seasonal challenges and XP. Rewards are cosmetics only.
- Premium entitlement is verified on the server (`Entitlements`), never by client report.

## 4. Purchase fulfilment design (MON-01)

1. `MarketplaceService.ProcessReceipt` is the only entry point for repeatable purchases. A client report of "purchase succeeded" grants nothing.
2. The receipt's `PurchaseId` is the transaction id. Fulfilment runs `PlayerDataService:ApplyTransaction(player, "receipt:" .. PurchaseId, grant)`. This is all-or-nothing and idempotent, and both properties are implemented and tested in `Data/Transactions.luau`.
3. `PurchaseGranted` is returned **only after** the profile containing the processed id and the grant has been **saved** successfully. If the save fails, or the player is not loaded, the result is `NotProcessedYet` and Roblox redelivers the receipt.
4. A duplicate delivery of an already-processed `PurchaseId` returns `PurchaseGranted` without granting again (the "replayed receipts cannot duplicate purchases" test target).
5. Receipt records go to `Purchases.Receipts` with a bounded history, plus an audit record (Economy category) with product, price and time.
6. Game passes are verified with `UserOwnsGamePassAsync` on join, and on `PromptGamePassPurchaseFinished` only as a hint followed by a server-side re-check.

## 5. Paid randomized items and PolicyService (MON-04)

- Call `PolicyService:GetPolicyInfoForPlayerAsync` and check `ArePaidRandomItemsRestricted` before any crate opening that could spend purchased currency, and before offering coin products for crate use.
- **Fail closed:** if the lookup errors or times out, treat the player as restricted.
- **Restricted players:**
  - can open crates only with earned coins (ECONOMY.md §5.4),
  - are not shown flows that spend purchased coins on crates,
  - still have unpaid gameplay crate paths and deterministic direct-purchase cosmetic alternatives.
- Before any crate purchase, show every possible final reward and its individual probability, generated from the same configuration the server uses to roll.

## 6. Pre-launch compliance checklist

- [ ] All products exist in the Roblox dashboard and their IDs are recorded in configuration (not code).
- [ ] Prices match the approved catalog; no misleading "was/now" pricing.
- [ ] ProcessReceipt replay test passes against a staging place.
- [ ] Interrupted-session test passes: purchase, then the player leaves before saving, then redelivery is granted exactly once.
- [ ] PolicyService gating is tested for a restricted account and for a simulated lookup failure.
- [ ] Odds disclosure is shown before every paid random purchase and matches the server configuration.
- [ ] No paid item changes combat stats (archetype audit).
- [ ] Content maturity questionnaire and monetization disclosures are completed in the Roblox experience settings.
- [ ] Owner authorization to enable live purchases is recorded in DECISIONS.md.
