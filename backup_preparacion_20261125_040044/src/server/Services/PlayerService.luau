local Players = game:GetService("Players")

local Service = { LoadPriority = -30 }

type PlayerRecord = {
    state: string,
    links: { RBXScriptConnection },
    death: RBXScriptConnection?,
}

local records: { [Player]: PlayerRecord } = {}
local connections: { RBXScriptConnection } = {}
local started = false
local transitions: { [string]: { [string]: boolean } } = {
    Active = { Unconscious = true },
    Unconscious = { Rescued = true },
    Rescued = { Active = true, Unconscious = true },
}

local function publish(player: Player, record: PlayerRecord)
    player:SetAttribute("CrewState", record.state)
end

function Service.Register(player: Player)
    if records[player] then return end
    local record: PlayerRecord = { state = "Active", links = {}, death = nil }
    records[player] = record
    publish(player, record)

    local function attach(character: Model)
        local hum = character:WaitForChild("Humanoid", 10)
        if not hum or not hum:IsA("Humanoid") then return end
        if records[player] ~= record or player.Character ~= character then return end

        local previousDeath = record.death
        if previousDeath then previousDeath:Disconnect() end
        record.death = nil
        record.state = "Active"
        publish(player, record)
        record.death = hum.Died:Connect(function()
            if records[player] == record and player.Character == character then
                record.state = "Unconscious"
                publish(player, record)
            end
        end)
    end

    table.insert(record.links, player.CharacterAdded:Connect(attach))
    local character = player.Character
    if character then task.spawn(attach, character) end
end

function Service.SetState(player: Player, state: string)
    local record = records[player]
    if not record then return false, "Jugador no registrado" end
    local allowed = transitions[record.state]
    if not allowed or not allowed[state] then
        return false, "Transición de estado no permitida"
    end
    record.state = state
    publish(player, record)
    return true
end

function Service.GetState(player: Player): string?
    local record = records[player]
    return if record then record.state else nil
end

local function remove(player: Player)
    local record = records[player]
    if not record then return end
    for _, connection in record.links do connection:Disconnect() end
    local deathConnection = record.death
    if deathConnection then deathConnection:Disconnect() end
    record.death = nil
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
    for _, connection in connections do connection:Disconnect() end
    table.clear(connections)
    for player in records do remove(player) end
    started = false
end

return Service
