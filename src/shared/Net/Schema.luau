--!strict
--[[
	Declarative payload schemas for remote traffic (spec §25: "Remote request schema validation").

	Clients can send ANY value through a remote: wrong types, NaN, infinities, Instances, huge tables,
	tables with mixed keys. Check() never throws and rejects anything not explicitly allowed.
	Struct schemas reject unknown fields so clients cannot smuggle extra data.
]]

export type Schema = {
	Kind: "Number" | "Integer" | "Boolean" | "String" | "Vector3" | "Optional" | "Array" | "Struct",
	Min: number?,
	Max: number?,
	MaxLength: number?,
	Enum: { [string]: boolean }?,
	MaxMagnitude: number?,
	Inner: Schema?,
	Fields: { [string]: Schema }?,
}

local Schema = {}

function Schema.Number(min: number, max: number): Schema
	return table.freeze({ Kind = "Number", Min = min, Max = max }) :: any
end

function Schema.Integer(min: number, max: number): Schema
	return table.freeze({ Kind = "Integer", Min = min, Max = max }) :: any
end

function Schema.Boolean(): Schema
	return table.freeze({ Kind = "Boolean" }) :: any
end

function Schema.String(maxLength: number): Schema
	return table.freeze({ Kind = "String", MaxLength = maxLength }) :: any
end

function Schema.Enum(values: { string }): Schema
	local set = {}
	local longest = 0
	for _, value in values do
		set[value] = true
		longest = math.max(longest, #value)
	end
	return table.freeze({ Kind = "String", MaxLength = longest, Enum = table.freeze(set) }) :: any
end

function Schema.Vector3(maxMagnitude: number): Schema
	return table.freeze({ Kind = "Vector3", MaxMagnitude = maxMagnitude }) :: any
end

function Schema.Optional(inner: Schema): Schema
	return table.freeze({ Kind = "Optional", Inner = inner }) :: any
end

function Schema.Array(inner: Schema, maxLength: number): Schema
	return table.freeze({ Kind = "Array", Inner = inner, MaxLength = maxLength }) :: any
end

function Schema.Struct(fields: { [string]: Schema }): Schema
	return table.freeze({ Kind = "Struct", Fields = table.freeze(fields) }) :: any
end

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local check: (schema: Schema, value: any, path: string) -> (boolean, string?)

function check(schema: Schema, value: any, path: string): (boolean, string?)
	local kind = schema.Kind
	if kind == "Optional" then
		if value == nil then
			return true, nil
		end
		return check(schema.Inner :: Schema, value, path)
	end
	if value == nil then
		return false, `{path}: required`
	end

	if kind == "Number" or kind == "Integer" then
		if not isFiniteNumber(value) then
			return false, `{path}: expected finite number`
		end
		if kind == "Integer" and value % 1 ~= 0 then
			return false, `{path}: expected integer`
		end
		if value < (schema.Min :: number) or value > (schema.Max :: number) then
			return false, `{path}: out of range`
		end
		return true, nil
	elseif kind == "Boolean" then
		if type(value) ~= "boolean" then
			return false, `{path}: expected boolean`
		end
		return true, nil
	elseif kind == "String" then
		if type(value) ~= "string" then
			return false, `{path}: expected string`
		end
		if #value > (schema.MaxLength :: number) then
			return false, `{path}: too long`
		end
		if schema.Enum and not schema.Enum[value] then
			return false, `{path}: not an allowed value`
		end
		return true, nil
	elseif kind == "Vector3" then
		if typeof(value) ~= "Vector3" then
			return false, `{path}: expected Vector3`
		end
		if not (isFiniteNumber(value.X) and isFiniteNumber(value.Y) and isFiniteNumber(value.Z)) then
			return false, `{path}: non-finite Vector3`
		end
		if value.Magnitude > (schema.MaxMagnitude :: number) then
			return false, `{path}: Vector3 too large`
		end
		return true, nil
	elseif kind == "Array" then
		if type(value) ~= "table" then
			return false, `{path}: expected array`
		end
		local count = 0
		for key in value do
			count += 1
			if type(key) ~= "number" or key % 1 ~= 0 or key < 1 then
				return false, `{path}: array has non-index key`
			end
			if count > (schema.MaxLength :: number) then
				return false, `{path}: array too long`
			end
		end
		if count ~= #value then
			return false, `{path}: sparse array`
		end
		for index = 1, count do
			local ok, reason = check(schema.Inner :: Schema, value[index], `{path}[{index}]`)
			if not ok then
				return false, reason
			end
		end
		return true, nil
	elseif kind == "Struct" then
		if type(value) ~= "table" then
			return false, `{path}: expected table`
		end
		local fields = schema.Fields :: { [string]: Schema }
		for key in value do
			if type(key) ~= "string" or fields[key] == nil then
				return false, `{path}: unexpected field {tostring(key)}`
			end
		end
		for name, fieldSchema in fields do
			local ok, reason = check(fieldSchema, value[name], `{path}.{name}`)
			if not ok then
				return false, reason
			end
		end
		return true, nil
	end
	return false, `{path}: unknown schema kind`
end

function Schema.Check(schema: Schema, value: any): (boolean, string?)
	local ok, result, reason = pcall(check, schema, value, "payload")
	if not ok then
		-- Defensive: a validator bug must reject, never accept.
		return false, `validator error: {result}`
	end
	return result, reason
end

return Schema
