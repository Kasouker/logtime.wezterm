-- plugin/init.lua : point d'entrée du plugin logtime.
-- Le compteur dans la barre d'onglets, la sauvegarde des heures dans .logtime.json, et la page du calendrier (touche F2).
--
-- Ce fichier est chargé par logtime_plugin.lua, qui lui transmet le dossier du plugin :
--   local logtime = chunk(dossier_du_plugin)
local wezterm = require("wezterm")
local sep = package.config:sub(1, 1)

local M = {}
M.version = "1.0.3" -- MAJEUR.MINEUR.CORRECTIF : 1.0.1 une correction, 1.1.0 une nouveauté, 2.0.0 si la config des gens casse

-- ------------------------------------------------------------
-- Retrouver le dossier du plugin
-- ------------------------------------------------------------
-- Un dossier est le bon s'il contient plugin/logtime/core/counter.lua.
local function is_plugin_dir(dir)
	if type(dir) ~= "string" or dir == "" then
		return false
	end
	local f = io.open(table.concat({ dir, "plugin", "logtime", "core", "counter.lua" }, sep), "rb")
	if f then
		f:close()
		return true
	end
	return false
end

-- Trois pistes : le dossier transmis par le chargeur (logtime_plugin.lua), la liste des plugins de WezTerm,
-- puis un dossier "logtime.wezterm" placé dans le dossier de config.
local function find_plugin_dir(given)
	if is_plugin_dir(given) then
		return given
	end
	local ok, list = pcall(function()
		return wezterm.plugin.list()
	end)
	if ok and type(list) == "table" then
		for _, p in ipairs(list) do
			if is_plugin_dir(p.plugin_dir) then
				return p.plugin_dir
			end
		end
	end
	if type(wezterm.config_dir) == "string" then
		local candidate = wezterm.config_dir .. sep .. "logtime.wezterm"
		if is_plugin_dir(candidate) then
			return candidate
		end
	end
	return nil
end

local DIR = find_plugin_dir(...)
if not DIR then
	error("logtime: plugin folder not found (it must contain plugin/logtime/core/counter.lua)", 0)
end

-- ------------------------------------------------------------
-- Charger les modules
-- ------------------------------------------------------------
local cache = {}
local function load_module(name)
	if cache[name] == nil then
		local path = table.concat({ DIR, "plugin", "logtime", (name:gsub("/", sep)) .. ".lua" }, sep)
		local f = io.open(path, "rb")
		if not f then
			error("logtime: module not found: " .. path, 0)
		end
		local source = f:read("*a")
		f:close()
		local chunk, err = load(source, "@" .. path)
		if not chunk then
			error(err, 0)
		end
		cache[name] = chunk(load_module)
	end
	return cache[name]
end

local day = load_module("core/day")
local counter = load_module("core/counter")
local idle = load_module("core/idle")
local activity = load_module("core/activity")
local timeline = load_module("core/timeline")
local status = load_module("status/status")
local auto = load_module("status/auto")
local storage = load_module("storage/days")
local projects_storage = load_module("storage/projects")
local timeline_storage = load_module("storage/timeline")
local platform = load_module("system/platform")
local location = load_module("storage/location")
local calendar_page = load_module("pages/calendar_page")
local keys = load_module("config/keys")
local settings = load_module("settings/store")
local settings_page = load_module("pages/settings_page")
local theme = load_module("color/theme")
local safe = load_module("ui/safe")

-- Options provisoires : elles iront dans config/defaults.lua à une étape suivante.
local cfg = {
	normal_gap = 5, -- un écart de 5 s ou moins entre deux mises à jour est du temps normal
	sleep_limit = 3900, -- veille comptée par épisode : 65 min
	settle_time = 60, -- secondes d'utilisation continue avant de rendre le budget de veille
	day_offset = 0, -- 0 : la journée change à minuit
	save_every = 10, -- sauvegarde dans le fichier toutes les 10 secondes (s'il y a du nouveau)
	data_file = nil, -- nil : <dossier personnel>/.logtime.json
	idle_after = 300, -- rien ne bouge dans le terminal pendant 5 min : ce temps est noté comme inactif (il compte quand même)
	idle_file = nil, -- nil : <dossier personnel>/.logtime_idle.json (le temps inactif par jour)
	projects_file = nil, -- nil : <dossier personnel>/.logtime_projects.json (le temps actif par projet et par jour)
	timeline_file = nil, -- nil : <dossier des fichiers>/.logtime_timeline.json (à quelle heure chaque projet a été utilisé)
	week_starts_on = "monday", -- ou "sunday"
	goal_hours = nil, -- nombre d'heures par jour qui comptent pour « objectif atteint » (nil : pas d'objectif)
	lang = "en", -- "en" ou "fr"
	open_key = "F2", -- la touche qui ouvre le calendrier
	settings_key = "F4", -- la touche qui ouvre la page de personnalisation
	debug = false, -- true : chaque touche et chaque dessin des pages sont écrits dans les journaux de WezTerm
}

