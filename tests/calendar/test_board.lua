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

-- ---- l'année : le dessin de l'ancienne vue, sur toute la largeur, les mois en dessous
local convert = load_module("color/convert")
local year_view = load_module("calendar/year")
local yl = board.year_lines(data({ day_key = "2026-10-14", accent = "#C96969" }), 148)
check("l'année : 8 lignes", #yl, 8)
local yl_sizes = true
for _, line in ipairs(yl) do
	yl_sizes = yl_sizes and layout.visible_width(line) == 148
end
check("l'année : chaque ligne fait la largeur", yl_sizes, true)
check("l'année : les jours en abrégé, lundi d'abord", strip(yl[1]):find("^ Lun ") ~= nil, true)
check("l'année : dimanche en dernier", strip(yl[7]):find("^ Dim ") ~= nil, true)
local sun_yl = board.year_lines(data({ cfg = gradient.apply_to({ week_starts_on = "sunday" }) }), 148)
check("l'année, dimanche d'abord", strip(sun_yl[1]):find("^ Dim ") ~= nil, true)
check("les mois en dessous, l'année devant", strip(yl[8]):find("^ 2026 ") ~= nil, true)
check(
	"les mois en dessous, dans l'ordre",
	strip(yl[8]):find("Jan.*Fév.*Mar.*Avr.*Mai.*Juin.*Juil.*Aoû.*Sep.*Oct.*Nov.*Déc") ~= nil,
	true
)
check("aujourd'hui : « ◆ » (un seul), un vendredi", select(2, strip(yl[5]):gsub("◆", "")), 1)
local worked = convert.fg(assemble.day_color(9 * 3600, data().cfg)) .. year_view.DAY
check("un jour travaillé : dans la couleur de ses heures", table.concat(yl):find(worked, 1, true) ~= nil, true)
check(
	"un jour sans rien : gris foncé",
	table.concat(yl):find(convert.fg(year_view.EMPTY_COLOR) .. year_view.DAY, 1, true) ~= nil,
	true
)
check("on ne choisit pas un jour ici : aucune case inversée", table.concat(yl):find("\27[7m", 1, true), nil)
check("le mois choisi (octobre) : rempli de la couleur", yl[8]:find(convert.bg("#C96969"), 1, true) ~= nil, true)
check(
	"le mois choisi : son nom centré dans sa place",
	(function()
		local style = convert.bg("#C96969") .. convert.fg(convert.contrast("#C96969"))
		local start = yl[8]:find(style, 1, true)
		local text = yl[8]:sub(start + #style, yl[8]:find(convert.RESET, start, true) - 1)
		local left, right = text:match("^( *)Oct( *)$")
		return left ~= nil and #left >= 2 and math.abs(#left - #right) <= 1
	end)(),
	true
)
check("un seul mois rempli", select(2, yl[8]:gsub("\27%[48;", "")), 1)
check("seulement sur la ligne des mois", table.concat(yl, "", 1, 7):find("\27[48;", 1, true), nil)
check(
	"sans couleur donnée : le mois choisi en gris",
	board.year_lines(data(), 148)[8]:find(convert.bg(board.ACCENT), 1, true) ~= nil,
	true
)
-- une case = une remise à zéro des couleurs (chaque jour en écrit une, sur chacune de ses lignes)
local function cells_of(line)
	return select(2, line:gsub("\27%[0m", ""))
end
-- les colonnes visibles où commence chaque case, avec la couleur de la case
local function cells_at(line)
	local out, col, i = {}, 0, 1
	local current
	while i <= #line do
		local code = line:match("^\27%[[%d;]*m", i)
		if code then
			if code == "\27[0m" then
				current = nil
			elseif not current then
				current = { col = col + 1, code = code }
				out[#out + 1] = current
			end
			i = i + #code
		else
			local ch = line:match("^[%z\1-\127\194-\244][\128-\191]*", i)
			col = col + 1
			i = i + #ch
		end
	end
	return out
end
-- exact : un mois n'a que ses jours. Tout février travaillé : aucune case grise dans les colonnes de février
local feb = {}
for d = 1, 28 do
	feb[string.format("2026-02-%02d", d)] = 9 * 3600
end
local feb_lines = board.year_lines(data({ days = feb }), 148)
local feb_color = convert.fg(assemble.day_color(9 * 3600, data().cfg))
local feb_cols, gray_cols, feb_count = {}, {}, 0
for row = 1, 7 do
	for _, c in ipairs(cells_at(feb_lines[row])) do
		if c.code == feb_color then
			feb_cols[c.col] = true
			feb_count = feb_count + 1
		else
			gray_cols[c.col] = true
		end
	end
end
check("février : ses 28 jours", feb_count, 28)
local shared = false
for col in pairs(feb_cols) do
	shared = shared or gray_cols[col] == true
end
check("un mois n'a que ses jours (aucune colonne partagée avec janvier ou mars)", shared, false)
-- le nom du mois centré sous son bloc (à une colonne près)
local feb_wide = board.year_lines(data({ days = feb }), 200)
local lo, hi = math.huge, 0
for row = 1, 7 do
	for _, c in ipairs(cells_at(feb_wide[row])) do
		if c.code == feb_color then
			lo, hi = math.min(lo, c.col), math.max(hi, c.col)
		end
	end
end
local axis_plain = strip(feb_wide[8])
local name_at = utf8.len(axis_plain:sub(1, axis_plain:find("Fév", 1, true) - 1)) + 1
check("le nom du mois centré sous son bloc", math.abs((name_at + 1) - (lo + hi) / 2) <= 1, true)
local function count_cells(lines, rows)
	local n = 0
	for row = 1, rows do
		n = n + cells_of(lines[row])
	end
	return n
end
check("une case par jour (365 en 2026)", count_cells(yl, 7), 365)
-- toute la largeur, et autant d'air à gauche qu'à droite
for _, w in ipairs({ 118, 148, 200 }) do
	local lines = board.year_lines(data(), w)
	local first, last = math.huge, 0
	for row = 1, 7 do
		local at = cells_at(lines[row])
		first = math.min(first, at[1].col)
		last = math.max(last, at[#at].col)
	end
	local left_air = first - (1 + year_view.LABEL) - 1
	local right_air = w - last - 1
	check("toute la largeur (" .. w .. ") : la dernière case près du bord droit", right_air <= 6, true)
	check(
		"centrée (" .. w .. ") : autant d'air à gauche qu'à droite (à 3 près)",
		math.abs(left_air - right_air) <= 3,
		true
	)
end
-- plus de hauteur : les jours s'allongent vers le bas
check("la hauteur de l'année : 8 lignes dans une fenêtre de 34", board.year_height(34), 8)
check("la hauteur de l'année : 15 lignes dans une fenêtre de 46 (2 lignes par jour)", board.year_height(46), 15)
check("la hauteur de l'année : jamais plus de 3 lignes par jour", board.year_height(200), 22)
local tall = board.year_lines(data(), 148, 15)
check("2 lignes par jour : 15 lignes", #tall, 15)
check(
	"2 lignes par jour : le nom du jour sur la première",
	strip(tall[1]):find("^ Lun ") ~= nil and strip(tall[2]):find("^      ") ~= nil,
	true
)
check(
	"2 lignes par jour : un pavé de couleur, puis une demi-case",
	tall[1]:find("\27[48;", 1, true) ~= nil and strip(tall[2]):find("▀", 1, true) ~= nil,
	true
)
check(
	"2 lignes par jour : toujours une case par jour",
	count_cells({ tall[1], tall[3], tall[5], tall[7], tall[9], tall[11], tall[13] }, 7),
	365
)
check("2 lignes par jour : aujourd'hui « ◆ » dans sa case", select(2, strip(table.concat(tall)):gsub("◆", "")), 1)
check("2 lignes par jour : les mois sur la dernière ligne", strip(tall[15]):find("Oct", 1, true) ~= nil, true)
local wide = board.year_lines(data(), 228)
check(
	"une fenêtre large : des cases plus larges (des pavés de couleur)",
	wide[1]:find("\27%[48;2;[%d;]+m\27%[38;2;[%d;]+m  \27%[0m") ~= nil,
	true
)
check("une fenêtre large : toujours une case par jour", count_cells(wide, 7), 365)
local en_yl = board.year_lines(data({ labels = en }), 148)
check("en anglais : les jours", strip(en_yl[3]):find("^ Wed ") ~= nil, true)
local page_year = board.render(data(), 150, 40)
check("la page : l'année sous le trait des chiffres", strip(page_year[4]):find("Lun", 1, true) ~= nil, true)
check("la page : les mois juste au-dessus du trait", strip(page_year[11]):find("Jan", 1, true) ~= nil, true)

-- ---- les zones
local function inside(r, width, height) -- dans le cadre (pas sur ses bords)
	return r.x >= 2 and r.y >= 2 and r.x + r.w - 1 <= width - 1 and r.y + r.h - 1 <= height - 1 and r.w > 0 and r.h > 0
end
local function overlap(a, b)
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end
for _, size in ipairs({ { 120, 34 }, { 150, 40 }, { 220, 60 } }) do
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
	check("zones " .. tag .. " : toutes dans le cadre, et pas vides", ok, true)
	check("zones " .. tag .. " : aucune ne chevauche une autre", apart, true)
	check("zones " .. tag .. " : la hauteur de l'année suit la fenêtre", z.year.h, board.year_height(size[2]))
	check(
		"zones " .. tag .. " : la frise, 4 lignes, juste au-dessus du trait de l'aide",
		z.timeline.h .. " " .. (z.timeline.y + z.timeline.h),
		"4 " .. (size[2] - 2)
	)
	check("zones " .. tag .. " : l'aide juste au-dessus du bas du cadre", z.help.y, size[2] - 1)
	check(
		"zones " .. tag .. " : la colonne des chiffres de la semaine, contre le bord droit",
		z.week_side.x + z.week_side.w - 1,
		size[1] - 1
	)
end

-- ---- toute la page, dans un cadre (comme la page F4)
local page = board.render(data(), 150, 40)
check("la page : exactement la hauteur", #page, 40)
local sizes = true
for _, line in ipairs(page) do
	sizes = sizes and layout.visible_width(line) == 150
end
check("la page : chaque ligne fait la largeur", sizes, true)
check("le cadre : en haut", strip(page[1]), "╭" .. string.rep("─", 148) .. "╮")
check("le cadre : en bas", strip(page[40]), "╰" .. string.rep("─", 148) .. "╯")
local sides = true
for y = 2, 39 do
	local plain = strip(page[y])
	local first = plain:sub(1, 3)
	local last = plain:sub(-3)
	sides = sides and (first == "│" or first == "├") and (last == "│" or last == "┤")
end
check("le cadre : les côtés (│, ou ├ ┤ au bout des traits)", sides, true)
check("en haut : les chiffres de l'année", strip(page[2]):find("Total de l'année : 31h30", 1, true) ~= nil, true)
check("sous les chiffres : un trait d'un bord à l'autre", strip(page[3]), "├" .. string.rep("─", 148) .. "┤")
check("en bas : l'aide", strip(page[39]):find(fr.board_help, 1, true), 5)
check("en bas : la légende contre le bord droit", strip(page[39]):sub(-7), "24h │")
local z = board.zones(150, 40)
local divider = z.month.x + z.month.w
local function char_at(line, x)
	local plain = strip(line)
	local start = utf8.offset(plain, x)
	return plain:sub(start, utf8.offset(plain, x + 1) - 1)
end
check("le trait sous l'année rejoint le trait vertical (┬)", char_at(page[z.year.y + z.year.h], divider), "┬")
check(
	"le trait sous l'année rejoint le cadre (├ … ┤)",
	char_at(page[z.year.y + z.year.h], 1) .. char_at(page[z.year.y + z.year.h], 150),
	"├┤"
)
check("le trait vertical rejoint le trait de l'aide (┴)", char_at(page[z.help.y - 1], divider), "┴")
check("le trait vertical entre le mois et la droite", char_at(page[z.month.y + 2], divider), "│")
check(
	"sous la semaine : la jonction à gauche (├) et au cadre (┤)",
	char_at(page[z.week.y + z.week.h], divider) .. char_at(page[z.week.y + z.week.h], 150),
	"├┤"
)
check(
	"au-dessus de la frise : la jonction à gauche (├) et au cadre (┤)",
	char_at(page[z.timeline.y - 1], divider) .. char_at(page[z.timeline.y - 1], 150),
	"├┤"
)
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
check(
	"sous la semaine : le trait entre les projets commence (┬)",
	char_at(page[z.week.y + z.week.h], z.week_projects.x - 1),
	"┬"
)
check(
	"le trait de la semaine part du trait sous l'année (┬)",
	char_at(page[z.year.y + z.year.h], z.week_side.x - 1),
	"┬"
)
local narrow = board.render(data(), 120, 34)
check("120 x 34 : la page tient", narrow ~= nil and #narrow, 34)
check("120 x 34 : l'aide entière", strip(narrow[33]):find(fr.board_help, 1, true), 5)
check(
	"120 x 34 : la légende ne tient pas à côté de l'aide : seulement l'aide (rien ne dépasse)",
	layout.visible_width(narrow[33]) == 120 and strip(narrow[33]):find("24h", 1, true) == nil,
	true
)
check(
	"120 x 34 : la ligne de l'année ne coupe aucune part",
	strip(narrow[2]):find("Total de l'année", 1, true) ~= nil
		and strip(narrow[2]):find("Semaines validées : 1/", 1, true) == nil,
	true
)
check("120 x 34 : l'année entière (Déc)", strip(narrow[11]):find("Déc", 1, true) ~= nil, true)
local none, min_w, min_h = board.render(data(), 119, 40)
check("trop étroit : rien", none, nil)
check("trop étroit : la taille minimum", min_w .. " x " .. min_h, board.MIN_WIDTH .. " x " .. board.MIN_HEIGHT)
check("trop bas : rien", board.render(data(), 150, board.MIN_HEIGHT - 1), nil)
local double = board.render(data({ b = assemble.BORDER_STYLES.double }), 150, 40)
check("le style des traits suit le réglage (double)", strip(double[1]):sub(1, #"╔"), "╔")
local colored = board.render(data({ edge = "\27[38;2;1;2;3m" }), 150, 40)
check("les traits dans leur couleur", colored[3]:find("\27[38;2;1;2;3m─", 1, true) ~= nil, true)

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
