-- tests/settings/test_schema.lua : teste settings/schema.lua (la liste des réglages, ce que chacun accepte, ses valeurs par
-- défaut) et sa cohérence avec les valeurs par défaut des autres modules. Lancer :   lua5.4 tests/settings/test_schema.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]settings[/\\]test_schema%.lua$") or "."

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
local schema = load_module("settings/schema")
local gradient = load_module("color/gradient")
local layout = load_module("calendar/layout")
local assemble = load_module("calendar/assemble")

local passed, failed = 0, 0
local function check(name, got, want)
	if got == want then
		passed = passed + 1
	else
		failed = failed + 1
		print(string.format("ÉCHEC  %s\n         attendu : %s\n         obtenu  : %s", name, tostring(want), tostring(got)))
	end
end
local function ok(key, value)
	local good, normalized = schema.validate(key, value)
	return good, normalized
end
local function accepts(name, key, value, expected)
	local good, normalized = ok(key, value)
	check(name .. " : accepté", good, true)
	if expected ~= nil then
		check(name .. " : valeur normalisée", normalized, expected)
	end
end
local function rejects(name, key, value)
	local good, reason = schema.validate(key, value)
	check(name .. " : refusé", good, false)
	check(name .. " : avec une raison", type(reason) == "string" and #reason > 3, true)
end

-- ---- la liste
check("dix-sept réglages", #schema.keys(), 17)
check("le premier est lang", schema.keys()[1], "lang")
check("gradient_color est connu", schema.is_known("gradient_color"), true)
check("un nom inconnu n'est pas connu", schema.is_known("gradiant"), false)
check("get d'un réglage connu", schema.get("max_months").kind, "integer")
check("get d'un réglage inconnu", schema.get("zzz"), nil)
local seen, duplicates = {}, false
for _, key in ipairs(schema.keys()) do
	if seen[key] then
		duplicates = true
	end
	seen[key] = true
end
check("aucun nom en double", duplicates, false)
local list = schema.keys()
list[1] = "modifié"
check("keys() renvoie une copie", schema.keys()[1], "lang")

-- ---- lang et week_starts_on (listes de valeurs)
accepts("lang fr", "lang", "fr", "fr")
accepts("lang en", "lang", "en", "en")
rejects("lang de", "lang", "de")
rejects("lang en majuscules", "lang", "FR")
rejects("lang nombre", "lang", 1)
rejects("lang vide", "lang", "")
rejects("lang absent", "lang", nil)
accepts("semaine lundi", "week_starts_on", "monday")
accepts("semaine dimanche", "week_starts_on", "sunday")
rejects("semaine samedi", "week_starts_on", "saturday")
accepts("ancre last", "months_anchor", "last")
accepts("ancre first", "months_anchor", "first")
rejects("ancre milieu", "months_anchor", "middle")
check("la raison d'une liste cite les valeurs", select(2, schema.validate("lang", "de")):find("« fr » ou « en »", 1, true) ~= nil, true)

-- ---- booléens
accepts("center vrai", "center", true, true)
accepts("center faux", "center", false, false)
rejects("center en texte", "center", "true")
rejects("center nombre", "center", 1)
rejects("center nil", "center", nil)
accepts("gradient faux", "gradient", false, false)
rejects("gradient en texte", "gradient", "oui")

-- ---- couleur
accepts("couleur", "gradient_color", "#3366CC", "#3366CC")
accepts("couleur en minuscules", "gradient_color", "#3366cc", "#3366CC")
accepts("couleur sans dièse", "gradient_color", "3366CC", "#3366CC")
rejects("couleur trop courte", "gradient_color", "#336")
rejects("couleur trop longue", "gradient_color", "#3366CC00")
rejects("couleur avec une lettre invalide", "gradient_color", "#33G6CC")
rejects("couleur en nombre", "gradient_color", 3366)
rejects("couleur vide", "gradient_color", "")
rejects("couleur avec des espaces", "gradient_color", " #3366CC")

-- ---- entier
accepts("max_months 1", "max_months", 1, 1)
accepts("max_months 12", "max_months", 12, 12)
accepts("max_months 6.0 devient un entier", "max_months", 6.0, 6)
check("max_months 6.0 : c'est un vrai entier", math.type(select(2, schema.validate("max_months", 6.0))), "integer")
rejects("max_months 0", "max_months", 0)
rejects("max_months 13", "max_months", 13)
rejects("max_months négatif", "max_months", -2)
rejects("max_months décimal", "max_months", 2.5)
rejects("max_months en texte", "max_months", "6")
rejects("max_months NaN", "max_months", 0 / 0)
rejects("max_months infini", "max_months", math.huge)
rejects("max_months moins l'infini", "max_months", -math.huge)

-- ---- nombres
accepts("goal_hours 3", "goal_hours", 3, 3)
accepts("goal_hours 0,5 (le minimum)", "goal_hours", 0.5, 0.5)
accepts("goal_hours 24 (le maximum)", "goal_hours", 24, 24)
rejects("goal_hours 0,4", "goal_hours", 0.4)
rejects("goal_hours 25", "goal_hours", 25)
rejects("goal_hours en texte", "goal_hours", "3")
accepts("gradient_light 0", "gradient_light", 0, 0)
accepts("gradient_light 1", "gradient_light", 1, 1)
accepts("gradient_light 0,95", "gradient_light", 0.95, 0.95)
rejects("gradient_light 1,1", "gradient_light", 1.1)
rejects("gradient_light négatif", "gradient_light", -0.1)
accepts("gradient_dark 0,05", "gradient_dark", 0.05, 0.05)
rejects("gradient_dark 2", "gradient_dark", 2)
accepts("gradient_hours 1", "gradient_hours", 1, 1)
accepts("gradient_hours 48", "gradient_hours", 48, 48)
rejects("gradient_hours 0,5", "gradient_hours", 0.5)
rejects("gradient_hours 49", "gradient_hours", 49)
accepts("gradient_curve 0,1", "gradient_curve", 0.1, 0.1)
accepts("gradient_curve 3", "gradient_curve", 3, 3)
rejects("gradient_curve 0", "gradient_curve", 0)
rejects("gradient_curve 3,1", "gradient_curve", 3.1)
check("la raison d'un intervalle cite les bornes", select(2, schema.validate("gradient_curve", 5)), "doit être compris entre 0.1 et 3")

rejects("goal_hours NaN", "goal_hours", 0 / 0)
rejects("goal_hours infini", "goal_hours", math.huge)
rejects("gradient_curve NaN", "gradient_curve", 0 / 0)
rejects("gradient_light moins l'infini", "gradient_light", -math.huge)
rejects("gradient_hours NaN", "gradient_hours", 0 / 0)

-- ---- inconnu
rejects("réglage inconnu", "gradiant", true)
check("réglage inconnu : la raison", select(2, schema.validate("gradiant", true)), "réglage inconnu")
rejects("clé en nombre", 12, true)

-- ---- valeurs par défaut
local defaults = schema.defaults()
local all_valid = true
for key, value in pairs(defaults) do
	if not schema.validate(key, value) then
		all_valid = false
	end
end
check("toutes les valeurs par défaut sont acceptées par le schéma", all_valid, true)
check("goal_hours n'a pas de valeur par défaut", defaults.goal_hours, nil)
check("quinze valeurs par défaut", (function()
	local n = 0
	for _ in pairs(defaults) do
		n = n + 1
	end
	return n
end)(), 15)
check("border_color : gris par défaut", defaults.border_color, "#8B8E99")
accepts("border_color en minuscules", "border_color", "#3366cc", "#3366CC")
rejects("border_color pas une couleur", "border_color", "bleu")
check("borders : non par défaut", defaults.borders, false)
check("border_style : arrondi par défaut", defaults.border_style, "rounded")
accepts("border_style double", "border_style", "double", "double")
rejects("border_style inconnu", "border_style", "pointillé")
rejects("borders en texte", "borders", "oui")

-- ---- « aucun » (none) et goal_days
accepts("goal_hours 0 : aucun objectif (la valeur none)", "goal_hours", 0, 0)
rejects("goal_hours 0,25 : ni aucun, ni dans les limites", "goal_hours", 0.25)
rejects("goal_hours -1", "goal_hours", -1)
check("goal_hours : la valeur none est 0", schema.get("goal_hours").none, 0)
check("goal_hours : change de 0,5 en 0,5 dans la page", schema.get("goal_hours").step, 0.5)
accepts("goal_days 1 (le minimum)", "goal_days", 1, 1)
accepts("goal_days 7 (le maximum)", "goal_days", 7, 7)
rejects("goal_days 0", "goal_days", 0)
rejects("goal_days 8", "goal_days", 8)
rejects("goal_days 4,5", "goal_days", 4.5)
check("goal_days : 5 par défaut", defaults.goal_days, 5)
rejects("max_months 0 (pas de valeur none pour lui)", "max_months", 0)
defaults.lang = "xx"
check("defaults() renvoie une copie", schema.defaults().lang, "fr")

-- ---- cohérence avec les valeurs par défaut des autres modules (si l'un change sans l'autre, ce test le dit)
check("gradient_color = la couleur par défaut du dégradé", schema.defaults().gradient_color, gradient.DEFAULT_COLOR)
check("gradient_light = celle du dégradé", schema.defaults().gradient_light, gradient.DEFAULT_LIGHT)
check("gradient_dark = celle du dégradé", schema.defaults().gradient_dark, gradient.DEFAULT_DARK)
check("gradient_hours = celle du dégradé", schema.defaults().gradient_hours, gradient.DEFAULT_HOURS)
check("gradient_curve = celle du dégradé", schema.defaults().gradient_curve, gradient.DEFAULT_CURVE)
check("max_months = le plafond de la disposition", schema.defaults().max_months, layout.MAX_MONTHS)
check("week_starts_on = celui du dessin du mois", schema.defaults().week_starts_on, assemble.DEFAULTS.week_starts_on)
check("le plafond de max_months est celui de la disposition (12)", schema.get("max_months").max, 12)
local languages_exist = true
for _, lang in ipairs(schema.get("lang").values) do
	if not pcall(load_module, "i18n/" .. lang) then
		languages_exist = false
	end
end
check("chaque langue du schéma a son fichier de textes", languages_exist, true)

local leaked = {}
for k in pairs(_G) do
	if not globals_before[k] then
		leaked[#leaked + 1] = k
	end
end
check("aucune variable globale ajoutée", table.concat(leaked, ","), "")

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
