-- tests/color/test_gradient.lua : teste color/gradient.lua (le dégradé de couleurs des jours : conversions, couleurs de
-- 0 à 24 h, réglages, légende). Aucune dépendance à WezTerm. Lancer :   lua5.4 tests/color/test_gradient.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]color[/\\]test_gradient%.lua$") or "."

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
local gradient = load_module("color/gradient")
local convert = load_module("color/convert")

local passed, failed = 0, 0
local function check(name, got, want)
	if got == want then
		passed = passed + 1
	else
		failed = failed + 1
		print(string.format("ÉCHEC  %s\n         attendu : %s\n         obtenu  : %s", name, tostring(want), tostring(got)))
	end
end
local function near(a, b, tolerance)
	return math.abs(a - b) <= tolerance
end
local function strip(text)
	return (text:gsub("\27%[[%d;]*m", ""))
end
local function lightness(hex)
	local _, _, l = gradient.hex_to_hsl(hex)
	return l
end
local H = 3600

-- ============================================================
-- hex <-> HSL
-- ============================================================
local h, s, l = gradient.hex_to_hsl("#FF0000")
check("rouge pur : teinte 0, saturation 1, luminosité 0,5", h == 0 and s == 1 and l == 0.5, true)
h, s, l = gradient.hex_to_hsl("#00FF00")
check("vert pur : teinte 120", h, 120)
h = gradient.hex_to_hsl("#0000FF")
check("bleu pur : teinte 240", h, 240)
h, s, l = gradient.hex_to_hsl("#FFFFFF")
check("blanc : saturation 0, luminosité 1", s == 0 and l == 1, true)
h, s, l = gradient.hex_to_hsl("#000000")
check("noir : saturation 0, luminosité 0", s == 0 and l == 0, true)
h, s, l = gradient.hex_to_hsl("#808080")
check("gris : saturation 0 (pas de teinte)", s, 0)
h, s, l = gradient.hex_to_hsl("#C9AB6B")
check("l'or de la palette : teinte autour de 41", near(h, 41, 1), true)
check("l'or de la palette : saturation autour de 0,47", near(s, 0.47, 0.01), true)
check("l'or de la palette : luminosité autour de 0,60", near(l, 0.60, 0.01), true)
h = gradient.hex_to_hsl("c9ab6b")
check("sans dièse et en minuscules", near(h, 41, 1), true)
h, s, l = gradient.hex_to_hsl("n'importe quoi")
check("code invalide : traité comme du blanc, sans plantage", s == 0 and l == 1, true)
check("hsl vers hex : rouge", gradient.hsl_to_hex(0, 1, 0.5), "#FF0000")
check("hsl vers hex : vert", gradient.hsl_to_hex(120, 1, 0.5), "#00FF00")
check("hsl vers hex : bleu", gradient.hsl_to_hex(240, 1, 0.5), "#0000FF")
check("hsl vers hex : jaune", gradient.hsl_to_hex(60, 1, 0.5), "#FFFF00")
check("hsl vers hex : cyan", gradient.hsl_to_hex(180, 1, 0.5), "#00FFFF")
check("hsl vers hex : magenta", gradient.hsl_to_hex(300, 1, 0.5), "#FF00FF")
check("hsl vers hex : gris moyen", gradient.hsl_to_hex(0, 0, 0.5), "#808080")
check("hsl vers hex : blanc", gradient.hsl_to_hex(123, 0.5, 1), "#FFFFFF")
check("hsl vers hex : noir", gradient.hsl_to_hex(123, 0.5, 0), "#000000")
check("teinte de 360 = teinte de 0", gradient.hsl_to_hex(360, 1, 0.5), "#FF0000")
check("teinte négative : ramenée dans le cercle (-120 = 240)", gradient.hsl_to_hex(-120, 1, 0.5), "#0000FF")

local worst = 0
for r = 0, 255, 15 do
	for g = 0, 255, 15 do
		for b = 0, 255, 15 do
			local hex = string.format("#%02X%02X%02X", r, g, b)
			local back = gradient.hsl_to_hex(gradient.hex_to_hsl(hex))
			local r2, g2, b2 = convert.rgb(back)
			worst = math.max(worst, math.abs(r - r2), math.abs(g - g2), math.abs(b - b2))
		end
	end