-- Les noms d'options valables en plus de ceux du schéma des réglages (settings/schema.lua).
local EXTRA_OPTIONS = {
	"normal_gap",
	"sleep_limit",
	"settle_time",
	"day_offset",
	"save_every",
	"data_file",
	"idle_after",
	"idle_file",
	"projects_file",
	"timeline_file",
	"settings_file",
	"settings_key",
	"open_key",
	"cell_color",
	"heat",
	"thresholds",
	"status", -- false : ne pas afficher le compteur dans la barre (il compte quand même)
	"debug",
}

-- Le dossier des fichiers du plugin : <dossier personnel>/.local/share/logtime (voir storage/location.lua : un
-- fichier écrit à côté de la config fait recharger la config). Préparé une fois par lancement de WezTerm (le résultat
-- est gardé dans wezterm.GLOBAL) : créé s'il manque, et les fichiers de l'ancien emplacement (le dossier personnel) y
-- sont copiés. Au moindre problème, l'ancien emplacement est gardé (jamais d'heures comptées à part) et c'est écrit
-- dans les journaux ; la prochaine fois que WezTerm démarre, on réessaie.
local function data_dir()
	local G_ = wezterm.GLOBAL
	if G_.logtime_data_dir ~= nil then
		return tostring(G_.logtime_data_dir)
	end
	local home = wezterm.home_dir
	local dir = location.dir(home, sep)
	local chosen = dir
	if not location.writable(dir, sep) then
		pcall(wezterm.run_child_process, location.mkdir_args(platform.os_name(wezterm.target_triple), dir))
	end
	if not location.writable(dir, sep) then
		wezterm.log_error("logtime: cannot create the folder " .. dir .. "; the files stay in " .. home)
		chosen = home
	else
		local copied, problems = location.migrate(home, dir, sep)
		if #problems > 0 then
			for _, problem in ipairs(problems) do
				wezterm.log_error(
					"logtime: cannot copy to " .. dir .. ": " .. problem .. " (the original is untouched)"
				)
			end
			wezterm.log_error("logtime: the files stay in " .. home .. " (new attempt at the next start)")
			chosen = home
		elseif #copied > 0 then
			wezterm.log_info(
				"logtime: files copied to "
					.. dir
					.. ": "
					.. table.concat(copied, ", ")
					.. ". The originals, in "
					.. home
					.. ", are no longer used: you can delete them."
			)
		end
	end
	G_.logtime_data_dir = chosen
	return chosen
end

-- Le fichier des réglages choisis par l'utilisateur : <dossier des fichiers>/.logtime_settings.json
local function settings_path()
	return cfg.settings_file or (data_dir() .. sep .. ".logtime_settings.json")
end

-- Les réglages, par ordre de priorité croissante : valeurs par défaut du plugin, options de wezterm.lua, fichier de réglages.
-- Un réglage du fichier qui est inconnu ou incorrect est ignoré et signalé dans les journaux de WezTerm.
function M.setup(opts)
	if type(opts) == "table" then
		for key, value in pairs(opts) do
			cfg[key] = value
		end
	end
	local saved, _, problems = settings.load(settings_path())
	for key, value in pairs(saved) do
		cfg[key] = value
	end
	for _, problem in ipairs(problems) do
		wezterm.log_error("logtime: settings: " .. problem)
	end
	safe.debug = cfg.debug == true
	return M
end

local function data_path()
	return cfg.data_file or (data_dir() .. sep .. ".logtime.json")
end

-- ------------------------------------------------------------
-- L'état, gardé dans wezterm.GLOBAL (il survit au rechargement de la config, pas à la fermeture de WezTerm)
-- ------------------------------------------------------------
-- Deux précautions, apprises sur un vrai WezTerm :
--   1. Une table lue dans wezterm.GLOBAL n'est pas une vraie table Lua : ses valeurs sont des objets "Value" qui
--      s'additionnent mais ne se comparent pas à un nombre. On n'y met donc JAMAIS de table : les heures par jour y
--      sont gardées sous forme de texte (le même que le fichier), et lues dans une vraie table Lua locale.
--   2. Même un nombre lu dans GLOBAL peut être un objet "Value" : num() le convertit toujours en vrai nombre.
--
--   logtime_days_json     : les heures par jour, en texte
--   logtime_last, logtime_budget, logtime_calm : le comptage
--   logtime_storage_ready : le fichier a été lu et fusionné dans cette session
--   logtime_dirty         : il y a du temps compté qui n'est pas encore dans le fichier
--   logtime_saved         : l'instant de la dernière tentative de sauvegarde
--   logtime_backup_done   : la copie de sécurité de la session a été faite
--   logtime_save_failed   : la dernière sauvegarde a échoué (la barre affiche alors un point d'alerte)
--   logtime_sync_retry_at, logtime_sync_error_logged : nouvelle tentative de lecture du fichier dans une minute
local G = wezterm.GLOBAL

local function num(v, default)
	if type(v) == "number" then
		return v
	end
	if v ~= nil then
		local ok, n = pcall(function()
			return v + 0
		end)
		if ok and type(n) == "number" then
			return n
		end
	end
	return default
end

-- ------------------------------------------------------------
-- Plusieurs WezTerm ouverts en même temps (plusieurs processus, chacun son GLOBAL) écrivent les mêmes fichiers.
-- ------------------------------------------------------------
-- Chacun a un identifiant (gardé dans GLOBAL : il survit aux rechargements de la config, pas à la fermeture) :
--   - son fichier temporaire porte cet identifiant : deux WezTerm ne s'écrasent jamais pendant une écriture ;
--   - avant chaque sauvegarde, le fichier est relu et fusionné (la plus grande valeur) : aucun n'efface ce qu'un
--     autre a compté ;
--   - un seul attribue le temps aux projets et à l'inactif : le dernier qui a eu une fenêtre au premier plan (il
--     écrit son identifiant dans .logtime_focus). Les autres comptent les heures, mais ne savent pas où tu travailles.
--   logtime_process_token : l'identifiant de ce WezTerm
--   logtime_focus_owner, logtime_focus_read_at : le WezTerm qui attribue (lu au plus toutes les FOCUS_READ_EVERY s)
local FOCUS_READ_EVERY = 2

