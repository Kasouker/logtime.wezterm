-- tests/storage/test_persist.lua : teste la sauvegarde des heures par plugin/init.lua (fusion avec le fichier,
-- cadence, copie de sécurité, fichier abîmé, échecs) avec une fausse API WezTerm. Aucun vrai WezTerm nécessaire.
-- Lancer :   lua5.4 tests/storage/test_persist.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]storage[/\\]test_persist%.lua$") or "."

local passed, failed = 0, 0
local current_mode_label = ""
local function check(name, got, want)
	name = current_mode_label .. name
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

local globals_before = {}
for k in pairs(_G) do
	globals_before[k] = true
end

-- ---- un faux wezterm.GLOBAL aussi difficile que le vrai (voir plugin/init.lua) :
--   * une table lue dans GLOBAL est un objet "Value" qui ne se compare pas à un nombre ;
--   * en mode "wrapped", même les nombres lus sont des objets "Value" (additionnables, jamais comparables) ;
--   * ici, ÉCRIRE une table dans GLOBAL est une erreur : le plugin ne doit garder que des valeurs simples.
local VALUE = {}
VALUE.__index = VALUE
local function raw(x)
	if type(x) == "table" and getmetatable(x) == VALUE then
		return x.__v
	end
	return x
end
VALUE.__add = function(a, b)
	return raw(a) + raw(b)
end
VALUE.__sub = function(a, b)
	return raw(a) - raw(b)
end
VALUE.__mul = function(a, b)
	return raw(a) * raw(b)
end
VALUE.__div = function(a, b)
	return raw(a) / raw(b)
end
VALUE.__unm = function(a)
	return -raw(a)
end
VALUE.__tostring = function(a)
	return tostring(raw(a))
end
-- pas de __lt ni de __le : comparer un Value à un nombre est une erreur, comme chez toi

local current_mode = "plain"
local function hostile_global(initial)
	local store = {}
	for k, v in pairs(initial or {}) do
		store[k] = v
	end
	return setmetatable({}, {
		__index = function(_, k)
			local v = store[k]
			if type(v) == "table" or (current_mode == "wrapped" and type(v) == "number") then
				return setmetatable({ __v = v }, VALUE)
			end
			return v
		end,
		__newindex = function(_, k, v)
			if type(v) == "table" or type(v) == "function" or type(v) == "userdata" then
				error(
					"test : wezterm.GLOBAL n'accepte ici que des valeurs simples (reçu "
						.. type(v)
						.. " pour "
						.. tostring(k)
						.. ")",
					2
				)
			end
			store[k] = v
		end,
		__pairs = function()
			return next, store, nil
		end,
	})
end

-- ---- horloge simulée et surveillance des écritures
local clock = { now = 0 }
local real_time = os.time
os.time = function(t)
	if t then
		return real_time(t)
	end
	return clock.now
end
local function ts(y, mo, d, h, mi, s)
	return real_time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s })
end

