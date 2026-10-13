-- tests/settings/test_store.lua : teste settings/store.lua (lecture d'un texte, écriture, fichier sur le disque avec copie
-- de sécurité et mise de côté d'un fichier illisible, vérification des options). Lancer :   lua5.4 tests/settings/test_store.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]settings[/\\]test_store%.lua$") or "."

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
local store = load_module("settings/store")
local schema = load_module("settings/schema")
local json = load_module("settings/json")

-- toute écriture doit rester dans un dossier temporaire
local homes, outside = {}, {}
local real_open = io.open
local corrupt_tmp_reads = false -- simule un disque qui rend un autre contenu que celui écrit dans le fichier temporaire
io.open = function(path, mode)
	if corrupt_tmp_reads and path:sub(-4) == ".tmp" and not (mode and (mode:find("w") or mode:find("a"))) then
		return { read = function() return "contenu corrompu" end, close = function() end }
	end
	if mode and (mode:find("w") or mode:find("a") or mode:find("%+")) then
		local inside = false
		for _, home in ipairs(homes) do
			if path:sub(1, #home) == home then
				inside = true
			end
		end
		if not inside then
			outside[#outside + 1] = path
		end
	end
	return real_open(path, mode)
end

local passed, failed = 0, 0
local function check(name, got, want)
	if got == want then
		passed = passed + 1
	else
		failed = failed + 1
		print(string.format("ÉCHEC  %s\n         attendu : %s\n         obtenu  : %s", name, tostring(want), tostring(got)))
	end
end
local function write(path, text)
	local f = assert(real_open(path, "wb"))
	f:write(text)
	f:close()
end
local function read(path)
	local f = real_open(path, "rb")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text
end
local function new_dir()
	local dir = os.tmpname()
	os.remove(dir)
	os.execute("mkdir -p '" .. dir .. "'")
	homes[#homes + 1] = dir
	return dir
end
local function list_files(dir)
	local out = {}
	local p = io.popen("ls -1A '" .. dir .. "'")
	for name in p:lines() do
		out[#out + 1] = name
	end
	p:close()
	return out
end
local function find_prefix(dir, prefix)
	for _, name in ipairs(list_files(dir)) do
		if name:sub(1, #prefix) == prefix then
			return name
		end
	end
end

-- ============================================================
-- parse
-- ============================================================
local settings, problems = store.parse('{"max_months": 6, "gradient_color": "#3366cc", "center": false, "lang": "en"}')
check("parse : un entier", settings.max_months, 6)
check("parse : une couleur mise en majuscules", settings.gradient_color, "#3366CC")
check("parse : un booléen faux est conservé", settings.center, false)
check("parse : un texte de liste", settings.lang, "en")
check("parse : aucun problème", #problems, 0)
settings, problems = store.parse('{"max_months": 6.0}')
check("parse : 6.0 devient un entier", math.type(settings.max_months), "integer")
settings, problems = store.parse('{"gradiant": true, "max_months": 6}')
check("parse : un réglage inconnu est ignoré", settings.gradiant, nil)
check("parse : les autres sont gardés", settings.max_months, 6)
check("parse : un problème est signalé", #problems, 1)
check("parse : le problème cite le nom", problems[1]:find("gradiant", 1, true) ~= nil, true)
settings, problems = store.parse('{"max_months": 100, "lang": "de", "center": true}')
check("parse : une valeur incorrecte est ignorée", settings.max_months, nil)
check("parse : une autre aussi", settings.lang, nil)
check("parse : la valeur correcte est gardée", settings.center, true)
check("parse : deux problèmes", #problems, 2)
check("parse : le problème cite la raison (bornes)", problems[2]:find("compris entre 1 et 12", 1, true) ~= nil, true)
settings, problems = store.parse('{"goal_hours": null, "max_months": null}')
check("parse : null est ignoré sans problème", next(settings) == nil and #problems == 0, true)
settings, problems = store.parse("{}")
check("parse : objet vide", next(settings) == nil and #problems == 0, true)
settings, problems = store.parse('{"max_months": "6"}')
check("parse : un nombre écrit en texte est refusé", settings.max_months == nil and #problems == 1, true)
settings, problems = store.parse('{"b_inconnu": 1, "a_inconnu": 2}')
check("parse : les problèmes sont dans l'ordre alphabétique", problems[1]:find("a_inconnu", 1, true) ~= nil and problems[2]:find("b_inconnu", 1, true) ~= nil, true)
for name, text in pairs({ liste_vide = "[]", liste = "[1, 2]", nombre = "12", texte = '"abc"', booleen = "true", null = "null" }) do
	local value, err = store.parse(text)
	check("parse : « " .. name .. " » n'est pas un objet : refusé", value, nil)
	check("parse : « " .. name .. " » : message sur les accolades", type(err) == "string" and err:find("objet", 1, true) ~= nil, true)
end
local value, err = store.parse("{ pas du json")
check("parse : texte illisible refusé", value, nil)
check("parse : avec un message", type(err), "string")
value, err = store.parse("")
check("parse : fichier vide refusé", value, nil)
check("parse : le message dit qu'il est vide", err:find("vide", 1, true) ~= nil, true)

-- ============================================================
-- encode
-- ============================================================
check("encode : aucun réglage", store.encode({}), "{}\n")
check("encode : un réglage", store.encode({ max_months = 6 }), '{\n  "max_months": 6\n}\n')
check("encode : plusieurs, dans l'ordre du schéma (pas alphabétique)", store.encode({ gradient_color = "#3366CC", lang = "en", max_months = 6 }), '{\n  "lang": "en",\n  "max_months": 6,\n  "gradient_color": "#3366CC"\n}\n')
check("encode : booléens", store.encode({ center = false, gradient = true }), '{\n  "center": false,\n  "gradient": true\n}\n')
check("encode : décimal", store.encode({ gradient_light = 0.8 }), '{\n  "gradient_light": 0.8\n}\n')
check("encode : un décimal entier s'écrit sans point", store.encode({ gradient_hours = 24.0 }), '{\n  "gradient_hours": 24\n}\n')
check("encode : une couleur en minuscules est normalisée", store.encode({ gradient_color = "#3366cc" }), '{\n  "gradient_color": "#3366CC"\n}\n')
check("encode : un réglage inconnu n'est pas écrit", store.encode({ zzz = 1, max_months = 6 }), '{\n  "max_months": 6\n}\n')
check("encode : un réglage absent (nil) n'est pas écrit", store.encode({ goal_hours = nil }), "{}\n")
local text, why = store.encode({ max_months = 100 })
check("encode : une valeur incorrecte est refusée", text, nil)
check("encode : avec la raison", why:find("max_months", 1, true) ~= nil and why:find("compris entre", 1, true) ~= nil, true)
check("encode : 0,1 + 0,2 s'écrit proprement", store.encode({ gradient_light = 0.1 + 0.2 }), '{\n  "gradient_light": 0.3\n}\n')

-- aller-retour : ce qu'on écrit se relit à l'identique, sur 500 combinaisons
local seed = 31337
local function rnd(n)
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed % n
end
local roundtrip_ok = true
for _ = 1, 500 do
	local combo = {}
	for _, definition in ipairs(schema.DEFINITIONS) do
		if rnd(2) == 1 then
			local value
			if definition.kind == "enum" then
				value = definition.values[1 + rnd(#definition.values)]
			elseif definition.kind == "boolean" then
				value = rnd(2) == 1
			elseif definition.kind == "color" then
				value = string.format("#%02X%02X%02X", rnd(256), rnd(256), rnd(256))
			elseif definition.kind == "integer" then
				value = definition.min + rnd(definition.max - definition.min + 1)
			else
				value = definition.min + (definition.max - definition.min) * (rnd(1001) / 1000)
			end
			combo[definition.key] = value
		end
	end
	local encoded = store.encode(combo)
	local back = store.parse(encoded)
	for key, value in pairs(combo) do
		local expected = schema.validate(key, value) and select(2, schema.validate(key, value))
		if back == nil or math.abs((tonumber(back[key]) or 0) - (tonumber(expected) or 0)) > 1e-9 and type(expected) == "number" or (type(expected) ~= "number" and back[key] ~= expected) then
			roundtrip_ok = false
		end
	end
	if back then
		for key in pairs(back) do
			if combo[key] == nil then
				roundtrip_ok = false
			end
		end
	end
end
check("500 combinaisons : écrire puis relire redonne exactement les mêmes réglages", roundtrip_ok, true)

-- encode_string : les caractères spéciaux
local function roundtrip_string(s)
	return json.decode(store.encode_string(s))
end
check("texte : guillemet", roundtrip_string('a"b'), 'a"b')
check("texte : antislash", roundtrip_string("a\\b"), "a\\b")
check("texte : retour à la ligne", roundtrip_string("a\nb"), "a\nb")
check("texte : tabulation", roundtrip_string("a\tb"), "a\tb")
check("texte : retour chariot", roundtrip_string("a\rb"), "a\rb")
check("texte : caractère de contrôle", roundtrip_string("a\1b"), "a\1b")
check("texte : accents conservés", roundtrip_string("Février ✓"), "Février ✓")
check("texte : le guillemet est échappé dans le fichier", store.encode_string('a"b'), '"a\\"b"')

-- ============================================================
-- le fichier : load / save
-- ============================================================
local dir = new_dir()
local path = dir .. "/.logtime_settings.json"
local loaded, state, issues, from_backup = store.load(path)
check("load : fichier absent", state, "absent")
check("load : absent donne des réglages vides", next(loaded), nil)
check("load : absent sans problème", #issues, 0)
check("load : absent, pas depuis la copie", from_backup, false)

local saved, save_err = store.save(path, { max_months = 6, gradient_color = "#3366CC" })
check("save : premier enregistrement", saved, true)
check("save : le contenu du fichier", read(path), '{\n  "max_months": 6,\n  "gradient_color": "#3366CC"\n}\n')
check("save : pas de copie de sécurité au premier enregistrement", read(path .. ".bak"), nil)
check("save : pas de fichier temporaire laissé", read(path .. ".tmp"), nil)
loaded, state = store.load(path)
check("load : relu à l'identique (entier)", loaded.max_months, 6)
check("load : relu à l'identique (couleur)", loaded.gradient_color, "#3366CC")
check("load : état ok", state, "ok")

local first_version = read(path)
saved = store.save(path, { max_months = 9, lang = "en" })
check("save : deuxième enregistrement", saved, true)
check("save : la copie de sécurité est la version précédente", read(path .. ".bak"), first_version)
check("save : le fichier est la nouvelle version", read(path), '{\n  "lang": "en",\n  "max_months": 9\n}\n')
local second_version = read(path)
store.save(path, { max_months = 3 })
check("save : la copie de sécurité suit (troisième enregistrement)", read(path .. ".bak"), second_version)
check("save : toujours pas de fichier temporaire", read(path .. ".tmp"), nil)

-- l'écriture est vérifiée : si le disque rend autre chose que ce qui a été écrit, rien ne remplace le bon fichier
local intact = read(path)
corrupt_tmp_reads = true
saved, save_err = store.save(path, { max_months = 2 })
corrupt_tmp_reads = false
check("save : écriture corrompue : échec", saved, false)
check("save : écriture corrompue : la raison parle de la vérification", save_err:find("vérification", 1, true) ~= nil, true)
check("save : écriture corrompue : le fichier d'origine est intact", read(path), intact)
check("save : écriture corrompue : le fichier temporaire est retiré", read(path .. ".tmp"), nil)

-- un réglage invalide ou inconnu
local before = read(path)
saved, save_err = store.save(path, { max_months = 99 })
check("save : une valeur incorrecte est refusée", saved, false)
check("save : avec la raison", save_err:find("max_months", 1, true) ~= nil, true)
check("save : le fichier n'est pas touché", read(path), before)
store.save(path, { max_months = 4, inconnu = 1 })
check("save : un réglage inconnu n'est pas écrit", read(path), '{\n  "max_months": 4\n}\n')
store.save(path, {})
check("save : des réglages vides s'écrivent {}", read(path), "{}\n")

-- un fichier avec des réglages inconnus ou incorrects est lu sans perdre les bons
write(path, '{"max_months": 6, "gradiant": true, "lang": "de"}')
loaded, state, issues = store.load(path)
check("load : état ok malgré des problèmes", state, "ok")
check("load : le bon réglage est gardé", loaded.max_months, 6)
check("load : deux problèmes signalés", #issues, 2)

-- fichier illisible, sans copie de sécurité
local dir2 = new_dir()
local path2 = dir2 .. "/.logtime_settings.json"
write(path2, "{ ceci n'est pas du json")
loaded, state, issues, from_backup = store.load(path2)
check("load : fichier illisible", state, "corrupt")
check("load : illisible sans copie : réglages vides", next(loaded), nil)
check("load : illisible : le problème le dit", issues[1]:find("illisible", 1, true) ~= nil and issues[1]:find("valeurs par défaut", 1, true) ~= nil, true)
check("load : illisible sans copie : pas depuis la copie", from_backup, false)
write(path2, "")
loaded, state = store.load(path2)
check("load : fichier vide : traité comme illisible", state, "corrupt")
write(path2, "[1, 2, 3]")
loaded, state = store.load(path2)
check("load : une liste à la place d'un objet : illisible", state, "corrupt")

-- fichier illisible AVEC une bonne copie de sécurité
write(path2 .. ".bak", '{"max_months": 7, "lang": "en"}')
write(path2, "\0\0\0 abîmé")
loaded, state, issues, from_backup = store.load(path2)
check("load : illisible avec copie : état corrupt", state, "corrupt")
check("load : la copie de sécurité est utilisée", loaded.max_months == 7 and loaded.lang == "en", true)
check("load : on sait que c'est la copie", from_backup, true)
check("load : le problème parle de la copie", issues[1]:find("copie de sécurité", 1, true) ~= nil, true)
write(path2 .. ".bak", "copie abîmée aussi")
loaded, state, issues, from_backup = store.load(path2)
check("load : copie abîmée aussi : réglages vides", next(loaded) == nil and from_backup == false, true)

-- enregistrer par-dessus un fichier illisible : il est mis de côté, jamais écrasé
local dir3 = new_dir()
local path3 = dir3 .. "/.logtime_settings.json"
write(path3, "contenu illisible précieux")
saved = store.save(path3, { max_months = 5 })
check("save sur un fichier illisible : réussi", saved, true)
check("save sur un fichier illisible : le nouveau fichier est bon", read(path3), '{\n  "max_months": 5\n}\n')
local quarantined = find_prefix(dir3, ".logtime_settings.json.corrupt-")
check("save sur un fichier illisible : l'ancien est mis de côté", quarantined ~= nil, true)
check("save sur un fichier illisible : son contenu est intact", read(dir3 .. "/" .. tostring(quarantined)), "contenu illisible précieux")
check("save sur un fichier illisible : pas de copie .bak d'un fichier illisible", read(path3 .. ".bak"), nil)
write(path3, "encore illisible")
store.save(path3, { max_months = 6 })
local count_quarantined = 0
for _, name in ipairs(list_files(dir3)) do
if name:find(".corrupt-", 1, true) then
count_quarantined = count_quarantined + 1
end
end
check("save : un second fichier illisible ne remplace pas le premier (noms uniques)", count_quarantined, 2)

-- échec d'écriture : dossier inexistant
saved, save_err = store.save(dir .. "/nexiste/pas/.logtime_settings.json", { max_months = 6 })
check("save : dossier inexistant : échec sans plantage", saved, false)
check("save : dossier inexistant : une raison", type(save_err) == "string" and #save_err > 5, true)
check("save : dossier inexistant : aucun fichier temporaire créé", read(dir .. "/nexiste/pas/.logtime_settings.json.tmp"), nil)

-- un fichier avec une marque BOM (enregistré par un éditeur de texte Windows)
write(path, "\239\187\191{\"max_months\": 2}")
loaded, state = store.load(path)
check("load : un fichier avec BOM est lu", state == "ok" and loaded.max_months == 2, true)

-- ============================================================
-- check_options
-- ============================================================
local EXTRA = { "open_key", "data_file", "settings_file", "cell_color" }
check("options : absentes", #store.check_options(nil, EXTRA), 0)
check("options : table vide", #store.check_options({}, EXTRA), 0)
local messages = store.check_options("max_months = 6", EXTRA)
check("options : un texte à la place d'une table", #messages, 1)
check("options : le message parle de table", messages[1]:find("table", 1, true) ~= nil, true)
check("options : le message donne un exemple", messages[1]:find("apply_to_config(config, { max_months = 6 })", 1, true) ~= nil, true)
check("options : le message dit le type reçu", messages[1]:find("string", 1, true) ~= nil, true)
check("options : un nombre à la place d'une table", #store.check_options(12, EXTRA), 1)
check("options : un booléen à la place d'une table", #store.check_options(true, EXTRA), 1)
check("options : une fonction à la place d'une table", #store.check_options(function() end, EXTRA), 1)
check("options : toutes valides", #store.check_options({ lang = "en", max_months = 6, gradient_color = "#3366CC", open_key = "F3", goal_hours = 3 }, EXTRA), 0)
messages = store.check_options({ gradiant = true }, EXTRA)
check("options : une faute de frappe est signalée", #messages, 1)
check("options : avec la suggestion « gradient »", messages[1]:find("tu voulais dire « gradient » ?", 1, true) ~= nil, true)
check("options : le nom fautif est cité", messages[1]:find("« gradiant »", 1, true) ~= nil, true)
messages = store.check_options({ gradient_colour = "#3366CC" }, EXTRA)
check("options : gradient_colour suggère gradient_color", messages[1]:find("« gradient_color » ?", 1, true) ~= nil, true)
messages = store.check_options({ maxmonths = 6 }, EXTRA)
check("options : maxmonths suggère max_months", messages[1]:find("« max_months » ?", 1, true) ~= nil, true)
messages = store.check_options({ centre = true }, EXTRA)
check("options : centre suggère center", messages[1]:find("« center » ?", 1, true) ~= nil, true)
messages = store.check_options({ open_ke = "F3" }, EXTRA)
check("options : une faute sur une option hors schéma suggère aussi (open_key)", messages[1]:find("« open_key » ?", 1, true) ~= nil, true)
messages = store.check_options({ gradient_hour = 12 }, EXTRA)
check("options : gradient_hour suggère le plus proche (gradient_hours)", messages[1]:find("« gradient_hours » ?", 1, true) ~= nil, true)
messages = store.check_options({ zzzzzzzzzz = 1 }, EXTRA)
check("options : un nom très différent : signalé sans suggestion", #messages == 1 and messages[1]:find("tu voulais dire", 1, true) == nil, true)
check("options : une option hors schéma mais déclarée est acceptée", #store.check_options({ data_file = "/tmp/x", cell_color = function() end }, EXTRA), 0)
check("options : sans liste d'options supplémentaires, open_key est inconnue", #store.check_options({ open_key = "F3" }), 1)
messages = store.check_options({ max_months = 100 }, EXTRA)
check("options : une valeur hors limites est signalée", #messages, 1)
check("options : le message cite le nom et les bornes", messages[1]:find("« max_months »", 1, true) ~= nil and messages[1]:find("compris entre 1 et 12", 1, true) ~= nil, true)
messages = store.check_options({ lang = "de", center = "oui" }, EXTRA)
check("options : deux valeurs incorrectes : deux messages", #messages, 2)
messages = store.check_options({ "gradient" }, EXTRA)
check("options : une liste à la place de réglages nommés", #messages == 1 and messages[1]:find("sans nom", 1, true) ~= nil, true)
messages = store.check_options({ zeta = 1, alpha = 2 }, EXTRA)
check("options : les messages sont dans l'ordre alphabétique", messages[1]:find("alpha", 1, true) ~= nil and messages[2]:find("zeta", 1, true) ~= nil, true)
local crashed = false
for _, weird in ipairs({ { [true] = 1 }, { [1.5] = 1 }, { [{}] = 1 }, setmetatable({}, { __index = function() error("boum") end }) }) do
if not pcall(store.check_options, weird, EXTRA) then
crashed = true
end
end
check("options : des tables bizarres ne font pas planter", crashed, false)

-- ============================================================
-- effets de bord
-- ============================================================
check("aucune écriture hors des dossiers temporaires", #outside, 0)
for _, d in ipairs(homes) do
os.execute("rm -rf '" .. d .. "'")
end
local leaked = {}
for k in pairs(_G) do
if not globals_before[k] then
leaked[#leaked + 1] = k
end
end
check("aucune variable globale ajoutée", table.concat(leaked, ","), "")

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
