-- M04 · Abyssal Salvage · Cámara prototipo 1
-- INSTALACIÓN (con Play detenido):
-- Guardar como src/client/CameraController.client.luau, junto a init.client.luau.
-- Rojo lo convierte en LocalScript: arranca solo. NO añadir require al init.
-- No reemplazar CabinAnchor, SubmarineClient ni ningún servicio del servidor.
-- PC: V cambia vista; ratón mira; Alt izquierdo libera el cursor.
-- Mando: R3 cambia vista; palanca derecha mira.
-- Móvil: botón Vista; arrastrar en la mitad derecha para mirar.
-- Se conservan WASD, salto, controles de pilotaje y salida X de M03.
-- PRUEBA: entrar/salir tres veces, V en ambas zonas, caminar contra paredes,
-- pilotar y salir con X, morir/reaparecer, escribir en chat y liberar cursor.
-- M03 multijugador y comodidad en dispositivos físicos quedan pendientes.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local CAS = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local player = Players.LocalPlayer
local STEP = "AbyssalCameraM04"
local ACTION = "AbyssalCameraViewM04"

-- Perfiles e input agrupados aquí para instalar sin nuevas dependencias.
local Profiles = {
    First = { distance = 0, shoulder = 0, fov = 75 },
    Third = { distance = 6, shoulder = 1.7, fov = 75 },
}
local sensitivity = 0.0028
local pitchLimit = math.rad(75)
local mode = "Third"
local yaw, pitch = 0, 0
local distance, shoulder = 6, 1.7
local safeDistance = nil
local stick = Vector2.zero
local lookTouch = nil
local cursorFree, menuOpen, focused = false, false, true
local char, hum, head, root
local connections = {}
local hiddenParts = {}
local inside = player:GetAttribute("InSubmarine") == true
local pendingInside, pendingSince = inside, os.clock()
local savedCamera, previousType, previousSubject, previousFov
local previousMouseBehavior = UIS.MouseBehavior
local previousMouseIcon = UIS.MouseIconEnabled
local destroyed = false
local bindVersion = 0

local gui = Instance.new("ScreenGui")
gui.Name = "M04CameraHUD"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")
local dot = Instance.new("Frame")
dot.Name = "Mira"
dot.AnchorPoint = Vector2.new(0.5, 0.5)
dot.Position = UDim2.fromScale(0.5, 0.5)
dot.Size = UDim2.fromOffset(4, 4)
dot.BackgroundColor3 = Color3.fromRGB(235, 245, 250)
dot.BorderSizePixel = 0
dot.Parent = gui
local round = Instance.new("UICorner")
round.CornerRadius = UDim.new(1, 0)
round.Parent = dot
local button = Instance.new("TextButton")
button.Name = "CambiarVista"
button.AnchorPoint = Vector2.new(1, 0)
button.Position = UDim2.new(1, -18, 0, 70)
button.Size = UDim2.fromOffset(145, 40)
button.BackgroundColor3 = Color3.fromRGB(24, 43, 55)
button.BackgroundTransparency = 0.15
button.TextColor3 = Color3.fromRGB(235, 245, 250)
button.Font = Enum.Font.GothamMedium
button.TextSize = 14
button.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = button

local function connect(signal, callback)
    table.insert(connections, signal:Connect(callback))
end
local function blocked()
    return player:GetAttribute("CrewLocked") ~= true or menuOpen or not focused or UIS:GetFocusedTextBox() ~= nil
end
local function setMode(nextMode)
    mode = nextMode
    button.Text = (mode == "First" and "Vista: 1ª" or "Vista: 3ª") .. (UIS.TouchEnabled and "" or " · V / R3")
end
local function toggle()
    if not blocked() then setMode(mode == "First" and "Third" or "First") end
end
local function restoreBody()
    for part, value in hiddenParts do
        if part.Parent then part.LocalTransparencyModifier = value end
    end
    table.clear(hiddenParts)
end
local function attach(character)
    bindVersion += 1
    local version = bindVersion
    restoreBody()
    char, hum, head, root = nil, nil, nil, nil
    local h = character:WaitForChild("Humanoid", 10)
    local r = character:WaitForChild("HumanoidRootPart", 10)
    local hd = character:WaitForChild("Head", 10)
    if destroyed or version ~= bindVersion or player.Character ~= character or not h or not r or not hd then return end
    char, hum, root, head = character, h, r, hd
    local look = root.CFrame.LookVector
    yaw = math.atan2(-look.X, -look.Z)
    pitch = 0
    inside = player:GetAttribute("InSubmarine") == true
    pendingInside, pendingSince = inside, os.clock()
    setMode(inside and "First" or "Third")
    distance, shoulder = Profiles[mode].distance, Profiles[mode].shoulder
    safeDistance = nil
end
local function rotate(delta)
    yaw -= delta.X * sensitivity
    pitch = math.clamp(pitch - delta.Y * sensitivity, -pitchLimit, pitchLimit)
end
connect(button.Activated, toggle)
CAS:BindAction(ACTION, function(_, state)
    if blocked() then return Enum.ContextActionResult.Pass end
    if state == Enum.UserInputState.Begin then toggle() end
    return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.V, Enum.KeyCode.ButtonR3)
