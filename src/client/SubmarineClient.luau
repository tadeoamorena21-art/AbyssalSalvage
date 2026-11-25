-- Destino: src/client/SubmarineClient.luau (ModuleScript)
-- Arranque en init.client.luau, después del handshake:
-- require(script:WaitForChild("SubmarineClient")).Start()
-- La línea anterior supone el mapeo Rojo estándar de init.client.luau.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Common = ReplicatedStorage:WaitForChild("Common")
local SubmarineConfig = Common:WaitForChild("SubmarineConfig")
local NetModule = Common:WaitForChild("Net")

local Config = require(SubmarineConfig) :: any
local Net = require(NetModule) :: any
local Client = {}
local player = Players.LocalPlayer
local remote, humanoid, activeSeat
local started, focused = false, true
local elapsed = 0
local held, connections, characterConnections = {}, {}, {}
local jumpWasEnabled = true
local actions = {
    { "M03Ascend", "Subir", { Enum.KeyCode.Space, Enum.KeyCode.ButtonR1 }, 1 },
    { "M03Descend", "Bajar", { Enum.KeyCode.C, Enum.KeyCode.LeftShift,
        Enum.KeyCode.RightShift, Enum.KeyCode.ButtonL1 }, -1 },
    { "M03Exit", "Salir", { Enum.KeyCode.X, Enum.KeyCode.ButtonB }, 0 },
}

local function disconnectAll(list)
    for _, connection in list do connection:Disconnect() end
    table.clear(list)
end

local function verticalInput()
    local up, down = false, false
    for _, value in held do
        if value == 1 then up = true elseif value == -1 then down = true end
    end
    return (up and 1 or 0) - (down and 1 or 0)
end

local function stopPiloting()
    if activeSeat then remote:FireServer(0, 0, 0) end
    for _, action in actions do ContextActionService:UnbindAction(action[1]) end
    if humanoid then
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, jumpWasEnabled)
    end
    activeSeat = nil
    table.clear(held)
    elapsed = 0
end

local function updateSeat()
    local candidate = humanoid and humanoid.SeatPart
    if candidate == activeSeat then return end
    if activeSeat then stopPiloting() end
    local model = workspace:FindFirstChild(Config.ModelName)
    if not candidate or not model or not candidate:IsDescendantOf(model)
        or not candidate:IsA("VehicleSeat") or candidate.Name ~= Config.SeatName then
        return
    end
    activeSeat = candidate
    jumpWasEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
    for index, action in actions do
        local name, title, keys, direction = action[1], action[2], action[3], action[4]
        ContextActionService:BindActionAtPriority(name, function(_, state, object)
            if not activeSeat then return Enum.ContextActionResult.Pass end
            local key = name .. ":" .. object.KeyCode.Name
            if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
                held[key] = nil
            elseif state == Enum.UserInputState.Begin and focused
                and not UserInputService:GetFocusedTextBox() then
                if direction == 0 then
                    humanoid.Sit = false
                    stopPiloting()
                else
                    held[key] = direction
                end
            end
            return Enum.ContextActionResult.Sink
        end, true, Enum.ContextActionPriority.High.Value + 100, table.unpack(keys))
        ContextActionService:SetTitle(name, title)
        ContextActionService:SetPosition(name, UDim2.new(1, -80, 0.36, (index - 1) * 65))
    end
end

local function attachCharacter(character)
    if activeSeat then stopPiloting() end
    disconnectAll(characterConnections)
    humanoid = nil
    local nextHumanoid = character:WaitForChild("Humanoid", 10)
    if not started or player.Character ~= character or not nextHumanoid then return end
    humanoid = nextHumanoid
    table.insert(characterConnections, humanoid:GetPropertyChangedSignal("SeatPart"):Connect(updateSeat))
    table.insert(characterConnections, humanoid.Died:Connect(stopPiloting))
    updateSeat()
end

function Client.Start()
    if started then return end
    remote = Net.GetEvent(Config.RemoteName)
    assert(typeof(remote) == "Instance" and remote:IsA("RemoteEvent"),
        "M03: Net.GetEvent debe devolver el evento registrado por servidor")
    started = true
    table.insert(connections, player.CharacterAdded:Connect(attachCharacter))
    table.insert(connections, player.CharacterRemoving:Connect(function()
        if activeSeat then stopPiloting() end
        disconnectAll(characterConnections)
        humanoid = nil
    end))
    table.insert(connections, UserInputService.WindowFocusReleased:Connect(function()
        focused = false
        table.clear(held)
        if activeSeat then remote:FireServer(0, 0, 0) end
    end))
    table.insert(connections, UserInputService.WindowFocused:Connect(function() focused = true end))
    table.insert(connections, UserInputService.TextBoxFocused:Connect(function()
        table.clear(held)
    end))
    table.insert(connections, RunService.Heartbeat:Connect(function(dt)
        if not activeSeat then return end
        if not activeSeat.Parent or not humanoid or humanoid.Health <= 0
            or humanoid.SeatPart ~= activeSeat then
            stopPiloting()
            return
        end
        elapsed += dt
        if elapsed < Config.SendInterval then return end
        elapsed = 0
        if not focused or UserInputService:GetFocusedTextBox() then
            remote:FireServer(0, 0, 0)
        else
            -- VehicleSeat recibe WASD, mando y joystick virtual de Roblox.
            remote:FireServer(activeSeat.ThrottleFloat, activeSeat.SteerFloat, verticalInput())
        end
    end))
    if player.Character then task.spawn(attachCharacter, player.Character) end
end

function Client.Destroy()
    if not started then return end
    started = false
    stopPiloting()
    disconnectAll(characterConnections)
    disconnectAll(connections)
    humanoid = nil
end
return Client
