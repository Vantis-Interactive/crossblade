--!strict
--[[
	Unified wallet with separate accounting (spec §13): Earned and Purchased balances are stored and
	audited separately but shown as one coin total.

	Spending rule for paid randomized items (crates, spec §14): purchased coins may only be spent when
	the player is confirmed eligible (PolicyService). Earned coins are always spent first.
]]

export type Currency = { Earned: number, Purchased: number }
export type Debit = { FromEarned: number, FromPurchased: number }

local Wallet = {}

function Wallet.Total(currency: Currency): number
	return currency.Earned + currency.Purchased
end

function Wallet.Spendable(currency: Currency, allowPurchased: boolean): number
	return currency.Earned + (if allowPurchased then currency.Purchased else 0)
end

-- Debits `price`. Errors (so an enclosing transaction aborts) when funds are insufficient.
function Wallet.Debit(currency: Currency, price: number, allowPurchased: boolean): Debit
	assert(price >= 0 and price % 1 == 0, "price must be a non-negative integer")
	if Wallet.Spendable(currency, allowPurchased) < price then
		if not allowPurchased and Wallet.Total(currency) >= price then
			error("InsufficientEarnedFunds", 0)
		end
		error("InsufficientFunds", 0)
	end
	local fromEarned = math.min(currency.Earned, price)
	local fromPurchased = price - fromEarned
	currency.Earned -= fromEarned
	currency.Purchased -= fromPurchased
	return { FromEarned = fromEarned, FromPurchased = fromPurchased }
end

function Wallet.CreditEarned(currency: Currency, amount: number)
	assert(amount >= 0 and amount % 1 == 0, "credit must be a non-negative integer")
	currency.Earned += amount
end

return Wallet
