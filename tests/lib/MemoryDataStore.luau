--!nocheck
--[[
	TEST DOUBLE ONLY. In-memory implementation of the ProfileStore adapter contract with the parts of
	DataStore semantics that matter for correctness: values are serialized (deep-copied) on write,
	a nil transform result cancels the write, and failures/concurrent writers can be injected.
]]

local MemoryDataStore = {}
MemoryDataStore.__index = MemoryDataStore

local function copy(value)
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for k, v in value do
		result[k] = copy(v)
	end
	return result
end

function MemoryDataStore.new()
	return setmetatable(
		{ Data = {}, Writes = 0, Calls = 0, FailNext = 0, BeforeTransform = nil },
		MemoryDataStore
	)
end

function MemoryDataStore:UpdateAsync(key, transform, userIds)
	self.Calls += 1
	if self.FailNext > 0 then
		self.FailNext -= 1
		error("simulated DataStore outage")
	end
	if self.BeforeTransform then
		self.BeforeTransform(self, key)
	end
	local newValue = transform(copy(self.Data[key]))
	if newValue == nil then
		return copy(self.Data[key])
	end
	self.Data[key] = copy(newValue)
	self.LastUserIds = userIds
	self.Writes += 1
	return copy(newValue)
end

return MemoryDataStore
