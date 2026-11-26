--!strict
-- Single entry point for all configuration. Gameplay code reads tuning values only from here.
return table.freeze({
	Player = require(script.Player),
	Camera = require(script.Camera),
	Input = require(script.Input),
	Combat = require(script.Combat),
	Pickups = require(script.Pickups),
	Spawning = require(script.Spawning),
	GameModes = require(script.GameModes),
	Data = require(script.Data),
	AntiCheat = require(script.AntiCheat),
	FeatureFlags = require(script.FeatureFlags),
	Rarity = require(script.Rarity),
	Theme = require(script.Theme),
	Collections = require(script.Collections),
	Economy = require(script.Economy),
	Progression = require(script.Progression),
	Crates = require(script.Crates),
	Archetypes = require(script.Weapons.Archetypes),
	Catalog = require(script.Weapons.Catalog),
})
