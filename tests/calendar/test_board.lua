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

-- ---- l'aide, coupée entre ses parties
local hl = board.help_lines("aa | bb | cc", "0h ██ 24h", 20)
check("l'aide : coupée entre ses parties", strip(hl[1]), " aa | bb | cc       ")
check(
	"l'aide : la légende sur une ligne à elle si elle ne tient pas à côté",
	strip(hl[2]),
	"          0h ██ 24h "
)
local hl2 = board.help_lines("aa | bb | cc", "0h ██ 24h", 30)
check(
	"l'aide : la légende au bout de la dernière ligne si elle tient",
	#hl2 .. " " .. strip(hl2[1]),
	"1  aa | bb | cc       0h ██ 24h "
)
local hl3 = board.help_lines("aaaa | bbbb | cccc", "", 12)
check(
	"l'aide : une partie par ligne s'il le faut (jamais coupée au milieu)",
	#hl3 .. strip(hl3[1]) .. strip(hl3[3]),
	"3 aaaa        cccc       "
)
local hl_sizes = true
for _, line in ipairs(board.help_lines(fr.board_help, "0h ████ 24h", 59)) do
	hl_sizes = hl_sizes and layout.visible_width(line) == 59
end
check("l'aide : chaque ligne fait la largeur", hl_sizes, true)

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
local feb_wide = board.year_lines(data({ days = feb }), 148)
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
local roomy = true
for h = 34, 120 do
	local y = board.year_height(h)
	roomy = roomy and (y == 8 or h - y - 5 >= board.MIN_BOTTOM)
end
check("la hauteur de l'année : toujours assez de place en bas (sauf au plus petit)", roomy, true)
check("la hauteur de l'année : 3 lignes par jour dès qu'il reste la place en bas", board.year_height(51), 22)
check("la hauteur de l'année : pas 3 lignes une ligne trop tôt", board.year_height(50), 15)
-- des cases aussi larges que possible : deux mois peuvent se toucher (à 160 colonnes : 3 colonnes par jour)
check(
	"des cases aussi larges que possible",
	strip(board.year_lines(data(), 196)[1]):find("■■", 1, true) ~= nil
		or board.year_lines(data(), 196)[1]:find("\27[48;", 1, true) ~= nil,
	true
)
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
		"zones " .. tag .. " : la frise, 4 lignes, jusqu'au bas du cadre",
		z.timeline.h .. " " .. (z.timeline.y + z.timeline.h),
		"4 " .. size[2]
	)
	check(
		"zones " .. tag .. " : l'aide sous le mois (2 lignes par défaut), jusqu'au bas du cadre",
		z.help.x == z.month.x and z.help.w == z.month.w and z.help.y == z.month.y + z.month.h and z.help.y + z.help.h,
		size[2]
	)
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
local z = board.zones(150, 40)
local divider = z.month.x + z.month.w
check(
	"le cadre : en bas, rejoint par le trait vertical du milieu (┴)",
	strip(page[40]),
	"╰" .. string.rep("─", divider - 2) .. "┴" .. string.rep("─", 150 - divider - 1) .. "╯"
)
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
local help_text = strip(table.concat(page, "", 37, 39))
check(
	"en bas à gauche : l'aide, sur plusieurs lignes",
	help_text:find("mois : Tab Maj+Tab", 1, true) ~= nil and help_text:find("rafraîchir : r", 1, true) ~= nil,
	true
)
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
local function left_of_divider(line)
	local plain = strip(line)
	return plain:sub(1, utf8.offset(plain, divider) - 1)
