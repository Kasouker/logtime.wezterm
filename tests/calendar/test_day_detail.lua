-- tests/calendar/test_day_detail.lua : teste calendar/day_detail.lua (le détail d'un jour).
-- Lancer :   lua5.4 tests/calendar/test_day_detail.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]calendar[/\\]test_day_detail%.lua$") or "."

local globals_before = {}
for k in pairs(_G) do
	globals_before[k] = true
end

local cache = {}
local function load_module(name)
	if not cache[name] then
		local chunk = assert(loadfile(root .. "/plugin/logtime/" .. name .. ".lua"))
		cache[name] = chunk(load_module)
	end
	return cache[name]
end
local detail = load_module("calendar/day_detail")
local assemble = load_module("calendar/assemble")
local convert = load_module("color/convert")
local gradient = load_module("color/gradient")
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
local function plain(lines)
	local out = {}
	for i, l in ipairs(lines) do
		out[i] = strip(l)
	end
	return out
end

-- ---- le titre
check("titre : mercredi", detail.title("2026-10-14", fr), "Mercredi 14 octobre 2026")
check(
	"titre : dimanche (le 7e de la liste, qui commence au lundi)",
	detail.title("2026-10-18", fr),
	"Dimanche 18 octobre 2026"
)
check("titre : lundi", detail.title("2026-10-19", fr), "Lundi 19 octobre 2026")
check("titre : samedi", detail.title("2026-10-17", fr), "Samedi 17 octobre 2026")
check("titre : les accents gardés", detail.title("2026-08-01", fr), "Samedi 1 août 2026")
check("titre : février", detail.title("2028-02-29", fr), "Mardi 29 février 2028")
check("titre : anglais", detail.title("2026-10-14", en), "Wednesday, October 14, 2026")

-- ---- la semaine du jour
local days = {
	["2026-09-28"] = 9 * 3600, -- lundi, en septembre : dans la semaine du jeudi 1er octobre
	["2026-10-01"] = 8 * 3600,
	["2026-10-04"] = 3600, -- dimanche
	["2026-10-05"] = 99999, -- lundi de la semaine suivante
}
local monday = gradient.apply_to({ goal_hours = 8 })
local total, reached = detail.week(days, "2026-10-01", monday)
check("semaine du lundi : avec le lundi de septembre", total, 18 * 3600)
check("semaine du lundi : deux jours à l'objectif", reached, 2)
check("semaine du lundi : depuis le dimanche, la même", (detail.week(days, "2026-10-04", monday)), 18 * 3600)
check("semaine du lundi : le lundi d'après, une autre", (detail.week(days, "2026-10-05", monday)), 99999)
local sunday = gradient.apply_to({ goal_hours = 8, week_starts_on = "sunday" })
check(
	"semaine du dimanche : le dimanche 4 commence une nouvelle semaine",
	(detail.week(days, "2026-10-04", sunday)),
	3600 + 99999
)
check(
	"semaine du dimanche : jeudi 1er, du dimanche 27 au samedi 3",
	(detail.week(days, "2026-10-01", sunday)),
	17 * 3600
)
check(
	"semaine : sans objectif, aucun jour compté",
	select(2, detail.week(days, "2026-10-01", gradient.apply_to({}))),
	0
)

