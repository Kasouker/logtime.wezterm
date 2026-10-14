-- tests/color/test_palette.lua : teste color/palette.lua (les seize couleurs numérotées de la page de personnalisation) et
-- leurs noms français et anglais. Aucune dépendance à WezTerm. Lancer :   lua5.4 tests/color/test_palette.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]color[/\\]test_palette%.lua$") or "."

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
local schema = load_module("settings/schema")
local fr = load_module("i18n/fr")
local en = load_module("i18n/en")

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
local function near(a, b, tolerance)
	return math.abs(a - b) <= tolerance
end

-- ---- la liste
check("seize couleurs", #palette.COLORS, 16)
check("COUNT = 16", palette.COUNT, 16)
check("la couleur par défaut est la numéro 3", palette.DEFAULT_INDEX, 3)
check("la numéro 3 est l'or par défaut du dégradé", palette.COLORS[3], gradient.DEFAULT_COLOR)
check(
	"la numéro 3 est la valeur par défaut du schéma des réglages",
	palette.COLORS[3],
	schema.defaults().gradient_color
)

local seen, all_format, all_valid = {}, true, true
for i, color in ipairs(palette.COLORS) do
	if not color:match("^#%x%x%x%x%x%x$") or color ~= color:upper() then
		all_format = false
	end
	if seen[color] then
		all_valid = false
	end
	seen[color] = true
	if not schema.validate("gradient_color", color) then
		all_valid = false
	end
end
check("toutes au format #RRGGBB en majuscules", all_format, true)
check("toutes différentes, et toutes acceptées par le schéma des réglages", all_valid, true)

-- ---- teintes réparties sur le cercle, même saturation et même luminosité que l'or
local hues = { 0, 22, 41, 55, 80, 120, 150, 175, 190, 205, 220, 250, 275, 300, 330 }
local shape_ok = true
for i, hue in ipairs(hues) do
	local h, s, l = gradient.hex_to_hsl(palette.COLORS[i])
	if not (near(h, hue, 2) and near(s, 0.47, 0.03) and near(l, 0.60, 0.03)) then
		shape_ok = false
		print("   la couleur " .. i .. " s'écarte : " .. string.format("%.1f %.2f %.2f", h, s, l))
	end
end
check("couleurs 1 à 15 : la teinte annoncée, avec la saturation et la luminosité de l'or", shape_ok, true)
local _, gray_saturation = gradient.hex_to_hsl(palette.COLORS[16])
check("la numéro 16 est un gris", gray_saturation, 0)
local increasing = true
for i = 2, #hues do
	if hues[i] <= hues[i - 1] then
		increasing = false
	end
end
check("les teintes sont rangées dans l'ordre du cercle", increasing, true)

-- ---- normalize
check("normalize : majuscules et dièse", palette.normalize("c9ab6b"), "#C9AB6B")
check("normalize : déjà normalisé", palette.normalize("#C9AB6B"), "#C9AB6B")
check("normalize : pas une couleur", palette.normalize("rouge"), nil)
check("normalize : nil", palette.normalize(nil), nil)
check("normalize : un nombre", palette.normalize(123456), nil)

-- ---- index_of
for i, color in ipairs(palette.COLORS) do
	if palette.index_of(color) ~= i then
		check("index_of : la couleur " .. i, palette.index_of(color), i)
	end
end
check("index_of : minuscules", palette.index_of("#c9ab6b"), 3)
check("index_of : sans dièse", palette.index_of("6989C9"), 11)
check("index_of : une couleur absente de la palette", palette.index_of("#123456"), nil)
check("index_of : pas une couleur", palette.index_of("bleu"), nil)
check("index_of : nil", palette.index_of(nil), nil)
check("index_of : un nombre", palette.index_of(42), nil)

-- ---- nearest
local own = true
for i, color in ipairs(palette.COLORS) do
	if palette.nearest(color) ~= i then
		own = false
	end
end
check("nearest : chaque couleur de la palette est la plus proche d'elle-même", own, true)
check("nearest : un bleu vif proche du 11", palette.nearest("#3366CC"), 11)
check("nearest : un rouge foncé (teinte 0)", palette.nearest("#8B0000"), 1)
check("nearest : un rouge un peu rosé (teinte 350) : le rouge", palette.nearest(gradient.hsl_to_hex(350, 0.5, 0.5)), 1)
check("nearest : une teinte 340 : le rose (330)", palette.nearest(gradient.hsl_to_hex(340, 0.5, 0.5)), 15)
check("nearest : un vert (teinte 125)", palette.nearest(gradient.hsl_to_hex(125, 0.6, 0.4)), 6)
check("nearest : un gris moyen va au gris", palette.nearest("#808080"), 16)
check("nearest : un gris clair va au gris", palette.nearest("#EEEEEE"), 16)
check("nearest : le blanc va au gris", palette.nearest("#FFFFFF"), 16)
check("nearest : le noir va au gris", palette.nearest("#000000"), 16)
check("nearest : une couleur très peu saturée va au gris", palette.nearest(gradient.hsl_to_hex(220, 0.10, 0.5)), 16)
check("nearest : un peu plus saturée garde sa teinte (bleu)", palette.nearest(gradient.hsl_to_hex(220, 0.13, 0.5)), 11)
check("nearest : sans dièse et en minuscules", palette.nearest("3366cc"), 11)
check("nearest : pas une couleur", palette.nearest("bleu"), nil)
check("nearest : nil", palette.nearest(nil), nil)
local never_gray_by_hue = true
for hue = 0, 359, 5 do
	local index = palette.nearest(gradient.hsl_to_hex(hue, 0.6, 0.5))
	if not index or index < 1 or index > 15 then
		never_gray_by_hue = false
	end
end
check("nearest : 72 teintes vives donnent toujours une couleur de 1 à 15", never_gray_by_hue, true)

-- ---- les noms, dans les deux langues
for name, labels in pairs({ ["français"] = fr, ["anglais"] = en }) do
	check("noms " .. name .. " : seize noms", type(labels.palette) == "table" and #labels.palette, 16)
	local unique, short, filled = {}, true, true
	for _, color_name in ipairs(labels.palette or {}) do
		if type(color_name) ~= "string" or #color_name == 0 then
			filled = false
		else
			if unique[color_name] then
				filled = false
			end
			unique[color_name] = true
			if utf8.len(color_name) > 11 then
				short = false
			end
		end
	end
	check("noms " .. name .. " : tous remplis et différents", filled, true)
	check("noms " .. name .. " : au plus 11 caractères (la largeur d'une couleur)", short, true)
end
check("le nom de la couleur 3 en français", fr.palette[3], "Or")
check("le nom de la couleur 3 en anglais", en.palette[3], "Gold")
check("le nom de la couleur 16 en français", fr.palette[16], "Gris")

local leaked = {}
for k in pairs(_G) do
	if not globals_before[k] then
		leaked[#leaked + 1] = k
	end
end
check("aucune variable globale ajoutée", table.concat(leaked, ","), "")

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
