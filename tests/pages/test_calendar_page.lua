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
local keys = load_module("config/keys")
local platform = load_module("system/platform")
local fr = load_module("i18n/fr")
local en = load_module("i18n/en")

local passed, failed = 0, 0
local label = ""
local function check(name, got, want)
	name = label .. name
	if got == want then
		passed = passed + 1
	else
		failed = failed + 1
		print(string.format("ÉCHEC  %s\n         attendu : %s\n         obtenu  : %s", name, tostring(want), tostring(got)))
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
VALUE.__add = function(a, b) return raw(a) + raw(b) end
VALUE.__sub = function(a, b) return raw(a) - raw(b) end
VALUE.__mul = function(a, b) return raw(a) * raw(b) end
VALUE.__div = function(a, b) return raw(a) / raw(b) end
VALUE.__unm = function(a) return -raw(a) end
VALUE.__tostring = function(a) return tostring(raw(a)) end
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
error("test : wezterm.GLOBAL n'accepte ici que des valeurs simples (reçu " .. type(v) .. " pour " .. tostring(k) .. ")", 2)
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
	local w = { logs = { error = {} }, events = {}, timers = {}, panes = {}, spawned = {}, GLOBAL = hostile_global(), target_triple = "x86_64-pc-windows-msvc" }
	w.log_error = function(m) w.logs.error[#w.logs.error + 1] = m end
	w.action = {
		ActivateKeyTable = function(t) return { kind = "ActivateKeyTable", args = t } end,
		SendKey = function(t) return { kind = "SendKey", args = t } end,
		CloseCurrentTab = function(t) return { kind = "CloseCurrentTab", args = t } end,
		PopKeyTable = { kind = "PopKeyTable" },
	}
	w.action_callback = function(fn) return { kind = "callback", fn = fn } end
	w.on = function(event, handler)
		w.events[event] = w.events[event] or {}
		table.insert(w.events[event], handler)
	end
	w.time = { call_after = function(seconds, fn) w.timers[#w.timers + 1] = { seconds = seconds, fn = fn } end }
	w.mux = { get_pane = function(id)
		local pane = w.panes[id]
		if not pane then
			error("pane id " .. tostring(id) .. " not found in mux")
		end
		return pane
	end }
	w.next_id = 100
	function w.new_pane(rows)
		w.next_id = w.next_id + 1
		local tab = { activated = false }
		function tab:activate() self.activated = true end
		local pane = { id = w.next_id, injected = {}, dims = { viewport_rows = rows or 40, cols = 120 }, the_tab = tab }
		function pane:pane_id() return self.id end
		function pane:get_dimensions() return self.dims end
		function pane:inject_output(text) self.injected[#self.injected + 1] = text end
		function pane:tab() return self.the_tab end
		w.panes[pane.id] = pane
		return pane
	end
	function w.run_timers()
		local list = w.timers
		w.timers = {}
		for _, t in ipairs(list) do t.fn() end
	end
	return w
end
local function new_window(w, opts)
	opts = opts or {}
	local win = { performed = {}, toasts = {} }
	function win:perform_action(action, pane) self.performed[#self.performed + 1] = { action = action, pane = pane } end
	function win:toast_notification(title, message, url, timeout) self.toasts[#self.toasts + 1] = { title = title, message = message } end
	function win:mux_window()
		return { spawn_tab = function(_, spec)
			if opts.spawn_fails then error("impossible d'ouvrir un onglet") end
			local pane = w.new_pane(opts.rows)
			w.spawned[#w.spawned + 1] = { spec = spec, pane = pane }
			return pane.the_tab, pane, nil
		end }
	end
	return win
end
local function kinds(win)
	local out = {}
	for _, p in ipairs(win.performed) do out[#out + 1] = p.action.kind end
	return table.concat(out, ",")
end
local function strip(text)
	return (text:gsub("\27%[[%d;]*m", ""))
end
local function new_page(w, extra)
	local days = { ["2026-10-10"] = 15231, ["2026-10-12"] = 3600, ["2026-09-30"] = 1800, ["2026-11-02"] = 7200 }
	local ctx = {
		wezterm = w, G = w.GLOBAL, num = num,
		days = function() return days end,
		today_key = function() return "2026-10-13" end,
		cfg = function() return { week_starts_on = "monday", day_offset = 0 } end,
		labels = function() return fr end,
		blocker_args = function() return platform.blocker_args("windows") end,
	}
	for k, v in pairs(extra or {}) do ctx[k] = v end
	return calendar_page.create(ctx), ctx
end
local function binding(page, key)
	for _, b in ipairs(page.key_table()) do
		if b.key == key then return b.action.fn end
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
local first_line = text:match("^(.-)\n")
check("texte : première ligne = titre et aide", first_line, "  Logtime   " .. fr.page_help)
check("texte : le mois en cours (octobre 2026) est dessiné", text:find("Logtime : Octobre 2026", 1, true) ~= nil, true)
check("texte : les heures du 10 octobre sont là", text:find("4h13", 1, true) ~= nil, true)
check("texte : septembre et novembre ne sont pas mélangés", text:find("0h30", 1, true) == nil and text:find("2h00", 1, true) == nil, true)

-- ============================================================
-- ouvrir la page
-- ============================================================
w = new_wezterm()
page = new_page(w)
local win = new_window(w)
page.open(win, w.new_pane())
check("ouvrir : un onglet est créé", #w.spawned, 1)
check("ouvrir : dans le domaine local", w.spawned[1].spec.domain.DomainName, "local")
check("ouvrir : avec le programme qui garde l'onglet ouvert (ping sous Windows)", w.spawned[1].spec.args[3], "ping -n 86400 127.0.0.1>nul")
local page_pane = w.spawned[1].pane
check("ouvrir : l'onglet est mis devant", page_pane.the_tab.activated, true)
check("ouvrir : l'identifiant du panneau est retenu", num(w.GLOBAL.logtime_page_pane), page_pane.id)
local year, month = month_of(w)
check("ouvrir : le mois affiché est le mois en cours", year .. "-" .. month, "2026-10")
check("ouvrir : premier dessin, avec l'écran alternatif", page_pane.injected[1]:sub(1, #START), START)
check("ouvrir : le dessin contient le calendrier", strip(page_pane.injected[1]):find("Logtime : Octobre 2026", 1, true) ~= nil, true)
check("ouvrir : les touches de la page sont activées", kinds(win), "ActivateKeyTable")
check("ouvrir : table de touches durable, sur le bon panneau", win.performed[1].action.args.one_shot == false and win.performed[1].action.args.name == "logtime_page" and win.performed[1].pane == page_pane, true)
check("ouvrir : deux redessins différés (0,4 s et 1,2 s)", #w.timers == 2 and w.timers[1].seconds == 0.4 and w.timers[2].seconds == 1.2, true)
w.run_timers()
check("redessins différés : la page est redessinée deux fois, sans repasser en écran alternatif", #page_pane.injected == 3 and page_pane.injected[2]:sub(1, 4) == "\27[2J" and page_pane.injected[3]:sub(1, 4) == "\27[2J", true)
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
check("deux ouvertures : redessiné sans repasser en écran alternatif", #page_pane.injected == count + 1 and page_pane.injected[count + 1]:sub(1, 4) == "\27[2J", true)

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
press("h")
year, month = month_of(w)
check("h : mois précédent (septembre 2026)", year .. "-" .. month, "2026-9")
check("h : le dessin est mis à jour", strip(page_pane.injected[#page_pane.injected]):find("Logtime : Septembre 2026", 1, true) ~= nil, true)
check("h : septembre affiche ses heures (0h30 le 30)", strip(page_pane.injected[#page_pane.injected]):find("0h30", 1, true) ~= nil, true)
press("LeftArrow")
year, month = month_of(w)
check("flèche gauche : août 2026", year .. "-" .. month, "2026-8")
press("l")
press("RightArrow")
press("RightArrow")
year, month = month_of(w)
check("l et flèche droite : trois mois plus tard = novembre 2026", year .. "-" .. month, "2026-11")
check("novembre affiche ses heures (2h00 le 2)", strip(page_pane.injected[#page_pane.injected]):find("2h00", 1, true) ~= nil, true)
press("t")
year, month = month_of(w)
check("t : retour au mois en cours", year .. "-" .. month, "2026-10")
w.GLOBAL.logtime_page_year, w.GLOBAL.logtime_page_month = 2026, 1
press("h")
year, month = month_of(w)
check("janvier puis h : décembre de l'année d'avant", year .. "-" .. month, "2025-12")
press("l")
year, month = month_of(w)
check("décembre puis l : janvier de l'année d'après", year .. "-" .. month, "2026-1")
w.GLOBAL.logtime_page_year, w.GLOBAL.logtime_page_month = 2026, 12
press("l")
year, month = month_of(w)
check("décembre 2026 puis l : janvier 2027", year .. "-" .. month, "2027-1")
count = #page_pane.injected
press("r")
year, month = month_of(w)
check("r : redessine sans changer de mois", #page_pane.injected == count + 1 and year .. "-" .. month == "2027-1", true)
w.GLOBAL.logtime_page_year, w.GLOBAL.logtime_page_month = 2200, 12
count = #page_pane.injected
press("l")
year, month = month_of(w)
check("limite : pas au-delà de l'année 2200", #page_pane.injected == count and year == 2200, true)
w.GLOBAL.logtime_page_year, w.GLOBAL.logtime_page_month = 1970, 1
press("h")
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
check("redimensionnement : à la nouvelle hauteur (8 lignes)", select(2, drawn:gsub("\r\n", "")), 7)
check("redimensionnement : deux redessins différés (0,3 s et 1 s)", #w.timers == 2 and w.timers[1].seconds == 0.3 and w.timers[2].seconds == 1.0, true)
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
check("keys : ses touches sont ajoutées à la suite des tiennes", #config.keys == 2 and config.keys[1] == existing and config.keys[2].key == "F2", true)
check("keys : la table de touches de la page existe, avec 8 touches", #config.key_tables.logtime_page, 8)
check("keys : un gestionnaire de redimensionnement est installé", w.events["window-resized"] ~= nil and #w.events["window-resized"], 1)
check("keys : aucune erreur de configuration", #w.logs.error, 0)
win = new_window(w)
config.keys[2].action.fn(win, w.new_pane())
check("keys : F2 ouvre la page", #w.spawned, 1)
local bare = keys.apply({}, w, { page = page, open_key = "F2", table_name = "t" })
check("keys : une configuration sans touches ni tables est complétée", #bare.keys == 1 and bare.key_tables.t ~= nil, true)
check("keys : touche personnalisée", keys.apply({}, w, { page = page, open_key = "F5", table_name = "t" }).keys[1].key, "F5")

w = new_wezterm()
page = new_page(w)
config = { keys = { { key = "F2", action = "autre chose" } } }
keys.apply(config, w, { page = page, open_key = "F2", table_name = "logtime_page" })
check("keys : touche déjà utilisée : prévenu dans les journaux", #w.logs.error == 1 and w.logs.error[1]:find("F2", 1, true) ~= nil, true)
w = new_wezterm()
page = new_page(w)
keys.apply({ keys = { { key = "F2", mods = "SHIFT", action = "autre chose" } } }, w, { page = page, open_key = "F2", table_name = "logtime_page" })
check("keys : F2 avec SHIFT n'est pas la même touche : pas d'alerte", #w.logs.error, 0)

w = new_wezterm()
page = new_page(w)
config = keys.apply({}, w, { page = page, open_key = "F2", table_name = "logtime_page" })
win = new_window(w, { spawn_fails = true })
local ok_press = pcall(config.keys[1].action.fn, win, w.new_pane())
check("F2 qui échoue : pas de plantage", ok_press, true)
check("F2 qui échoue : erreur journalisée", #w.logs.error, 1)
check("F2 qui échoue : notification affichée", #win.toasts, 1)
check("F2 qui échoue : le message nomme l'ouverture", win.toasts[1].message:find("ouverture", 1, true) ~= nil, true)

-- en anglais
w = new_wezterm()
page = new_page(w, { labels = function() return en end })
page.open(new_window(w), w.new_pane())
check("anglais : la page est en anglais", strip(w.spawned[1].pane.injected[1]):find("Logtime : October 2026", 1, true) ~= nil and strip(w.spawned[1].pane.injected[1]):find("q: close", 1, true) ~= nil, true)
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