connect(UIS.InputBegan, function(input, processed)
    if not processed and input.KeyCode == Enum.KeyCode.LeftAlt then cursorFree = not cursorFree end
    if input.UserInputType == Enum.UserInputType.Touch and not processed and not lookTouch then
        local camera = workspace.CurrentCamera
        if camera and input.Position.X > camera.ViewportSize.X * 0.5 then lookTouch = input end
    end
end)
connect(UIS.InputChanged, function(input)
    if input.KeyCode == Enum.KeyCode.Thumbstick2 then
        stick = Vector2.new(input.Position.X, input.Position.Y)
    end
    if blocked() then return end
    if input == lookTouch then rotate(Vector2.new(input.Delta.X, input.Delta.Y)) end
    if input.UserInputType == Enum.UserInputType.MouseMovement and not cursorFree then
        rotate(Vector2.new(input.Delta.X, input.Delta.Y))
    end
end)
connect(UIS.InputEnded, function(input)
    if input == lookTouch then lookTouch = nil end
    if input.KeyCode == Enum.KeyCode.Thumbstick2 then stick = Vector2.zero end
end)
connect(UIS.WindowFocusReleased, function() focused = false; stick = Vector2.zero; lookTouch = nil end)
connect(UIS.WindowFocused, function() focused = true end)
connect(GuiService.MenuOpened, function() menuOpen = true; stick = Vector2.zero; lookTouch = nil end)
connect(GuiService.MenuClosed, function() menuOpen = false end)
connect(player.CharacterAdded, attach)
connect(player.CharacterRemoving, function()
    bindVersion += 1
    restoreBody()
    char, hum, root, head = nil, nil, nil, nil
end)
if player.Character then task.spawn(attach, player.Character) end
setMode(inside and "First" or "Third")
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.RespectCanCollide = true

RunService:BindToRenderStep(STEP, Enum.RenderPriority.Camera.Value + 1, function(dt)
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
    if not camera or not char or not root or not head or not hum or not root.Parent then return end
    if camera ~= savedCamera then
        savedCamera = camera
        previousType, previousSubject, previousFov = camera.CameraType, camera.CameraSubject, camera.FieldOfView
    end
    if hum.Health <= 0 then
        restoreBody()
        camera.CameraType = Enum.CameraType.Custom
        camera.CameraSubject = hum
        UIS.MouseBehavior = Enum.MouseBehavior.Default
        UIS.MouseIconEnabled = true
        return
    end
    camera.CameraType = Enum.CameraType.Scriptable
    local lock = not blocked() and not cursorFree and UIS.MouseEnabled and not UIS.TouchEnabled
    UIS.MouseBehavior = lock and Enum.MouseBehavior.LockCenter or Enum.MouseBehavior.Default
    UIS.MouseIconEnabled = not lock
    dot.Visible = not blocked()
    if not blocked() and stick.Magnitude > 0.15 then
        local magnitude = math.min(1, (stick.Magnitude - 0.15) / 0.85)
        local value = stick.Unit * magnitude
        yaw -= value.X * 2.5 * math.min(dt, 0.1)
        pitch = math.clamp(pitch + value.Y * 2.0 * math.min(dt, 0.1), -pitchLimit, pitchLimit)
    end
    -- Histéresis temporal: no alternar vistas por un roce en el umbral.
    local aboard = player:GetAttribute("InSubmarine") == true
    if aboard ~= pendingInside then pendingInside, pendingSince = aboard, os.clock() end
    if pendingInside ~= inside and os.clock() - pendingSince > 0.35 then
        inside = pendingInside
        setMode(inside and "First" or "Third")
    end
    local profile = Profiles[mode]
    local alpha = 1 - math.exp(-12 * math.min(dt, 0.1))
    distance += (profile.distance - distance) * alpha
    shoulder += (profile.shoulder - shoulder) * alpha
    local rotation = CFrame.fromOrientation(pitch, yaw, 0)
    -- Sin balanceo artificial ni interpolación de la posición mundial:
    -- la cámara acompaña al personaje y no queda detrás del submarino.
    local pivot = head.Position
    local offset = rotation:VectorToWorldSpace(Vector3.new(shoulder, 0, distance))
    local length = offset.Magnitude
    local position = pivot
    params.FilterDescendantsInstances = { char }
    params.CollisionGroup = root.CollisionGroup
    if length > 0.001 then
        local direction = offset.Unit
        local sphere = workspace:Spherecast(pivot, 0.3, offset, params)
        local ray = workspace:Raycast(pivot, offset, params)
        local allowed = length
        if sphere then allowed = math.min(allowed, math.max(0, sphere.Distance - 0.12)) end
        if ray then allowed = math.min(allowed, math.max(0, ray.Distance - 0.35)) end
        -- Acercar inmediatamente ante obstáculos, recuperar distancia suavemente.
        if not safeDistance or allowed < safeDistance then safeDistance = allowed
        else safeDistance += (allowed - safeDistance) * alpha end
        position += direction * math.min(allowed, safeDistance)
    else safeDistance = 0 end
    camera.CFrame = CFrame.new(position) * rotation
    camera.Focus = CFrame.new(pivot + rotation.LookVector * 12)
    camera.FieldOfView = profile.fov
    local hide = (position - head.Position).Magnitude < 1
    if hide then
        for _, part in char:GetDescendants() do
            if part:IsA("BasePart") then
                if hiddenParts[part] == nil then hiddenParts[part] = part.LocalTransparencyModifier end
                part.LocalTransparencyModifier = 1
            end
        end
    else restoreBody() end
end)
connect(script.Destroying, function()
    destroyed = true
    RunService:UnbindFromRenderStep(STEP)
    CAS:UnbindAction(ACTION)
    restoreBody()
    for _, connection in connections do connection:Disconnect() end
    gui:Destroy()
    UIS.MouseBehavior, UIS.MouseIconEnabled = previousMouseBehavior, previousMouseIcon
    if savedCamera and savedCamera.Parent then
        savedCamera.CameraType = previousType
        savedCamera.CameraSubject = previousSubject
        savedCamera.FieldOfView = previousFov
    end
end)
print("[AbyssalSalvage] M04: cámara lista · V / R3 cambia vista")