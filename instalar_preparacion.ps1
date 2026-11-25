# Abyssal Salvage · Instalador nativo de Windows (PowerShell)
# No requiere Python. Funciona directamente en cualquier PC con Windows.

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
if (-not $root) { $root = Get-Location }

Write-Host "Iniciando instalacion de preparacion de clases..." -ForegroundColor Cyan

$projectFile = Join-Path $root "default.project.json"
if (-not (Test-Path $projectFile)) {
    Write-Host "ERROR: No se encontro default.project.json. Ejecuta este script dentro de la carpeta AbyssalSalvage." -ForegroundColor Red
    exit 1
}

$utf8NoBom = New-Object System.Text.UTF8Encoding $false

function Read-FileText($path) {
    return [System.IO.File]::ReadAllText((Join-Path $root $path))
}

function Write-FileText($path, $content) {
    $fullPath = Join-Path $root $path
    $dir = Split-Path $fullPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($fullPath, $content, $utf8NoBom)
}

$paths = @{
    crew   = "src/server/Services/CrewService.luau"
    ui     = "src/client/CrewController.client.luau"
    camera = "src/client/CameraController.client.luau"
    sub    = "src/client/SubmarineClient.luau"
    cabin  = "src/server/Services/CabinService.luau"
    player = "src/server/Services/PlayerService.luau"
}

# 1. Leer archivos
$original = @{}
foreach ($key in $paths.Keys) {
    $p = $paths[$key]
    $full = Join-Path $root $p
    if (-not (Test-Path $full)) {
        Write-Host "ERROR: No se encontro el archivo $p" -ForegroundColor Red
        exit 1
    }
    $original[$key] = Read-FileText $p
}

# 2. Verificar si ya esta instalado
if ($original["ui"] -match "M02Preparation") {
    Write-Host "AVISO: La preparacion ya estaba instalada en este proyecto." -ForegroundColor Yellow
    exit 0
}

# 3. Aplicar modificaciones en memoria
$updated = @{}
foreach ($key in $paths.Keys) { $updated[$key] = $original[$key].Replace("`r`n", "`n").Replace("`r", "`n") }

function Replace-Exact($key, [string]$oldStr, [string]$newStr) {
    $oldStr = $oldStr.Replace("`r`n", "`n").Replace("`r", "`n")
    $newStr = $newStr.Replace("`r`n", "`n").Replace("`r", "`n")
    $current = $updated[$key]
    $firstIndex = $current.IndexOf($oldStr)
    if ($firstIndex -lt 0) {
        Write-Host "ERROR: No se encontro el fragmento esperado en $($paths[$key])." -ForegroundColor Red
        Write-Host "Fragmento buscado:"
        Write-Host $oldStr -ForegroundColor Yellow
        Write-Host "No se modifico ningun archivo del proyecto."
        exit 1
    }
    $secondIndex = $current.IndexOf($oldStr, $firstIndex + $oldStr.Length)
    if ($secondIndex -ge 0) {
        Write-Host "ERROR: Fragmento ambiguo en $($paths[$key])." -ForegroundColor Red
        exit 1
    }
    $updated[$key] = $current.Substring(0, $firstIndex) + $newStr + $current.Substring($firstIndex + $oldStr.Length)
}

# Modificaciones en CrewService
$updated["crew"] = $updated["crew"].Replace('"Lobby"', '"Preparation"')
Replace-Exact "crew" "connected = m.player ~= nil," "connected = m.player ~= nil, ready = m.ready == true,"
Replace-Exact "crew" "m.class = role" "m.class = role`n    m.ready = false"
Replace-Exact "crew" "m.player, m.expires = player, nil" "m.player, m.expires = player, nil`n    m.ready = false"
Replace-Exact "crew" "if count() >= Defs.MaxCrew then" "if phase == `"Locked`" then player:Kick(`"Expedición en curso. Esperá a la próxima preparación.`"); return end`n        if count() >= Defs.MaxCrew then"
Replace-Exact "crew" "if not m.class then return false, `"Todos deben elegir una clase`" end" "if not m.class then return false, `"Todos deben elegir una clase`" end`n        if not m.ready then return false, `"Falta confirmar Listo`" end"
Replace-Exact "crew" "phase = `"Preparation`"`n    broadcast()" "phase = `"Preparation`"`n    for _, m in members do m.ready = false end`n    broadcast()"

