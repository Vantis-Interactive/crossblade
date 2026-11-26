--!strict
--[[
	Tutorial step machine (spec §27). Pure. Steps complete strictly in order; a client may only
	complete "Client" steps, and server-observed events only complete the matching "Server" step.
	The reward is due exactly once: when the GrantsReward step completes and it was never claimed.
]]

export type Step = { Id: string, Check: string, Event: string?, GrantsReward: boolean? }
export type State = { Index: number, Active: boolean }
export type Result = { Advanced: boolean, GrantReward: boolean, Finished: boolean }

local TutorialProgress = {}

local NONE: Result = table.freeze({ Advanced = false, GrantReward = false, Finished = false })

function TutorialProgress.new(): State
	return { Index = 1, Active = true }
end

function TutorialProgress.Current(state: State, steps: { Step }): Step?
	return if state.Active then steps[state.Index] else nil
end

local function advance(state: State, steps: { Step }, rewardClaimed: boolean): Result
	local step = steps[state.Index]
	state.Index += 1
	local finished = state.Index > #steps
	if finished then
		state.Active = false
	end
	return {
		Advanced = true,
		GrantReward = step.GrantsReward == true and not rewardClaimed,
		Finished = finished,
	}
end

-- Client claims completion of step `index`.
function TutorialProgress.ClientComplete(
	state: State,
	steps: { Step },
	index: number,
	rewardClaimed: boolean
): Result
	local step = TutorialProgress.Current(state, steps)
	if step == nil or index ~= state.Index or step.Check ~= "Client" then
		return NONE
	end
	return advance(state, steps, rewardClaimed)
end

-- A gameplay event observed by the server.
function TutorialProgress.ServerEvent(
	state: State,
	steps: { Step },
	event: string,
	rewardClaimed: boolean
): Result
	local step = TutorialProgress.Current(state, steps)
	if step == nil or step.Check ~= "Server" or step.Event ~= event then
		return NONE
	end
	return advance(state, steps, rewardClaimed)
end

return TutorialProgress
