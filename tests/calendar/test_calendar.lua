-- tests/calendar/test_calendar.lua : teste color/convert.lua, calendar/dates.lua, calendar/stats.lua et calendar/assemble.lua.
-- Aucune dépendance à WezTerm. Lancer :   lua5.4 tests/calendar/test_calendar.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]calendar[/\\]test_calendar%.lua$") or "."

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
local convert = load_module("color/convert")
local dates = load_module("calendar/dates")
local stats = load_module("calendar/stats")
local assemble = load_module("calendar/assemble")
local fr = load_module("i18n/fr")
local en = load_module("i18n/en")

local passed, failed = 0, 0
local function check(name, got, want)
	if got == want then
		passed = passed + 1
	else
		failed = failed + 1
		print(string.format("ÉCHEC  %s\n         attendu : %s\n         obtenu  : %s", name, tostring(want), tostring(got)))
	end
end

local function strip(text)
	return (text:gsub("\27%[[%d;]*m", ""))
end
local function lines_of(text)
	local out = {}
	for line in (text .. "\n"):gmatch("(.-)\n") do
		out[#out + 1] = line
	end
	return out
end
local function render(days, y, m, today, cfg, labels)
	return assemble.render_month(days, y, m, today, cfg or {}, labels or fr)
end

-- Sous-chaîne par CARACTÈRES (le point médian « · » fait deux octets : couper par octets décalerait les colonnes)
local function usub(s, i, j)
	local a = utf8.offset(s, i)
	if not a then
		return ""
	end
	local b = utf8.offset(s, j + 1)
	if not b then
		return s:sub(a)
	end
	return s:sub(a, b - 1)
end

-- Lit la grille d'un mois rendu : une liste de semaines, chaque semaine = 7 cases { day, star, text }.
local function grid(text)
local lines = lines_of(strip(text))
local weeks = {}
local i = 5 -- ligne 1 vide, 2 titre, 3 vide, 4 en-tête, puis les semaines par trois lignes (nombres, durées, vide)
while lines[i] and lines[i + 1] and lines[i]:match("%d") and not lines[i]:find(":", 1, true) do
local week = {}
for col = 1, 7 do
local top = usub(lines[i], 3 + (col - 1) * 9, 2 + col * 9)
local bottom = usub(lines[i + 1], 3 + (col - 1) * 9, 2 + col * 9)
local star, num = top:match("^(%*?)%s*(%d+)")
week[col] = { day = num and tonumber(num) or nil, star = star == "*", text = bottom:match("^%s*(.-)%s*$") }
end
weeks[#weeks + 1] = week
i = i + 3
end
return weeks
end
local function day_numbers(week)
local out = {}
for col = 1, 7 do
out[col] = week[col].day or "."
end
return table.concat(out, ",")
end
local function width(line)
return utf8.len(strip(line))
end

-- ============================================================
-- color/convert.lua
-- ============================================================
local r, g, b = convert.rgb("#C9AB6B")
check("rgb : #C9AB6B", r .. "," .. g .. "," .. b, "201,171,107")
r, g, b = convert.rgb("c9ab6b")
check("rgb : sans dièse et en minuscules", r .. "," .. g .. "," .. b, "201,171,107")
for _, bad in ipairs({ "zzzzzz", "#12345", "#1234567", "", "rouge" }) do
r, g, b = convert.rgb(bad)
check("rgb : code invalide « " .. bad .. " » = blanc", r .. "," .. g .. "," .. b, "255,255,255")
end
r, g, b = convert.rgb(nil)
check("rgb : nil = blanc", r .. "," .. g .. "," .. b, "255,255,255")
check("fg : séquence exacte", convert.fg("#C9AB6B"), "\27[38;2;201;171;107m")
check("bg : séquence exacte", convert.bg("#C9AB6B"), "\27[48;2;201;171;107m")
check("RESET", convert.RESET, "\27[0m")
check("contrast : fond blanc, texte sombre", convert.contrast("#FFFFFF"), "#17191F")
check("contrast : fond noir, texte clair", convert.contrast("#000000"), "#ECE6D9")
check("contrast : fond doré (clair), texte sombre", convert.contrast("#C9AB6B"), "#17191F")
check("contrast : fond bronze (sombre), texte clair", convert.contrast("#8C7A4A"), "#ECE6D9")

-- ============================================================
-- calendar/dates.lua
-- ============================================================
check("key : zéros ajoutés", dates.key(2026, 3, 5), "2026-03-05")
check("key : date à deux chiffres", dates.key(2026, 12, 31), "2026-12-31")
local expected_len = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
for m = 1, 12 do
check("days_in_month 2026-" .. m, dates.days_in_month(2026, m), expected_len[m])
end
check("février 2024 (bissextile)", dates.days_in_month(2024, 2), 29)
check("février 2028 (bissextile)", dates.days_in_month(2028, 2), 29)
check("février 2000 (bissextile : divisible par 400)", dates.days_in_month(2000, 2), 29)
check("février 2100 (pas bissextile : divisible par 100)", dates.days_in_month(2100, 2), 28)
check("décembre : le mois suivant est bien l'année d'après", dates.days_in_month(2026, 12), 31)
check("first_wday : octobre 2026 commence un jeudi", dates.first_wday(2026, 10), 5)
check("first_wday : février 2026 commence un dimanche", dates.first_wday(2026, 2), 1)
check("first_wday : février 2028 commence un mardi", dates.first_wday(2028, 2), 3)
check("first_wday : janvier 2024 commence un lundi", dates.first_wday(2024, 1), 2)
check("offset lundi : octobre 2026", dates.offset(2026, 10, "monday"), 3)
check("offset lundi : février 2026 (dimanche)", dates.offset(2026, 2, "monday"), 6)
check("offset lundi : janvier 2024 (lundi)", dates.offset(2024, 1, "monday"), 0)
check("offset par défaut : lundi", dates.offset(2026, 10), 3)
check("offset dimanche : octobre 2026", dates.offset(2026, 10, "sunday"), 4)
check("offset dimanche : février 2026 (dimanche)", dates.offset(2026, 2, "sunday"), 0)

-- ============================================================
-- calendar/stats.lua
-- ============================================================
check("hm : zéro", stats.hm(0), "0h00")
check("hm : 59 s", stats.hm(59), "0h00")
check("hm : 60 s", stats.hm(60), "0h01")
check("hm : 1 h", stats.hm(3600), "1h00")
check("hm : 25020 s", stats.hm(25020), "6h57")
check("hm : 4h13 du 10 octobre", stats.hm(15231), "4h13")
check("hm : valeur négative", stats.hm(-100), "0h00")
check("hm : plus de 99 h", stats.hm(360000), "100h00")
check("hm : décimales ignorées", stats.hm(3661.9), "1h01")

local function streak(days, today)
return stats.streak(days, today)
end
check("série : 3 jours dont aujourd'hui", streak({ ["2026-10-10"] = 5, ["2026-10-11"] = 5, ["2026-10-12"] = 5 }, "2026-10-12"), 3)
check("série : rien aujourd'hui, on part d'hier", streak({ ["2026-10-10"] = 5, ["2026-10-11"] = 5 }, "2026-10-12"), 2)
check("série : un trou interrompt la série", streak({ ["2026-10-09"] = 5, ["2026-10-11"] = 5, ["2026-10-12"] = 5 }, "2026-10-12"), 2)
check("série : un jour à zéro interrompt la série", streak({ ["2026-10-10"] = 5, ["2026-10-11"] = 0, ["2026-10-12"] = 5 }, "2026-10-12"), 1)
check("série : aucun historique", streak({}, "2026-10-12"), 0)
check("série : hier vide et aujourd'hui vide", streak({ ["2026-10-09"] = 5 }, "2026-10-12"), 0)
check("série : à cheval sur deux années", streak({ ["2026-12-31"] = 5, ["2027-01-01"] = 5, ["2027-01-02"] = 5 }, "2027-01-02"), 3)
check("série : à cheval sur deux mois", streak({ ["2026-09-30"] = 5, ["2026-10-01"] = 5 }, "2026-10-01"), 2)
check("série : clé de date invalide", streak({}, "n'importe quoi"), 0)
check("série : clé nil", streak({}, nil), 0)

local oct = { ["2026-10-10"] = 15231, ["2026-10-11"] = 1900, ["2026-10-12"] = 3600, ["2026-09-30"] = 99999, ["2026-11-01"] = 99999 }
local s = stats.month_stats(oct, 2026, 10)
check("month_stats : total (septembre et novembre ignorés)", s.total, 15231 + 1900 + 3600)
check("month_stats : jours actifs", s.active, 3)
check("month_stats : moyenne", math.floor(s.average), math.floor((15231 + 1900 + 3600) / 3))
check("month_stats : meilleur jour", s.best_day, 10)
check("month_stats : durée du meilleur jour", s.best_secs, 15231)
check("month_stats : sans objectif, 0 jour", s.goal_days, 0)
check("month_stats : objectif de 3 h atteint 1 jour", stats.month_stats(oct, 2026, 10, 3).goal_days, 1)
check("month_stats : objectif de 1 h atteint 2 jours", stats.month_stats(oct, 2026, 10, 1).goal_days, 2)
check("month_stats : objectif de 0,5 h atteint 3 jours", stats.month_stats(oct, 2026, 10, 0.5).goal_days, 3)
s = stats.month_stats({}, 2026, 10)
check("month_stats : mois vide, total", s.total, 0)
check("month_stats : mois vide, moyenne", s.average, 0)
check("month_stats : mois vide, pas de meilleur jour", s.best_day, nil)
s = stats.month_stats({ ["2028-02-29"] = 600 }, 2028, 2)
check("month_stats : le 29 février bissextile est compté", s.total, 600)
s = stats.month_stats({ ["2026-10-05"] = -500, ["2026-10-06"] = 100.9 }, 2026, 10)
check("month_stats : valeur négative ignorée, décimales arrondies vers le bas", s.total, 100)

-- ============================================================
-- calendar/assemble.lua : la structure
-- ============================================================
local days = { ["2026-10-10"] = 15231, ["2026-10-11"] = 1900, ["2026-10-12"] = 3600 }
local text = render(days, 2026, 10, "2026-10-12")
local lines = lines_of(strip(text))
check("première ligne vide", lines[1], "")
check("titre, avec le total et les jours actifs", lines[2], "  Logtime : Octobre 2026   Total du mois : 5h45 / Jours actifs : 3")
check("en-tête : commence par Lun", lines[4]:match("^%s*(%a+)"), "Lun")
check("en-tête : sept jours dans l'ordre", table.concat({ lines[4]:match("(%a+)%s+(%a+)%s+(%a+)%s+(%a+)%s+(%a+)%s+(%a+)%s+(%a+)") }, ","), "Lun,Mar,Mer,Jeu,Ven,Sam,Dim")
check("largeur de l'en-tête", width(lines[4]), assemble.WIDTH)

local weeks = grid(text)
check("octobre 2026 : 5 semaines", #weeks, 5)
check("octobre 2026 : première semaine (lundi d'abord)", day_numbers(weeks[1]), ".,.,.,1,2,3,4")
check("octobre 2026 : deuxième semaine", day_numbers(weeks[2]), "5,6,7,8,9,10,11")
check("octobre 2026 : dernière semaine", day_numbers(weeks[5]), "26,27,28,29,30,31,.")
check("le 10 octobre affiche 4h13", weeks[2][6].text, "4h13")
check("le 11 octobre affiche 0h31", weeks[2][7].text, "0h31")
check("le 12 octobre affiche 1h00", weeks[3][1].text, "1h00")
check("un jour sans temps affiche un point", weeks[2][1].text, "·")
check("l'étoile marque aujourd'hui (le 12)", weeks[3][1].star, true)
local stars = 0
for _, week in ipairs(weeks) do
for _, cell in ipairs(week) do
if cell.star then
stars = stars + 1
end
end
end
check("une seule étoile dans le mois", stars, 1)
local stars_elsewhere = 0
for _, week in ipairs(grid(render(days, 2026, 10, "2026-11-20"))) do
for _, cell in ipairs(week) do
if cell.star then
stars_elsewhere = stars_elsewhere + 1
end
end
end
check("pas d'étoile quand aujourd'hui n'est pas dans ce mois", stars_elsewhere, 0)

for _, case in ipairs({
{ 2026, 10, 5 }, { 2026, 2, 5 }, { 2028, 2, 5 }, { 2026, 8, 6 }, { 2027, 2, 4 }, { 2026, 12, 5 }, { 2024, 1, 5 },
}) do
local w = grid(render({}, case[1], case[2], "x"))
check(string.format("%d-%02d : %d semaines", case[1], case[2], case[3]), #w, case[3])
end
weeks = grid(render({}, 2026, 2, "x"))
check("février 2026 : le 1er est un dimanche, dernière colonne", day_numbers(weeks[1]), ".,.,.,.,.,.,1")
weeks = grid(render({}, 2028, 2, "x"))
check("février 2028 : le 29 existe", weeks[5][2].day, 29)
check("février 2028 : première semaine", day_numbers(weeks[1]), ".,1,2,3,4,5,6")

-- semaine commençant le dimanche
local sunday = grid(render(days, 2026, 10, "2026-10-12", { week_starts_on = "sunday" }))
check("dimanche d'abord : première semaine", day_numbers(sunday[1]), ".,.,.,.,1,2,3")
check("dimanche d'abord : deuxième semaine", day_numbers(sunday[2]), "4,5,6,7,8,9,10")
local sunday_header = lines_of(strip(render(days, 2026, 10, "x", { week_starts_on = "sunday" })))[4]
check("dimanche d'abord : l'en-tête commence par Dim", sunday_header:match("^%s*(%a+)"), "Dim")
check("dimanche d'abord : et finit par Sam", sunday_header:match("(%a+)%s*$"), "Sam")

-- alignement : toutes les lignes de la grille ont la même largeur
local widths_ok = true
for _, year in ipairs({ 2026, 2028 }) do
for month = 1, 12 do
for _, start in ipairs({ "monday", "sunday" }) do
local out = lines_of(render({ ["2026-10-10"] = 15231 }, year, month, "x", { week_starts_on = start }))
for i = 4, #out - 3 do
if out[i] ~= "" and width(out[i]) ~= assemble.WIDTH then
widths_ok = false
end
end
end
end
end
check("alignement : l'en-tête et toutes les semaines ont la même largeur, tous les mois de 2026 et 2028", widths_ok, true)

-- ============================================================
-- calendar/assemble.lua : les statistiques et la légende
-- ============================================================
check("statistiques : première ligne (le total est monté dans le titre)", lines[#lines - 2], "  Moyenne par jour actif : 1h55")
check("statistiques : deuxième ligne", lines[#lines - 1], "  Meilleur jour : 10 (4h13)   Série en cours : 3 j")
check("légende : niveaux par défaut", lines[#lines], "  ██ <1h   ██ 1-3h   ██ 3-6h   ██ 6h+     * = aujourd'hui")
local with_goal = lines_of(strip(render(days, 2026, 10, "2026-10-12", { goal_hours = 3 })))
check("objectif : 1 jour validé sur 31, aucune semaine", with_goal[#with_goal - 1], "  Semaines validées : 0/5 / Jours validés : 1/31")
local goal_zero = lines_of(strip(render(days, 2026, 10, "2026-10-12", { goal_hours = 0 })))
check("objectif 0 (« aucun ») : pas de ligne Objectif", goal_zero[#goal_zero - 1], "  Meilleur jour : 10 (4h13)   Série en cours : 3 j")
check("has_goal : 0 n'est pas un objectif", stats.has_goal(0), false)
check("has_goal : nil n'est pas un objectif", stats.has_goal(nil), false)
check("has_goal : 0,5 est un objectif", stats.has_goal(0.5), true)
check("objectif 0 : aucun jour compté comme atteint", stats.month_stats(days, 2026, 10, 0).goal_days, 0)

-- ---- l'objectif dans les cases : ✓ si atteint, durée rayée si pas atteint (jours passés seulement)
-- le 10 : 4h13, le 11 : 0h31, le 12 (aujourd'hui) : 1h00 ; objectif 3 h
local function durations_line(text, day_line_pattern)
	local ls = lines_of(text)
	for i, line in ipairs(ls) do
		if strip(line):find(day_line_pattern) then
			return ls[i + 1]
		end
	end
end
local goal_raw = render(days, 2026, 10, "2026-10-12", { goal_hours = 3 })
local raw_line = durations_line(goal_raw, " 10 ")
local plain_line = strip(raw_line)
check("objectif atteint (le 10, 4h13 ≥ 3h) : « ✓ 4h13 »", plain_line:find("✓ 4h13", 1, true) ~= nil, true)
check("objectif pas atteint, jour passé (le 11, 0h31) : la durée est rayée", raw_line:find("\27[9m0h31\27[29m", 1, true) ~= nil, true)
check("rayé : seulement le texte, les espaces autour ne le sont pas", raw_line:find("\27[9m 0h31", 1, true) == nil and raw_line:find("0h31 \27[29m", 1, true) == nil, true)
check("aujourd'hui (le 12, 1h00 < 3h) : pas rayé, la journée n'est pas finie", raw_line:find("\27[9m1h00", 1, true), nil)
check("aujourd'hui : pas de ✓ non plus", plain_line:find("✓ 1h00", 1, true), nil)
local function struck_days(text)
	return select(2, text:gsub("\27%[9m%d+h%d%d", ""))
end
local function struck_weeks(text)
	return select(2, text:gsub("\27%[9m%d/%d", ""))
end
check("un seul jour rayé dans le mois", struck_days(goal_raw), 1)
check("un seul ✓ de jour dans le mois", select(2, goal_raw:gsub("✓ %d+h", "")), 1)
check("avec un objectif, la ligne garde ses 65 colonnes, ✓ et rayé compris", utf8.len(plain_line), 65)
check("sans objectif, la ligne fait toujours 65", utf8.len(strip(durations_line(render(days, 2026, 10, "2026-10-12", {}), " 10 "))), 65)
check("objectif atteint pile (3h00 = 3h) : ✓", strip(render({ ["2026-10-05"] = 10800 }, 2026, 10, "2026-10-12", { goal_hours = 3 })):find("✓ 3h00", 1, true) ~= nil, true)
check("objectif 2h59 pour 3h : rayé", render({ ["2026-10-05"] = 10799 }, 2026, 10, "2026-10-12", { goal_hours = 3 }):find("\27[9m2h59", 1, true) ~= nil, true)
check("une longue durée avec ✓ tient dans la case (« ✓ 12h30 »)", strip(render({ ["2026-10-05"] = 45000 }, 2026, 10, "2026-10-12", { goal_hours = 3 })):find("✓ 12h30", 1, true) ~= nil, true)
local no_goal = render(days, 2026, 10, "2026-10-12", {})
check("sans objectif : ni ✓ ni rayé", no_goal:find("✓", 1, true) == nil and no_goal:find("\27[9m", 1, true) == nil, true)
local zero_goal = render(days, 2026, 10, "2026-10-12", { goal_hours = 0 })
check("objectif « aucun » (0) : ni ✓ ni rayé", zero_goal:find("✓", 1, true) == nil and zero_goal:find("\27[9m", 1, true) == nil, true)
check("mois sans rien : ni jour ni semaine rayés (comme un jour vide, une semaine sans travail n'est pas ratée)", render({}, 2026, 10, "2026-10-12", { goal_hours = 3 }):find("\27[9m", 1, true), nil)
local past_month = render({ ["2026-09-01"] = 60, ["2026-09-30"] = 60 }, 2026, 9, "2026-10-12", { goal_hours = 3 })
check("mois passé entier : tous les jours pas atteints sont rayés", struck_days(past_month), 2)
check("mois passé entier : les semaines ne sont jamais rayées (plus de colonne)", struck_weeks(past_month), 0)

-- ---- les semaines validées (en bas du mois)
-- une semaine est validée si l'objectif est atteint goal_days jours sur ses 7 jours
local five = {}
for d = 5, 9 do
	five[string.format("2026-10-%02d", d)] = 4 * 3600
end
local function vw(data, y, m, cfg)
	return table.concat({ assemble.validated_weeks(data, y, m, cfg) }, "/")
end
check("validated_weeks : sans objectif, rien", assemble.validated_weeks(five, 2026, 10, {}), nil)
check("validated_weeks : objectif 0 (aucun), rien", assemble.validated_weeks(five, 2026, 10, { goal_hours = 0 }), nil)
check("octobre 2026 (lundi) : 5 semaines affichées, 1 validée (5 jours sur 5)", vw(five, 2026, 10, { goal_hours = 3 }), "1/5")
check("4 jours sur 5 : pas validée", vw({ ["2026-10-05"] = 4 * 3600, ["2026-10-06"] = 4 * 3600, ["2026-10-07"] = 4 * 3600, ["2026-10-08"] = 4 * 3600 }, 2026, 10, { goal_hours = 3 }), "0/5")
check("goal_days = 3 : 5 jours suffisent largement", vw(five, 2026, 10, { goal_hours = 3, goal_days = 3 }), "1/5")
check("goal_days = 6 : 5 jours ne suffisent pas", vw(five, 2026, 10, { goal_hours = 3, goal_days = 6 }), "0/5")
check("objectif 5 h : des jours de 4 h ne comptent pas", vw(five, 2026, 10, { goal_hours = 5 }), "0/5")
local with_sunday = { ["2026-10-05"] = 4 * 3600, ["2026-10-06"] = 4 * 3600, ["2026-10-07"] = 4 * 3600, ["2026-10-08"] = 4 * 3600, ["2026-10-11"] = 4 * 3600 }
check("le 7e jour de la semaine (dimanche 11) compte aussi", vw(with_sunday, 2026, 10, { goal_hours = 3 }), "1/5")
local across = { ["2026-09-28"] = 4 * 3600, ["2026-09-29"] = 4 * 3600, ["2026-09-30"] = 4 * 3600, ["2026-10-01"] = 4 * 3600, ["2026-10-02"] = 4 * 3600 }
check("semaine du 28 sept. au 4 oct., en octobre : les jours de septembre comptent", vw(across, 2026, 10, { goal_hours = 3 }), "1/5")
check("la même semaine, en septembre : validée aussi", vw(across, 2026, 9, { goal_hours = 3 }), "1/5")
check("semaine du dimanche : novembre 2026 (commence un dimanche) a 5 semaines", vw({}, 2026, 11, { goal_hours = 3, week_starts_on = "sunday" }), "0/5")
check("semaine du lundi : novembre 2026 a 6 semaines", vw({}, 2026, 11, { goal_hours = 3 }), "0/6")
check("février 2021 (commence un lundi, 28 jours) : 4 semaines", vw({}, 2021, 2, { goal_hours = 3 }), "0/4")

-- les lignes : total et jours actifs en haut, semaines et jours validés en bas
local wk = lines_of(strip(render(five, 2026, 10, "2026-10-20", { goal_hours = 3 })))
check("mois seul : le titre avec le total et les jours actifs", wk[2], "  Logtime : Octobre 2026   Total du mois : 20h00 / Jours actifs : 5")
check("mois seul : semaines et jours validés (jours sur le nombre de jours du mois)", wk[#wk - 1], "  Semaines validées : 1/5 / Jours validés : 5/31")
check("mois seul sans objectif : pas de ligne « validées »", strip(render(five, 2026, 10, "2026-10-20", {})):find("validé", 1, true), nil)
local blk_goal = assemble.month_block(five, 2026, 9, "2026-10-20", { goal_hours = 3 }, fr, false)
check("plusieurs mois : septembre, 30 jours, 0 jour validé (les jours d'octobre ne comptent pas pour les jours)", strip(blk_goal.lines[#blk_goal.lines]), "  Semaines validées : 0/5 / Jours validés : 0/30")
local blk_oct = assemble.month_block(five, 2026, 10, "2026-10-20", { goal_hours = 3 }, en, true)
check("plusieurs mois, anglais : la ligne du bas", strip(blk_oct.lines[#blk_oct.lines]), "  Validated weeks : 1/5 / Validated days : 5/31")
check("plusieurs mois : toujours 21 lignes", #blk_oct.lines, 21)
check("plusieurs mois : le titre le plus long tient dans 65 colonnes", (function()
	local long = {}
	for d = 1, 30 do
		long[string.format("2026-09-%02d", d)] = 86399
	end
	for _, labels in ipairs({ fr, en }) do
		local b = assemble.month_block(long, 2026, 9, "2026-10-20", { goal_hours = 3 }, labels, true)
		for _, line in ipairs(b.lines) do
			if utf8.len(strip(line)) > 65 then
				return strip(line)
			end
		end
	end
	return true
end)(), true)
check("dates.key_any : le 0 octobre est le 30 septembre", dates.key_any(2026, 10, 0), "2026-09-30")
check("dates.key_any : le 32 décembre est le 1er janvier", dates.key_any(2026, 12, 32), "2027-01-01")
check("dates.key_any : un jour normal", dates.key_any(2026, 10, 12), "2026-10-12")
check("dates.key_any : au changement d'heure (25 octobre 2026)", dates.key_any(2026, 10, 25), "2026-10-25")
check("month_block sans objectif : largeur 65", assemble.month_block(days, 2026, 10, "2026-10-12", {}, fr, false).width, 65)
check("month_block avec un objectif : largeur 65 aussi", assemble.month_block(days, 2026, 10, "2026-10-12", { goal_hours = 3 }, fr, false).width, 65)
check("assemble.width : objectif 0 (aucun) = 65", assemble.width({ goal_hours = 0 }), 65)
check("mois à venir : rien n'est rayé", render({ ["2026-11-01"] = 60 }, 2026, 11, "2026-10-12", { goal_hours = 3 }):find("\27[9m", 1, true), nil)
local block = assemble.month_block(days, 2026, 10, "2026-10-12", { goal_hours = 3 }, fr, false)
local block_text = table.concat(block.lines, "\n")
check("plusieurs mois (month_block) : ✓ et rayé aussi", block_text:find("✓ 4h13", 1, true) ~= nil and block_text:find("\27[9m0h31", 1, true) ~= nil, true)
local empty = lines_of(strip(render({}, 2026, 10, "2026-10-12")))
check("mois vide : totaux à zéro (dans le titre)", empty[2], "  Logtime : Octobre 2026   Total du mois : 0h00 / Jours actifs : 0")
check("mois vide : moyenne à zéro", empty[#empty - 2], "  Moyenne par jour actif : 0h00")
check("mois vide : pas de meilleur jour, série à zéro", empty[#empty - 1], "  Série en cours : 0 j")
local custom_thresholds = lines_of(strip(render({}, 2026, 10, "x", { thresholds = { 2, 4, 8 } })))
check("légende : seuils personnalisés", custom_thresholds[#custom_thresholds], "  ██ <2h   ██ 2-4h   ██ 4-8h   ██ 8h+     * = aujourd'hui")

-- anglais
local english = lines_of(strip(render(days, 2026, 10, "2026-10-12", {}, en)))
check("anglais : titre", english[2], "  Logtime : October 2026   Month total : 5h45 / Active days : 3")
check("anglais : en-tête", english[4]:match("^%s*(%a+)"), "Mon")
check("anglais : statistiques", english[#english - 2], "  Average per active day : 1h55")
check("anglais : série", english[#english - 1], "  Best day : 10 (4h13)   Current streak : 3 d")
check("anglais : légende", english[#english]:match("%* = today$"), "* = today")

-- ============================================================
-- calendar/assemble.lua : les couleurs
-- ============================================================
local function single_day(secs, cfg)
return render({ ["2026-10-05"] = secs }, 2026, 10, "x", cfg)
end
local HEAT = { "#2E3644", "#5A5240", "#8C7A4A", "#C9AB6B" }
local function has_bg(text, hex)
return text:find(convert.bg(hex), 1, true) ~= nil
end
local function only_bg(text, hex)
for _, other in ipairs(HEAT) do
if (other == hex) ~= has_bg(text, other) then
return false
end
end
return true
end
check("niveau 1 : 3599 s (juste sous 1 h)", only_bg(single_day(3599), HEAT[1]), true)
check("niveau 2 : 3600 s (1 h pile)", only_bg(single_day(3600), HEAT[2]), true)
check("niveau 2 : 10799 s (juste sous 3 h)", only_bg(single_day(10799), HEAT[2]), true)
check("niveau 3 : 10800 s (3 h pile)", only_bg(single_day(10800), HEAT[3]), true)
check("niveau 3 : 21599 s (juste sous 6 h)", only_bg(single_day(21599), HEAT[3]), true)
check("niveau 4 : 21600 s (6 h pile)", only_bg(single_day(21600), HEAT[4]), true)
check("niveau 4 : 100000 s", only_bg(single_day(100000), HEAT[4]), true)
check("aucun temps : aucun fond", only_bg(single_day(0), "aucun"), true)
check("texte clair sur le fond bronze (niveau 3)", single_day(10800):find(convert.fg("#ECE6D9"), 1, true) ~= nil, true)
check("texte sombre sur le fond doré (niveau 4)", single_day(21600):find(convert.fg("#17191F"), 1, true) ~= nil, true)
check("seuils personnalisés : 1 h est maintenant le niveau 1 avec {2,4,8}", only_bg(single_day(3600, { thresholds = { 2, 4, 8 } }), HEAT[1]), true)
check("couleurs personnalisées : le fond du niveau 2", has_bg(single_day(3600, { heat = { "#111111", "#222222", "#333333", "#444444" } }), "#222222"), true)

-- une fonction de couleur personnalisée (la future échelle de dégradé) remplace les niveaux
local received = {}
local function gradient(secs)
received[#received + 1] = secs
if secs <= 0 then
return nil
end
return "#123456"
end
local custom = single_day(7200, { cell_color = gradient })
check("fonction de couleur : son fond est utilisé", has_bg(custom, "#123456"), true)
check("fonction de couleur : aucun niveau par défaut", has_bg(custom, HEAT[2]) or has_bg(custom, HEAT[1]), false)
check("fonction de couleur : appelée avec des secondes entières", received[1] ~= nil and math.type(received[1]) == "integer", true)
check("fonction de couleur : appelée pour chaque jour du mois", #received, 31)
received = {}
render({ ["2026-10-05"] = -500, ["2026-10-06"] = 3600 }, 2026, 10, "x", { cell_color = gradient })
local negative = 0
for _, secs in ipairs(received) do
if secs < 0 then
negative = negative + 1
end
end
check("fonction de couleur : jamais appelée avec une valeur négative", negative, 0)
local custom_lines = lines_of(strip(custom))
check("fonction de couleur : pas de légende des niveaux, seulement l'étoile", custom_lines[#custom_lines], "  * = aujourd'hui")

-- ============================================================
-- calendar/assemble.lua : robustesse
-- ============================================================
local odd = grid(render({ ["2026-10-05"] = -500, ["2026-10-06"] = 3600.9, ["2026-10-07"] = 1e9 }, 2026, 10, "x"))
check("valeur négative : affichée comme aucun temps", odd[2][1].text, "·")
check("secondes décimales : arrondies vers le bas", odd[2][2].text, "1h00")
check("valeur énorme : affichée sans erreur", odd[2][3].text ~= "", true)

local property_ok = true
for year = 2020, 2031 do
for month = 1, 12 do
for _, start in ipairs({ "monday", "sunday" }) do
local ok, weeks_out = pcall(function()
return grid(render({ [dates.key(year, month, 1)] = 100 }, year, month, "x", { week_starts_on = start }))
end)
if not ok or #weeks_out < 4 or #weeks_out > 6 then
property_ok = false
else
local expected_day, in_order = 1, true
for _, week in ipairs(weeks_out) do
for col = 1, 7 do
if week[col].day then
if week[col].day ~= expected_day then
in_order = false
end
expected_day = expected_day + 1
end
end
end
if expected_day - 1 ~= dates.days_in_month(year, month) or not in_order then
property_ok = false
end
end
end
end
end
check("144 mois (2020 à 2031, deux conventions) : jours 1..n dans l'ordre, 4 à 6 semaines, aucune erreur", property_ok, true)
check("rendu déterministe", render(days, 2026, 10, "2026-10-12"), render(days, 2026, 10, "2026-10-12"))

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
