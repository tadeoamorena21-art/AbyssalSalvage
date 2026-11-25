-- M02 · Preparación de clases. LocalScript automático de Rojo.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local PPS = game:GetService("ProximityPromptService")
local player = Players.LocalPlayer
local common = RS:WaitForChild("Common")
local Defs = require(common:WaitForChild("ClassDefs"))
local Net = require(common:WaitForChild("Net"))
local remote = Net.GetEvent("CrewM02_v1")
local gui = Instance.new("ScreenGui")
gui.Name = "M02Preparation"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100
gui.Parent = player:WaitForChild("PlayerGui")
local background = Instance.new("Frame")
background.Size = UDim2.fromScale(1, 1)
background.BackgroundColor3 = Color3.fromRGB(8, 19, 29)
background.BorderSizePixel = 0
background.Active = true
background.Parent = gui
local panel = Instance.new("ScrollingFrame")
panel.Position = UDim2.fromScale(0.06, 0.1)
panel.Size = UDim2.fromScale(0.88, 0.83)
panel.BackgroundTransparency = 1
panel.BorderSizePixel = 0
panel.CanvasSize = UDim2.new()
panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
panel.ScrollBarThickness = 5
panel.Parent = background
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 12)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = panel
local index = 0
local function element(kind, text, height)
    index += 1
    local item = Instance.new(kind)
    item.LayoutOrder = index
    item.Size = UDim2.new(1, -12, 0, height)
    item.Text = text
    item.TextWrapped = true
    item.Font = Enum.Font.GothamMedium
    item.TextSize = 17
    item.TextColor3 = Color3.fromRGB(228, 241, 248)
    item.BackgroundColor3 = Color3.fromRGB(26, 52, 68)
    item.BorderSizePixel = 0
    item.Parent = panel
    if kind == "TextLabel" then item.BackgroundTransparency = 1 end
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = item
    return item
end
element("TextLabel", "ABYSSAL SALVAGE  /  PREPARACIÓN", 42)
element("TextLabel", "Elegí tu especialidad y confirmá cuando estés listo.", 44)
local status = element("TextLabel", "Conectando con la tripulación…", 40)
local cards, available = {}, {}
local descriptions = {
    Pilot = "Navegación y maniobras del submarino",
    Technician = "Mantenimiento y reparación de sistemas",
    Sonarist = "Lectura del entorno y detección de amenazas",
    Diver = "Exploración exterior y recuperación de objetos",
}
local phase, ownClass, ownReady, connected = "Preparation", nil, false, false
local lastSend = -math.huge
local function send(action, value)
    if os.clock() - lastSend < 0.2 then return end
    lastSend = os.clock()
    remote:FireServer(action, value)
end
for _, role in Defs.Order do
    local b = element("TextButton", Defs.Names[role], 82)
    b.Activated:Connect(function()
        if phase == "Preparation" and available[role] then send("Choose", role) end
    end)
    cards[role] = b
end
local roster = element("TextLabel", "", 125)
local message = element("TextLabel", "Las especialidades describen el diseño; sus mecánicas se desarrollan en módulos posteriores.", 62)
local ready = element("TextButton", "Elegí una clase", 54)
ready.Activated:Connect(function()
    if connected and ownClass and phase == "Preparation" then send("Ready", not ownReady) end
end)
element("TextLabel", "Prueba local: al estar todos listos se habilita el prototipo. En solitario alcanza con tu confirmación.", 62)
local returnButton = Instance.new("TextButton")
returnButton.Size = UDim2.fromOffset(225, 38)
returnButton.Position = UDim2.new(0, 16, 0, 60)
returnButton.Text = "Studio: volver a preparación"
returnButton.BackgroundColor3 = Color3.fromRGB(26, 52, 68)
returnButton.TextColor3 = Color3.new(1, 1, 1)
returnButton.Visible = false
returnButton.Parent = gui
returnButton.Activated:Connect(function() send("TestEnd") end)
local controls
local promptsBefore = PPS.Enabled
local function applyLock()
    local locked = player:GetAttribute("CrewLocked") == true
    if controls then
        if locked then controls:Enable() else controls:Disable() end
    end
    PPS.Enabled = locked and promptsBefore or false
    if not locked then
        UIS.MouseBehavior = Enum.MouseBehavior.Default
        UIS.MouseIconEnabled = true
    end
end
local lockConnection = player:GetAttributeChangedSignal("CrewLocked"):Connect(applyLock)
applyLock()
task.spawn(function()
    local module = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 15)
    if module and gui.Parent then
        local ok, result = pcall(function() return require(module):GetControls() end)
        if ok then controls = result; applyLock() else warn("M02: no se pudieron suspender controles", result) end
    end
end)
local connection = remote.OnClientEvent:Connect(function(kind, data)
    if kind == "Result" then message.Text = data.message; return end
    if kind ~= "Snapshot" then return end
    connected = true
    phase = data.phase
    background.Visible = phase ~= "Locked"
    returnButton.Visible = data.studio == true and phase == "Locked" and data.leader == player.UserId
    ownClass, ownReady = nil, false
    local taken, lines, readyCount, total = {}, {}, 0, 0
    for _, m in data.members do
        if m.class then taken[m.class] = m.id end
        if m.id == player.UserId then ownClass, ownReady = m.class, m.ready == true end
        if m.connected then total += 1; if m.ready then readyCount += 1 end end
        local state = not m.connected and "Desconectado" or (m.ready and "Listo" or "Preparándose")
        table.insert(lines, m.name .. " · " .. (Defs.Names[m.class] or "Sin clase") .. " · " .. state)
    end
    status.Text = string.format("TRIPULACIÓN  ·  %d/%d listos", readyCount, total)
    roster.Text = table.concat(lines, "\n")
    for _, role in Defs.Order do
        local own = taken[role] == player.UserId
        available[role] = phase == "Preparation" and (not taken[role] or own)
        local b = cards[role]
        b.Text = Defs.Names[role] .. (own and "  ·  TU CLASE" or (taken[role] and "  ·  OCUPADA" or "")) .. "\n" .. descriptions[role]
        b.BackgroundColor3 = own and Color3.fromRGB(20, 105, 107) or Color3.fromRGB(26, 52, 68)
        b.AutoButtonColor = available[role]
        b.Selectable = available[role]
    end
    ready.Text = not ownClass and "Elegí una clase" or (ownReady and "Cancelar listo" or "Listo")
    ready.AutoButtonColor = ownClass ~= nil
end)
task.spawn(function()
    while gui.Parent do
        remote:FireServer("Sync")
        task.wait(connected and 5 or 2)
    end
end)
script.Destroying:Connect(function()
    connection:Disconnect()
    lockConnection:Disconnect()
    if controls then controls:Enable() end
    PPS.Enabled = promptsBefore
    gui:Destroy()
end)