end
check("aller-retour sur 4913 couleurs : jamais plus d'un cran d'écart par canal", worst <= 1, true)

-- ============================================================
-- make : les couleurs
-- ============================================================
local g = gradient.make({})
check("0 seconde : aucune couleur (transparent)", g.color(0), nil)
check("temps négatif : aucune couleur", g.color(-100), nil)
check("valeur absente : aucune couleur", g.color(nil), nil)
check("valeur qui n'est pas un nombre : aucune couleur", g.color("beaucoup"), nil)
check("valeur NaN : aucune couleur", g.color(0 / 0), nil)
check("1 seconde : une couleur", type(g.color(1)), "string")
check("le format est #RRGGBB en majuscules", g.color(2 * H):match("^#%x%x%x%x%x%x$") ~= nil and g.color(2 * H) == g.color(2 * H):upper(), true)

local previous = 2
local decreasing = true
for _, hours in ipairs({ 0.01, 0.1, 0.5, 1, 2, 3, 4, 6, 8, 10, 12, 16, 20, 24 }) do
	local lum = lightness(g.color(hours * H))
	if lum >= previous then
		decreasing = false
	end
	previous = lum
end
check("plus on travaille, plus la couleur est foncée (14 durées de 0,01 h à 24 h)", decreasing, true)
check("un jour très court : couleur claire (luminosité près de 0,80)", near(lightness(g.color(0.01 * H)), 0.80, 0.03), true)
check("24 h : couleur foncée (luminosité près de 0,30)", near(lightness(g.color(24 * H)), 0.30, 0.02), true)
check("au-delà de 24 h : toujours la même couleur foncée (30 h)", g.color(30 * H), g.color(24 * H))
check("au-delà de 24 h : toujours la même couleur foncée (1000 h)", g.color(1000 * H), g.color(24 * H))
check("avec la courbe par défaut, 12 h est à 0,446 de luminosité (racine carrée)", near(lightness(g.color(12 * H)), 0.446, 0.02), true)

local base_h, base_s = gradient.hex_to_hsl(gradient.DEFAULT_COLOR)
local hue_ok, sat_ok = true, true
for _, hours in ipairs({ 0.5, 1, 2, 4, 8, 12, 18, 24 }) do
	local ph, ps = gradient.hex_to_hsl(g.color(hours * H))
	if not near(ph, base_h, 3) then
		hue_ok = false
	end
	if not near(ps, base_s, 0.08) then
		sat_ok = false
	end
end
check("la teinte reste celle de la couleur de départ, de 0,5 h à 24 h", hue_ok, true)
check("la saturation reste celle de la couleur de départ (à l'arrondi près)", sat_ok, true)

-- une autre teinte
local blue = gradient.make({ color = "#3366CC" })
local bh = gradient.hex_to_hsl("#3366CC")
check("une autre couleur de départ donne une autre teinte (bleu)", near(gradient.hex_to_hsl(blue.color(8 * H)), bh, 3), true)
check("sans dièse : même résultat qu'avec", gradient.make({ color = "3366CC" }).color(8 * H), blue.color(8 * H))
check("code invalide : retour à l'or par défaut", gradient.make({ color = "bleu" }).color(8 * H), g.color(8 * H))
check("couleur absente : l'or par défaut", gradient.make().color(8 * H), g.color(8 * H))
check("couleur de type incorrect : l'or par défaut", gradient.make({ color = 42 }).color(8 * H), g.color(8 * H))

