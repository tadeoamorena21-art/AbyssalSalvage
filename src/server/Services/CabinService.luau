-- Destino: src/server/Services/CabinService.luau (ModuleScript)
-- Prototipo P1. Conserva SubmarineService.luau corregido.
-- Construye una cabina abierta durante Play; no modifica el modelo guardado.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Service = { LoadPriority = 100 }
local model, hull, seat, floor, zone, folder, exitRemote
local connections, cooldown = {}, {}
local initialized, started = false, false
local savedSeatTouch
local function connect(signal, callback)
    table.insert(connections, signal:Connect(callback))
end
local function inside(part, position, margin)
    local p = part.CFrame:PointToObjectSpace(position)
    local h = part.Size / 2 + Vector3.one * (margin or 0)
    return math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y and math.abs(p.Z) <= h.Z
end
local function part(name, size, cf, color, solid, invisible)
    local p = Instance.new("Part")
    p.Name, p.Size, p.CFrame = name, size, cf
    p.Color, p.Material = color, Enum.Material.Metal
    p.Anchored, p.Massless = false, true
    p.CanCollide, p.CanTouch, p.CanQuery = solid, false, solid
    p.Transparency = invisible and 1 or 0
    -- Fricción firme para caminar sin patinar sobre el piso.
    p.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.85, 0, 1, 1)
    p.Parent = folder
    local weld = Instance.new("WeldConstraint")
    weld.Part0, weld.Part1, weld.Parent = hull, p, p
    return p
end
local function prompt(parent, name, text, callback)
    local p = Instance.new("ProximityPrompt")
    p.Name, p.ActionText, p.ObjectText = name, text, "Submarino"
    p.KeyboardKeyCode = Enum.KeyCode.E
    p.GamepadKeyCode = Enum.KeyCode.ButtonX
    p.HoldDuration, p.MaxActivationDistance = 0.35, 10
    p.RequiresLineOfSight = false
    p.Parent = parent
    connect(p.Triggered, function(player)
        if player:GetAttribute("CrewLocked") ~= true then return end
        local char = player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not root or not hum or hum.Health <= 0 or hum.SeatPart then return end
        if (root.Position - parent.Position).Magnitude > 12 then return end
        local now = os.clock()
        if now < (cooldown[player] or 0) then return end
        cooldown[player] = now + 1
        callback(player, char, root, hum)
    end)
end
local function transfer(player, char, root, destination, aboard)
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {char, zone}
    params.RespectCanCollide = true
    -- Rechaza destinos ocupados: evita atravesar rocas u otros jugadores.
    for _, hit in workspace:GetPartBoundsInBox(destination, Vector3.new(4, 5, 4), params) do
        if hit.CanCollide then return end
    end
    char:PivotTo(destination * root.CFrame:ToObjectSpace(char:GetPivot()))
    root.AssemblyLinearVelocity = hull:GetVelocityAtPosition(root.Position)
    root.AssemblyAngularVelocity = Vector3.zero
    player:SetAttribute("InSubmarine", aboard)
end
function Service.Init()
    if initialized then return end
    local common = RS:WaitForChild("Common", 10)
    assert(common, "M03 cabina: falta Common")
    local Net = require(common:WaitForChild("Net"))
    exitRemote = Net.GetEvent("SubmarineExit_v1")
    local config = require(common:WaitForChild("SubmarineConfig"))
    model = workspace:FindFirstChild(config.ModelName)
    hull = model and (model:FindFirstChild("Hull", true) or model.PrimaryPart)
    seat = model and model:FindFirstChild(config.SeatName, true)
    if model and not seat then
        local seats = {}
        for _, p in model:GetDescendants() do
            if p:IsA("VehicleSeat") then table.insert(seats, p) end
        end
        if #seats == 1 then seat = seats[1] end
    end
    if not hull or not hull:IsA("BasePart") or not seat or not seat:IsA("VehicleSeat") then
        warn("M03 cabina deshabilitada: falta Hull o el asiento único del piloto")
        return
    end
    if model:FindFirstChild("M03CabinPrototype") then
        warn("M03 cabina: ya existe M03CabinPrototype; detené Play y eliminá el duplicado")
        return
    end
    folder = Instance.new("Folder")
    folder.Name, folder.Parent = "M03CabinPrototype", model
    local look = seat.CFrame.LookVector * Vector3.new(1, 0, 1)
    if look.Magnitude < 0.01 then look = Vector3.new(0, 0, -1) end
    local origin = CFrame.lookAt(seat.Position, seat.Position + look.Unit)
    -- Cabina detrás del asiento. Piso a la altura de su base.
    local base = origin * CFrame.new(0, -seat.Size.Y / 2 - 0.5, 10)
    local steel = Color3.fromRGB(42, 63, 77)
    floor = part("CabinFloor", Vector3.new(20, 1, 28), base, steel, true)
    part("BackWall", Vector3.new(20, 7, 1), base * CFrame.new(0, 4, 13.5), steel, true)
    part("LeftWall", Vector3.new(1, 7, 28), base * CFrame.new(-9.5, 4, 0), steel, true)
    part("RightWall", Vector3.new(1, 7, 28), base * CFrame.new(9.5, 4, 0), steel, true)
    part("FrontRail", Vector3.new(20, 2, 1), base * CFrame.new(0, 1.5, -13.5), steel, true)
    zone = part("CabinZone", Vector3.new(18, 12, 26), base * CFrame.new(0, 6.5, 0), steel, false, true)
    local inner = part("AirlockZone", Vector3.new(1, 2, 2), base * CFrame.new(8.5, 2, 6), Color3.fromRGB(240, 165, 55), false)
    part("BoardingDeck", Vector3.new(8, 1, 10), base * CFrame.new(14, 0, 6), steel, true)
    local outer = part("AirlockExterior", Vector3.new(1, 2, 2), base * CFrame.new(11, 2, 6), Color3.fromRGB(65, 200, 170), false)
    local innerTarget = part("InteriorTarget", Vector3.one, base * CFrame.new(5, 4, 6), steel, false, true)
    local outerTarget = part("ExteriorTarget", Vector3.one, base * CFrame.new(14, 4, 6), steel, false, true)
    prompt(inner, "ExitCabin", "Salir de la cabina", function(p, c, r)
        if inside(zone, r.Position, 1) then transfer(p, c, r, outerTarget.CFrame, false) end
    end)
    prompt(outer, "EnterCabin", "Entrar a la cabina", function(p, c, r)
        if not inside(zone, r.Position, 0) then transfer(p, c, r, innerTarget.CFrame, true) end
    end)
    -- Entrada accesible desde el suelo de la escena de prueba.
    local board = part("BoardingMarker", Vector3.new(1, 2, 1), base * CFrame.new(14, 2, 10), Color3.fromRGB(65, 200, 170), false)
    prompt(board, "Board", "Embarcar", function(p, c, r)
        if not inside(zone, r.Position, 0) then transfer(p, c, r, innerTarget.CFrame, true) end
    end)
    savedSeatTouch = seat.CanTouch
    seat.CanTouch = false -- Sentarse únicamente mediante el prompt.
    prompt(seat, "Pilot", "Pilotar", function(_, _, _, hum)
        if not seat.Occupant then seat:Sit(hum) end
    end)
    initialized = true
