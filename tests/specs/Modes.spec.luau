--!nocheck
local Config = Runtime:Get("ReplicatedStorage/Shared/Config")
local Teams = Runtime:Get("ServerScriptService/Server/Domain/Teams")
local DuelRounds = Runtime:Get("ServerScriptService/Server/Domain/DuelRounds")
local MapVote = Runtime:Get("ServerScriptService/Server/Domain/MapVote")
local TutorialProgress = Runtime:Get("ServerScriptService/Server/Domain/TutorialProgress")
local PlaceConfig = Runtime:Get("ReplicatedStorage/Shared/PlaceConfig")

local function fixed(value)
	return function()
		return value
	end
end

describe("Teams", function()
	it("assigns newcomers to the smaller team and respects capacity", function()
		local assignment = {}
		for userId = 1, 4 do
			assignment[userId] = Teams.Pick(assignment, 2)
		end
		expect(Teams.Count(assignment, "A")).toBe(2)
		expect(Teams.Count(assignment, "B")).toBe(2)
		expect(Teams.Pick(assignment, 2)).toBeNil()
	end)
	it("balances an ordered list and reports overflow", function()
		local assignment, overflow = Teams.Balance({ 10, 11, 12 }, 1)
		expect(assignment[10]).toBe("A")
		expect(assignment[11]).toBe("B")
		expect(overflow).toEqual({ 12 })
	end)
	it("decides Team Deathmatch by score limit, then by score at time, with draws", function()
		local limit = Config.GameModes.TeamDeathmatch.ScoreLimit
		expect(Teams.DeathmatchWinner({ A = limit, B = 3 }, limit, false)).toBe("A")
		local winner, over = Teams.DeathmatchWinner({ A = 10, B = 3 }, limit, false)
		expect(winner).toBeNil()
		expect(over).toBe(false)
		expect(Teams.DeathmatchWinner({ A = 10, B = 12 }, limit, true)).toBe("B")
		local drawWinner, drawOver = Teams.DeathmatchWinner({ A = 7, B = 7 }, limit, true)
		expect(drawWinner).toBeNil()
		expect(drawOver).toBe(true)
	end)
end)

describe("DuelRounds", function()
	local roster = { [1] = "A", [2] = "B" }

	it("plays best of five: first to three round wins takes the match", function()
		local state = DuelRounds.new(Config.GameModes.CasualDuel1v1.RoundsToWin, roster)
		for round = 1, 3 do
			DuelRounds.StartRound(state)
			local outcome = DuelRounds.Eliminate(state, 2)
			expect(outcome.RoundWinner).toBe("A")
			if round < 3 then
				expect(outcome.MatchWinner).toBeNil()
			else
				expect(outcome.MatchWinner).toBe("A")
			end
		end
		expect(state.Wins.A).toBe(3)
	end)

	it("eliminated players stay out until the next round", function()
		local state = DuelRounds.new(4, { [1] = "A", [2] = "A", [3] = "B", [4] = "B" })
		DuelRounds.StartRound(state)
		expect(DuelRounds.Eliminate(state, 1).RoundWinner).toBeNil()
		expect(DuelRounds.IsAlive(state, 1)).toBe(false)
		expect(DuelRounds.IsAlive(state, 2)).toBe(true)
		expect(DuelRounds.Eliminate(state, 1).RoundWinner).toBeNil() -- double elimination ignored
		DuelRounds.Eliminate(state, 3)
		expect(DuelRounds.Eliminate(state, 4).RoundWinner).toBe("A")
		DuelRounds.StartRound(state)
		expect(DuelRounds.IsAlive(state, 1)).toBe(true)
	end)

	it("a team whose players all leave forfeits the match", function()
		local state = DuelRounds.new(3, roster)
		DuelRounds.StartRound(state)
		expect(DuelRounds.RemovePlayer(state, 1).MatchWinner).toBe("B")
	end)

	it("resolves the round time limit by survivors, then health, else replays", function()
		local state = DuelRounds.new(3, { [1] = "A", [2] = "A", [3] = "B", [4] = "B" })
		DuelRounds.StartRound(state)
		DuelRounds.Eliminate(state, 3)
		expect(DuelRounds.TimeUp(state, fixed(100)).RoundWinner).toBe("A")
		DuelRounds.StartRound(state)
		local health = { [1] = 50, [2] = 50, [3] = 150, [4] = 10 }
		expect(DuelRounds.TimeUp(state, function(id)
			return health[id]
		end).RoundWinner).toBe("B")
		DuelRounds.StartRound(state)
		local draw = DuelRounds.TimeUp(state, fixed(150))
		expect(draw.Draw).toBe(true)
		expect(state.Wins.A + state.Wins.B).toBe(2)
	end)
end)

