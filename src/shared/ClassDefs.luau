local Defs = {}
Defs.Order = { "Pilot", "Technician", "Sonarist", "Diver" }
Defs.Names = {
    Pilot = "Piloto",
    Technician = "Técnico",
    Sonarist = "Sonarista",
    Diver = "Buzo",
}
Defs.MaxCrew = 4
-- Reserva en el MISMO servidor vivo; no es guardado persistente.
Defs.ReconnectSeconds = 120
return Defs