local function process_token()
	local token = G.logtime_process_token
	if token == nil then
		token = string.format("%x%06x", os.time(), math.random(0, 0xFFFFFF))
		G.logtime_process_token = token
	end
	return tostring(token)
end

-- Le fichier temporaire de ce WezTerm pour `path`.
local function tmp_of(path)
	return path .. "." .. process_token() .. ".tmp"
end

local function focus_path()
	return data_dir() .. sep .. ".logtime_focus"
end

-- Une fenêtre de ce WezTerm est au premier plan : il devient celui qui attribue (s'il ne l'était pas déjà). Le temps
-- passé ailleurs n'est pas de l'inactivité de ce WezTerm : sa dernière activité repart de maintenant.
local function claim_focus(now)
	local me = process_token()
	if G.logtime_focus_owner ~= nil and tostring(G.logtime_focus_owner) == me then
		return
	end
	local f = io.open(focus_path(), "wb")
	if f then
		f:write(me)
		f:close()
	end
	G.logtime_focus_owner = me
	G.logtime_focus_read_at = now
	G.logtime_last_activity = now
	G.logtime_idle_marked = nil
end

-- Ce WezTerm attribue-t-il le temps aux projets et à l'inactif ? Oui s'il est le dernier au premier plan, ou si
-- personne ne l'est encore (un seul WezTerm ouvert : comme avant).
local function is_focus_owner(now)
	local read_at = num(G.logtime_focus_read_at)
	if not read_at or now - read_at >= FOCUS_READ_EVERY or now < read_at then
		G.logtime_focus_read_at = now
		local f = io.open(focus_path(), "rb")
		if f then
			local owner = (f:read("*a") or ""):match("^%s*(%x+)%s*$")
			f:close()
			if owner then
				G.logtime_focus_owner = owner
			end
		end
	end
	local owner = G.logtime_focus_owner
	return owner == nil or tostring(owner) == process_token()
end

-- L'ancienne version gardait une table dans GLOBAL : on la retire, elle ne sert plus.
pcall(function()
	G.logtime_days = nil
end)

-- Les heures par jour de cette session : une vraie table Lua, reconstruite depuis GLOBAL après un rechargement.
local days_mem = nil

local function get_days()
	if not days_mem then
		local text = G.logtime_days_json
		local decoded = type(text) == "string" and storage.decode(text) or nil
		days_mem = decoded or {}
		if not decoded and G.logtime_storage_ready then
			-- le texte gardé en mémoire est illisible : on relira le fichier plutôt que de repartir de zéro
			G.logtime_storage_ready = false
		end
	end
	return days_mem
end

local function remember(days)
	G.logtime_days_json = storage.encode(days)
end

-- Lit le fichier et le fusionne avec ce qui est déjà compté en mémoire : pour chaque jour, la plus grande des deux
-- valeurs (jamais la somme : on ne risque pas de compter deux fois). Un fichier illisible est mis de côté, jamais écrasé.
-- Quand la lecture échoue, on réessaie une minute plus tard (pas à chaque seconde) et on ne l'écrit qu'une fois dans les journaux.
local function sync_failed(now, message)
	G.logtime_sync_retry_at = now + 60
	G.logtime_save_failed = true
	if not G.logtime_sync_error_logged then
		G.logtime_sync_error_logged = true
		wezterm.log_error(message)
	end
end

