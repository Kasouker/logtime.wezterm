-- tests/ui/test_trace.lua : teste les traces laissées dans les journaux de WezTerm par les touches de la page
-- (ui/safe.lua, ui/keytable.lua, config/keys.lua, pages/calendar_page.lua). Lancer :   lua5.4 tests/ui/test_trace.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]ui[/\\]test_trace%.lua$") or "."

local globals_before = {}
for k in pairs(_G) do
	globals_before[k] = true
end

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
local safe = load_module("ui/safe")
local keytable = load_module("ui/keytable")
local keys = load_module("config/keys")
local calendar_page = load_module("pages/calendar_page")
local platform = load_module("system/platform")
local fr = load_module("i18n/fr")

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

local function new_wezterm(with_log_info)
	local w = { logs = { error = {}, info = {} }, events = {}, timers = {}, panes = {}, spawned = {}, GLOBAL = {} }
	current_w = w
	w.log_error = function(m)
		w.logs.error[#w.logs.error + 1] = m
	end
	if with_log_info ~= false then
		w.log_info = function(m)
			w.logs.info[#w.logs.info + 1] = m
		end
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
	w.next_id = 40
	function w.new_pane()
		w.next_id = w.next_id + 1
		local tab = { activated = false }
		function tab:activate()
			self.activated = true
		end
		local pane = { id = w.next_id, injected = {}, dims = { viewport_rows = 30, cols = 100 }, the_tab = tab }
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
	return w
end
local function new_window(w)
	local win = { performed = {}, toasts = {} }
	function win:perform_action(action, pane)
		self.performed[#self.performed + 1] = action.kind
	end
	function win:toast_notification(title, message)
		self.toasts[#self.toasts + 1] = message
	end
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
local function new_page(w)
	return calendar_page.create({
		wezterm = w,
		G = w.GLOBAL,
		num = function(v)
			return v
		end,
		days = function()
			return { ["2026-10-10"] = 15231 }
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
	})
end
local function find(list, text)
	local n = 0
	for _, line in ipairs(list) do
		if line:find(text, 1, true) then
			n = n + 1
		end
	end
	return n
end

-- ============================================================
-- ui/safe.lua
-- ============================================================
-- par défaut (debug = false) : aucune trace, mais les erreurs restent écrites et notifiées
check("debug : éteint par défaut", safe.debug, false)
local w = new_wezterm()
local win = new_window(w)
safe.wrap(w, "essai", function() end, true)(win, nil)
safe.trace(w, "message")
check("debug éteint : aucune trace dans les journaux", #w.logs.info, 0)
safe.wrap(w, "essai", function()
	error("boum")
end, true)(win, nil)
check("debug éteint : l'erreur est quand même écrite", #w.logs.error, 1)
check("debug éteint : et notifiée", #win.toasts, 1)
check("debug éteint : toujours aucune trace", #w.logs.info, 0)

safe.debug = true -- la suite vérifie les traces elles-mêmes
w = new_wezterm()
win = new_window(w)
safe.wrap(w, "essai", function() end, true)(win, nil)
check("trace : deux lignes pour un appel réussi", #w.logs.info, 2)
check("trace : d'abord « appelée »", w.logs.info[1], "logtime (essai) : appelée")
check("trace : puis « terminée »", w.logs.info[2], "logtime (essai) : terminée")
check("trace : aucune erreur", #w.logs.error, 0)

w = new_wezterm()
safe.wrap(w, "essai", function() end)(win, nil)
check("sans trace : rien dans les journaux", #w.logs.info, 0)
safe.wrap(w, "essai", function() end, false)(win, nil)
check("trace à false : rien non plus", #w.logs.info, 0)

w = new_wezterm()
win = new_window(w)
safe.wrap(w, "essai", function()
	error("boum")
end, true)(win, nil)
check("trace avec erreur : « appelée » est écrit", w.logs.info[1], "logtime (essai) : appelée")
check("trace avec erreur : pas de « terminée »", find(w.logs.info, "terminée"), 0)
check("trace avec erreur : l'erreur reste journalisée et notifiée", #w.logs.error == 1 and #win.toasts == 1, true)

w = new_wezterm(false)
local ok = pcall(safe.wrap(w, "essai", function() end, true), new_window(w), nil)
check("sans log_info dans WezTerm : aucun plantage", ok, true)
check("safe.trace sans log_info : silencieux", pcall(safe.trace, w, "message"), true)

-- ============================================================
-- ui/keytable.lua
-- ============================================================
w = new_wezterm()
local page_pane, other_pane = w.new_pane(), w.new_pane()
local table_ = keytable.build(
	w,
	{ { key = "h", run = function() end }, { key = "q", run = function() end } },
	function(p)
		return p == page_pane
	end
)
win = new_window(w)
fire(table_[1].action, win, page_pane)
check("touche dans la page : trois lignes (appelée, touche, terminée)", #w.logs.info, 3)
check(
	"touche dans la page : la touche, le panneau et « est la page »",
	w.logs.info[2],
	"logtime (page) : touche h, panneau " .. page_pane.id .. ", est la page : true"
)
check("touche dans la page : terminée", w.logs.info[3], "logtime (page) : terminée")
fire(table_[2].action, new_window(w), other_pane)
check(
	"touche ailleurs : « est la page : false » est noté",
	find(w.logs.info, "touche q, panneau " .. other_pane.id .. ", est la page : false"),
	1
)
check("touche ailleurs : aucune erreur", #w.logs.error, 0)

w = new_wezterm()
page_pane = w.new_pane()
win = new_window(w)
keytable.activate(w, win, page_pane, "logtime_page")
check("activation : tracée avec le nom de la table", find(w.logs.info, "logtime_page"), 1)
keytable.leave(w, win, page_pane)
check("retrait : tracé", find(w.logs.info, "retirées"), 1)

-- les journaux ne contiennent que le nom des touches de la page, jamais une autre frappe
w = new_wezterm()
page_pane = w.new_pane()
local only = keytable.build(w, { { key = "h", run = function() end } }, function()
	return true
end)
fire(only[1].action, new_window(w), page_pane)
local leaked_text = false
for _, line in ipairs(w.logs.info) do
	if line:find("mot de passe", 1, true) then
		leaked_text = true
	end
end
check("seuls les noms des touches de la page sont écrits", leaked_text, false)

-- ============================================================
-- config/keys.lua : F2
-- ============================================================
w = new_wezterm()
local page = new_page(w)
local config = keys.apply({}, w, { page = page, open_key = "F2", table_name = "logtime_page" })
win = new_window(w)
fire(config.keys[1].action, win, w.new_pane())
check(
	"F2 : « appelée » et « terminée » sont tracés",
	find(w.logs.info, "logtime (ouverture) : appelée") == 1
		and find(w.logs.info, "logtime (ouverture) : terminée") == 1,
	true
)
check(
	"F2 : la page ouverte est tracée avec son panneau",
	find(w.logs.info, "page ouverte dans le panneau " .. w.spawned[1].id),
	1
)
check(
	"F2 : le premier dessin est tracé (mois 2026-10)",
	find(w.logs.info, "dessin du mois 2026-10 dans le panneau " .. w.spawned[1].id) >= 1,
	true
)
check(
	"F2 : l'activation des touches est tracée",
	find(w.logs.info, "touches de la page « logtime_page » activées"),
	1
)

-- une touche de la page : traces d'appel puis de dessin
local before = #w.logs.info
local h = nil
for _, b in ipairs(config.key_tables.logtime_page) do
	if b.key == "PageUp" then
		h = function(window, pane)
			fire(b.action, window, pane)
		end
	end
end
w.GLOBAL.logtime_page_pane = w.spawned[1].id
h(new_window(w), w.spawned[1])
check("h dans la page : le nouveau mois est tracé (septembre)", find(w.logs.info, "dessin du mois 2026-09"), 1)
check("h dans la page : plusieurs lignes de trace en plus", #w.logs.info > before + 2, true)

-- le redimensionnement n'est PAS tracé (il se déclenche des dizaines de fois quand on tire sur la fenêtre)
local info_before = #w.logs.info
w.events["window-resized"][1](new_window(w), nil)
check("redimensionnement : aucune ligne « appelée » ou « terminée »", find(w.logs.info, "redimensionnement"), 0)

check(
	"aucune variable globale ajoutée",
	(function()
		local leaked = {}
		for k in pairs(_G) do
			if not globals_before[k] then
				leaked[#leaked + 1] = k
			end
		end
		return table.concat(leaked, ",")
	end)(),
	""
)

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
