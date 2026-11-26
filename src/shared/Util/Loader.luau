--!strict
--[[
	Service/controller lifecycle loader shared by server and client.

	A module is a table with:
	  Name: string
	  Dependencies: { string }?   -- names of modules that must Init before this one
	  Init: (self, registry) -> ()?  -- synchronous wiring; must not yield
	  Start: (self) -> ()?           -- runs after every Init; may yield (spawned)

	Init order is a topological sort of Dependencies; cycles and missing dependencies are rejected
	at boot rather than producing undefined behaviour at runtime.
]]

export type Module = {
	Name: string,
	Dependencies: { string }?,
	Init: ((self: any, registry: Registry) -> ())?,
	Start: ((self: any) -> ())?,
	[any]: any,
}

export type Registry = { [string]: any }

export type Options = {
	-- Start functions are spawned by default. Tests pass a synchronous runner.
	Spawn: ((fn: () -> ()) -> ())?,
	OnStartError: ((name: string, err: any) -> ())?,
}

local Loader = {}

function Loader.Sort(modules: { Module }): { Module }
	local byName: { [string]: Module } = {}
	for _, module in modules do
		assert(type(module.Name) == "string" and module.Name ~= "", "module missing Name")
		assert(byName[module.Name] == nil, `duplicate module name '{module.Name}'`)
		byName[module.Name] = module
	end

	local ordered: { Module } = {}
	local state: { [string]: "visiting" | "done" } = {}

	local function visit(module: Module, path: { string })
		local current = state[module.Name]
		if current == "done" then
			return
		elseif current == "visiting" then
			table.insert(path, module.Name)
			error(`dependency cycle: {table.concat(path, " -> ")}`)
		end
		state[module.Name] = "visiting"
		table.insert(path, module.Name)
		for _, dependencyName in module.Dependencies or {} do
			local dependency = byName[dependencyName]
			if dependency == nil then
				error(`'{module.Name}' depends on unknown module '{dependencyName}'`)
			end
			visit(dependency, path)
		end
		table.remove(path)
		state[module.Name] = "done"
		table.insert(ordered, module)
	end

	-- Visit in name order so boot order is deterministic regardless of discovery order.
	local names = {}
	for name in byName do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		visit(byName[name], {})
	end
	return ordered
end

function Loader.Boot(modules: { Module }, options: Options?): Registry
	local spawn = (options and options.Spawn) or function(fn)
		task.spawn(fn)
	end
	local onStartError = (options and options.OnStartError)
		or function(name, err)
			warn(`[Loader] {name}.Start failed: {err}`)
		end

	local ordered = Loader.Sort(modules)
	local registry: Registry = {}
	for _, module in ordered do
		registry[module.Name] = module
	end

	for _, module in ordered do
		if module.Init then
			-- Init failures are fatal: a half-wired service graph is worse than a failed boot.
			local ok, err = pcall(module.Init, module, registry)
			if not ok then
				error(`{module.Name}.Init failed: {err}`, 0)
			end
		end
	end

	for _, module in ordered do
		local start = module.Start
		if start then
			spawn(function()
				local ok, err = pcall(start, module)
				if not ok then
					onStartError(module.Name, err)
				end
			end)
		end
	end

	return registry
end

-- Requires every ModuleScript child of `folder` (Roblox runtime only).
function Loader.RequireChildren(folder: Instance): { Module }
	local modules = {}
	for _, child in folder:GetChildren() do
		if child:IsA("ModuleScript") then
			table.insert(modules, (require :: any)(child))
		end
	end
	return modules
end

return Loader
