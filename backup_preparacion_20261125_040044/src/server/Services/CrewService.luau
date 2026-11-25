-- Destino: src/server/Services/CrewService.luau
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Common = RS:WaitForChild("Common")
local Defs = require(Common:WaitForChild("ClassDefs"))
local PlayerService = require(script.Parent:WaitForChild("PlayerService"))
local Net = require(Common:WaitForChild("Net"))
local Service = { LoadPriority = -20 }
local members, owners, connections, lastRequest = {}, {}, {}, {}
local phase, leader = "Lobby", nil
local remote, started, initialized
local function ordered(connectedOnly)
    local result = {}
    for _, m in members do
        if not connectedOnly or m.player then table.insert(result, m) end
    end
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end
local function count()
    local n = 0
    for _ in members do n += 1 end
    return n
end
local function rebuild()
    local active = ordered(true)
    if not leader or not members[leader] or not members[leader].player then
        leader = active[1] and active[1].id or nil
    end
    table.clear(owners)
    local loads = {}
    for _, m in active do loads[m.id] = 0 end
    for _, m in active do
        if m.class then owners[m.class] = m.id; loads[m.id] += 1 end
    end
    -- Funciones adicionales son cobertura temporal, nunca cambian la clase elegida.
    if phase == "Locked" and #active > 0 then
        for _, role in Defs.Order do
            if not owners[role] then
                local best = active[1]
                for _, m in active do if loads[m.id] < loads[best.id] then best = m end end
                owners[role] = best.id
                loads[best.id] += 1
            end
        end
    end
    for _, m in active do
        local roles = {}
        for _, role in Defs.Order do if owners[role] == m.id then table.insert(roles, role) end end
        m.player:SetAttribute("CrewId", "Main")
        m.player:SetAttribute("CrewClass", m.class or "")
        m.player:SetAttribute("CrewRoles", table.concat(roles, ","))
        m.player:SetAttribute("CrewLocked", phase == "Locked")
        m.player:SetAttribute("CrewLeader", m.id == leader)
    end
end
local function snapshot()
    local rows = {}
    for _, m in ordered(false) do
        table.insert(rows, { id = m.id, name = m.name, class = m.class,
            connected = m.player ~= nil,
            state = m.player and PlayerService.GetState(m.player) or "Disconnected" })
    end
    local roleOwners = table.clone(owners)
    return { phase = phase, leader = leader, members = rows, owners = roleOwners, studio = RunService:IsStudio() }
end
local function broadcast()
    rebuild()
    remote:FireAllClients("Snapshot", snapshot())
end
local function add(player)
    PlayerService.Register(player)
    local m = members[player.UserId]
    if not m then
        if count() >= Defs.MaxCrew then player:Kick("Esta tripulación ya tiene cuatro plazas ocupadas o reservadas."); return end
        m = { id = player.UserId, name = player.DisplayName }
        members[player.UserId] = m
    end
    m.player, m.expires = player, nil
    if m.link then m.link:Disconnect() end
    m.link = player:GetAttributeChangedSignal("CrewState"):Connect(broadcast)
    broadcast()
end
local function choose(player, role)
    local m = members[player.UserId]
    if not m or m.player ~= player then return false, "No pertenecés a esta tripulación" end
    if phase ~= "Lobby" then return false, "La clase queda fija hasta terminar" end
    if type(role) ~= "string" or not Defs.Names[role] then return false, "Clase inválida" end
    for id, other in members do
        if id ~= m.id and other.class == role then return false, "Esa clase ya está ocupada o reservada" end
    end
    m.class = role
    broadcast()
    return true
end
function Service.BeginExpedition()
    if phase ~= "Lobby" then return false, "La tripulación ya está confirmada" end
    local active = ordered(true)
    if #active == 0 then return false, "No hay tripulantes" end
    for _, m in active do
        if not m.class then return false, "Todos deben elegir una clase" end
        if PlayerService.GetState(m.player) ~= "Active" then return false, "Todos deben estar activos" end
    end
    phase = "Locked"
    broadcast()
    return true
end
function Service.EndExpedition()
    if phase ~= "Locked" then return false, "No hay tripulación confirmada" end
    phase = "Lobby"
    broadcast()
    return true
end
function Service.GetRoleOwner(role)
    local m = members[owners[role]]
    return m and m.player
end
function Service.GetSnapshot() return snapshot() end
function Service.Init()
    if initialized then return end
    initialized = true
    remote = Net.GetEvent("CrewM02_v1")
end
function Service.Start()
    if started then return end
    Service.Init()
    started = true
    table.insert(connections, remote.OnServerEvent:Connect(function(player, action, value)
        if type(action) ~= "string" then return end
        local now = os.clock()
        if now - (lastRequest[player] or -math.huge) < 0.15 then return end
        lastRequest[player] = now
        if action == "Sync" then remote:FireClient(player, "Snapshot", snapshot()); return end
        local ok, message = false, "Acción no disponible"
        if action == "Choose" then ok, message = choose(player, value)
        elseif RunService:IsStudio() and members[player.UserId] then
            if action == "TestBegin" and player.UserId == leader then ok, message = Service.BeginExpedition()
            elseif action == "TestEnd" and player.UserId == leader then ok, message = Service.EndExpedition()
            elseif action == "TestState" and type(value) == "string" then ok, message = PlayerService.SetState(player, value) end
        end
        remote:FireClient(player, "Result", { ok = ok, message = message or "Cambio aplicado" })
    end))
    table.insert(connections, Players.PlayerAdded:Connect(add))
    table.insert(connections, Players.PlayerRemoving:Connect(function(player)
        lastRequest[player] = nil
        local m = members[player.UserId]
        if not m or m.player ~= player then return end
        if m.link then m.link:Disconnect(); m.link = nil end
        m.player, m.expires = nil, os.clock() + Defs.ReconnectSeconds
        broadcast()
    end))
    local elapsed = 0
    table.insert(connections, RunService.Heartbeat:Connect(function(dt)
        elapsed += dt
        if elapsed < 1 then return end
        elapsed = 0
        local changed = false
        for id, m in members do
            if not m.player and m.expires and os.clock() >= m.expires then members[id] = nil; changed = true end
        end
        if next(members) == nil then phase = "Lobby" end
        if changed then broadcast() end
    end))
    for _, player in Players:GetPlayers() do add(player) end
    print("[AbyssalSalvage] M02: tripulación y clases listas")
end
function Service.Destroy()
    for _, c in connections do c:Disconnect() end
    for _, m in members do if m.link then m.link:Disconnect() end end
    table.clear(connections); table.clear(members); table.clear(owners); table.clear(lastRequest)
    phase, leader, started = "Lobby", nil, false
end
return Service
