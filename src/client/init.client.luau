-- src/client/init.client.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local common = ReplicatedStorage:WaitForChild("Common", 10)
assert(common and common:IsA("Folder"), "Falta ReplicatedStorage.Common (Folder)")

local function module(name: string): ModuleScript
	local child = common:WaitForChild(name, 10)
	assert(child and child:IsA("ModuleScript"), "Falta ModuleScript: " .. name)
	return child
end

local Config = require(module("Config"))
local Log = require(module("Log"))
local Net = require(module("Net"))
Log.SetMinLevel(Config.Logging.MinLevel)
local ready = Net.GetEvent("ServerReady")
local status = { ready = false, failure = nil :: string? }

-- Suscribirse antes de solicitar estado evita perder el anuncio inicial.
-- Las solicitudes permiten entrar después de FireAllClients sin quedar bloqueado.
local connection = ready.OnClientEvent:Connect(function(serverState: any, version: any)
	if typeof(serverState) ~= "string" or typeof(version) ~= "string" then return end
	if version ~= Config.Meta.Version then
		status.failure = "Versión incompatible; volver a entrar al servidor"
	elseif serverState == "Failed" then
		status.failure = "El servidor no pudo inicializarse"
	elseif serverState == "Ready" then
		status.ready = true
	end
end)

local deadline = os.clock() + Config.Network.ReadyTimeout
local nextRequest = 0
while not status.ready and status.failure == nil and os.clock() < deadline do
	local now = os.clock()
	if now >= nextRequest then
		ready:FireServer()
		nextRequest = now + Config.Network.HandshakeInterval
	end
	task.wait(0.1)
end
connection:Disconnect()

if status.failure ~= nil then
	Log.Error(status.failure)
	error(status.failure, 0)
end
if not status.ready then
	local message = "Timeout esperando ServerReady; revisar Output del servidor"
	Log.Error(message)
	error(message, 0)
end

script:SetAttribute("ClientReady", true)
Log.Info("Cliente iniciado | versión " .. Config.Meta.Version)
require(script:WaitForChild("SubmarineClient")).Start()