local function sync_from_file(now)
	local path = data_path()
	local ok, from_file, state, err = pcall(storage.load, path)
	if not ok then
		sync_failed(now, "logtime: cannot read the hours file: " .. tostring(from_file))
		return
	end

	if state == "corrupt" then
		local moved, qerr = storage.quarantine(path)
		if not moved then
			-- impossible de le mettre de côté : on ne l'écrase surtout pas, on compte en mémoire seulement
			sync_failed(
				now,
				"logtime: the hours file is unreadable ("
					.. tostring(err)
					.. ") and could not be set aside ("
					.. tostring(qerr)
					.. "): nothing is saved"
			)
			return
		end
		wezterm.log_error(
			"logtime: the hours file was unreadable (" .. tostring(err) .. "): it was set aside as " .. moved
		)
	end

	local memory = get_days()
	local merged, dirty = {}, false
	for key, secs in pairs(from_file) do
		merged[key] = secs
	end
	for key, secs in pairs(memory) do
		if (merged[key] or 0) < secs then
			merged[key] = secs
			dirty = true
		end
	end
	days_mem = merged
	remember(merged)
	G.logtime_dirty = dirty
	G.logtime_storage_ready = true
	G.logtime_sync_error_logged = false
	G.logtime_save_failed = false
end

local function maybe_save(now, days)
	if not G.logtime_dirty then
		return
	end
	local last_save = num(G.logtime_saved)
	if last_save and last_save <= now and now - last_save < cfg.save_every then
		return
	end

	local path = data_path()
	if not G.logtime_backup_done then
		pcall(storage.backup, path) -- copie de sécurité de l'état d'avant les écritures de la session
		G.logtime_backup_done = true
	end

	-- Relire juste avant d'écrire : un autre WezTerm a pu sauvegarder entre-temps (on garde la plus grande valeur).
	local read_ok, from_file, state = pcall(storage.load, path)
	if read_ok and state == "corrupt" then
		G.logtime_storage_ready = false -- jamais écrire par-dessus : relu (et mis de côté) au prochain passage
		return
	end
	if read_ok and state == "ok" then
		for key, secs in pairs(from_file) do
			if (days[key] or 0) < secs then
				days[key] = secs
			end
		end
		remember(days)
	end

	local ok, saved, err = pcall(storage.save, path, days, nil, tmp_of(path))
	G.logtime_saved = now
	if ok and saved then
		if G.logtime_save_failed then
			wezterm.log_info("logtime: saved again (the previous problem was temporary)")
		end
		G.logtime_dirty = false
		G.logtime_save_failed = false
	else
		if not G.logtime_save_failed then
			wezterm.log_error("logtime: cannot save: " .. tostring(ok and err or saved))
		end
		G.logtime_save_failed = true
	end
end

