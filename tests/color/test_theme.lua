-- tests/color/test_theme.lua : teste color/theme.lua (les seize couleurs du thème lues dans la configuration de WezTerm)
-- avec de fausses configurations, et les noms des couleurs du thème. Lancer :   lua5.4 tests/color/test_theme.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]color[/\\]test_theme%.lua$") or "."

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
local theme = load_module("color/theme")
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
local function join(list)
	local out = {}
	for i = 1, 16 do
		out[i] = tostring(list and list[i])
	end
	return table.concat(out, ",")
end
local function copy(list)
	local out = {}
	for i, v in ipairs(list) do
		out[i] = v
	end
	return out
end

local ANSI = { "#1E1E1E", "#CC3333", "#33CC33", "#CCCC33", "#3333CC", "#CC33CC", "#33CCCC", "#CCCCCC" }
local BRIGHTS = { "#555555", "#FF5555", "#55FF55", "#FFFF55", "#5555FF", "#FF55FF", "#55FFFF", "#FFFFFF" }
local EXPECTED = {}
for i = 1, 8 do
	EXPECTED[i], EXPECTED[8 + i] = ANSI[i], BRIGHTS[i]
end
local EXPECTED_TEXT = join(EXPECTED)

-- ---- les couleurs viennent de config.colors
local colors, scheme_name = theme.extract({ colors = { ansi = ANSI, brights = BRIGHTS } })
check("config.colors : les seize couleurs, dans l'ordre (8 ANSI puis 8 vives)", join(colors), EXPECTED_TEXT)
check("config.colors : pas de nom de thème", scheme_name, nil)
colors = theme.extract({
	colors = {
		ansi = { "#1e1e1e", "cc3333", "#33cc33", "#cccc33", "#3333cc", "#cc33cc", "#33cccc", "#cccccc" },
		brights = BRIGHTS,
	},
})
check("minuscules et dièse absent : normalisés", colors and colors[1] .. colors[2], "#1E1E1E#CC3333")

-- ---- les couleurs viennent d'un thème intégré
local function fake_wezterm(schemes, style)
	if style == "ancien" then
		return {
			get_builtin_color_schemes = function()
				return schemes
			end,
		}
	end
	return { color = {
		get_builtin_schemes = function()
			return schemes
		end,
	} }
end
local SCHEMES = { Fake = { ansi = ANSI, brights = BRIGHTS, foreground = "#FFFFFF" } }
colors, scheme_name = theme.extract({ color_scheme = "Fake" }, fake_wezterm(SCHEMES))
check("thème intégré (wezterm.color.get_builtin_schemes)", join(colors), EXPECTED_TEXT)
check("thème intégré : son nom est renvoyé", scheme_name, "Fake")
colors, scheme_name = theme.extract({ color_scheme = "Fake" }, fake_wezterm(SCHEMES, "ancien"))
check("thème intégré avec l'ancienne fonction (wezterm.get_builtin_color_schemes)", join(colors), EXPECTED_TEXT)
colors = theme.extract({ color_scheme = "Fake" }, {
	color = {
		get_builtin_schemes = function()
			error("boum")
		end,
	},
	get_builtin_color_schemes = function()
		return SCHEMES
	end,
})
check("si la première fonction plante, la seconde est essayée", join(colors), EXPECTED_TEXT)

-- ---- un thème défini dans config.color_schemes passe avant les thèmes intégrés
local custom_ansi = copy(ANSI)
custom_ansi[2] = "#AA0000"
colors = theme.extract(
	{ color_scheme = "Fake", color_schemes = { Fake = { ansi = custom_ansi, brights = BRIGHTS } } },
	fake_wezterm(SCHEMES)
)
check("thème de config.color_schemes : prioritaire", colors and colors[2], "#AA0000")
colors = theme.extract({ color_scheme = "Mien", color_schemes = { Mien = { ansi = ANSI, brights = BRIGHTS } } })
check("thème de config.color_schemes sans wezterm", join(colors), EXPECTED_TEXT)

