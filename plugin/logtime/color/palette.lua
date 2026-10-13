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
function M.index_of(hex)
	local wanted = normalize(hex)
	if not wanted then
		return nil
	end
	for i, color in ipairs(M.COLORS) do
		if color == wanted then
			return i
		end
	end
	return nil
end

-- Le numéro de la couleur de la palette la plus proche (par la teinte ; un gris va au gris). nil si ce n'est pas une couleur.
function M.nearest(hex)
local wanted = normalize(hex)
if not wanted then
return nil
end
local hue, saturation = gradient.hex_to_hsl(wanted)
if saturation < 0.12 then
return M.COUNT
end
local best, best_distance
for i = 1, M.COUNT - 1 do
local candidate = gradient.hex_to_hsl(M.COLORS[i])
local d = math.abs(hue - candidate)
d = math.min(d, 360 - d)
if best_distance == nil or d < best_distance then
best, best_distance = i, d
end
end
return best
end

return M
