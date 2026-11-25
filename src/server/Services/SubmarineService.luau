-- Destino: src/server/Services/SubmarineService.luau
-- INSTALACIÓN: detener Play, reemplazar TODO el archivo anterior por este,
-- guardar en VS Code, dejar sincronizar Rojo y volver a pulsar Play.
-- No hace falta modificar Net, SubmarineConfig ni SubmarineClient del commit original.
-- Debe existir Workspace.Submarine con casco y VehicleSeat.
-- Para este prototipo RÍGIDO, une las piezas del modelo al casco y las desancla.
-- No incluir puertas articuladas ni objetos independientes dentro del modelo todavía.
-- Los ajustes automáticos del modelo ocurren durante Play, no se guardan en edición.
-- Prueba PC: W/S avanzar/retroceder; A/D girar; Espacio subir; C bajar; X salir.
-- Output esperado: M03: submarino listo. Si falta el modelo, informa M03 deshabilitado.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Service = {}
local Config, Net, Log, common, remote
local model, hull, seat, linear, angular
local initialized, started = false, false
local connections, created = {}, {}
local pilot
local throttle, steer, vertical = 0, 0, 0
local lastInput, bucketTime, tokens = 0, 0, 0
local speed, climb, turn = 0, 0, 0

local function resetInput()
    throttle, steer, vertical = 0, 0, 0
    lastInput = 0
end

local function track(connection)
    table.insert(connections, connection)
    return connection
end

local function make(className, name, parent)
    local item = Instance.new(className)
    item.Name = name
    table.insert(created, item)
    item.Parent = parent
    return item
end

local function cleanup()
    for _, connection in connections do connection:Disconnect() end
    table.clear(connections)
    for i = #created, 1, -1 do created[i]:Destroy() end
    table.clear(created)
    pilot = nil
    resetInput()
    speed, climb, turn = 0, 0, 0
end

local function serverOwnership()
    local canSet, reason = hull:CanSetNetworkOwnership()
    if not canSet then error("M03: no se puede controlar la física: " .. tostring(reason)) end
    hull:SetNetworkOwner(nil)
end

local function occupantChanged()
    local occupant = seat.Occupant
    pilot = occupant and occupant.Parent and Players:GetPlayerFromCharacter(occupant.Parent) or nil
    resetInput()
    tokens = Config.PacketBurst
    bucketTime = os.clock()
    -- La física permanece en servidor, incluso con piloto sentado.
    local ok, message = pcall(serverOwnership)
    if not ok then
        pilot = nil
        Log.Warn(tostring(message))
    end
end

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function receive(player, forwardInput, turnInput, depthInput)
    if player ~= pilot or not seat or not seat.Parent then return end
    local occupant = seat.Occupant
    if not occupant or occupant.Health <= 0 or occupant.Parent ~= player.Character then return end
    local now = os.clock()
    tokens = math.min(Config.PacketBurst, tokens + (now - bucketTime) * Config.PacketsPerSecond)
    bucketTime = now
    if tokens < 1 then return end
    tokens -= 1
    if not finite(forwardInput) or not finite(turnInput) or not finite(depthInput) then return end
    throttle = math.clamp(forwardInput, -1, 1)
    steer = math.clamp(turnInput, -1, 1)
    vertical = math.clamp(depthInput, -1, 1)
    lastInput = now
end

local function approach(current, target, amount)
    return current + math.clamp(target - current, -amount, amount)
end

local function step(dt)
    if not model:IsDescendantOf(workspace) or not hull:IsDescendantOf(model)
        or not seat:IsDescendantOf(model) or not linear.Parent or not angular.Parent then
        cleanup()
        common:SetAttribute("SubmarineState", "Unavailable")
        Log.Warn("M03 detenido: se retiró el modelo o una pieza necesaria. Reiniciar Play tras corregirlo.")
        return
    end
    local occupant = seat.Occupant
    if not pilot or not occupant or occupant.Health <= 0
        or occupant.Parent ~= pilot.Character or os.clock() - lastInput > Config.InputTimeout then
        resetInput()
    end
    dt = math.min(dt, 0.1)
    local desiredSpeed = throttle * (throttle >= 0 and Config.ForwardSpeed or Config.ReverseSpeed)
    local braking = throttle == 0 or speed * desiredSpeed < 0 or math.abs(desiredSpeed) < math.abs(speed)
    speed = approach(speed, desiredSpeed, (braking and Config.Braking or Config.Acceleration) * dt)
    climb = approach(climb, vertical * Config.VerticalSpeed,
        (vertical == 0 and Config.Braking or Config.Acceleration) * dt)
    turn += (-steer * Config.TurnSpeed - turn) * (1 - math.exp(-Config.OrientationResponsiveness * dt))
    -- Frente definido por PilotSeat: evita depender de la orientación visual de Hull.
    local look = seat.CFrame.LookVector
    local forward = Vector3.new(look.X, 0, look.Z)
    forward = forward.Magnitude > 0.001 and forward.Unit or Vector3.new(0, 0, -1)
    linear.VectorVelocity = forward * speed + Vector3.new(0, climb, 0)
    -- Recuperación de inclinación sin competir con otro constraint de orientación.
    local up = seat.CFrame.UpVector
    local axis = up:Cross(Vector3.yAxis)
    local correction = Vector3.zero
    if axis.Magnitude > 0.0001 then
        correction = axis.Unit * math.acos(math.clamp(up.Y, -1, 1)) * Config.OrientationResponsiveness
    elseif up.Y < 0 then
        correction = forward * Config.MaxAngularVelocity
    end
    local target = correction + Vector3.new(0, turn, 0)
    if target.Magnitude > Config.MaxAngularVelocity then
        target = target.Unit * Config.MaxAngularVelocity
    end
    angular.AngularVelocity = target
    local mass = hull.AssemblyMass
    if finite(mass) and mass > 0 then
        linear.MaxForce = mass * math.max(Config.ForcePerMass, workspace.Gravity + Config.Acceleration)
        angular.MaxTorque = mass * Config.TorquePerMass
    end
