--!strict
-- Production adapter: MemoryStoreSortedMap behind the Queue.SortedMap interface.

local MemoryStoreService = game:GetService("MemoryStoreService")

local MemoryStoreAdapter = {}

-- The underlying map is created on first use, so constructing an adapter can never fail during a
-- service's Init (e.g. Studio without API access); failures surface inside callers' pcalls.
function MemoryStoreAdapter.Map(name: string): any
	local cached: any = nil
	local function sortedMap(): any
		if cached == nil then
			cached = MemoryStoreService:GetSortedMap(name)
		end
		return cached
	end
	return {
		GetAsync = function(_self, key: string)
			return sortedMap():GetAsync(key)
		end,
		SetAsync = function(_self, key: string, value: any, expiration: number, sortKey: number?)
			return sortedMap():SetAsync(key, value, expiration, sortKey)
		end,
		UpdateAsync = function(_self, key: string, transform: (any, any) -> (any, any), expiration: number)
			return sortedMap():UpdateAsync(key, transform, expiration)
		end,
		RemoveAsync = function(_self, key: string)
			sortedMap():RemoveAsync(key)
		end,
		GetRangeAsync = function(_self, direction: string, count: number)
			local items = sortedMap():GetRangeAsync(
				if direction == "Ascending"
					then Enum.SortDirection.Ascending
					else Enum.SortDirection.Descending,
				count
			)
			local result = {}
			for _, item in items do
				table.insert(result, { key = item.key, value = item.value, sortKey = item.sortKey })
			end
			return result
		end,
	}
end

return MemoryStoreAdapter
