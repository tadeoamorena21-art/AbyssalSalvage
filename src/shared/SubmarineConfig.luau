-- Destino: src/shared/SubmarineConfig.luau
-- Valores iniciales del prototipo; se calibran en las pruebas P1.
local Config = {
    ModelName = "Submarine",
    SeatName = "PilotSeat",
    RemoteName = "SubmarineControl_v1",
    ForwardSpeed = 28,
    ReverseSpeed = 12,
    VerticalSpeed = 10,
    TurnSpeed = math.rad(35),
    Acceleration = 8,
    Braking = 12,
    OrientationResponsiveness = 12,
    MaxAngularVelocity = math.rad(60),
    ForcePerMass = 500,
    TorquePerMass = 100000,
    SendInterval = 0.1,
    InputTimeout = 0.5,
    PacketBurst = 4,
    PacketsPerSecond = 20,
}
return table.freeze(Config)
