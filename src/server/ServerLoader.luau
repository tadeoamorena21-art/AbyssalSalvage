-- src/server/ServerLoader.luau

local RunService = game:GetService("RunService")

export type Service = {
	Init: (self: Service) -> (),
	Start: (self: Service) -> (),
}
type Entry = { source: ModuleScript, path: string, priority: number }
type Loaded = { service: Service, path: string }
local used = false
local ServerLoader = {}

local function traceback(message: any): string
	return debug.traceback(tostring(message), 2)
end

local function invoke(entry: Loaded, phase: "Init" | "Start")
	local success, message = xpcall(function()
		if phase == "Init" then entry.service:Init() else entry.service:Start() end
	end, traceback)
	if not success then error(string.format("%s.%s falló:\n%s", entry.path, phase, tostring(message)), 0) end
end

-- Cada ModuleScript descendiente es un servicio; auxiliares fuera de Services.
-- Atributo numérico LoadPriority ascendente (predeterminado 0), luego ruta.
-- require sin efectos secundarios. Init/Start deben finalizar; bucles con task.spawn.
-- Init prepara referencias y estado; Start puede consumir servicios inicializados.
function ServerLoader.Run(root: Folder): number
	assert(RunService:IsServer(), "ServerLoader solo se ejecuta en servidor")
	assert(not used, "ServerLoader ya fue ejecutado; reiniciar sesión tras un fallo")
	used = true
	local entries: { Entry } = {}
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("ModuleScript") then
			local raw = descendant:GetAttribute("LoadPriority")
			local priority = 0
			if raw ~= nil then
				assert(typeof(raw) == "number", descendant:GetFullName() .. ": LoadPriority debe ser numérico")
				priority = raw :: number
				assert(priority == priority and math.abs(priority) < math.huge, "LoadPriority debe ser finito")
			end
			table.insert(entries, { source = descendant, path = descendant:GetFullName(), priority = priority })
		end
	end
	local paths: { [string]: boolean } = {}
	for _, entry in entries do
		assert(not paths[entry.path], "Ruta duplicada: " .. entry.path)
		paths[entry.path] = true
	end
	table.sort(entries, function(a: Entry, b: Entry): boolean
		if a.priority == b.priority then return a.path < b.path end
		return a.priority < b.priority
	end)
	local loaded: { Loaded } = {}
	for _, entry in entries do
		local success, result = xpcall(function(): any
			return require(entry.source)
		end, traceback)
		if not success then error(entry.path .. ": require falló\n" .. tostring(result), 0) end
		assert(type(result) == "table", entry.path .. " debe devolver una tabla")
		assert(type(result.Init) == "function", entry.path .. " necesita Init(self)")
		assert(type(result.Start) == "function", entry.path .. " necesita Start(self)")
		table.insert(loaded, { service = result :: Service, path = entry.path })
	end
	for _, entry in loaded do invoke(entry, "Init") end
	for _, entry in loaded do invoke(entry, "Start") end
	return #loaded
end

return table.freeze(ServerLoader)