end
function Service.Start()
    if started or not initialized then return end
    started = true
    local elapsed = 0
    connect(RunService.Heartbeat, function(dt)
        elapsed += dt
        if elapsed < 0.1 then return end
        elapsed = 0
        if not zone.Parent then return end
        for _, p in Players:GetPlayers() do
            local c = p.Character
            local r = c and c:FindFirstChild("HumanoidRootPart")
            local h = c and c:FindFirstChildOfClass("Humanoid")
            local aboard = r ~= nil and h ~= nil and h.Health > 0 and inside(zone, r.Position, 0.5)
            p:SetAttribute("InSubmarine", aboard)
        end
    end)
    connect(exitRemote.OnServerEvent, function(player)
        if not seat or not seat.Parent then return end
        local occupant = seat.Occupant
        local char = player.Character
        if not occupant or not char or occupant.Parent ~= char then return end
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root or not root:IsA("BasePart") then return end
        local now = os.clock()
        if now < (cooldown[player] or 0) then return end
        cooldown[player] = now + 0.5
        -- Desactivar temporalmente evita que el contacto vuelva a sentarlo.
        seat.Disabled = true
        local weld = seat:FindFirstChild("SeatWeld")
        if weld then weld:Destroy() end
        occupant.Sit = false
        occupant:ChangeState(Enum.HumanoidStateType.GettingUp)
        task.spawn(function()
            RunService.Heartbeat:Wait()
            if player.Character == char and root.Parent and floor.Parent then
                -- Solo mover al personaje cuando ya no comparte ensamblaje.
                if root.AssemblyRootPart ~= hull.AssemblyRootPart then
                    local height = floor.Size.Y / 2 + occupant.HipHeight + root.Size.Y / 2 + 0.3
                    if occupant.RigType == Enum.HumanoidRigType.R6 then
                        local leg = char:FindFirstChild("Left Leg")
                        if leg then height += leg.Size.Y end
                    end
                    local stand = floor.CFrame * CFrame.new(0, height, -5)
                    char:PivotTo(stand * root.CFrame:ToObjectSpace(char:GetPivot()))
                    root.AssemblyLinearVelocity = hull:GetVelocityAtPosition(root.Position)
                    root.AssemblyAngularVelocity = Vector3.zero
                    local canSet = root:CanSetNetworkOwnership()
                    if canSet then root:SetNetworkOwner(player) end
                    exitRemote:FireClient(player)
                else
                    warn("[AbyssalSalvage] M03: otra unión mantiene al personaje conectado al casco")
                end
            end
            task.wait(0.5)
            if seat and seat.Parent then seat.Disabled = false end
        end)
    end)
    connect(Players.PlayerRemoving, function(p) cooldown[p] = nil end)
    print("[AbyssalSalvage] M03: cabina prototipo lista | esclusa con E | P1 pendiente")
end
function Service.Destroy()
    for _, c in connections do c:Disconnect() end
    table.clear(connections)
    table.clear(cooldown)
    if seat and seat.Parent then
        seat.CanTouch = savedSeatTouch
        local p = seat:FindFirstChild("Pilot")
        if p then p:Destroy() end
    end
    if folder then folder:Destroy() end
    for _, p in Players:GetPlayers() do p:SetAttribute("InSubmarine", false) end
    initialized, started = false, false
end
return Service
