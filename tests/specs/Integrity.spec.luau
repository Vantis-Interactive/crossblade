--!nocheck
--[[
	Static integrity checks over ALL source files, including Roblox-only services/controllers that
	cannot execute under Lune. These catch the classes of bug most likely to break a live server:
	bad require paths, undeclared service dependencies (nil at runtime), dependency cycles, and remote
	names that do not exist in the network contracts.
]]

local fs = require("@lune/fs")
local Loader = Runtime:Get("ReplicatedStorage/Shared/Util/Loader")
local Contracts = Runtime:Get("ReplicatedStorage/Shared/Net/Contracts")

local root = Runtime.Root

local function collect(directory, out)
	for _, entry in fs.readDir(directory) do
		local path = directory .. "/" .. entry
		if fs.isDir(path) then
			collect(path, out)
		elseif string.match(entry, "%.luau$") then
			table.insert(out, path)
		end
	end
	return out
end

local files = collect(root .. "/src", {})

-- Virtual node for a source file (mirrors default.project.json).
local function nodeFor(path)
	local relative = string.sub(path, #root + 2)
	local service, folder, rest
	if string.sub(relative, 1, 11) == "src/shared/" then
		service, folder, rest = "ReplicatedStorage", "Shared", string.sub(relative, 12)
	elseif string.sub(relative, 1, 11) == "src/server/" then
		service, folder, rest = "ServerScriptService", "Server", string.sub(relative, 12)
	elseif string.sub(relative, 1, 11) == "src/client/" then
		service, folder, rest = "StarterPlayer", "StarterPlayerScripts/Client", string.sub(relative, 12)
	else
		return nil
	end
	local node = Runtime.Services[service]
	for _, segment in string.split(folder, "/") do
		node = node and node:FindFirstChild(segment)
	end
	local parts = string.split(rest, "/")
	for index, part in parts do
		local name = string.gsub(
			string.gsub(string.gsub(part, "%.server%.luau$", ""), "%.client%.luau$", ""),
			"%.luau$",
			""
		)
		if name == "init" and index == #parts then
			return node
		end
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function resolve(start, chain)
	local node = start
	for _, step in chain do
		if node == nil then
			return nil
		end
		if step == "Parent" then
			node = rawget(node, "Parent")
		else
			node = node:FindFirstChild(step)
		end
	end
	return node
end

describe("Source integrity", function()
	it("every file compiles with the Luau compiler", function()
		local failures = {}
		local compiler = Runtime.Compile
		for _, path in files do
			local ok, err = compiler(fs.readFile(path))
			if not ok then
				table.insert(failures, path .. ": " .. tostring(err))
			end
		end
		if #failures > 0 then
			error(table.concat(failures, "\n"))
		end
		expect(#files).toBeGreaterThan(40)
	end)

	it("every script-relative and ReplicatedStorage require resolves to a ModuleScript", function()
		local failures = {}
		for _, path in files do
			local source = fs.readFile(path)
			local node = nodeFor(path)
			for expression in string.gmatch(source, "require%(([%w%.]+)%)") do
				local parts = string.split(expression, ".")
				local target = nil
				local checkable = true
				if parts[1] == "script" then
					assert(node, `no virtual node for {path}`)
					table.remove(parts, 1)
					target = resolve(node, parts)
				elseif parts[1] == "ReplicatedStorage" then
					table.remove(parts, 1)
					target = resolve(Runtime.Services.ReplicatedStorage, parts)
				else
					checkable = false
				end
				if checkable then
					if target == nil or rawget(target, "ClassName") ~= "ModuleScript" then
						table.insert(failures, `{path}: require({expression}) does not resolve`)
					end
				end
			end
		end
		if #failures > 0 then
			error(table.concat(failures, "\n"))
		end
	end)

	local function moduleGraph(directory)
		local modules = {}
		for _, path in collect(root .. "/" .. directory, {}) do
			local source = fs.readFile(path)
			local name = string.match(source, '\n%s*Name = "(%w+)"')
			if name then
				local deps = {}
				local block = string.match(source, "Dependencies = (%b{})")
				if block then
					for dep in string.gmatch(block, '"(%w+)"') do
						table.insert(deps, dep)
					end
				end
				local used = {}
				for ref in string.gmatch(source, "registry%.(%w+)") do
					used[ref] = true
				end
				local roles = nil
				local rolesBlock = string.match(source, "\n%s*Roles = (%b{})")
				if rolesBlock then
					roles = {}
					for role in string.gmatch(rolesBlock, '"(%w+)"') do
						table.insert(roles, role)
					end
				end
				table.insert(
					modules,
					{ Name = name, Dependencies = deps, Used = used, Path = path, Roles = roles }
				)
			end
		end
		return modules
	end

	local function checkGraph(modules, extra)
		local names = {}
		for _, module in modules do
			names[module.Name] = true
		end
		for _, name in extra or {} do
			table.insert(modules, { Name = name, Dependencies = {}, Used = {} })
			names[name] = true
		end
		local failures = {}
		for _, module in modules do
			for ref in module.Used do
				if not table.find(module.Dependencies, ref) then
					table.insert(
						failures,
						`{module.Name} uses registry.{ref} without declaring it in Dependencies`
					)
				end
			end
		end
		if #failures > 0 then
			error(table.concat(failures, "\n"))
		end
		-- Every place role must boot: the role's module subset has no cycles or missing dependencies.
		for _, role in { "Hub", "Arena" } do
			local subset = {}
			for _, module in modules do
				if module.Roles == nil or table.find(module.Roles, role) then
					table.insert(subset, module)
				end
			end
			local ok, err = pcall(Loader.Sort, subset)
			if not ok then
				error(`role {role}: {err}`)
			end
		end
	end

	it("server services declare every registry dependency they use, with no cycles", function()
		local modules = moduleGraph("src/server/Services")
		expect(#modules).toBeGreaterThan(10)
		checkGraph(modules, { "Net" })
	end)

	it("client controllers declare every registry dependency they use, with no cycles", function()
		local modules = moduleGraph("src/client/Controllers")
		expect(#modules).toBeGreaterThan(8)
		checkGraph(modules)
	end)

	it("every remote referenced in code exists in the contracts with the right direction", function()
		local failures = {}
		local patterns = {
			{ 'net%.OnEvent%("(%w+)"', Contracts.ClientToServer },
			{ 'net%.OnInvoke%("(%w+)"', Contracts.ClientToServer },
			{ 'net%.Fire%("(%w+)"', Contracts.ServerToClient },
			{ 'net%.FireAll%("(%w+)"', Contracts.ServerToClient },
			{ 'net%.FireAllExcept%("(%w+)"', Contracts.ServerToClient },
			{ 'Net%.On%("(%w+)"', Contracts.ServerToClient },
			{ 'Net%.Fire%("(%w+)"', Contracts.ClientToServer },
			{ 'Net%.Invoke%("(%w+)"', Contracts.ClientToServer },
		}
		local used = {}
		for _, path in files do
			local source = fs.readFile(path)
			for _, pattern in patterns do
				for name in string.gmatch(source, pattern[1]) do
					used[name] = true
					if pattern[2][name] == nil then
						table.insert(
							failures,
							`{path}: remote {name} missing from contracts for this direction`
						)
					end
				end
			end
		end
		if #failures > 0 then
			error(table.concat(failures, "\n"))
		end
		-- No dead contracts: every declared remote is used somewhere.
		for name in Contracts.ClientToServer do
			expect(used[name]).toBe(true)
		end
		for name in Contracts.ServerToClient do
			expect(used[name]).toBe(true)
		end
	end)
end)

describe("Signal wiring", function()
	local fs = require("@lune/fs")
	local function collect(directory, out)
		for _, entry in fs.readDir(directory) do
			local path = directory .. "/" .. entry
			if fs.isDir(path) then
				collect(path, out)
			elseif string.match(entry, "%.luau$") then
				table.insert(out, path)
			end
		end
		return out
	end
	local files = collect(Runtime.Root .. "/src", {})

	-- module name -> set of declared Signal fields
	local declared = {}
	local sources = {}
	for _, path in files do
		local source = fs.readFile(path)
		sources[path] = source
		local name = string.match(source, '\n%s*Name = "(%w+)"')
		if name then
			declared[name] = declared[name] or {}
			for field in string.gmatch(source, "\n%s*(%w+) = Signal%.new%(%)") do
				declared[name][field] = true
			end
		end
	end

	it("every Module.Signal:Fire targets a signal the module declares", function()
		local failures = {}
		for path, source in sources do
			local name = string.match(source, '\n%s*Name = "(%w+)"')
			if name then
				for field in string.gmatch(source, name .. "%.(%w+):Fire%(") do
					if not declared[name][field] then
						table.insert(
							failures,
							`{path}: {name}.{field}:Fire but {field} is not declared as Signal.new()`
						)
					end
				end
			end
		end
		if #failures > 0 then
			error(table.concat(failures, "\n"))
		end
	end)

	it("every registry.Service.Signal:Connect targets a declared signal", function()
		local failures = {}
		for path, source in sources do
			for service, field in string.gmatch(source, "registry%.(%w+)%.(%w+):Connect%(") do
				if declared[service] == nil or not declared[service][field] then
					table.insert(
						failures,
						`{path}: registry.{service}.{field}:Connect has no matching Signal.new()`
					)
				end
			end
			-- Locals bound from the registry, e.g. `weapons = registry.WeaponService` then `weapons.X:Connect`.
			for variable, service in string.gmatch(source, "\n%s*(%w+) = registry%.(%w+)\n") do
				for field in string.gmatch(source, "\n%s*" .. variable .. "%.(%u%w+):Connect%(") do
					if declared[service] == nil or not declared[service][field] then
						table.insert(
							failures,
							`{path}: {variable}.{field}:Connect ({service}) has no matching Signal.new()`
						)
					end
				end
			end
		end
		if #failures > 0 then
			error(table.concat(failures, "\n"))
		end
	end)
end)