local writes = {}
local real_open = io.open
io.open = function(path, mode)
	if mode and (mode:find("w") or mode:find("a") or mode:find("%+")) then
		writes[#writes + 1] = path
	end
	return real_open(path, mode)
end
local function reset_writes()
	writes = {}
end
local function writes_matching(pattern)
	local n = 0
	for _, p in ipairs(writes) do
		if p:find(pattern) then
			n = n + 1
		end
	end
	return n
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
local function write(path, text)
	local f = assert(real_open(path, "wb"))
	f:write(text)
	f:close()
end
local function list(dir)
	local names = {}
	local p = io.popen("ls -A '" .. dir .. "' 2>/dev/null")
	for line in p:lines() do
		names[#names + 1] = line
	end
	p:close()
	table.sort(names)
	return names
end
local function has_prefix(dir, prefix)
	for _, n in ipairs(list(dir)) do
		if n:sub(1, #prefix) == prefix then
			return n
		end
	end
	return nil
end

local ICON = utf8.char(0xF017)
local FILE = ".logtime.json"
local days_mod = assert(loadfile(root .. "/plugin/logtime/storage/days.lua"))()

-- Un environnement neuf : dossier personnel temporaire, fausse API, module chargé
local function new_env(opts)
	opts = opts or {}
	local home = os.tmpname()
	os.remove(home)
	os.execute("mkdir -p '" .. home .. "'")
	local logs = { error = {}, info = {} }
	local fake = {
		GLOBAL = hostile_global(opts.global),
		home_dir = home,
		log_error = function(m)
			logs.error[#logs.error + 1] = m
		end,
		log_info = function(m)
			logs.info[#logs.info + 1] = m
		end,
	}
	if opts.file then
		write(home .. "/" .. FILE, opts.file)
	end
	package.loaded["wezterm"] = fake
	local function load_module()
		return assert(loadfile(root .. "/plugin/init.lua"))(root)
	end
	local env =
		{ home = home, fake = fake, logs = logs, path = home .. "/" .. FILE, load = load_module, M = load_module() }
	return env
end
local function run(env, t0, seconds)
	local text
	for i = 0, seconds do
		clock.now = t0 + i
		text = env.M.tick(nil)
	end
	return text
end
local function cleanup(env)
	os.execute("rm -rf '" .. env.home .. "'")
end

local HISTORY = '{"2026-10-10":15231,"2026-10-11":1900}'

local function scenarios()
	local t0 = ts(2026, 10, 12, 12, 0, 0)

	-- ============================================================
	-- 1. Aucun fichier au départ : il se crée, puis se met à jour toutes les 10 s
	-- ============================================================
	local e = new_env()
	clock.now = t0
	e.M.tick(nil)
	check("sans fichier : premier appel, rien n'est écrit (rien n'est encore compté)", read(e.path), nil)
	clock.now = t0 + 1
	e.M.tick(nil)
	check("sans fichier : dès la première seconde comptée, le fichier est créé", read(e.path), '{"2026-10-12":1}')
	run(e, t0 + 1, 8) -- jusqu'à t0 + 9
	check("sans fichier : 8 s plus tard, pas de nouvelle écriture (cadence de 10 s)", read(e.path), '{"2026-10-12":1}')
	clock.now = t0 + 11
	e.M.tick(nil)
	check(
		"sans fichier : 10 s après la précédente sauvegarde, le fichier est mis à jour",
		read(e.path),
		'{"2026-10-12":11}'
	)
	clock.now = t0 + 15
	e.M.tick(nil)
	check("sans fichier : entre deux sauvegardes, le fichier ne bouge pas", read(e.path), '{"2026-10-12":11}')
	check("sans fichier : aucune erreur", #e.logs.error, 0)
	check("sans fichier : pas de fichier temporaire laissé", has_prefix(e.home, FILE .. ".tmp"), nil)
	cleanup(e)

	-- ============================================================
	-- 2. Ton vrai historique est conservé à l'identique
	-- ============================================================
	e = new_env({ file = HISTORY })
	clock.now = t0
	check("historique : premier appel, la journée du 12 commence à zéro", e.M.tick(nil), ICON .. " 00:00:00")
	check("historique : lecture seule tant que rien n'est compté, aucune écriture", read(e.path), HISTORY)
	local text = run(e, t0, 15)
	check("historique : le compteur avance", text, ICON .. " 00:00:15")
	check(
		"historique : le 10 et le 11 octobre sont conservés exactement, le 12 est ajouté",
		read(e.path),
		'{"2026-10-10":15231,"2026-10-11":1900,"2026-10-12":11}'
	)
	cleanup(e)

	-- le jour en cours est déjà dans le fichier : on reprend ce total
	e = new_env({ file = '{"2026-10-11":1900,"2026-10-12":3600}' })
	clock.now = t0
	check("reprise : le total du jour vient du fichier", e.M.tick(nil), ICON .. " 01:00:00")
	text = run(e, t0, 12)
	check("reprise : le compteur continue à partir du total du fichier", text, ICON .. " 01:00:12")
	check(
		"reprise : le fichier est mis à jour sans perdre les autres jours",
		read(e.path),
		'{"2026-10-11":1900,"2026-10-12":3611}'
	)
	cleanup(e)

	-- ============================================================
	-- 3. Fusion avec ce qui est déjà compté en mémoire : le plus grand des deux, jamais la somme
	-- ============================================================
	e = new_env({
		file = '{"2026-10-10":500,"2026-10-12":3600}',
		global = { logtime_days_json = '{"2026-10-12":600,"2026-10-13":40}' },
	})
	clock.now = t0
	check("fusion : le fichier (3600) l'emporte sur la mémoire (600)", e.M.tick(nil), ICON .. " 01:00:00")
	check(
		"fusion : un jour présent seulement dans la mémoire est gardé",
		days_mod.decode(e.fake.GLOBAL.logtime_days_json)["2026-10-13"],
		40
	)
	check(
		"fusion : un jour présent seulement dans le fichier est gardé",
		days_mod.decode(e.fake.GLOBAL.logtime_days_json)["2026-10-10"],
		500
	)
	check(
		"fusion : la mémoire apportait du nouveau : le fichier est réécrit tout de suite avec les trois jours",
		read(e.path),
		'{"2026-10-10":500,"2026-10-12":3600,"2026-10-13":40}'
	)
	run(e, t0, 11)
	check(
		"fusion : puis mis à jour 10 s plus tard",
		read(e.path),
		'{"2026-10-10":500,"2026-10-12":3610,"2026-10-13":40}'
	)
	cleanup(e)

	e = new_env({ file = '{"2026-10-12":3600}', global = { logtime_days_json = '{"2026-10-12":7200}' } })
	clock.now = t0
	check("fusion : la mémoire (7200) l'emporte sur le fichier (3600)", e.M.tick(nil), ICON .. " 02:00:00")
	cleanup(e)

	-- ============================================================
	-- 4. Pas de réécriture inutile
	-- ============================================================
	e = new_env({ file = HISTORY })
	e.M.setup({ sleep_limit = 0 })
	clock.now = t0
	e.M.tick(nil)
	reset_writes()
	clock.now = t0 + 600 -- une veille qui ne compte pas : rien de nouveau à sauvegarder
	e.M.tick(nil)
	clock.now = t0 + 700
	e.M.tick(nil)
	check("rien de nouveau : aucune écriture", #writes, 0)
	check("rien de nouveau : le fichier est intact", read(e.path), HISTORY)
	cleanup(e)

	-- tout est sauvegardé : les secondes qui passent sans rien compter (veille non comptée) n'écrivent plus rien
	e = new_env({ file = HISTORY })
	e.M.setup({ sleep_limit = 0 })
	run(e, t0, 12)
	clock.now = t0 + 22
	e.M.tick(nil) -- sauvegarde du dernier temps compté
	reset_writes()
	clock.now = t0 + 40
	e.M.tick(nil)
	clock.now = t0 + 60
	e.M.tick(nil)
	check("tout est sauvegardé : plus aucune écriture tant que rien de nouveau n'est compté", #writes, 0)
	cleanup(e)

	-- deux fenêtres qui appellent tick la même seconde : une seule sauvegarde
	e = new_env({ file = HISTORY })
	clock.now = t0
	e.M.tick(nil)
	clock.now = t0 + 1
	e.M.tick(nil)
	reset_writes()
	e.M.tick(nil)
	e.M.tick(nil)
	check("deux fenêtres, même seconde : aucune écriture supplémentaire", writes_matching("%.tmp$"), 0)
	cleanup(e)

	-- ============================================================
	-- 5. Copie de sécurité : une fois par session, de l'état d'avant
	-- ============================================================
	e = new_env({ file = HISTORY })
	run(e, t0, 35)
	check("copie de sécurité : créée, identique au fichier d'origine", read(e.path .. ".bak"), HISTORY)
	check(
		"copie de sécurité : pas réécrite aux sauvegardes suivantes (le fichier a pourtant changé)",
		read(e.path) ~= HISTORY and read(e.path .. ".bak") == HISTORY,
		true
	)
	cleanup(e)

	e = new_env()
	run(e, t0, 5)
	check("copie de sécurité : sans fichier au départ, pas de copie inventée", read(e.path .. ".bak"), nil)
	cleanup(e)

	-- ============================================================
	-- 6. Fichier abîmé : mis de côté, jamais écrasé
	-- ============================================================
	local broken = '{"2026-10-10":15231,"2026-10-1'
	e = new_env({ file = broken })
	clock.now = t0
	e.M.tick(nil)
	local kept = has_prefix(e.home, FILE .. ".corrupt-")
	check("fichier abîmé : mis de côté sous un nouveau nom", kept ~= nil, true)
	check("fichier abîmé : son contenu est conservé tel quel", kept and read(e.home .. "/" .. kept), broken)
	check("fichier abîmé : l'emplacement d'origine est libre", read(e.path), nil)
	check("fichier abîmé : l'erreur est écrite dans les journaux", #e.logs.error, 1)
	check("fichier abîmé : le message dit où il est", e.logs.error[1]:find(".corrupt-", 1, true) ~= nil, true)
	text = run(e, t0, 12)
	check("fichier abîmé : le comptage continue", text, ICON .. " 00:00:12")
	check("fichier abîmé : un nouveau fichier valide est écrit", read(e.path), '{"2026-10-12":11}')
	check("fichier abîmé : une seule erreur dans les journaux", #e.logs.error, 1)
	cleanup(e)

	-- impossible de mettre le fichier de côté : on ne l'écrase surtout pas
	e = new_env({ file = broken })
	local real_rename = os.rename
	local rename_calls = 0
	os.rename = function(from)
		if tostring(from):find("%.logtime%.json$") then -- seulement le fichier d'heures (pas les autres fichiers)
			rename_calls = rename_calls + 1
		end
		return nil, "refusé"
	end
	reset_writes()
	text = run(e, t0, 25)
	check("fichier abîmé non déplaçable : le comptage continue", text, ICON .. " 00:00:25 ⚠")
	check("fichier abîmé non déplaçable : le fichier n'est PAS écrasé", read(e.path), broken)
	check(
		"fichier abîmé non déplaçable : aucune écriture dans le fichier",
		writes_matching("%.logtime%.json$") + writes_matching("%.logtime%.json%.tmp$"),
		0
	)
	check(
		"fichier abîmé non déplaçable : l'erreur n'est écrite qu'UNE fois (pas à chaque seconde)",
		#e.logs.error,
		1
	)
	text = run(e, t0 + 26, 120)
	check("fichier abîmé non déplaçable : toujours une seule erreur au bout de 2 minutes", #e.logs.error, 1)
	check(
		"fichier abîmé non déplaçable : nouvelles tentatives rares (toutes les 60 s), pas à chaque seconde",
		rename_calls <= 4,
		true
	)
	os.rename = real_rename
	text = run(e, t0 + 147, 70) -- la nouvelle tentative (toutes les 60 s) réussit, le fichier est mis de côté
	check(
		"fichier abîmé non déplaçable : une fois le problème réglé, le fichier est mis de côté",
		has_prefix(e.home, FILE .. ".corrupt-") ~= nil,
		true
	)
	check(
		"fichier abîmé non déplaçable : puis un nouveau fichier valide est écrit",
		read(e.path) ~= nil and read(e.path):find('"2026-10-12":', 1, true) ~= nil,
		true
	)
	check("fichier abîmé non déplaçable : le point d'alerte a disparu", text:sub(-1) ~= "⚠", true)
	cleanup(e)

	-- ============================================================
	-- 7. Échec de sauvegarde : le comptage continue, la barre le signale, tout rentre dans l'ordre ensuite
	-- ============================================================
	e = new_env()
	e.M.setup({ data_file = e.home .. "/pas_encore/.logtime.json" })
	text = run(e, t0, 12)
	check("échec de sauvegarde : la barre affiche un point d'alerte", text, ICON .. " 00:00:12 ⚠")
	check("échec de sauvegarde : le comptage n'est pas interrompu", e.M.today_seconds(), 12)
	check("échec de sauvegarde : une seule erreur dans les journaux", #e.logs.error, 1)
	check(
		"échec de sauvegarde : le message le dit",
		e.logs.error[1]:find("sauvegarde impossible", 1, true) ~= nil,
		true
	)
	os.execute("mkdir -p '" .. e.home .. "/pas_encore'")
	text = run(e, t0 + 13, 12)
	check(
		"échec de sauvegarde : le dossier existe maintenant, le point d'alerte disparaît",
		text,
		ICON .. " 00:00:25"
	)
	check(
		"échec de sauvegarde : le fichier est écrit à la tentative suivante (toutes les 10 s)",
		read(e.home .. "/pas_encore/.logtime.json"),
		'{"2026-10-12":21}'
	)
	cleanup(e)

	-- ============================================================
	-- 8. Passage de minuit
	-- ============================================================
	e = new_env({ file = HISTORY })
	local m0 = ts(2026, 10, 12, 23, 59, 58)
	run(e, m0, 14)
	check(
		"minuit : les deux jours sont sauvegardés (dernière sauvegarde à la seconde 11)",
		read(e.path),
		'{"2026-10-10":15231,"2026-10-11":1900,"2026-10-12":2,"2026-10-13":9}'
	)
	cleanup(e)

	-- ============================================================
	-- 9. Rechargement de la config : le fichier n'est pas relu, l'état continue
	-- ============================================================
	e = new_env({ file = HISTORY })
	run(e, t0, 5)
	write(e.path, "contenu inattendu écrit par quelqu'un d'autre")
	e.M = e.load()
	clock.now = t0 + 6
	text = e.M.tick(nil)
	check("rechargement : le comptage continue", text, ICON .. " 00:00:06")
	check("rechargement : le fichier n'est pas relu ni mis de côté", has_prefix(e.home, FILE .. ".corrupt-"), nil)
	cleanup(e)

	-- ============================================================
	-- 10. Beaucoup d'historique, et chemin par défaut
	-- ============================================================
	local parts = {}
	local expected_history = {}
	for i = 0, 399 do
		local key = os.date("%Y-%m-%d", ts(2025, 1, 1, 12, 0, 0) + i * 86400)
		expected_history[#expected_history + 1] = string.format('"%s":%d', key, 1000 + i)
	end
	table.sort(expected_history)
	local big = "{" .. table.concat(expected_history, ",") .. "}"
	e = new_env({ file = big })
	run(e, t0, 12)
	local before_days = days_mod.decode(big)
	local after_days = days_mod.decode(read(e.path))
	local identical = after_days ~= nil
	for key, secs in pairs(before_days) do
		if not after_days or after_days[key] ~= secs then
			identical = false
		end
	end
	check("400 jours d'historique : tous conservés avec exactement les mêmes valeurs", identical, true)
	check("400 jours d'historique : le jour du 12 est ajouté", after_days and after_days["2026-10-12"], 11)
	check("chemin par défaut : <dossier personnel>/.logtime.json", read(e.home .. "/.logtime.json") ~= nil, true)
	cleanup(e)

	-- ============================================================
	-- 11. Ce que laisse une ancienne version, et un texte d'état illisible
	-- ============================================================
	-- l'ancienne version gardait une TABLE dans GLOBAL : la nouvelle ne la lit pas, ne plante pas, et la retire
	e = new_env({ file = HISTORY, global = { logtime_days = { ["2026-10-12"] = 99999 }, logtime_last = 5 } })
	clock.now = t0
	text = e.M.tick(nil)
	check("ancienne version : pas d'erreur malgré la table laissée dans GLOBAL", #e.logs.error, 0)
	check("ancienne version : le total du jour vient du fichier, pas de l'ancien test", text, ICON .. " 00:00:00")
	check("ancienne version : l'ancienne table est retirée de GLOBAL", e.fake.GLOBAL.logtime_days, nil)
	check(
		"ancienne version : GLOBAL n'en contient plus",
		(function()
			for k in pairs(e.fake.GLOBAL) do
				if k == "logtime_days" then
					return true
				end
			end
			return false
		end)(),
		false
	)
	cleanup(e)

	-- le texte gardé en mémoire devient illisible : on relit le fichier, l'historique n'est pas perdu
	e = new_env({ file = HISTORY })
	run(e, t0, 15)
	local before_garbage = read(e.path)
	e.fake.GLOBAL.logtime_days_json = "n'importe quoi"
	e.M = e.load() -- rechargement de la config : le module relit son état dans GLOBAL
	run(e, t0 + 16, 12)
	local after_garbage = days_mod.decode(read(e.path))
	check(
		"état illisible : le fichier est relu, l'historique du 10 et du 11 n'est pas perdu",
		after_garbage and after_garbage["2026-10-10"] == 15231 and after_garbage["2026-10-11"] == 1900,
		true
	)
	check(
		"état illisible : le jour en cours n'est pas remis à zéro",
		(after_garbage and after_garbage["2026-10-12"] or 0) >= 10,
		true
	)
	check("état illisible : aucune erreur", #e.logs.error, 0)
	cleanup(e)

	-- ============================================================
	-- 12. Effets de bord
	-- ============================================================
	e = new_env({ file = HISTORY })
	run(e, t0, 30)
	local foreign = {}
	for k in pairs(e.fake.GLOBAL) do
		if not k:find("^logtime_") then
			foreign[#foreign + 1] = k
		end
	end
	check("wezterm.GLOBAL : seulement des clés logtime_*", table.concat(foreign, ","), "")
	local names = {}
	for _, n in ipairs(list(e.home)) do
		names[#names + 1] = n
	end
	check(
		"dossier personnel : seulement le fichier d'heures, sa copie de sécurité et le temps par projet",
		table.concat(names, ","),
		FILE .. "," .. FILE .. ".bak,.logtime_projects.json"
	)
	cleanup(e)
end

-- tout est joué deux fois : avec un GLOBAL qui renvoie de vrais nombres, puis avec un GLOBAL qui renvoie des objets Value
current_mode = "plain"
current_mode_label = ""
scenarios()
current_mode = "wrapped"
current_mode_label = "[nombres Value] "
scenarios()

local leaked = {}
for k in pairs(_G) do
	if not globals_before[k] then
		leaked[#leaked + 1] = k
	end
end
check("aucune variable globale ajoutée", table.concat(leaked, ","), "")

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
