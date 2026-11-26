--!strict
-- Spawn selection weights (spec §10: consider nearby opponents, recent eliminations, spawn camping).
local Spawning = {
	-- Distance to the nearest living opponent is the base score, capped here (studs).
	EnemyDistanceCap = 120,
	-- Opponents closer than this make a spawn unusable unless every spawn is unsafe.
	UnsafeEnemyDistance = 18,
	RecentDeath = { Radius = 40, WindowSeconds = 10, Penalty = 30 },
	RecentUse = { WindowSeconds = 6, Penalty = 50 },
	LineOfSight = { MaxDistance = 150, Penalty = 40 },
	-- Choose randomly among spawns within this many points of the best score (avoids predictability).
	ChoiceMargin = 12,
}

return table.freeze(Spawning)
