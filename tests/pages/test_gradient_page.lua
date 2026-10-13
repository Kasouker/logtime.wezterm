-- tests/pages/test_gradient_page.lua : teste que la page utilise le dégradé de couleurs par défaut (sauf si gradient = false,
-- qui rend les quatre niveaux), avec ses réglages et sa légende. Fausse API WezTerm.
-- Lancer :   lua5.4 tests/pages/test_gradient_page.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]pages[/\\]test_gradient_page%.lua$") or "."

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
local calendar_page = load_module("pages/calendar_page")
local gradient = load_module("color/gradient")
local convert = load_module("color/convert")
local platform = load_module("system/platform")
local fr = load_module("i18n/fr")

local passed, failed = 0, 0
local function check(name, got, want)
	if got == want then
		passed = passed + 1
	else
		failed = failed + 1
		print(string.format("ÉCHEC  %s\n         attendu : %s\n         obtenu  : %s", name, tostring(want), tostring(got)))
	end
end

local function new_state()
	local w = { events = {}, logs = { error = {}, info = {} }, panes = {}, spawned = {}, GLOBAL = {} }
	w.log_error = function(m) w.logs.error[#w.logs.error + 1] = m end
	w.log_info = function(m) w.logs.info[#w.logs.info + 1] = m end
	w.action = {
		EmitEvent = function(name) return { kind = "EmitEvent", name = name } end,
		ActivateKeyTable = function(t) return { kind = "ActivateKeyTable", args = t } end,
		SendKey = function(t) return { kind = "SendKey", args = t } end,
		CloseCurrentTab = function(t) return { kind = "CloseCurrentTab", args = t } end,
		PopKeyTable = { kind = "PopKeyTable" },
	}
	w.on = function(event, handler)
		w.events[event] = w.events[event] or {}
		table.insert(w.events[event], handler)
	end
	w.time = { call_after = function() end }
	w.mux = { get_pane = function(id)
		local pane = w.panes[id]
		if not pane then
			error("pane id " .. tostring(id) .. " not found in mux")
		end
		return pane
	end }
	w.next_id = 150
	function w.new_pane(cols, rows)
		w.next_id = w.next_id + 1
		local tab = {}
		function tab:activate() end
		local pane = { id = w.next_id, injected = {}, dims = { viewport_rows = rows or 40, cols = cols or 120 }, the_tab = tab }
		function pane:pane_id() return self.id end
		function pane:get_dimensions() return self.dims end
		function pane:inject_output(text) self.injected[#self.injected + 1] = text end
		function pane:tab() return self.the_tab end
		w.panes[pane.id] = pane
		return pane
	end
	return w
end
local function new_window(w, cols, rows)
	local win = { performed = {} }
	function win:perform_action(action, pane) self.performed[#self.performed + 1] = action.kind end
	function win:toast_notification() end
	function win:mux_window()
		return { spawn_tab = function(_, spec)
			local pane = w.new_pane(cols, rows)
			w.spawned[#w.spawned + 1] = pane
			return pane.the_tab, pane, nil
		end }
	end
	return win
end
local DAYS = { ["2026-10-10"] = 15231, ["2026-10-12"] = 3600, ["2026-09-14"] = 7200, ["2026-08-03"] = 3600, ["2026-07-21"] = 20000 }
local function new_page(cfg)
	local w = new_state()
	local settings = { week_starts_on = "monday", day_offset = 0 }
	for k, v in pairs(cfg or {}) do
		settings[k] = v
	end
	return calendar_page.create({
wezterm = w, G = w.GLOBAL, num = function(v) return v end,
days = function() return DAYS end,
		today_key = function() return "2026-10-13" end,
		cfg = function() return settings end,
		labels = function() return fr end,
		blocker_args = function() return platform.blocker_args("windows") end,
	}), w
end
local function strip(text)
	return (text:gsub("\27%[[%?%d;]*%a", ""))
end
local function lines_of(text)
	local out = {}
	for line in (text .. "\n"):gmatch("(.-)\n") do
		out[#out + 1] = line
	end
	return out
end
local function count(text, needle)
	return select(2, text:gsub(needle:gsub("%p", "%%%0"), ""))
end
local HEAT3 = convert.bg("#8C7A4A") -- le fond du niveau « 3 à 6 h » des quatre niveaux, pour 4h13

-- ============================================================
-- par défaut : le dégradé
-- ============================================================
local made = gradient.make({})
local page = new_page({})
local raw, n = page.build_text({ cols = 120, rows = 40 })
check("par défaut : un seul mois dans cette fenêtre", n, 1)
check("par défaut : le fond du 10 octobre (4h13) vient du dégradé", raw:find(convert.bg(made.color(15231)), 1, true) ~= nil, true)
check("par défaut : le fond du 12 octobre (1h00) vient du dégradé", raw:find(convert.bg(made.color(3600)), 1, true) ~= nil, true)
check("par défaut : les anciens niveaux ne sont plus utilisés", raw:find(HEAT3, 1, true) == nil, true)
local text_lines = lines_of(strip(raw))
local legend = text_lines[#text_lines]
check("par défaut : la légende est la barre du dégradé", legend:sub(1, 5), "  0h ")
check("par défaut : la légende finit par l'étoile", legend:sub(-15), "* = aujourd'hui")
check("par défaut : la légende va jusqu'à 24h", legend:find(" 24h", 1, true) ~= nil, true)
check("par défaut : l'ancienne légende (<1h) a disparu", legend:find("<1h", 1, true), nil)
check("par défaut : exactement 4 fonds de couleur (2 jours avec du temps, 2 lignes chacun) : rien pour les jours à zéro", count(raw, "\27[48;2;"), 4)
check("par défaut : la légende utilise des couleurs de texte, pas de fond", count(raw, "\27[38;2;") > 0, true)
page = new_page({ gradient = true })
check("gradient = true : identique au réglage par défaut", page.build_text({ cols = 120, rows = 40 }), raw)
page = new_page({ gradient = nil })
check("gradient = nil : identique au réglage par défaut", page.build_text({ cols = 120, rows = 40 }), raw)

-- gradient = false : les quatre niveaux, comme avant le dégradé
page = new_page({ gradient = false })
local levels = page.build_text({ cols = 120, rows = 40 })
check("gradient = false : les quatre niveaux (le fond du niveau 3 est là)", levels:find(HEAT3, 1, true) ~= nil, true)
check("gradient = false : la légende des quatre niveaux", strip(levels):find("<1h", 1, true) ~= nil, true)
check("gradient = false : aucun fond du dégradé", levels:find(convert.bg(made.color(15231)), 1, true) == nil, true)
check("gradient = false : plus de barre 0h à 24h", strip(levels):find("0h ", 1, true) == nil, true)
check("gradient = false : exactement 4 fonds de couleur, comme le dégradé", count(levels, "\27[48;2;"), 4)

-- ============================================================
-- les réglages du dégradé, sur un mois
-- ============================================================
-- les réglages
page = new_page({ gradient = true, gradient_color = "#3366CC" })
raw = page.build_text({ cols = 120, rows = 40 })
local blue = gradient.make({ color = "#3366CC" })
check("gradient_color : les fonds sont de la teinte choisie", raw:find(convert.bg(blue.color(15231)), 1, true) ~= nil and raw:find(convert.bg(made.color(15231)), 1, true) == nil, true)
page = new_page({ gradient = true, gradient_hours = 8 })
raw = page.build_text({ cols = 120, rows = 40 })
check("gradient_hours = 8 : la légende va jusqu'à 8h", strip(raw):find(" 8h", 1, true) ~= nil and strip(raw):find(" 24h", 1, true) == nil, true)
check("gradient_hours = 8 : les fonds suivent", raw:find(convert.bg(gradient.make({ max_hours = 8 }).color(15231)), 1, true) ~= nil, true)
page = new_page({ gradient = true, gradient_light = 0.95, gradient_dark = 0.05 })
raw = page.build_text({ cols = 120, rows = 40 })
check("gradient_light et gradient_dark : pris en compte", raw:find(convert.bg(gradient.make({ light = 0.95, dark = 0.05 }).color(15231)), 1, true) ~= nil, true)
page = new_page({ gradient = true, gradient_curve = 1 })
raw = page.build_text({ cols = 120, rows = 40 })
check("gradient_curve = 1 : pris en compte", raw:find(convert.bg(gradient.make({ curve = 1 }).color(15231)), 1, true) ~= nil, true)
page = new_page({ gradient = true, gradient_color = "pas une couleur" })
raw = page.build_text({ cols = 120, rows = 40 })
check("gradient_color invalide : retour à l'or par défaut, sans plantage", raw:find(convert.bg(made.color(15231)), 1, true) ~= nil, true)

-- un cell_color donné explicitement est prioritaire
local calls = 0
page = new_page({ gradient = true, cell_color = function(secs) calls = calls + 1; return secs > 0 and "#112233" or nil end })
raw = page.build_text({ cols = 120, rows = 40 })
check("cell_color explicite : il est utilisé", calls > 0 and raw:find(convert.bg("#112233"), 1, true) ~= nil, true)
check("cell_color explicite : le dégradé n'est pas utilisé", raw:find(convert.bg(made.color(15231)), 1, true) == nil, true)
text_lines = lines_of(strip(raw))
check("cell_color explicite : légende réduite à l'étoile (pas de barre du dégradé)", text_lines[#text_lines], "  * = aujourd'hui")
calls = 0
page = new_page({ cell_color = function(secs) calls = calls + 1; return secs > 0 and "#112233" or nil end })
raw = page.build_text({ cols = 120, rows = 40 })
check("cell_color explicite, sans réglage gradient : il est prioritaire sur le dégradé par défaut", calls > 0 and raw:find(convert.bg("#112233"), 1, true) ~= nil and raw:find(convert.bg(made.color(15231)), 1, true) == nil, true)

-- ============================================================
-- gradient = true : plusieurs mois et dessin complet
-- ============================================================
page = new_page({ gradient = true })
raw, n = page.build_text({ cols = 140, rows = 60 })
check("dégradé, plusieurs mois : quatre mois", n, 4)
check("dégradé, plusieurs mois : les fonds viennent du dégradé (4h13 en octobre)", raw:find(convert.bg(made.color(15231)), 1, true) ~= nil, true)
check("dégradé, plusieurs mois : le 21 juillet (5h33) aussi", raw:find(convert.bg(made.color(20000)), 1, true) ~= nil, true)
check("dégradé, plusieurs mois : aucun ancien niveau", raw:find(HEAT3, 1, true) == nil, true)
text_lines = lines_of(strip(raw))
check("dégradé, plusieurs mois : la barre du dégradé est la dernière ligne", text_lines[#text_lines]:sub(1, 5) == "  0h " and text_lines[#text_lines]:sub(-15) == "* = aujourd'hui", true)

local w
page, w = new_page({})
local win = new_window(w, 120, 40)
page.open(win, w.new_pane())
local frame = w.spawned[1].injected[#w.spawned[1].injected]
check("page ouverte par défaut : le dessin envoyé à l'onglet utilise le dégradé", frame:find(convert.bg(made.color(15231)), 1, true) ~= nil, true)
check("page ouverte : aucune erreur", #w.logs.error, 0)
page, w = new_page({ gradient = false })
win = new_window(w, 120, 40)
page.open(win, w.new_pane())
frame = w.spawned[1].injected[#w.spawned[1].injected]
check("page ouverte avec gradient = false : les quatre niveaux", frame:find(HEAT3, 1, true) ~= nil and frame:find(convert.bg(made.color(15231)), 1, true) == nil, true)

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
