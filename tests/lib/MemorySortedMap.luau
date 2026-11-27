--!nocheck
--[[
	TEST DOUBLE ONLY. In-memory MemoryStoreSortedMap with expiration, transform-cancel semantics,
	ascending/descending ranges by (sortKey, key), and injectable clock and failures.
]]

local MemorySortedMap = {}
MemorySortedMap.__index = MemorySortedMap

local function copy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = copy(v)
	end
	return out
end

function MemorySortedMap.new(clock)
	return setmetatable({ Items = {}, Clock = clock or os.clock, FailNext = 0 }, MemorySortedMap)
end

function MemorySortedMap:_live(key)
	local item = self.Items[key]
	if item and item.ExpiresAt <= self.Clock() then
		self.Items[key] = nil
		return nil
	end
	return item
end

function MemorySortedMap:_fail()
	if self.FailNext > 0 then
		self.FailNext -= 1
		error("simulated MemoryStore failure")
	end
end

function MemorySortedMap:GetAsync(key)
	self:_fail()
	local item = self:_live(key)
	return item and copy(item.Value)
end

function MemorySortedMap:SetAsync(key, value, expiration, sortKey)
	self:_fail()
	self.Items[key] = { Value = copy(value), ExpiresAt = self.Clock() + expiration, SortKey = sortKey }
	return true
end

function MemorySortedMap:UpdateAsync(key, transform, expiration)
	self:_fail()
	local item = self:_live(key)
	local newValue, newSortKey = transform(item and copy(item.Value), item and item.SortKey)
	if newValue == nil then
		return nil
	end
	self.Items[key] = {
		Value = copy(newValue),
		ExpiresAt = self.Clock() + expiration,
		SortKey = if newSortKey ~= nil then newSortKey else (item and item.SortKey),
	}
	return copy(newValue)
end

function MemorySortedMap:RemoveAsync(key)
	self:_fail()
	self.Items[key] = nil
end

function MemorySortedMap:GetRangeAsync(direction, count)
	self:_fail()
	local list = {}
	for key in self.Items do
		local item = self:_live(key)
		if item then
			table.insert(list, { key = key, value = copy(item.Value), sortKey = item.SortKey })
		end
	end
	table.sort(list, function(a, b)
		local sa, sb = a.sortKey or 0, b.sortKey or 0
		if sa ~= sb then
			if direction == "Ascending" then
				return sa < sb
			end
			return sa > sb
		end
		return a.key < b.key
	end)
	local result = {}
	for i = 1, math.min(count, #list) do
		result[i] = list[i]
	end
	return result
end

return MemorySortedMap
