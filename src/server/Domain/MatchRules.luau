--!strict
-- Free-for-All scoring and ranking rules (spec §5, §9).

export type Entry = {
	UserId: number,
	Name: string,
	Eliminations: number,
	Deaths: number,
	Assists: number,
	Streak: number,
	BestStreak: number,
	Damage: number,
	JoinOrder: number,
}

local MatchRules = {}

function MatchRules.NewEntry(userId: number, name: string, joinOrder: number): Entry
	return {
		UserId = userId,
		Name = name,
		Eliminations = 0,
		Deaths = 0,
		Assists = 0,
		Streak = 0,
		BestStreak = 0,
		Damage = 0,
		JoinOrder = joinOrder,
	}
end

-- Eliminations desc, deaths asc, assists desc, damage desc, then earliest join (stable ties).
function MatchRules.Rank(entries: { Entry }): { Entry }
	local sorted = table.clone(entries)
	table.sort(sorted, function(a, b)
		if a.Eliminations ~= b.Eliminations then
			return a.Eliminations > b.Eliminations
		elseif a.Deaths ~= b.Deaths then
			return a.Deaths < b.Deaths
		elseif a.Assists ~= b.Assists then
			return a.Assists > b.Assists
		elseif a.Damage ~= b.Damage then
			return a.Damage > b.Damage
		end
		return a.JoinOrder < b.JoinOrder
	end)
	return sorted
end

-- Applies an elimination. Returns the killer's new streak if it should be announced, else nil.
function MatchRules.RecordElimination(
	killer: Entry?,
	victim: Entry,
	assisters: { Entry },
	announceAt: { number }
): number?
	victim.Deaths += 1
	victim.Streak = 0
	for _, assister in assisters do
		assister.Assists += 1
	end
	if killer == nil or killer == victim then
		return nil
	end
	killer.Eliminations += 1
	killer.Streak += 1
	killer.BestStreak = math.max(killer.BestStreak, killer.Streak)
	if table.find(announceAt, killer.Streak) then
		return killer.Streak
	end
	return nil
end

return MatchRules
