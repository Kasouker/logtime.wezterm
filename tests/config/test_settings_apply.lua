-- tests/config/test_settings_apply.lua : teste le fichier de réglages BRANCHÉ sur le vrai plugin/init.lua : priorités
-- (défauts < wezterm.lua < fichier), réglages incorrects, fichier illisible, options mal écrites, arguments en trop.
-- Fausse API WezTerm. Lancer :   lua5.4 tests/config/test_settings_apply.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]config[/\\]test_settings_apply%.lua$") or "."

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
local T0 = real_time({ year = 2026, month = 10, day = 13, hour = 12 })
clock.now = T0

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
local function exists(path)
	local f = io.open(path, "rb")
	if f then
		f:close()
		return true
	end
	return false
end
local function strip(text)
	return (text:gsub("\27%[[%?%d;]*%a", ""):gsub("\r", ""))
end

local HISTORY = '{"2026-10-10":15231,"2026-10-11":1900}'
local function new_env(dims)
	dims = dims or { cols = 120, rows = 40 }
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
		GLOBAL = {},
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
	w.next_id = 300
	function w.new_pane()
		w.next_id = w.next_id + 1
		local tab = {}
		function tab:activate() end
		local pane =
			{ id = w.next_id, injected = {}, dims = { viewport_rows = dims.rows, cols = dims.cols }, the_tab = tab }
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
	local env = { home = home, w = w, path = home .. "/.local/share/logtime/.logtime_settings.json" }
	-- Ces tests comptent les mois dessinés grâce aux traces du journal : debug = true sauf si le test le choisit.
	function env.load()
		local M = assert(loadfile(root .. "/plugin/init.lua"))(root)
		local apply = M.apply_to_config
		M.apply_to_config = function(config, opts, ...)
			opts = opts or {}
			if type(opts) == "table" and opts.debug == nil then
				opts.debug = true
			end
			return apply(config, opts, ...)
		end
		return M
	end
	function env.window()
		local win = { performed = {} }
		function win:perform_action(action, pane)
			self.performed[#self.performed + 1] = action
		end
		function win:toast_notification() end
		function win:mux_window()
			return {
				spawn_tab = function(_, spec)
					local pane = w.new_pane()
					w.spawned[#w.spawned + 1] = pane
					return pane.the_tab, pane, nil
				end,
			}
		end
		return win
	end
	function env.settings(text)
		write(env.path, text)
	end
	env.M = env.load()
	return env
end
-- (variable partagée entre les scénarios : déclarée ici pour ne pas créer de variable globale)
local lines

-- ouvre la page avec F2 et renvoie le dessin brut, le nombre de mois dessinés et les lignes sans couleur
local function open_page(env, config)
	for _, b in ipairs(config.keys or {}) do
		if b.key == "F2" then
			fire(b.action, env.window(), env.w.new_pane())
		end
	end
	local pane = env.w.spawned[#env.w.spawned]
	if not pane then
		return nil, 0, {}
	end
	local frame = pane.injected[#pane.injected]
	local months = 0
	for _, line in ipairs(env.w.logs.info) do
		local n = line:match("%((%d+) months%)")
		if n then
			months = tonumber(n)
		end
	end
	local lines = {}
	for line in (strip(frame) .. "\n"):gmatch("(.-)\n") do
		lines[#lines + 1] = line
	end
	return frame, months, lines
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
local function cleanup(env)
	os.execute("rm -rf '" .. env.home .. "'")
end

local BIG = { cols = 300, rows = 74 } -- 4 colonnes x 3 rangées : 12 mois (8 + 3 x 21 + 2 = 73 lignes)
local HEAT3 = convert.bg("#8C7A4A") -- le fond du niveau « 3 à 6 h » des quatre niveaux, pour 4h13
local GOLD = convert.bg(gradient.make({}).color(15231))
local BLUE = convert.bg(gradient.make({ color = "#3366CC" }).color(15231))

-- ============================================================
-- sans fichier : le comportement d'avant
-- ============================================================
local e = new_env(BIG)
check("version : un numéro MAJEUR.MINEUR.CORRECTIF", e.M.version:match("^%d+%.%d+%.%d+$") ~= nil, true)
local config = e.M.apply_to_config({})
local frame, months = open_page(e, config)
check("sans fichier ni option : 12 mois dans une grande fenêtre", months, 12)
check("sans fichier ni option : aucune erreur", #e.w.logs.error, 0)
check("sans fichier : le fichier de réglages n'est jamais créé en lisant", exists(e.path), false)
check("sans fichier : le dégradé par défaut", frame:find(GOLD, 1, true) ~= nil, true)
cleanup(e)

e = new_env(BIG)
config = e.M.apply_to_config({}, { max_months = 3 })
frame, months = open_page(e, config)
check("option de wezterm.lua : max_months = 3", months, 3)
check("option valide : aucune erreur", #e.w.logs.error, 0)
cleanup(e)

-- ============================================================
-- le fichier passe avant wezterm.lua
-- ============================================================
e = new_env(BIG)
e.settings('{"max_months": 2}')
config = e.M.apply_to_config({}, { max_months = 5 })
frame, months = open_page(e, config)
check("le fichier gagne sur wezterm.lua : 2 mois et non 5", months, 2)
check("le fichier est lu sans erreur", #e.w.logs.error, 0)
cleanup(e)

e = new_env(BIG)
e.settings('{"max_months": 4}')
config = e.M.apply_to_config({})
frame, months = open_page(e, config)
check("le fichier seul : 4 mois", months, 4)
cleanup(e)

e = new_env(BIG)
e.settings('{"gradient_color": "#3366CC"}')
config = e.M.apply_to_config({}, { gradient_color = "#112233" })
frame = open_page(e, config)
check("la couleur du fichier gagne : le dessin est bleu", frame:find(BLUE, 1, true) ~= nil, true)
check(
	"la couleur de wezterm.lua n'est pas utilisée",
	frame:find(convert.bg(gradient.make({ color = "#112233" }).color(15231)), 1, true),
	nil
)
cleanup(e)

e = new_env(BIG)
config = e.M.apply_to_config({}, { gradient_color = "#3366CC" })
frame = open_page(e, config)
check("sans fichier, la couleur de wezterm.lua est utilisée", frame:find(BLUE, 1, true) ~= nil, true)
cleanup(e)

e = new_env({ cols = 120, rows = 40 })
e.settings('{"gradient": false}')
config = e.M.apply_to_config({})
frame = open_page(e, config)
check(
	"gradient = false dans le fichier : les quatre niveaux",
	frame:find(HEAT3, 1, true) ~= nil and frame:find(GOLD, 1, true) == nil,
	true
)
cleanup(e)

e = new_env({ cols = 120, rows = 40 })
e.settings('{"lang": "en", "week_starts_on": "sunday"}')
config = e.M.apply_to_config({}, { lang = "fr", week_starts_on = "monday" })
frame, months, lines = open_page(e, config)
local text = table.concat(lines, "\n")
check("lang en dans le fichier : textes anglais", text:find("October 2026", 1, true) ~= nil, true)
check("semaine du dimanche dans le fichier : l'en-tête commence par Sun", text:match("Sun%s+Mon") ~= nil, true)
cleanup(e)

e = new_env({ cols = 120, rows = 40 })
e.settings('{"center": false}')
config = e.M.apply_to_config({})
frame, months, lines = open_page(e, config)
check(
	"center = false dans le fichier : le cadre de l'aide est tout en haut à gauche",
	lines[1]:sub(1, #"╭") == "╭",
	true
)
cleanup(e)
e = new_env({ cols = 120, rows = 40 })
config = e.M.apply_to_config({})
frame, months, lines = open_page(e, config)
check("sans réglage : le dessin est centré (la première ligne est vide)", lines[1], "")
cleanup(e)

-- ============================================================
-- un fichier avec des réglages incorrects
-- ============================================================
e = new_env({ cols = 120, rows = 40 })
e.settings('{"max_months": 100, "lang": "de", "center": false, "gradiant": true}')
config = e.M.apply_to_config({}, { lang = "en" })
frame, months, lines = open_page(e, config)
check("réglages incorrects : le bon réglage est appliqué (center = false)", lines[1]:sub(1, #"╭") == "╭", true)
check(
	"réglages incorrects : la langue de wezterm.lua reste (l'incorrecte du fichier est ignorée)",
	table.concat(lines, "\n"):find("October 2026", 1, true) ~= nil,
	true
)
check("réglages incorrects : trois avertissements", errors_with(e, "logtime: settings:"), 3)
check("réglages incorrects : max_months nommé", errors_with(e, '"max_months"'), 1)
check("réglages incorrects : lang nommé", errors_with(e, '"lang"'), 1)
check("réglages incorrects : le réglage inconnu est nommé", errors_with(e, '"gradiant"'), 1)
check("réglages incorrects : le plugin fonctionne quand même (la page est ouverte)", frame ~= nil, true)
cleanup(e)

-- ============================================================
-- un fichier illisible
-- ============================================================
e = new_env(BIG)
e.settings("{ ceci n'est pas du json")
config = e.M.apply_to_config({}, { max_months = 5 })
frame, months = open_page(e, config)
check("fichier illisible : les options de wezterm.lua restent (5 mois)", months, 5)
check("fichier illisible : un avertissement", errors_with(e, "unreadable"), 1)
check("fichier illisible : le message annonce les valeurs par défaut", errors_with(e, "default values"), 1)
check(
	"fichier illisible : le fichier n'est pas modifié par la lecture",
	io.open(e.path, "rb"):read("*a"),
	"{ ceci n'est pas du json"
)
cleanup(e)

e = new_env(BIG)
e.settings("abîmé")
write(e.path .. ".bak", '{"max_months": 3}')
config = e.M.apply_to_config({}, { max_months = 5 })
frame, months = open_page(e, config)
check("fichier illisible avec copie de sécurité : la copie est utilisée (3 mois)", months, 3)
check("fichier illisible avec copie : l'avertissement parle de la copie", errors_with(e, "backup copy"), 1)
cleanup(e)

e = new_env(BIG)
e.settings("")
config = e.M.apply_to_config({})
frame, months = open_page(e, config)
check("fichier vide : le plugin fonctionne avec les valeurs par défaut", months, 12)
check("fichier vide : signalé", errors_with(e, "unreadable"), 1)
cleanup(e)

-- ============================================================
-- le chemin du fichier
-- ============================================================
e = new_env(BIG)
write(e.home .. "/mes_reglages.json", '{"max_months": 2}')
config = e.M.apply_to_config({}, { settings_file = e.home .. "/mes_reglages.json" })
frame, months = open_page(e, config)
check("settings_file : un autre chemin est utilisé", months, 2)
check("settings_file : aucune erreur (l'option est connue)", #e.w.logs.error, 0)
cleanup(e)

-- ============================================================
-- options mal écrites et arguments en trop
-- ============================================================
e = new_env(BIG)
config = e.M.apply_to_config({}, { gradiant = true })
check("faute de frappe : un avertissement", #e.w.logs.error, 1)
check("faute de frappe : avec la suggestion", errors_with(e, 'did you mean "gradient"?'), 1)
check("faute de frappe : le plugin fonctionne quand même (F2 existe)", open_page(e, config) ~= nil, true)
cleanup(e)

e = new_env(BIG)
config = e.M.apply_to_config({}, { max_months = 2 }, { gradient = false })
check("argument en trop : un avertissement", errors_with(e, "ONE table"), 1)
check("argument en trop : le nombre est donné", errors_with(e, "1 extra argument(s)"), 1)
frame, months = open_page(e, config)
check("argument en trop : le deuxième argument est quand même appliqué (2 mois)", months, 2)
check("argument en trop : le troisième est ignoré (le dégradé reste)", frame:find(GOLD, 1, true) ~= nil, true)
cleanup(e)

e = new_env(BIG)
config = e.M.apply_to_config({}, {}, 1, 2, 3)
check("trois arguments en trop : le nombre est donné", errors_with(e, "3 extra argument(s)"), 1)
cleanup(e)

e = new_env(BIG)
config = e.M.apply_to_config({}, "max_months = 6")
check("réglages donnés en texte : un avertissement sur la table", errors_with(e, "must be a table"), 1)
frame = open_page(e, config)
-- sans table, pas d'option debug : les mois sont comptés dans le dessin (12 mois : de novembre 2025 à octobre 2026,
-- en anglais, la langue par défaut)
check(
	"réglages donnés en texte : le plugin fonctionne avec les valeurs par défaut (12 mois, en anglais)",
	strip(frame):find("November 2025", 1, true) ~= nil and strip(frame):find("October 2026", 1, true) ~= nil,
	true
)
check(
	"réglages donnés en texte : pas un mois de plus (pas d'octobre 2025)",
	strip(frame):find("October 2025", 1, true),
	nil
)
cleanup(e)

e = new_env(BIG)
config = e.M.apply_to_config({}, { max_months = 100, lang = "de" })
check("valeurs hors limites dans wezterm.lua : deux avertissements", #e.w.logs.error, 2)
cleanup(e)

e = new_env(BIG)
config = e.M.apply_to_config({}, {
	lang = "en",
	week_starts_on = "sunday",
	goal_hours = 3,
	open_key = "F3",
	data_file = e.home .. "/autre.json",
	day_offset = 0,
})
check("toutes les options connues : aucun avertissement", #e.w.logs.error, 0)
check(
	"open_key = F3 : la touche est ajoutée",
	(function()
		for _, b in ipairs(config.keys) do
			if b.key == "F3" then
				return true
			end
		end
		return false
	end)(),
	true
)
cleanup(e)

-- ============================================================
-- un nouveau chargement (WezTerm réévalue la config) relit le fichier
-- ============================================================
e = new_env(BIG)
e.settings('{"max_months": 2}')
config = e.M.apply_to_config({})
frame, months = open_page(e, config)
check("premier chargement : 2 mois", months, 2)
e.settings('{"max_months": 3}')
e.M = e.load()
e.w.events = {} -- une nouvelle évaluation de la config repart d'un état Lua vide, sans les anciens gestionnaires
local config2 = e.M.apply_to_config({})
e.w.spawned = {}
e.w.logs.info = {}
e.w.GLOBAL.logtime_page_pane = nil
frame, months = open_page(e, config2)
check("nouveau chargement après modification du fichier : 3 mois", months, 3)
e.settings('{"max_months": 3}')
os.remove(e.path)
e.M = e.load()
e.w.events = {}
config2 = e.M.apply_to_config({})
e.w.spawned = {}
e.w.logs.info = {}
e.w.GLOBAL.logtime_page_pane = nil
frame, months = open_page(e, config2)
check("nouveau chargement après suppression du fichier : retour à 12 mois", months, 12)
check("la lecture n'a jamais écrit dans le fichier de réglages", exists(e.path), false)
cleanup(e)

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
