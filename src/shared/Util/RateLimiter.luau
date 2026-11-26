--!strict
--[[
	Token-bucket rate limiter keyed by an arbitrary key (usually a player UserId).
	Pure: time is passed in explicitly, so behaviour is deterministic and unit-testable.
]]

local RateLimiter = {}
RateLimiter.__index = RateLimiter

type Bucket = { Tokens: number, Updated: number }

export type RateLimiter = typeof(setmetatable(
	{} :: { Capacity: number, RefillPerSecond: number, _buckets: { [any]: Bucket } },
	RateLimiter
))

function RateLimiter.new(capacity: number, refillPerSecond: number): RateLimiter
	assert(capacity > 0, "capacity must be positive")
	assert(refillPerSecond >= 0, "refill must be non-negative")
	return setmetatable(
		{ Capacity = capacity, RefillPerSecond = refillPerSecond, _buckets = {} },
		RateLimiter
	)
end

-- Attempts to consume `cost` tokens. Returns true if allowed.
function RateLimiter.Consume(self: RateLimiter, key: any, now: number, cost: number?): boolean
	local amount = cost or 1
	local bucket = self._buckets[key]
	if bucket == nil then
		bucket = { Tokens = self.Capacity, Updated = now }
		self._buckets[key] = bucket
	end
	local elapsed = math.max(0, now - bucket.Updated)
	bucket.Tokens = math.min(self.Capacity, bucket.Tokens + elapsed * self.RefillPerSecond)
	bucket.Updated = now
	if bucket.Tokens >= amount then
		bucket.Tokens -= amount
		return true
	end
	return false
end

function RateLimiter.Reset(self: RateLimiter, key: any)
	self._buckets[key] = nil
end

return RateLimiter