-- Lit le fichier d'heures si ce n'est pas encore fait (ou si la dernière tentative a échoué il y a plus d'une minute).
local function ensure_synced(now)
	if G.logtime_storage_ready then
		return
	end
	local retry_at = num(G.logtime_sync_retry_at)
	if not retry_at or now >= retry_at or retry_at > now + 3600 then
		sync_from_file(now)
	end
end

-- ------------------------------------------------------------
-- Les fichiers à côté de .logtime.json : le temps inactif (core/idle.lua) et le temps par projet (core/activity.lua)
-- ------------------------------------------------------------
-- Chaque fichier a dans wezterm.GLOBAL, avec son préfixe (logtime_idle, logtime_projects) :
--   <préfixe>_json   : son contenu, en texte
--   <préfixe>_ready  : le fichier a été lu et fusionné dans cette session
--   <préfixe>_broken : le fichier est illisible et n'a pas pu être mis de côté : on ne l'écrit pas
--   <préfixe>_dirty, <préfixe>_saved, <préfixe>_save_failed : la sauvegarde
-- Et pour l'activité :
--   logtime_last_activity : la dernière fois que quelque chose a bougé dans un terminal
--   logtime_idle_marked   : la dernière activité dont l'inactivité est déjà notée
--   logtime_label         : le projet de l'onglet affiché (le temps compté va à ce projet)
--
--   <préfixe>_base   : le contenu du fichier tel que CE WezTerm l'a lu ou écrit en dernier (en texte)
--
-- side_file(o) : o.prefix, o.what (pour les messages), o.path(), o.decode(texte), o.encode(table),
-- o.merge(mémoire, fichier, base) : reprendre du fichier ce qu'un autre WezTerm a changé (la plus grande des deux
-- valeurs : jamais compter deux fois). Une valeur égale à `base` est la nôtre : on garde la mémoire, même plus petite
-- (le temps inactif, noté après coup, est retiré du projet : la fusion ne doit pas l'y remettre). Sans `base`
-- (la première lecture) : toujours la plus grande.
local function side_file(o)
	local mem = nil
	local file = {}
	local function key(name)
		return o.prefix .. "_" .. name
	end

	-- Le contenu. Le fichier est lu une fois par session et fusionné ; un fichier illisible est mis de côté. Si la
	-- lecture plante, on réessaiera (et on n'écrit rien d'ici là).
	function file.get()
		if not mem then
			local text = G[key("json")]
			mem = (type(text) == "string" and o.decode(text)) or {}
		end
		if not G[key("ready")] and not G[key("broken")] then
			local ok, from_file, state, err = pcall(storage.load, o.path(), o.decode)
			if ok then
				if state == "corrupt" then
					local moved_ok, moved = pcall(storage.quarantine, o.path())
					if not (moved_ok and moved) then
						G[key("broken")] = true -- surtout ne pas l'écraser
						wezterm.log_error(
							"logtime: the "
								.. o.what
								.. " file is unreadable ("
								.. tostring(err)
								.. ") and could not be set aside: it is not saved"
						)
						return mem
					end
					wezterm.log_error(
						"logtime: the "
							.. o.what
							.. " file was unreadable ("
							.. tostring(err)
							.. "): set aside as "
							.. moved
					)
					from_file = {}
				end
				o.merge(mem, from_file, nil)
				G[key("json")] = o.encode(mem)
				G[key("base")] = o.encode(from_file)
				G[key("ready")] = true
			end
		end
		return mem
	end

	-- Le contenu a changé : le garder dans GLOBAL et le sauvegarder bientôt.
	function file.changed()
		G[key("json")] = o.encode(file.get())
		G[key("dirty")] = true
	end

	-- Sauvegarde au plus toutes les save_every secondes, une fois le fichier lu.
	function file.maybe_save(now)
		if not G[key("dirty")] or not G[key("ready")] then
			return
		end
		local last_save = num(G[key("saved")])
		if last_save and last_save <= now and now - last_save < cfg.save_every then
			return
		end
		-- relire juste avant d'écrire : un autre WezTerm a pu sauvegarder entre-temps
		local read_ok, from_file, state = pcall(storage.load, o.path(), o.decode)
		if read_ok and state == "corrupt" then
			G[key("ready")] = false -- jamais écrire par-dessus : relu (et mis de côté) au prochain passage
			return
		end
		if read_ok and state == "ok" then
			local base_text = G[key("base")]
			o.merge(file.get(), from_file, type(base_text) == "string" and o.decode(base_text) or nil)
			G[key("json")] = o.encode(file.get())
		end
		local text = o.encode(file.get())
		local ok, saved, err = pcall(storage.save, o.path(), file.get(), o.encode, tmp_of(o.path()))
		G[key("saved")] = now
		if ok and saved then
			G[key("base")] = text -- ce que le fichier contient maintenant, écrit par nous
			if G[key("save_failed")] then
				wezterm.log_info("logtime: " .. o.what .. " file saved again (the previous problem was temporary)")
			end
			G[key("dirty")] = false
			G[key("save_failed")] = false
		elseif not G[key("save_failed")] then
			G[key("save_failed")] = true
			wezterm.log_error("logtime: cannot save the " .. o.what .. " file: " .. tostring(ok and err or saved))
		end
	end
	return file
end

local idle_file = side_file({
	prefix = "logtime_idle",
	what = "idle time",
	path = function()
		return cfg.idle_file or (data_dir() .. sep .. ".logtime_idle.json")
	end,
	decode = storage.decode,
	encode = storage.encode,
	merge = function(mem, from_file, base)
		for k, secs in pairs(from_file) do
			local ours = base ~= nil and base[k] == secs -- inchangé depuis notre dernière lecture ou écriture
			if not ours and (mem[k] or 0) < secs then
				mem[k] = secs
			end
		end
	end,
})
local get_idle = idle_file.get

local projects_file = side_file({
	prefix = "logtime_projects",
	what = "project time",
	path = function()
		return cfg.projects_file or (data_dir() .. sep .. ".logtime_projects.json")
	end,
	decode = projects_storage.decode,
	encode = projects_storage.encode,
	merge = function(mem, from_file, base)
		for k, of_file_day in pairs(from_file) do
			local of_day = mem[k] or {}
			mem[k] = of_day
			local base_day = base and base[k]
			for label, secs in pairs(of_file_day) do
				local ours = base_day ~= nil and base_day[label] == secs
				if not ours and (of_day[label] or 0) < secs then
					of_day[label] = secs
				end
			end
		end
	end,
})
local get_projects = projects_file.get

-- La frise de la journée (core/timeline.lua) : à quelle heure chaque projet a été utilisé.
local timeline_file = side_file({
	prefix = "logtime_timeline",
	what = "timeline",
	path = function()
		return cfg.timeline_file or (data_dir() .. sep .. ".logtime_timeline.json")
	end,
	decode = timeline_storage.decode,
	encode = timeline_storage.encode,
	merge = timeline.merge,
})
local get_timeline = timeline_file.get

-- Le projet en cours (celui de l'onglet affiché à la dernière mise à jour).
local function current_label()
	local label = G.logtime_label
	return type(label) == "string" and label or activity.OTHER
end

-- Du temps vient d'être compté, de `from` à `to` : il va au projet en cours, et sa part inactive va dans le temps
-- inactif (et elle est retirée du projet : le temps par projet est du temps actif).
local function note_counted(from, to)
	if not is_focus_owner(to) then
		return -- un autre WezTerm est au premier plan : c'est lui qui attribue ce temps
	end
	local label = current_label()
	activity.add(get_projects(), label, from, to, cfg.day_offset)
	timeline.add(get_timeline(), label, from, to, cfg.day_offset)
	local last_activity = num(G.logtime_last_activity)
	local start = idle.span(last_activity, num(G.logtime_idle_marked), from, to, cfg.idle_after)
	if start then
		G.logtime_idle_marked = last_activity
		day.add_interval(get_idle(), start, to, cfg.day_offset)
		idle_file.changed()
		activity.add(get_projects(), label, start, to, cfg.day_offset, -1)
		timeline.remove(get_timeline(), start, to, cfg.day_offset) -- une pause n'est pas du travail sur la frise
	end
	projects_file.changed()
	timeline_file.changed()
end

-- L'empreinte de ce qu'on voit dans un panneau : si elle change, il y a de l'activité. Chaque morceau est lu à part
-- (une information illisible ne gêne pas les autres).
local function pane_fingerprint(pane)
	local parts = {}
	local function add(read)
		local ok, value = pcall(read)
		parts[#parts + 1] = ok and tostring(value) or "?"
	end
	add(function()
		return pane:pane_id()
	end)
	add(function()
		return pane:get_title()
	end)
	add(function()
		local c = pane:get_cursor_position()
		return c.x .. "," .. c.y
	end)
	add(function()
		return pane:get_lines_as_text()
	end)
	return table.concat(parts, "\n")
end

-- Le projet d'un panneau : les pages du plugin comptent pour « logtime » ; sinon son dossier, ou son titre.
-- Le dossier est un objet Url dans les WezTerm récents, du texte dans les anciens : tostring donne l'adresse dans
-- les deux cas.
local function pane_label(pane)
	local ok_id, id = pcall(function()
		return pane:pane_id()
	end)
	if ok_id and id ~= nil and (id == num(G.logtime_page_pane) or id == num(G.logtime_settings_pane)) then
		return "logtime"
	end
	local ok_cwd, cwd = pcall(function()
		local url = pane:get_current_working_dir()
		return url ~= nil and tostring(url) or nil
	end)
	local ok_title, title = pcall(function()
		return pane:get_title()
	end)
	return activity.label(ok_cwd and cwd or nil, ok_title and title or nil)
end

-- La dernière empreinte de chaque fenêtre (elle se perd au rechargement de la config : ça compte comme une activité).
local fingerprints = {}

-- À chaque mise à jour : quelque chose a-t-il bougé dans le panneau actif de cette fenêtre ? Et, si la fenêtre est
-- celle qu'on utilise (elle a le focus), le projet en cours devient celui de son onglet.
local function note_activity(window, pane)
	local ok, id = pcall(function()
		return window:window_id()
	end)
	local key = ok and tostring(id) or "?"
	local current = pane_fingerprint(pane)
	G.logtime_last_activity = idle.note(fingerprints[key], current, num(G.logtime_last_activity), os.time())
	fingerprints[key] = current
	local ok_focus, focused = pcall(function()
		return window:is_focused()
	end)
	if not ok_focus or focused then
		G.logtime_label = pane_label(pane)
	end
	if ok_focus and focused == true then
		claim_focus(os.time())
	end
end

-- ------------------------------------------------------------
-- Le comptage
-- ------------------------------------------------------------
local function compute()
	local now = os.time()
	local days = get_days()
	ensure_synced(now)
	days = get_days()

	local last = num(G.logtime_last)
	local state = { budget = num(G.logtime_budget, 0), calm = num(G.logtime_calm, 0) }

	local added, counted = counter.advance(days, last, now, cfg, state)
	if added then
		remember(days)
		G.logtime_dirty = true
		note_counted(last, last + counted)
	end
	G.logtime_budget = state.budget
	G.logtime_calm = state.calm

	if not last or now > last then
		G.logtime_last = now
	end

	if G.logtime_storage_ready then
		maybe_save(now, days)
	end
	idle_file.maybe_save(now)
	projects_file.maybe_save(now)
	timeline_file.maybe_save(now)
	return days[day.key(now, cfg.day_offset)] or 0
end

-- Les secondes comptées aujourd'hui
function M.today_seconds()
	local days = get_days()
	return days[day.key(os.time(), cfg.day_offset)] or 0
end

-- Les textes dans la langue choisie (le français si la langue demandée n'existe pas).
local function labels()
	local ok, found = pcall(load_module, "i18n/" .. tostring(cfg.lang))
	if ok then
		return found
	end
	return load_module("i18n/fr")
end

-- Fait avancer le compteur et renvoie le texte à afficher. Plusieurs appels dans la même seconde ne comptent le
-- temps qu'une fois (counter.advance ne compte rien si l'instant n'a pas changé).
-- Une erreur ne doit jamais casser la barre : elle est écrite dans les journaux de WezTerm, une seule fois tant que
-- c'est la même (et de nouveau si elle revient après un passage normal).
local function status_text()
	local ok, result = pcall(compute)
	if not ok then
		local message = tostring(result)
		if G.logtime_error_message ~= message then
			G.logtime_error_message = message
			wezterm.log_error("logtime: " .. message)
		end
		return "logtime: error (see logs)"
	end
	if G.logtime_error_message ~= nil then
		G.logtime_error_message = nil
	end
	local text = status.text(result, cfg.goal_hours)
	if G.logtime_save_failed then
		text = text .. " ⚠"
	end
	return text, status.reached(result, cfg.goal_hours)
end

-- La couleur du compteur une fois l'objectif du jour atteint : la couleur du dégradé (réglable dans F4).
local function reached_color()
	local color = cfg.gradient_color
	if type(color) == "string" and color:match("^#%x%x%x%x%x%x$") then
		return color
	end
	return "#C9AB6B"
end

-- Pour ceux qui affichent le compteur eux-mêmes dans leur barre (inutile sinon : le plugin l'affiche tout seul).
-- Fait avancer le compteur et renvoie le texte à afficher. Le plugin note l'appel : il sait alors que quelqu'un
-- affiche déjà le compteur, et ne l'ajoute pas une seconde fois.
function M.tick(window)
	G.logtime_external_tick = os.time()
	return (status_text())
end

-- Le compteur que le plugin ajoute lui-même à la barre de tabline.wez (il ne compte pas comme un appel venu d'ailleurs).
-- tabline n'accepte que du texte brut d'une fonction : la couleur vient d'un élément de style placé juste avant
-- (tabline_style, mis à jour à chaque seconde), et "ResetAttributes" remet ensuite les couleurs de tabline.
local function tabline_component(window)
	return (status_text())
end
local tabline_style = { Attribute = { Intensity = "Normal" } }
local tabline_items = { tabline_style, tabline_component, "ResetAttributes" }

-- Le style du compteur dans tabline : la couleur du dégradé si l'objectif est atteint, sinon rien de spécial.
local function update_tabline_style(reached)
	tabline_style.Foreground = nil
	tabline_style.Attribute = nil
	if reached then
		tabline_style.Foreground = { Color = reached_color() }
	else
		tabline_style.Attribute = { Intensity = "Normal" }
	end
end

-- À chaque mise à jour de WezTerm (update-status) : compter, puis afficher le compteur là où il faut (status/auto.lua).
-- Ne renvoie jamais false : ça empêcherait les autres (tabline.wez…) de dessiner leur barre.
-- 🎉 L'objectif du jour vient d'être atteint : une notification, une seule fois par jour (voir status.goal_event).
-- Une notification qui échoue (Windows peut les masquer) ne gêne rien : le « ✓ » du compteur le montre aussi.
-- Sans objectif, reached est toujours faux : rien n'est jamais annoncé.
local function maybe_announce(window, reached)
	local today = day.key(os.time(), cfg.day_offset)
	local seen, announce = status.goal_event(G.logtime_goal_seen, today, reached)
	G.logtime_goal_seen = seen
	if announce then
		local message = string.format(labels().goal_toast, status.goal_short(cfg.goal_hours))
		pcall(function()
			window:toast_notification("logtime", message, nil, 10000)
		end)
		wezterm.log_info("logtime: daily goal reached (" .. status.goal_short(cfg.goal_hours) .. ")") -- toujours en anglais, comme tous les journaux
	end
end

-- tabline.wez s'il est installé ET utilisé par cette config (son setup() a été appelé : get_config() renvoie sa
-- configuration). Installé ne suffit pas : WezTerm garde tous les plugins déjà téléchargés, même ceux qu'une config
-- n'utilise plus, et le compteur s'ajouterait alors à une barre qui n'est jamais affichée.
local function active_tabline(tabline_url)
	if not tabline_url then
		return nil
	end
	local ok, tabline = pcall(wezterm.plugin.require, tabline_url)
	if not (ok and type(tabline) == "table" and type(tabline.get_config) == "function") then
		return nil
	end
	local ok_config, opts = pcall(tabline.get_config)
	if ok_config and type(opts) == "table" then
		return tabline, opts
	end
	return nil
end

local function on_update_status(window, pane, tabline_url)
	local text, reached = status_text() -- d'abord compter (avec la dernière activité connue), puis regarder l'activité
	note_activity(window, pane)
	update_tabline_style(reached)
	maybe_announce(window, reached)
	local now = os.time()
	if not num(G.logtime_status_started) then
		G.logtime_status_started = now -- le premier passage depuis le démarrage de WezTerm (survit aux rechargements)
	end
	local tabline, tabline_opts = active_tabline(tabline_url)
	local mode = auto.choose({
		enabled = cfg.status ~= false,
		now = now,
		external_at = num(G.logtime_external_tick),
		started_at = num(G.logtime_status_started),
		has_tabline = tabline ~= nil,
	})
	if mode == "right" then
		if reached then
			local ok, formatted =
				pcall(wezterm.format, { { Foreground = { Color = reached_color() } }, { Text = text } })
			text = ok and formatted or text
		end
		window:set_right_status(text .. " ") -- un espace au bord : sinon le dernier caractère touche le bord et est rogné
	elseif mode == "tabline" then
		if auto.ensure_component(tabline_opts, tabline_items) then
			wezterm.log_info("logtime: counter added to the tabline.wez bar")
		end
	end
end

-- L'adresse de tabline.wez s'il est installé (nil sinon, ou si la liste des plugins n'est pas lisible).
local function installed_tabline()
	if not (wezterm.plugin and wezterm.plugin.list) then
		return nil
	end
	local ok, plugins = pcall(wezterm.plugin.list)
	return ok and auto.find_tabline(plugins) or nil
end

-- Les heures par jour, à jour (le fichier est lu si ce n'est pas encore fait). La page du calendrier s'en sert.
local function days_for_page()
	get_days()
	ensure_synced(os.time())
	return get_days()
end

-- Une copie des heures par jour : { ["2026-10-12"] = secondes, ... }
function M.days_snapshot()
	local copy = {}
	for key, secs in pairs(days_for_page()) do
		copy[key] = secs
	end
	return copy
end

-- À appeler dans wezterm.lua, APRÈS les autres réglages de touches (keys.lua remplace config.keys) :
--   require("logtime_plugin").apply_to_config(config)
-- Ajoute la touche qui ouvre le calendrier (F2), les touches de la page et le redessin au redimensionnement.
-- Une erreur ici ne casse jamais ta configuration : elle est écrite dans les journaux de WezTerm.
function M.apply_to_config(config, opts, ...)
	local extra = select("#", ...)
	local ok, err = pcall(function()
		for _, message in ipairs(settings.check_options(opts, EXTRA_OPTIONS)) do
			wezterm.log_error("logtime: " .. message)
		end
		if extra > 0 then
			wezterm.log_error(
				"logtime: apply_to_config takes two arguments (config, options); "
					.. extra
					.. " extra argument(s) ignored. Put all your options in ONE table: apply_to_config(config, { ... })"
			)
		end
		M.setup(opts)
		local page = calendar_page.create({
			wezterm = wezterm,
			G = G,
			num = num,
			days = days_for_page,
			idle_days = get_idle,
			projects = get_projects,
			today_key = function()
				return day.key(os.time(), cfg.day_offset)
			end,
			cfg = function()
				return cfg
			end,
			labels = labels,
			blocker_args = function()
				return platform.blocker_args(platform.os_name(wezterm.target_triple))
			end,
		})
		keys.apply(config, wezterm, { page = page, open_key = cfg.open_key, table_name = calendar_page.TABLE_NAME })
		local settings_view = settings_page.create({
			wezterm = wezterm,
			G = G,
			num = num,
			cfg = function()
				return cfg
			end,
			labels = labels,
			blocker_args = function()
				return platform.blocker_args(platform.os_name(wezterm.target_triple))
			end,
			store = settings,
			days = days_for_page, -- pour l'aperçu du mois actuel
			idle_days = get_idle, -- et le détail du jour de l'aperçu
			projects = get_projects,
			timeline = get_timeline, -- et sa frise
			today_key = function()
				return day.key(os.time(), cfg.day_offset)
			end,
			palette = function()
				if cfg.theme_colors == true then
					local colors, reason = theme.extract(config, wezterm)
					if colors then
						return { kind = "theme", colors = colors }
					end
					return { kind = "classic", unavailable = reason }
				end
				return { kind = "classic" }
			end,
			consent = function()
				return cfg.theme_colors
			end,
			settings_key = function()
				return cfg.settings_key
			end,
			settings_path = settings_path,
			apply = function(changes)
				for key, value in pairs(changes) do
					cfg[key] = value
				end
			end,
			refresh_calendar = function(window, pane)
				page.on_resize(window, pane)
			end,
		})
		keys.apply(config, wezterm, {
			page = settings_view,
			open_key = cfg.settings_key,
			table_name = settings_page.TABLE_NAME,
			open_event = "logtime-settings-open",
		})
		wezterm.on("window-config-reloaded", function(window, pane)
			pcall(settings_view.on_config_loaded, window, pane)
		end)
		-- Le compteur, sans rien à brancher : une mise à jour au moins chaque seconde (sans ralentir une barre plus
		-- rapide), et à chaque mise à jour, compter et afficher (voir on_update_status).
		if not config.status_update_interval or config.status_update_interval > 1000 then
			config.status_update_interval = 1000
		end
		local tabline_url = installed_tabline()
		wezterm.on("update-status", function(window, pane)
			local ok_status, status_err = pcall(on_update_status, window, pane, tabline_url)
			if not ok_status and G.logtime_error_message ~= tostring(status_err) then
				G.logtime_error_message = tostring(status_err)
				wezterm.log_error("logtime: " .. tostring(status_err))
			end
		end)
	end)
	if not ok then
		wezterm.log_error("logtime: apply_to_config failed: " .. tostring(err))
	end
	return config
end

if wezterm.log_info then
	wezterm.log_info("logtime: version " .. M.version .. " loaded from " .. DIR)
end

return M
