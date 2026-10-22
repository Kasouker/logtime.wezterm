-- tests/calendar/test_board.lua : teste calendar/board.lua (la vue « tout en un » de la page F2, touche a).
-- Lancer :   lua5.4 tests/calendar/test_board.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]calendar[/\\]test_board%.lua$") or "."
local cache = {}
local function load_module(name)
	if not cache[name] then
		cache[name] = assert(loadfile(root .. "/plugin/logtime/" .. name .. ".lua"))(load_module)
	end
	return cache[name]
end
local board = load_module("calendar/board")
local assemble = load_module("calendar/assemble")
local gradient = load_module("color/gradient")
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
local function literal(text)
	return (text:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end
local function strip(text)
	return (text:gsub("\27%[[%d;]*m", ""))
end

local DAYS = {
	["2026-10-12"] = 8 * 3600,
	["2026-10-13"] = 5 * 3600,
	["2026-10-14"] = 9 * 3600,
	["2026-10-15"] = 7 * 3600 + 1800,
	["2026-10-16"] = 2 * 3600,
}
local function data(over)
	local cfg = gradient.apply_to({ goal_hours = 7, goal_days = 3 })
	local o = {
		days = DAYS,
		idle_days = { ["2026-10-12"] = 3600 },
		year = 2026,
		month = 10,
		day_key = "2026-10-16",
		today_key = "2026-10-16",
		cfg = cfg,
		labels = fr,
		b = assemble.BORDER_STYLES.rounded,
		edge = "",
		legend = board.legend(assemble.legend(cfg, fr), fr),
	}
	for k, v in pairs(over or {}) do
		o[k] = v
	end
	return o
end

-- ---- les chiffres de l'année
local parts = board.year_parts(data())
check("l'année : le total", parts[1], "Total de l'année : 31h30")
check("l'année : le meilleur jour", parts[2], "Meilleur jour : 14 octobre (9h00)")
check("l'année : l'inactif", parts[3], "Inactif : 1h00 (3 %)")
check("l'année : les semaines et jours validés", parts[4], "Semaines validées : 1/53 // Jours validés : 3/365")
check("l'année : 4 parts", #parts, 4)
local no_goal = board.year_parts(data({ cfg = gradient.apply_to({}) }))
check("sans objectif : pas de validés", #no_goal, 3)
check(
	"sans inactif (non compté) : pas d'inactif",
	board.year_parts(data({ idle_days = false }))[3]:find("Inactif", 1, true),
	nil
)
check("une année vide : seulement le total", #board.year_parts(data({ days = {}, cfg = gradient.apply_to({}) })), 1)
check("en anglais", board.year_parts(data({ labels = en }))[1]:find(en.year_total, 1, true), 1)

-- ---- les parts sur une ligne
check("join : tout tient, avec de l'air", board.join_parts({ "aa", "bb", "cc" }, 20), "aa  |  bb  |  cc")
check("join : plus serré s'il le faut", board.join_parts({ "aa", "bb", "cc" }, 12), "aa | bb | cc")
check("join : les dernières parts retirées (jamais coupées)", board.join_parts({ "aa", "bb", "cc" }, 9), "aa  |  bb")
check("join : une seule part trop longue : coupée", board.join_parts({ "abcdef" }, 4), "abcd")

-- ---- la légende : sans « * = aujourd'hui »
local legend = board.legend(assemble.legend(gradient.apply_to({}), fr), fr)
check("légende : plus de « aujourd'hui »", strip(legend):find("aujourd", 1, true), nil)
check(
	"légende : les couleurs restent",
	strip(legend):find("0h", 1, true) ~= nil and strip(legend):find("24h", 1, true) ~= nil,
	true
)
check("légende : pas d'espaces au bout", strip(legend):sub(-1) ~= " ", true)

-- ---- l'année : une case par jour
local convert = load_module("color/convert")
local year_view = load_module("calendar/year")
local yl = board.year_lines(data({ day_key = "2026-10-14", accent = "#C96969" }), 150)
check("l'année : 8 lignes", #yl, 8)
local yl_sizes = true
for _, line in ipairs(yl) do
	yl_sizes = yl_sizes and layout.visible_width(line) == 150
end
check("l'année : chaque ligne fait la largeur", yl_sizes, true)
check("l'année : lundi d'abord, en entier", strip(yl[1]):find("^ Lundi") ~= nil, true)
check("l'année : dimanche en dernier", strip(yl[7]):find("^ Dimanche") ~= nil, true)
check("l'année : l'année sous les jours", strip(yl[8]):find("2026", 1, true) ~= nil, true)
local sun_yl = board.year_lines(data({ cfg = gradient.apply_to({ week_starts_on = "sunday" }) }), 150)
check("l'année, dimanche d'abord", strip(sun_yl[1]):find("^ Dimanche") ~= nil, true)
local squares = 0
for row = 1, 7 do
	squares = squares + select(2, strip(yl[row]):gsub("■", "")) + select(2, strip(yl[row]):gsub("◆", ""))
end
check("l'année : une case par jour (365 en 2026)", squares, 365)
check("aujourd'hui : « ◆ » (un seul)", select(2, strip(table.concat(yl, "\n")):gsub("◆", "")), 1)
check("aujourd'hui : un vendredi (le 16 octobre 2026)", strip(yl[5]):find("◆", 1, true) ~= nil, true)
local worked = convert.fg(assemble.day_color(9 * 3600, data().cfg)) .. year_view.DAY
check("un jour travaillé : dans la couleur de ses heures", table.concat(yl):find(worked, 1, true) ~= nil, true)
check(
	"un jour sans rien : gris foncé",
	table.concat(yl):find(convert.fg(year_view.EMPTY_COLOR) .. year_view.DAY, 1, true) ~= nil,
	true
)
check(
	"le jour choisi (le 14, un mercredi) : en couleurs inversées",
	yl[3]:find(assemble.SELECTED .. worked, 1, true) ~= nil,
	true
)
check("un seul jour choisi", select(2, table.concat(yl):gsub("\27%[7m", "")), 1)
check(
	"1er janvier 2026, un jeudi : la case du lundi de cette semaine est vide",
	strip(yl[1]):find("│ +■") ~= nil,
	true
)
check(
	"les mois sous l'année, dans l'ordre",
	strip(yl[8]):find("Jan.*Fév.*Mar.*Avr.*Mai.*Juin.*Juil.*Aoû.*Sep.*Oct.*Nov.*Déc") ~= nil,
	true
)
check("le mois choisi (octobre) : rempli de la couleur", yl[8]:find(convert.bg("#C96969"), 1, true) ~= nil, true)
check(
	"le mois choisi : son nom dedans",
	yl[8]:find(literal(convert.bg("#C96969") .. convert.fg(convert.contrast("#C96969"))) .. " *Oct") ~= nil,
	true
)
check(
	"le mois choisi : son nom centré dans sa place",
	(function()
		local style = convert.bg("#C96969") .. convert.fg(convert.contrast("#C96969"))
		local start = yl[8]:find(style, 1, true)
		local text = yl[8]:sub(start + #style, yl[8]:find(convert.RESET, start, true) - 1)
		local left, right = text:match("^( *)Oct( *)$")
		return left ~= nil and #left >= 1 and math.abs(#left - #right) <= 1
	end)(),
	true
)
check("le nom le plus long, puis un espace avant le trait", strip(yl[3]):find("^ Mercredi │") ~= nil, true)
check("un seul mois rempli", select(2, yl[8]:gsub("\27%[48;", "")), 1)
-- toute la largeur : la place en plus va entre les mois, les cases d'un même mois restent régulières
local function positions(line)
	local out, col = {}, 0
	for _, code in utf8.codes(strip(line)) do
		col = col + 1
		if code == utf8.codepoint("■") or code == utf8.codepoint("◆") then
			out[#out + 1] = col
		end
	end
	return out
end
local mon = positions(yl[1])
check("toute la largeur : la dernière case près du bord droit", mon[#mon] >= 150 - 6, true)
local steps = {}
for k = 2, #mon do
	steps[mon[k] - mon[k - 1]] = true
end
local distinct = 0
for _ in pairs(steps) do
	distinct = distinct + 1
end
check("des écarts réguliers : la case, et la case plus l'espace entre deux mois", distinct <= 3, true)
check("des écarts réguliers : jamais plus serré qu'une case de 2", steps[1], nil)
local wide = board.year_lines(data(), 230)
check("une fenêtre large : plusieurs carrés par case", strip(wide[1]):find("■■■", 1, true) ~= nil, true)
local small_yl = board.year_lines(data(), 120)
local small_ok = true
for _, line in ipairs(small_yl) do
	small_ok = small_ok and layout.visible_width(line) == 120
end
check("120 colonnes : l'année tient", small_ok, true)
local en_yl = board.year_lines(data({ labels = en }), 150)
check("en anglais : les jours", strip(en_yl[3]):find("^ Wednesday") ~= nil, true)
check("en anglais : les mois", strip(en_yl[8]):find("Oct", 1, true) ~= nil, true)
local page_year = board.render(data(), 150, 40)
check("la page : l'année sous les chiffres", strip(page_year[3]):find("^ Lundi") ~= nil, true)
check("la page : les mois juste au-dessus du trait", strip(page_year[10]):find("Jan", 1, true) ~= nil, true)

-- ---- les zones
local function inside(r, width, height)
	return r.x >= 1 and r.y >= 1 and r.x + r.w - 1 <= width and r.y + r.h - 1 <= height and r.w > 0 and r.h > 0
end
local function overlap(a, b)
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end
for _, size in ipairs({ { 120, 32 }, { 150, 40 }, { 220, 60 } }) do
	local z = board.zones(size[1], size[2])
	local names = { "stats", "year", "month", "week", "week_side", "day_projects", "week_projects", "timeline", "help" }
	local ok, apart = true, true
	for i, a in ipairs(names) do
		ok = ok and inside(z[a], size[1], size[2])
		for j = i + 1, #names do
			apart = apart and not overlap(z[a], z[names[j]])
		end
	end
	local tag = size[1] .. " x " .. size[2]
	check("zones " .. tag .. " : toutes dans la fenêtre, et pas vides", ok, true)
	check("zones " .. tag .. " : aucune ne chevauche une autre", apart, true)
	check("zones " .. tag .. " : l'année fait 8 lignes", z.year.h, board.YEAR_HEIGHT)
	check(
		"zones " .. tag .. " : la frise, 4 lignes, en bas à droite",
		z.timeline.h .. " " .. (z.timeline.y + z.timeline.h),
		"4 " .. (size[2] - 1)
	)
	check("zones " .. tag .. " : l'aide sur la dernière ligne", z.help.y, size[2])
	check(
		"zones " .. tag .. " : la colonne des chiffres de la semaine, au bord droit",
		z.week_side.x + z.week_side.w - 1,
		size[1]
	)
end

-- ---- toute la page
local page = board.render(data(), 150, 40)
check("la page : exactement la hauteur", #page, 40)
local sizes = true
for _, line in ipairs(page) do
	sizes = sizes and layout.visible_width(line) == 150
end
check("la page : chaque ligne fait la largeur", sizes, true)
check("en haut : les chiffres de l'année", strip(page[1]):find("Total de l'année : 31h30", 1, true) ~= nil, true)
check("sous les chiffres : un trait", strip(page[2]) == string.rep("─", 150), true)
check("en bas : l'aide", strip(page[40]):find(fr.board_help, 1, true), 2)
check("en bas : la légende au bord droit", strip(page[40]):sub(-3), "24h")
local z = board.zones(150, 40)
local divider = z.month.x + z.month.w
local function char_at(line, x)
	local plain = strip(line)
	local start = utf8.offset(plain, x)
	return plain:sub(start, utf8.offset(plain, x + 1) - 1)
end
check("le trait sous l'année rejoint le trait vertical (┬)", char_at(page[z.year.y + z.year.h], divider), "┬")
check("le trait vertical rejoint le trait du bas (┴)", char_at(page[z.help.y - 1], divider), "┴")
check("le trait vertical entre le mois et la droite", char_at(page[z.month.y + 2], divider), "│")
check("sous la semaine : la jonction à gauche (├)", char_at(page[z.week.y + z.week.h], divider), "├")
check("au-dessus de la frise : la jonction à gauche (├)", char_at(page[z.timeline.y - 1], divider), "├")
check(
	"au-dessus de la frise : le trait entre les projets s'arrête (┴)",
	char_at(page[z.timeline.y - 1], z.week_projects.x - 1),
	"┴"
)
check(
	"sous la semaine : le trait de ses chiffres s'arrête (┴)",
	char_at(page[z.week.y + z.week.h], z.week_side.x - 1),
	"┴"
)
local narrow = board.render(data(), 120, 32)
check("120 x 32 : la page tient", narrow ~= nil and #narrow, 32)
check("120 x 32 : l'aide entière", strip(narrow[32]):find(fr.board_help, 1, true), 2)
check(
	"120 x 32 : la légende ne tient pas à côté de l'aide : seulement l'aide (rien ne dépasse)",
	layout.visible_width(narrow[32]) == 120 and strip(narrow[32]):find("24h", 1, true) == nil,
	true
)
check(
	"120 x 32 : la ligne de l'année ne coupe aucune part",
	strip(narrow[1]):find("Total de l'année", 1, true) ~= nil
		and strip(narrow[1]):find("Semaines validées : 1/", 1, true) == nil,
	true
)
local none, min_w, min_h = board.render(data(), 119, 40)
check("trop étroit : rien", none, nil)
check("trop étroit : la taille minimum", min_w .. " x " .. min_h, board.MIN_WIDTH .. " x " .. board.MIN_HEIGHT)
check("trop bas : rien", board.render(data(), 150, 31), nil)
local double = board.render(data({ b = assemble.BORDER_STYLES.double }), 150, 40)
check("le style des traits suit le réglage (double)", strip(double[2]):sub(1, #"═"), "═")
local colored = board.render(data({ edge = "\27[38;2;1;2;3m" }), 150, 40)
check("les traits dans leur couleur", colored[2]:find("\27[38;2;1;2;3m─", 1, true) ~= nil, true)

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
