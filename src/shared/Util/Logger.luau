--!strict
--[[
	Structured logger. Every log line is tagged with a scope and optional context table so that
	output is searchable in the developer console and forwardable to analytics later.
	Errors are never swallowed silently: use Logger:Error for anything unexpected.
]]

export type Level = "Debug" | "Info" | "Warn" | "Error"
export type Sink = (level: Level, scope: string, message: string, context: { [string]: any }?) -> ()

local LEVEL_RANK: { [Level]: number } = { Debug = 1, Info = 2, Warn = 3, Error = 4 }

local Logger = {}
Logger.__index = Logger

export type Logger = typeof(setmetatable({} :: { Scope: string }, Logger))

local minimumLevel: Level = "Info"
local sinks: { Sink } = {}

local function formatContext(context: { [string]: any }?): string
	if context == nil then
		return ""
	end
	local parts = {}
	for key, value in context do
		table.insert(parts, `{key}={tostring(value)}`)
	end
	table.sort(parts)
	return " {" .. table.concat(parts, ", ") .. "}"
end

local function defaultSink(level: Level, scope: string, message: string, context: { [string]: any }?)
	local line = `[{scope}] {message}{formatContext(context)}`
	if level == "Error" or level == "Warn" then
		warn(line)
	else
		print(line)
	end
end

function Logger.new(scope: string): Logger
	return setmetatable({ Scope = scope }, Logger)
end

function Logger.SetMinimumLevel(level: Level)
	minimumLevel = level
end

-- Replaces the default sink set. Used by tests to capture output and by AnalyticsService later.
function Logger.SetSinks(newSinks: { Sink }?)
	sinks = newSinks or {}
end

local function emit(self: Logger, level: Level, message: string, context: { [string]: any }?)
	if LEVEL_RANK[level] < LEVEL_RANK[minimumLevel] then
		return
	end
	if #sinks == 0 then
		defaultSink(level, self.Scope, message, context)
		return
	end
	for _, sink in sinks do
		local ok, err = pcall(sink, level, self.Scope, message, context)
		if not ok then
			warn(`[Logger] sink failed: {err}`)
		end
	end
end

function Logger.Debug(self: Logger, message: string, context: { [string]: any }?)
	emit(self, "Debug", message, context)
end

function Logger.Info(self: Logger, message: string, context: { [string]: any }?)
	emit(self, "Info", message, context)
end

function Logger.Warn(self: Logger, message: string, context: { [string]: any }?)
	emit(self, "Warn", message, context)
end

function Logger.Error(self: Logger, message: string, context: { [string]: any }?)
	emit(self, "Error", message, context)
end

return Logger
