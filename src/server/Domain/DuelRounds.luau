--!strict
--[[
	Duel round state (spec §5): best-of-N rounds, no respawns within a round, the last team with a
	living member wins the round, first to RoundsToWin wins the match. Players who leave count as
	eliminated; a team with no remaining members forfeits. At the round time limit the team with more
	survivors wins, then the team with more total health; a full tie replays the round.
]]

local Teams = require(script.Parent.Teams)

export type State = {
	RoundsToWin: number,
	Wins: { [string]: number },
	Round: number,
	Alive: { [string]: { [number]: boolean } },
	Roster: { [number]: Teams.TeamId },
	Winner: Teams.TeamId?,
	RoundOver: boolean,
}

export type Outcome = { RoundWinner: Teams.TeamId?, MatchWinner: Teams.TeamId?, Draw: boolean }

local DuelRounds = {}

local function countAlive(state: State, team: Teams.TeamId): number
	local count = 0
	for _ in state.Alive[team] do
		count += 1
	end
	return count
end

function DuelRounds.new(roundsToWin: number, roster: { [number]: Teams.TeamId }): State
	return {
		RoundsToWin = roundsToWin,
		Wins = { A = 0, B = 0 },
		Round = 0,
		Alive = { A = {}, B = {} },
		Roster = table.clone(roster),
		Winner = nil,
		RoundOver = true,
	}
end

function DuelRounds.StartRound(state: State)
	assert(state.Winner == nil, "match already decided")
	state.Round += 1
	state.RoundOver = false
	state.Alive = { A = {}, B = {} }
	for userId, team in state.Roster do
		state.Alive[team][userId] = true
	end
end

local function award(state: State, team: Teams.TeamId): Outcome
	state.RoundOver = true
	state.Wins[team] += 1
	if state.Wins[team] >= state.RoundsToWin then
		state.Winner = team
	end
	return { RoundWinner = team, MatchWinner = state.Winner, Draw = false }
end

local NONE: Outcome = table.freeze({ RoundWinner = nil, MatchWinner = nil, Draw = false })

function DuelRounds.Eliminate(state: State, userId: number): Outcome
	local team = state.Roster[userId]
	if state.RoundOver or team == nil or not state.Alive[team][userId] then
		return NONE
	end
	state.Alive[team][userId] = nil
	if countAlive(state, team) == 0 then
		return award(state, Teams.Other(team))
	end
	return NONE
end

-- A participant left the server: removed from the roster; their team forfeits if now empty.
function DuelRounds.RemovePlayer(state: State, userId: number): Outcome
	local team = state.Roster[userId]
	if team == nil or state.Winner then
		return NONE
	end
	local outcome = DuelRounds.Eliminate(state, userId)
	state.Roster[userId] = nil
	local remaining = 0
	for _, value in state.Roster do
		if value == team then
			remaining += 1
		end
	end
	if remaining == 0 and state.Winner == nil then
		state.RoundOver = true
		state.Winner = Teams.Other(team)
		return { RoundWinner = outcome.RoundWinner, MatchWinner = state.Winner, Draw = false }
	end
	return outcome
end

-- Round time limit. `healthOf(userId)` returns current health for survivors.
function DuelRounds.TimeUp(state: State, healthOf: (number) -> number): Outcome
	if state.RoundOver then
		return NONE
	end
	local a, b = countAlive(state, "A"), countAlive(state, "B")
	if a ~= b then
		return award(state, if a > b then "A" else "B")
	end
	local healthA, healthB = 0, 0
	for userId in state.Alive.A do
		healthA += healthOf(userId)
	end
	for userId in state.Alive.B do
		healthB += healthOf(userId)
	end
	if healthA ~= healthB then
		return award(state, if healthA > healthB then "A" else "B")
	end
	state.RoundOver = true
	return { RoundWinner = nil, MatchWinner = nil, Draw = true }
end

function DuelRounds.IsAlive(state: State, userId: number): boolean
	local team = state.Roster[userId]
	return team ~= nil and not state.RoundOver and state.Alive[team][userId] == true
end

return DuelRounds
