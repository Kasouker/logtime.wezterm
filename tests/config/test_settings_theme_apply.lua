-- tests/config/test_settings_theme_apply.lua : teste les couleurs du thème BRANCHÉES sur le vrai plugin/init.lua : la
-- question dans la page F4 (touches y et n), la palette lue dans la configuration de WezTerm, la réponse enregistrée dans le
-- fichier de réglages, la notification au chargement de la config. Fausse API WezTerm.
-- Lancer :   lua5.4 tests/config/test_settings_theme_apply.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]config[/\\]test_settings_theme_apply%.lua$") or "."

local globals_before = {}
for k in pairs(_G) do
	globals_before[k] = true
end

-- horloge simulée : mardi 13 octobre 2026, midi
local clock = { now = 0 }
local real_time = os.time
os.time = function(t)
	if t then
		return real_time(t)
	end
	return clock.now
end
clock.now = real_time({ year = 2026, month = 10, day = 13, hour = 12 })

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
local palette = load_module("color/palette")

local homes = {}
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
-- Comme WezTerm : émettre un événement appelle les gestionnaires dans l'ordre, jusqu'à ce que l'un renvoie false
local current_w
local function fire(action, window, pane)
	for _, handler in ipairs(current_w.events[action.name] or {}) do
		if handler(window, pane) == false then
			return
		end
	end
end
local function write(path, text)
	local f = assert(io.open(path, "wb"))
	f:write(text)
	f:close()