end
check("l'aide : la légende au bout de sa dernière ligne", left_of_divider(page[39]):find("24h $") ~= nil, true)
check(
	"l'aide : dans la zone du mois, à gauche du trait du milieu",
	char_at(page[38], divider) .. char_at(page[39], divider),
	"││"
)
check(
	"pas de trait entre le mois et l'aide (seulement les lignes en trop du mois)",
	(function()
		for y = z.help.y - 1, z.month.y, -1 do
			local left = left_of_divider(page[y])
			if left:find("╰", 1, true) then
				return true
			end
			if left:find("├", 1, true) or left:find("┤", 1, true) then
				return false
			end
		end
	end)(),
	true
)
check(
	"l'aide n'est pas « à cheval » : la légende commence après la fin de toutes les lignes de l'aide",
	(function()
		local longest, legend_at = 0, nil
		for y = z.help.y, z.help.y + z.help.h - 1 do
			local left = left_of_divider(page[y])
			local at = left:find("0h", 1, true)
			if at then
				legend_at = utf8.len(left:sub(1, at - 1))
				local before = left:sub(1, at - 1):gsub("%s+$", "")
				longest = math.max(longest, utf8.len(before))
			else
				longest = math.max(longest, utf8.len((left:gsub("%s+$", ""))))
			end
		end
		return legend_at ~= nil and legend_at > longest
	end)(),
	true
)
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
local narrow_help = strip(table.concat(narrow, "\n", 30, 33))
check(
	"120 x 34 : l'aide entière, sur plusieurs lignes, et la légende",
	narrow_help:find("mois : Tab Maj+Tab", 1, true) ~= nil
		and narrow_help:find("rafraîchir : r", 1, true) ~= nil
		and narrow_help:find("24h", 1, true) ~= nil,
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

-- ---- le mois choisi, en bas à gauche : dans son propre cadre, des cases toutes de la même taille
local ml = board.month_lines(data({ accent = "#C96969" }), 74, 27)
check("le mois : exactement la hauteur", #ml, 27)
local ml_sizes = true
for _, line in ipairs(ml) do
	ml_sizes = ml_sizes and layout.visible_width(line) == 74
end
check("le mois : chaque ligne fait la largeur", ml_sizes, true)
local ml_plain = {}
for k, line in ipairs(ml) do
	ml_plain[k] = strip(line)
end
local function first_with(text)
	for k, line in ipairs(ml_plain) do
		if line:find(text, 1, true) then
			return k, line
		end
	end
end
local top_k, top = first_with("╭")
local bottom_k, bottom = first_with("╰")
check(
	"le mois : son propre cadre, avec une colonne d'air au moins de chaque côté",
	top:find("^ +╭") ~= nil and top:find("╮ +$") ~= nil,
	true
)
check(
	"le mois : toute la hauteur (au plus une ligne en trop par semaine, partagée)",
	(top_k - 1) + (27 - bottom_k) < 5,
	true
)
check("le mois : centré en hauteur (à une ligne près)", math.abs((top_k - 1) - (27 - bottom_k)) <= 1, true)
check(
	"le mois : les jours et le mois posés sur le trait du haut",
	top:find("─ Lun ─", 1, true) ~= nil
		and top:find("─ Mar ─", 1, true) ~= nil
		and top:find("─ Oct ─", 1, true) ~= nil,
	true
)
check(
	"le mois : les jonctions du bas (┴) gardées après le texte des validés, et le coin ╯",
	bottom:find("3/31 ─", 1, true) ~= nil and bottom:find("┴", 1, true) ~= nil and bottom:sub(-4) == "╯ ",
	true
)
check("le mois : plus de rangée de cases pour les noms", ml_plain[top_k + 1]:find("Lun", 1, true), nil)
check(
	"le mois : les semaines et jours validés posés sur le trait du bas",
	bottom:find("╰─ Semaines validées : 1/5 / Jours validés : 3/31 ─", 1, true) ~= nil,
	true
)
-- toutes les cases de la même largeur : les traits verticaux régulièrement espacés
local function bars(line)
	local out, col = {}, 0
	for _, code in utf8.codes(line) do
		col = col + 1
		local ch = utf8.char(code)
		if ch == "│" or ch == "┼" or ch == "├" or ch == "┤" then
			out[#out + 1] = col
		end
	end
	return out
end
local _, rule_line = first_with("┼")
local cols_ = bars(rule_line)
check("le mois : 9 traits verticaux (7 jours, puis la colonne des semaines)", #cols_, 9)
local widths_ = {}
for k = 2, #cols_ do
	widths_[#widths_ + 1] = cols_[k] - cols_[k - 1]
end
check(
	"le mois : les 8 colonnes de la même largeur, à une colonne près",
	math.max(table.unpack(widths_)) - math.min(table.unpack(widths_)) <= 1,
	true
)
check("le mois : toute la largeur (une colonne d'air de chaque côté)", cols_[1] .. " " .. cols_[#cols_], "2 73")
-- toutes les semaines de la même hauteur
local rows_at = { top_k }
for k = top_k + 1, bottom_k do
	if ml_plain[k]:find("├", 1, true) or k == bottom_k then
		rows_at[#rows_at + 1] = k
	end
end
local heights_ = {}
for k = 2, #rows_at do
	heights_[#heights_ + 1] = rows_at[k] - rows_at[k - 1]
end
check("le mois : 5 semaines (octobre 2026)", #rows_at - 1, 5)
check(
	"le mois : toutes les semaines exactement de la même hauteur",
	math.max(table.unpack(heights_)) - math.min(table.unpack(heights_)),
	0
)
check(
	"le mois : en haut de sa zone, les lignes en trop (moins d'une semaine) sous le cadre",
	top_k == 1 and 27 - bottom_k < 5,
	true
)
local joined_ml = table.concat(ml_plain, "\n")
check(
	"le mois : les semaines à droite (« Sem. 1 » dans sa case)",
	(select(2, first_with("Sem. 1"))):find("Sem%. 1 +│ $") ~= nil,
	true
)
check(
	"le mois : ses jours (le 31) et l'objectif (✓)",
	joined_ml:find("31", 1, true) ~= nil and joined_ml:find("✓ 9h00", 1, true) ~= nil,
	true
)
check("le mois : aujourd'hui « *16 »", joined_ml:find("*16", 1, true) ~= nil, true)
local function week_filled(lines, plain, label)
	for k, line in ipairs(plain) do
		if line:find(label, 1, true) then
			return lines[k]:find(
				literal(convert.bg("#C96969") .. convert.fg(convert.contrast("#C96969"))) .. " *Sem%. "
			) ~= nil
		end
	end
end
check("le mois : la semaine choisie (celle du 16) remplie de la couleur", week_filled(ml, ml_plain, "Sem. 3"), true)
check("le mois : les autres non", week_filled(ml, ml_plain, "Sem. 2"), false)
local other = board.month_lines(data({ accent = "#C96969", day_key = "2026-10-26" }), 74, 27)
local other_plain = {}
for k, line in ipairs(other) do
	other_plain[k] = strip(line)
end
check("le mois : la semaine choisie suit le jour choisi", week_filled(other, other_plain, "Sem. 5"), true)
local elsewhere = board.month_lines(data({ accent = "#C96969", day_key = "2026-11-03" }), 74, 27)
check(
	"le mois : un jour choisi dans un autre mois : aucune semaine remplie",
	table.concat(elsewhere):find(convert.bg("#C96969"), 1, true),
	nil
)
check(
	"le mois : « Sem. 1 » au milieu de sa case (pas sur la ligne des numéros)",
	(select(2, first_with("Sem. 1"))):find("│ 1 ", 1, true),
	nil
)
check(
	"le mois : une case sans temps reste sans couleur (les couleurs ne débordent pas)",
	(function()
		for k, line in ipairs(ml_plain) do
			if line:find("│ 17 ", 1, true) then
				return ml[k]:find("│ 17 ", 1, true) ~= nil
			end
		end
	end)(),
	true
)
local wide_ml = strip(table.concat(board.month_lines(data(), 110, 27), "\n"))
check(
	"une zone large : « Semaine 3 » en entier, les jours et le mois en entier",
	wide_ml:find("Semaine 3", 1, true) ~= nil
		and wide_ml:find("Mercredi", 1, true) ~= nil
		and wide_ml:find("Octobre", 1, true) ~= nil,
	true
)
local narrow_ml = strip(table.concat(board.month_lines(data(), 59, 19), "\n"))
check(
	"une case étroite : « ✓8h00 » plutôt qu'une durée coupée",
	narrow_ml:find("✓8h00", 1, true) ~= nil and narrow_ml:find("✓ 8h0│", 1, true) == nil,
	true
)
local sun_ml = strip(board.month_lines(data({ cfg = gradient.apply_to({ week_starts_on = "sunday" }) }), 74, 27)[top_k])
check("le mois : dimanche d'abord si réglé", sun_ml:find("╭─ Dim ─", 1, true) ~= nil, true)
local en_ml = strip(table.concat(board.month_lines(data({ labels = en }), 74, 27), "\n"))
check("le mois en anglais", en_ml:find("Week 1", 1, true) ~= nil and en_ml:find("Mon", 1, true) ~= nil, true)
-- dans la page
local mp = board.render(data(), 150, 40)
local mz = board.zones(150, 40)
check("la page : le mois dans sa zone", strip(table.concat(mp, "\n")):find("Sem. 3", 1, true) ~= nil, true)
check(
	"la page : le cadre du mois ne touche pas les traits de la page",
	char_at(mp[mz.month.y + 1], 1) .. char_at(mp[mz.month.y + 1], 2),
	"│ "
)
local m120 = board.render(data(), 120, 34)
check("120 x 34 : le mois tient", strip(table.concat(m120, "\n")):find("Sem. 5", 1, true) ~= nil, true)

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
