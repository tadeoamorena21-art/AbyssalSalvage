local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SubmarineService = {}

-- Valores por defecto. Si SubmarineConfig define las mismas claves, se usan esas.
local DEFAULTS = {
	MaxSpeed = 20,        -- velocidad máxima hacia adelante (studs/s)
	Acceleration = 4,     -- qué tan rápido responde al input (más bajo = más pesado)
	TurnRate = 1.0,       -- giro en rad/s
	VerticalSpeed = 8,    -- velocidad de subida/bajada (studs/s)
	MaxForce = 1e6,       -- fuerza máxima de los constraints
}

local cfg = {}
for key, value in pairs(DEFAULTS) do
	cfg[key] = value
end

local hull: BasePart? = nil
local seat: VehicleSeat? = nil
local linearVel: LinearVelocity? = nil
local angularVel: AngularVelocity? = nil
local pilot: Player? = nil
local verticalInput = 0
local verticalRemote: RemoteEvent? = nil

local function log(level: string, msg: string)
	print(string.format("[AbyssalSalvage] [%s]: %s", level, msg))
end

local function loadConfig(common: Instance?)
	local mod = common and common:FindFirstChild("SubmarineConfig")
	if not (mod and mod:IsA("ModuleScript")) then
		log("WARN", "SubmarineConfig no encontrado, usando valores por defecto")
		return
	end
	local ok, data = pcall(require, mod)
	if not ok or type(data) ~= "table" then
		log("WARN", "SubmarineConfig no se pudo leer, usando valores por defecto")
		return
	end
	for key in pairs(DEFAULTS) do
		if data[key] ~= nil then
			cfg[key] = data[key]
		end
	end
end

local function getVerticalRemote(): RemoteEvent
	local remote = ReplicatedStorage:FindFirstChild("SubmarineVertical")
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = "SubmarineVertical"
		remote.Parent = ReplicatedStorage
	end
	return remote :: RemoteEvent
end

local function onOccupantChanged()
	local occupant = seat and seat.Occupant
	local player = occupant and Players:GetPlayerFromCharacter(occupant.Parent)

	pilot = player
	verticalInput = 0

	if hull then
		pcall(function()
			hull:SetNetworkOwner(player)
		end)
	end

	if player then
		log("INFO", "Piloto al mando: " .. player.Name)
	end
end

local function setupPhysics(model: Model)
	local h = model.PrimaryPart or model:FindFirstChild("Hull") or model:FindFirstChildWhichIsA("BasePart", true)
	if not h or not h:IsA("BasePart") then
		error("el modelo Submarine no tiene ninguna BasePart")
	end
	model.PrimaryPart = h
	hull = h

	seat = model:FindFirstChildWhichIsA("VehicleSeat", true)

	hull.Anchored = false
	if seat then
		seat.Anchored = false
		seat:GetPropertyChangedSignal("Occupant"):Connect(onOccupantChanged)
	else
		log("WARN", "No hay VehicleSeat dentro de Submarine: nadie podrá pilotar")
	end

	local att = hull:FindFirstChild("SubAttachment")
	if not att then
		att = Instance.new("Attachment")
		att.Name = "SubAttachment"
		att.Parent = hull
	end

	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = cfg.MaxForce
	lv.Parent = hull
	linearVel = lv

	local av = Instance.new("AngularVelocity")
	av.Attachment0 = att
	av.RelativeTo = Enum.ActuatorRelativeTo.World
	av.MaxTorque = cfg.MaxForce
	av.Parent = hull
	angularVel = av
end

function SubmarineService.Init()
	local common = ReplicatedStorage:FindFirstChild("Common") or ReplicatedStorage:WaitForChild("Common", 10)
	loadConfig(common)

	verticalRemote = getVerticalRemote()
	verticalRemote.OnServerEvent:Connect(function(player: Player, value: any)
		if player ~= pilot then
			return
		end
		if type(value) ~= "number" then
			return
		end
		verticalInput = math.clamp(math.round(value), -1, 1)
	end)

	log("INFO", "SubmarineService inicializado")
end

function SubmarineService.Start()
	-- No bloquea el arranque del servidor: el submarino se configura en segundo plano.
	task.spawn(function()
		local model = workspace:FindFirstChild("Submarine") or workspace:WaitForChild("Submarine", 10)
		if not model or not model:IsA("Model") then
			log("WARN", "No hay Workspace.Submarine: el servicio arranca sin submarino")
			return
		end

		local ok, err = pcall(setupPhysics, model)
		if not ok then
			log("ERROR", "Fallo al configurar el submarino: " .. tostring(err))
			return
		end

		RunService.Heartbeat:Connect(function(dt)
			if not hull or not linearVel or not angularVel then
				return
			end

			local throttle, steer = 0, 0
			if seat and pilot then
				throttle = seat.Throttle
				steer = seat.Steer
			end

			local forward = hull.CFrame.LookVector * throttle * cfg.MaxSpeed
			local desired = forward + Vector3.new(0, verticalInput * cfg.VerticalSpeed, 0)

			local alpha = math.clamp(cfg.Acceleration * dt, 0, 1)
			linearVel.VectorVelocity = linearVel.VectorVelocity:Lerp(desired, alpha)
			angularVel.AngularVelocity = Vector3.new(0, -steer * cfg.TurnRate, 0)
		end)

		log("INFO", "Submarino listo")
	end)
end

return SubmarineService


	print("[SubmarineService] Sistema de submarino activo y listo.")
end

return SubmarineService