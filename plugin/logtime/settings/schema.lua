-- plugin/logtime/settings/schema.lua : la liste des réglages que l'utilisateur peut choisir (dans le fichier de
-- réglages, et plus tard dans la page de personnalisation), avec pour chacun ce qu'il accepte et sa valeur par défaut.
-- Aucune dépendance à WezTerm : se teste avec un simple interpréteur Lua.
local M = {}

-- kind : "enum" (une valeur parmi une liste), "boolean", "color" (#RRGGBB), "number", "integer" (nombre entier).
-- default = nil : pas de valeur par défaut (le réglage est simplement absent, comme goal_hours).
-- none : une valeur acceptée en plus des limites, qui veut dire « aucun » (goal_hours = 0 : pas d'objectif). Elle peut
-- être écrite dans le fichier de réglages, et l'emporte alors sur la valeur de wezterm.lua.
-- step : de combien la valeur change à chaque appui sur ← ou → dans la page de personnalisation (1 par défaut).
M.DEFINITIONS = {
	{ key = "lang", kind = "enum", values = { "fr", "en" }, default = "en" },
	{ key = "week_starts_on", kind = "enum", values = { "monday", "sunday" }, default = "monday" },
	{ key = "goal_hours", kind = "number", min = 0.5, max = 24, default = nil, none = 0, step = 0.5 },
	{ key = "goal_days", kind = "integer", min = 1, max = 7, default = 5 },
	{ key = "count_idle", kind = "boolean", default = true },
	{ key = "max_months", kind = "integer", min = 1, max = 12, default = 12 },
	{ key = "months_anchor", kind = "enum", values = { "last", "first" }, default = "last" },
	{ key = "center", kind = "boolean", default = true },
	{ key = "borders", kind = "boolean", default = false },
	{ key = "border_style", kind = "enum", values = { "rounded", "single", "double", "heavy" }, default = "rounded" },
	{ key = "border_color", kind = "color", default = "#8B8E99" },
	{ key = "gradient", kind = "boolean", default = true },
	{ key = "gradient_color", kind = "color", default = "#C9AB6B" },
	{ key = "gradient_light", kind = "number", min = 0, max = 1, default = 0.8 },
	{ key = "gradient_dark", kind = "number", min = 0, max = 1, default = 0.3 },
	{ key = "gradient_hours", kind = "number", min = 1, max = 48, default = 24 },
	{ key = "gradient_curve", kind = "number", min = 0.1, max = 3, default = 0.5 },
	{ key = "theme_colors", kind = "boolean", default = nil },
	{ key = "show_timeline", kind = "boolean", default = true },
}

local BY_KEY = {}
for _, definition in ipairs(M.DEFINITIONS) do
	BY_KEY[definition.key] = definition
end

-- La liste des noms de réglages, dans l'ordre de la définition.
function M.keys()
	local out = {}
	for _, definition in ipairs(M.DEFINITIONS) do
		out[#out + 1] = definition.key
	end
	return out
end

function M.is_known(key)
	return BY_KEY[key] ~= nil
end

-- La définition d'un réglage (nil s'il n'existe pas).
function M.get(key)
	return BY_KEY[key]
end

-- Les valeurs par défaut (sans les réglages qui n'en ont pas).
function M.defaults()
	local out = {}
	for _, definition in ipairs(M.DEFINITIONS) do
		if definition.default ~= nil then
			out[definition.key] = definition.default
		end
	end
	return out
end

local function quoted(list)
	local parts = {}
	for i, value in ipairs(list) do
		parts[i] = '"' .. value .. '"'
	end
	return table.concat(parts, " or ")
end

-- Vérifie une valeur. Renvoie true et la valeur normalisée (couleur en majuscules avec #, entier sans décimale),
-- ou false et la raison en français.
function M.validate(key, value)
	local definition = BY_KEY[key]
	if not definition then
		return false, "unknown setting"
	end
	local kind = definition.kind
	if kind == "enum" then
		for _, allowed in ipairs(definition.values) do
			if value == allowed then
				return true, value
			end
		end
		return false, "must be " .. quoted(definition.values)
	elseif kind == "boolean" then
		if type(value) == "boolean" then
			return true, value
		end
		return false, "must be true or false"
	elseif kind == "color" then
		if type(value) == "string" and value:match("^#?%x%x%x%x%x%x$") then
			return true, "#" .. value:gsub("^#", ""):upper()
		end
		return false, 'must be a color code like "#C9AB6B"'
	end
	-- number ou integer
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return false, "must be a number"
	end
	if definition.none ~= nil and value == definition.none then
		return true, math.tointeger(value) or value
	end
	if kind == "integer" and value ~= math.floor(value) then
		return false, "must be a whole number"
	end
	if value < definition.min or value > definition.max then
		return false, string.format("must be between %g and %g", definition.min, definition.max)
	end
	if kind == "integer" then
		return true, math.tointeger(value)
	end
	return true, value
end

return M
