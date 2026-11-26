--!nocheck
--[[
	Test entry point:  lune run tests/run
	Discovers tests/specs/*.spec.luau, runs each with describe/it/expect plus a `Runtime` that can
	require repository modules, and exits non-zero on any failure.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Harness = require("./lib/Harness")
local Runtime = require("./lib/Runtime")
local MemoryDataStore = require("./lib/MemoryDataStore")

local root = process.cwd
if string.sub(root, -1) == "/" then
	root = string.sub(root, 1, -2)
end

local filter = process.args[1]
local specDir = root .. "/tests/specs"
local files = {}
for _, entry in fs.readDir(specDir) do
	if string.match(entry, "%.spec%.luau$") and (filter == nil or string.find(entry, filter, 1, true)) then
		table.insert(files, entry)
	end
end
table.sort(files)

for _, file in files do
	local path = specDir .. "/" .. file
	local runtime = Runtime.new(root)
	local env = runtime:Environment(nil)
	env.describe = Harness.describe
	env.it = Harness.it
	env.expect = Harness.expect
	env.beforeEach = Harness.beforeEach
	env.Runtime = runtime
	env.require = function(target)
		if type(target) == "string" then
			assert(string.sub(target, 1, 6) == "@lune/", "specs may only string-require @lune built-ins")
			if target == "@lune/fs" then
				return require("@lune/fs")
			elseif target == "@lune/process" then
				return require("@lune/process")
			end
			error("unsupported built-in " .. target)
		end
		return runtime:Require(target)
	end
	env.MemoryDataStore = MemoryDataStore
	env.Vector3 = roblox.Vector3
	env.CFrame = roblox.CFrame
	env.task = task
	local ok, err = pcall(function()
		luau.load(fs.readFile(path), { debugName = path, environment = env })()
	end)
	if not ok then
		local results = Harness.Results()
		results.Failed += 1
		table.insert(results.Failures, { Name = file .. " (load)", Error = tostring(err) })
	end
end

local results = Harness.Results()
for _, failure in results.Failures do
	print("FAIL  " .. failure.Name)
	print("      " .. string.gsub(failure.Error, "\n", "\n      "))
end
print(string.format("\n%d passed, %d failed across %d spec files", results.Passed, results.Failed, #files))
if results.Failed > 0 then
	process.exit(1)
end
