--!strict
-- Tracks who damaged whom and when, for assist attribution (spec §9 "Assist tracking").

export type Entry = { Damage: number, LastTime: number }
export type DamageLedger = { Victims: { [number]: { [number]: Entry } } }

local DamageLedger = {}

function DamageLedger.new(): DamageLedger
	return { Victims = {} }
end

function DamageLedger.Record(
	ledger: DamageLedger,
	victimId: number,
	attackerId: number,
	amount: number,
	now: number
)
	if victimId == attackerId or amount <= 0 then
		return
	end
	local attackers = ledger.Victims[victimId]
	if attackers == nil then
		attackers = {}
		ledger.Victims[victimId] = attackers
	end
	local entry = attackers[attackerId]
	if entry == nil then
		attackers[attackerId] = { Damage = amount, LastTime = now }
	else
		entry.Damage += amount
		entry.LastTime = now
	end
end

-- Attackers other than the killer who dealt at least `minimumDamage` within `window` seconds.
-- Sorted by damage, highest first.
function DamageLedger.Assists(
	ledger: DamageLedger,
	victimId: number,
	killerId: number?,
	now: number,
	minimumDamage: number,
	window: number
): { number }
	local result = {}
	local attackers = ledger.Victims[victimId]
	if attackers == nil then
		return result
	end
	for attackerId, entry in attackers do
		if attackerId ~= killerId and entry.Damage >= minimumDamage and now - entry.LastTime <= window then
			table.insert(result, attackerId)
		end
	end
	table.sort(result, function(a, b)
		return attackers[a].Damage > attackers[b].Damage
	end)
	return result
end

function DamageLedger.ClearVictim(ledger: DamageLedger, victimId: number)
	ledger.Victims[victimId] = nil
end

-- Remove a player entirely (left the server).
function DamageLedger.ForgetPlayer(ledger: DamageLedger, userId: number)
	ledger.Victims[userId] = nil
	for _, attackers in ledger.Victims do
		attackers[userId] = nil
	end
end

return DamageLedger
