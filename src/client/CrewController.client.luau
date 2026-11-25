-- Destino: src/client/CrewController.client.luau
-- LocalScript autónomo: NO añadir require al init.client.luau.
-- T abre/cierra. Usar Alt izquierdo (M04) para liberar el cursor en PC.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CAS = game:GetService("ContextActionService")
local UIS = game:GetService("UserInputService")
local player = Players.LocalPlayer
local common = RS:WaitForChild("Common")
local Defs = require(common:WaitForChild("ClassDefs"))
local Net = require(common:WaitForChild("Net"))
local remote = Net.GetEvent("CrewM02_v1")
local gui = Instance.new("ScreenGui")
gui.Name = "M02CrewHUD"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")
local function text(parent, label, height)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -12, 0, height)
    l.BackgroundTransparency = 1
    l.TextColor3 = Color3.fromRGB(228, 239, 245)
    l.Font = Enum.Font.Gotham
    l.TextSize = 14
    l.TextWrapped = true
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Text = label
    l.Parent = parent
    return l
end
local function button(parent, label, callback)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -12, 0, 36)
    b.BackgroundColor3 = Color3.fromRGB(39, 73, 87)
    b.TextColor3 = Color3.fromRGB(240, 248, 250)
    b.Font = Enum.Font.GothamMedium
    b.TextSize = 14
    b.Text = label
    b.Selectable = true
    b.Parent = parent
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = b
    b.Activated:Connect(callback)
    return b
end
local panel = Instance.new("ScrollingFrame")
panel.Position = UDim2.new(0, 12, 0.5, -170)
panel.Size = UDim2.new(0.85, 0, 0.7, 0)
panel.BackgroundColor3 = Color3.fromRGB(15, 29, 39)
panel.BackgroundTransparency = 0.06
panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
panel.CanvasSize = UDim2.new()
panel.ScrollBarThickness = 5
panel.Parent = gui
local size = Instance.new("UISizeConstraint")
size.MaxSize = Vector2.new(340, 540)
size.Parent = panel
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 7)
layout.Parent = panel
local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 10)
padding.PaddingTop = UDim.new(0, 10)
padding.PaddingBottom = UDim.new(0, 10)
padding.Parent = panel
local opener = button(gui, "Tripulación · T", function() panel.Visible = not panel.Visible end)
opener.Position = UDim2.new(0, 12, 0, 70)
opener.Size = UDim2.fromOffset(160, 36)
text(panel, "TRIPULACIÓN · M02", 28)
text(panel, "PC: Alt libera el cursor · T cierra el panel", 35)
local status = text(panel, "Conectando…", 35)
local roster = text(panel, "", 90)
local roles = text(panel, "", 65)
local message = text(panel, "Elegí tu clase antes de confirmar.", 42)
local classButtons = {}
for _, role in Defs.Order do
    classButtons[role] = button(panel, Defs.Names[role], function() remote:FireServer("Choose", role) end)
end
local tests = {}
table.insert(tests, text(panel, "PRUEBAS DE STUDIO · No inician una misión real", 40))
table.insert(tests, button(panel, "Confirmar tripulación (bloquea clases)", function() remote:FireServer("TestBegin") end))
table.insert(tests, button(panel, "Terminar prueba (desbloquea clases)", function() remote:FireServer("TestEnd") end))
for _, item in { { "Unconscious", "Marcar inconsciente" }, { "Rescued", "Marcar rescatado" }, { "Active", "Volver a activo" } } do
    table.insert(tests, button(panel, item[2], function() remote:FireServer("TestState", item[1]) end))
end
for _, item in tests do item.Visible = false end
local stateNames = { Active = "Activo", Unconscious = "Inconsciente", Rescued = "Rescatado", Disconnected = "Desconectado (plaza reservada)" }
local connected = false
local connection = remote.OnClientEvent:Connect(function(kind, data)
    if kind == "Result" then message.Text = data.message; return end
    if kind ~= "Snapshot" then return end
    connected = true
    local lines, names, taken = {}, {}, {}
    for _, member in data.members do
        names[member.id] = member.name
        if member.class then taken[member.class] = member.id end
        table.insert(lines, member.name .. (member.id == data.leader and " [Líder]" or "") .. " · " .. (Defs.Names[member.class] or "Sin clase") .. "\n" .. (stateNames[member.state] or member.state))
    end
    roster.Text = table.concat(lines, "\n")
    roster.Size = UDim2.new(1, -12, 0, math.max(48, #lines * 42))
    status.Text = data.phase == "Locked" and "Clases bloqueadas hasta el final" or "Preparación · Elegí tu clase"
    local coverage = {}
    for _, role in Defs.Order do
        table.insert(coverage, Defs.Names[role] .. ": " .. (names[data.owners[role]] or "Sin asignar"))
        local b = classButtons[role]
        local own = taken[role] == player.UserId
        local available = data.phase == "Lobby" and (not taken[role] or own)
        b.Text = Defs.Names[role] .. (own and " · Tu clase" or (taken[role] and " · Ocupada" or ""))
        b.Active = available
        b.AutoButtonColor = available
        b.BackgroundColor3 = available and Color3.fromRGB(39, 73, 87) or Color3.fromRGB(42, 46, 51)
    end
    roles.Text = table.concat(coverage, "\n")
    for _, item in tests do item.Visible = data.studio == true end
end)
CAS:BindAction("M02CrewPanel", function(_, state)
    if UIS:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
    if state == Enum.UserInputState.Begin then panel.Visible = not panel.Visible end
    return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.T)
-- Reintentar sincronización si el primer mensaje precede al arranque del servicio.
task.spawn(function()
    while not connected and gui.Parent do
        remote:FireServer("Sync")
        task.wait(2)
    end
end)
script.Destroying:Connect(function()
    connection:Disconnect()
    CAS:UnbindAction("M02CrewPanel")
    gui:Destroy()
end)
print("[AbyssalSalvage] M02: panel de tripulación listo")
