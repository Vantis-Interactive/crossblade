--!strict
--[[
	Crate opening applied to a profile draft (spec §14). Intended to run inside Transactions.Apply,
	which makes the whole operation atomic: the debit, the reward grant OR the duplicate compensation,
	the statistics and the history record are committed together or not at all.

	The reward is selected from `Roll` (server-side randomness) through Shared/Economy/CrateOdds,
	the same distribution disclosed to the player. The client never influences the result.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CrateOdds = require(ReplicatedStorage.Shared.Economy.CrateOdds)
local Wallet = require(ReplicatedStorage.Shared.Economy.Wallet)

export type Args = {
	CrateId: string,
	Price: number,
	Distribution: CrateOdds.Distribution,
	Roll: number,
	RequestId: string,
	Now: number,
	AllowPurchased: boolean,
	Compensation: { [string]: number },
	HistoryLimit: number,
	UseToken: boolean?,
}

export type Result = {
	RequestId: string,
	CrateId: string,
	WeaponId: string,
	Rarity: string,
	Duplicate: boolean,
	Compensation: number,
	FromEarned: number,
	FromPurchased: number,
	UsedToken: boolean,
	Time: number,
}

local CrateOpening = {}

function CrateOpening.Open(draft: { [string]: any }, args: Args): Result
	local debit = { FromEarned = 0, FromPurchased = 0 }
	if args.UseToken then
		-- A free token is not a paid randomized purchase: no currency moves.
		local tokens = draft.CrateTokens[args.CrateId] or 0
		if tokens <= 0 then
			error("NoToken", 0)
		end
		draft.CrateTokens[args.CrateId] = tokens - 1
	else
		debit = Wallet.Debit(draft.Currency, args.Price, args.AllowPurchased)
	end
	local entry = CrateOdds.Select(args.Distribution, args.Roll)
	local owned = draft.Inventory.Weapons[entry.WeaponId] ~= nil
	local compensation = 0
	if owned then
		compensation = args.Compensation[entry.Rarity]
		assert(type(compensation) == "number", `no compensation for {entry.Rarity}`)
		Wallet.CreditEarned(draft.Currency, compensation)
		draft.Stats.CoinsEarned += compensation
	else
		draft.Inventory.Weapons[entry.WeaponId] = { AcquiredAt = args.Now, Source = `Crate:{args.CrateId}` }
	end
	draft.Stats.CratesOpened += 1
	local result: Result = {
		RequestId = args.RequestId,
		CrateId = args.CrateId,
		WeaponId = entry.WeaponId,
		Rarity = entry.Rarity,
		Duplicate = owned,
		Compensation = compensation,
		FromEarned = debit.FromEarned,
		FromPurchased = debit.FromPurchased,
		UsedToken = args.UseToken == true,
		Time = args.Now,
	}
	table.insert(draft.CrateHistory, result)
	while #draft.CrateHistory > args.HistoryLimit do
		table.remove(draft.CrateHistory, 1)
	end
	return result
end

-- Finds a previously applied result (used to answer a replayed request idempotently).
function CrateOpening.FindResult(data: { [string]: any }, requestId: string): Result?
	for index = #data.CrateHistory, 1, -1 do
		local result = data.CrateHistory[index]
		if result.RequestId == requestId then
			return result
		end
	end
	return nil
end

return CrateOpening