$readyBlock = @"
if action == "Ready" then
            local m = members[player.UserId]
            if phase == "Preparation" and m and m.player == player and m.class and type(value) == "boolean" then
                if PlayerService.GetState(player) == "Active" then
                    m.ready = value
                    ok, message = true, value and "Listo. Esperando al resto…" or "Confirmación cancelada"
                    local allReady = true
                    for _, member in ordered(true) do
                        if not member.ready or not member.class or PlayerService.GetState(member.player) ~= "Active" then allReady = false end
                    end
                    if allReady then
                        ok, message = Service.BeginExpedition()
                    else broadcast() end
                else message = "Esperá a estar activo para confirmar" end
            else message = "Elegí una clase durante la preparación" end
        elseif action == "Choose" then ok, message = choose(player, value)
"@
Replace-Exact "crew" "if action == `"Choose`" then ok, message = choose(player, value)" $readyBlock

$linkBlock = @"
m.link = player:GetAttributeChangedSignal("CrewState"):Connect(function()
        if PlayerService.GetState(player) ~= "Active" then m.ready = false end
        broadcast()
    end)
"@
Replace-Exact "crew" "m.link = player:GetAttributeChangedSignal(`"CrewState`"):Connect(broadcast)" $linkBlock

# Modificaciones en CameraController
Replace-Exact "camera" "return menuOpen or not focused or UIS:GetFocusedTextBox() ~= nil" "return player:GetAttribute(`"CrewLocked`") ~= true or menuOpen or not focused or UIS:GetFocusedTextBox() ~= nil"

$cameraUpdateBlock = @"
    local camera = workspace.CurrentCamera
    local preparation = player:GetAttribute("CrewLocked") ~= true
    gui.Enabled = not preparation
    if preparation then
        restoreBody()
        stick = Vector2.zero
        lookTouch = nil
        UIS.MouseBehavior = Enum.MouseBehavior.Default
        UIS.MouseIconEnabled = true
        if camera then
            camera.CameraType = Enum.CameraType.Custom
            if hum then camera.CameraSubject = hum end
        end
        return
    end
    if not camera or not char
"@
Replace-Exact "camera" "    local camera = workspace.CurrentCamera`n    if not camera or not char" $cameraUpdateBlock

# Modificaciones en SubmarineClient
Replace-Exact "sub" "local function verticalInput()`n" "local function verticalInput()`n    if player:GetAttribute(`"CrewLocked`") ~= true then return 0 end`n"
Replace-Exact "sub" "if not focused or UserInputService:GetFocusedTextBox() then" "if player:GetAttribute(`"CrewLocked`") ~= true or not focused or UserInputService:GetFocusedTextBox() then`n            table.clear(held)"

# Modificaciones en CabinService
Replace-Exact "cabin" "connect(p.Triggered, function(player)`n" "connect(p.Triggered, function(player)`n        if player:GetAttribute(`"CrewLocked`") ~= true then return end`n"

# Modificaciones en PlayerService
if ($updated["player"].Contains('local record = { state = "Active", links = {} }')) {
    Replace-Exact "player" 'local record = { state = "Active", links = {} }' 'local record: { state: string, links: {RBXScriptConnection}, death: RBXScriptConnection? } = { state = "Active", links = {}, death = nil }'
}

# 4. Nueva UI de Preparación de Pantalla Completa
$clientUI = @"
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
"@
$updated["ui"] = $clientUI

# 5. Crear Backup
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupFolder = Join-Path $root "backup_preparacion_$timestamp"
New-Item -ItemType Directory -Path $backupFolder -Force | Out-Null
foreach ($key in $paths.Keys) {
    $src = Join-Path $root $paths[$key]
    $dst = Join-Path $backupFolder $paths[$key]
    $dstDir = Split-Path $dst -Parent
    if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
    Copy-Item -Path $src -Destination $dst -Force
}

# 6. Escribir archivos actualizados
foreach ($key in $paths.Keys) {
    Write-FileText $paths[$key] $updated[$key]
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host " INSTALACION COMPLETADA CON EXITO" -ForegroundColor Green
Write-Host " Copia de seguridad guardada en: backup_preparacion_$timestamp" -ForegroundColor Gray
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "Ahora podes volver a Roblox Studio, sincronizar Rojo y probar en Play." -ForegroundColor Cyan
