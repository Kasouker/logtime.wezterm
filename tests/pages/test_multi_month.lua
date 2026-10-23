-- tests/pages/test_multi_month.lua : teste que la page affiche un ou plusieurs mois selon la taille de la fenêtre, qu'elle
-- passe de l'un à l'autre quand la fenêtre change de taille, et que la navigation suit. Fausse API WezTerm.
-- Lancer :   lua5.4 tests/pages/test_multi_month.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]pages[/\\]test_multi_month%.lua$") or "."

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
load_module("ui/safe").debug = true -- ces tests lisent les traces du journal (éteintes par défaut)
local calendar_page = load_module("pages/calendar_page")
local layout = load_module("calendar/layout")
local platform = load_module("system/platform")
local fr = load_module("i18n/fr")
local en = load_module("i18n/en")

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
local function new_state()
	local w = { events = {}, logs = { error = {}, info = {} }, panes = {}, spawned = {}, GLOBAL = {} }
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
	w.next_id = 90
	function w.new_pane(cols, rows)
		w.next_id = w.next_id + 1
		local tab = {}
		function tab:activate() end
		local pane =
			{ id = w.next_id, injected = {}, dims = { viewport_rows = rows or 60, cols = cols or 140 }, the_tab = tab }
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
local function new_window(w, cols, rows)
	local win = { performed = {} }
	function win:perform_action(action, pane)
		self.performed[#self.performed + 1] = action.kind
	end
	function win:toast_notification() end
	function win:mux_window()
		return {
			spawn_tab = function(_, spec)
				local pane = w.new_pane(cols, rows)
				w.spawned[#w.spawned + 1] = pane
				return pane.the_tab, pane, nil
			end,
		}
	end
	return win
end
local function fire(w, action, window, pane)
	for _, handler in ipairs(w.events[action.name] or {}) do
		if handler(window, pane) == false then
			return
		end
	end
end
local DAYS = {
	["2026-10-10"] = 15231,
	["2026-10-12"] = 3600,
	["2026-09-14"] = 7200,
	["2026-08-03"] = 3600,
	["2026-07-21"] = 20000,
}
local function new_page(w, cfg, labels)
	local settings = { week_starts_on = "monday", day_offset = 0, gradient = false }
	for k, v in pairs(cfg or {}) do
		settings[k] = v
	end
	return calendar_page.create({
		wezterm = w,
		G = w.GLOBAL,
		num = function(v)
			return v
		end,
		days = function()
			return DAYS
		end,
		today_key = function()
			return "2026-10-13"
		end,
		cfg = function()
			return settings
		end,
		labels = function()
			return labels or fr
		end,
		blocker_args = function()
			return platform.blocker_args("windows")
		end,
	})
end
local function strip(text)
	return (text:gsub("\27%[[%?%d;]*%a", ""):gsub("\r", ""))
end
local function lines_of(text)
	local out = {}
	for line in (text .. "\n"):gmatch("(.-)\n") do
		out[#out + 1] = line
	end
	return out
end
local function position(text, needle)
	return (text:find(needle, 1, true))
end
local function line_of(text, needle)
	for i, line in ipairs(lines_of(text)) do
		if line:find(needle, 1, true) then
			return i
		end
	end
end
local function last_text(pane)
	return strip(pane.injected[#pane.injected])
end
local function binding(w, page, key)
	for _, b in ipairs(page.key_table()) do
		if b.key == key then
			return function(window, pane)
				fire(w, b.action, window, pane)
			end
		end
	end
end

-- ============================================================
-- combien de mois selon la taille
-- ============================================================
local w = new_state()
local page = new_page(w)
local text, count = page.build_text()
check("sans taille : un seul mois", count, 1)
check(
	"sans taille : le dessin habituel (titre du plugin devant le mois)",
	strip(text):find("Logtime : Octobre 2026", 1, true) ~= nil,
	true
)
text, count = page.build_text({ cols = 120, rows = 40 })
check("120 x 40 : un seul mois", count, 1)
check("120 x 40 : avec ses statistiques détaillées", strip(text):find("Moyenne par jour actif", 1, true) ~= nil, true)
text, count = page.build_text({ cols = 140, rows = 60 })
text = strip(text)
check("140 x 60 : quatre mois", count, 4)
check(
	"140 x 60 : les quatre titres sont là",
	position(text, "Juillet 2026") ~= nil
		and position(text, "Août 2026") ~= nil
		and position(text, "Septembre 2026") ~= nil
		and position(text, "Octobre 2026") ~= nil,
	true
)
check(
	"140 x 60 : du plus ancien au plus récent",
	position(text, "Juillet 2026") < position(text, "Août 2026")
		and position(text, "Août 2026") < position(text, "Septembre 2026")
		and position(text, "Septembre 2026") < position(text, "Octobre 2026"),
	true
)
check(
	"140 x 60 : Juillet et Août sont côte à côte (même ligne)",
	line_of(text, "Juillet 2026") == line_of(text, "Août 2026"),
	true
)
check(
	"140 x 60 : Septembre et Octobre sont côte à côte, sous les deux premiers",
	line_of(text, "Septembre 2026") == line_of(text, "Octobre 2026")
		and line_of(text, "Septembre 2026") > line_of(text, "Juillet 2026"),
	true
)
check(
	"140 x 60 : en haut, l'aide dans son cadre (« Logtime : » devant)",
	lines_of(text)[1]:sub(1, #"╭")
		.. " "
		.. tostring(lines_of(text)[2]:match("^│ Logtime : vue d'ensemble : Entrée │") ~= nil),
	"╭ true"
)
check(
	"140 x 60 : le titre du plugin n'est pas répété devant chaque mois (une seule fois, dans l'aide)",
	select(2, text:gsub("Logtime : ", "")),
	1
)
check(
	"140 x 60 : la légende des couleurs est à la fin, sans cadre ni étoile",
	lines_of(text)[#lines_of(text)],
	"  ██ <1h   ██ 1-3h   ██ 3-6h   ██ 6h+"
)
check("140 x 60 : les heures du 10 octobre (4h13) sont affichées", position(text, "4h13") ~= nil, true)
check("140 x 60 : celles du 14 septembre (2h00) aussi", position(text, "2h00") ~= nil, true)
check("140 x 60 : et celles du 21 juillet (5h33)", position(text, "5h33") ~= nil, true)
check("140 x 60 : une seule étoile (aujourd'hui, le 13 octobre)", select(2, text:gsub("%*13", "")), 1)
local _, raw_count = page.build_text({ cols = 140, rows = 60 })
local raw = page.build_text({ cols = 140, rows = 60 })
check("le mois choisi a son titre en gras", raw:find("\27[1m  Octobre 2026", 1, true) ~= nil, true)
check(
	"les autres mois n'ont pas leur titre en gras",
	raw:find("\27[1m  Septembre 2026", 1, true) == nil and raw:find("\27[1m  Juillet 2026", 1, true) == nil,
	true
)

text, count = page.build_text({ cols = 140, rows = 30 })
check("140 x 30 (une seule rangée tient) : deux mois côte à côte", count, 2)
text, count = page.build_text({ cols = 140, rows = 26 })
check("140 x 26 (trop bas pour un mois entier, l'aide et la légende) : un seul mois", count, 1)
text, count = page.build_text({ cols = 263, rows = 21 })
check(
	"263 x 21 (très large, trop bas) : le message « fenêtre trop petite » (0 mois), jamais des mois coupés",
	count == 0 and text:find("Fenêtre trop petite", 1, true) ~= nil,
	true
)
text, count = page.build_text({ cols = 60, rows = 100 })
check(
	"60 x 100 (trop étroit) : le message « fenêtre trop petite » (0 mois)",
	count == 0 and text:find("Fenêtre trop petite", 1, true) ~= nil,
	true
)
text, count = page.build_text({ cols = 100, rows = 100 })
text = strip(text)
check("100 x 100 : quatre mois empilés", count, 4)
check(
	"100 x 100 : un mois par rangée",
	line_of(text, "Juillet 2026") ~= line_of(text, "Août 2026")
		and line_of(text, "Août 2026") ~= line_of(text, "Septembre 2026"),
	true
)
text, count = page.build_text({ cols = 400, rows = 27 })
text = strip(text)
check(
	"400 x 27 : cinq mois côte à côte sur une seule rangée",
	count == 5 and line_of(text, "Juillet 2026") == line_of(text, "Octobre 2026"),
	true
)

-- jamais plus large ni plus haut que la fenêtre
local fits = true
for _, size in ipairs({ { 133, 47 }, { 140, 60 }, { 200, 60 }, { 100, 100 }, { 400, 25 }, { 201, 47 }, { 133, 25 } }) do
	local shown = strip((page.build_text({ cols = size[1], rows = size[2] })))
	local all = lines_of(shown)
	if #all > size[2] then
		fits = false
	end
	for _, line in ipairs(all) do
		if utf8.len(line) > size[1] then
			fits = false
		end
	end
end
check("7 tailles de fenêtre : le dessin ne dépasse jamais la fenêtre (ni en largeur, ni en hauteur)", fits, true)

-- les réglages
local limited = new_page(w, { max_months = 2 })
text, count = limited.build_text({ cols = 400, rows = 100 })
check("max_months = 2 : deux mois même dans une immense fenêtre", count, 2)
text = strip(text)
check(
	"max_months = 2 : Septembre et Octobre",
	position(text, "Septembre 2026") ~= nil
		and position(text, "Octobre 2026") ~= nil
		and position(text, "Août 2026") == nil,
	true
)
text, count = new_page(w, { max_months = 1 }).build_text({ cols = 400, rows = 100 })
check(
	"max_months = 1 : un seul mois, avec le dessin habituel",
	count == 1 and strip(text):find("Logtime : Octobre 2026", 1, true) ~= nil,
	true
)
text, count = new_page(w, { max_months = 2, months_anchor = "first" }).build_text({ cols = 400, rows = 100 })
text = strip(text)
check(
	"months_anchor = first : Octobre puis Novembre",
	count == 2
		and position(text, "Octobre 2026") < position(text, "Novembre 2026")
		and position(text, "Septembre 2026") == nil,
	true
)
text, count = new_page(w, { week_starts_on = "sunday" }).build_text({ cols = 140, rows = 60 })
check("semaine du dimanche : l'en-tête commence par Dim", strip(text):match("Dim%s+Lun") ~= nil, true)
text, count = new_page(w, {}, en).build_text({ cols = 140, rows = 60 })
text = strip(text)
check(
	"anglais : mois et légende en anglais",
	position(text, "July 2026") ~= nil
		and position(text, "October 2026") ~= nil
		and text:find("* = Today", 1, true) ~= nil,
	true
)
text, count = new_page(w, { goal_hours = 3 }).build_text({ cols = 140, rows = 60 })
check("objectif : 140 colonnes, 4 mois comme sans objectif (les mois gardent 65 colonnes)", count, 4)
check(
	"objectif : chaque mois a sa ligne « Semaines validées »",
	select(2, strip(text):gsub("Semaines validées", "")),
	4
)
local goal_width
text, count, goal_width = new_page(w, { goal_hours = 3 }).build_text({ cols = 140, rows = 60 })
check("objectif : la largeur à centrer est 2 x 65 + 3 = 133", goal_width, 133)
text, count = new_page(w, { goal_hours = 0 }).build_text({ cols = 140, rows = 60 })
check(
	"objectif « aucun » (0) : pas de ligne « validées »",
	count == 4 and strip(text):find("validées", 1, true) == nil,
	true
)
-- les encadrés : un mois fait 65 x 20 (pas plus grand que sans encadrés : autant de mois à l'écran)
text, count = new_page(w, { borders = true }).build_text({ cols = 133, rows = 60 })
check("encadrés : 133 colonnes = 65 + 3 + 65, 2 mois de large", count, 4)
text, count = new_page(w, { borders = true }).build_text({ cols = 132, rows = 60 })
check("encadrés : 132 colonnes, une de trop peu : 1 mois de large", count, 2)
text, count = new_page(w, { borders = true }).build_text({ cols = 133, rows = 47 })
check("encadrés : 47 lignes = 6 + 20 + 1 + 20 : 2 rangées", count, 4)
text, count = new_page(w, { borders = true }).build_text({ cols = 133, rows = 46 })
check("encadrés : 46 lignes : une seule rangée", count, 2)
text, count = new_page(w, { borders = true }).build_text({ cols = 201, rows = 47 })
check("encadrés, plein écran 201 x 47 : 6 mois (3 x 2)", count, 6)
check(
	"sans encadrés, 201 x 47 : 3 mois seulement (les encadrés prennent moins de place)",
	select(2, new_page(w, {}).build_text({ cols = 201, rows = 47 })),
	3
)
local _, _, boxed_width = new_page(w, { borders = true }).build_text({ cols = 133, rows = 60 })
check("encadrés : la largeur à centrer est 65 + 3 + 65 = 133", boxed_width, 133)
text = new_page(w, { borders = true }).build_text({ cols = 133, rows = 60 })
local boxed_lines = lines_of(strip(text))
check(
	"encadrés : la légende de la page hors des cadres des mois, tout en bas",
	boxed_lines[#boxed_lines],
	"  ██ <1h   ██ 1-3h   ██ 3-6h   ██ 6h+"
)
check(
	"encadrés : l'aide de la page dans son propre cadre, aligné sur ceux des mois (une colonne de marge)",
	utf8.len(boxed_lines[1]) .. boxed_lines[1]:sub(1, #" ╭"),
	"133 ╭"
)

-- ============================================================
-- la page ouverte : navigation, redimensionnement (multiplier, diviser)
-- ============================================================
w = new_state()
page = new_page(w)
local win = new_window(w, 140, 60)
page.open(win, w.new_pane())
local pane = w.spawned[1]
check(
	"ouverture dans une grande fenêtre : quatre mois",
	position(last_text(pane), "Juillet 2026") ~= nil and position(last_text(pane), "Octobre 2026") ~= nil,
	true
)
check(
	"ouverture : le journal dit combien de mois sont dessinés",
	w.logs.info[#w.logs.info - 2]:find("(4 months)", 1, true) ~= nil
		or w.logs.info[#w.logs.info - 1]:find("(4 months)", 1, true) ~= nil,
	true
)
w.GLOBAL.logtime_page_pane = pane.id
binding(w, page, "PageUp")(win, pane)
local shown = last_text(pane)
check(
	"PgUp dans le calendrier de base : rien ne bouge (on se déplace dans la vue d'ensemble)",
	position(shown, "Juillet 2026") ~= nil and position(shown, "Octobre 2026") ~= nil,
	true
)
-- revenu de la vue d'ensemble en septembre : le calendrier de base montre le mois où l'on était
w.GLOBAL.logtime_page_year, w.GLOBAL.logtime_page_month = 2026, 9
binding(w, page, "r")(win, pane)
shown = last_text(pane)
check(
	"septembre (le mois où l'on était), quatre mois : Juin à Septembre",
	position(shown, "Juin 2026") ~= nil
		and position(shown, "Septembre 2026") ~= nil
		and position(shown, "Octobre 2026") == nil,
	true
)
binding(w, page, "t")(win, pane)
shown = last_text(pane)
check(
	"t : retour sur Juillet à Octobre",
	position(shown, "Juillet 2026") ~= nil
		and position(shown, "Octobre 2026") ~= nil
		and position(shown, "Juin 2026") == nil,
	true
)
w.GLOBAL.logtime_page_year, w.GLOBAL.logtime_page_month = 2026, 4
binding(w, page, "r")(win, pane)
shown = last_text(pane)
check("avril : Janvier à Avril", position(shown, "Janvier 2026") ~= nil and position(shown, "Avril 2026") ~= nil, true)
w.GLOBAL.logtime_page_year, w.GLOBAL.logtime_page_month = 2026, 1
binding(w, page, "r")(win, pane)
shown = last_text(pane)
check(
	"janvier : les mois d'avant sont ceux de l'année précédente",
	position(shown, "Octobre 2025") ~= nil and position(shown, "Janvier 2026") ~= nil,
	true
)

-- la fenêtre rétrécit : 4 mois -> 1 mois (diviser), puis grandit : 1 -> 4 (multiplier)
w = new_state()
page = new_page(w)
win = new_window(w, 140, 60)
page.open(win, w.new_pane())
pane = w.spawned[1]
w.GLOBAL.logtime_page_pane = pane.id
pane.dims.cols, pane.dims.viewport_rows = 120, 40
page.on_resize(win, pane)
shown = last_text(pane)
check(
	"la fenêtre rétrécit (120 x 40) : on revient à un seul mois",
	position(shown, "Logtime : Octobre 2026") ~= nil and position(shown, "Juillet 2026") == nil,
	true
)
check(
	"rétrécissement : le journal annonce 1 mois",
	w.logs.info[#w.logs.info]:find("(1 months)", 1, true) ~= nil,
	true
)
pane.dims.cols, pane.dims.viewport_rows = 200, 60
page.on_resize(win, pane)
shown = last_text(pane)
check(
	"la fenêtre grandit (200 x 60) : quatre mois",
	position(shown, "Juillet 2026") ~= nil and position(shown, "Octobre 2026") ~= nil,
	true
)
check("agrandissement : le journal annonce 4 mois", w.logs.info[#w.logs.info]:find("(4 months)", 1, true) ~= nil, true)
pane.dims.cols, pane.dims.viewport_rows = 200, 26
page.on_resize(win, pane)
shown = last_text(pane)
check(
	"la fenêtre devient trop basse (200 x 26) : un seul mois",
	position(shown, "Logtime : Octobre 2026") ~= nil,
	true
)
pane.dims.cols, pane.dims.viewport_rows = 120, 60
page.on_resize(win, pane)
shown = last_text(pane)
check(
	"120 x 60 : deux mois empilés (une seule colonne tient, deux rangées) : Septembre et Octobre",
	position(shown, "Septembre 2026") ~= nil
		and position(shown, "Octobre 2026") ~= nil
		and position(shown, "Juillet 2026") == nil
		and position(shown, "Août 2026") == nil,
	true
)
check("120 x 60 : l'un sous l'autre", line_of(shown, "Septembre 2026") ~= line_of(shown, "Octobre 2026"), true)
pane.dims.cols, pane.dims.viewport_rows = 140, 49
page.on_resize(win, pane)
check(
	"la fenêtre repasse à 140 x 49 : quatre mois à nouveau",
	position(last_text(pane), "Juillet 2026") ~= nil,
	true
)
local drawn = lines_of(last_text(pane))
check("140 x 49 : le dessin tient exactement dans la fenêtre", #drawn <= 49, true)
local info_before = #w.logs.info
w.events["window-resized"] = w.events["window-resized"] or {}
check("aucune erreur pendant tous ces changements de taille", #w.logs.error, 0)

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
