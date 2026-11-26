--!nocheck
--[[
	Test runtime: loads repository modules under Lune with Roblox-compatible `script`, `require`,
	`game:GetService`, datatypes (Vector3, CFrame, ...) and `task`.

	The virtual instance tree mirrors default.project.json, so `require(script.Parent.X)` and
	`game:GetService("ReplicatedStorage").Shared.X` resolve exactly as they do inside Roblox.
	Only services mapped to source folders exist; any other GetService call fails loudly, which keeps
	unit-tested modules free of hidden Roblox engine dependencies.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Runtime = {}

-- Service -> { "Nested/Folder/Path" = source directory }, mirroring default.project.json.
local MAPPING = {
	ReplicatedStorage = { Shared = "src/shared" },
	ServerScriptService = { Server = "src/server" },
	StarterPlayer = { ["StarterPlayerScripts/Client"] = "src/client" },
}

local Node = {}

local function childOf(node, name)
	return rawget(node, "_children")[name]
end

Node.__index = function(node, key)
	local method = Node[key]
	if method ~= nil and key ~= "__index" then
		return method
	end
	local child = childOf(node, key)
	if child ~= nil then
		return child
	end
	error(`{key} is not a valid member of {rawget(node, "Name")}`, 2)
end

function Node.FindFirstChild(node, name)
	return childOf(node, name)
end

function Node.WaitForChild(node, name)
	local child = childOf(node, name)
	assert(child, `WaitForChild would hang: {name} under {rawget(node, "Name")}`)
	return child
end

function Node.GetChildren(node)
	local list = {}
	for _, child in rawget(node, "_children") do
		table.insert(list, child)
	end
	return list
end

function Node.IsA(node, className)
	return rawget(node, "ClassName") == className
end

function Node.GetFullName(node)
	local parent = rawget(node, "Parent")
	if parent == nil then
		return rawget(node, "Name")
	end
	return parent:GetFullName() .. "." .. rawget(node, "Name")
end

local function newNode(name, className, parent, path)
	local node = setmetatable(
		{ Name = name, ClassName = className, Parent = parent, _children = {}, _path = path },
		Node
	)
	if parent then
		rawget(parent, "_children")[name] = node
	end
	return node
end

local function classify(fileName)
	local base = fileName:match("^(.*)%.server%.luau$")
	if base then
		return base, "Script"
	end
	base = fileName:match("^(.*)%.client%.luau$")
	if base then
		return base, "LocalScript"
	end
	base = fileName:match("^(.*)%.luau$")
	if base then
		return base, "ModuleScript"
	end
	return nil, nil
end

local function buildDirectory(node, directory)
	for _, entry in fs.readDir(directory) do
		local path = directory .. "/" .. entry
		if fs.isDir(path) then
			local init = path .. "/init.luau"
			local child = newNode(
				entry,
				if fs.isFile(init) then "ModuleScript" else "Folder",
				node,
				if fs.isFile(init) then init else nil
			)
			buildDirectory(child, path)
		elseif entry ~= "init.luau" then
			local name, className = classify(entry)
			if name then
				newNode(name, className, node, path)
			end
		end
	end
end

function Runtime.new(root)
	local self = { Root = root, Cache = {}, Services = {} }
	self.Compile = function(source)
		return pcall(luau.compile, source)
	end
	local game = newNode("game", "DataModel", nil, nil)
	for serviceName, folders in MAPPING do
		local service = newNode(serviceName, serviceName, game, nil)
		for folderPath, relative in folders do
			local directory = root .. "/" .. relative
			local init = directory .. "/init.luau"
			local segments = string.split(folderPath, "/")
			local parent = service
			for index = 1, #segments - 1 do
				parent = childOf(parent, segments[index])
					or newNode(segments[index], segments[index], parent, nil)
			end
			local folderName = segments[#segments]
			local folder = newNode(
				folderName,
				if fs.isFile(init) then "ModuleScript" else "Folder",
				parent,
				if fs.isFile(init) then init else nil
			)
			buildDirectory(folder, directory)
		end
		self.Services[serviceName] = service
	end
	self.Game = setmetatable({}, {
		__index = function(_, key)
			if key == "GetService" then
				return function(_, name)
					local service = self.Services[name]
					if service == nil then
						error(`GetService("{name}") is not available in unit tests (module is not pure)`, 2)
					end
					return service
				end
			end
			error(`game.{key} is not available in unit tests`, 2)
		end,
	})
	return setmetatable(self, { __index = Runtime })
end

function Runtime.Environment(self, scriptNode)
	return {
		script = scriptNode,
		game = self.Game,
		require = function(target)
			return self:Require(target)
		end,
		-- Roblox datatypes
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Enum = roblox.Enum,
		NumberRange = roblox.NumberRange,
		task = task,
		-- Standard library
		print = print,
		warn = warn,
		error = error,
		assert = assert,
		pcall = pcall,
		xpcall = xpcall,
		type = type,
		typeof = typeof,
		tostring = tostring,
		tonumber = tonumber,
		select = select,
		next = next,
		pairs = pairs,
		ipairs = ipairs,
		rawget = rawget,
		rawset = rawset,
		rawequal = rawequal,
		rawlen = rawlen,
		setmetatable = setmetatable,
		getmetatable = getmetatable,
		unpack = unpack,
		math = math,
		string = string,
		table = table,
		os = os,
		bit32 = bit32,
		utf8 = utf8,
		buffer = buffer,
		coroutine = coroutine,
		debug = debug,
	}
end

function Runtime.Require(self, node)
	if type(node) ~= "table" or getmetatable(node) ~= Node then
		error("require expects a virtual ModuleScript (got " .. typeof(node) .. ")", 2)
	end
	local cached = self.Cache[node]
	if cached ~= nil then
		return cached.Value
	end
	if rawget(node, "ClassName") ~= "ModuleScript" then
		error(`{node:GetFullName()} is not a ModuleScript`, 2)
	end
	local path = rawget(node, "_path")
	local source = fs.readFile(path)
	local fn = luau.load(source, { debugName = path, environment = self:Environment(node) })
	local value = fn()
	if value == nil then
		error(`module {path} returned nil`)
	end
	self.Cache[node] = { Value = value }
	return value
end

-- Resolve "ReplicatedStorage/Shared/Combat/Hitbox" to a module value.
function Runtime.Get(self, path)
	local parts = string.split(path, "/")
	local node = self.Services[parts[1]]
	assert(node, `unknown service {parts[1]}`)
	for index = 2, #parts do
		node = rawget(node, "_children")[parts[index]]
		assert(node, `unknown path {path}`)
	end
	return self:Require(node)
end

return Runtime
