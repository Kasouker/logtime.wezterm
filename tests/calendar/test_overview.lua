-- tests/calendar/test_overview.lua : teste calendar/overview.lua (la vue du mois et du jour, l'aperçu de la page F4).
-- Lancer :   lua5.4 tests/calendar/test_overview.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]calendar[/\\]test_overview%.lua$") or "."
local cache = {}
local function load_module(name)
	if not cache[name] then
		cache[name] = assert(loadfile(root .. "/plugin/logtime/" .. name .. ".lua"))(load_module)
	end
	return cache[name]
end
local overview = load_module("calendar/overview")
local assemble = load_module("calendar/assemble")
local gradient = load_module("color/gradient")
local convert = load_module("color/convert")
local layout = load_module("calendar/layout")
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
local function strip(text)
	return (text:gsub("\27%[[%d;]*m", ""))
end
local function joined(lines)
	return table.concat(lines, "\n")
end

local DAYS = {
	["2026-10-10"] = 4 * 3600 + 13 * 60,
	["2026-10-12"] = 8 * 3600 + 56 * 60,
	["2026-10-14"] = 15 * 3600 + 35 * 60,
	["2026-10-15"] = 10 * 3600 + 4 * 60,
}
local function data(over)
	local o = {
		days = DAYS,
		idle_days = { ["2026-10-15"] = 1 * 3600 + 55 * 60 },
		projects = {
			["2026-10-15"] = {
				["Bot Discord"] = 4 * 3600,
				["Plug WT"] = 2 * 3600,
				RL = 3600,
				tiny = 30, -- moins d'une minute : pas affiché
			},
		},
		year = 2026,
		month = 10,
		today_key = "2026-10-15",
		day_key = "2026-10-15",
		cfg = gradient.apply_to({ goal_hours = 8, week_starts_on = "monday" }),
		labels = fr,
		b = assemble.BORDER_STYLES.rounded,
		edge = "",
	}
	for k, v in pairs(over or {}) do
		o[k] = v
	end
	return o
end

