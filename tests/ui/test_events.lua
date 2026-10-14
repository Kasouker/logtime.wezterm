-- tests/ui/test_events.lua : teste que les touches de la page et F2 passent par des événements à NOM FIXE, et qu'elles
-- survivent à une nouvelle évaluation de la config (WezTerm reconstruit l'état Lua de zéro à chaque évaluation).
-- Lancer :   lua5.4 tests/ui/test_events.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]ui[/\\]test_events%.lua$") or "."

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
local keytable = load_module("ui/keytable")
local keys = load_module("config/keys")
local calendar_page = load_module("pages/calendar_page")
local platform = load_module("system/platform")
local fr = load_module("i18n/fr")

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

-- Comme WezTerm : action_callback fabrique un identifiant UNIQUE (un compteur qui ne repart pas de zéro d'une évaluation
-- à l'autre), enregistre la fonction sous ce nom, et renvoie l'action qui l'émet.
local unique_ids = 0
local function new_state()
	local w = { events = {}, logs = { error = {} }, panes = {}, spawned = {}, GLOBAL = {} }
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
	w.on = function(event, handler)
		w.events[event] = w.events[event] or {}
		table.insert(w.events[event], handler)
	end
	w.action_callback = function(fn)
		unique_ids = unique_ids + 1
		local name = "user-defined-" .. unique_ids
		w.on(name, fn)
		return w.action.EmitEvent(name)
	end
	w.time = { call_after = function() end }
	w.mux = {
		get_pane = function(id)
			local pane = w.panes[id]
			if not pane then
				error("pane id " .. tostring(id) .. " not found in mux")
			end
			return pane
		end,
	}
	w.next_id = 70
	function w.new_pane()
		w.next_id = w.next_id + 1
		local tab = {}
		function tab:activate() end
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
	local win = { performed = {} }
	function win:perform_action(action, pane)
		self.performed[#self.performed + 1] = action.kind
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
-- Comme WezTerm : émettre un événement dans l'ÉTAT COURANT appelle ses gestionnaires, jusqu'à ce que l'un renvoie false.
-- Renvoie le nombre de gestionnaires appelés.
local function emit(state, action, window, pane)
	local called = 0
	for _, handler in ipairs(state.events[action.name] or {}) do
		called = called + 1
		if handler(window, pane) == false then
			break
		end
	end
	return called
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
local function action_of(list, key)
	for _, b in ipairs(list) do
		if b.key == key then
			return b.action
		end
	end
end

-- ============================================================
-- noms fixes
-- ============================================================
local w1 = new_state()
local ran = {}
local table1 = keytable.build(
	w1,
	{ {
		key = "h",
		run = function()
			ran[#ran + 1] = "h"
		end,
	}, { key = "LeftArrow", run = function() end } },
	function()
		return true
	end,
	"logtime-page"
)
check("touche : action de type EmitEvent", table1[1].action.kind, "EmitEvent")
check("touche : nom d'événement fixe (préfixe + touche)", table1[1].action.name, "logtime-page-h")
check("touche : nom pour une flèche", table1[2].action.name, "logtime-page-LeftArrow")
check("touche : aucune fonction dans l'action elle-même", table1[1].action.fn, nil)
check("touche : un gestionnaire enregistré par touche", #w1.events["logtime-page-h"], 1)
check(
	"touche : préfixe par défaut",
	keytable.build(new_state(), { { key = "q", run = function() end } }, function()
		return true
	end)[1].action.name,
	"logtime-page-q"
)
local win1 = new_window(w1)
local pane1 = w1.new_pane()
check(
	"touche : émettre l'événement exécute l'action",
	emit(w1, table1[1].action, win1, pane1) == 1 and ran[1] == "h",
	true
)
check(
	"touche : le gestionnaire renvoie false (le suivant n'est pas appelé)",
	w1.events["logtime-page-h"][1](win1, pane1),
	false
)

-- la même config appliquée deux fois : chaque touche n'agit qu'une fois
local twice = new_state()
local hits = 0
local function build_again()
	return keytable.build(twice, { {
		key = "h",
		run = function()
			hits = hits + 1
		end,
	} }, function()
		return true
	end, "logtime-page")
end
local first_table = build_again()
build_again()
check("deux applications : deux gestionnaires enregistrés", #twice.events["logtime-page-h"], 2)
local called = emit(twice, first_table[1].action, new_window(twice), twice.new_pane())
check("deux applications : un seul est appelé", called, 1)
check("deux applications : l'action n'agit qu'une fois", hits, 1)

-- ============================================================
-- F2
-- ============================================================
local state = new_state()
local page = new_page(state)
local config = keys.apply({}, state, { page = page, open_key = "F2", table_name = "logtime_page" })
check("F2 : action de type EmitEvent", config.keys[1].action.kind, "EmitEvent")
check("F2 : nom d'événement fixe", config.keys[1].action.name, "logtime-open")
check(
	"F2 : l'événement émis ouvre la page",
	emit(state, config.keys[1].action, new_window(state), state.new_pane()) == 1 and #state.spawned == 1,
	true
)
local state_b = new_state()
local page_b = new_page(state_b)
keys.apply({}, state_b, { page = page_b, open_key = "F2", table_name = "logtime_page" })
keys.apply({}, state_b, { page = page_b, open_key = "F2", table_name = "logtime_page" })
emit(state_b, config.keys[1].action, new_window(state_b), state_b.new_pane())
check("F2 appliquée deux fois : la page ne s'ouvre qu'une fois", #state_b.spawned, 1)

-- ============================================================
-- le scénario réel : WezTerm réévalue la config et répond depuis le NOUVEL état Lua
-- ============================================================
-- (1) avec action_callback et des identifiants générés : l'événement n'a plus de gestionnaire. C'est le défaut observé.
local old_eval, new_eval = new_state(), new_state()
local old_config_action = old_eval.action_callback(function() end)
new_eval.action_callback(function() end) -- la nouvelle évaluation enregistre SA fonction sous un AUTRE identifiant
check(
	"action_callback : l'identifiant de l'ancienne évaluation est inconnu du nouvel état",
	new_eval.events[old_config_action.name],
	nil
)
check(
	"action_callback : émettre l'ancienne action dans le nouvel état n'appelle personne (silence total)",
	emit(new_eval, old_config_action, nil, nil),
	0
)

-- (2) avec des noms fixes : le nouvel état retrouve ses gestionnaires
local eval1 = new_state()
local page1 = new_page(eval1)
local config1 = keys.apply({}, eval1, { page = page1, open_key = "F2", table_name = "logtime_page" })
local eval2 = new_state()
eval2.GLOBAL = eval1.GLOBAL -- wezterm.GLOBAL survit aux réévaluations
local page2 = new_page(eval2)
keys.apply({}, eval2, { page = page2, open_key = "F2", table_name = "logtime_page" })
-- la config utilisée par WezTerm est celle de l'évaluation 1, mais les événements sont traités par l'état de l'évaluation 2
local opened = emit(eval2, config1.keys[1].action, new_window(eval2), eval2.new_pane())
check("noms fixes : F2 de l'ancienne config appelle bien le gestionnaire du nouvel état", opened, 1)
check("noms fixes : la page est ouverte par le nouvel état", #eval2.spawned, 1)
local page_pane = eval2.spawned[1]
eval2.GLOBAL.logtime_page_pane = page_pane.id
local h_action = action_of(config1.key_tables.logtime_page, "h")
local n_before = #page_pane.injected
check(
	"noms fixes : « h » de l'ancienne config appelle le gestionnaire du nouvel état",
	emit(eval2, h_action, new_window(eval2), page_pane),
	1
)
check(
	"noms fixes : et le calendrier est redessiné (septembre)",
	#page_pane.injected == n_before + 1
		and page_pane.injected[#page_pane.injected]:find("Septembre 2026", 1, true) ~= nil,
	true
)
local q_action = action_of(config1.key_tables.logtime_page, "q")
local closer = new_window(eval2)
emit(eval2, q_action, closer, page_pane)
check(
	"noms fixes : « q » de l'ancienne config ferme la page (touches retirées, onglet fermé)",
	table.concat(closer.performed, ","),
	"PopKeyTable,CloseCurrentTab"
)

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
