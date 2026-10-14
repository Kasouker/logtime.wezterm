-- plugin/init.lua : point d'entrée du plugin logtime.
-- Le compteur dans la barre d'onglets, la sauvegarde des heures dans .logtime.json, et la page du calendrier (touche F2).
--
-- Ce fichier est chargé par logtime_plugin.lua, qui lui transmet le dossier du plugin :
--   local logtime = chunk(dossier_du_plugin)
local wezterm = require("wezterm")
local sep = package.config:sub(1, 1)

local M = {}
M.version = "2.2.0-reglages"

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
	error("logtime : dossier du plugin introuvable (il doit contenir plugin/logtime/core/counter.lua)", 0)
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
			error("logtime : module introuvable : " .. path, 0)
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
local status = load_module("status/status")
local auto = load_module("status/auto")
local storage = load_module("storage/days")
local platform = load_module("system/platform")
local calendar_page = load_module("pages/calendar_page")
local keys = load_module("config/keys")
local settings = load_module("settings/store")
local settings_page = load_module("pages/settings_page")
local theme = load_module("color/theme")

-- Options provisoires : elles iront dans config/defaults.lua à une étape suivante.
local cfg = {
	normal_gap = 5, -- un écart de 5 s ou moins entre deux mises à jour est du temps normal
	sleep_limit = 3900, -- veille comptée par épisode : 65 min
	settle_time = 60, -- secondes d'utilisation continue avant de rendre le budget de veille
	day_offset = 0, -- 0 : la journée change à minuit
	save_every = 10, -- sauvegarde dans le fichier toutes les 10 secondes (s'il y a du nouveau)
	data_file = nil, -- nil : <dossier personnel>/.logtime.json
	week_starts_on = "monday", -- ou "sunday"
	goal_hours = nil, -- nombre d'heures par jour qui comptent pour « objectif atteint » (nil : pas d'objectif)
	lang = "fr", -- "fr" ou "en"
	open_key = "F2", -- la touche qui ouvre le calendrier
	settings_key = "F4", -- la touche qui ouvre la page de personnalisation
}

-- Les noms d'options valables en plus de ceux du schéma des réglages (settings/schema.lua).
local EXTRA_OPTIONS = {
	"normal_gap",
	"sleep_limit",
	"settle_time",
	"day_offset",
	"save_every",
	"data_file",
	"settings_file",
	"settings_key",
	"open_key",
	"cell_color",
	"heat",
	"thresholds",
	"status", -- false : ne pas afficher le compteur dans la barre (il compte quand même)
}

-- Le fichier des réglages choisis par l'utilisateur : <dossier personnel>/.logtime_settings.json
local function settings_path()
	return cfg.settings_file or (wezterm.home_dir .. sep .. ".logtime_settings.json")
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
		wezterm.log_error("logtime : réglages : " .. problem)
	end
	return M
end

local function data_path()
	return cfg.data_file or (wezterm.home_dir .. sep .. ".logtime.json")
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
		sync_failed(now, "logtime : lecture du fichier d'heures impossible : " .. tostring(from_file))
		return
	end

	if state == "corrupt" then
		local moved, qerr = storage.quarantine(path)
		if not moved then
			-- impossible de le mettre de côté : on ne l'écrase surtout pas, on compte en mémoire seulement
			sync_failed(
				now,
				"logtime : le fichier d'heures est illisible ("
					.. tostring(err)
					.. ") et n'a pas pu être mis de côté ("
					.. tostring(qerr)
					.. ") : rien n'est sauvegardé"
			)
			return
		end
		wezterm.log_error(
			"logtime : le fichier d'heures était illisible ("
				.. tostring(err)
				.. ") : il a été mis de côté dans "
				.. moved
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

	local ok, saved, err = pcall(storage.save, path, days)
	G.logtime_saved = now
	if ok and saved then
		G.logtime_dirty = false
		G.logtime_save_failed = false
	else
		if not G.logtime_save_failed then
			wezterm.log_error("logtime : sauvegarde impossible : " .. tostring(ok and err or saved))
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
-- Le comptage
-- ------------------------------------------------------------
local function compute()
	local now = os.time()
	local days = get_days()
	ensure_synced(now)
	days = get_days()

	local last = num(G.logtime_last)
	local state = { budget = num(G.logtime_budget, 0), calm = num(G.logtime_calm, 0) }

	if counter.advance(days, last, now, cfg, state) then
		remember(days)
		G.logtime_dirty = true
	end
	G.logtime_budget = state.budget
	G.logtime_calm = state.calm

	if not last or now > last then
		G.logtime_last = now
	end

	if G.logtime_storage_ready then
		maybe_save(now, days)
	end
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
			wezterm.log_error("logtime : " .. message)
		end
		return "logtime : erreur (voir les journaux)"
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
		wezterm.log_info("logtime : " .. message)
	end
end

local function on_update_status(window, pane, tabline_url)
	local text, reached = status_text()
	update_tabline_style(reached)
	maybe_announce(window, reached)
	local now = os.time()
	if not num(G.logtime_status_started) then
		G.logtime_status_started = now -- le premier passage depuis le démarrage de WezTerm (survit aux rechargements)
	end
	local mode = auto.choose({
		enabled = cfg.status ~= false,
		now = now,
		external_at = num(G.logtime_external_tick),
		started_at = num(G.logtime_status_started),
		has_tabline = tabline_url ~= nil,
	})
	if mode == "right" then
		if reached then
			local ok, formatted =
				pcall(wezterm.format, { { Foreground = { Color = reached_color() } }, { Text = text } })
			text = ok and formatted or text
		end
		window:set_right_status(text)
	elseif mode == "tabline" then
		local ok, tabline = pcall(wezterm.plugin.require, tabline_url)
		if ok and type(tabline) == "table" and type(tabline.get_config) == "function" then
			if auto.ensure_component(tabline.get_config(), tabline_items) then
				wezterm.log_info("logtime : compteur ajouté à la barre de tabline.wez")
			end
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
			wezterm.log_error("logtime : " .. message)
		end
		if extra > 0 then
			wezterm.log_error(
				"logtime : apply_to_config reçoit deux arguments (config, réglages) ; "
					.. extra
					.. " argument(s) en trop ignoré(s). Mets tous tes réglages dans UNE seule table : apply_to_config(config, { ... })"
			)
		end
		M.setup(opts)
		local page = calendar_page.create({
			wezterm = wezterm,
			G = G,
			num = num,
			days = days_for_page,
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
				wezterm.log_error("logtime : " .. tostring(status_err))
			end
		end)
	end)
	if not ok then
		wezterm.log_error("logtime : apply_to_config a échoué : " .. tostring(err))
	end
	return config
end

if wezterm.log_info then
	wezterm.log_info("logtime : version " .. M.version .. " chargée depuis " .. DIR)
end

return M
