-- plugin/logtime/calendar/board.lua : la vue « tout en un » de la page F2 (touche a) : l'année, le mois, la semaine et
-- le jour choisis, sur toute la fenêtre, dans un cadre (comme la page F4). Aucune dépendance à WezTerm : se teste avec un
-- simple interpréteur Lua.
--
--   ╭───────────────────────────────────────────────────────────────────────────────────────────────────────────╮
--   │  Total de l'année : 412h10  |  Meilleur jour : 14 octobre (15h35)  |  Inactif : …  |  Semaines validées : … │
--   ├───────────────────────────────────────────────────────────────────────────────────────────────────────────┤
--   │                    l'année, comme l'ancienne vue de l'année (calendar/year.lua), centrée                   │
--   ├───────────────────────────────┬───────────────────────────────────────┬───────────────────────────────────┤
--   │ le mois choisi                │ la semaine choisie : 7 colonnes       │ les chiffres de la semaine        │
--   │                               ├───────────────────────────────────────┴───────────────────────────────────┤
--   │                               │ les projets du jour choisi            │ les meilleurs projets de la semaine │
--   │                               ├───────────────────────────────────────┴───────────────────────────────────┤
--   │                               │ la frise du jour choisi                                                     │
--   ├───────────────────────────────┴───────────────────────────────────────────────────────────────────────────┤
--   │ mois : Tab Maj+Tab | semaine : ↑ ↓ | jour : ← → | …                                           la légende │
--   ╰───────────────────────────────────────────────────────────────────────────────────────────────────────────╯
local load = ...
local year_view = load("calendar/year")
local stats = load("calendar/stats")
local layout = load("calendar/layout")
local convert = load("color/convert")
local idle = load("core/idle")
local dates = load("calendar/dates")
local assemble = load("calendar/assemble")

local M = {}

M.MIN_WIDTH = 120 -- en dessous, la page demande d'agrandir la fenêtre (l'aide tient juste)
M.MIN_HEIGHT = 34
M.YEAR_HEIGHT = 8 -- les 7 jours de la semaine, puis la ligne des mois
M.MONTH_SHARE = 0.42 -- la part de la largeur pour le mois (à gauche, en bas)
M.WEEK_SIDE = 26 -- la colonne des chiffres de la semaine (à droite des 7 colonnes)
M.WEEK_SHARE = 0.5 -- la part de la hauteur du bas pour la semaine ; le reste pour les projets et la frise
M.PROJECTS_SHARE = 0.5 -- la part de la largeur de droite pour les projets du jour ; le reste pour ceux de la semaine
M.TIMELINE_HEIGHT = 4 -- la frise : les heures, puis la frise dans son cadre

local vw = layout.visible_width

