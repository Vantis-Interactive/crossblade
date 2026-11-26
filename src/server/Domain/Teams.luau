--!strict
--[[
	Team assignment and team scoring (spec §5). Two teams, "A" (Alpha) and "B" (Bravo).
	Assignment always joins the smaller team (ties go to A) and never exceeds the per-team capacity.
]]

export type TeamId = "A" | "B"

local Teams = {}

Teams.Ids = table.freeze({ "A", "B" }) :: { TeamId }
Teams.Names = table.freeze({ A = "Alpha", B = "Bravo" })

function Teams.Other(team: TeamId): TeamId
	return if team == "A" then "B" else "A"
end

-- `assignment` maps userId -> team. Returns the team for a newcomer, or nil when both are full.
function Teams.Pick(assignment: { [number]: TeamId }, capacity: number?): TeamId?
	local counts = { A = 0, B = 0 }
	for _, team in assignment do
		counts[team] += 1
	end
	local choice: TeamId = if counts.B < counts.A then "B" else "A"
	if capacity and counts[choice] >= capacity then
		return nil
	end
	return choice
end

-- Fresh balanced assignment for an ordered list of userIds (alternating A, B, A, ...).
function Teams.Balance(userIds: { number }, capacity: number?): ({ [number]: TeamId }, { number })
	local assignment: { [number]: TeamId } = {}
	local overflow = {}
	for _, userId in userIds do
		local team = Teams.Pick(assignment, capacity)
		if team then
			assignment[userId] = team
		else
			table.insert(overflow, userId)
		end
	end
	return assignment, overflow
end

function Teams.Count(assignment: { [number]: TeamId }, team: TeamId): number
	local count = 0
	for _, value in assignment do
		if value == team then
			count += 1
		end
	end
	return count
end

-- Team Deathmatch outcome: the team at the score limit wins; at time, the higher score wins.
function Teams.DeathmatchWinner(
	scores: { [string]: number },
	limit: number?,
	timeUp: boolean
): (TeamId?, boolean)
	for _, team in Teams.Ids do
		if limit and scores[team] >= limit then
			return team, true
		end
	end
	if not timeUp then
		return nil, false
	end
	if scores.A == scores.B then
		return nil, true -- draw
	end
	return if scores.A > scores.B then "A" else "B", true
end

return Teams
