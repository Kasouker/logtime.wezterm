-- tests/config/test_apply.lua : teste le branchement du plugin sur la configuration de WezTerm (plugin/init.lua :
-- apply_to_config, days_snapshot) avec une fausse API WezTerm aussi difficile que la vraie.
-- Lancer :   lua5.4 tests/config/test_apply.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]config[/\\]test_apply%.lua$") or "."

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

-- toute écriture doit rester dans le dossier personnel temporaire
local homes = {}
local outside = {}
local writes = {} -- le nombre d'ouvertures en écriture, par nom de fichier (sans le dossier)
local open_fails = {} -- io.open plante pour les fichiers dont le nom contient l'un de ces textes
local real_open = io.open
io.open = function(path, mode)
	for _, part in ipairs(open_fails) do
		if tostring(path):find(part, 1, true) then
			error("test : lecture impossible")
		end
	end
	if mode and mode:find("w") then
		local name = tostring(path):match("[^/\\]+$")
		writes[name] = (writes[name] or 0) + 1
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
-- Comme WezTerm : émettre un événement appelle les gestionnaires dans l'ordre, jusqu'à ce que l'un renvoie false
local current_w
local function fire(action, window, pane)
	for _, handler in ipairs(current_w.events[action.name] or {}) do
		if handler(window, pane) == false then
			return
		end
	end
end
local label = ""
local function check(name, got, want)
	name = label .. name
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

-- ---- un faux wezterm.GLOBAL aussi difficile que le vrai
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

local current_mode = "plain"
local function hostile_global()
	local store = {}
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
local function strip(text)
	return (text:gsub("\27%[[%?%d;]*%a", ""):gsub("\r", ""))
end

local HISTORY = '{"2026-10-10":15231,"2026-10-11":1900}'

