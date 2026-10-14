-- tests/pages/test_center.lua : teste le centrage du calendrier dans la fenêtre (calendar/layout.lua : center, et le dessin
-- de la page). Fausse API WezTerm. Lancer :   lua5.4 tests/pages/test_center.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]pages[/\\]test_center%.lua$") or "."

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
local layout = load_module("calendar/layout")
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

-- ============================================================
-- layout.center : la fonction pure
-- ============================================================
local function sample(count, width)
	local lines = {}
	for i = 1, count do
		lines[i] = string.rep("x", width)
	end
	return lines
end
local function leading(line)
	return #line:match("^( *)")
end
local function empties(lines)
	local n = 0
	for _, line in ipairs(lines) do
		if line ~= "" then
			break
		end
		n = n + 1
	end
	return n
end

local out = layout.center(sample(30, 65), 65, 165, 50)
check("centrer : marge à gauche = (165 - 65) / 2", leading(out[#out]), 50)
check("centrer : marge en haut = (50 - 30) / 2 lignes vides", empties(out), 10)
check("centrer : le nombre de lignes = marge + contenu", #out, 40)
check("centrer : le contenu est conservé", out[#out]:sub(51), string.rep("x", 65))
out = layout.center(sample(3, 65), 65, 166, 50)
check("centrer : un écart impair est arrondi vers le bas (166 : 50)", leading(out[#out]), 50)
out = layout.center(sample(3, 65), 65, 165, 51)
check("centrer : en hauteur aussi (51 - 3 = 48 : 24)", empties(out), 24)
local right = 165 - 50 - 65
check("centrer : marges droite et gauche presque égales", math.abs(right - 50) <= 1, true)

out = layout.center({ "abc", "", "def" }, 3, 103, 3)
check("centrer : une ligne vide reste vide (pas d'espaces inutiles)", out[2], "")
check("centrer : les autres lignes sont décalées", out[1], string.rep(" ", 50) .. "abc")
out = layout.center(sample(5, 65), 65, 65, 5)
check("fenêtre juste de la taille du calendrier : aucune marge à gauche", leading(out[1]), 0)
check("fenêtre juste de la taille du calendrier : aucune marge en haut", empties(out), 0)
out = layout.center(sample(40, 65), 65, 50, 20)
check(
	"fenêtre plus petite que le calendrier : aucune marge, jamais négative",
	leading(out[1]) == 0 and empties(out) == 0 and #out == 40,
	true
)
out = layout.center(sample(3, 76), 65, 80, 10)
check(
	"une ligne plus large que le calendrier (l'aide, 76) : la marge est réduite pour qu'elle tienne (80 - 76)",
	leading(out[#out]),
	4
)
out = layout.center(sample(3, 76), 65, 70, 10)
check("ligne plus large que la fenêtre : aucune marge", leading(out[#out]), 0)
out = layout.center(sample(2, 65), 65, nil, nil)
check("taille inconnue : aucune marge à gauche", leading(out[1]), 0)
check("taille inconnue : aucune marge en haut", empties(out), 0)
out = layout.center(sample(2, 65), 65, 165, nil)
check("hauteur inconnue : centré seulement en largeur", leading(out[1]) == 50 and empties(out) == 0, true)
out = layout.center(sample(2, 65), 65, nil, 40)
check("largeur inconnue : centré seulement en hauteur", leading(out[#out]) == 0 and empties(out) == 19, true)
out = layout.center(sample(2, 65), 65, "beaucoup", "trop")
check("taille en texte : aucune marge", leading(out[1]) == 0 and empties(out) == 0, true)

local input = sample(3, 10)
layout.center(input, 10, 100, 20)
check("la liste d'origine n'est pas modifiée", input[1] .. input[2] .. input[3], string.rep("x", 30))
local colored = "\27[48;2;1;2;3m" .. string.rep("y", 65) .. "\27[0m"
out = layout.center({ colored }, 65, 165, 3)
check("lignes colorées : la marge est devant les codes de couleur", out[#out], string.rep(" ", 50) .. colored)
check(
	"lignes colorées : la largeur visible est celle du texte, pas des codes",
	layout.visible_width(out[#out]),
	50 + 65
)

local seed = 777
local function rnd(n)
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed % n
end
local safe = true
for _ = 1, 400 do
	local count, width = 1 + rnd(60), 20 + rnd(80)
	local cols, rows = 20 + rnd(300), 5 + rnd(100)
	local lines = sample(count, width)
	local result = layout.center(lines, width, cols, rows)
	local widest = 0
	for _, line in ipairs(result) do
		widest = math.max(widest, layout.visible_width(line))
	end
	if width <= cols and widest > cols then
		safe = false
	end
	if count <= rows and #result > rows then
		safe = false
	end
	if #result < count then
		safe = false
	end
end
check("400 tailles au hasard : centrer ne fait jamais déborder ce qui tenait, et ne perd aucune ligne", safe, true)

-- ============================================================
-- le dessin de la page
-- ============================================================
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
	w.next_id = 120
	function w.new_pane(cols, rows)
		w.next_id = w.next_id + 1
		local tab = {}
		function tab:activate() end
		local pane =
			{ id = w.next_id, injected = {}, dims = { viewport_rows = rows or 40, cols = cols or 120 }, the_tab = tab }
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
local DAYS = {
	["2026-10-10"] = 15231,
	["2026-10-12"] = 3600,
	["2026-09-14"] = 7200,
	["2026-08-03"] = 3600,
	["2026-07-21"] = 20000,
}
local function new_page(w, cfg)
	local settings = { week_starts_on = "monday", day_offset = 0 }
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
			return fr
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
	local out_lines = {}
	for line in (text .. "\n"):gmatch("(.-)\n") do
		out_lines[#out_lines + 1] = line
	end
	return out_lines
end
local function drawn(pane)
	return lines_of(strip(pane.injected[#pane.injected]))
end
local function find_line(lines, needle)
	for i, line in ipairs(lines) do
		if line:find(needle, 1, true) then
			return i, line
		end
	end
end
local function open(cfg, cols, rows)
	local w = new_state()
	local page = new_page(w, cfg)
	local win = new_window(w, cols, rows)
	page.open(win, w.new_pane())
	return w, page, w.spawned[1]
end

-- un seul mois dans une fenêtre de 120 x 40
local w, page, pane = open({}, 120, 40)
local lines = drawn(pane)
local text_lines = lines_of((page.build_text({ cols = 120, rows = 40 })))
local top = math.floor((40 - #text_lines) / 2)
check("un mois : la marge du haut est la moitié de l'espace libre", empties(lines), top)
check("un mois : cette marge n'est pas nulle", top > 0, true)
local _, help = find_line(lines, "Logtime   ←→↑↓")
check("un mois : l'aide est décalée de 27 (la marge) + 2 espaces", leading(help), 27 + 2)
local _, title = find_line(lines, "Logtime : Octobre 2026")
check("un mois : le titre est décalé de la même marge", leading(title), 27 + 2)
local _, header = find_line(lines, "Lun")
check("un mois : l'en-tête des jours est décalé de la même marge (27 + 5)", leading(header), 27 + 5)
local _, stats_line = find_line(lines, "Total du mois")
check("un mois : les totaux sont décalés de la même marge", leading(stats_line), 27 + 2)
check("un mois : le dessin tient dans la fenêtre", #lines <= 40, true)
local widest = 0
for _, line in ipairs(lines) do
	widest = math.max(widest, utf8.len(line))
end
check("un mois : aucune ligne ne dépasse la largeur de la fenêtre", widest <= 120, true)

-- centrage désactivé
w, page, pane = open({ center = false }, 120, 40)
lines = drawn(pane)
check(
	"center = false : la première ligne est l'aide, tout en haut",
	lines[1]:find("Logtime   ←→↑↓", 1, true) == 3,
	true
)
_, header = find_line(lines, "Lun")
check("center = false : l'en-tête garde sa position d'origine (5 espaces)", leading(header), 5)

-- sans taille connue : build_text ne centre jamais, il rend le texte brut
local raw_text, count, width = page.build_text()
check("build_text sans taille : première ligne = l'aide, sans marge", lines_of(raw_text)[1]:sub(1, 11), "  Logtime  ")
check("build_text sans taille : un mois, de la largeur du calendrier", count == 1 and width == layout.BLOCK_WIDTH, true)
raw_text, count, width = page.build_text({ cols = 140, rows = 60 })
check(
	"build_text avec taille : le texte lui-même n'est pas centré (c'est le dessin qui le fait)",
	lines_of(raw_text)[1]:sub(1, 11),
	"  Logtime  "
)
check("build_text : quatre mois, 2 x 65 + 3 de largeur", count == 4 and width == 133, true)
raw_text, count, width = page.build_text({ cols = 400, rows = 25 })
check("build_text : cinq mois sur une rangée, 5 x 65 + 4 x 3 de largeur", count == 5 and width == 337, true)

-- plusieurs mois : 2 x 2 dans 140 x 60
w, page, pane = open({}, 140, 60)
lines = drawn(pane)
check("quatre mois : marge du haut = (60 - 47) / 2", empties(lines), 6)
local _, first_title = find_line(lines, "Juillet 2026")
check("quatre mois : marge à gauche = (140 - 133) / 2 = 3, plus les 2 espaces du titre", leading(first_title), 3 + 2)
local _, second_title = find_line(lines, "Août 2026")
check(
	"quatre mois : le second mois est 68 colonnes plus loin (65 + 3)",
	second_title:find("Août", 1, true) - first_title:find("Juillet", 1, true),
	68
)
check("quatre mois : le dessin tient dans la fenêtre", #lines <= 60, true)
widest = 0
for _, line in ipairs(lines) do
	widest = math.max(widest, utf8.len(line))
end
check("quatre mois : aucune ligne ne dépasse la largeur de la fenêtre", widest <= 140, true)

-- fenêtre à la taille exacte : pas de marge
w, page, pane = open({}, 133, 47)
lines = drawn(pane)
check("fenêtre de 133 x 47 (la taille exacte de 4 mois) : aucune marge en haut", empties(lines), 0)
_, first_title = find_line(lines, "Juillet 2026")
check("fenêtre de 133 x 47 : aucune marge à gauche (juste les 2 espaces du titre)", leading(first_title), 2)

-- la fenêtre change de taille : les marges suivent
w, page, pane = open({}, 100, 40)
w.GLOBAL.logtime_page_pane = pane.id
_, help = find_line(drawn(pane), "Logtime   ←→↑↓")
check("avant : fenêtre de 100 colonnes, marge de 17 (+ 2)", leading(help), 17 + 2)
pane.dims.cols = 120
page.on_resize(new_window(w, 120, 40), pane)
_, help = find_line(drawn(pane), "Logtime   ←→↑↓")
check("après : fenêtre de 120 colonnes, marge de 27 (+ 2) : le calendrier reste centré", leading(help), 27 + 2)
pane.dims.cols, pane.dims.viewport_rows = 120, 60
page.on_resize(new_window(w, 120, 60), pane)
lines = drawn(pane)
check("fenêtre plus haute : la marge du haut grandit aussi", empties(lines) > 0, true)
check("aucune erreur pendant ces changements de taille", #w.logs.error, 0)

-- jamais plus de lignes que la fenêtre, et jamais plus large qu'avant le centrage (la ligne d'aide, large de 77 colonnes,
-- dépasse déjà d'une fenêtre très étroite : centrer ne doit pas aggraver ça)
local always_fits = true
for _, size in ipairs({
	{ 120, 40 },
	{ 140, 60 },
	{ 133, 47 },
	{ 100, 100 },
	{ 400, 25 },
	{ 65, 25 },
	{ 200, 80 },
	{ 90, 30 },
}) do
	local _, _, centered = open({}, size[1], size[2])
	local _, _, plain = open({ center = false }, size[1], size[2])
	local shown, before = drawn(centered), drawn(plain)
	local widest_after, widest_before = 0, 0
	for _, line in ipairs(shown) do
		widest_after = math.max(widest_after, utf8.len(line))
	end
	for _, line in ipairs(before) do
		widest_before = math.max(widest_before, utf8.len(line))
	end
	if #shown > size[2] or widest_after > math.max(size[1], widest_before) then
		always_fits = false
	end
end
check(
	"8 tailles de fenêtre : le dessin centré ne dépasse jamais la fenêtre, ni plus qu'avant le centrage",
	always_fits,
	true
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