-- ---- config.colors complète ou remplace le thème, couleur par couleur
colors, scheme_name = theme.extract(
	{ color_scheme = "Fake", colors = { ansi = { [2] = "#112233" }, brights = { [8] = "#445566" } } },
	fake_wezterm(SCHEMES)
)
check("config.colors remplace la couleur 2 du thème", colors and colors[2], "#112233")
check("config.colors remplace la couleur 16 du thème", colors and colors[16], "#445566")
check(
	"les autres couleurs restent celles du thème",
	colors and colors[1] .. colors[3] .. colors[9],
	"#1E1E1E#33CC33#555555"
)
check("le nom du thème est renvoyé aussi", scheme_name, "Fake")
colors = theme.extract(
	{ color_scheme = "Fake", colors = { foreground = "#FFFFFF", cursor_bg = "#000000" } },
	fake_wezterm(SCHEMES)
)
check("config.colors sans ansi ni brights : le thème est gardé", join(colors), EXPECTED_TEXT)
colors = theme.extract({ color_scheme = "Fake", colors = "pas une table" }, fake_wezterm(SCHEMES))
check("config.colors qui n'est pas une table : ignoré", join(colors), EXPECTED_TEXT)

-- ---- il manque des couleurs : refus avec la raison
local missing, reason = theme.extract({ colors = { ansi = { "#1", "#2" } } })
check("couleurs manquantes : refusé", missing, nil)
local short_ansi = copy(ANSI)
short_ansi[8] = nil
missing, reason = theme.extract({ colors = { ansi = short_ansi, brights = BRIGHTS } })
check("une seule couleur ANSI manquante : refusé", missing, nil)
check("la raison cite la couleur manquante (8)", reason:find("couleur 8", 1, true) ~= nil, true)
local short_brights = copy(BRIGHTS)
short_brights[3] = nil
missing, reason = theme.extract({ colors = { ansi = ANSI, brights = short_brights } })
check("une couleur vive manquante : refusé", missing, nil)
local gap = {}
for i = 1, 8 do
	gap[i] = BRIGHTS[i]
