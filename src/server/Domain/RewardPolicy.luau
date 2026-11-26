--!strict
--[[
	Match reward rules and anti-farming (spec §13). Pure.

	Evaluate() turns one elimination into per-player grants (coins + XP + reasons), applying:
	  - mode/server eligibility (private matches and owned private servers award nothing)
	  - minimum population
	  - repeat-victim limits (the same killer->victim pair is rewarded at most N times per window,
	    which defeats cooperative and alt-account farming)
	Self-eliminations and environmental deaths without an attacker award nothing.
	ApplyHourlyCap() bounds match-earned coins/XP per rolling hour using persisted counters.
]]

export type Event = {
	KillerId: number?,
	VictimId: number,
	Kind: string, -- "Firearm" | "Knife" | "ThrownKnife" | "Finished" | "Environment"
	Headshot: boolean,
	AssistIds: { number },
	KillerStreak: number,
}

export type Grant = { Coins: number, XP: number, Reasons: { string } }

export type Context = {
	Enabled: boolean,
	Population: number,
	Now: number,
	Guard: Guard,
	Rewards: { [string]: any },
	Experience: { [string]: number },
	AntiFarming: { [string]: any },
}

export type Guard = { Pairs: { [string]: { number } } }

local RewardPolicy = {}

function RewardPolicy.NewGuard(): Guard
	return { Pairs = {} }
end

local function add(grants: { [number]: Grant }, userId: number, coins: number, xp: number, reason: string)
	local grant = grants[userId]
	if grant == nil then
		grant = { Coins = 0, XP = 0, Reasons = {} }
		grants[userId] = grant
	end
	grant.Coins += coins
	grant.XP += xp
	table.insert(grant.Reasons, reason)
end

-- Records the pair and reports whether it is still within the rewarded limit.
local function pairAllowed(
	guard: Guard,
	killerId: number,
	victimId: number,
	now: number,
	limit: { [string]: number }
): boolean
	local key = `{killerId}>{victimId}`
	local times = guard.Pairs[key] or {}
	local cutoff = now - limit.WindowSeconds
	local kept = {}
	for _, time in times do
		if time > cutoff then
			table.insert(kept, time)
		end
	end
	local allowed = #kept < limit.MaxRewarded
	if allowed then
		table.insert(kept, now)
	end
	guard.Pairs[key] = kept
	return allowed
end

function RewardPolicy.Evaluate(event: Event, context: Context): { [number]: Grant }
	local grants: { [number]: Grant } = {}
	if not context.Enabled or context.Population < context.AntiFarming.MinPlayersForRewards then
		return grants
	end
	local killer = event.KillerId
	if killer == nil or killer == event.VictimId then
		return grants
	end
	if
		not pairAllowed(context.Guard, killer, event.VictimId, context.Now, context.AntiFarming.RepeatVictim)
	then
		return grants -- farmed pair: no rewards for anyone on this elimination
	end

	local R, X = context.Rewards, context.Experience
	if event.Kind == "Finished" then
		add(grants, killer, R.FinishedElimination, X.FinishedElimination, "FinishedElimination")
	else
		local knife = event.Kind == "Knife" or event.Kind == "ThrownKnife"
		add(
			grants,
			killer,
			if knife then R.KnifeElimination else R.GunElimination,
			X.Elimination,
			if knife then "KnifeElimination" else "GunElimination"
		)
		if event.Headshot then
			add(grants, killer, R.HeadshotEliminationBonus, X.HeadshotBonus, "Headshot")
		end
	end
	if event.KillerStreak > 0 and event.KillerStreak % R.Streak.Every == 0 then
		add(grants, killer, R.Streak.Coins, 0, `Streak{event.KillerStreak}`)
	end
	for _, assistId in event.AssistIds do
		if assistId ~= event.VictimId and assistId ~= killer then
			add(grants, assistId, R.Assist, X.Assist, "Assist")
		end
	end
	return grants
end

--[[
	Clamps a grant to the hourly caps using the persisted counters in `economy`
	({ HourStart, HourCoins, HourXP }), updating them. Returns the allowed (coins, xp).
]]
function RewardPolicy.ApplyHourlyCap(
	economy: { [string]: number },
	now: number,
	coins: number,
	xp: number,
	antiFarming: { [string]: any }
): (number, number)
	if now - economy.HourStart >= 3600 then
		economy.HourStart = now
		economy.HourCoins = 0
		economy.HourXP = 0
	end
	local allowedCoins = math.clamp(antiFarming.HourlyCoinCap - economy.HourCoins, 0, math.max(0, coins))
	local allowedXP = math.clamp(antiFarming.HourlyXPCap - economy.HourXP, 0, math.max(0, xp))
	economy.HourCoins += allowedCoins
	economy.HourXP += allowedXP
	return allowedCoins, allowedXP
end

return RewardPolicy
