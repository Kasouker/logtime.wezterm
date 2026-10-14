-- plugin/logtime/color/palette.lua : les seize couleurs proposées dans la page de personnalisation (numérotées de 1 à 16).
-- Ce sont des teintes réparties sur le cercle des couleurs, avec la même saturation et la même luminosité que l'or par défaut
-- (le dégradé en garde la teinte et la saturation) ; la dernière est un gris. Les noms sont dans les fichiers de textes
-- (i18n/fr.lua et i18n/en.lua : labels.palette, dans le même ordre).
-- Aucune dépendance à WezTerm : se teste avec un simple interpréteur Lua.
local load = ...
local gradient = load("color/gradient")

local M = {}

M.COLORS = {
	"#C96969", -- 1 rouge
	"#C98C69", -- 2 orange
	"#C9AB6B", -- 3 or (la couleur par défaut)
	"#C9C169", -- 4 jaune
	"#A9C969", -- 5 citron
	"#69C969", -- 6 vert
	"#69C999", -- 7 émeraude
	"#69C9C1", -- 8 turquoise
	"#69B9C9", -- 9 cyan
	"#69A1C9", -- 10 ciel
	"#6989C9", -- 11 bleu
	"#7969C9", -- 12 indigo
	"#A169C9", -- 13 violet
	"#C969C9", -- 14 magenta
	"#C96999", -- 15 rose
	"#999999", -- 16 gris
}
M.COUNT = #M.COLORS
M.DEFAULT_INDEX = 3

local function normalize(hex)
	if type(hex) == "string" and hex:match("^#?%x%x%x%x%x%x$") then
		return "#" .. hex:gsub("^#", ""):upper()
	end
	return nil
end

M.normalize = normalize

-- Le numéro de cette couleur dans la palette (nil si elle n'y est pas). Majuscules, minuscules et # facultatif sont acceptés.
-- colors : une autre liste de couleurs (la palette du thème) ; la palette classique par défaut.
function M.index_of(hex, colors)
	local wanted = normalize(hex)
	if not wanted then
		return nil
	end
	for i, color in ipairs(colors or M.COLORS) do
		if color == wanted then
			return i
		end
	end
	return nil
end

-- Le numéro de la couleur la plus proche dans la palette, ou nil si ce n'est pas une couleur.
-- Un gris (peu saturé) va au gris le plus proche en luminosité ; une couleur va à la teinte la plus proche. Avec la palette
-- classique, le gris est la couleur 16. colors : une autre liste de couleurs (la palette du thème).
function M.nearest(hex, colors)
	local wanted = normalize(hex)
	if not wanted then
		return nil
	end
	colors = colors or M.COLORS
	local hue, saturation, lightness = gradient.hex_to_hsl(wanted)
	local gray = saturation < 0.12
	local pool = {}
	for i, color in ipairs(colors) do
		local h, s, l = gradient.hex_to_hsl(color)
		if (s < 0.12) == gray then
			pool[#pool + 1] = { index = i, hue = h, lightness = l }
		end
	end
	if #pool == 0 then
		for i, color in ipairs(colors) do
			local h, _, l = gradient.hex_to_hsl(color)
			pool[#pool + 1] = { index = i, hue = h, lightness = l }
		end
	end
	local best, best_distance
	for _, candidate in ipairs(pool) do
		local d
		if gray then
			d = math.abs(lightness - candidate.lightness)
		else
			d = math.abs(hue - candidate.hue)
			d = math.min(d, 360 - d)
		end
		if best_distance == nil or d < best_distance then
			best, best_distance = candidate.index, d
		end
	end
	return best
end

return M
