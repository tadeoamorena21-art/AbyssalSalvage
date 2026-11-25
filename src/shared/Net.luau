--!strict
-- src/shared/Net.luau

local RunService = game:GetService("RunService")
local Config = require(script.Parent.Config)
local Log = require(script.Parent.Log)
local isServer = RunService:IsServer()
local Net = {}

local function fail(message: string): any
	Log.Warn(message)
	error(message, 3)
end

local function getFolder(): Folder
	local existing = script.Parent:FindFirstChild("Network")
	if existing == nil then
		if isServer then
			local folder = Instance.new("Folder")
			folder.Name = "Network"
			folder.Parent = script.Parent
			return folder
		end
		existing = script.Parent:WaitForChild("Network", Config.Network.Timeout)
	end
	if existing == nil then return fail("Timeout esperando Common.Network") end
	if not existing:IsA("Folder") then return fail("Common.Network debe ser Folder") end
	return existing
end

local function getRemote(name: string, className: "RemoteEvent" | "RemoteFunction"): Instance
	assert(#name > 0 and #name <= 64 and string.match(name, "^[%a_][%w_]*$") ~= nil, "Nombre de remoto inválido")
	local folder = getFolder()
	local existing = folder:FindFirstChild(name)
	if existing == nil then
		if isServer then
			local remote: Instance
			if className == "RemoteEvent" then
				remote = Instance.new("RemoteEvent")
			else
				remote = Instance.new("RemoteFunction")
			end
			remote.Name = name
			remote.Parent = folder
			return remote
		end
		existing = folder:WaitForChild(name, Config.Network.Timeout)
	end
	if existing == nil then return fail("Timeout esperando remoto: " .. name) end
	if existing.ClassName ~= className then
		return fail(string.format("%s debe ser %s; encontrado %s", name, className, existing.ClassName))
	end
	return existing
end

-- Cada receptor debe validar permisos, argumentos y frecuencia de sus mensajes.
-- No invocar clientes mediante RemoteFunction desde lógica crítica del servidor.
function Net.GetEvent(name: string): RemoteEvent
	return getRemote(name, "RemoteEvent") :: RemoteEvent
end

function Net.GetFunction(name: string): RemoteFunction
	return getRemote(name, "RemoteFunction") :: RemoteFunction
end

return table.freeze(Net)