end
local function read(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text
end
local function strip(text)
	return (text:gsub("\27%[[%?%d;]*%a", ""):gsub("\r", ""))
end

local ANSI = { "#1E1E1E", "#CC3333", "#33CC33", "#CCCC33", "#3333CC", "#CC33CC", "#33CCCC", "#CCCCCC" }
local BRIGHTS = { "#555555", "#FF5555", "#55FF55", "#FFFF55", "#5555FF", "#FF55FF", "#55FFFF", "#FFFFFF" }
local THEME = {}
for i = 1, 8 do
	THEME[i], THEME[8 + i] = ANSI[i], BRIGHTS[i]
end
-- la configuration telle que appearance.lua la laisse : les couleurs sont déjà dedans
local function theme_config()
	local ansi, brights = {}, {}
	for i = 1, 8 do
		ansi[i], brights[i] = ANSI[i], BRIGHTS[i]
	end
	return { colors = { ansi = ansi, brights = brights } }
end

local HISTORY = '{"2026-10-10":15231,"2026-10-11":1900}'
local function new_env(global)
	local home = os.tmpname()
	os.remove(home)
	os.execute("mkdir -p '" .. home .. "'")
	os.execute("mkdir -p '" .. home .. "/.local/share/logtime'") -- le dossier des fichiers du plugin
	homes[#homes + 1] = home
	write(home .. "/.local/share/logtime/.logtime.json", HISTORY)
	local w = {
		logs = { error = {}, info = {} },
		events = {},
		timers = {},
		panes = {},
		spawned = {},
		GLOBAL = global or {},
		home_dir = home,
		run_child_process = function(args) -- crée le dossier des fichiers, comme WezTerm (storage/location.lua)
			os.execute("mkdir -p '" .. args[#args] .. "'")
			return true, "", ""
		end,
		target_triple = "x86_64-pc-windows-msvc",
	}
	current_w = w
	w.log_error = function(m)
		w.logs.error[#w.logs.error + 1] = m
	end
	w.log_info = function(m)
		w.logs.info[#w.logs.info + 1] = m
	end
	w.action = {
		EmitEvent = function(name)
			return { kind = "EmitEvent", name = name }
		end,
		ActivateKeyTable = function(t)
			return { kind = "ActivateKeyTable", args = t }
		end,
		SendKey = function(t)
			return { kind = "SendKey", args = t }
		end,
		CloseCurrentTab = function(t)
			return { kind = "CloseCurrentTab", args = t }
		end,
		PopKeyTable = { kind = "PopKeyTable" },
	}
	w.on = function(event, handler)
		w.events[event] = w.events[event] or {}
		table.insert(w.events[event], handler)
	end
	w.time = {
		call_after = function(seconds, fn)
			w.timers[#w.timers + 1] = { seconds = seconds, fn = fn }
		end,
	}
	w.mux = {
		get_pane = function(id)
			local pane = w.panes[id]
			if not pane then
				error("pane id " .. tostring(id) .. " not found in mux")
			end
			return pane
		end,
	}
	w.next_id = 1100
	function w.new_pane()
		w.next_id = w.next_id + 1
		local tab = {}
		function tab:activate() end
		local pane = { id = w.next_id, injected = {}, dims = { viewport_rows = 40, cols = 120 }, the_tab = tab }
		function pane:pane_id()
			return self.id
		end
		function pane:get_dimensions()
			return self.dims
		end
		function pane:inject_output(text)
			self.injected[#self.injected + 1] = text
		end
		function pane:tab()
			return self.the_tab
		end
		w.panes[pane.id] = pane
		return pane
	end
	package.loaded["wezterm"] = w
	local env = { home = home, w = w, path = home .. "/.local/share/logtime/.logtime_settings.json", toasts = {} }
	-- Ces tests vérifient les textes français : lang = "fr" sauf si le test choisit une langue (le défaut est l'anglais).
	function env.load()
		local M = assert(loadfile(root .. "/plugin/init.lua"))(root)
		local setup = M.setup
		M.setup = function(opts)
			if opts == nil then
				opts = {}
			end
			if type(opts) == "table" and opts.lang == nil then
				opts.lang = "fr"
			end
			return setup(opts)
		end
		return M
	end
	env.win = { performed = {} }
	function env.win:perform_action(action, pane)
		self.performed[#self.performed + 1] = action
	end
	function env.win:toast_notification(title, message, url, timeout)
		env.toasts[#env.toasts + 1] = message
	end
	function env.win:mux_window()
		return {
			spawn_tab = function(_, spec)
				local pane = w.new_pane()
				w.spawned[#w.spawned + 1] = pane
				return pane.the_tab, pane, nil
			end,
		}
	end
	env.M = env.load()
	return env
end
local function open_key(env, config, key)
	for _, b in ipairs(config.keys or {}) do
		if b.key == key then
			fire(b.action, env.win, env.w.new_pane())
			return true
		end
	end
	return false
end
local function press(env, config, key, pane)
	for _, b in ipairs(config.key_tables.logtime_settings or {}) do
		if b.key == key then
			fire(b.action, env.win, pane)
			return
		end
	end
	error("touche inconnue : " .. key)
end
local function last_frame(pane)
	return pane.injected[#pane.injected]
end
local function plain(pane)
	return strip(last_frame(pane))
end
local function chosen(pane)
	return tonumber(plain(pane):match("Choix : (%d+)"))
end
local function has_colors(pane, list)
	for _, color in ipairs(list) do
		if not last_frame(pane):find(convert.bg(color), 1, true) then
			return false
		end
	end
	return true
end
local function has_any(pane, list)
	for _, color in ipairs(list) do
		if last_frame(pane):find(convert.bg(color), 1, true) then
			return true
		end
	end
	return false
end
local function bg(color)
	return convert.bg(gradient.make({ color = color }).color(15231))
end
local function errors_with(env, text)
	local n = 0
	for _, message in ipairs(env.w.logs.error) do
		if message:find(text, 1, true) then
			n = n + 1
		end
	end
	return n
end
local function config_loaded(env)
	for _, handler in ipairs(env.w.events["window-config-reloaded"] or {}) do
		handler(env.win, env.w.new_pane())
	end
end
local function cleanup()
	for _, d in ipairs(homes) do
		os.execute("rm -rf '" .. d .. "'")
	end
end

-- ============================================================
-- pas encore répondu : la question, et la palette classique
-- ============================================================
local e = new_env()
local config = e.M.apply_to_config(theme_config())
check("la table de touches a quinze touches (Tab, y et n compris)", #config.key_tables.logtime_settings, 15)
open_key(e, config, "F4")
local settings = e.w.spawned[1]
check(
	"la question est affichée",
	plain(settings):find("Couleurs de ton thème ?   y : oui   n : non", 1, true) ~= nil,
	true
)
check(
	"avant la réponse : la palette classique",
	has_colors(settings, palette.COLORS) and not has_any(settings, { THEME[2], THEME[5] }),
	true
)
check("aucune erreur", #e.w.logs.error, 0)

-- ---- y : les couleurs du thème, lues dans la configuration
press(e, config, "y", settings)
check("y : la réponse est enregistrée dans le fichier de réglages", read(e.path), '{\n  "theme_colors": true\n}\n')
check(
	"y : la palette du thème (celle de appearance.lua) est affichée",
	has_colors(settings, THEME) and not has_any(settings, palette.COLORS),
	true
)
check(
	"y : la commande pour changer d'avis est affichée",
	plain(settings):find("(n : palette classique)", 1, true) ~= nil,
	true
)
check(
	"y : le message de réponse enregistrée",
	plain(settings):find("✓ Réponse enregistrée.", 1, true) ~= nil,
	true
)
check("y : la case de départ est celle du thème la plus proche de l'or (jaune, 4)", chosen(settings), 4)
press(e, config, "h", settings)
press(e, config, "h", settings)
check("deux fois gauche : le rouge du thème (2)", chosen(settings), 2)
press(e, config, "Enter", settings)
check(
	"Entrée : la couleur du thème et la réponse sont dans le fichier",
	read(e.path),
	'{\n  "gradient_color": "#CC3333",\n  "theme_colors": true\n}\n'
)
check("Entrée : aucune erreur", #e.w.logs.error, 0)
open_key(e, config, "F2")
check("le calendrier utilise le rouge du thème", last_frame(e.w.spawned[2]):find(bg("#CC3333"), 1, true) ~= nil, true)

-- ---- n : retour à la palette classique, sans toucher à la couleur enregistrée
press(e, config, "n", settings)
check(
	"n : la réponse est enregistrée",
	read(e.path),
	'{\n  "gradient_color": "#CC3333",\n  "theme_colors": false\n}\n'
)
check(
	"n : la palette classique revient",
	has_colors(settings, palette.COLORS) and not has_any(settings, { THEME[2], THEME[5] }),
	true
)
check(
	"n : la commande pour changer d'avis est affichée",
	plain(settings):find("(y : couleurs de ton thème)", 1, true) ~= nil,
	true
)
check(
	"n : la couleur enregistrée n'a pas changé",
	read(e.path):find('"gradient_color": "#CC3333"', 1, true) ~= nil,
	true
)
check("n : le calendrier garde sa couleur", last_frame(e.w.spawned[2]):find(bg("#CC3333"), 1, true) ~= nil, true)
cleanup()

-- ============================================================
-- la réponse est déjà là au démarrage
-- ============================================================
e = new_env()
write(e.path, '{"theme_colors": true}')
config = e.M.apply_to_config(theme_config())
open_key(e, config, "F4")
check(
	"fichier avec theme_colors = true : la palette du thème dès l'ouverture",
	has_colors(e.w.spawned[1], THEME) and not has_any(e.w.spawned[1], palette.COLORS),
	true
)
check("... et la ligne dit oui", plain(e.w.spawned[1]):find("Couleurs de ton thème : oui", 1, true) ~= nil, true)
cleanup()

e = new_env()
write(e.path, '{"theme_colors": false}')
config = e.M.apply_to_config(theme_config())
open_key(e, config, "F4")
check(
	"fichier avec theme_colors = false : la palette classique",
	has_colors(e.w.spawned[1], palette.COLORS) and not has_any(e.w.spawned[1], { THEME[2] }),
	true
)
check("... et la ligne dit non", plain(e.w.spawned[1]):find("Palette classique", 1, true) ~= nil, true)
cleanup()

e = new_env()
config = e.M.apply_to_config(theme_config(), { theme_colors = true })
open_key(e, config, "F4")
check("theme_colors = true dans wezterm.lua : compte comme une réponse oui", has_colors(e.w.spawned[1], THEME), true)
check("... valeur acceptée, aucun avertissement", #e.w.logs.error, 0)
cleanup()

e = new_env()
write(e.path, '{"theme_colors": "oui"}')
config = e.M.apply_to_config(theme_config())
open_key(e, config, "F4")
check(
	"theme_colors incorrect dans le fichier : ignoré, la question est posée",
	plain(e.w.spawned[1]):find("Couleurs de ton thème ?", 1, true) ~= nil,
	true
)
check("... et signalé dans les journaux", errors_with(e, '"theme_colors"'), 1)
cleanup()

-- ============================================================
-- le thème n'est pas lisible
-- ============================================================
e = new_env()
write(e.path, '{"theme_colors": true}')
config = e.M.apply_to_config({})
open_key(e, config, "F4")
check(
	"oui mais aucune couleur dans la configuration : le dit",
	plain(e.w.spawned[1]):find("Thème introuvable : palette classique", 1, true) ~= nil,
	true
)
check("... et la palette classique est utilisée", has_colors(e.w.spawned[1], palette.COLORS), true)
press(e, config, "n", e.w.spawned[1])
check("... n arrête d'essayer", read(e.path), '{\n  "theme_colors": false\n}\n')
cleanup()

e = new_env()
e.w.color = {
	get_builtin_schemes = function()
		return { Fake = { ansi = ANSI, brights = BRIGHTS } }
	end,
}
write(e.path, '{"theme_colors": true}')
config = e.M.apply_to_config({ color_scheme = "Fake" })
open_key(e, config, "F4")
check("un thème intégré (color_scheme) : ses couleurs sont proposées", has_colors(e.w.spawned[1], THEME), true)
cleanup()

e = new_env()
write(e.path, '{"theme_colors": true}')
config = e.M.apply_to_config({ color_scheme = "Fake", colors = { ansi = { [2] = "#AA0000" } } })
e.w.color = {
	get_builtin_schemes = function()
		return { Fake = { ansi = ANSI, brights = BRIGHTS } }
	end,
}
open_key(e, config, "F4")
check(
	"config.colors complète le thème : la couleur 2 est celle de config.colors",
	has_colors(e.w.spawned[1], { "#AA0000", THEME[3] }) and not has_any(e.w.spawned[1], { "#CC3333" }),
	true
)
cleanup()

-- ============================================================
-- la notification au chargement de la config
-- ============================================================
e = new_env()
config = e.M.apply_to_config(theme_config())
check("un gestionnaire de window-config-reloaded est installé", #e.w.events["window-config-reloaded"], 1)
config_loaded(e)
check("pas encore répondu : une notification", #e.toasts, 1)
check("elle nomme la touche F4", e.toasts[1]:find("F4", 1, true) ~= nil, true)
config_loaded(e)
check("une seule fois par session", #e.toasts, 1)
e.w.events = {}
e.M = e.load()
local config2 = e.M.apply_to_config(theme_config())
config_loaded(e)
check("après une nouvelle évaluation de la config (même session) : pas de seconde notification", #e.toasts, 1)
cleanup()

local session = {}
e = new_env(session)
config = e.M.apply_to_config(theme_config())
config_loaded(e)
local second_session = new_env({})
second_session.M.apply_to_config(theme_config())
config_loaded(second_session)
check("une nouvelle session de WezTerm : la notification revient", #e.toasts + #second_session.toasts, 2)
cleanup()

e = new_env()
write(e.path, '{"theme_colors": false}')
config = e.M.apply_to_config(theme_config())
config_loaded(e)
check("déjà répondu non : aucune notification", #e.toasts, 0)
cleanup()
e = new_env()
config = e.M.apply_to_config(theme_config(), { theme_colors = true })
config_loaded(e)
check("déjà répondu oui (wezterm.lua) : aucune notification", #e.toasts, 0)
cleanup()

e = new_env()
config = e.M.apply_to_config(theme_config(), { settings_key = "F5" })
config_loaded(e)
check(
	"avec settings_key = F5 : la notification nomme F5",
	#e.toasts == 1 and e.toasts[1]:find("F5", 1, true) ~= nil,
	true
)
cleanup()

e = new_env()
config = e.M.apply_to_config(theme_config(), { lang = "en" })
config_loaded(e)
check(
	"en anglais : la notification est en anglais",
	#e.toasts == 1 and e.toasts[1]:find("Use your theme's colors?", 1, true) ~= nil,
	true
)
cleanup()

e = new_env()
config = e.M.apply_to_config(theme_config())
e.win.toast_notification = nil
check("une fenêtre sans notifications : aucun plantage", pcall(config_loaded, e), true)
check("... et aucune erreur dans les journaux", #e.w.logs.error, 0)
cleanup()

-- ============================================================
-- le choix survit à un redémarrage
-- ============================================================
e = new_env()
config = e.M.apply_to_config(theme_config())
open_key(e, config, "F4")
press(e, config, "y", e.w.spawned[1])
press(e, config, "h", e.w.spawned[1])
press(e, config, "h", e.w.spawned[1])
press(e, config, "j", e.w.spawned[1])
local saved_index = chosen(e.w.spawned[1])
press(e, config, "Enter", e.w.spawned[1])
local saved_color = THEME[saved_index]
e.w.events = {}
e.w.spawned = {}
e.w.GLOBAL = {}
e.M = e.load()
config2 = e.M.apply_to_config(theme_config())
open_key(e, config2, "F4")
check("après un redémarrage : la palette du thème est toujours là", has_colors(e.w.spawned[1], THEME), true)
check("après un redémarrage : la page démarre sur la couleur enregistrée", chosen(e.w.spawned[1]), saved_index)
open_key(e, config2, "F2")
check(
	"après un redémarrage : le calendrier a la couleur enregistrée",
	last_frame(e.w.spawned[2]):find(bg(saved_color), 1, true) ~= nil,
	true
)
check(
	"après un redémarrage : aucune notification (déjà répondu)",
	(function()
		config_loaded(e)
		return #e.toasts
	end)(),
	0
)
cleanup()

-- ============================================================
-- les autres réglages du fichier sont gardés
-- ============================================================
e = new_env()
write(e.path, '{"max_months": 4, "lang": "en"}')
config = e.M.apply_to_config(theme_config())
open_key(e, config, "F4")
press(e, config, "y", e.w.spawned[1])
check(
	"y garde les autres réglages du fichier",
	read(e.path),
	'{\n  "lang": "en",\n  "max_months": 4,\n  "theme_colors": true\n}\n'
)
check(
	"la page est en anglais : la ligne de réponse aussi",
	plain(e.w.spawned[1]):find("Theme colors: on", 1, true) ~= nil,
	true
)
check(
	"... et les noms des couleurs du thème sont en anglais",
	plain(e.w.spawned[1]):find("Lt Magenta", 1, true) ~= nil,
	true
)
cleanup()

local leaked = {}
for k in pairs(_G) do
	if not globals_before[k] then
		leaked[#leaked + 1] = k
	end
end
check("aucune variable globale ajoutée", table.concat(leaked, ","), "")

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
