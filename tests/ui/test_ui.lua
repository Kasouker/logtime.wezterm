-- tests/ui/test_ui.lua : teste ui/safe.lua, ui/screen.lua, ui/keytable.lua et ui/resize.lua avec une fausse API WezTerm.
-- Lancer :   lua5.4 tests/ui/test_ui.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]ui[/\\]test_ui%.lua$") or "."

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

local cache = {}
local function load_module(name)
	if not cache[name] then
		local chunk = assert(loadfile(root .. "/plugin/logtime/" .. name .. ".lua"))
		cache[name] = chunk(load_module)
	end
	return cache[name]
end
local safe = load_module("ui/safe")
local screen = load_module("ui/screen")
local keytable = load_module("ui/keytable")
local resize = load_module("ui/resize")

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
local function check(name, got, want)
	if got == want then
		passed = passed + 1
	else
		failed = failed + 1
		print(string.format("ÉCHEC  %s\n         attendu : %s\n         obtenu  : %s", name, tostring(want), tostring(got)))
	end
end

-- ---- une fausse API WezTerm qui se comporte comme la vraie
local function new_wezterm()
	local w = { logs = { error = {} }, events = {}, timers = {}, panes = {} }
	current_w = w
	w.log_error = function(m)
		w.logs.error[#w.logs.error + 1] = m
	end
	w.action = {
		EmitEvent = function(name) return { kind = "EmitEvent", name = name } end,
		ActivateKeyTable = function(t) return { kind = "ActivateKeyTable", args = t } end,
		SendKey = function(t) return { kind = "SendKey", args = t } end,
		PopKeyTable = { kind = "PopKeyTable" },
	}
	w.action_callback = function(fn)
		return { kind = "callback", fn = fn }
	end
	w.on = function(event, handler)
		w.events[event] = w.events[event] or {}
		table.insert(w.events[event], handler)
	end
	w.time = { call_after = function(seconds, fn) w.timers[#w.timers + 1] = { seconds = seconds, fn = fn } end }
	-- comme dans WezTerm : un panneau qui n'existe plus provoque une erreur, il ne renvoie pas nil
w.mux = { get_pane = function(id)
local pane = w.panes[id]
if not pane then
error("pane id " .. tostring(id) .. " not found in mux")
end
return pane
end }
w.next_id = 0
function w.new_pane(rows, cols)
w.next_id = w.next_id + 1
local pane = { id = w.next_id, injected = {}, dims = { viewport_rows = rows, cols = cols or 100 } }
function pane:pane_id() return self.id end
function pane:get_dimensions() return self.dims end
function pane:inject_output(text) self.injected[#self.injected + 1] = text end
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
local function new_window(opts)
opts = opts or {}
local win = { performed = {}, toasts = {} }
function win:perform_action(action, pane) self.performed[#self.performed + 1] = { action = action, pane = pane } end
if not opts.no_toast then
function win:toast_notification(title, message, url, timeout)
if opts.toast_raises then error("notification impossible") end
self.toasts[#self.toasts + 1] = { title = title, message = message, timeout = timeout }
end
end
return win
end
local function kinds(win)
local out = {}
for _, p in ipairs(win.performed) do out[#out + 1] = p.action.kind end
return table.concat(out, ",")
end

local START, CLEAR = "\27[?1049h\27[?25l\27[?7l", "\27[2J\27[H"

-- ============================================================
-- ui/safe.lua
-- ============================================================
local w = new_wezterm()
local win = new_window()
local got
local wrapped = safe.wrap(w, "essai", function(window, pane, extra)
got = { window, pane, extra }
end)
local result = wrapped(win, "pane", "extra")
check("safe : sans erreur, rien n'est journalisé", #w.logs.error, 0)
check("safe : sans erreur, aucune notification", #win.toasts, 0)
check("safe : les arguments sont transmis", got and got[1] == win and got[2] == "pane" and got[3] == "extra", true)
check("safe : ne renvoie rien", result, nil)

local failing = safe.wrap(w, "calendrier", function()
error("boum")
end)
failing(win, nil)
check("safe : une erreur est écrite dans les journaux", #w.logs.error, 1)
check("safe : le message nomme l'action et l'erreur", w.logs.error[1]:find("logtime (calendrier)", 1, true) ~= nil and w.logs.error[1]:find("boum", 1, true) ~= nil, true)
check("safe : une notification est affichée", #win.toasts, 1)
check("safe : titre de la notification", win.toasts[1].title, "logtime")
check("safe : la notification contient le message", win.toasts[1].message, w.logs.error[1])
check("safe : la notification dure 10 s", win.toasts[1].timeout, 10000)
local no_toast = new_window({ no_toast = true })
failing(no_toast, nil)
check("safe : fenêtre sans notification : pas de plantage, erreur journalisée", #w.logs.error, 2)
failing(new_window({ toast_raises = true }), nil)
check("safe : notification qui échoue : pas de plantage", #w.logs.error, 3)
failing(nil, nil)
check("safe : fenêtre absente : pas de plantage", #w.logs.error, 4)
safe.wrap(w, "x", function() error() end)(win, nil)
check("safe : erreur sans valeur : pas de plantage", #w.logs.error, 5)
safe.wrap(w, "x", function() error({ code = 1 }) end)(win, nil)
check("safe : erreur qui est une table : pas de plantage", #w.logs.error, 6)

-- ============================================================
-- ui/screen.lua : frame
-- ============================================================
check("frame : premier dessin, écran alternatif puis effacement", screen.frame("a", 24, true), START .. CLEAR .. "a")
check("frame : dessins suivants, seulement l'effacement", screen.frame("a", 24, false), CLEAR .. "a")
check("frame : lignes séparées par CRLF", screen.frame("a\nb\nc", 24), CLEAR .. "a\r\nb\r\nc")
check("frame : pas de CRLF final", screen.frame("a\nb", 24):sub(-1), "b")
check("frame : un retour final donne une ligne vide", screen.frame("a\n", 24), CLEAR .. "a\r\n")
check("frame : texte vide", screen.frame("", 24), CLEAR)
check("frame : exactement la hauteur de la fenêtre, rien n'est coupé", screen.frame("a\nb\nc", 3), CLEAR .. "a\r\nb\r\nc")
check("frame : trop de lignes, on coupe à la fin", screen.frame("1\n2\n3\n4\n5\n6", 3), CLEAR .. "1\r\n2\r\n3")
check("frame : le pied de page est gardé", screen.frame("1\n2\n3\n4\n5\n6", 4, false, 2), CLEAR .. "1\r\n2\r\n5\r\n6")
check("frame : pied de page plus grand que la fenêtre", screen.frame("1\n2\n3\n4", 2, false, 5), CLEAR .. "3\r\n4")
check("frame : hauteur absente = 24 lignes", select(2, screen.frame(string.rep("x\n", 30) .. "x"):gsub("\r\n", "")), 23)
check("frame : hauteur nulle = au moins une ligne", screen.frame("1\n2", 0), CLEAR .. "1")
check("frame : les couleurs et les accents sont conservés", screen.frame("\27[1mé·█\27[0m", 5), CLEAR .. "\27[1mé·█\27[0m")

-- ============================================================
-- ui/screen.lua : bind
-- ============================================================
w = new_wezterm()
local api = screen.bind(w)
local pane = w.new_pane(5)
check("find_pane : un panneau existant", api.find_pane(pane.id), pane)
check("find_pane : un panneau disparu renvoie nil, sans erreur", api.find_pane(999), nil)
check("find_pane : identifiant absent", api.find_pane(nil), nil)
check("find_pane : sans mux", screen.bind({}).find_pane(1), nil)

api.draw(pane, "1\n2\n3\n4\n5\n6\n7", true)
check("draw : coupé à la hauteur de la fenêtre (5 lignes)", pane.injected[1], START .. CLEAR .. "1\r\n2\r\n3\r\n4\r\n5")
api.draw(pane, "1\n2\n3\n4\n5\n6\n7", false, 1)
check("draw : pied de page gardé", pane.injected[2], CLEAR .. "1\r\n2\r\n3\r\n4\r\n7")
local tall = w.new_pane(nil)
api.draw(tall, string.rep("x\n", 40) .. "x", false)
check("draw : hauteur inconnue = 24 lignes", select(2, tall.injected[1]:gsub("\r\n", "")), 23)

local redrawn = {}
api.later(pane.id, { 0.4, 1.2 }, function(p) redrawn[#redrawn + 1] = p end)
check("later : un minuteur par délai", #w.timers, 2)
check("later : premier délai", w.timers[1].seconds, 0.4)
check("later : second délai", w.timers[2].seconds, 1.2)
check("later : rien n'est redessiné avant l'échéance", #redrawn, 0)
w.run_timers()
check("later : redessiné deux fois, avec le bon panneau", #redrawn == 2 and redrawn[1] == pane, true)
api.later(pane.id, { 0.1 }, function(p) redrawn[#redrawn + 1] = p end)
w.panes[pane.id] = nil
w.run_timers()
check("later : panneau disparu entre-temps : rien n'est redessiné, aucune erreur", #redrawn, 2)
local pane2 = w.new_pane(5)
api.later(pane2.id, { 0.1 }, function() error("redessin impossible") end)
local ok_run = pcall(w.run_timers)
check("later : une erreur de redessin ne plante pas", ok_run, true)
api.later(pane2.id, {}, function() end)
check("later : aucun délai, aucun minuteur", #w.timers, 0)
check("later : sans minuterie dans WezTerm, silencieux", pcall(screen.bind({ mux = w.mux }).later, 1, { 0.1 }, function() end), true)

-- ============================================================
-- ui/keytable.lua
-- ============================================================
w = new_wezterm()
local page_pane, other_pane = w.new_pane(10), w.new_pane(10)
local ran = {}
local table_ = keytable.build(w, {
{ key = "h", run = function(window, p) ran[#ran + 1] = "h" end },
{ key = "LeftArrow", run = function(window, p) ran[#ran + 1] = "gauche" end },
{ key = "q", run = function(window, p) ran[#ran + 1] = "q" end },
}, function(p) return p == page_pane end)
check("build : une entrée par touche", #table_, 3)
check("build : les touches, dans l'ordre", table_[1].key .. "," .. table_[2].key .. "," .. table_[3].key, "h,LeftArrow,q")
check("build : chaque action est un rappel WezTerm", table_[1].action.kind, "EmitEvent")

win = new_window()
fire(table_[2].action, win, page_pane)
check("build : dans la page, la touche exécute son action", table.concat(ran, ","), "gauche")
check("build : dans la page, aucune action WezTerm supplémentaire", #win.performed, 0)

for i, key in ipairs({ "h", "LeftArrow", "q" }) do
win = new_window()
local before = #ran
fire(table_[i].action, win, other_pane)
check("build : " .. key .. " ailleurs : touches retirées puis touche rendue", kinds(win), "PopKeyTable,SendKey")
check("build : " .. key .. " ailleurs : la bonne touche est rendue", win.performed[2].action.args.key, key)
check("build : " .. key .. " ailleurs : l'action de la page n'est pas exécutée", #ran, before)
end

w = new_wezterm()
local boom_pane = w.new_pane(10)
local boom = keytable.build(w, { { key = "x", run = function() error("touche cassée") end } }, function() return true end)
win = new_window()
fire(boom[1].action, win, boom_pane)
check("build : une erreur dans une touche est signalée (journaux)", #w.logs.error, 1)
check("build : une erreur dans une touche est signalée (notification)", #win.toasts, 1)
local picky = keytable.build(w, { { key = "x", run = function() end } }, function() error("is_page cassé") end)
fire(picky[1].action, new_window(), boom_pane)
check("build : une erreur dans is_page est signalée aussi", #w.logs.error, 2)

win = new_window()
keytable.activate(w, win, page_pane, "logtime_page")
check("activate : active la table, de façon durable", kinds(win) == "ActivateKeyTable" and win.performed[1].action.args.name == "logtime_page" and win.performed[1].action.args.one_shot == false, true)
check("activate : sur le bon panneau", win.performed[1].pane, page_pane)
win = new_window()
keytable.leave(w, win, page_pane)
check("leave : retire la table", kinds(win), "PopKeyTable")

-- ============================================================
-- ui/resize.lua
-- ============================================================
w = new_wezterm()
local calls = {}
resize.install(w, function(window, p) calls[#calls + 1] = { window, p } end)
check("resize : un gestionnaire window-resized", w.events["window-resized"] ~= nil and #w.events["window-resized"], 1)
win = new_window()
local rpane = w.new_pane(10)
w.events["window-resized"][1](win, rpane)
check("resize : l'action reçoit la fenêtre et le panneau", #calls == 1 and calls[1][1] == win and calls[1][2] == rpane, true)
w = new_wezterm()
resize.install(w, function() error("redessin cassé") end)
win = new_window()
w.events["window-resized"][1](win, nil)
check("resize : une erreur est signalée (journaux)", #w.logs.error, 1)
check("resize : une erreur est signalée (notification)", #win.toasts, 1)

-- ============================================================
-- effets de bord
-- ============================================================
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