-- ---- les semaines du mois
local weeks = overview.weeks(2026, 10, "monday")
check("octobre 2026 (semaine du lundi) : 5 semaines", #weeks, 5)
check("le 1er octobre 2026 est un jeudi (4e colonne)", tostring(weeks[1][4]), "1")
check("avant le 1er : des cases vides", tostring(weeks[1][1]) .. tostring(weeks[1][3]), "falsefalse")
check(
	"la dernière semaine finit le 31, puis du vide",
	tostring(weeks[5][6]) .. " " .. tostring(weeks[5][7]),
	"31 false"
)
local sunday = overview.weeks(2026, 10, "sunday")
check("semaine du dimanche : le jeudi 1er est en 5e colonne", tostring(sunday[1][5]), "1")
check("février 2027 (semaine du lundi) : 4 semaines pile (le 1er est un lundi)", #overview.weeks(2027, 2, "monday"), 4)
check("août 2026 (semaine du lundi) : 6 semaines", #overview.weeks(2026, 8, "monday"), 6)

-- ---- la grille du mois
local grid = overview.grid(data(), 100, 30)
local plain = {}
for i, line in ipairs(grid) do
	plain[i] = strip(line)
end
check("la grille : exactement la hauteur demandée", #grid, 30)
check(
	"la grille : chaque ligne fait la largeur demandée",
	(function()
		for i, line in ipairs(grid) do
			if layout.visible_width(line) ~= 100 then
				return i
			end
		end
		return true
	end)(),
	true
)
check("le nom du mois, en haut à gauche (au-dessus des semaines)", plain[2]:match("^│%s*(%S+)%s*│"), "Octobre")
check("les jours en toutes lettres quand ils tiennent", plain[2]:find("Mercredi", 1, true) ~= nil, true)
check("lundi d'abord", plain[2]:find("Lundi", 1, true) < plain[2]:find("Mardi", 1, true), true)
check(
	"une ligne par semaine : Semaine 1 à 5",
	joined(plain):find("Semaine 1", 1, true) ~= nil
		and joined(plain):find("Semaine 5", 1, true) ~= nil
		and joined(plain):find("Semaine 6", 1, true) == nil,
	true
)
check("aujourd'hui est marqué « * »", joined(plain):find("*15", 1, true) ~= nil, true)
check("la durée sous le numéro du jour", joined(plain):find("15h35", 1, true) ~= nil, true)
check("un jour sans temps : pas de durée", joined(plain):find("0h00", 1, true), nil)
local color14 = assemble.day_color(DAYS["2026-10-14"], data().cfg)
check(
	"un jour avec du temps : sa case sur la couleur de sa durée",
	joined(grid):find(convert.bg(color14), 1, true) ~= nil,
	true
)
check(
	"le texte d'une case lisible (contraste)",
	joined(grid):find(convert.bg(color14) .. convert.fg(convert.contrast(color14)), 1, true) ~= nil,
	true
)
check("le cadre de la grille : le style choisi", plain[1]:sub(1, #"╭"), "╭")
local double = strip(joined(overview.grid(data({ b = assemble.BORDER_STYLES.double }), 100, 30)))
check("le cadre de la grille : un autre style (double)", double:find("╬", 1, true) ~= nil, true)
local narrow = strip(joined(overview.grid(data(), 70, 30)))
check(
	"étroit : les jours en abrégé, centrés dans leur case (pas un nom long coupé)",
	narrow:find("│  Mer  │", 1, true) ~= nil and narrow:find("Mercre", 1, true) == nil,
	true
)
local sun_grid = strip(overview.grid(data({ cfg = gradient.apply_to({ week_starts_on = "sunday" }) }), 100, 30)[2])
check(
	"semaine du dimanche : Dimanche d'abord",
	sun_grid:find("Dimanche", 1, true) < sun_grid:find("Lundi", 1, true),
	true
)
check(
	"anglais : les noms anglais",
	strip(overview.grid(data({ labels = en }), 100, 30)[2]):find("Wednesday", 1, true) ~= nil,
	true
)
check("trop étroit pour une grille : nil", overview.grid(data(), 40, 30), nil)
check("trop bas pour une grille : nil", overview.grid(data(), 100, 10), nil)
-- les semaines prennent la hauteur disponible
local tall = overview.grid(data(), 100, 60)
local short = overview.grid(data(), 100, 20)
local function week_height(g)
	local rows = {}
	for i, line in ipairs(g) do
		if strip(line):sub(1, #"├") == "├" then
			rows[#rows + 1] = i
		end
	end
	return rows[3] - rows[2]
end
check("plus de place : des semaines plus hautes", week_height(tall) > week_height(short), true)

-- ---- l'objectif dans la grille (comme dans le calendrier F2)
-- le bas du cadre de la grille (la grille peut finir par des lignes vides)
local function bottom_of(g)
	for k = #g, 1, -1 do
		if strip(g[k]):find("^╰") then
			return g[k]
		end
	end
end
local goal_grid = overview.grid(data(), 100, 30)
local goal_text_ = strip(joined(goal_grid))
check("objectif atteint : « ✓ » devant la durée", goal_text_:find("✓ 8h56", 1, true) ~= nil, true)
check("objectif atteint aujourd'hui aussi", goal_text_:find("✓ 10h04", 1, true) ~= nil, true)
check(
	"objectif manqué un jour passé : la durée rayée",
	joined(goal_grid):find("\27[9m4h13\27[29m", 1, true) ~= nil,
	true
)
check(
	"en bas du cadre : les semaines et les jours validés",
	strip(bottom_of(goal_grid)):find("^╰─ Semaines validées : 0/5 / Jours validés : 3/31 ─┴") ~= nil,
	true
)
local _, goal_bottom_joins = strip(bottom_of(goal_grid)):gsub("┴", "")
check(
	"en bas du cadre : le texte cache seulement les jonctions sous lui",
	goal_bottom_joins > 0 and goal_bottom_joins < 7,
	true
)
check("en bas du cadre : la largeur reste la même", layout.visible_width(bottom_of(goal_grid)), 100)
local no_goal_grid = overview.grid(data({ cfg = gradient.apply_to({}) }), 100, 30)
check("sans objectif : pas de « ✓ »", strip(joined(no_goal_grid)):find("✓", 1, true), nil)
check("sans objectif : pas de durée rayée", joined(no_goal_grid):find("\27[9m", 1, true), nil)
check("sans objectif : le bas du cadre sans texte", strip(bottom_of(no_goal_grid)):find("Semaines", 1, true), nil)
check(
	"en anglais",
	strip(bottom_of(overview.grid(data({ labels = en }), 100, 30))):find(en.validated_weeks, 1, true) ~= nil,
	true
)
local long_labels = {}
for k, v in pairs(fr) do
	long_labels[k] = v
end
long_labels.validated_weeks = string.rep("x", 60) -- un texte qui ne tient pas sur le bas du cadre
local narrow_goal = overview.grid(data({ labels = long_labels }), 70, 30)
check(
	"trop étroit pour le texte : le bas du cadre reste un trait",
	strip(bottom_of(narrow_goal)):find("xxx", 1, true) == nil
		and select(2, strip(bottom_of(narrow_goal)):gsub("┴", "")) == 7,
	true
)

-- ---- les noms des jours : tous en entier, ou tous en abrégé
local mixed = strip(overview.grid(data(), 75, 30)[2])
check(
	"les noms des jours : jamais un mélange (tous abrégés si l'un ne tient pas)",
	mixed:find("Lun", 1, true) ~= nil and mixed:find("Lundi", 1, true) == nil and mixed:find("Mer", 1, true) ~= nil,
	true
)
check(
	"les noms des jours : tous en entier s'ils tiennent",
	strip(overview.grid(data(), 100, 30)[2]):find("Mercredi", 1, true) ~= nil,
	true
)
-- ---- une barre verticale (au huitième de ligne près)
local function bar_text(lines)
	local out = {}
	for i, line in ipairs(lines) do
		out[i] = strip(line)
	end
	return table.concat(out, "|")
end
check(
	"barre vide : seulement son sol (▁ en bas)",
	bar_text(overview.vertical_bar(0, 3, "#FFFFFF", 2)),
	"  |  |▁▁"
)
check("barre pleine : toute la hauteur", bar_text(overview.vertical_bar(1, 3, "#FFFFFF", 2)), "██|██|██")
check(
	"barre à moitié (4 lignes) : les 2 du bas",
	bar_text(overview.vertical_bar(0.5, 4, "#FFFFFF", 1)),
	" | |█|█"
)
check("barre à 1/8 de ligne : ▁", bar_text(overview.vertical_bar(1 / 32, 4, "#FFFFFF", 1)), " | | |▁")
check("barre à 3/4 de ligne : ▆", bar_text(overview.vertical_bar(6 / 32, 4, "#FFFFFF", 1)), " | | |▆")
check("barre au-delà de 100 % : pleine (jamais plus)", bar_text(overview.vertical_bar(2, 2, "#FFFFFF", 1)), "█|█")
check("barre : dans sa couleur", overview.vertical_bar(1, 1, "#123456", 1)[1]:find(convert.fg("#123456"), 1, true), 1)

-- ---- le détail du jour : un tableau encadré
local detail = overview.detail(data(), "2026-10-15", 100, 16)
local dplain = {}
for i, line in ipairs(detail) do
	dplain[i] = strip(line)
end
local function line_with(text)
	for i, line in ipairs(dplain) do
		if line:find(text, 1, true) then
			return i, line
		end
	end
end
check("le détail : exactement la hauteur demandée", #detail, 16)
check(
	"le détail : chaque ligne fait la largeur demandée",
	(function()
		for i, line in ipairs(detail) do
			if layout.visible_width(line) ~= 100 then
				return i
			end
		end
		return true
	end)(),
	true
)
check("le tableau : encadré (haut)", dplain[1]:sub(1, #"╭") .. dplain[1]:sub(-#"╮"), "╭╮")
check("le tableau : encadré (bas)", dplain[16]:sub(1, #"╰") .. dplain[16]:sub(-#"╯"), "╰╯")
check("le tableau : 4 colonnes (actif, inactif, la liste, les pourcentages)", select(2, dplain[1]:gsub("┬", "")), 3)
local _, top_row = line_with("8h09")
check("en haut des barres : l'actif et l'inactif (8h09, 1h55)", top_row:find("1h55", 1, true) ~= nil, true)
check(
	"une délimitation entre les deux barres, et entre les barres et la liste",
	select(2, top_row:gsub("│", "")) >= 4,
	true
)
local _, names_row = line_with("Inactif")
check(
	"sous les barres : leurs noms, en entier (« Actif », « Inactif »)",
	names_row:find("Actif", 1, true) ~= nil,
	true
)
local _, percent_row = line_with("81%")
check("tout en bas : les pourcentages (81 % actif, 19 % inactif)", percent_row:find("19%", 1, true) ~= nil, true)
check("les pourcentages : juste au-dessus du bas du cadre", line_with("81%"), 15)
check("les barres : l'actif est rempli", strip(detail[13]):find("█", 1, true) ~= nil, true)
local total_index, total_row = line_with("Total")
check("le total : sur la 1re ligne de la liste", total_index, 2)
check(
	"le total et l'objectif atteint",
	total_row:find("Total  10h04", 1, true) ~= nil and total_row:find("✓ objectif 8h atteint", 1, true) ~= nil,
	true
)
check(
	"sous le total : un trait (├ … ┼ … ┤)",
	dplain[3]:find("├", 1, true) ~= nil and dplain[3]:find("┼", 1, true) ~= nil,
	true
)
local project_index, first_project = line_with("Bot Discord")
check(
	"l'objectif est aligné sur le début des barres des projets",
	utf8.len(total_row:sub(1, total_row:find("✓", 1, true) - 1)),
	utf8.len(first_project:sub(1, first_project:find("█", 1, true) - 1))
)
check("le plus gros projet d'abord, avec sa durée", first_project:find("4h00", 1, true) ~= nil, true)
check("puis le suivant", line_with("Plug WT") > project_index, true)
check("le pourcentage dans sa colonne, au bord droit", first_project:match("│ *40%% │$") ~= nil, true)
check(
	"une barre par projet",
	detail[project_index]:find("█", 1, true) ~= nil and detail[project_index]:find("░", 1, true) ~= nil,
	true
)
check("un trait entre deux projets (il y a la place)", dplain[project_index + 1]:find("┼", 1, true) ~= nil, true)
check("un projet de moins d'une minute : caché", table.concat(dplain, "\n"):find("tiny", 1, true), nil)
local tight = strip(joined(overview.detail(data(), "2026-10-15", 100, 8)))
check("pas la place pour les traits entre les projets : la liste sans eux", select(2, tight:gsub("┼", "")), 1)
check("pas la place : les projets sont quand même là", tight:find("RL", 1, true) ~= nil, true)
local missing = strip(joined(overview.detail(data({ days = { ["2026-10-15"] = 3600 } }), "2026-10-15", 100, 12)))
check(
	"objectif pas encore atteint aujourd'hui : ce qu'il manque",
	missing:find("objectif 8h : il manque 7h00", 1, true) ~= nil,
	true
)
local past = strip(joined(overview.detail(data({ days = { ["2026-10-12"] = 3600 } }), "2026-10-12", 100, 12)))
check("un jour passé sous l'objectif : manqué", past:find("non atteint", 1, true) ~= nil, true)
local no_goal = strip(joined(overview.detail(data({ cfg = gradient.apply_to({}) }), "2026-10-15", 100, 12)))
check("sans objectif : juste le total", no_goal:find("objectif", 1, true), nil)
local empty = strip(joined(overview.detail(data(), "2026-10-20", 100, 12)))
check("un jour sans temps : le dit", empty:find(fr.detail_empty, 1, true) ~= nil, true)
check("un jour sans temps : 0 % partout, pas de division par zéro", empty:find("0%", 1, true) ~= nil, true)
local english = strip(joined(overview.detail(data({ labels = en }), "2026-10-15", 100, 12)))
check("anglais : Active / Idle", english:find("Active", 1, true) ~= nil and english:find("Idle", 1, true) ~= nil, true)
local many = {}
for i = 1, 12 do
	many["p" .. i] = i * 600
end
local crowded = overview.detail(data({ projects = { ["2026-10-15"] = many } }), "2026-10-15", 100, 16)
check("beaucoup de projets : jamais plus haut que la place", #crowded, 16)
check("beaucoup de projets : le reste dans « autres »", strip(joined(crowded)):find("autres", 1, true) ~= nil, true)
local double_detail = strip(joined(overview.detail(data({ b = assemble.BORDER_STYLES.double }), "2026-10-15", 100, 12)))
local hidden =
	overview.detail(data({ cfg = gradient.apply_to({ goal_hours = 8, count_idle = false }) }), "2026-10-15", 100, 12)
local hidden_text = strip(joined(hidden))
check("inactif non compté : plus de colonne Inactif", hidden_text:find("Inactif", 1, true), nil)
check("inactif non compté : la colonne Actif reste", hidden_text:find("Actif", 1, true) ~= nil, true)
local _, hidden_cols = strip(hidden[1]):gsub("┬", "")
check("inactif non compté : un trait vertical de moins en haut", hidden_cols, 2)
local _, hidden_bottom = strip(hidden[#hidden]):gsub("┴", "")
check("inactif non compté : et en bas", hidden_bottom, 2)
local hidden_sizes = true
for _, line in ipairs(hidden) do
	hidden_sizes = hidden_sizes and layout.visible_width(line) == 100
end
check("inactif non compté : toutes les lignes font la largeur", hidden_sizes, true)
check(
	"inactif non compté : le cadre va jusqu'au bord droit (la liste prend la place)",
	strip(hidden[1]):sub(-3),
	"╮"
)
check("le tableau suit le style du trait (double)", double_detail:find("╔", 1, true) ~= nil, true)

-- ---- la frise
local palette = load_module("color/palette")
local SEGS = { { 9 * 3600, 10 * 3600, "petit" }, { 10 * 3600, 14 * 3600, "gros" }, { 15 * 3600, 15 * 3600 + 600, "?" } }
local colors = overview.timeline_colors(SEGS)
check(
	"couleurs : le plus gros projet du jour prend la 1re couleur",
	colors.gros,
	palette.COLORS[overview.TIMELINE_ORDER[1]]
)
check("couleurs : puis le suivant", colors.petit, palette.COLORS[overview.TIMELINE_ORDER[2]])
check("couleurs : « autres » en gris", colors["?"], overview.OTHER_COLOR)
check("couleurs : deux projets, deux couleurs différentes", colors.gros ~= colors.petit, true)
local columns = overview.timeline_columns(SEGS, 24) -- une colonne par heure
check("colonnes : rien avant 9h", tostring(columns[9]), "false")
check("colonnes : 9h-10h : petit", columns[10], "petit")
check("colonnes : 10h-14h : gros", columns[11] .. columns[14], "grosgros")
check("colonnes : 14h-15h : rien", tostring(columns[15]), "false")
check("colonnes : 15h-16h : 10 min d'autres, c'est le seul", columns[16], "?")
check(
	"colonnes : une colonne partagée va au projet qui y a passé le plus de temps",
	overview.timeline_columns({ { 0, 1000, "a" }, { 1000, 3600, "b" } }, 24)[1],
	"b"
)
-- (sans temps par projet ce jour-là : les couleurs viennent de la frise seule)
local tl = overview.timeline(data({ projects = {}, timeline = { ["2026-10-15"] = SEGS } }), "2026-10-15", 98)
check("la frise : 4 lignes", #tl, 4)
check(
	"la frise : chaque ligne fait la largeur",
	layout.visible_width(tl[1]) == 98 and layout.visible_width(tl[3]) == 98,
	true
)
check("au-dessus : 0h00 à gauche, 24h00 à droite", strip(tl[1]):match("^ 0h00 +24h00 $") ~= nil, true)
check("la frise dans un cadre", strip(tl[2]):sub(1, #"╭") .. strip(tl[4]):sub(1, #"╰"), "╭╰")
check("le nom du projet dans son morceau (s'il y tient)", strip(tl[3]):find("gros", 1, true) ~= nil, true)
check(
	"un morceau trop court pour son nom : coloré, sans aucune lettre (pas un nom coupé)",
	(function()
		local style = convert.bg(overview.OTHER_COLOR) .. convert.fg(convert.contrast(overview.OTHER_COLOR))
		local s_ = tl[3]:find(style, 1, true)
		local text = s_ and tl[3]:sub(s_ + #style, (tl[3]:find("\27[0m", s_, true) or 0) - 1)
		return text ~= nil and #text > 0 and text:match("^ +$") ~= nil
	end)(),
	true
)
check(
	"chaque projet dans sa couleur",
	tl[3]:find(convert.bg(colors.gros), 1, true) ~= nil and tl[3]:find(convert.bg(colors.petit), 1, true) ~= nil,
	true
)
check(
	"le texte lisible sur sa couleur",
	tl[3]:find(convert.bg(colors.gros) .. convert.fg(convert.contrast(colors.gros)), 1, true) ~= nil,
	true
)
check(
	"le morceau du gros projet à sa place (de 10h à 14h : à partir de 10/24 de la largeur)",
	-- la colonne où commence sa couleur (après le trait de gauche du cadre)
	math.abs(
		layout.visible_width(tl[3]:sub(1, tl[3]:find(convert.bg(colors.gros), 1, true) - 1))
			- 1
			- math.floor(96 * 10 / 24)
	) <= 1,
	true
)
-- ---- les couleurs reliées : la frise et le détail, chaque projet dans la même couleur
local LINKED = {
	{ 9 * 3600, 13 * 3600, "Bot Discord" },
	{ 13 * 3600, 15 * 3600, "Plug WT" },
	{ 15 * 3600, 16 * 3600, "RL" },
	{ 16 * 3600, 16 * 3600 + 30, "tiny" },
}
local linked = data({ timeline = { ["2026-10-15"] = LINKED } })
local day_colors = overview.day_colors(linked, "2026-10-15")
check(
	"couleurs du jour : le plus gros projet du détail a la 1re couleur",
	day_colors["Bot Discord"],
	palette.COLORS[overview.TIMELINE_ORDER[1]]
)
check("couleurs du jour : le 2e la 2e", day_colors["Plug WT"], palette.COLORS[overview.TIMELINE_ORDER[2]])
check("couleurs du jour : le 3e la 3e", day_colors.RL, palette.COLORS[overview.TIMELINE_ORDER[3]])
check(
	"couleurs du jour : un projet absent du détail (moins d'une minute) : pas de couleur à lui",
	day_colors.tiny,
	nil
)
check(
	"couleurs du jour : « autres » en gris (comme sur la frise)",
	overview.day_colors(data({ projects = { ["2026-10-15"] = { A = 3600, ["?"] = 600 } } }), "2026-10-15")["?"],
	overview.OTHER_COLOR
)
local linked_tl = overview.timeline(linked, "2026-10-15", 98)
local linked_detail = joined(overview.detail(linked, "2026-10-15", 100, 16))
for _, name in ipairs({ "Bot Discord", "Plug WT", "RL" }) do
	check(
		"couleurs reliées : " .. name .. " a la même couleur sur la frise et dans le détail",
		linked_tl[3]:find(convert.bg(day_colors[name]), 1, true) ~= nil
			and linked_detail:find(convert.fg(day_colors[name]) .. "█", 1, true) ~= nil,
		true
	)
end
check(
	"couleurs reliées : un projet sans couleur à lui est gris sur la frise (comme « autres »)",
	linked_tl[3]:find(convert.bg(overview.OTHER_COLOR), 1, true) ~= nil,
	true
)
local day_color = assemble.day_color(DAYS["2026-10-15"], linked.cfg)
local function literal(text)
	return (text:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end
-- une barre horizontale de projet : sa couleur, puis le gris du vide (les barres verticales n'en ont pas)
local function project_bars(text, color)
	return select(
		2,
		text:gsub(literal(convert.fg(color)) .. "[^\27]*" .. literal(convert.fg(overview.EMPTY_COLOR)), "")
	)
end
check(
	"couleurs reliées : plus aucune barre de projet dans la couleur du jour",
	project_bars(linked_detail, day_color),
	0
)
local unlinked = joined(overview.detail(
	data({
		cfg = gradient.apply_to({ goal_hours = 8, show_timeline = false }),
		timeline = { ["2026-10-15"] = LINKED },
	}),
	"2026-10-15",
	100,
	16
))
check(
	"sans la frise : les 3 barres de projets dans la couleur du jour (comme avant)",
	project_bars(unlinked, day_color),
	3
)
check(
	"sans la frise : aucune couleur de projet",
	unlinked:find(convert.fg(day_colors["Bot Discord"]) .. "█", 1, true),
	nil
)

local shifted_tl = overview.timeline(data({ cfg = gradient.apply_to({ day_offset = -3600 }) }), "2026-10-15", 60)
check("une journée qui commence à 1h00 : 1h00 … 1h00", strip(shifted_tl[1]):match("^ 1h00 +1h00 $") ~= nil, true)
local empty_tl = overview.timeline(data({ timeline = {} }), "2026-10-15", 60)
check("sans frise ce jour-là : le cadre vide", strip(empty_tl[3]):match("^│ +│$") ~= nil, true)
local with_tl = overview.render(data({ timeline = { ["2026-10-15"] = SEGS } }), 100, 50)
check(
	"la vue : la frise tout en bas (son cadre, puis le bas)",
	strip(with_tl[50]):sub(1, #"╰") == "╰" and strip(with_tl[49]):find("gros", 1, true) ~= nil,
	true
)
check(
	"la vue : les heures de la frise juste au-dessus d'elle",
	strip(with_tl[47]):match("^ 0h00 +24h00 $") ~= nil,
	true
)
check("la vue : le détail du jour au-dessus de la frise", strip(with_tl[46]):sub(1, #"╰"), "╰")

-- ---- sans la frise (show_timeline = false) : le détail prend sa place
local no_tl = overview.render(
	data({ cfg = gradient.apply_to({ goal_hours = 8, show_timeline = false }), timeline = { ["2026-10-15"] = SEGS } }),
	100,
	50
)
check("sans la frise : la bonne hauteur", #no_tl, 50)
check("sans la frise : plus les heures de la frise", strip(joined(no_tl)):find("24h00", 1, true), nil)
check("sans la frise : le détail descend jusqu'en bas", strip(no_tl[#no_tl]):sub(1, 3), "╰")
local with_tl_view = overview.render(data({ timeline = { ["2026-10-15"] = SEGS } }), 100, 50)
check("avec la frise (par défaut) : elle est là", strip(joined(with_tl_view)):find("24h00", 1, true) ~= nil, true)

-- ---- toute la vue
local view = overview.render(data(), 100, 40)
check("la vue : exactement la taille demandée", #view == 40 and layout.visible_width(view[40]) == 100, true)
check(
	"la vue : la grille puis le détail",
	strip(joined(view)):find("Semaine 5", 1, true) < strip(joined(view)):find("Total", 1, true),
	true
)
local big = overview.render(data(), 100, 60)
local grid_end
for i, line in ipairs(big) do
	if strip(line):sub(1, #"╰") == "╰" then
		grid_end = grid_end or i
	end
end
check("la grille ne grossit pas avec la place : au plus la moitié de la hauteur", grid_end <= 30, true)
check("une semaine : au plus 3 lignes de haut", week_height(overview.grid(data(), 100, 60)), overview.MAX_ROW + 1)
check("le détail commence juste sous la grille", strip(big[grid_end + 1]):sub(1, #"╭"), "╭")
check("le détail prend tout le reste (jusqu'en bas)", strip(big[60]):sub(1, #"╰"), "╰")
local mid = overview.render(data(), 100, 40)
local mid_end
for i, line in ipairs(mid) do
	if strip(line):sub(1, #"╰") == "╰" then
		mid_end = mid_end or i
	end
end
check("40 lignes : la grille ne prend pas plus de la moitié (le détail garde sa place)", mid_end <= 20, true)
local min_w, min_h = overview.minimum(5)
check("la vue : pile au minimum, elle tient", overview.render(data(), min_w, min_h) ~= nil, true)
check("la vue : une colonne de moins, nil", overview.render(data(), min_w - 1, min_h), nil)
check("la vue : une ligne de moins, nil", overview.render(data(), min_w, min_h - 1), nil)
check("le minimum pour 6 semaines est plus haut", select(2, overview.minimum(6)) > min_h, true)
local at_min = overview.render(data(), min_w, min_h)
check("au minimum : le détail est là", strip(joined(at_min)):find("Total", 1, true) ~= nil, true)
check("au minimum : la grille entière (Semaine 5)", strip(joined(at_min)):find("Semaine 5", 1, true) ~= nil, true)
check(
	"le jour du détail : un autre jour que aujourd'hui",
	strip(joined(overview.render(data({ day_key = "2026-10-14" }), 100, 40))):find("Total  15h35", 1, true) ~= nil,
	true
)

-- ---- la semaine (l'aperçu de F4 : le détail de la semaine en cours)
check(
	"les jours de la semaine (lundi d'abord)",
	table.concat(overview.week_keys("2026-10-15", "monday"), " "),
	"2026-10-12 2026-10-13 2026-10-14 2026-10-15 2026-10-16 2026-10-17 2026-10-18"
)
local edge_week = overview.week_keys("2026-10-01", "monday")
check("la semaine du 1er : elle commence le mois d'avant", edge_week[1] .. " " .. edge_week[7], "2026-09-28 2026-10-04")
local sun_week = overview.week_keys("2026-10-15", "sunday")
check("la semaine qui commence le dimanche", sun_week[1] .. " " .. sun_week[7], "2026-10-11 2026-10-17")
local WEEK = overview.week_keys("2026-10-15", "monday")
local week_projects = {
	["2026-10-12"] = { ["Bot Discord"] = 3600, X = 600 },
	["2026-10-15"] = data().projects["2026-10-15"],
}
local wd, reached = overview.week_data(data({ projects = week_projects }), WEEK)
check(
	"la semaine réunie : le total des 7 jours",
	wd.days[overview.WEEK_KEY],
	DAYS["2026-10-12"] + DAYS["2026-10-14"] + DAYS["2026-10-15"]
)
check("la semaine réunie : le temps inactif des 7 jours", wd.idle_days[overview.WEEK_KEY], 1 * 3600 + 55 * 60)
check(
	"la semaine réunie : un projet de plusieurs jours additionné",
	wd.projects[overview.WEEK_KEY]["Bot Discord"],
	5 * 3600
)
check("la semaine réunie : un projet d'un seul jour", wd.projects[overview.WEEK_KEY].X, 600)
check("la semaine réunie : les jours à l'objectif (8h : le 12, le 14, le 15)", reached, 3)
check("la semaine réunie : les données d'origine ne sont pas touchées", data().days[overview.WEEK_KEY], nil)
local week_text = strip(joined(overview.week_detail(data({ projects = week_projects }), WEEK, 100, 14)))
check("le détail de la semaine : le total des 7 jours", week_text:find("Total  34h35", 1, true) ~= nil, true)
check(
	"le détail de la semaine : les jours à l'objectif (5 par défaut)",
	week_text:find("3/5 jours à l'objectif", 1, true) ~= nil,
	true
)
check("le détail de la semaine : pas l'objectif du jour", week_text:find("objectif 8h", 1, true), nil)
check("le détail de la semaine : le projet additionné", week_text:find("5h00", 1, true) ~= nil, true)
local validated = strip(
	joined(overview.week_detail(data({ cfg = gradient.apply_to({ goal_hours = 8, goal_days = 3 }) }), WEEK, 100, 14))
)
check(
	"le détail de la semaine : semaine validée",
	validated:find("✓ semaine validée (3/3 jours)", 1, true) ~= nil,
	true
)
local week_no_goal = strip(joined(overview.week_detail(data({ cfg = gradient.apply_to({}) }), WEEK, 100, 14)))
check("le détail de la semaine sans objectif : rien sur l'objectif", week_no_goal:find("jours", 1, true), nil)
local empty_week = strip(joined(overview.week_detail(data(), overview.week_keys("2026-10-26", "monday"), 100, 14)))
check("une semaine vide : le dit", empty_week:find(fr.overview_week_empty, 1, true) ~= nil, true)
check("une semaine vide : pas le texte du jour", empty_week:find(fr.detail_empty, 1, true), nil)
local week_en = strip(joined(overview.week_detail(data({ labels = en }), WEEK, 100, 14)))
check("le détail de la semaine en anglais", week_en:find("3/5 days at goal", 1, true) ~= nil, true)
local week_sizes = true
for _, line in ipairs(overview.week_detail(data(), WEEK, 100, 14)) do
	week_sizes = week_sizes and layout.visible_width(line) == 100
end
check("le détail de la semaine : toutes les lignes font la largeur", week_sizes, true)

-- la frise de la semaine
local FULL = { { 0, 24 * 3600, "gros" } }
local wtl = overview.week_timeline(
	data({
		timeline = {
			["2026-10-12"] = FULL,
			["2026-10-15"] = { { 0, 12 * 3600, "gros" } },
			["2026-10-16"] = { { 0, 600, "petit" } },
		},
	}),
	WEEK,
	100
)
check("la frise de la semaine : 4 lignes", #wtl, overview.TIMELINE_HEIGHT)
local wtl_sizes = true
for _, line in ipairs(wtl) do
	wtl_sizes = wtl_sizes and layout.visible_width(line) == 100
end
check("la frise de la semaine : toutes les lignes font la largeur", wtl_sizes, true)
local _, separators = strip(wtl[2]):gsub("┬", "")
check("la frise de la semaine : un trait entre chaque jour", separators, 6)
local _, bottoms = strip(wtl[4]):gsub("┴", "")
check("la frise de la semaine : en bas aussi", bottoms, 6)
check(
	"la frise de la semaine : les noms des jours au-dessus, dans l'ordre",
	strip(wtl[1]):match("Lundi.*Mardi.*Mercredi.*Jeudi.*Vendredi.*Samedi.*Dimanche") ~= nil,
	true
)
local day_parts = {}
for part in strip(wtl[3]):gmatch("[^│]+") do
	day_parts[#day_parts + 1] = part
end
check("la frise de la semaine : 7 parts", #day_parts, 7)
check("la frise de la semaine : le nom dans le jour où il tient", day_parts[1]:find("gros", 1, true) ~= nil, true)
check("la frise de la semaine : un jour vide reste vide", day_parts[2]:match("^ +$") ~= nil, true)
local gros = convert.bg(overview.timeline_colors({ { 0, 1, "gros" }, { 0, 0.5, "petit" } }).gros)
local raw_parts = {}
for part in wtl[3]:gmatch("[^│]+") do
	raw_parts[#raw_parts + 1] = part
end
check(
	"la frise de la semaine : un projet garde sa couleur toute la semaine",
	raw_parts[1]:find(gros, 1, true) ~= nil and raw_parts[4]:find(gros, 1, true) ~= nil,
	true
)
check("la frise de la semaine : la moitié du jeudi seulement", day_parts[4]:sub(-3):match("^ +$") ~= nil, true)

check(
	"la frise de la semaine : le nom du jour centré au-dessus de sa part",
	strip(wtl[1]):match("^   +Lundi") ~= nil,
	true
)
local OTHER = load_module("core/activity").OTHER
local other_tl =
	overview.week_timeline(data({ timeline = { ["2026-10-12"] = { { 0, 24 * 3600, OTHER } } } }), WEEK, 100)
check(
	"la frise de la semaine : « autres » dans la langue choisie (pas « ? »)",
	strip(other_tl[3]):find(fr.detail_other, 1, true) ~= nil,
	true
)
local _, exact = overview.week_data(data({ days = { ["2026-10-12"] = 8 * 3600 } }), WEEK)
check("la semaine réunie : un jour à 8h00 tout juste compte à l'objectif", exact, 1)

-- la case « Semaine N » de la semaine choisie
local ACCENT = "#C96969"
local function week_cell_filled(g, n)
	for _, line in ipairs(g) do
		if strip(line):find("Semaine " .. n, 1, true) then
			return line:find(convert.bg(ACCENT), 1, true) ~= nil
		end
	end
end
local week_grid = overview.grid(data({ week = true, accent = ACCENT }), 100, 30)
check("la semaine choisie : sa case « Semaine 3 » est remplie", week_cell_filled(week_grid, 3), true)
check("la semaine choisie : pas les autres", week_cell_filled(week_grid, 2), false)
check(
	"sans semaine choisie : aucune case remplie",
	week_cell_filled(overview.grid(data({ accent = ACCENT }), 100, 30), 3),
	false
)
check(
	"un jour d'un autre mois : aucune case remplie",
	week_cell_filled(overview.grid(data({ week = true, accent = ACCENT, day_key = "2026-11-12" }), 100, 30), 3),
	false
)
local filled_lines = 0
for _, line in ipairs(week_grid) do
	if line:find(convert.bg(ACCENT), 1, true) then
		filled_lines = filled_lines + 1
	end
end
check("la semaine choisie : toute la hauteur de sa case (sans les traits)", filled_lines, week_height(week_grid) - 1)

local week_view = overview.render(data({ week = true, accent = ACCENT }), 100, 40)
check("toute la vue en semaine : la bonne hauteur", #week_view, 40)
local week_view_text = strip(joined(week_view))
check(
	"toute la vue en semaine : le détail de la semaine",
	week_view_text:find("3/5 jours à l'objectif", 1, true) ~= nil,
	true
)
check(
	"toute la vue en semaine : la frise reste celle du jour",
	strip(week_view[#week_view - 3]):find("24h00", 1, true) ~= nil,
	true
)

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