-- les réglages
local custom = gradient.make({ light = 0.9, dark = 0.1 })
check("light et dark réglés : jour très court", near(lightness(custom.color(0.01 * H)), 0.9, 0.03), true)
check("light et dark réglés : 24 h", near(lightness(custom.color(24 * H)), 0.1, 0.03), true)
check("light au-dessus de 1 : ramené à 1 (même couleur que light = 1)", gradient.make({ light = 2 }).color(H), gradient.make({ light = 1 }).color(H))
check("light = 1 : un jour très court est presque blanc", lightness(gradient.make({ light = 1 }).color(1)) > 0.99, true)
check("light en dessous de 0 : ramené à 0 (même couleur que light = 0)", gradient.make({ light = -1 }).color(H), gradient.make({ light = 0 }).color(H))
check("dark en dessous de 0 : ramené à 0 (noir)", gradient.make({ dark = -1 }).color(30 * H), "#000000")
check("light en texte : valeur par défaut", gradient.make({ light = "clair" }).color(8 * H), g.color(8 * H))
check("dark en texte : valeur par défaut", gradient.make({ dark = "sombre" }).color(8 * H), g.color(8 * H))
local short = gradient.make({ max_hours = 8 })
check("max_hours = 8 : 8 h donne déjà la couleur la plus foncée", short.color(8 * H), g.color(24 * H))
check("max_hours = 8 : 4 h est plus clair que 8 h", lightness(short.color(4 * H)) > lightness(short.color(8 * H)), true)
check("max_hours = 8 : au-delà, même couleur", short.color(50 * H), short.color(8 * H))
check("max_hours à 0 : ramené à une valeur minuscule, sans division par zéro", type(gradient.make({ max_hours = 0 }).color(H)), "string")
check("max_hours négatif : ramené au minimum, sans plantage", type(gradient.make({ max_hours = -5 }).color(H)), "string")
check("max_hours en texte : valeur par défaut (24)", gradient.make({ max_hours = "long" }).color(12 * H), g.color(12 * H))
local linear = gradient.make({ curve = 1 })
check("courbe linéaire (1) : 12 h est à mi-chemin (luminosité 0,55)", near(lightness(linear.color(12 * H)), 0.55, 0.02), true)
check("courbe linéaire : les premières heures se distinguent moins bien que par défaut", lightness(linear.color(1 * H)) > lightness(g.color(1 * H)), true)
check("courbe en texte : valeur par défaut", gradient.make({ curve = "courbe" }).color(12 * H), g.color(12 * H))
check("courbe à 0 : ramenée au minimum, sans plantage", type(gradient.make({ curve = 0 }).color(H)), "string")
check("courbe négative : ramenée au minimum, sans plantage", type(gradient.make({ curve = -3 }).color(H)), "string")
check("deux dégradés sont indépendants", gradient.make({ light = 0.9 }).color(H) ~= g.color(H), true)
check("déterministe", g.color(5 * H), gradient.make({}).color(5 * H))
local gray = gradient.make({ color = "#808080" })
check("une couleur grise donne un dégradé de gris", gray.color(8 * H):sub(2, 3) == gray.color(8 * H):sub(4, 5) and gray.color(8 * H):sub(4, 5) == gray.color(8 * H):sub(6, 7), true)

-- ============================================================
-- legend
-- ============================================================
local legend = g.legend()
local plain = strip(legend)
check("légende : commence par 0h", plain:sub(1, 3), "0h ")
check("légende : finit par 24h", plain:sub(-4), " 24h")
check("légende : huit blocs de deux carrés", select(2, plain:gsub("█", "")), 16)
check("légende : le premier bloc est le jour très court", legend:find(convert.fg(g.color(0.5 * H)) .. "██", 1, true) ~= nil, true)
check("légende : le dernier bloc est le plus foncé (24 h)", legend:find(convert.fg(g.color(24 * H)) .. "██" .. convert.RESET .. " 24h", 1, true) ~= nil, true)
check("légende : une couleur de texte (pas de fond) pour chaque bloc", select(2, legend:gsub("\27%[38;2;", "")), 8)
check("légende : avec max_hours = 12", strip(gradient.make({ max_hours = 12 }).legend()):sub(-4), " 12h")
check("légende : les blocs foncent de gauche à droite", (function()
	local colors = {}
	for code in legend:gmatch("\27%[38;2;(%d+;%d+;%d+)m") do
		local r, gg, b = code:match("(%d+);(%d+);(%d+)")
		colors[#colors + 1] = tonumber(r) + tonumber(gg) + tonumber(b)
	end
	for i = 2, #colors do
		if colors[i] >= colors[i - 1] then
			return false
		end
	end
	return #colors == 8
end)(), true)

-- ============================================================
-- effets de bord
-- ============================================================
local leaked = {}
for k in pairs(_G) do
	if not globals_before[k] then
		leaked[#leaked + 1] = k
	end
end
check("aucune variable globale ajoutée", table.concat(leaked, ","), "")

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
