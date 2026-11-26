--!strict
-- Map voting between matches (spec §5, §17). Pure; randomness is injected.

export type Vote = { Options: { string }, Votes: { [number]: string } }

local MapVote = {}

-- Up to `count` options from `eligible`, preferring maps other than `current` when possible.
function MapVote.Options(
	eligible: { string },
	current: string?,
	count: number,
	random: () -> number
): { string }
	local pool = {}
	for _, id in eligible do
		if id ~= current then
			table.insert(pool, id)
		end
	end
	if #pool == 0 and current then
		table.insert(pool, current)
	end
	table.sort(pool)
	local options = {}
	while #options < count and #pool > 0 do
		local index = math.clamp(math.floor(random() * #pool) + 1, 1, #pool)
		table.insert(options, table.remove(pool, index) :: string)
	end
	return options
end

function MapVote.new(options: { string }): Vote
	return { Options = table.clone(options), Votes = {} }
end

function MapVote.Cast(vote: Vote, userId: number, mapId: string): boolean
	if not table.find(vote.Options, mapId) then
		return false
	end
	vote.Votes[userId] = mapId
	return true
end

function MapVote.Remove(vote: Vote, userId: number)
	vote.Votes[userId] = nil
end

function MapVote.Tally(vote: Vote): { [string]: number }
	local counts = {}
	for _, option in vote.Options do
		counts[option] = 0
	end
	for _, mapId in vote.Votes do
		counts[mapId] += 1
	end
	return counts
end

-- Most votes wins; ties (including no votes) are broken randomly among the tied options.
function MapVote.Winner(vote: Vote, random: () -> number): string?
	if #vote.Options == 0 then
		return nil
	end
	local counts = MapVote.Tally(vote)
	local best = -1
	local tied = {}
	for _, option in vote.Options do
		if counts[option] > best then
			best = counts[option]
			tied = { option }
		elseif counts[option] == best then
			table.insert(tied, option)
		end
	end
	return tied[math.clamp(math.floor(random() * #tied) + 1, 1, #tied)]
end

return MapVote
