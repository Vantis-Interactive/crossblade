--!strict
--[[
	Spawn point selection (spec §10). Scores each spawn by distance to living opponents, penalizes
	spawns near recent eliminations, recently used spawns (anti spawn-camping), and spawns in an
	opponent's line of sight; then picks randomly among the near-best to stay unpredictable.
]]

export type SpawnPoint = { Id: string, Position: Vector3 }
export type Death = { Position: Vector3, Time: number }

export type Weights = {
	EnemyDistanceCap: number,
	UnsafeEnemyDistance: number,
	RecentDeath: { Radius: number, WindowSeconds: number, Penalty: number },
	RecentUse: { WindowSeconds: number, Penalty: number },
	LineOfSight: { MaxDistance: number, Penalty: number },
	ChoiceMargin: number,
}

export type Input = {
	Spawns: { SpawnPoint },
	Enemies: { Vector3 },
	RecentDeaths: { Death },
	LastUsed: { [string]: number },
	Now: number,
	Weights: Weights,
	LineOfSight: ((from: Vector3, to: Vector3) -> boolean)?,
	Random: (() -> number)?,
}

local SpawnSelector = {}

function SpawnSelector.Score(spawn: SpawnPoint, input: Input): (number, boolean)
	local w = input.Weights
	local nearest = math.huge
	local seen = false
	for _, enemy in input.Enemies do
		local distance = (enemy - spawn.Position).Magnitude
		nearest = math.min(nearest, distance)
		if not seen and input.LineOfSight and distance <= w.LineOfSight.MaxDistance then
			if input.LineOfSight(enemy, spawn.Position) then
				seen = true
			end
		end
	end
	local score = math.min(nearest, w.EnemyDistanceCap)
	for _, death in input.RecentDeaths do
		if
			input.Now - death.Time <= w.RecentDeath.WindowSeconds
			and (death.Position - spawn.Position).Magnitude <= w.RecentDeath.Radius
		then
			score -= w.RecentDeath.Penalty
		end
	end
	local lastUsed = input.LastUsed[spawn.Id]
	if lastUsed and input.Now - lastUsed <= w.RecentUse.WindowSeconds then
		score -= w.RecentUse.Penalty
	end
	if seen then
		score -= w.LineOfSight.Penalty
	end
	return score, nearest < w.UnsafeEnemyDistance
end

function SpawnSelector.Select(input: Input): SpawnPoint?
	if #input.Spawns == 0 then
		return nil
	end
	local scored = {}
	local anySafe = false
	for _, spawn in input.Spawns do
		local score, unsafe = SpawnSelector.Score(spawn, input)
		anySafe = anySafe or not unsafe
		table.insert(scored, { Spawn = spawn, Score = score, Unsafe = unsafe })
	end
	local best = -math.huge
	for _, entry in scored do
		if (not anySafe or not entry.Unsafe) and entry.Score > best then
			best = entry.Score
		end
	end
	local candidates = {}
	for _, entry in scored do
		if (not anySafe or not entry.Unsafe) and entry.Score >= best - input.Weights.ChoiceMargin then
			table.insert(candidates, entry.Spawn)
		end
	end
	local random = input.Random or math.random
	local index = math.clamp(math.floor(random() * #candidates) + 1, 1, #candidates)
	return candidates[index]
end

return SpawnSelector
