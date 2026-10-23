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

-- ---- la frise
local palette = load_module("color/palette")
local SEGS = { { 9 * 3600, 10 * 3600, "petit" }, { 10 * 3600, 14 * 3600, "gros" }, { 15 * 3600, 15 * 3600 + 600, "?" } }
-- (les couleurs viennent de calendar/board.lua : board.project_colors)
local colors = { gros = palette.COLORS[overview.TIMELINE_ORDER[1]], petit = palette.COLORS[overview.TIMELINE_ORDER[2]] }
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
local tl = overview.timeline(data({ timeline = { ["2026-10-15"] = SEGS } }), "2026-10-15", 98, colors)
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
check("un projet sans couleur (« ? ») : gris", tl[3]:find(convert.bg(overview.OTHER_COLOR), 1, true) ~= nil, true)
check(
	"sans couleurs du tout : tout en gris, sans erreur",
	overview
		.timeline(data({ timeline = { ["2026-10-15"] = SEGS } }), "2026-10-15", 98)[3]
		:find(convert.bg(overview.OTHER_COLOR), 1, true) ~= nil,
	true
)

-- ---- le texte de l'objectif du jour
check("objectif atteint", overview.goal_text(data(), "2026-10-12", 9 * 3600), "✓ objectif 8h atteint")
check(
	"objectif pas atteint aujourd'hui : ce qu'il manque",
	overview.goal_text(data(), "2026-10-15", 6 * 3600),
	"objectif 8h : il manque 2h00"
)
check(
	"objectif pas atteint un jour passé : manqué",
	overview.goal_text(data(), "2026-10-10", 6 * 3600),
	"objectif 8h non atteint (−2h00)"
)
check("pile l'objectif (8h00) : atteint", overview.goal_text(data(), "2026-10-10", 8 * 3600), "✓ objectif 8h atteint")
check("sans objectif : rien", overview.goal_text(data({ cfg = gradient.apply_to({}) }), "2026-10-10", 3600), "")

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
local _, exact = overview.week_data(data({ days = { ["2026-10-12"] = 8 * 3600 } }), WEEK)
check("la semaine réunie : un jour à 8h00 tout juste compte à l'objectif", exact, 1)

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
