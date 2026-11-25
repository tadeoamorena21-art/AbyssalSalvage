--!strict
-- src/shared/Log.luau

local Config = require(script.Parent.Config)
local Levels = table.freeze({ DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 })
local names: { string } = { "DEBUG", "INFO", "WARN", "ERROR" }
local minimum: number = Config.Logging.MinLevel
local Log = { Levels = Levels }

local function validate(level: number)
	assert(level >= 1 and level <= 4 and level % 1 == 0, "Nivel de registro inválido")
end

function Log.SetMinLevel(level: number)
	validate(level)
	minimum = level
end

function Log.GetMinLevel(): number
	return minimum
end

function Log.Write(level: number, message: string)
	validate(level)
	if level < minimum then return end
	local line = string.format("%s [%s] [%s]: %s", Config.Meta.Tag, names[level], os.date("!%H:%M:%S"), message)
	if level >= Levels.WARN then warn(line) else print(line) end
end

function Log.Debug(message: string) Log.Write(Levels.DEBUG, message) end
function Log.Info(message: string) Log.Write(Levels.INFO, message) end
function Log.Warn(message: string) Log.Write(Levels.WARN, message) end
function Log.Error(message: string) Log.Write(Levels.ERROR, message) end

validate(minimum)
return table.freeze(Log)
