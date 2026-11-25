-- Destino: src/client/CabinAnchor.client.luau
-- Es un LocalScript automático de Rojo: NO añadir require en init.client.
-- Prototipo de compensación por transformación; validar P1 antes de producción.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local common = RS:WaitForChild("Common")
local config = require(common:WaitForChild("SubmarineConfig"))
local previous, previousRoot, previousFloor
local function reset()
    previous, previousRoot, previousFloor = nil, nil, nil
end
local function contains(part, position)
    local p = part.CFrame:PointToObjectSpace(position)
    local s = part.Size * 0.5
    return math.abs(p.X) <= s.X and math.abs(p.Y) <= s.Y and math.abs(p.Z) <= s.Z
end
local connection = RunService.PreSimulation:Connect(function()
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    local model = workspace:FindFirstChild(config.ModelName)
    local cabin = model and model:FindFirstChild("M03CabinPrototype")
    local floor = cabin and cabin:FindFirstChild("CabinFloor")
    local zone = cabin and cabin:FindFirstChild("CabinZone")
    if not root or not humanoid or humanoid.Health <= 0 or not floor or not zone then
        reset()
        return
    end
    -- El SeatWeld ya mueve al piloto; no aplicar una segunda transformación.
    if humanoid.SeatPart or humanoid.Sit or not contains(zone, root.Position) then
        reset()
        return
    end
    local current = floor.CFrame
    -- Transporte por contacto físico exclusivamente en esta revisión.
    -- No sumar delta de CFrame: la fricción ya transmite movimiento.
    -- Validar aceleraciones y giros con pasajero antes de cerrar M03.
    previous, previousRoot, previousFloor = current, root, floor
end)
player.CharacterRemoving:Connect(reset)
script.Destroying:Connect(function()
    connection:Disconnect()
    reset()
end)
print("[AbyssalSalvage] M03: CabinAnchor cliente iniciado")
