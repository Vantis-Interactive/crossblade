--!strict
local TableUtil = {}

function TableUtil.DeepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in value :: any do
		copy[TableUtil.DeepCopy(key)] = TableUtil.DeepCopy(inner)
	end
	return (copy :: any) :: T
end

function TableUtil.DeepFreeze<T>(value: T): T
	if type(value) == "table" and not table.isfrozen(value :: any) then
		for _, inner in value :: any do
			TableUtil.DeepFreeze(inner)
		end
		table.freeze(value :: any)
	end
	return value
end

--[[
	Adds any keys present in `template` but missing from `target`, recursively, without ever
	overwriting an existing value. Used to add new schema fields to existing player data.
	Returns the number of keys added.
]]
function TableUtil.Reconcile(target: { [any]: any }, template: { [any]: any }): number
	local added = 0
	for key, templateValue in template do
		local existing = target[key]
		if existing == nil then
			target[key] = TableUtil.DeepCopy(templateValue)
			added += 1
		elseif type(existing) == "table" and type(templateValue) == "table" then
			added += TableUtil.Reconcile(existing, templateValue)
		end
	end
	return added
end

function TableUtil.Count(value: { [any]: any }): number
	local count = 0
	for _ in value do
		count += 1
	end
	return count
end

return TableUtil
