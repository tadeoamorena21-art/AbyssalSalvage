-- Destino: src/client/SubmarineClient.luau (ModuleScript)
-- Reemplaza el archivo existente en src/client/SubmarineClient.luau.
-- Maneja controles de pilotaje, salida confiable (X) y cartel de ayuda en pantalla.
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
local remote, exitRemote, humanoid, activeSeat, hintGui
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

local function setHintVisible(visible)
    if not visible then
        if hintGui then hintGui.Enabled = false end
        return
    end
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return end
    if not hintGui or not hintGui.Parent then
        hintGui = Instance.new("ScreenGui")
        hintGui.Name = "M03PilotHint"
        hintGui.ResetOnSpawn = false
        hintGui.Parent = playerGui

        local label = Instance.new("TextLabel")
        label.Name = "ControlsLabel"
        label.AnchorPoint = Vector2.new(0.5, 1)
        label.Position = UDim2.new(0.5, 0, 1, -24)
        label.Size = UDim2.new(0, 440, 0, 34)
        label.BackgroundColor3 = Color3.fromRGB(14, 22, 30)
        label.BackgroundTransparency = 0.25
        label.TextColor3 = Color3.fromRGB(235, 245, 250)
        label.Font = Enum.Font.GothamMedium
        label.TextSize = 14
        label.Text = "WASD Mover  ·  Espacio Subir  ·  C Bajar  ·  X Levantarse"
        label.Parent = hintGui

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = label
    end
    hintGui.Enabled = true
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
    setHintVisible(false)
    activeSeat = nil
    table.clear(held)
    elapsed = 0
end

local function requestExit()
    if not activeSeat then return end
    remote:FireServer(0, 0, 0)
    if exitRemote then exitRemote:FireServer() end
    -- El servidor debe ver al ocupante antes de soltarlo. No modificar Sit
    -- localmente ni quitar el botón antes de que confirme la separación.
    table.clear(held)
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
    setHintVisible(true)
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
                    requestExit()
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
    exitRemote = Net.GetEvent("SubmarineExit_v1")
    assert(typeof(remote) == "Instance" and remote:IsA("RemoteEvent"),
        "M03: Net.GetEvent debe devolver el evento registrado por servidor")
    started = true
    table.insert(connections, exitRemote.OnClientEvent:Connect(function()
        stopPiloting()
        if humanoid then
            humanoid.Sit = false
            humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
    end))
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
    if hintGui then hintGui:Destroy(); hintGui = nil end
    humanoid = nil
end

return Client