end
gap[2] = "#GGGGGG"
missing, reason = theme.extract({ colors = { ansi = ANSI, brights = gap } })
check("une couleur invalide (lettres hors hexadécimal) : refusé", missing, nil)
check("la raison cite la couleur 10", reason:find("couleur 10", 1, true) ~= nil, true)
missing = theme.extract({
	colors = { ansi = { "red", "green", "blue", "black", "white", "cyan", "magenta", "yellow" }, brights = BRIGHTS },
})
check("des noms de couleurs au lieu de codes : refusé", missing, nil)
local objects = copy(ANSI)
objects[3] = {}
missing = theme.extract({ colors = { ansi = objects, brights = BRIGHTS } })
check("un objet à la place d'un code couleur : refusé", missing, nil)
local numbers = copy(ANSI)
numbers[1] = 123456
missing = theme.extract({ colors = { ansi = numbers, brights = BRIGHTS } })
check("un nombre à la place d'un code couleur : refusé", missing, nil)
missing, reason = theme.extract({})
check("configuration vide : refusé", missing, nil)
check("configuration vide : la raison", type(reason) == "string" and #reason > 5, true)

-- ---- un thème qu'on ne sait pas lire
missing, reason = theme.extract({ color_scheme = "Inconnu" }, fake_wezterm(SCHEMES))
check("thème inconnu, sans config.colors : refusé", missing, nil)
check("la raison cite le nom du thème", reason:find("« Inconnu »", 1, true) ~= nil, true)
missing, reason = theme.extract({ color_scheme = "Fake" })
check("thème intégré mais sans le module wezterm : refusé", missing, nil)
colors = theme.extract({ color_scheme = "Inconnu", colors = { ansi = ANSI, brights = BRIGHTS } }, fake_wezterm(SCHEMES))
check(
	"thème inconnu mais config.colors complète : les couleurs de config.colors servent",
	join(colors),
	EXPECTED_TEXT
)
local no_brights = { Faible = { ansi = ANSI } }
missing, reason = theme.extract({ color_scheme = "Faible" }, fake_wezterm(no_brights))
check("thème sans couleurs vives : refusé", missing, nil)
check("... avec la couleur manquante dans la raison", reason:find("couleur 9", 1, true) ~= nil, true)
missing = theme.extract({ color_scheme = 42 })
check("color_scheme qui n'est pas un texte : refusé sans plantage", missing, nil)
missing = theme.extract({ color_scheme = "" })
check("color_scheme vide : refusé sans plantage", missing, nil)

-- ---- des entrées bizarres ne plantent jamais
for _, weird in ipairs({ "texte", 12, true, false }) do
	local ok, result = pcall(theme.extract, weird)
	check("configuration de type " .. type(weird) .. " : pas de plantage, refusé", ok and result == nil, true)
end
check("configuration nil : pas de plantage, refusé", select(2, pcall(theme.extract, nil)), nil)
local strict = setmetatable({}, {
	__index = function()
		error("boum")
	end,
})
local ok, result = pcall(theme.extract, strict)
check("une configuration dont la lecture plante : pas de plantage", ok and result == nil, true)
ok, result = pcall(theme.extract, { color_scheme = "Fake", colors = strict }, fake_wezterm(SCHEMES))
check("config.colors dont la lecture plante : le thème est gardé", ok and join(result) == EXPECTED_TEXT, true)
ok, result = pcall(
	theme.extract,
	{ color_scheme = "Fake" },
	{ color = {
		get_builtin_schemes = function()
			error("boum")
		end,
	} }
)
check("wezterm dont les thèmes plantent : refusé sans plantage", ok and result == nil, true)
ok, result = pcall(theme.extract, { color_scheme = "Fake" }, "pas un module")
check("wezterm qui n'est pas une table : refusé sans plantage", ok and result == nil, true)
local seed = 2024
local function rnd(n)
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed % n
end
local never_crashes = true
local pieces = { "#1E1E1E", "cc3333", {}, 12, true, "rouge", "#GGGGGG", "" }
for _ = 1, 500 do
	local list = {}
	for i = 1, rnd(10) do
		list[i] = pieces[1 + rnd(#pieces)]
	end
	if
		not pcall(
			theme.extract,
			{ colors = { ansi = list, brights = list }, color_scheme = pieces[1 + rnd(#pieces)] },
			fake_wezterm(SCHEMES)
		)
	then
		never_crashes = false
	end
end
check("500 configurations au hasard : jamais de plantage", never_crashes, true)

-- ---- la configuration n'est jamais modifiée
local function dump(value)
	if type(value) ~= "table" then
		return tostring(value)
	end
	local keys = {}
	for key in pairs(value) do
		keys[#keys + 1] = key
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	local parts = {}
	for _, key in ipairs(keys) do
		parts[#parts + 1] = tostring(key) .. "=" .. dump(value[key])
	end
	return "{" .. table.concat(parts, ",") .. "}"
end
local config =
	{ color_scheme = "Fake", colors = { ansi = { [2] = "#112233" }, foreground = "#FFFFFF" }, font_size = 12 }
local snapshot = dump(config)
local wez = fake_wezterm(SCHEMES)
local wez_snapshot = dump(SCHEMES)
theme.extract(config, wez)
check("la configuration n'est pas modifiée (ni une clé ajoutée, ni une valeur changée)", dump(config), snapshot)
check("les thèmes intégrés ne sont pas modifiés", dump(SCHEMES), wez_snapshot)
local failing_config = { colors = { ansi = { "#1" } }, other = true }
local failing_snapshot = dump(failing_config)
theme.extract(failing_config, wez)
check("même un refus ne modifie pas la configuration", dump(failing_config), failing_snapshot)
colors = theme.extract({ colors = { ansi = ANSI, brights = BRIGHTS } })
colors[1] = "#000000"
check("la liste renvoyée est indépendante de la configuration", ANSI[1], "#1E1E1E")

-- ---- les noms des couleurs du thème, dans les deux langues
for name, labels in pairs({ ["français"] = fr, ["anglais"] = en }) do
	check(
		"noms du thème en " .. name .. " : seize noms",
		type(labels.palette_theme) == "table" and #labels.palette_theme,
		16
	)
	local unique, short, filled = {}, true, true
	for _, color_name in ipairs(labels.palette_theme or {}) do
		if type(color_name) ~= "string" or #color_name == 0 or unique[color_name] then
			filled = false
		else
			unique[color_name] = true
			if utf8.len(color_name) > 11 then
				short = false
			end
		end
	end
	check("noms du thème en " .. name .. " : tous remplis et différents", filled, true)
	check("noms du thème en " .. name .. " : au plus 11 caractères (la largeur d'une couleur)", short, true)
end
check("le nom de la couleur 2 du thème en français", fr.palette_theme[2], "Rouge")
check("le nom de la couleur 10 du thème en anglais", en.palette_theme[10], "Lt Red")

local leaked = {}
for k in pairs(_G) do
	if not globals_before[k] then
		leaked[#leaked + 1] = k
	end
end
check("aucune variable globale ajoutée", table.concat(leaked, ","), "")

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
