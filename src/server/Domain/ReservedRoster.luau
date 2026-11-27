--!strict
--[[
	Admission and start rules for reserved match servers (spec §19). Pure.
	  - Only rostered players may play; everyone else is turned away.
	  - The match starts when every rostered player has arrived, or at the arrival deadline with
	    whoever is present if that is a playable match (both teams represented in team modes);
	    otherwise the match is cancelled and players are returned to the hub.
	  - A rostered player who disconnects may reconnect until their reconnect deadline.
]]

export type Roster = { Teams: { [string]: { number } } }
export type State = {
	Members: { [number]: string }, -- userId -> team
	Present: { [number]: boolean },
	Disconnected: { [number]: number }, -- userId -> reconnect deadline
	ArrivalDeadline: number,
	Started: boolean,
}

export type Decision = "Wait" | "Start" | "Cancel"

local ReservedRoster = {}

function ReservedRoster.new(roster: Roster, now: number, arrivalSeconds: number): State
	local members = {}
	for team, ids in roster.Teams do
		for _, userId in ids do
			members[userId] = team
		end
	end
	return {
		Members = members,
		Present = {},
		Disconnected = {},
		ArrivalDeadline = now + arrivalSeconds,
		Started = false,
	}
end

function ReservedRoster.Admit(state: State, userId: number, now: number): (boolean, string?)
	if state.Members[userId] == nil then
		return false, "NotRostered"
	end
	local deadline = state.Disconnected[userId]
	if deadline ~= nil and now > deadline then
		return false, "ReconnectExpired"
	end
	state.Disconnected[userId] = nil
	state.Present[userId] = true
	return true, nil
end

function ReservedRoster.Disconnect(state: State, userId: number, now: number, reconnectSeconds: number)
	if state.Present[userId] then
		state.Present[userId] = nil
		state.Disconnected[userId] = now + reconnectSeconds
	end
end

-- Players whose reconnect window has passed (caller treats them as having left for good).
function ReservedRoster.Expired(state: State, now: number): { number }
	local list = {}
	for userId, deadline in state.Disconnected do
		if now > deadline then
			table.insert(list, userId)
		end
	end
	for _, userId in list do
		state.Disconnected[userId] = nil
	end
	return list
end

function ReservedRoster.Decide(state: State, now: number, teamMode: boolean): Decision
	if state.Started then
		return "Start"
	end
	local total, present = 0, 0
	local teamsPresent: { [string]: boolean } = {}
	for userId, team in state.Members do
		total += 1
		if state.Present[userId] then
			present += 1
			teamsPresent[team] = true
		end
	end
	if present == total and total > 0 then
		return "Start"
	end
	if now < state.ArrivalDeadline then
		return "Wait"
	end
	local playable = if teamMode then teamsPresent.A == true and teamsPresent.B == true else present >= 1
	return if playable then "Start" else "Cancel"
end

return ReservedRoster
