--!strict
--[[
	Retry with exponential backoff and jitter. Used for every DataStore / MemoryStore / Teleport call.
	The sleep function is injectable so tests run instantly.
]]

export type Options = {
	MaxAttempts: number,
	BaseBackoffSeconds: number,
	MaxBackoffSeconds: number,
	Sleep: ((seconds: number) -> ())?,
	Random: (() -> number)?,
	-- Return false to stop retrying immediately for a non-retryable error.
	ShouldRetry: ((err: any, attempt: number) -> boolean)?,
}

local Retry = {}

function Retry.BackoffFor(attempt: number, base: number, maximum: number, jitter: number): number
	local delay = math.min(maximum, base * 2 ^ (attempt - 1))
	-- Up to 25% jitter avoids synchronized retry storms across servers.
	return delay * (1 + 0.25 * jitter)
end

-- Calls fn until it succeeds. Returns (true, results...) or (false, lastError, attempts).
function Retry.Call<T>(options: Options, fn: (attempt: number) -> T): (boolean, any, number)
	local sleep = options.Sleep or task.wait
	local random = options.Random or math.random
	local lastError: any = nil
	for attempt = 1, options.MaxAttempts do
		local ok, result = pcall(fn, attempt)
		if ok then
			return true, result, attempt
		end
		lastError = result
		if options.ShouldRetry and not options.ShouldRetry(result, attempt) then
			return false, lastError, attempt
		end
		if attempt < options.MaxAttempts then
			sleep(Retry.BackoffFor(attempt, options.BaseBackoffSeconds, options.MaxBackoffSeconds, random()))
		end
	end
	return false, lastError, options.MaxAttempts
end

return Retry