-- ---- l'environnement : dossier personnel temporaire, fausse API WezTerm, plugin chargé
local all_logs = {} -- tous les messages des journaux, pour le garde-fou de la fin
-- opts.home : le dossier personnel d'un autre environnement (un 2e WezTerm ouvert en même temps : même dossier,
-- mais son propre GLOBAL et sa propre fausse API).
local function new_env(opts)
	opts = opts or {}
	local home = opts.home
	if not home then
		home = os.tmpname()
		os.remove(home)
		os.execute("mkdir -p '" .. home .. "'")
		os.execute("mkdir -p '" .. home .. "/.local/share/logtime'") -- le dossier des fichiers du plugin
		homes[#homes + 1] = home
	end
	if opts.file ~= false and not opts.home then
		write(home .. "/.local/share/logtime/.logtime.json", opts.file or HISTORY)
	end
	local w = {
		logs = { error = {}, info = {} },
		events = {},
		timers = {},
		panes = {},
		spawned = {},
		GLOBAL = hostile_global(),
		home_dir = home,
		run_child_process = function(args) -- crée le dossier des fichiers, comme WezTerm (storage/location.lua)
			os.execute("mkdir -p '" .. args[#args] .. "'")
			return true, "", ""
		end,
		target_triple = opts.triple or "x86_64-pc-windows-msvc",
	}
	current_w = w
	w.log_error = function(m)
		w.logs.error[#w.logs.error + 1] = m
		all_logs[#all_logs + 1] = m
	end
	w.log_info = function(m)
		w.logs.info[#w.logs.info + 1] = m
		all_logs[#all_logs + 1] = m
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
	w.action_callback = function(fn)
		return { kind = "callback", fn = fn }
	end
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
	w.next_id = 200
	function w.new_pane()
		w.next_id = w.next_id + 1
		local tab = { activated = false, title = "", title_changes = 0 }
		function tab:activate()
			self.activated = true
		end
		function tab:get_title()
			return self.title
		end
		function tab:set_title(title)
			self.title = title
			self.title_changes = self.title_changes + 1
		end
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
	-- wezterm.format : une trace lisible de la couleur demandée, par exemple "[#C9AB6B]texte"
	w.format = function(items)
		local out = {}
		for _, item in ipairs(items) do
			if item.Foreground then
				out[#out + 1] = "[" .. item.Foreground.Color .. "]"
			elseif item.Text then
				out[#out + 1] = item.Text
			end
		end
		return table.concat(out)
	end
	-- les plugins installés (wezterm.plugin.list) et tabline.wez (wezterm.plugin.require), pour le compteur automatique
	w.plugin = {
		list = function()
			return opts.plugins or {}
		end,
		require = function(url)
			if opts.tabline and url == opts.tabline.url then
				return opts.tabline.module
			end
			error("plugin inconnu : " .. tostring(url))
		end,
	}
	package.loaded["wezterm"] = w
	local env = { home = home, w = w }
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
	function env.window()
		local win = { performed = {}, toasts = {} }
		function win:perform_action(action, pane)
			self.performed[#self.performed + 1] = { action = action, pane = pane }
		end
		function win:toast_notification(title, message)
			self.toasts[#self.toasts + 1] = message
		end
		function win:set_right_status(text)
			self.right = text
			self.right_count = (self.right_count or 0) + 1
		end
		function win:mux_window()
			return {
				spawn_tab = function(_, spec)
					local pane = w.new_pane()
					w.spawned[#w.spawned + 1] = { spec = spec, pane = pane }
					return pane.the_tab, pane, nil
				end,
			}
		end
		return win
	end
	env.M = env.load()
	return env
end
local function open_binding(config, key)
	for _, b in ipairs(config.keys or {}) do
		if b.key == key then
			return function(window, pane)
				fire(b.action, window, pane)
			end
		end
	end
end
local function page_binding(config, key)
	for _, b in ipairs(config.key_tables and config.key_tables.logtime_page or {}) do
		if b.key == key then
			return function(window, pane)
				fire(b.action, window, pane)
			end
		end
	end
end
local function last_text(pane)
	return strip(pane.injected[#pane.injected])
end
local function cleanup(env)
	os.execute("rm -rf '" .. env.home .. "'")
end

local function scenarios()
	-- ============================================================
	-- le branchement
	-- ============================================================
	clock.now = T0
	local e = new_env()
	local config = { keys = { { key = "d", mods = "CTRL|SHIFT", action = "split" } } }
	local returned = e.M.apply_to_config(config)
	check("apply : renvoie la même configuration", returned, config)
	check(
		"apply : ses touches sont ajoutées à la suite des tiennes (le calendrier F2, puis la personnalisation F4)",
		#config.keys == 3 and config.keys[1].key == "d" and config.keys[2].key == "F2" and config.keys[3].key == "F4",
		true
	)
	check(
		"apply : la table de touches de la page, avec 18 touches (dont a : l'année, Entrée : le détail, Tab / Shift+Tab : le mois)",
		#config.key_tables.logtime_page,
		18
	)
	local shift_tab = nil
	for _, binding in ipairs(config.key_tables.logtime_page) do
		if binding.key == "Tab" and binding.mods == "SHIFT" then
			shift_tab = binding
		end
	end
	check("apply : Shift+Tab est une touche à part (avec son modificateur)", shift_tab ~= nil, true)
	check(
		"apply : un gestionnaire de redimensionnement par page (calendrier et personnalisation)",
		e.w.events["window-resized"] ~= nil and #e.w.events["window-resized"],
		2
	)
	check("apply : aucune erreur", #e.w.logs.error, 0)

	-- F2 avant même le premier tick : les heures viennent du fichier
	local win = e.window()
	open_binding(config, "F2")(win, e.w.new_pane())
	check("F2 : un onglet est ouvert", #e.w.spawned, 1)
	local page_pane = e.w.spawned[1].pane
	local text = last_text(page_pane)
	check("F2 : le mois en cours est dessiné", text:find("Logtime : Octobre 2026", 1, true) ~= nil, true)
	check("F2 : tes heures du 10 octobre (4h13) viennent du fichier", text:find("4h13", 1, true) ~= nil, true)
	check("F2 : tes heures du 11 octobre (0h31) viennent du fichier", text:find("0h31", 1, true) ~= nil, true)
	check(
		"F2 : sous Windows, l'onglet est gardé ouvert par ping",
		e.w.spawned[1].spec.args[3],
		"ping -n 86400 127.0.0.1>nul"
	)
	check(
		"F2 : la ligne d'aide est la première ligne affichée (le dessin est centré)",
		(text:gsub("^\n+", "")):match("^%s*(.-)\n"),
		"Logtime   ←→↑↓ jour   Tab Maj+Tab mois   Entrée détail   a année   t aujourd'hui"
	)
	check(
		"F2 : lire les heures n'écrit rien (rien de nouveau à sauvegarder)",
		read(e.home .. "/.local/share/logtime/.logtime.json"),
		HISTORY
	)
	check("F2 : aucune erreur", #e.w.logs.error, 0)

	-- le temps compté après l'ouverture apparaît au rafraîchissement (r)
	clock.now = T0
	e.M.tick(nil)
	clock.now = T0 + 600
	e.M.tick(nil) -- 10 min de veille comptées
	page_binding(config, "r")(e.window(), page_pane)
	check(
		"r : le temps compté depuis l'ouverture apparaît (0h10 aujourd'hui)",
		last_text(page_pane):find("0h10", 1, true) ~= nil,
		true
	)
	check(
		"r : et le total du mois est mis à jour (21 + ... : 4h13 + 0h31 + 0h10 = 4h55)",
		last_text(page_pane):find("Total du mois : 4h55", 1, true) ~= nil,
		true
	)
	cleanup(e)

	-- sous Linux
	e = new_env({ triple = "x86_64-unknown-linux-gnu" })
	config = e.M.apply_to_config({})
	open_binding(config, "F2")(e.window(), e.w.new_pane())
	check("Linux : l'onglet est gardé ouvert par sleep", e.w.spawned[1].spec.args[1], "sh")
	cleanup(e)

	-- les réglages
	e = new_env()
	config = e.M.apply_to_config({}, { week_starts_on = "sunday", lang = "en", open_key = "F3", goal_hours = 3 })
	check(
		"réglages : la touche choisie (F3) ouvre la page",
		open_binding(config, "F3") ~= nil and open_binding(config, "F2") == nil,
		true
	)
	open_binding(config, "F3")(e.window(), e.w.new_pane())
	text = last_text(e.w.spawned[1].pane)
	check(
		"réglages : en anglais",
		text:find("Logtime: October 2026", 1, true) ~= nil and text:find("Enter details", 1, true) ~= nil,
		true
	)
	check("réglages : la semaine commence le dimanche", text:find("Sun%s+Mon") ~= nil, true)
	check("réglages : objectif de 3 h atteint 1 jour (le 10)", text:find("Validated days: 1/31", 1, true) ~= nil, true)
	cleanup(e)

	e = new_env()
	config = e.M.apply_to_config({}, { lang = "xx" })
	open_binding(config, "F2")(e.window(), e.w.new_pane())
	check(
		"langue inconnue : retour au français",
		last_text(e.w.spawned[1].pane):find("Octobre 2026", 1, true) ~= nil,
		true
	)
	check("langue inconnue : un avertissement est écrit dans les journaux", #e.w.logs.error, 1)
	check("langue inconnue : l'avertissement nomme le réglage", e.w.logs.error[1]:find('"lang"', 1, true) ~= nil, true)
	cleanup(e)

	-- le décalage de journée (day_offset) décide quel jour est « aujourd'hui » (l'étoile)
	e = new_env()
	config = e.M.apply_to_config({}, { day_offset = 86400 })
	open_binding(config, "F2")(e.window(), e.w.new_pane())
	text = last_text(e.w.spawned[1].pane)
	check(
		"day_offset d'un jour : l'étoile est sur le 14",
		text:find("*14", 1, true) ~= nil and text:find("*13", 1, true) == nil,
		true
	)
	cleanup(e)
	e = new_env()
	config = e.M.apply_to_config({})
	open_binding(config, "F2")(e.window(), e.w.new_pane())
	text = last_text(e.w.spawned[1].pane)
	check(
		"sans décalage : l'étoile est sur le 13",
		text:find("*13", 1, true) ~= nil and text:find("*14", 1, true) == nil,
		true
	)
	cleanup(e)

	-- une erreur ne casse jamais la configuration
	e = new_env()
	local ok, result = pcall(e.M.apply_to_config, nil)
	check("configuration absente : pas de plantage", ok, true)
	check("configuration absente : renvoie nil", result, nil)
	check(
		"configuration absente : l'erreur est journalisée",
		#e.w.logs.error == 1 and e.w.logs.error[1]:find("apply_to_config failed", 1, true) ~= nil,
		true
	)
	cleanup(e)

	e = new_env()
	config = e.M.apply_to_config({})
	check(
		"configuration vide : complétée (F2 et F4, les deux tables de touches)",
		#config.keys == 2 and config.key_tables.logtime_page ~= nil and config.key_tables.logtime_settings ~= nil,
		true
	)
	e.M.apply_to_config(config)
	check(
		"appliqué deux fois : pas de plantage, les touches en double sont signalées (F2 et F4)",
		#config.keys == 4
			and #e.w.logs.error == 2
			and e.w.logs.error[1]:find("F2", 1, true) ~= nil
			and e.w.logs.error[2]:find("F4", 1, true) ~= nil,
		true
	)
	cleanup(e)

	-- fichier abîmé : la page s'ouvre quand même (mois vide), le fichier est mis de côté
	e = new_env({ file = '{"2026-10-10":152' })
	config = e.M.apply_to_config({})
	ok = pcall(open_binding(config, "F2"), e.window(), e.w.new_pane())
	text = last_text(e.w.spawned[1].pane)
	check("fichier abîmé : la page s'ouvre", ok and #e.w.spawned == 1, true)
	check("fichier abîmé : mois vide", text:find("Total du mois : 0h00", 1, true) ~= nil, true)
	check("fichier abîmé : une seule erreur dans les journaux (le fichier mis de côté)", #e.w.logs.error, 1)
	cleanup(e)

	-- ============================================================
	-- days_snapshot
	-- ============================================================
	e = new_env()
	local snapshot = e.M.days_snapshot()
	check(
		"days_snapshot : les heures du fichier",
		snapshot["2026-10-10"] == 15231 and snapshot["2026-10-11"] == 1900,
		true
	)
	snapshot["2026-10-10"] = 1
	check("days_snapshot : c'est une copie (la modifier ne change rien)", e.M.days_snapshot()["2026-10-10"], 15231)
	clock.now = T0
	e.M.tick(nil)
	clock.now = T0 + 60
	e.M.tick(nil)
	check("days_snapshot : le temps compté depuis est inclus", e.M.days_snapshot()["2026-10-13"], 60)
	cleanup(e)

	-- ============================================================
	-- effets de bord
	-- ============================================================
	e = new_env()
	config = e.M.apply_to_config({})
	open_binding(config, "F2")(e.window(), e.w.new_pane())
	local foreign = {}
	for k in pairs(e.w.GLOBAL) do
		if not k:find("^logtime_") then
			foreign[#foreign + 1] = k
		end
	end
	check("wezterm.GLOBAL : seulement des clés logtime_*", table.concat(foreign, ","), "")
	cleanup(e)

	-- ============================================================
	-- le compteur automatique : il compte et s'affiche sans rien à brancher
	-- ============================================================
	-- Comme WezTerm : chaque mise à jour appelle les gestionnaires d'update-status, dans l'ordre, tant qu'aucun ne
	-- renvoie false. Renvoie true si l'un d'eux a renvoyé false (il aurait bloqué tabline.wez).
	local function update(env, win)
		local blocked = false
		for _, handler in ipairs(env.w.events["update-status"] or {}) do
			if handler(win, env.w.new_pane()) == false then
				blocked = true
			end
		end
		return blocked
	end
	local HMS = "%d%d:%d%d:%d%d"

	-- la barre normale de WezTerm : un nouvel utilisateur, qui n'a rien branché
	clock.now = T0
	e = new_env({ file = false })
	config = e.M.apply_to_config({})
	check("automatique : une mise à jour par seconde", config.status_update_interval, 1000)
	check("automatique : un gestionnaire d'update-status", #(e.w.events["update-status"] or {}), 1)
	local win = e.window()
	check(
		"automatique : le gestionnaire ne renvoie jamais false (il bloquerait les autres barres)",
		update(e, win),
		false
	)
	check(
		"automatique : le compteur à droite de la barre, tout seul",
		type(win.right) == "string" and win.right:find(HMS) ~= nil,
		true
	)
	check("automatique : un espace au bord (sinon le dernier caractère est rogné)", win.right:sub(-1), " ")
	clock.now = T0 + 1
	update(e, win)
	check("automatique : sans aucun tick(), le temps compte (1 s)", e.M.today_seconds(), 1)
	update(e, win)
	update(e, win)
	check("automatique : trois mises à jour dans la même seconde comptent une seule fois", e.M.today_seconds(), 1)
	clock.now = T0 + 2
	e.M.tick(win)
	update(e, win)
	check(
		"automatique : tick() et la mise à jour dans la même seconde comptent une seule fois",
		e.M.today_seconds(),
		2
	)
	cleanup(e)
	-- une barre déjà plus rapide n'est pas ralentie ; une plus lente est accélérée
	e = new_env({ file = false })
	check(
		"automatique : 500 ms gardées",
		e.M.apply_to_config({ status_update_interval = 500 }).status_update_interval,
		500
	)
	check(
		"automatique : 5 s ramenées à 1 s",
		e.M.apply_to_config({ status_update_interval = 5000 }).status_update_interval,
		1000
	)
	cleanup(e)

	-- status = false : rien n'est affiché, mais le temps compte quand même
	clock.now = T0
	e = new_env({ file = false })
	e.M.apply_to_config({}, { status = false })
	check("status = false : option connue (pas de message d'erreur)", #e.w.logs.error, 0)
	win = e.window()
	update(e, win)
	clock.now = T0 + 1
	update(e, win)
	check("status = false : rien dans la barre", win.right, nil)
	check("status = false : le temps compte quand même", e.M.today_seconds(), 1)
	cleanup(e)

	-- l'utilisateur affiche déjà le compteur (il appelle tick() dans sa barre) : pas de second compteur
	clock.now = T0
	e = new_env({ file = false })
	e.M.apply_to_config({})
	win = e.window()
	e.M.tick(win)
	update(e, win)
	check("tick() appelé ailleurs : le plugin n'écrit pas dans la barre", win.right, nil)
	clock.now = T0 + 3
	update(e, win)
	check("tick() appelé il y a 3 s : toujours rien", win.right, nil)
	clock.now = T0 + 4
	update(e, win)
	check("plus de tick() depuis 4 s : le plugin reprend l'affichage", win.right ~= nil, true)
	cleanup(e)

	-- tabline.wez installé : le compteur s'ajoute à sa barre (après 3 s, le temps de voir si tick() est déjà appelé)
	local TABLINE = "https://github.com/michaelbrusegard/tabline.wez"
	local function fake_tabline()
		local opts = { sections = { tabline_x = {}, tabline_y = { "datetime" } } }
		return { url = TABLINE, opts = opts, module = {
			get_config = function()
				return opts
			end,
		} }
	end
	clock.now = T0
	local tl = fake_tabline()
	e = new_env({
		file = false,
		plugins = { { url = "https://github.com/x/autre.wez" }, { url = TABLINE } },
		tabline = tl,
	})
	e.M.apply_to_config({})
	win = e.window()
	update(e, win)
	check("tabline : au démarrage, on attend (rien d'ajouté)", #tl.opts.sections.tabline_x, 0)
	check("tabline : jamais dans la barre de droite (c'est celle de tabline)", win.right, nil)
	clock.now = T0 + 3
	update(e, win)
	check(
		"tabline : après 3 s, le compteur est ajouté à tabline_x (son style, lui, puis la remise des couleurs)",
		#tl.opts.sections.tabline_x,
		3
	)
	check(
		"tabline : la remise des couleurs de tabline après le compteur",
		tl.opts.sections.tabline_x[3],
		"ResetAttributes"
	)
	check(
		"tabline : ajouté une fois, c'est noté dans les journaux",
		#e.w.logs.info >= 1 and e.w.logs.info[#e.w.logs.info]:find("tabline", 1, true) ~= nil,
		true
	)
	local shown = tl.opts.sections.tabline_x[2](win)
	check("tabline : le compteur ajouté affiche le temps", type(shown) == "string" and shown:find(HMS) ~= nil, true)
	clock.now = T0 + 4
	update(e, win)
	update(e, win)
	check("tabline : toujours un seul compteur ajouté", #tl.opts.sections.tabline_x, 3)
	check("tabline : les autres sections ne bougent pas", #tl.opts.sections.tabline_y, 1)
	clock.now = T0 + 20
	update(e, win)
	check(
		"tabline : le compteur ajouté ne compte pas comme un tick() venu d'ailleurs (il reste)",
		#tl.opts.sections.tabline_x,
		3
	)
	check("tabline : toujours rien dans la barre de droite", win.right, nil)
	-- WezTerm réévalue la config (en ouvrant un onglet…) : tabline repart d'une liste neuve, sans le compteur.
	-- Le compteur affiché par tabline juste avant ne doit pas passer pour un tick() venu d'ailleurs : sinon il
	-- disparaîtrait 3 s à chaque nouvel onglet.
	tl.opts.sections.tabline_x[2](win) -- tabline vient d'afficher le compteur ajouté
	tl.opts.sections.tabline_x = {} -- la config est réévaluée
	update(e, win)
	check(
		"tabline, config réévaluée : le compteur est remis tout de suite (pas 3 s sans compteur)",
		#tl.opts.sections.tabline_x,
		3
	)
	check("tabline : aucune erreur", #e.w.logs.error, 0)
	cleanup(e)

	-- tabline.wez installé mais PAS utilisé par cette config (son setup() n'a pas été appelé : get_config() renvoie
	-- nil) : WezTerm garde les plugins déjà téléchargés. Le compteur doit s'afficher à droite, sinon il est invisible.
	clock.now = T0
	tl = fake_tabline()
	tl.module.get_config = function()
		return nil
	end
	e = new_env({ file = false, plugins = { { url = TABLINE } }, tabline = tl })
	e.M.apply_to_config({})
	win = e.window()
	update(e, win)
	check("tabline installé mais pas utilisé : le compteur est à droite dès le départ", win.right ~= nil, true)
	clock.now = T0 + 5
	update(e, win)
	check(
		"tabline installé mais pas utilisé : toujours à droite",
		win.right ~= nil and win.right:find(HMS) ~= nil,
		true
	)
	check("tabline installé mais pas utilisé : rien d'ajouté à tabline", #tl.opts.sections.tabline_x, 0)
	check("tabline installé mais pas utilisé : aucune erreur", #e.w.logs.error, 0)
	cleanup(e)

	-- tabline.wez installé, et sa fonction get_config plante : le compteur reste visible, à droite
	clock.now = T0
	tl = fake_tabline()
	tl.module.get_config = function()
		error("tabline cassé")
	end
	e = new_env({ file = false, plugins = { { url = TABLINE } }, tabline = tl })
	e.M.apply_to_config({})
	win = e.window()
	clock.now = T0 + 5
	update(e, win)
	check("tabline qui plante : le compteur est à droite", win.right ~= nil, true)
	check("tabline qui plante : aucune erreur du plugin", #e.w.logs.error, 0)
	cleanup(e)

	-- tabline.wez + tick() déjà branché dans tabline (ta configuration) : rien n'est ajouté
	clock.now = T0
	tl = fake_tabline()
	e = new_env({ file = false, plugins = { { url = TABLINE } }, tabline = tl })
	e.M.apply_to_config({})
	win = e.window()
	for s = 0, 10 do
		clock.now = T0 + s
		e.M.tick(win) -- comme ta section tabline_y qui appelle logtime.tick
		update(e, win)
	end
	check("tabline + tick() branché : rien n'est ajouté (pas de second compteur)", #tl.opts.sections.tabline_x, 0)
	check("tabline + tick() branché : le temps compte normalement (10 s)", e.M.today_seconds(), 10)
	cleanup(e)

	-- tabline.wez installé mais illisible : pas de plantage
	clock.now = T0
	e =
		new_env({ file = false, plugins = { { url = TABLINE } }, tabline = { url = TABLINE, module = "pas un module" } })
	e.M.apply_to_config({})
	win = e.window()
	clock.now = T0 + 5
	check("tabline illisible : le gestionnaire ne renvoie pas false", update(e, win), false)
	check("tabline illisible : aucune erreur", #e.w.logs.error, 0)
	cleanup(e)
	-- la liste des plugins plante : on fait comme sans tabline
	clock.now = T0
	e = new_env({ file = false })
	e.w.plugin.list = function()
		error("boum")
	end
	e.M.apply_to_config({})
	win = e.window()
	update(e, win)
	check("liste des plugins illisible : le compteur à droite quand même", win.right ~= nil, true)
	cleanup(e)

	-- ============================================================
	-- l'objectif dans le compteur : « / 7h » avant, « ✓ » et la couleur du dégradé une fois atteint
	-- ============================================================
	-- 2026-10-13 (T0) : 6h59m58s déjà comptées ; objectif 7 h
	local almost = '{"2026-10-13":25198}'
	clock.now = T0
	e = new_env({ file = almost })
	e.M.apply_to_config({}, { goal_hours = 7, gradient_color = "#3366CC" })
	win = e.window()
	update(e, win)
	check("objectif pas atteint : « / 7h » après la durée", win.right:find("06:59:58 / 7h", 1, true) ~= nil, true)
	check("objectif pas atteint : pas de couleur", win.right:find("[#", 1, true), nil)
	clock.now = T0 + 1
	update(e, win)
	clock.now = T0 + 2
	update(e, win)
	check(
		"objectif atteint : « ✓ » devant la durée, plus de « / 7h »",
		win.right:find("✓ 07:00:00", 1, true) ~= nil and win.right:find("/ 7h", 1, true) == nil,
		true
	)
	check("objectif atteint : dans la couleur du dégradé", win.right:find("[#3366CC]", 1, true) ~= nil, true)
	check(
		"tick() branché à la main : « ✓ » aussi (en texte)",
		e.M.tick(win):find("✓ 07:00:0", 1, true) ~= nil,
		true
	)
	cleanup(e)
	-- sans couleur du dégradé valable : l'or
	clock.now = T0
	e = new_env({ file = '{"2026-10-13":30000}' })
	e.M.apply_to_config({}, { goal_hours = 7 })
	win = e.window()
	update(e, win)
	check("objectif atteint, couleur par défaut : l'or", win.right:find("[#C9AB6B]", 1, true) ~= nil, true)
	cleanup(e)
	-- sans objectif : comme avant
	clock.now = T0
	e = new_env({ file = '{"2026-10-13":30000}' })
	e.M.apply_to_config({})
	win = e.window()
	update(e, win)
	check(
		"sans objectif : ni « / », ni « ✓ », ni couleur",
		win.right:find("/", 1, true) == nil
			and win.right:find("✓", 1, true) == nil
			and win.right:find("[#", 1, true) == nil,
		true
	)
	cleanup(e)
	-- tabline : le style placé avant le compteur prend la couleur une fois l'objectif atteint
	-- 6h59m50s déjà comptées : le compteur est ajouté à tabline 3 s après le démarrage, l'objectif est atteint 10 s après
	clock.now = T0
	tl = fake_tabline()
	e = new_env({ file = '{"2026-10-13":25190}', plugins = { { url = TABLINE } }, tabline = tl })
	e.M.apply_to_config({}, { goal_hours = 7, gradient_color = "#3366CC" })
	win = e.window()
	for s = 0, 3 do
		clock.now = T0 + s
		update(e, win)
	end
	local style = tl.opts.sections.tabline_x[1]
	check(
		"tabline, objectif pas encore atteint (6h59m53) : le style ne colore pas",
		style.Foreground == nil and style.Attribute ~= nil,
		true
	)
	check(
		"tabline, objectif pas atteint : « / 7h » dans le compteur",
		tl.opts.sections.tabline_x[2](win):find("/ 7h", 1, true) ~= nil,
		true
	)
	for s = 4, 10 do
		clock.now = T0 + s
		update(e, win)
	end
	check(
		"tabline, objectif atteint : le style prend la couleur du dégradé",
		style.Foreground and style.Foreground.Color,
		"#3366CC"
	)
	check("tabline, objectif atteint : plus d'Attribute en même temps", style.Attribute, nil)
	check(
		"tabline, objectif atteint : « ✓ » dans le compteur",
		tl.opts.sections.tabline_x[2](win):find("✓ 07:00:0", 1, true) ~= nil,
		true
	)
	cleanup(e)

	-- ============================================================
	-- 🎉 la notification : une seule fois par jour, au moment où l'objectif est atteint
	-- ============================================================
	local function run(env, windows, from, to)
		for s = from, to do
			clock.now = T0 + s
			for _, w_ in ipairs(windows) do
				update(env, w_)
			end
		end
	end
	local function toasts(windows)
		local all = {}
		for _, w_ in ipairs(windows) do
			for _, m in ipairs(w_.toasts) do
				all[#all + 1] = m
			end
		end
		return all
	end
	-- 6h59m58s, objectif 7 h : atteint 2 s plus tard
	e = new_env({ file = almost })
	e.M.apply_to_config({}, { goal_hours = 7 })
	win = e.window()
	run(e, { win }, 0, 1)
	check("🎉 pas encore atteint : pas de notification", #win.toasts, 0)
	run(e, { win }, 2, 2)
	check("🎉 atteint : une notification", #win.toasts, 1)
	check(
		"🎉 le message, avec ses 🎉 au début et à la fin",
		win.toasts[1],
		"🎉 Objectif du jour atteint : 7h ! 🎉"
	)
	check("🎉 aussi dans les journaux", e.w.logs.info[#e.w.logs.info], "logtime: daily goal reached (7h)")
	run(e, { win }, 3, 30)
	check("🎉 une seule fois (rien de plus ensuite)", #win.toasts, 1)
	cleanup(e)
	-- WezTerm démarre alors que l'objectif est déjà atteint : pas de seconde notification
	e = new_env({ file = '{"2026-10-13":30000}' })
	e.M.apply_to_config({}, { goal_hours = 7 })
	win = e.window()
	run(e, { win }, 0, 10)
	check("🎉 WezTerm rouvert après l'objectif : pas de notification", #win.toasts, 0)
	cleanup(e)
	-- sans objectif : jamais
	e = new_env({ file = almost })
	e.M.apply_to_config({})
	win = e.window()
	run(e, { win }, 0, 10)
	check("🎉 sans objectif : jamais de notification", #win.toasts, 0)
	cleanup(e)
	-- deux fenêtres : une seule notification en tout
	e = new_env({ file = almost })
	e.M.apply_to_config({}, { goal_hours = 7 })
	local win1, win2 = e.window(), e.window()
	run(e, { win1, win2 }, 0, 5)
	check("🎉 deux fenêtres ouvertes : une seule notification en tout", #toasts({ win1, win2 }), 1)
	cleanup(e)
	-- le compteur caché (status = false) : la notification part quand même
	e = new_env({ file = almost })
	e.M.apply_to_config({}, { goal_hours = 7, status = false })
	win = e.window()
	run(e, { win }, 0, 5)
	check("🎉 compteur caché : la notification part quand même", #win.toasts, 1)
	cleanup(e)
	-- en anglais, objectif 7 h 30
	e = new_env({ file = '{"2026-10-13":26998}' })
	e.M.apply_to_config({}, { goal_hours = 7.5, lang = "en" })
	win = e.window()
	run(e, { win }, 0, 5)
	check("🎉 en anglais, 7h30", win.toasts[1], "🎉 Daily goal reached: 7h30! 🎉")
	cleanup(e)
	-- Windows refuse la notification : rien ne casse
	e = new_env({ file = almost })
	e.M.apply_to_config({}, { goal_hours = 7 })
	win = e.window()
	function win:toast_notification()
		error("notifications désactivées")
	end
	run(e, { win }, 0, 5)
	check("🎉 notification refusée : aucune erreur", #e.w.logs.error, 0)
	check(
		"🎉 notification refusée : le compteur s'affiche quand même, avec son ✓",
		win.right:find("✓", 1, true) ~= nil,
		true
	)
	cleanup(e)

	-- ============================================================
	-- le temps inactif : rien ne bouge dans le terminal pendant 5 min
	-- ============================================================
	-- un panneau qui reste le même : on décide nous-mêmes quand son texte change (et son dossier, son titre)
	local function screen_pane(env, cwd, title)
		local pane = env.w.new_pane()
		pane.text = "$ "
		function pane:get_title()
			return title or "zsh"
		end
		function pane:get_current_working_dir()
			return cwd
		end
		function pane:get_cursor_position()
			return { x = #self.text, y = 0 }
		end
		function pane:get_lines_as_text()
			return self.text
		end
		return pane
	end
	-- de from à to (secondes après T0), une mise à jour par seconde ; active : le texte change à chaque seconde
	local function live(env, win_, pane, from, to, active)
		for s = from, to do
			clock.now = T0 + s
			if active then
				pane.text = "$ ligne " .. s
			end
			for _, handler in ipairs(env.w.events["update-status"] or {}) do
				handler(win_, pane)
			end
		end
	end
	clock.now = T0
	e = new_env({ file = false })
	config = e.M.apply_to_config({})
	win = e.window()
	local screen = screen_pane(e)
	open_binding(config, "F2")(win, screen)
	local idle_page = e.w.spawned[#e.w.spawned].pane
	check("inactif : rien de compté aujourd'hui, pas de ligne", last_text(idle_page):find("inactif", 1, true), nil)
	live(e, win, screen, 0, 600, true) -- 10 min de travail
	local function idle_tmp_writes() -- les écritures du fichier temporaire (.logtime_idle.json.<identifiant>.tmp)
		local n = 0
		for name, count in pairs(writes) do
			if name:match("^%.logtime_idle%.json%.%x+%.tmp$") then
				n = n + count
			end
		end
		return n
	end
	local idle_writes_before = idle_tmp_writes()
	live(e, win, screen, 601, 4200, false) -- 1 h sans rien toucher
	check(
		"inactif : le fichier est écrit au plus toutes les 10 s (pas à chaque seconde)",
		idle_tmp_writes() - idle_writes_before <= 3600 / 10 and idle_tmp_writes() - idle_writes_before > 0,
		true
	)
	live(e, win, screen, 4201, 4260, true) -- reprise
	check("inactif : le compteur garde tout (1h11)", e.M.today_seconds(), 4260)
	-- la pause d'une heure, plus la seconde de la reprise (comptée avant de voir que l'écran a changé)
	check(
		"inactif : la pause est notée dans .logtime_idle.json",
		read(e.home .. "/.local/share/logtime/.logtime_idle.json"),
		'{"2026-10-13":3601}'
	)
	-- (sauvegardé toutes les 10 s : les dernières secondes sont encore en mémoire)
	check(
		"inactif : .logtime.json garde son format (sans l'inactif)",
		read(e.home .. "/.local/share/logtime/.logtime.json"):match('^{"2026%-10%-13":%d+}$') ~= nil,
		true
	)
	check("inactif : aucune erreur", #e.w.logs.error, 0)
	open_binding(config, "F2")(win, screen)
	check(
		"inactif : dans le calendrier, au bout de la légende",
		last_text(idle_page):find("* = aujourd'hui     Aujourd'hui : 1h00 inactif sur 1h11 (85 %)", 1, true) ~= nil,
		true
	)
	idle_page.dims = { viewport_rows = 40, cols = 80 }
	page_binding(config, "r")(win, idle_page)
	check(
		"inactif : fenêtre trop étroite pour la ligne : pas affiché",
		last_text(idle_page):find("inactif", 1, true),
		nil
	)
	check("inactif : mais le calendrier, si", last_text(idle_page):find("Octobre 2026", 1, true) ~= nil, true)
	idle_page.dims = { viewport_rows = 50, cols = 200 }
	page_binding(config, "r")(win, idle_page)
	check(
		"inactif : plusieurs mois, au bout de la légende commune",
		last_text(idle_page):find("Aujourd'hui : 1h00 inactif sur 1h11 (85 %)", 1, true) ~= nil,
		true
	)
	page_binding(config, "a")(win, idle_page)
	check(
		"inactif : la vue de l'année, dans les statistiques",
		last_text(idle_page):find("Inactif : 1h00 (85 %)", 1, true) ~= nil,
		true
	)
	check(
		"inactif : la vue de l'année, au bout de la légende",
		last_text(idle_page):find("Aujourd'hui : 1h00 inactif", 1, true) ~= nil,
		true
	)
	page_binding(config, "a")(win, idle_page)
	page_binding(config, "Enter")(win, idle_page)
	check(
		"Entrée : le détail d'aujourd'hui, avec son temps inactif",
		last_text(idle_page):find("Mardi 13 octobre 2026 · aujourd'hui", 1, true) ~= nil
			and last_text(idle_page):find("Inactif    1h00", 1, true) ~= nil,
		true
	)
	page_binding(config, "Escape")(win, idle_page)
	check("Échap : retour au calendrier", last_text(idle_page):find("Octobre 2026", 1, true) ~= nil, true)
	-- WezTerm rouvert : le fichier est relu, et la suite s'y ajoute
	local home = e.home
	homes[#homes + 1] = home
	e = new_env({ file = false })
	os.execute("rm -rf '" .. e.home .. "'")
	e.home, e.w.home_dir = home, home
	e.M.apply_to_config({})
	screen = screen_pane(e)
	live(e, win, screen, 4300, 4300, true)
	live(e, win, screen, 4301, 4700, false) -- 6 min 40 sans rien toucher
	check(
		"inactif, WezTerm rouvert : l'ancien inactif est gardé, le nouveau s'y ajoute",
		read(home .. "/.local/share/logtime/.logtime_idle.json"),
		'{"2026-10-13":4001}'
	)
	cleanup(e)
	-- un fichier d'inactif abîmé : mis de côté, jamais pris pour du vide en silence
	clock.now = T0
	e = new_env({ file = false })
	write(e.home .. "/.local/share/logtime/.logtime_idle.json", "pas du json")
	e.M.apply_to_config({})
	screen = screen_pane(e)
	live(e, win, screen, 0, 400, false)
	check("inactif, fichier abîmé : signalé une seule fois dans les journaux", #e.w.logs.error, 1)
	check(
		"inactif, fichier abîmé : mis de côté",
		io.popen("ls -a '" .. e.home .. "/.local/share/logtime'")
			:read("*a")
			:find(".logtime_idle.json.corrupt-", 1, true) ~= nil,
		true
	)
	check(
		"inactif, fichier abîmé : un nouveau fichier",
		read(e.home .. "/.local/share/logtime/.logtime_idle.json"),
		'{"2026-10-13":400}'
	)
	cleanup(e)
	-- ============================================================
	-- le temps par projet
	-- ============================================================
	clock.now = T0
	e = new_env({ file = false })
	config = e.M.apply_to_config({})
	win = e.window()
	local c05 = screen_pane(e, "file:///C:/Users/max/42/C05/ex02/", "zsh")
	local claude = screen_pane(e, "file:///C:/Users/max/", "◑ Claude Code")
	live(e, win, c05, 0, 600, true) -- 10 min dans 42/C05
	live(e, win, claude, 601, 900, true) -- 5 min dans Claude (le dossier personnel : c'est le titre qui compte)
	live(e, win, claude, 901, 4500, false) -- 1 h de pause dans Claude
	live(e, win, claude, 4501, 4560, true) -- 1 min de reprise
	-- une seconde fenêtre, qui n'a pas le focus : ce qu'on y voit ne change pas le projet en cours
	local other_win = e.window()
	function other_win:is_focused()
		return false
	end
	function win:is_focused()
		return true
	end
	local other = screen_pane(e, "file:///C:/Users/max/autre/projet/", "zsh")
	for s_ = 4561, 4620 do
		clock.now = T0 + s_
		claude.text = "$ " .. s_
		other.text = "$ " .. s_
		for _, handler in ipairs(e.w.events["update-status"] or {}) do
			handler(win, claude)
			handler(other_win, other)
		end
	end
	-- la page du calendrier : son temps va à « logtime » (et pas à PING)
	open_binding(config, "F2")(win, claude)
	local project_page = e.w.spawned[#e.w.spawned].pane
	function project_page:get_title() -- comme dans la réalité : l'onglet est gardé ouvert par ping
		return "PING.EXE"
	end
	live(e, win, project_page, 4621, 4700, false)
	local saved = assert(read(e.home .. "/.local/share/logtime/.logtime_projects.json"))
	-- relu avec le lecteur du plugin (storage/projects.lua)
	local modules = {}
	local function module(name)
		modules[name] = modules[name] or assert(loadfile(root .. "/plugin/logtime/" .. name .. ".lua"))(module)
		return modules[name]
	end
	local p_day = assert(module("storage/projects").decode(saved))["2026-10-13"]
	check("projets : 42/C05 (les 10 premières minutes, plus la seconde du changement d'onglet)", p_day["42/C05"], 601)
	check(
		"projets : Claude Code (5 min, la reprise et la 2de fenêtre, sans l'heure de pause ; plus la seconde vers la page)",
		p_day["Claude Code"],
		299 + 59 + 60 + 1
	)
	check("projets : rien pour la fenêtre sans le focus", p_day["autre/projet"], nil)
	check("projets : la page du calendrier compte pour logtime", p_day.logtime ~= nil and p_day.logtime >= 60, true)
	check("projets : jamais pour PING", saved:find("PING", 1, true), nil)
	-- la page de personnalisation aussi
	open_binding(config, "F4")(win, claude)
	local settings_pane = e.w.spawned[#e.w.spawned].pane
	function settings_pane:get_title()
		return "PING.EXE"
	end
	live(e, win, settings_pane, 4701, 4760, false)
	local p_after =
		module("storage/projects").decode(read(e.home .. "/.local/share/logtime/.logtime_projects.json"))["2026-10-13"]
	check("projets : la page F4 compte aussi pour logtime (jamais pour PING)", p_after.PING, nil)
	check("projets : la page F4, le temps va bien quelque part (logtime)", p_after.logtime >= 100, true)
	check("projets : aucune erreur", #e.w.logs.error, 0)
	page_binding(config, "Enter")(win, project_page)
	check(
		"projets : dans le détail du jour",
		last_text(project_page):find("Par projet (temps actif)", 1, true) ~= nil
			and last_text(project_page):find("42/C05", 1, true) ~= nil
			and last_text(project_page):find("Claude Code", 1, true) ~= nil,
		true
	)
	cleanup(e)
	-- un fichier de projets abîmé : mis de côté, comme les autres
	clock.now = T0
	e = new_env({ file = false })
	write(e.home .. "/.local/share/logtime/.logtime_projects.json", '{"2026-10-13":5}')
	e.M.apply_to_config({})
	screen = screen_pane(e, "file:///C:/Users/max/a/b/")
	live(e, win, screen, 0, 30, true)
	check("projets, fichier abîmé : signalé", #e.w.logs.error, 1)
	check(
		"projets, fichier abîmé : mis de côté",
		io.popen("ls -a '" .. e.home .. "/.local/share/logtime'")
			:read("*a")
			:find(".logtime_projects.json.corrupt-", 1, true) ~= nil,
		true
	)
	check(
		"projets, fichier abîmé : un nouveau fichier",
		read(e.home .. "/.local/share/logtime/.logtime_projects.json"):find('"a/b"', 1, true) ~= nil,
		true
	)
	cleanup(e)

	-- le fichier des projets ne se lit pas tout de suite : le temps attend en mémoire, puis s'ajoute au fichier
	clock.now = T0
	e = new_env({ file = false })
	write(
		e.home .. "/.local/share/logtime/.logtime_projects.json",
		'{"2026-10-12":{"vieux":7200},"2026-10-13":{"a/b":50,"c/d":9}}'
	)
	e.M.apply_to_config({})
	screen = screen_pane(e, "file:///C:/Users/max/a/b/")
	open_fails[1] = "logtime_projects"
	live(e, win, screen, 0, 400, true)
	open_fails[1] = nil
	live(e, win, screen, 401, 421, true)
	check(
		"projets, lus en retard : la mémoire (421 s) l'emporte, les autres projets et jours sont gardés",
		read(e.home .. "/.local/share/logtime/.logtime_projects.json"),
		'{"2026-10-12":{"vieux":7200},"2026-10-13":{"a/b":421,"c/d":9}}'
	)
	cleanup(e)

	-- la sauvegarde des projets échoue un moment (fichier bloqué) : une erreur, puis le retour à la normale est noté
	clock.now = T0
	e = new_env({ file = false })
	e.M.apply_to_config({})
	screen = screen_pane(e, "file:///C:/Users/max/a/b/")
	open_fails[1] = ".logtime_projects.json." -- son fichier temporaire (.logtime_projects.json.<identifiant>.tmp)
	live(e, win, screen, 0, 30, true)
	open_fails[1] = nil
	local function logged(list, text)
		local n = 0
		for _, m in ipairs(list) do
			if m:find(text, 1, true) then
				n = n + 1
			end
		end
		return n
	end
	check("projets, sauvegarde bloquée : une seule erreur", logged(e.w.logs.error, "cannot save the"), 1)
	live(e, win, screen, 31, 60, true)
	check(
		"projets, sauvegarde bloquée : le retour à la normale est noté, une fois",
		logged(e.w.logs.info, "saved again"),
		1
	)
	check(
		"projets, sauvegarde bloquée : rien n'est perdu (dernière sauvegarde à la seconde 51, toutes les 10 s)",
		read(e.home .. "/.local/share/logtime/.logtime_projects.json"),
		'{"2026-10-13":{"a/b":51}}'
	)
	cleanup(e)

	-- ============================================================
	-- deux WezTerm ouverts en même temps (deux processus : chacun son GLOBAL), le même dossier
	-- ============================================================
	clock.now = T0
	local a = new_env({ file = false })
	local config_a = a.M.apply_to_config({})
	local win_a = a.window()
	function win_a:is_focused()
		return true
	end
	local pane_a = screen_pane(a, "file:///C:/Users/max/42/C05/", "zsh")
	local b = new_env({ home = a.home })
	b.M.apply_to_config({})
	local win_b = b.window()
	local b_focused = false
	function win_b:is_focused()
		return b_focused
	end
	local pane_b = screen_pane(b, "file:///C:/Users/max/autre/projet/", "zsh")
	local function both(from, to, a_active, b_active)
		for s_ = from, to do
			clock.now = T0 + s_
			if a_active then
				pane_a.text = "$ a " .. s_
			end
			if b_active then
				pane_b.text = "$ b " .. s_
			end
			for _, handler in ipairs(a.w.events["update-status"] or {}) do
				handler(win_a, pane_a)
			end
			for _, handler in ipairs(b.w.events["update-status"] or {}) do
				handler(win_b, pane_b)
			end
		end
	end
	local D = a.home .. "/.local/share/logtime/"
	local function projects_now()
		local text = read(D .. ".logtime_projects.json")
		return text and module("storage/projects").decode(text)["2026-10-13"] or {}
	end
	-- 10 min : on travaille dans A (au premier plan) ; B est ouvert à côté, sans le focus, et rien n'y bouge
	both(0, 600, true, false)
	check("deux WezTerm : aucune erreur dans A", #a.w.logs.error, 0)
	check("deux WezTerm : aucune erreur dans B (plus de « check after writing failed »)", #b.w.logs.error, 0)
	check(
		"deux WezTerm : les heures, une seule fois, pas le double (dernière sauvegarde à la seconde 591)",
		read(D .. ".logtime.json"),
		'{"2026-10-13":591}'
	)
	check(
		"deux WezTerm : le projet de A reçoit le temps (sauvegardé à la seconde 591)",
		projects_now()["42/C05"],
		591
	)
	check("deux WezTerm : rien pour le projet de B (il n'a pas le focus)", projects_now()["autre/projet"], nil)
	check(
		"deux WezTerm : B ne compte pas d'inactif (il n'attribue rien : rien ne bougeait chez lui)",
		read(D .. ".logtime_idle.json"),
		nil
	)
	check(
		"deux WezTerm : le fichier .logtime_focus désigne A",
		read(D .. ".logtime_focus"),
		tostring(a.w.GLOBAL.logtime_process_token)
	)
	check(
		"deux WezTerm : chacun son identifiant (donc son fichier temporaire)",
		tostring(a.w.GLOBAL.logtime_process_token) ~= tostring(b.w.GLOBAL.logtime_process_token),
		true
	)
	-- on passe dans B : il prend la main ; les 10 min passées dans A ne sont pas de l'inactivité de B
	function win_a:is_focused()
		return false
	end
	b_focused = true
	-- B a le focus, mais rien n'y bouge pendant 2 min (on lit l'écran : moins que les 5 min d'inactivité), puis on y
	-- travaille. Sa dernière activité doit repartir de sa prise de main : sinon les 10 min passées dans A compteraient
	-- comme de l'inactivité de B.
	both(601, 720, false, false)
	both(721, 900, false, true)
	check(
		"deux WezTerm : le fichier .logtime_focus désigne B",
		read(D .. ".logtime_focus"),
		tostring(b.w.GLOBAL.logtime_process_token)
	)
	check("deux WezTerm : B attribue maintenant à son projet", (projects_now()["autre/projet"] or 0) >= 290, true)
	check(
		"deux WezTerm : A n'ajoute plus rien à son projet (il garde ses 10 min)",
		projects_now()["42/C05"] <= 602,
		true
	)
	check(
		"deux WezTerm : pas d'inactif compté pour les 10 min passées dans A (B repart de sa prise de main)",
		read(D .. ".logtime_idle.json"),
		nil
	)
	check(
		"deux WezTerm : les heures continuent, une seule fois (sauvegardées à la seconde 891)",
		read(D .. ".logtime.json"),
		'{"2026-10-13":891}'
	)
	check("deux WezTerm : toujours aucune erreur", #a.w.logs.error + #b.w.logs.error, 0)
	-- une pause dans B : l'inactif est noté (B est celui qui attribue), et retiré de son projet
	both(901, 1800, false, false)
	check("deux WezTerm : une pause dans B, notée en inactif", read(D .. ".logtime_idle.json") ~= nil, true)
	check(
		"deux WezTerm : l'inactif est retiré du projet de B (la fusion ne le remet pas)",
		projects_now()["autre/projet"] < 600,
		true
	)
	check("deux WezTerm : A ne compte jamais cette pause dans son projet", projects_now()["42/C05"] <= 602, true)
	cleanup(a)

	-- un WezTerm n'efface jamais ce qu'un autre a écrit : A sauvegarde un jour, B (lancé avant) ne l'efface pas
	clock.now = T0
	a = new_env({ file = false })
	a.M.apply_to_config({})
	b = new_env({ home = a.home })
	b.M.apply_to_config({})
	win_a, win_b = a.window(), b.window()
	pane_a, pane_b = screen_pane(a), screen_pane(b)
	for _, handler in ipairs(b.w.events["update-status"] or {}) do
		handler(win_b, pane_b) -- B lit le fichier (vide) au démarrage
	end
	write(a.home .. "/.local/share/logtime/.logtime.json", '{"2026-10-10":5000}') -- A a sauvegardé entre-temps
	for s_ = 1, 12 do
		clock.now = T0 + s_
		for _, handler in ipairs(b.w.events["update-status"] or {}) do
			handler(win_b, pane_b)
		end
	end
	check(
		"deux WezTerm : B garde le jour sauvegardé par A (relu juste avant d'écrire)",
		read(a.home .. "/.local/share/logtime/.logtime.json"),
		'{"2026-10-10":5000,"2026-10-13":11}'
	)
	cleanup(a)

	-- les projets aussi : B garde les projets qu'un autre WezTerm a sauvegardés entre-temps
	clock.now = T0
	b = new_env({ file = false })
	b.M.apply_to_config({})
	win_b = b.window()
	pane_b = screen_pane(b, "file:///C:/Users/max/autre/projet/", "zsh")
	local PF = b.home .. "/.local/share/logtime/.logtime_projects.json"
	for s_ = 0, 1 do
		clock.now = T0 + s_
		pane_b.text = "$ " .. s_
		for _, handler in ipairs(b.w.events["update-status"] or {}) do
			handler(win_b, pane_b)
		end
	end
	write(PF, '{"2026-10-12":{"hier":3600},"2026-10-13":{"ailleurs":50}}') -- un autre WezTerm a sauvegardé
	for s_ = 2, 12 do
		clock.now = T0 + s_
		pane_b.text = "$ " .. s_
		for _, handler in ipairs(b.w.events["update-status"] or {}) do
			handler(win_b, pane_b)
		end
	end
	check(
		"deux WezTerm : B garde les projets sauvegardés par un autre (hier, et « ailleurs » aujourd'hui)",
		read(PF),
		'{"2026-10-12":{"hier":3600},"2026-10-13":{"ailleurs":50,"autre/projet":11}}'
	)
	-- le fichier de projets devient illisible pendant que WezTerm tourne : jamais écrasé, mis de côté, puis réécrit
	write(PF, "abîmé par un autre programme")
	for s_ = 13, 40 do
		clock.now = T0 + s_
		pane_b.text = "$ " .. s_
		for _, handler in ipairs(b.w.events["update-status"] or {}) do
			handler(win_b, pane_b)
		end
	end
	local kept_projects = io.popen("ls -a '" .. b.home .. "/.local/share/logtime'"):read("*a")
	check(
		"fichier de projets abîmé en cours de route : mis de côté (jamais écrasé)",
		kept_projects:find(".logtime_projects.json.corrupt-", 1, true) ~= nil,
		true
	)
	check(
		"fichier de projets abîmé en cours de route : un nouveau fichier lisible ensuite",
		module("storage/projects").decode(read(PF) or "") ~= nil,
		true
	)
	cleanup(b)

	-- sans option lang : l'interface est en anglais (le plugin chargé tel quel, sans le lang = "fr" de ces tests)
	clock.now = T0
	e = new_env({ file = false })
	e.M = assert(loadfile(root .. "/plugin/init.lua"))(root)
	config = e.M.apply_to_config({})
	win = e.window()
	screen = screen_pane(e)
	open_binding(config, "F2")(win, screen)
	local page_text = last_text(e.w.spawned[#e.w.spawned].pane)
	check("langue par défaut : le calendrier est en anglais", page_text:find("October 2026", 1, true) ~= nil, true)
	check("langue par défaut : rien en français", page_text:find("Octobre", 1, true), nil)
	local cal_tab = e.w.spawned[#e.w.spawned].pane.the_tab
	check("onglet du calendrier : son titre est « Logtime » (et non PING.EXE)", cal_tab.title, "Logtime")
	page_binding(config, "l")(win, e.w.spawned[#e.w.spawned].pane)
	check("onglet du calendrier : le titre n'est pas redonné à chaque dessin", cal_tab.title_changes, 1)
	open_binding(config, "F4")(win, screen)
	check(
		"onglet des réglages : « Logtime · Settings » (dans la langue choisie)",
		e.w.spawned[#e.w.spawned].pane.the_tab.title,
		"Logtime · Settings"
	)
	cleanup(e)

	-- les traces (chaque touche, chaque dessin) : éteintes par défaut, allumées avec debug = true
	local function traces(env)
		local n = 0
		for _, m in ipairs(env.w.logs.info) do
			if m:find("logtime (", 1, true) or m:find("drawing month", 1, true) or m:find("page keys", 1, true) then
				n = n + 1
			end
		end
		return n
	end
	for _, debug in ipairs({ false, true }) do
		clock.now = T0
		e = new_env({ file = false })
		local opts = debug and { debug = true } or {}
		config = e.M.apply_to_config({}, opts)
		win = e.window()
		screen = screen_pane(e)
		open_binding(config, "F2")(win, screen)
		check(
			debug and "debug = true : ouvrir le calendrier laisse des traces"
				or "par défaut : ouvrir le calendrier ne laisse aucune trace dans les journaux",
			traces(e) > 0,
			debug
		)
		check("debug = " .. tostring(debug) .. " : aucune option inconnue signalée", #e.w.logs.error, 0)
		cleanup(e)
	end

	-- le fichier ne se lit pas tout de suite : le temps inactif attend en mémoire, puis s'ajoute au fichier
	clock.now = T0
	e = new_env({ file = false })
	write(e.home .. "/.local/share/logtime/.logtime_idle.json", '{"2026-10-12":7200,"2026-10-13":50}')
	e.M.apply_to_config({})
	screen = screen_pane(e)
	open_fails[1] = "logtime_idle"
	live(e, win, screen, 0, 400, false)
	open_fails[1] = nil
	live(e, win, screen, 401, 421, false) -- sauvegardé à 401, 411 et 421
	check(
		"inactif, lu en retard : la mémoire (421 s) l'emporte sur le fichier (50 s), les autres jours sont gardés",
		read(e.home .. "/.local/share/logtime/.logtime_idle.json"),
		'{"2026-10-12":7200,"2026-10-13":421}'
	)
	cleanup(e)
	-- un fichier abîmé qu'on ne peut pas mettre de côté : jamais écrasé, signalé une seule fois
	clock.now = T0
	e = new_env({ file = false })
	write(e.home .. "/.local/share/logtime/.logtime_idle.json", "pas du json")
	e.M.apply_to_config({})
	local real_rename = os.rename
	os.rename = function(from, to)
		if tostring(from):find("logtime_idle", 1, true) then
			return nil, "refusé"
		end
		return real_rename(from, to)
	end
	screen = screen_pane(e)
	live(e, win, screen, 0, 400, false)
	os.rename = real_rename
	check(
		"inactif, impossible à mettre de côté : pas écrasé",
		read(e.home .. "/.local/share/logtime/.logtime_idle.json"),
		"pas du json"
	)
	check("inactif, impossible à mettre de côté : une seule erreur", #e.w.logs.error, 1)
	check("inactif, impossible à mettre de côté : le compteur compte quand même", e.M.today_seconds(), 400)
	cleanup(e)
end

current_mode = "plain"
label = ""
scenarios()
current_mode = "wrapped"
label = "[nombres Value] "
scenarios()

check("aucune écriture en dehors des dossiers temporaires", #outside, 0)
local leaked = {}
for k in pairs(_G) do
	if not globals_before[k] then
		leaked[#leaked + 1] = k
	end
end
check("aucune variable globale ajoutée", table.concat(leaked, ","), "")

-- Tous les messages écrits dans les journaux pendant ces scénarios (avec lang = "fr" !) sont en anglais.
local french = {}
for _, m in ipairs(all_logs) do
	-- un accent, des « », ou un petit mot français courant (certaines phrases françaises n'ont aucun accent)
	local padded = " " .. m:lower():gsub("[%p]", " ") .. " "
	local word = false
	for _, w in ipairs({ "dans", "le", "la", "les", "du", "des", "une", "est", "pas", "sur", "avec", "pour" }) do
		word = word or padded:find(" " .. w .. " ", 1, true) ~= nil
	end
	if m:find("[éèàçêùôîâ«»]") or word then
		french[#french + 1] = m
	end
end
check("journaux : au moins 50 messages vus (le garde-fou a de quoi vérifier)", #all_logs >= 50, true)
check("journaux : tous en anglais (aucun accent, ni « », ni petit mot français)", table.concat(french, " | "), "")

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
