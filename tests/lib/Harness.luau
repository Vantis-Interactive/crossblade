--!nocheck
-- TestEZ-style describe/it/expect harness (see docs/DECISIONS.md D-005 for why TestEZ is not vendored).

local Harness = {}

local results = { Passed = 0, Failed = 0, Failures = {} }
local stack = {}
local beforeEachStack = {}

local function fullName(name)
	local parts = table.clone(stack)
	table.insert(parts, name)
	return table.concat(parts, " > ")
end

function Harness.describe(name, body)
	table.insert(stack, name)
	table.insert(beforeEachStack, {})
	local ok, err = pcall(body)
	if not ok then
		results.Failed += 1
		table.insert(results.Failures, { Name = fullName("(describe body)"), Error = tostring(err) })
	end
	table.remove(beforeEachStack)
	table.remove(stack)
end

function Harness.beforeEach(fn)
	table.insert(beforeEachStack[#beforeEachStack], fn)
end

function Harness.it(name, body)
	for _, level in beforeEachStack do
		for _, hook in level do
			hook()
		end
	end
	local ok, err = xpcall(body, debug.traceback)
	if ok then
		results.Passed += 1
	else
		results.Failed += 1
		table.insert(results.Failures, { Name = fullName(name), Error = tostring(err) })
	end
end

local function fmt(value)
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

local function deepEqual(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in a do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

function Harness.expect(actual)
	local negate = false
	local assertion = {}
	local function check(condition, message)
		if negate then
			condition = not condition
			message = "NOT " .. message
		end
		if not condition then
			error("expectation failed: " .. message, 3)
		end
	end
	assertion.never = setmetatable({}, {
		__index = function(_, key)
			negate = true
			return assertion[key]
		end,
	})
	function assertion.toBe(expected)
		check(actual == expected, `expected {fmt(actual)} to be {fmt(expected)}`)
	end
	function assertion.toEqual(expected)
		check(deepEqual(actual, expected), `expected {fmt(actual)} to deep-equal {fmt(expected)}`)
	end
	function assertion.toBeNear(expected, epsilon)
		check(
			type(actual) == "number" and math.abs(actual - expected) <= (epsilon or 1e-6),
			`expected {fmt(actual)} to be near {fmt(expected)}`
		)
	end
	function assertion.toBeNil()
		check(actual == nil, `expected {fmt(actual)} to be nil`)
	end
	function assertion.toBeTruthy()
		check(not not actual, `expected {fmt(actual)} to be truthy`)
	end
	function assertion.toBeGreaterThan(expected)
		check(actual > expected, `expected {fmt(actual)} > {fmt(expected)}`)
	end
	function assertion.toBeLessThan(expected)
		check(actual < expected, `expected {fmt(actual)} < {fmt(expected)}`)
	end
	function assertion.toBeAtMost(expected)
		check(actual <= expected, `expected {fmt(actual)} <= {fmt(expected)}`)
	end
	function assertion.toThrow(pattern)
		local ok, err = pcall(actual)
		local matched = not ok and (pattern == nil or string.find(tostring(err), pattern, 1, true) ~= nil)
		check(
			matched,
			`expected function to throw{if pattern then " matching " .. fmt(pattern) else ""} (got {fmt(err)})`
		)
	end
	return assertion
end

function Harness.Results()
	return results
end

return Harness
