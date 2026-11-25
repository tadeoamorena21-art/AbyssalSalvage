local Players = game:GetService("Players")
local Service = { LoadPriority = -30 }
local records, connections = {}, {}
local started = false
local transitions = {
    Active = { Unconscious = true },
    Unconscious = { Rescued = true },
    Rescued = { Active = true, Unconscious = true },
}
local function publish(player, record)
    player:SetAttribute("CrewState", record.state)
end
function Service.Register(player)
    if records[player] then return end
    local record = { state = "Active", links = {} }
    records[player] = record
    publish(player, record)
    local function attach(character)
        local hum = character:WaitForChild("Humanoid", 10)
        if not hum or records[player] ~= record or player.Character ~= character then return end
        if record.death then record.death:Disconnect() end
        record.state = "Active"
        publish(player, record)
        record.death = hum.Died:Connect(function()
            if records[player] == record then
                record.state = "Unconscious"
                publish(player, record)
            end
        end)
    end
    table.insert(record.links, player.CharacterAdded:Connect(attach))
    if player.Character then task.spawn(attach, player.Character) end
end
function Service.SetState(player, state)
    local record = records[player]
    if not record then return false, "Jugador no registrado" end
    if not transitions[record.state] or not transitions[record.state][state] then
        return false, "Transición de estado no permitida"
    end
    record.state = state
    publish(player, record)
    return true
end
function Service.GetState(player)
    return records[player] and records[player].state
end
local function remove(player)
    local record = records[player]
    if not record then return end
    for _, connection in record.links do connection:Disconnect() end
    if record.death then record.death:Disconnect() end
    records[player] = nil
end
function Service.Init() end
function Service.Start()
    if started then return end
    started = true
    table.insert(connections, Players.PlayerAdded:Connect(Service.Register))
    table.insert(connections, Players.PlayerRemoving:Connect(remove))
    for _, player in Players:GetPlayers() do Service.Register(player) end
    print("[AbyssalSalvage] M02: registro de jugadores listo")
end
function Service.Destroy()
    for _, c in connections do c:Disconnect() end
    table.clear(connections)
    for player in records do remove(player) end
    started = false
end
return Service