end

local function setup()
    model = workspace:FindFirstChild(Config.ModelName)
    if not model or not model:IsA("Model") then
        error("Falta Workspace." .. Config.ModelName .. " (Model), con casco y VehicleSeat.")
    end
    hull = model:FindFirstChild("Hull", true)
    if not hull or not hull:IsA("BasePart") then
        hull = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
    end
    if not hull then error("El modelo Submarine no contiene ninguna BasePart.") end
    seat = model:FindFirstChild(Config.SeatName, true)
    if not seat then
        local candidates = {}
        for _, item in model:GetDescendants() do
            if item:IsA("VehicleSeat") then table.insert(candidates, item) end
        end
        if #candidates == 1 then
            seat = candidates[1]
            seat.Name = Config.SeatName
            Log.Info("M03: asiento renombrado automáticamente a " .. Config.SeatName)
        end
    end
    if not seat or not seat:IsA("VehicleSeat") then
        error("Submarine necesita un VehicleSeat llamado " .. Config.SeatName .. ".")
    end
    -- Solo se configura tras comprobar las piezas esenciales.
    model.PrimaryPart = hull
    local parts = {}
    for _, item in model:GetDescendants() do
        if item:IsA("BasePart") then table.insert(parts, item) end
    end
    local connected = { [hull] = true }
    for _, part in hull:GetConnectedParts(true) do connected[part] = true end
    for _, part in parts do
        if not connected[part] then
            local weld = make("WeldConstraint", "M03RigidWeld", hull)
            weld.Part0, weld.Part1 = hull, part
        end
        part.Anchored = false
    end
    seat.Disabled = false
    seat.MaxSpeed, seat.Torque, seat.TurnSpeed = 0, 0, 0
    local attachment = make("Attachment", "M03Attachment", hull)
    linear = make("LinearVelocity", "M03LinearVelocity", hull)
    linear.Attachment0 = attachment
    linear.RelativeTo = Enum.ActuatorRelativeTo.World
    linear.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
    linear.ForceLimitsEnabled = true
    linear.ForceLimitMode = Enum.ForceLimitMode.Magnitude
    linear.MaxForce = hull.AssemblyMass * math.max(Config.ForcePerMass, workspace.Gravity + Config.Acceleration)
    linear.VectorVelocity = Vector3.zero
    angular = make("AngularVelocity", "M03AngularVelocity", hull)
    angular.Attachment0 = attachment
    angular.RelativeTo = Enum.ActuatorRelativeTo.World
    angular.MaxTorque = hull.AssemblyMass * Config.TorquePerMass
    angular.AngularVelocity = Vector3.zero
    serverOwnership()
    occupantChanged()
    track(seat:GetPropertyChangedSignal("Occupant"):Connect(occupantChanged))
    track(remote.OnServerEvent:Connect(receive))
    track(Players.PlayerRemoving:Connect(function(player)
        if player == pilot then pilot = nil; resetInput() end
    end))
    track(RunService.Heartbeat:Connect(step))
end

function Service.Init()
    if initialized then return end
    common = ReplicatedStorage:WaitForChild("Common", 10)
    assert(common, "M03: falta ReplicatedStorage.Common")
    local function load(name)
        local item = common:WaitForChild(name, 10)
        assert(item and item:IsA("ModuleScript"), "M03: falta Common." .. name)
        return require(item)
    end
    Config, Net, Log = load("SubmarineConfig"), load("Net"), load("Log")
    for _, key in { "ForwardSpeed", "ReverseSpeed", "VerticalSpeed", "TurnSpeed", "Acceleration",
        "Braking", "OrientationResponsiveness", "MaxAngularVelocity", "ForcePerMass", "TorquePerMass",
        "InputTimeout", "PacketBurst", "PacketsPerSecond" } do
        assert(finite(Config[key]) and Config[key] > 0, "M03: configuración inválida: " .. key)
    end
    remote = Net.GetEvent(Config.RemoteName)
    common:SetAttribute("SubmarineState", "Starting")
    initialized = true
end

function Service.Start()
    if started then return end
    if not initialized then Service.Init() end
    -- Síncrono: el cargador no anuncia Ready antes de terminar este intento.
    local ok, message = xpcall(setup, function(err) return debug.traceback(tostring(err), 2) end)
    if not ok then
        cleanup()
        common:SetAttribute("SubmarineState", "Unavailable")
        Log.Warn("M03 deshabilitado; el resto del servidor puede arrancar. " .. tostring(message))
        return
    end
    started = true
    common:SetAttribute("SubmarineState", "Ready")
    Log.Info("M03: submarino listo | control " .. Config.RemoteName .. " | física en servidor")
end

function Service.Destroy()
    cleanup()
    started, initialized = false, false
    if common then common:SetAttribute("SubmarineState", "Stopped") end
end

return Service