describe("MapVote", function()
	it("offers maps other than the current one when possible", function()
		local options = MapVote.Options({ "a", "b", "c", "d" }, "a", 3, fixed(0))
		expect(#options).toBe(3)
		expect(table.find(options, "a")).toBeNil()
		expect(MapVote.Options({ "a" }, "a", 3, fixed(0))).toEqual({ "a" })
	end)
	it("counts one vote per player, rejects invalid maps, and picks the most voted", function()
		local vote = MapVote.new({ "x", "y" })
		expect(MapVote.Cast(vote, 1, "x")).toBe(true)
		expect(MapVote.Cast(vote, 1, "y")).toBe(true) -- changed vote
		expect(MapVote.Cast(vote, 2, "y")).toBe(true)
		expect(MapVote.Cast(vote, 3, "zzz")).toBe(false)
		expect(MapVote.Tally(vote)).toEqual({ x = 0, y = 2 })
		expect(MapVote.Winner(vote, fixed(0))).toBe("y")
		MapVote.Remove(vote, 1)
		MapVote.Remove(vote, 2)
		-- No votes: random among all options.
		expect(MapVote.Winner(vote, fixed(0.99))).toBe("y")
		expect(MapVote.Winner(vote, fixed(0))).toBe("x")
	end)
end)

describe("TutorialProgress", function()
	local steps = Config.Tutorial.Steps

	it("covers the twelve specified topics in order", function()
		local ids = {}
		for _, step in steps do
			table.insert(ids, step.Id)
		end
		expect(ids).toEqual({
			"Move",
			"Camera",
			"Weapons",
			"Shoot",
			"Reload",
			"Knife",
			"Throw",
			"Pickups",
			"Coins",
			"Crate",
			"Loadout",
			"Matchmaking",
		})
		expect(Config.Tutorial.Reward.Coins).toBe(500)
		expect(Config.Tutorial.Reward.CrateId).toBe("basic")
	end)

	it("only accepts the current step, and only from the right source", function()
		local state = TutorialProgress.new()
		expect(TutorialProgress.ClientComplete(state, steps, 2, false).Advanced).toBe(false) -- skipping
		expect(TutorialProgress.ClientComplete(state, steps, 1, false).Advanced).toBe(true)
		expect(TutorialProgress.ClientComplete(state, steps, 2, false).Advanced).toBe(true)
		expect(TutorialProgress.ClientComplete(state, steps, 3, false).Advanced).toBe(true)
		-- "Shoot" is server-checked: a client claim is refused, the right event is accepted.
		expect(TutorialProgress.ClientComplete(state, steps, 4, false).Advanced).toBe(false)
		expect(TutorialProgress.ServerEvent(state, steps, "Reload", false).Advanced).toBe(false)
		expect(TutorialProgress.ServerEvent(state, steps, "DummyHitFirearm", false).Advanced).toBe(true)
	end)

	it("grants the reward exactly once", function()
		local state = TutorialProgress.new()
		local granted = 0
		for index, step in steps do
			local result = if step.Check == "Client"
				then TutorialProgress.ClientComplete(state, steps, index, granted > 0)
				else TutorialProgress.ServerEvent(state, steps, step.Event, granted > 0)
			expect(result.Advanced).toBe(true)
			if result.GrantReward then
				granted += 1
			end
			expect(result.Finished).toBe(index == #steps)
		end
		expect(granted).toBe(1)
		-- Replaying the tutorial never grants it again.
		local replay = TutorialProgress.new()
		for index, step in steps do
			local result = if step.Check == "Client"
				then TutorialProgress.ClientComplete(replay, steps, index, true)
				else TutorialProgress.ServerEvent(replay, steps, step.Event, true)
			expect(result.GrantReward).toBe(false)
		end
	end)
end)

describe("Mode and place configuration", function()
	it(
		"implements Lobby, FFA, TDM and both casual duel formats; keeps ranked and private for later",
		function()
			for _, id in { "Lobby", "FreeForAll", "TeamDeathmatch", "CasualDuel1v1", "CasualDuelTeam" } do
				expect(Config.GameModes[id].Implemented).toBe(true)
			end
			expect(Config.GameModes.RankedDuel.Implemented).toBe(false)
			expect(Config.GameModes.Private.Implemented).toBe(false)
			expect(Config.GameModes.Lobby.AwardsProgression).toBe(false)
		end
	)
	it("duels never respawn within a round; FFA and TDM do", function()
		expect(Config.GameModes.CasualDuel1v1.RespawnDelaySeconds).toBeNil()
		expect(Config.GameModes.CasualDuelTeam.RespawnDelaySeconds).toBeNil()
		expect(Config.GameModes.FreeForAll.RespawnDelaySeconds).toBe(3)
		expect(Config.GameModes.TeamDeathmatch.RespawnDelaySeconds).toBe(5)
	end)
	it("every destination points at an implemented mode", function()
		for id, destination in Config.Places.Destinations do
			if destination.Mode then
				expect(Config.GameModes[destination.Mode].Implemented).toBe(true)
			else
				expect(id).toBe("Hub")
			end
		end
	end)
	it("defaults to a Free-for-All arena when no PlaceConfig exists", function()
		expect(PlaceConfig.Role).toBe("Arena")
		expect(PlaceConfig.Mode).toBe("FreeForAll")
	end)
end)