local function fit(text, width)
	local len = vw(text)
	if len <= width then
		return text .. string.rep(" ", width - len)
	end
	local plain = text:gsub("\27%[[%d;]*m", "")
	return plain:sub(1, (utf8.offset(plain, width + 1) or (#plain + 1)) - 1)
end

local function centered(text, width)
	return fit(string.rep(" ", math.max(0, (width - vw(text)) // 2)) .. text, width)
end

-- « 14 octobre » ou "October 14", selon la langue
local function day_month(key, labels)
	local _, m, d = key:match("^(%d+)-(%d+)-(%d+)$")
	local month = labels.months[tonumber(m)]
	return (
		labels.day_month:gsub("{([%w_]+)}", {
			day = tostring(tonumber(d)),
			month = month,
			month_lower = month:lower(),
		})
	)
end

-- La ligne des chiffres de l'année : les parts (le total, le meilleur jour, l'inactif s'il est compté, les semaines et
-- jours validés avec un objectif).
function M.year_parts(o)
	local labels, c = o.labels, o.labels.colon
	local s = year_view.year_stats(o.days, o.year, o.cfg, o.idle_days)
	local parts = { string.format("%s%s%s", labels.year_total, c, stats.hm(s.total)) }
	if s.best_key then
		parts[#parts + 1] =
			string.format("%s%s%s (%s)", labels.best, c, day_month(s.best_key, labels), stats.hm(s.best_secs))
	end
	if o.idle_days and s.total > 0 then
		local _, percent = idle.share(s.total, s.idle)
		parts[#parts + 1] = string.format(labels.idle_year, stats.hm(s.idle), percent)
	end
	if stats.has_goal(o.cfg.goal_hours) then
		parts[#parts + 1] = string.format(
			"%s%s%d/%d // %s%s%d/%d",
			labels.validated_weeks,
			c,
			s.validated_weeks,
			s.weeks,
			labels.validated_days,
			c,
			s.goal_days,
			s.days
		)
	end
	return parts
end

-- Les parts sur une ligne de `width` colonnes : séparées par « | » avec de l'air, sinon plus serrées, sinon les
-- dernières parts sont retirées (jamais une part coupée au milieu).
function M.join_parts(parts, width)
	for count = #parts, 1, -1 do
		for _, sep in ipairs({ "  |  ", " | " }) do
			local text = table.concat(parts, sep, 1, count)
			if vw(text) <= width then
				return text
			end
		end
	end
	return fit(parts[1] or "", width)
end

-- La légende des couleurs du calendrier (assemble.legend), sans « * = aujourd'hui » au bout : comme sur la maquette,
-- seulement les couleurs (elle partage la ligne de l'aide).
function M.legend(legend, labels)
	local today = labels.today or ""
	if today ~= "" and legend:sub(-#today) == today then
		legend = legend:sub(1, -#today - 1)
	end
	return (legend:gsub("%s+$", ""))
end

M.ACCENT = "#8B8E99" -- la couleur du mois choisi sous l'année (sans o.accent)

-- Le numéro du jour dans l'année (1 pour le 1er janvier).
local function yday(year, month, day)
	return os.date("*t", os.time({ year = year, month = month, day = day, hour = 12 })).yday
end

-- L'année : M.YEAR_HEIGHT lignes de `width` colonnes, sur toute la largeur. Le dessin de l'ancienne vue de l'année
-- (les jours en abrégé, une case « ■ » par jour dans la couleur de ses heures, aujourd'hui « ◆ »), mais les cases
-- s'élargissent avec la place (plusieurs carrés), la place qui reste va entre les mois, et les mois sont en dessous.
-- On ne choisit pas un jour ici, seulement un mois : le mois choisi est rempli de o.accent, sous ses semaines.
--   Lun  ■■ ■■ ■■   ■■ ■■ ■■ ■■   …
--   …
--   Dim  ■■ ■■ ■■   ■■ ■■ ■■ ■■   …
--   2026  Jan        Fév         …   ▐   Oct   ▌   …
function M.year_lines(o, width)
	local labels, cfg = o.labels, o.cfg
	local week_starts_on = cfg.week_starts_on
	local offset = dates.offset(o.year, 1, week_starts_on)
	local columns = year_view.columns(o.year, week_starts_on)
	local count = yday(o.year, 12, 31)
	local label_w = 1 + year_view.LABEL -- une colonne d'air contre le cadre, puis « Lun » et deux espaces
	local room = width - label_w
	-- des cases toutes de la même largeur ; la place qui reste va entre les mois (avant la semaine du 1er de chaque mois,
	-- et aux deux bouts) : les mois se détachent, et l'année prend toute la largeur
	local base = math.max(1, room // columns)
	local starts = {}
	for month = 1, 12 do
		starts[month] = math.floor((yday(o.year, month, 1) - 1 + offset) / 7) + 1
	end
	local slots = { 1 } -- le bord gauche, puis le début de chaque mois (sauf janvier) ; + 1 : le bord droit
	for month = 2, 12 do
		slots[#slots + 1] = starts[month]
	end
	local free = math.max(0, room - base * columns)
	local n = #slots + 1
	local gaps = {}
	for k, col in ipairs(slots) do -- free réparti régulièrement : k * free / n, arrondi, moins ce qui est déjà donné
		gaps[col] = (gaps[col] or 0) + (k * free // n - (k - 1) * free // n)
	end
	local at, x = {}, 0
	for col = 1, columns do
		x = x + (gaps[col] or 0)
		at[col] = x -- la position de la colonne, après les noms des jours
		x = x + base
	end
	local marks = math.max(1, base - 1) -- les carrés par case (le même nombre partout), puis une colonne d'air
	-- une ligne par jour de la semaine
	local names = {}
	for i = 1, 7 do
		names[i] = labels.weekdays[i]
	end
	if week_starts_on == "sunday" then
		table.insert(names, 1, names[7])
		names[8] = nil
	end
	local out = {}
	for row = 1, 7 do
		local parts = { " " .. fit(names[row], year_view.LABEL) }
		for col = 1, columns do
			parts[#parts + 1] = string.rep(" ", gaps[col] or 0)
			local i = (col - 1) * 7 + row - offset
			if i < 1 or i > count then
				parts[#parts + 1] = string.rep(" ", base)
			else
				local key = dates.key_any(o.year, 1, i)
				local secs = math.floor(math.max(0, o.days[key] or 0))
				local color = (secs > 0 and assemble.day_color(secs, cfg)) or year_view.EMPTY_COLOR
				local square = (key == o.today_key) and year_view.TODAY or year_view.DAY
				parts[#parts + 1] = convert.fg(color)
					.. string.rep(square, math.min(marks, base))
					.. convert.RESET
					.. string.rep(" ", base - math.min(marks, base))
			end
		end
		out[row] = fit(table.concat(parts), width)
	end
	-- les mois, en dessous : chacun centré sous ses semaines ; le mois choisi rempli de sa couleur
	local accent = o.accent or M.ACCENT
	local axis = { " " .. fit(tostring(o.year), year_view.LABEL) }
	local function x_of(col) -- la position d'une colonne (columns + 1 : la fin des cases)
		return col > columns and x or at[col]
	end
	local cursor = 0
	for month = 1, 12 do
		-- de la fin du mois d'avant (le milieu de l'espace entre les deux) à la fin de ce mois
		local stop = month < 12 and (x_of(starts[month + 1]) - (gaps[starts[month + 1]] or 0) // 2) or room
		local span = stop - cursor
		local name = (labels.months_short or {})[month] or labels.months[month]
		local text = centered(name, span)
		if month == o.month then
			text = convert.bg(accent) .. convert.fg(convert.contrast(accent)) .. text .. convert.RESET
		end
		axis[#axis + 1] = text
		cursor = stop
	end
	out[M.YEAR_HEIGHT] = fit(table.concat(axis), width)
	return out
end

-- Les zones de la page : { x, y, w, h } (x et y à partir de 1), pour une fenêtre de width x height. Le cadre et les
-- traits entre les zones ne leur appartiennent pas.
function M.zones(width, height)
	local z = {}
	local inner = width - 2 -- entre les deux bords du cadre
	z.stats = { x = 2, y = 2, w = inner, h = 1 }
	z.year = { x = 2, y = 4, w = inner, h = M.YEAR_HEIGHT } -- sous le trait des chiffres
	local bottom_y = z.year.y + z.year.h + 1 -- sous le trait
	local help_y = height - 1 -- au-dessus du bas du cadre
	local bottom_h = help_y - 1 - bottom_y -- jusqu'au trait au-dessus de l'aide
	local month_w = math.floor(inner * M.MONTH_SHARE)
	z.month = { x = 2, y = bottom_y, w = month_w, h = bottom_h }
	local right_x = 2 + month_w + 1 -- après le trait vertical
	local right_w = width - right_x -- jusqu'au bord droit du cadre
	local week_h = math.floor(bottom_h * M.WEEK_SHARE)
	z.week_side = { x = width - M.WEEK_SIDE, y = bottom_y, w = M.WEEK_SIDE, h = week_h }
	z.week = { x = right_x, y = bottom_y, w = z.week_side.x - 1 - right_x, h = week_h }
	local projects_y = bottom_y + week_h + 1
	local projects_h = bottom_h - week_h - 1 - M.TIMELINE_HEIGHT - 1
	local day_w = math.floor(right_w * M.PROJECTS_SHARE)
	z.day_projects = { x = right_x, y = projects_y, w = day_w, h = projects_h }
	z.week_projects = { x = right_x + day_w + 1, y = projects_y, w = right_w - day_w - 1, h = projects_h }
	z.timeline = { x = right_x, y = projects_y + projects_h + 1, w = right_w, h = M.TIMELINE_HEIGHT }
	z.help = { x = 2, y = help_y, w = inner, h = 1 }
	return z
end

-- Toute la page : exactement `height` lignes de `width` colonnes ; ou nil, la largeur et la hauteur minimum si la
-- fenêtre est trop petite.
--   o = { days, idle_days, projects, timeline, year, month, day_key, today_key, cfg, labels, b, edge, legend, accent }
function M.render(o, width, height)
	if width < M.MIN_WIDTH or height < M.MIN_HEIGHT then
		return nil, M.MIN_WIDTH, M.MIN_HEIGHT
	end
	local b, edge = o.b, o.edge or ""
	local off = edge ~= "" and convert.RESET or ""
	local z = M.zones(width, height)
	-- une grille de caractères : chaque case est un caractère visible (ou un texte avec ses couleurs, déjà à sa place)
	local grid = {}
	for y = 1, height do
		grid[y] = {}
		for x = 1, width do
			grid[y][x] = " "
		end
	end
	local function put(x, y, char)
		grid[y][x] = edge .. char .. off
	end
	local function line(y, x1, x2, char)
		for x = x1, x2 do
			put(x, y, char)
		end
	end
	local function column(x, y1, y2, char)
		for y = y1, y2 do
			put(x, y, char)
		end
	end
	-- le cadre de la page
	line(1, 2, width - 1, b.h)
	line(height, 2, width - 1, b.h)
	column(1, 2, height - 1, b.v)
	column(width, 2, height - 1, b.v)
	put(1, 1, b.tl)
	put(width, 1, b.tr)
	put(1, height, b.bl)
	put(width, height, b.br)
	-- un trait d'un bord à l'autre (├───┤)
	local function across(y)
		line(y, 2, width - 1, b.h)
		put(1, y, b.l)
		put(width, y, b.r)
	end
	-- un trait de la colonne x au bord droit
	local function to_right(y, x)
		line(y, x + 1, width - 1, b.h)
		put(x, y, b.l)
		put(width, y, b.r)
	end
	local below_stats = z.stats.y + 1
	local below_year = z.year.y + z.year.h
	local above_help = z.help.y - 1
	local divider = z.month.x + z.month.w -- le trait vertical entre le mois et la droite
	across(below_stats)
	across(below_year)
	across(above_help)
	column(divider, below_year + 1, above_help - 1, b.v)
	put(divider, below_year, b.t)
	put(divider, above_help, b.b)
	local side = z.week_side.x - 1 -- le trait entre la semaine et ses chiffres
	column(side, z.week.y, z.week.y + z.week.h - 1, b.v)
	put(side, below_year, b.t)
	local under_week = z.week.y + z.week.h
	to_right(under_week, divider)
	put(side, under_week, b.b)
	local between = z.week_projects.x - 1 -- le trait entre les projets du jour et ceux de la semaine
	column(between, z.day_projects.y, z.day_projects.y + z.day_projects.h - 1, b.v)
	put(between, under_week, b.t)
	local above_timeline = z.timeline.y - 1
	to_right(above_timeline, divider)
	put(between, above_timeline, b.b)
	local out = {}
	for y = 1, height do
		out[y] = table.concat(grid[y])
	end
	-- une ligne d'une zone qui prend toute la largeur entre les deux bords
	local function inside(y, text)
		out[y] = edge .. b.v .. off .. text .. edge .. b.v .. off
	end
	for i, text in ipairs(M.year_lines(o, z.year.w)) do
		inside(z.year.y + i - 1, text)
	end
	-- les chiffres de l'année, en haut ; l'aide et la légende, en bas
	local inner = z.stats.w
	inside(z.stats.y, centered(M.join_parts(M.year_parts(o), inner - 2), inner))
	local help = " " .. (o.labels.board_help or "")
	local legend = (o.legend or ""):gsub("^%s+", "") .. " "
	if vw(help) + vw(legend) + 2 <= inner then
		inside(z.help.y, help .. string.rep(" ", inner - vw(help) - vw(legend)) .. legend)
	else
		inside(z.help.y, fit(help, inner))
	end
	return out
end

return M
