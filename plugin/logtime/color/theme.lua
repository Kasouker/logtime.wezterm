-- plugin/logtime/color/theme.lua : les seize couleurs du thème de l'utilisateur : les 8 couleurs ANSI (noir, rouge, vert,
-- jaune, bleu, magenta, cyan, blanc) puis les 8 couleurs « vives », dans cet ordre.
-- On ne lit PAS le fichier appearance.lua : quand le plugin s'applique (après appearance.apply(config)), les couleurs du thème
-- sont déjà dans la configuration de WezTerm : soit par color_scheme (un thème intégré ou défini dans config.color_schemes),
-- soit par config.colors, qui complète ou remplace le thème couleur par couleur (c'est la règle de WezTerm).
-- Aucune dépendance à WezTerm : se teste avec une fausse configuration.
local load = ...
local palette = load("color/palette")

local M = {}

local function field(table_, key)
	local ok, value = pcall(function()
		return table_[key]
	end)
	if ok then
		return value
	end
	return nil
end

local function builtin_scheme(wezterm, name)
	if type(wezterm) ~= "table" then
		return nil
	end
	for _, lookup in ipairs({
		function()
			return wezterm.color.get_builtin_schemes()
		end,
		function()
			return wezterm.get_builtin_color_schemes()
		end,
	}) do
		local ok, schemes = pcall(lookup)
		if ok and type(schemes) == "table" and type(schemes[name]) == "table" then
			return schemes[name]
		end
	end
	return nil
end

-- Renvoie la liste des 16 couleurs ("#RRGGBB", majuscules) et le nom du thème utilisé (ou nil), ou bien nil et la raison
-- en français si les couleurs du thème ne sont pas toutes connues.
--   config  : la configuration de WezTerm, après appearance.lua
--   wezterm : le module wezterm (pour les thèmes intégrés ; facultatif)
function M.extract(config, wezterm)
	if type(config) ~= "table" then
		return nil, "the WezTerm configuration was not found"
	end
	local ansi, brights = {}, {}
	local name = field(config, "color_scheme")
	local scheme_name
	if type(name) == "string" and name ~= "" then
		local custom = field(config, "color_schemes")
		local scheme = (type(custom) == "table" and type(field(custom, name)) == "table" and custom[name])
			or builtin_scheme(wezterm, name)
		if scheme then
			scheme_name = name
			for i = 1, 8 do
				ansi[i] = field(field(scheme, "ansi") or {}, i)
				brights[i] = field(field(scheme, "brights") or {}, i)
			end
		end
	end
	local colors = field(config, "colors")
	if type(colors) == "table" then
		for i = 1, 8 do
			local a, b = field(field(colors, "ansi") or {}, i), field(field(colors, "brights") or {}, i)
			if a ~= nil then
				ansi[i] = a
			end
			if b ~= nil then
				brights[i] = b
			end
		end
	end
	local out = {}
	for i = 1, 8 do
		out[i] = palette.normalize(ansi[i])
		out[8 + i] = palette.normalize(brights[i])
	end
	for i = 1, 16 do
		if not out[i] then
			if type(name) == "string" and name ~= "" and not scheme_name then
				return nil,
					'the color scheme "'
						.. name
						.. '" cannot be read by the plugin (neither built in nor in config.color_schemes)'
			end
			return nil, "the color scheme does not define all 16 ANSI colors (color " .. i .. " is missing)"
		end
	end
	return out, scheme_name
end

return M
