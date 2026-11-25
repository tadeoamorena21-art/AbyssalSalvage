-- src/server/init.server.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local common = ReplicatedStorage:WaitForChild("Common", 10)
assert(common and common:IsA("Folder"), "Falta ReplicatedStorage.Common (Folder)")

local function module(parent: Instance, name: string): ModuleScript
	local child = parent:WaitForChild(name, 10)
	assert(child and child:IsA("ModuleScript"), "Falta ModuleScript: " .. name)
	return child
end

local Config = require(module(common, "Config"))
local Log = require(module(common, "Log"))
local Net = require(module(common, "Net"))
Log.SetMinLevel(Config.Logging.MinLevel)
assert(common:GetAttribute("ServerState") == nil, "Bootstrap duplicado")
common:SetAttribute("ServerState", "Starting")
local ready = Net.GetEvent("ServerReady")
local state = "Starting"
local lastRequest: { [Player]: number } = {}

-- No se confía en datos enviados por el cliente. El remoto solo informa estado.
ready.OnServerEvent:Connect(function(player: Player)
	local now = os.clock()
	local previous = lastRequest[player]
	if previous and now - previous < Config.Network.HandshakeInterval then return end
	lastRequest[player] = now
	ready:FireClient(player, state, Config.Meta.Version)
end)
Players.PlayerRemoving:Connect(function(player: Player) lastRequest[player] = nil end)

local success, result = xpcall(function(): number
	-- init.server.luau convierte src/server en Script; sus módulos son hijos.
	local services = script:FindFirstChild("Services")
	assert(services and services:IsA("Folder"), "Falta Server.Services (Folder); comprobar Rojo")
	local Loader = require(module(script, "ServerLoader"))
	return Loader.Run(services)
end, function(message: any): string
	return debug.traceback(tostring(message), 2)
end)

if not success then
	state = "Failed"
	common:SetAttribute("ServerState", state)
	ready:FireAllClients(state, Config.Meta.Version)
	Log.Error("Arranque del servidor fallido: " .. tostring(result))
	error("M01: servidor no disponible", 0)
end

state = "Ready"
common:SetAttribute("ServerState", state)
ready:FireAllClients(state, Config.Meta.Version)
Log.Info(string.format("Servidor listo | versión %s | servicios %d", Config.Meta.Version, result))
