-- tests/calendar/test_year.lua : teste calendar/year.lua (la vue de l'année). Lancer :   lua5.4 tests/calendar/test_year.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]calendar[/\\]test_year%.lua$") or "."

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
local year = load_module("calendar/year")
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
-- la position (en caractères) d'un texte dans une ligne
local function col_of(line, text)
	local at = line:find(text, 1, true)
	return at and utf8.len(line:sub(1, at - 1)) + 1 or nil
end

-- ---- le nombre de colonnes (semaines)
check("2026 commence un jeudi : 3 + 365 jours = 53 semaines", year.columns(2026, "monday"), 53)
check("2026, semaine du dimanche : 4 + 365 = 53 semaines", year.columns(2026, "sunday"), 53)
check("2028 (bissextile) commence un samedi : 5 + 366 = 53 semaines", year.columns(2028, "monday"), 53)
check("2033 commence un samedi, semaine du dimanche : 6 + 365 = 53", year.columns(2033, "sunday"), 53)
check("2034 commence un dimanche, semaine du lundi : 6 + 365 = 53", year.columns(2034, "monday"), 53)
check("2040 (bissextile) commence un dimanche, semaine du lundi : 6 + 366 = 54", year.columns(2040, "monday"), 54)

-- ---- le dessin
local days = {
	["2026-01-01"] = 3600,
	["2026-03-12"] = 9 * 3600 + 1800,
	["2026-10-12"] = 4 * 3600,
	["2026-10-13"] = 1800,
	["2025-12-29"] = 8 * 3600, -- l'année d'avant : dans la 1re semaine (lundi 29 décembre), pas dans les statistiques
}
local cfg = gradient.apply_to({})
local lines, width = year.render(days, 2026, "2026-10-13", cfg, fr)
local p = plain(lines)
check("sans objectif : 12 lignes", #lines, 12)
check("largeur : 2 + 5 + 53 x 2 = 113", width, 113)
check("ligne 1 : le titre", p[1], "  2026   Total de l'année : 15h00 / Jours actifs : 4")
check("ligne 4 : les lundis", p[4]:sub(1, 7), "  Lun  ")
check("ligne 10 : les dimanches", p[10]:sub(1, 7), "  Dim  ")
check("le 1er janvier 2026 est un jeudi : la 1re colonne commence au jeudi", p[7]:sub(8, 8 + #"■" - 1), "■")
check("lundi 29 décembre 2025 (l'année d'avant) : une case vide", p[4]:sub(8, 9), "  ")
check(
	"chaque ligne des jours tient dans la largeur",
	(function()
		for i = 4, 10 do
			if utf8.len(p[i]) > width then
				return i
			end
		end
		return true
	end)(),
	true
)
check("Jan au-dessus de la 1re semaine", col_of(p[3], "Jan"), 8)
check(
	"Avr au-dessus de la semaine du 1er avril (le lundi 30 mars : colonne 14, le décalage du 1er janvier compte)",
	col_of(p[3], "Avr"),
	8 + (14 - 1) * 2
)
check("Juin et Juil distincts", p[3]:find("Juin", 1, true) ~= nil and p[3]:find("Juil", 1, true) ~= nil, true)
check("Oct au-dessus de la semaine du 1er octobre (colonne 40)", col_of(p[3], "Oct"), 8 + (40 - 1) * 2)
check(
	"les 12 mois sont nommés",
	(function()
		for _, m in ipairs(fr.months_short) do
			if not p[3]:find(m, 1, true) then
				return m
			end
		end
		return true
	end)(),
	true
)
check("aujourd'hui (mardi 13 octobre) : ◆ sur la ligne des mardis", p[5]:find("◆", 1, true) ~= nil, true)
check("un seul ◆", select(2, table.concat(p, "\n"):gsub("◆", "")), 1)
local raw = table.concat(lines, "\n")
check(
	"le 12 mars (9h30) a la couleur du calendrier",
	raw:find(convert.fg(assemble.day_color(9 * 3600 + 1800, cfg)) .. "■", 1, true) ~= nil,
	true
)
check("un jour sans travail : le gris foncé", raw:find(convert.fg(year.EMPTY_COLOR) .. "■", 1, true) ~= nil, true)
check("ligne 12 : moyenne et meilleur jour", p[12], "  Moyenne par jour actif : 3h45   Meilleur jour : 12 mars (9h30)")
check("sans objectif : pas de ligne « validées »", table.concat(p, "\n"):find("validé", 1, true), nil)

-- ---- le temps inactif
local idle_days = {
	["2026-03-12"] = 3600, -- 1 h sur 9h30
	["2026-10-13"] = 99999, -- plus que le temps du jour (0h30) : seulement 0h30
	["2025-12-29"] = 3600, -- l'année d'avant : ne compte pas
}
local ip = plain((year.render(days, 2026, "2026-10-13", cfg, fr, idle_days)))
check(
	"inactif : 1h30 sur 15h00 = 10 %",
	ip[12],
	"  Moyenne par jour actif : 3h45   Meilleur jour : 12 mars (9h30)   Inactif : 1h30 (10 %)"
)
check("inactif : year_stats", year.year_stats(days, 2026, cfg, idle_days).idle, 5400)
check(
	"inactif : sans temps inactif connu, 0h00",
	plain((year.render(days, 2026, "x", cfg, fr, {})))[12]:match("Inactif.*$"),
	"Inactif : 0h00 (0 %)"
)
check(
	"inactif : année vide, pas de ligne inactif",
	plain((year.render({}, 2026, "x", cfg, fr, idle_days)))[12]:find("Inactif", 1, true),
	nil
)
check(
	"inactif : anglais",
	plain((year.render(days, 2026, "x", cfg, en, idle_days)))[12]:match("Idle.*$"),
	"Idle: 1h30 (10%)"
)
check(
	"inactif : la ligne tient dans la largeur",
	utf8.len(ip[12]) <= select(2, year.render(days, 2026, "x", cfg, fr, idle_days)),
	true
)

-- ---- les statistiques de l'année
local s = year.year_stats(days, 2026, cfg)
check(
	"year_stats : total sans l'année d'avant (1h + 9h30 + 4h + 0h30, pas les 8 h du 29 décembre 2025)",
	s.total,
	15 * 3600
)
check("year_stats : jours actifs", s.active, 4)
check("year_stats : 365 jours", s.days, 365)
check("year_stats : 2028, 366 jours", year.year_stats({}, 2028, cfg).days, 366)
check("year_stats : meilleur jour", s.best_key, "2026-03-12")
check("year_stats : année vide, pas de meilleur jour", year.year_stats({}, 2026, cfg).best_key, nil)
-- les semaines validées (objectif 3 h, 4 jours par semaine)
local week = {}
for d = 5, 8 do
	week[string.format("2026-10-%02d", d)] = 4 * 3600
end
week["2025-12-29"], week["2025-12-30"], week["2025-12-31"], week["2026-01-01"] = 4 * 3600, 4 * 3600, 4 * 3600, 4 * 3600
local goal_cfg = gradient.apply_to({ goal_hours = 3, goal_days = 4 })
local gs = year.year_stats(week, 2026, goal_cfg)
check(
	"semaines validées : celle du 5 octobre, et la 1re (à cheval sur 2025 : ses 7 jours comptent)",
	gs.validated_weeks,
	2
)
check("semaines : 53", gs.weeks, 53)
check("jours validés : seulement ceux de 2026 (5 : le 1er janvier et 4 en octobre)", gs.goal_days, 5)
local goal_lines = plain((year.render(week, 2026, "x", goal_cfg, fr)))
check("avec un objectif : 13 lignes", #goal_lines, 13)
check(
	"avec un objectif : la ligne des validés",
	goal_lines[13],
	"  Semaines validées : 2/53 / Jours validés : 5/365"
)
check(
	"objectif 0 (aucun) : pas de ligne « validées »",
	#year.render(week, 2026, "x", gradient.apply_to({ goal_hours = 0 }), fr),
	12
)

-- ---- semaine du dimanche
local sun = plain((year.render(days, 2026, "x", gradient.apply_to({ week_starts_on = "sunday" }), fr)))
check("semaine du dimanche : la 1re ligne est Dim", sun[4]:sub(1, 7), "  Dim  ")
check("semaine du dimanche : la dernière est Sam", sun[10]:sub(1, 7), "  Sam  ")

-- ---- anglais
local eng = plain((year.render(days, 2026, "x", cfg, en)))
check("anglais : le titre", eng[1], "  2026   Year total: 15h00 / Active days: 4")
check("anglais : Jun et Jul", eng[3]:find("Jun", 1, true) ~= nil and eng[3]:find("Jul", 1, true) ~= nil, true)
check("anglais : les jours", eng[4]:sub(1, 7), "  Mon  ")
check(
	"anglais : le meilleur jour, le mois puis le jour",
	table.concat(eng, "\n"):find("Best day: March 12 (9h30)", 1, true) ~= nil,
	true
)
check("anglais : jamais d'espace avant les deux-points", table.concat(eng, "\n"):find(" :", 1, true), nil)

-- ---- avec les encadrés
local boxed, boxed_width =
	year.render(week, 2026, "x", gradient.apply_to({ borders = true, goal_hours = 3, goal_days = 4 }), fr)
local bp = plain(boxed)
check("encadrés : 12 lignes (le titre et les validés sur les traits)", #boxed, 12)
check("encadrés : largeur 116 (tient dans 120 colonnes)", boxed_width, 116)
check("encadrés : le titre sur le haut", bp[1]:find(" ╭─ 2026   Total de l'année", 1, true), 1)
check(
	"encadrés : les validés sur le bas",
	bp[12]:find(" ╰─ Semaines validées : 2/53 / Jours validés : 5/365 ─", 1, true),
	1
)
check(
	"encadrés : chaque ligne fait la même largeur",
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
check(
	"encadrés : les traits dans leur couleur",
	boxed[1]:find(convert.fg(assemble.BORDER_COLOR) .. "╭", 1, true) ~= nil,
	true
)
check(
	"encadrés : le style double",
	plain(year.render({}, 2026, "x", gradient.apply_to({ borders = true, border_style = "double" }), fr))[1]:sub(1, 4),
	" ╔"
)
check(
	"encadrés sans objectif : le bas sans texte",
	plain(year.render({}, 2026, "x", gradient.apply_to({ borders = true }), fr))[12]:find("─ ", 1, true),
	nil
)

-- ---- toutes les années de 2020 à 2045 tiennent dans 120 colonnes, encadrées ou non
check(
	"2020 à 2045 : au plus 120 colonnes",
	(function()
		for y = 2020, 2045 do
			for _, c in ipairs({ {}, { borders = true }, { week_starts_on = "sunday", borders = true } }) do
				local ls, wd = year.render({}, y, "x", gradient.apply_to(c), fr)
				if wd > 120 then
					return y .. " : " .. wd
				end
				for _, l in ipairs(ls) do
					if utf8.len(strip(l)) > wd then
						return y .. " ligne trop longue"
					end
				end
			end
		end
		return true
	end)(),
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
