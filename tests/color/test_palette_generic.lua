-- tests/color/test_palette_generic.lua : teste que color/palette.lua cherche une couleur (index_of, nearest) dans n'importe
-- quelle liste de couleurs (la palette du thème), et que la palette classique reste la valeur par défaut.
-- Lancer :   lua5.4 tests/color/test_palette_generic.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]color[/\\]test_palette_generic%.lua$") or "."

local globals_before = {}
for k in pairs(_G) do
	globals_before[k] = true
end
local cache = {}
local function load_module(name)
	if not cache[name] then
		local chunk = assert(loadfile(root .. "/plugin/logtime/" .. name .. ".lua"))
		cache[name] = chunk(load_module)
	end
	return cache[name]
end
local palette = load_module("color/palette")
local gradient = load_module("color/gradient")

local passed, failed = 0, 0
local function check(name, got, want)
	if got == want then
		passed = passed + 1
	else
		failed = failed + 1
		print(
			string.format(
				"ÉCHEC  %s\n         attendu : %s\n         obtenu  : %s",
				name,
				tostring(want),
				tostring(got)
			)
		)
	end
end

-- un thème : 4 gris (1, 8, 9, 16) et 12 couleurs ; les vives (9 à 16) ont les mêmes teintes que les normales (1 à 8)
local THEME = {
	"#1E1E1E",
	"#CC3333",
	"#33CC33",
	"#CCCC33",
	"#3333CC",
	"#CC33CC",
	"#33CCCC",
	"#CCCCCC",
	"#555555",
	"#FF5555",
	"#55FF55",
	"#FFFF55",
	"#5555FF",
	"#FF55FF",
	"#55FFFF",
	"#FFFFFF",
}

-- ---- index_of
check("index_of dans le thème : exact", palette.index_of("#CC3333", THEME), 2)
check("index_of dans le thème : minuscules", palette.index_of("#cc3333", THEME), 2)
check("index_of dans le thème : sans dièse", palette.index_of("FF5555", THEME), 10)
check("index_of dans le thème : absente", palette.index_of("#123456", THEME), nil)
check(
	"index_of dans le thème : une couleur de la palette classique n'y est pas",
	palette.index_of(palette.COLORS[3], THEME),
	nil
)
check("index_of sans liste : la palette classique", palette.index_of(palette.COLORS[3]), 3)
check("index_of avec nil : la palette classique", palette.index_of(palette.COLORS[11], nil), 11)
check("index_of dans une liste vide", palette.index_of("#CC3333", {}), nil)
check("index_of : pas une couleur", palette.index_of("rouge", THEME), nil)
local DOUBLE = { "#AAAAAA", "#CC3333", "#CC3333" }
check("index_of avec une couleur en double : la première", palette.index_of("#CC3333", DOUBLE), 2)

-- ---- nearest : les couleurs
check(
	"nearest dans le thème : chaque gris du thème est trouvé lui-même, chaque couleur trouve une couleur de même teinte",
	(function()
		for i, color in ipairs(THEME) do
			local found = palette.nearest(color, THEME)
			local h, s = gradient.hex_to_hsl(color)
			if s < 0.12 then
				if found ~= i then
					return false
				end
			else
				local found_hue = gradient.hex_to_hsl(THEME[found])
				if math.abs(found_hue - h) > 0.5 then
					return false
				end
			end
		end
		return true
	end)(),
	true
)
check("nearest dans le thème : un rouge", palette.nearest("#DD4444", THEME), 2)
check("nearest dans le thème : un bleu", palette.nearest("#2222DD", THEME), 5)
check("nearest dans le thème : un vert", palette.nearest("#22DD22", THEME), 3)
check(
	"nearest dans le thème : un jaune orangé (teinte 45) est plus près du jaune (60) que du rouge (0)",
	palette.nearest(gradient.hsl_to_hex(45, 0.6, 0.5), THEME),
	4
)
check(
	"nearest dans le thème : la teinte 350 est plus près du rouge",
	palette.nearest(gradient.hsl_to_hex(350, 0.6, 0.5), THEME),
	2
)
check(
	"nearest dans le thème : la teinte 320 est plus près du magenta (300)",
	palette.nearest(gradient.hsl_to_hex(320, 0.6, 0.5), THEME),
	6
)
check(
	"nearest dans le thème : à égalité, la première (rouge normal avant rouge vif)",
	palette.nearest("#EE4444", THEME),
	2
)
check(
	"nearest dans le thème : un jaune d'or (l'or du plugin, teinte 41) : le jaune",
	palette.nearest(palette.COLORS[3], THEME),
	4
)
-- ---- nearest : les gris vont au gris le plus proche en luminosité
check("nearest dans le thème : un gris moyen va au gris 9 (#555555)", palette.nearest("#808080", THEME), 9)
check("nearest dans le thème : un gris très clair va au blanc vif (16)", palette.nearest("#F0F0F0", THEME), 16)
check("nearest dans le thème : un gris très foncé va au noir (1)", palette.nearest("#101010", THEME), 1)
check("nearest dans le thème : un gris clair va au gris clair (8)", palette.nearest("#C0C0C0", THEME), 8)
check("nearest dans le thème : le blanc va au blanc vif", palette.nearest("#FFFFFF", THEME), 16)
check("nearest dans le thème : le noir va au noir", palette.nearest("#000000", THEME), 1)
-- ---- nearest : cas limites
local ONLY_COLORS = { "#CC3333", "#33CC33", "#3333CC" }
check("nearest : une couleur dans une palette sans gris", palette.nearest("#DD4444", ONLY_COLORS), 1)
check(
	"nearest : un gris dans une palette sans gris : le plus proche en luminosité",
	palette.nearest("#808080", ONLY_COLORS) ~= nil,
	true
)
local ONLY_GRAYS = { "#111111", "#888888", "#EEEEEE" }
check(
	"nearest : une couleur dans une palette de gris seulement : une réponse, sans plantage",
	palette.nearest("#DD4444", ONLY_GRAYS) ~= nil,
	true
)
check("nearest : un gris dans une palette de gris : le plus proche", palette.nearest("#8A8A8A", ONLY_GRAYS), 2)
check("nearest : liste vide", palette.nearest("#DD4444", {}), nil)
check("nearest : pas une couleur", palette.nearest("rouge", THEME), nil)
check("nearest : nil", palette.nearest(nil, THEME), nil)
check("nearest : une seule couleur", palette.nearest("#DD4444", { "#33CC33" }), 1)
-- ---- la palette classique est toujours la valeur par défaut, inchangée
check("nearest sans liste : la palette classique (bleu)", palette.nearest("#3366CC"), 11)
check("nearest sans liste : le gris va au gris (16)", palette.nearest("#808080"), 16)
check(
	"nearest avec la palette classique donnée explicitement : pareil",
	palette.nearest("#3366CC", palette.COLORS),
	11
)
local same = true
for hue = 0, 359, 7 do
	local color = gradient.hsl_to_hex(hue, 0.6, 0.5)
	if palette.nearest(color) ~= palette.nearest(color, palette.COLORS) then
		same = false
	end
end
check("52 teintes : explicite ou par défaut, même résultat", same, true)

local leaked = {}
for k in pairs(_G) do
	if not globals_before[k] then
		leaked[#leaked + 1] = k
	end
end
check("aucune variable globale ajoutée", table.concat(leaked, ","), "")

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