-- ---- le détail
local week = {
	["2026-10-12"] = 8 * 3600 + 720,
	["2026-10-13"] = 6 * 3600,
	["2026-10-14"] = 36240,
}
local idle = { ["2026-10-14"] = 5400, ["2026-10-13"] = 99999 }
local cfg = gradient.apply_to({ goal_hours = 8, goal_days = 5 })
local lines, width = detail.render(week, idle, "2026-10-14", "2026-10-14", cfg, fr)
local p = plain(lines)
check("aujourd'hui : le titre", p[1], "  Mercredi 14 octobre 2026 · aujourd'hui")
check("ligne vide sous le titre", p[2], "")
check("total et objectif atteint", p[3], "  Total     10h04   ✓ objectif 8h atteint")
check(
	"actif : 10h04 - 1h30 = 8h34, 85 %",
	p[4],
	"  Actif      8h34   █████████████████░░░   85 %"
)
check(
	"inactif : 1h30, 15 %",
	p[5],
	"  Inactif    1h30   ███░░░░░░░░░░░░░░░░░   15 %"
)
check("ligne vide", p[6], "")
check("la semaine : 8h12 + 6h00 + 10h04", p[7], "  Semaine   24h16   2/5 jours à l'objectif")
check("7 lignes", #p, 7)
check("largeur : la plus longue ligne, au moins 46 + 2", width, 48)
local raw = table.concat(lines, "\n")
check(
	"la barre active a la couleur du jour dans le calendrier",
	raw:find(convert.fg(assemble.day_color(36240, cfg)) .. "█", 1, true) ~= nil,
	true
)
check(
	"la barre inactive en gris",
	raw:find(convert.fg(detail.IDLE_COLOR) .. "███" .. convert.fg(detail.BAR_EMPTY_COLOR), 1, true) ~= nil,
	true
)

p = plain((detail.render(week, idle, "2026-10-13", "2026-10-14", cfg, fr)))
check("jour passé : pas de « aujourd'hui »", p[1], "  Mardi 13 octobre 2026")
check("jour passé, objectif pas atteint : non atteint", p[3], "  Total      6h00   objectif 8h non atteint (−2h00)")
check(
	"inactif plus grand que le jour : ramené au jour (6h00, 100 %)",
	p[5],
	"  Inactif    6h00   ████████████████████  100 %"
)
check(
	"actif : 0h00, 0 %",
	p[4],
	"  Actif      0h00   ░░░░░░░░░░░░░░░░░░░░    0 %"
)
p = plain((detail.render({ ["2026-10-14"] = 3600 }, nil, "2026-10-14", "2026-10-14", cfg, fr)))
check("aujourd'hui, pas encore atteint : il manque", p[3], "  Total      1h00   objectif 8h : il manque 7h00")
check(
	"sans temps inactif connu : tout est actif",
	p[4],
	"  Actif      1h00   ████████████████████  100 %"
)
p = plain((detail.render({ ["2026-10-13"] = 8 * 3600 }, nil, "2026-10-13", "2026-10-14", cfg, fr)))
check("objectif atteint pile (8h00) : atteint", p[3], "  Total      8h00   ✓ objectif 8h atteint")
p = plain((detail.render({}, nil, "2026-10-20", "2026-10-14", cfg, fr)))
check("jour à venir, vide : il manque tout", p[3], "  Total      0h00   objectif 8h : il manque 8h00")
check("jour vide : le message", p[4], "  Aucun temps compté ce jour-là.")
check("jour vide : 6 lignes", #p, 6)
p = plain((detail.render(week, idle, "2026-10-14", "2026-10-14", gradient.apply_to({}), fr)))
check("sans objectif : juste le total", p[3], "  Total     10h04")
check("sans objectif : juste le total de la semaine", p[7], "  Semaine   24h16")
p = plain((detail.render(week, idle, "2026-10-14", "x", gradient.apply_to({ goal_hours = 7.5, goal_days = 2 }), en)))
check("anglais : objectif 7h30", p[3], "  Total     10h04   ✓ 7h30 goal reached")
check("anglais : semaine validée", p[7], "  Week      24h16   ✓ week validated (2/2 days)")
check("anglais : idle", p[5]:sub(1, 10), "  Idle    ")
check("anglais : le pourcentage collé au nombre (83%)", p[4]:match("%d%%$") ~= nil and p[4]:find(" %%$") == nil, true)
local p_fr = plain((detail.render(week, idle, "2026-10-14", "x", gradient.apply_to({}), fr)))
check("français : le pourcentage garde son espace (85 %)", p_fr[4]:find("%d %%$") ~= nil, true)

-- ---- par projet
local projects = {
	["2026-10-14"] = {
		["Projet_Perso/logtime.wezterm"] = 4 * 3600 + 600,
		["42/C05"] = 3 * 3600,
		["un nom de projet beaucoup trop long pour la colonne"] = 1200,
		logtime = 300,
		["?"] = 200,
		["a/b"] = 100,
		["c/d"] = 40,
	},
}
local pp = plain((detail.render(week, idle, "2026-10-14", "2026-10-14", cfg, fr, projects)))
check("projets : après l'inactif, une ligne vide", pp[6], "")
check("projets : le titre", pp[7], "  Par projet (temps actif)")
check(
	"projets : le plus grand d'abord, sa part du total du jour (4h10 sur 10h04 = 41 %)",
	pp[8],
	"    Projet_Perso/logtime.wezterm    4h10   █████░░░░░░░   41 %"
)
check(
	"projets : le suivant",
	pp[9],
	"    42/C05                          3h00   ████░░░░░░░░   30 %"
)
check("projets : un nom trop long est coupé", pp[10]:find("    un nom de projet beaucoup tr… ", 1, true), 1)
check("projets : coupé avec …", pp[10]:find("…", 1, true) ~= nil, true)
check(
	"projets : 5 projets, puis « autres » (le reste et l'inconnu : 40 s + 200 s)",
	pp[13],
	"    autres                          0h04   ░░░░░░░░░░░░    1 %"
)
check("projets : puis la semaine", pp[15], "  Semaine   24h16   2/5 jours à l'objectif")
check("projets : 15 lignes", #pp, 15)
check(
	"projets : la barre a la couleur du jour",
	table.concat(detail.render(week, idle, "2026-10-14", "x", cfg, fr, projects), "\n"):find(
		convert.fg(assemble.day_color(36240, cfg)) .. "█████" .. convert.fg(detail.BAR_EMPTY_COLOR),
		1,
		true
	) ~= nil,
	true
)
check(
	"projets : un autre jour sans projets, pas de section",
	#plain((detail.render(week, idle, "2026-10-13", "2026-10-14", cfg, fr, projects))),
	7
)
check(
	"projets : un jour sans temps compté, pas de section (même avec des projets)",
	table
		.concat(plain((detail.render({}, nil, "2026-10-14", "x", cfg, fr, projects))), "\n")
		:find("Par projet", 1, true),
	nil
)
check(
	"projets : un projet plus grand que le jour (fichiers fusionnés) : 100 % au plus",
	plain((detail.render({ ["2026-10-14"] = 60 }, nil, "2026-10-14", "x", cfg, fr, { ["2026-10-14"] = { a = 999 } })))[8],
	"    a                               0h01   ████████████  100 %"
)
-- moins d'une minute s'afficherait « 0h00 » : la ligne est cachée (« autres » comme un petit projet)
local small = plain((detail.render(week, idle, "2026-10-14", "x", cfg, fr, {
	["2026-10-14"] = { gros = 3600, petit = 59, ["?"] = 30 },
})))
local small_text = table.concat(small, "\n")
check("moins d'une minute : le gros projet est affiché", small_text:find("    gros ", 1, true) ~= nil, true)
check("moins d'une minute : le petit projet (59 s) est caché", small_text:find("petit", 1, true), nil)
check("moins d'une minute : « autres » (30 s) est caché", small_text:find("autres", 1, true), nil)
check("moins d'une minute : aucune ligne à 0h00 dans la section", small_text:find("0h00   ", 1, true), nil)
check(
	"une minute pile : affichée (0h01)",
	table
		.concat(plain((detail.render(week, idle, "2026-10-14", "x", cfg, fr, { ["2026-10-14"] = { pile = 60 } }))), "\n")
		:find("    pile ", 1, true) ~= nil,
	true
)
check(
	"que des projets de moins d'une minute : pas de section du tout",
	table
		.concat(
			plain((detail.render(week, idle, "2026-10-14", "x", cfg, fr, { ["2026-10-14"] = { a = 10, ["?"] = 5 } }))),
			"\n"
		)
		:find("Par projet", 1, true),
	nil
)
local pe = plain((detail.render(week, idle, "2026-10-14", "x", cfg, en, projects)))
check("projets : anglais", pe[7], "  By project (active time)")
check("projets : anglais, autres", pe[13]:sub(1, 10), "    others")
local framed =
	plain((detail.render(week, idle, "2026-10-14", "x", gradient.apply_to({ borders = true }), fr, projects)))
check(
	"projets encadrés : chaque ligne de la même largeur",
	(function()
		for i, l in ipairs(framed) do
			if utf8.len(l) ~= utf8.len(framed[1]) then
				return i
			end
		end
		return true
	end)(),
	true
)

-- ---- avec les encadrés
local boxed, boxed_width =
	detail.render(week, idle, "2026-10-14", "2026-10-14", gradient.apply_to({ borders = true, goal_hours = 8 }), fr)
local bp = plain(boxed)
check("encadré : le titre sur le haut", bp[1]:find("╭─ Mercredi 14 octobre 2026 · aujourd'hui ─", 1, true), 1)
check("encadré : 7 lignes (le haut avec le titre, 5 lignes, le bas)", #bp, 7)
check("encadré : le bas", bp[7]:sub(1, #"╰─"), "╰─")
check("encadré : le contenu", bp[2], "│ Total     10h04   ✓ objectif 8h atteint        │")
check(
	"encadré : chaque ligne de la même largeur",
	(function()
		for i, l in ipairs(bp) do
			if utf8.len(l) ~= boxed_width then
				return i .. " : " .. utf8.len(l)
			end
		end
		return true
	end)(),
	true
)
check("encadré : les traits dans leur couleur", boxed[1]:find(convert.fg(assemble.BORDER_COLOR) .. "╭", 1, true), 1)
check(
	"encadré : le style double",
	plain(detail.render({}, nil, "2026-10-14", "x", gradient.apply_to({ borders = true, border_style = "double" }), fr))[1]:sub(
		1,
		#"╔═"
	),
	"╔═"
)
-- le titre réel le plus long tient dans la largeur minimum ; un titre plus long (une autre langue) élargit le cadre
local long_labels = setmetatable({ detail_today = "a very very long word for today" }, { __index = en })
local long =
	plain(detail.render({}, nil, "2026-09-30", "2026-09-30", gradient.apply_to({ borders = true }), long_labels))
check(
	"titre trop long : il tient dans le cadre",
	long[1]:find("Wednesday, September 30, 2026 · a very very long word for today ───╮", 1, true) ~= nil
		and utf8.len(long[1]) == utf8.len(long[2]),
	true
)
check(
	"le titre réel le plus long tient dans la largeur minimum",
	utf8.len(detail.title("2026-09-30", fr) .. " · " .. fr.detail_today) + 4 <= detail.MIN_WIDTH,
	true
)

local leaked = {}
for k in pairs(_G) do
	if not globals_before[k] then
		leaked[#leaked + 1] = k
	end
end
check("aucune variable globale ajoutée", table.concat(leaked, ","), "")

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
