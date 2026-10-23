-- tests/pages/test_calendar_page.lua : teste pages/calendar_page.lua et config/keys.lua avec une fausse API WezTerm
-- aussi difficile que la vraie (voir plugin/init.lua). Lancer :   lua5.4 tests/pages/test_calendar_page.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]pages[/\\]test_calendar_page%.lua$") or "."

local globals_before = {}
for k in pairs(_G) do
	globals_before[k] = true
end
local real_open = io.open
local writes = {}
io.open = function(path, mode)
	if mode and (mode:find("w") or mode:find("a") or mode:find("%+")) then
		writes[#writes + 1] = path
	end
	return real_open(path, mode)
end

-- horloge simulée : le mois « en cours » est octobre 2026
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
local calendar_page = load_module("pages/calendar_page")
local assemble = load_module("calendar/assemble")
local convert = load_module("color/convert")
local keys = load_module("config/keys")
local platform = load_module("system/platform")
local fr = load_module("i18n/fr")
local en = load_module("i18n/en")

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
-- pas de __lt, __le ni __eq : un Value ne se compare pas à un nombre, comme chez toi

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

-- la conversion que fait plugin/init.lua pour toute valeur lue dans GLOBAL
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

-- ---- une fausse API WezTerm
local function new_wezterm()
	local w = {
		logs = { error = {} },
		events = {},
		timers = {},
		panes = {},
		spawned = {},
		GLOBAL = hostile_global(),
		target_triple = "x86_64-pc-windows-msvc",
	}
	current_w = w
	w.log_error = function(m)
		w.logs.error[#w.logs.error + 1] = m
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
	w.next_id = 100
	function w.new_pane(rows)
		w.next_id = w.next_id + 1
		local tab = { activated = false }
		function tab:activate()
			self.activated = true
		end
		local pane = { id = w.next_id, injected = {}, dims = { viewport_rows = rows or 40, cols = 120 }, the_tab = tab }
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
	function w.run_timers()
		local list = w.timers
		w.timers = {}
		for _, t in ipairs(list) do
			t.fn()
		end
	end
	return w
end
local function new_window(w, opts)
	opts = opts or {}
	local win = { performed = {}, toasts = {} }
	function win:perform_action(action, pane)
		self.performed[#self.performed + 1] = { action = action, pane = pane }
	end
	function win:toast_notification(title, message, url, timeout)
		self.toasts[#self.toasts + 1] = { title = title, message = message }
	end
	function win:mux_window()
		return {
			spawn_tab = function(_, spec)
				if opts.spawn_fails then
					error("impossible d'ouvrir un onglet")
				end
				local pane = w.new_pane(opts.rows)
				w.spawned[#w.spawned + 1] = { spec = spec, pane = pane }
				return pane.the_tab, pane, nil
			end,
		}
	end
	return win
end
local function kinds(win)
	local out = {}
	for _, p in ipairs(win.performed) do
		out[#out + 1] = p.action.kind
	end
	return table.concat(out, ",")
end
local function strip(text)
	return (text:gsub("\27%[[%d;]*m", ""))
end
local function new_page(w, extra)
	local days = { ["2026-10-10"] = 15231, ["2026-10-12"] = 3600, ["2026-09-30"] = 1800, ["2026-11-02"] = 7200 }
	local ctx = {
		wezterm = w,
		G = w.GLOBAL,
		num = num,
		days = function()
			return days
		end,
		today_key = function()
			return "2026-10-13"
		end,
		cfg = function()
			return { week_starts_on = "monday", day_offset = 0 }
		end,
		labels = function()
			return fr
		end,
		blocker_args = function()
			return platform.blocker_args("windows")
		end,
	}
	for k, v in pairs(extra or {}) do
		ctx[k] = v
	end
	return calendar_page.create(ctx), ctx
end
-- key : "h", ou "SHIFT-Tab" pour une touche avec un modificateur
local function binding(page, key)
	local mods, plain_key = key:match("^(%u+)%-(.+)$")
	for _, b in ipairs(page.key_table()) do
		if b.key == (plain_key or key) and b.mods == mods then
			return function(window, pane)
				fire(b.action, window, pane)
			end
		end
	end
end
local function month_of(w)
	return num(w.GLOBAL.logtime_page_year), num(w.GLOBAL.logtime_page_month)
end
local START = "\27[?1049h\27[?25l\27[?7l"

local function scenarios()
	-- ============================================================
	-- le texte de la page
	-- ============================================================
	local w = new_wezterm()
	local page = new_page(w)
	local text = strip(page.build_text())
	local text_lines = {}
	for line in (text .. "\n"):gmatch("(.-)\n") do
		text_lines[#text_lines + 1] = line
	end
	check(
		"texte : l'aide dans un cadre en haut, ses parties séparées par des traits",
		text_lines[1]:sub(1, #"╭") .. " " .. text_lines[2] .. " " .. text_lines[3]:sub(1, #"╰"),
		"╭ │ vue d'ensemble : Entrée │ Aujourd'hui : t │ Fermer : Échap/q  │ ╰"
	)
	check(
		"texte : le cadre de l'aide a la largeur du mois",
		utf8.len(text_lines[1]) .. " " .. utf8.len(text_lines[2]) .. " " .. utf8.len(text_lines[3]),
		"65 65 65"
	)
	check(
		"texte : en bas, la légende seule, sans cadre ni étoile",
		text_lines[#text_lines],
		"  0h ████████████████ 24h"
	)
	check("texte : plus d'étoile en bas (elle est en haut quand il y a la place)", text:find("* =", 1, true), nil)
	local english = strip(new_page(w, {
		labels = function()
			return en
		end,
	}).build_text())
	check(
		"texte en anglais, un mois : « Logtime: » tient, pas la case de « * = Today »",
		english:match("^[^\n]*\n([^\n]*)"),
		"│ Logtime: overview: Enter │ Today: t │ Close: Esc/q            │"
	)
	local wide = strip(page.build_text({ cols = 140, rows = 60 }))
	local wide_second = wide:match("^[^\n]*\n([^\n]*)")
	check(
		"texte, plusieurs mois : « Logtime : » devant l'aide, une case vide, et « * = Aujourd'hui » dans sa case au bord droit",
		wide_second:find(
			"^│ Logtime : vue d'ensemble : Entrée │ Aujourd'hui : t │ Fermer : Échap/q │ +│ %* = Aujourd'hui │$"
		) ~= nil,
		true
	)
	-- avec les encadrés : le cadre de l'aide aligné sur ceux des mois (une colonne de marge, jusqu'au bout du dernier)
	local framed_page = new_page(w, {
		cfg = function()
			return { week_starts_on = "monday", day_offset = 0, borders = true }
		end,
	})
	local framed = {}
	for line in (strip(framed_page.build_text({ cols = 140, rows = 60 })) .. "\n"):gmatch("(.-)\n") do
		framed[#framed + 1] = line
	end
	local month_top
	for k = 4, #framed do
		if not month_top and framed[k]:find("╭", 1, true) then
			month_top = framed[k]
		end
	end
	check(
		"encadrés : l'aide commence à la même colonne que les cadres des mois",
		framed[1]:find("╭", 1, true),
		month_top:find("╭", 1, true)
	)
	check(
		"encadrés : et finit à la même colonne que le dernier",
		utf8.len((framed[1]:gsub("%s+$", ""))),
		utf8.len((month_top:gsub("%s+$", "")))
	)
	check(
		"texte : le mois en cours (octobre 2026) est dessiné",
		text:find("Logtime : Octobre 2026", 1, true) ~= nil,
		true
	)
	check("texte : les heures du 10 octobre sont là", text:find("4h13", 1, true) ~= nil, true)
	check(
		"texte : septembre et novembre ne sont pas mélangés",
		text:find("0h30", 1, true) == nil and text:find("2h00", 1, true) == nil,
		true
	)

	-- ============================================================
	-- ouvrir la page
	-- ============================================================
	w = new_wezterm()
	page = new_page(w)
	local win = new_window(w)
	page.open(win, w.new_pane())
	check("ouvrir : un onglet est créé", #w.spawned, 1)
	check("ouvrir : dans le domaine local", w.spawned[1].spec.domain.DomainName, "local")
	check(
		"ouvrir : avec le programme qui garde l'onglet ouvert (ping sous Windows)",
		w.spawned[1].spec.args[3],
		"ping -n 86400 127.0.0.1>nul"
	)
	local page_pane = w.spawned[1].pane
	check("ouvrir : l'onglet est mis devant", page_pane.the_tab.activated, true)
	check("ouvrir : l'identifiant du panneau est retenu", num(w.GLOBAL.logtime_page_pane), page_pane.id)
	local year, month = month_of(w)
	check("ouvrir : le mois affiché est le mois en cours", year .. "-" .. month, "2026-10")
	check("ouvrir : premier dessin, avec l'écran alternatif", page_pane.injected[1]:sub(1, #START), START)
	check(
		"ouvrir : le dessin contient le calendrier",
		strip(page_pane.injected[1]):find("Logtime : Octobre 2026", 1, true) ~= nil,
		true
	)
	check("ouvrir : les touches de la page sont activées", kinds(win), "ActivateKeyTable")
	check(
		"ouvrir : table de touches durable, sur le bon panneau",
		win.performed[1].action.args.one_shot == false
			and win.performed[1].action.args.name == "logtime_page"
			and win.performed[1].pane == page_pane,
		true
	)
	check(
		"ouvrir : deux redessins différés (0,4 s et 1,2 s)",
		#w.timers == 2 and w.timers[1].seconds == 0.4 and w.timers[2].seconds == 1.2,
		true
	)
	w.run_timers()
	check(
		"redessins différés : la page est redessinée deux fois, sans repasser en écran alternatif",
		#page_pane.injected == 3
			and page_pane.injected[2]:sub(1, 4) == "\27[2J"
			and page_pane.injected[3]:sub(1, 4) == "\27[2J",
		true
	)
	check("is_page : le panneau de la page", page.is_page(page_pane), true)
	check("is_page : un autre panneau", page.is_page(w.new_pane()), false)

	-- fermer avant les redessins différés : rien ne revient
	w = new_wezterm()
	page = new_page(w)
	win = new_window(w)
	page.open(win, w.new_pane())
	page_pane = w.spawned[1].pane
	binding(page, "q")(win, page_pane)
	local before = #page_pane.injected
	w.run_timers()
	check("redessin différé après fermeture : rien n'est redessiné", #page_pane.injected, before)

	-- ouvrir deux fois : la page existante revient devant
	w = new_wezterm()
	page = new_page(w)
	win = new_window(w)
	page.open(win, w.new_pane())
	page_pane = w.spawned[1].pane
	page_pane.the_tab.activated = false
	local count = #page_pane.injected
	page.open(win, w.new_pane())
	check("deux ouvertures : pas de deuxième onglet", #w.spawned, 1)
	check("deux ouvertures : l'onglet existant est remis devant", page_pane.the_tab.activated, true)
	check(
		"deux ouvertures : redessiné sans repasser en écran alternatif",
		#page_pane.injected == count + 1 and page_pane.injected[count + 1]:sub(1, 4) == "\27[2J",
		true
	)

	-- page périmée (onglet fermé à la souris) : une nouvelle page s'ouvre, sans erreur
	w = new_wezterm()
	page = new_page(w)
	win = new_window(w)
	page.open(win, w.new_pane())
	local old_id = w.spawned[1].pane.id
	w.panes[old_id] = nil
	local ok = pcall(page.open, win, w.new_pane())
	check("page périmée : aucune erreur", ok, true)
	check("page périmée : un nouvel onglet est ouvert", #w.spawned, 2)
	check("page périmée : le nouvel identifiant est retenu", num(w.GLOBAL.logtime_page_pane), w.spawned[2].pane.id)

	-- ============================================================
	-- les touches
	-- ============================================================
	w = new_wezterm()
	page = new_page(w)
	win = new_window(w)
	page.open(win, w.new_pane())
	page_pane = w.spawned[1].pane
	local function press(key, pane)
		local w2 = new_window(w)
		binding(page, key)(w2, pane or page_pane)
		return w2
	end
	press("Enter") -- on ne change de mois que dans la vue d'ensemble
	press("PageUp")
	year, month = month_of(w)
	check("PgUp : mois précédent (septembre 2026)", year .. "-" .. month, "2026-9")
	check(
		"PgUp : le dessin est mis à jour",
		strip(page_pane.injected[#page_pane.injected]):find("13 septembre", 1, true) ~= nil,
		true
	)
	check(
		"PgUp : septembre affiche ses heures (0h30 le 30)",
		strip(page_pane.injected[#page_pane.injected]):find("0h30", 1, true) ~= nil,
		true
	)
	press("PageUp")
	year, month = month_of(w)
	check("PgUp encore : août 2026", year .. "-" .. month, "2026-8")
	press("PageDown")
	press("PageDown")
	press("PageDown")
	year, month = month_of(w)
	check("PgDn trois fois : trois mois plus tard = novembre 2026", year .. "-" .. month, "2026-11")
	-- Tab et Shift+Tab : comme PgDn et PgUp (tous les claviers n'ont pas ces touches)
	press("Tab")
	year, month = month_of(w)
	check("Tab : le mois suivant (décembre 2026)", year .. "-" .. month, "2026-12")
	press("SHIFT-Tab")
	press("SHIFT-Tab")
	year, month = month_of(w)
	check("Shift+Tab deux fois : deux mois avant (octobre 2026)", year .. "-" .. month, "2026-10")
	press("Tab")
	year, month = month_of(w)
	check("Tab : retour à novembre 2026", year .. "-" .. month, "2026-11")
	check(
		"novembre affiche ses heures (2h00 le 2)",
		strip(page_pane.injected[#page_pane.injected]):find("2h00", 1, true) ~= nil,
		true
	)
	press("t")
	year, month = month_of(w)
	check("t : retour au mois en cours", year .. "-" .. month, "2026-10")
	w.GLOBAL.logtime_page_year, w.GLOBAL.logtime_page_month = 2026, 1
	press("PageUp")
	year, month = month_of(w)
	check("janvier puis PgUp : décembre de l'année d'avant", year .. "-" .. month, "2025-12")
	press("PageDown")
	year, month = month_of(w)
	check("décembre puis PgDn : janvier de l'année d'après", year .. "-" .. month, "2026-1")
	w.GLOBAL.logtime_page_year, w.GLOBAL.logtime_page_month = 2026, 12
	press("PageDown")
	year, month = month_of(w)
	check("décembre 2026 puis PgDn : janvier 2027", year .. "-" .. month, "2027-1")
	count = #page_pane.injected
	press("r")
	year, month = month_of(w)
	check(
		"r : redessine sans changer de mois",
		#page_pane.injected == count + 1 and year .. "-" .. month == "2027-1",
		true
	)
	w.GLOBAL.logtime_page_year, w.GLOBAL.logtime_page_month = 2200, 12
	count = #page_pane.injected
	press("PageDown")
	year, month = month_of(w)
	check("limite : pas au-delà de l'année 2200", #page_pane.injected == count and year == 2200, true)
	w.GLOBAL.logtime_page_year, w.GLOBAL.logtime_page_month = 1970, 1
	press("PageUp")
	year = month_of(w)
	check("limite : pas avant 1970", year, 1970)

	-- fermer
	for _, key in ipairs({ "q", "Escape" }) do
		w = new_wezterm()
		page = new_page(w)
		win = new_window(w)
		page.open(win, w.new_pane())
		page_pane = w.spawned[1].pane
		local w2 = new_window(w)
		binding(page, key)(w2, page_pane)
		check(key .. " : la page est oubliée", w.GLOBAL.logtime_page_pane, nil)
		check(key .. " : touches retirées puis onglet fermé", kinds(w2), "PopKeyTable,CloseCurrentTab")
		check(key .. " : fermeture sans confirmation", w2.performed[2].action.args.confirm, false)
		check(key .. " : ce n'est plus la page", page.is_page(page_pane), false)
	end

	-- une touche pressée ailleurs que dans la page n'est jamais avalée
	w = new_wezterm()
	page = new_page(w)
	win = new_window(w)
	page.open(win, w.new_pane())
	page_pane = w.spawned[1].pane
	local elsewhere = w.new_pane()
	local before_month = select(2, month_of(w))
	local w3 = new_window(w)
	binding(page, "h")(w3, elsewhere)
	check("touche ailleurs : touches de la page retirées puis touche rendue", kinds(w3), "PopKeyTable,SendKey")
	check("touche ailleurs : la bonne touche est rendue", w3.performed[2].action.args.key, "h")
	check("touche ailleurs : le mois ne change pas", select(2, month_of(w)), before_month)
	check("touche ailleurs : rien n'est dessiné dans l'autre onglet", #elsewhere.injected, 0)

	-- ============================================================
	-- le redimensionnement
	-- ============================================================
	w = new_wezterm()
	page = new_page(w)
	win = new_window(w)
	page.open(win, w.new_pane())
	page_pane = w.spawned[1].pane
	w.run_timers()
	page_pane.dims.viewport_rows = 8
	count = #page_pane.injected
	page.on_resize(win, w.new_pane())
	check("redimensionnement : la page est redessinée", #page_pane.injected, count + 1)
	local drawn = page_pane.injected[#page_pane.injected]
	check(
		"redimensionnement : à 8 lignes, le message « fenêtre trop petite » remplace le calendrier",
		drawn:find("Fenêtre trop petite", 1, true) ~= nil,
		true
	)
	check(
		"redimensionnement : deux redessins différés (0,3 s et 1 s)",
		#w.timers == 2 and w.timers[1].seconds == 0.3 and w.timers[2].seconds == 1.0,
		true
	)
	w.run_timers()
	check("redimensionnement : les redessins différés ont lieu", #page_pane.injected, count + 3)
	w = new_wezterm()
	page = new_page(w)
	ok = pcall(page.on_resize, new_window(w), w.new_pane())
	check("redimensionnement sans page ouverte : rien, sans erreur", ok and #w.timers == 0, true)
	w = new_wezterm()
	page = new_page(w)
	win = new_window(w)
	page.open(win, w.new_pane())
	w.panes[w.spawned[1].pane.id] = nil
	ok = pcall(page.on_resize, win, nil)
	check("redimensionnement avec une page disparue : sans erreur", ok, true)

	-- ============================================================
	-- config/keys.lua
	-- ============================================================
	w = new_wezterm()
	page = new_page(w)
	local existing = { key = "k", mods = "CTRL", action = "quelque_chose" }
	local config = { keys = { existing } }
	keys.apply(config, w, { page = page, open_key = "F2", table_name = "logtime_page" })
	check(
		"keys : ses touches sont ajoutées à la suite des tiennes",
		#config.keys == 2 and config.keys[1] == existing and config.keys[2].key == "F2",
		true
	)
	check(
		"keys : la table de touches de la page existe, avec 17 touches (Tab et Shift+Tab compris)",
		#config.key_tables.logtime_page,
		17
	)
	check(
		"keys : un gestionnaire de redimensionnement est installé",
		w.events["window-resized"] ~= nil and #w.events["window-resized"],
		1
	)
	check("keys : aucune erreur de configuration", #w.logs.error, 0)
	win = new_window(w)
	fire(config.keys[2].action, win, w.new_pane())
	check("keys : F2 ouvre la page", #w.spawned, 1)
	local bare = keys.apply({}, w, { page = page, open_key = "F2", table_name = "t" })
	check(
		"keys : une configuration sans touches ni tables est complétée",
		#bare.keys == 1 and bare.key_tables.t ~= nil,
		true
	)
	check(
		"keys : touche personnalisée",
		keys.apply({}, w, { page = page, open_key = "F5", table_name = "t" }).keys[1].key,
		"F5"
	)

	w = new_wezterm()
	page = new_page(w)
	config = { keys = { { key = "F2", action = "autre chose" } } }
	keys.apply(config, w, { page = page, open_key = "F2", table_name = "logtime_page" })
	check(
		"keys : touche déjà utilisée : prévenu dans les journaux",
		#w.logs.error == 1 and w.logs.error[1]:find("F2", 1, true) ~= nil,
		true
	)
	w = new_wezterm()
	page = new_page(w)
	keys.apply(
		{ keys = { { key = "F2", mods = "SHIFT", action = "autre chose" } } },
		w,
		{ page = page, open_key = "F2", table_name = "logtime_page" }
	)
	check("keys : F2 avec SHIFT n'est pas la même touche : pas d'alerte", #w.logs.error, 0)

	w = new_wezterm()
	page = new_page(w)
	config = keys.apply({}, w, { page = page, open_key = "F2", table_name = "logtime_page" })
	win = new_window(w, { spawn_fails = true })
	local ok_press = pcall(fire, config.keys[1].action, win, w.new_pane())
	check("F2 qui échoue : pas de plantage", ok_press, true)
	check("F2 qui échoue : erreur journalisée", #w.logs.error, 1)
	check("F2 qui échoue : notification affichée", #win.toasts, 1)
	check("F2 qui échoue : le message nomme l'ouverture", win.toasts[1].message:find("(open)", 1, true) ~= nil, true)

	-- en anglais
	w = new_wezterm()
	page = new_page(w, {
		labels = function()
			return en
		end,
	})
	page.open(new_window(w), w.new_pane())
	check(
		"anglais : la page est en anglais",
		strip(w.spawned[1].pane.injected[1]):find("Logtime: October 2026", 1, true) ~= nil
			and strip(w.spawned[1].pane.injected[1]):find("overview: Enter", 1, true) ~= nil,
		true
	)

	-- ============================================================
	-- la vue d'ensemble (touche Entrée, calendar/board.lua)
	-- ============================================================
	w = new_wezterm()
	page = new_page(w)
	win = new_window(w)
	page.open(win, w.new_pane())
	page_pane = w.spawned[1].pane
	local function shown_now()
		return strip(page_pane.injected[#page_pane.injected])
	end
	local function board_day()
		local year_, month_ = month_of(w)
		return string.format("%d-%02d-%02d", year_, month_, num(w.GLOBAL.logtime_page_day))
	end
	check("ouverture : la vue des mois", num(w.GLOBAL.logtime_page_view), calendar_page.VIEW.MONTHS)
	check(
		"plus de touche a (la vue d'ensemble est sur Entrée)",
		(function()
			for _, b in ipairs(page.bindings()) do
				if b.key == "a" then
					return false
				end
			end
			return true
		end)(),
		true
	)
	press("Enter")
	check("Entrée : la vue d'ensemble", num(w.GLOBAL.logtime_page_view), calendar_page.VIEW.OVERVIEW)
	check(
		"Entrée : les chiffres de l'année en haut",
		shown_now():find("Total de l'année : 7h43", 1, true) ~= nil,
		true
	)
	check(
		"Entrée : l'aide de la vue d'ensemble",
		shown_now():find("mois : Tab Maj+Tab", 1, true) ~= nil and shown_now():find("rafraîchir : r", 1, true) ~= nil,
		true
	)
	local board_lines = {}
	for line in (shown_now() .. "\n"):gmatch("(.-)\n") do
		board_lines[#board_lines + 1] = line
	end
	check("Entrée : toute la fenêtre (120 x 40 par défaut, sans fenêtre connue)", #board_lines, 40)
	press("l")
	check("vue d'ensemble, l : le jour suivant (plus l'année suivante)", board_day(), "2026-10-14")
	press("DownArrow")
	check("vue d'ensemble, ↓ : la semaine suivante", board_day(), "2026-10-21")
	press("Tab")
	year, month = month_of(w)
	check("vue d'ensemble, Tab : le mois suivant", year .. "-" .. month, "2026-11")
	press("t")
	check("vue d'ensemble, t : aujourd'hui", board_day(), "2026-10-13")
	check("vue d'ensemble, t : on y reste", num(w.GLOBAL.logtime_page_view), calendar_page.VIEW.OVERVIEW)
	press("Escape")
	check("vue d'ensemble, Échap : retour aux mois", num(w.GLOBAL.logtime_page_view), calendar_page.VIEW.MONTHS)
	check("vue d'ensemble, Échap : la page reste ouverte", num(w.GLOBAL.logtime_page_pane), page_pane.id)
	press("Enter")
	press("Enter")
	check("Entrée de nouveau : les mois", num(w.GLOBAL.logtime_page_view), calendar_page.VIEW.MONTHS)
	check("Entrée de nouveau : le mois est dessiné", shown_now():find("Logtime : Octobre 2026", 1, true) ~= nil, true)
	-- rouvrir F2 : on revient aux mois
	press("Enter")
	w.GLOBAL.logtime_page_pane = nil
	page.open(new_window(w), w.new_pane())
	check("rouvrir F2 : la vue des mois", num(w.GLOBAL.logtime_page_view), calendar_page.VIEW.MONTHS)
	-- la taille de la fenêtre
	w = new_wezterm()
	page = new_page(w)
	w.GLOBAL.logtime_page_view = calendar_page.VIEW.OVERVIEW
	local board_text, _, board_width = page.build_text({ cols = 150, rows = 45 })
	check("vue d'ensemble, 150 x 45 : dessinée", strip(board_text):find("Total de l'année", 1, true) ~= nil, true)
	check("vue d'ensemble : toute la largeur (rien à centrer)", board_width, 150)
	check(
		"vue d'ensemble : le mois choisi rempli de la couleur choisie (l'or par défaut)",
		board_text:find(convert.bg("#C9AB6B") .. convert.fg(convert.contrast("#C9AB6B")), 1, true) ~= nil,
		true
	)
	local board_top = strip(board_text):match("^[^\n]*\n([^\n]*)") -- la ligne des chiffres de l'année
	check(
		"vue d'ensemble : la légende des couleurs au bout de la ligne de l'année, sans « * = Aujourd'hui »",
		board_top:find("24h │", 1, true) ~= nil and board_top:find("* =", 1, true) == nil,
		true
	)
	local small_text = page.build_text({ cols = 99, rows = 40 })
	check(
		"vue d'ensemble, 99 colonnes : « fenêtre trop petite »",
		strip(small_text):find("Fenêtre trop petite", 1, true) == 1,
		true
	)
	check(
		"vue d'ensemble : la taille nécessaire",
		strip(small_text):find("120 colonnes sur 34 lignes", 1, true) ~= nil,
		true
	)
	check(
		"vue d'ensemble, 33 lignes : trop bas",
		strip(page.build_text({ cols = 120, rows = 33 })):find("Fenêtre trop petite", 1, true) == 1,
		true
	)

	-- ============================================================
	-- le calendrier de base (on ne s'y déplace pas), puis la vue d'ensemble (Entrée), où l'on se déplace
	-- ============================================================
	w = new_wezterm()
	page = new_page(w)
	page.open(new_window(w), w.new_pane())
	page_pane = w.spawned[1].pane
	local function day_of()
		local year_, month_ = month_of(w)
		return string.format("%d-%02d-%02d", year_, month_, num(w.GLOBAL.logtime_page_day))
	end
	local function drawn_raw()
		return page_pane.injected[#page_pane.injected]
	end
	check("ouverture : aujourd'hui", day_of(), "2026-10-13")
	check("ouverture : aujourd'hui marqué de son étoile", strip(drawn_raw()):find("*13", 1, true) ~= nil, true)
	check("ouverture : plus de case en couleurs inversées", drawn_raw():find("\27[7m", 1, true), nil)
	for _, key in ipairs({
		"RightArrow",
		"l",
		"LeftArrow",
		"h",
		"DownArrow",
		"j",
		"UpArrow",
		"k",
		"PageDown",
		"PageUp",
		"Tab",
	}) do
		press(key)
		check("calendrier de base : " .. key .. " ne déplace rien", day_of(), "2026-10-13")
	end
	check(
		"calendrier de base : toujours octobre",
		strip(drawn_raw()):find("Logtime : Octobre 2026", 1, true) ~= nil,
		true
	)
	press("Enter")
	check(
		"Entrée : la vue d'ensemble, sur aujourd'hui",
		strip(drawn_raw()):find("Mar 13 octobre 2026", 1, true) ~= nil,
		true
	)
	press("RightArrow")
	check("vue d'ensemble, → : le jour d'après", day_of(), "2026-10-14")
	press("l")
	check("vue d'ensemble, l : pareil", day_of(), "2026-10-15")
	press("LeftArrow")
	press("h")
	press("h")
	check("vue d'ensemble, ← h h : trois jours en arrière", day_of(), "2026-10-12")
	press("DownArrow")
	check("vue d'ensemble, ↓ : la semaine d'après", day_of(), "2026-10-19")
	press("j")
	press("j")
	check("vue d'ensemble, j j : on passe en novembre tout seul", day_of(), "2026-11-02")
	press("UpArrow")
	check("vue d'ensemble, ↑ : la semaine d'avant, retour en octobre", day_of(), "2026-10-26")
	press("k")
	check("vue d'ensemble, k : pareil", day_of(), "2026-10-19")
	w.GLOBAL.logtime_page_year, w.GLOBAL.logtime_page_month, w.GLOBAL.logtime_page_day = 2026, 12, 31
	press("RightArrow")
	check("31 décembre puis → : 1er janvier de l'année d'après", day_of(), "2027-01-01")
	press("LeftArrow")
	check("puis ← : 31 décembre", day_of(), "2026-12-31")
	w.GLOBAL.logtime_page_month, w.GLOBAL.logtime_page_day = 10, 31
	press("PageDown")
	check("31 octobre puis PgDn : 30 novembre (pas de 31)", day_of(), "2026-11-30")
	press("PageUp")
	check("puis PgUp : 30 octobre (le jour est gardé)", day_of(), "2026-10-30")
	w.GLOBAL.logtime_page_year, w.GLOBAL.logtime_page_month, w.GLOBAL.logtime_page_day = 2026, 2, 31
	check(
		"un jour trop grand dans GLOBAL : ramené à la fin du mois",
		strip(page.build_text()):find("Sam 28 février 2026", 1, true) ~= nil,
		true
	)
	press("t")
	check("vue d'ensemble, t : de nouveau aujourd'hui", day_of(), "2026-10-13")
	-- pas de jour enregistré : aujourd'hui dans le mois en cours, le 1er dans un autre
	w.GLOBAL.logtime_page_day = nil
	check(
		"pas de jour enregistré, mois en cours : aujourd'hui",
		strip(page.build_text()):find("Mar 13 octobre 2026", 1, true) ~= nil,
		true
	)
	w.GLOBAL.logtime_page_month = 9
	check(
		"pas de jour enregistré, autre mois : le 1er",
		strip(page.build_text()):find("Mar 1 septembre 2026", 1, true) ~= nil,
		true
	)
	press("t")
	-- le retour : le calendrier de base montre le mois où l'on était ; Entrée rouvre sur le même jour
	press("PageUp")
	press("Escape")
	check(
		"Échap dans la vue d'ensemble : retour au calendrier",
		num(w.GLOBAL.logtime_page_view),
		calendar_page.VIEW.MONTHS
	)
	check("Échap dans la vue d'ensemble : la page reste ouverte", num(w.GLOBAL.logtime_page_pane), page_pane.id)
	check(
		"retour : le mois où l'on était (septembre)",
		strip(drawn_raw()):find("Logtime : Septembre 2026", 1, true) ~= nil,
		true
	)
	press("Enter")
	check(
		"Entrée : rouvre sur le jour où l'on était",
		strip(drawn_raw()):find("Dim 13 septembre", 1, true) ~= nil,
		true
	)
	press("Enter")
	check("Entrée de nouveau : le calendrier", num(w.GLOBAL.logtime_page_view), calendar_page.VIEW.MONTHS)
	press("t")
	check(
		"calendrier de base, t : le mois d'aujourd'hui",
		strip(drawn_raw()):find("Logtime : Octobre 2026", 1, true) ~= nil,
		true
	)
	press("Escape")
	check("Échap dans le calendrier : la page est fermée", w.GLOBAL.logtime_page_pane, nil)
	-- rouvrir : aujourd'hui de nouveau, dans les mois
	page.open(new_window(w), w.new_pane())
	check("rouvrir : aujourd'hui", day_of(), "2026-10-13")
	-- une vue qui n'existe plus (3 : l'ancien détail du jour) dans GLOBAL : les mois
	w.GLOBAL.logtime_page_view = 3
	check(
		"vue inconnue dans GLOBAL : les mois",
		strip(page.build_text()):find("Logtime : Octobre 2026", 1, true) ~= nil,
		true
	)
end

current_mode = "plain"
label = ""
scenarios()
current_mode = "wrapped"
label = "[nombres Value] "
scenarios()

check("aucune écriture sur le disque", #writes, 0)
local leaked = {}
for k in pairs(_G) do
	if not globals_before[k] then
		leaked[#leaked + 1] = k
	end
end
check("aucune variable globale ajoutée", table.concat(leaked, ","), "")

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
