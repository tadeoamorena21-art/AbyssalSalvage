--!strict
-- src/shared/Config.luau

return table.freeze({
	Meta = table.freeze({ Version = "0.1.0-mvp", Tag = "[AbyssalSalvage]" }),
	Tripulacion = table.freeze({
		MaxPlayers = 4, -- Configurar también el límite del lugar en Roblox.
		Clases = table.freeze({ "Piloto", "Tecnico", "Sonarista", "Buzo" }),
	}),
	-- Valores iniciales de balance; deberán validarse mediante pruebas.
	Expedicion = table.freeze({ DuracionBase = 720, ProfundidadMaximaBioma1 = 500 }),
	Submarino = table.freeze({ CascoBase = 100, EnergiaBase = 100, OxigenoBase = 100 }),
	Camara = table.freeze({ FOVInterior = 75, FOVExterior = 80, DistanciaTercera = 12 }),
	Logging = table.freeze({ MinLevel = 2 }),
	Network = table.freeze({ Timeout = 10, ReadyTimeout = 60, HandshakeInterval = 1 }),
})
