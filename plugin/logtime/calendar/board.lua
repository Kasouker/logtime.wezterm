-- plugin/logtime/calendar/board.lua : la vue « tout en un » de la page F2 (touche a) : l'année, le mois, la semaine et
-- le jour choisis, sur toute la fenêtre. Aucune dépendance à WezTerm : se teste avec un simple interpréteur Lua.
--
--    Total de l'année : 412h10  |  Meilleur jour : 14 octobre (15h35)  |  Inactif : …  |  Semaines validées : …
--   ───────────────────────────────────────────────────────────────────────────────────────────────────────────
--    l'année : une case par jour (7 lignes, une colonne par semaine), les mois en dessous
--   ───────────────────────────────┬───────────────────────────────────────┬───────────────────────────────────
--    le mois choisi                │ la semaine choisie : 7 colonnes       │ les chiffres de la semaine
--                                  ├───────────────────────────────────────┴───────────────────────────────────
--                                  │ les projets du jour choisi            │ les meilleurs projets de la semaine
--                                  ├───────────────────────────────────────────────────────────────────────────
--                                  │ la frise du jour choisi
--   ───────────────────────────────┴───────────────────────────────────────────────────────────────────────────
--    mois : Tab Maj+Tab | semaine : ↑ ↓ | jour : ← → | …                                          la légende
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
M.MIN_HEIGHT = 32
M.YEAR_HEIGHT = 8 -- les 7 jours de la semaine, puis les mois
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

-- Le numéro du jour dans l'année (1 pour le 1er janvier) et le nombre de jours de l'année.
local function yday(year, month, day)
	return os.date("*t", os.time({ year = year, month = month, day = day, hour = 12 })).yday
end

-- L'année : M.YEAR_HEIGHT lignes de `width` colonnes. Une case par jour (7 lignes, une colonne par semaine), dans la
-- couleur de ses heures (comme le calendrier) ; aujourd'hui « ◆ », le jour choisi en couleurs inversées. Dessous, les
-- mois, chacun sous sa première semaine ; le mois choisi rempli de o.accent.
--   Lundi    │ ■ ■ ■ ■ ■ ■ ■ ■ ■ …
--   …
--   Dimanche │ ■ ■ ■ ■ ■ ■ ■ ■ ■ …
--     2026   │ Jan     Fév     …   ▐ Oct ▌ …
function M.year_lines(o, width)
	local labels, cfg = o.labels, o.cfg
	local b, edge = o.b, o.edge or ""
	local off = edge ~= "" and convert.RESET or ""
	local week_starts_on = cfg.week_starts_on
	local offset = dates.offset(o.year, 1, week_starts_on)
	local columns = year_view.columns(o.year, week_starts_on)
	local count = yday(o.year, 12, 31)
	-- la colonne des jours de la semaine : les noms longs (« Mercredi »), le premier jour de la semaine d'abord
	local names, label_w = {}, 0
	for i = 1, 7 do
		local index = week_starts_on == "sunday" and ((i + 5) % 7 + 1) or i
		names[i] = (labels.weekdays_long or labels.weekdays)[index]
		label_w = math.max(label_w, vw(names[i]))
	end
	label_w = label_w + 2
	local room = width - label_w - 1 -- après le trait vertical
	-- des cases toutes de la même largeur ; la place qui reste va entre les mois (avant la semaine du 1er de chaque mois,
	-- et aux deux bouts) : les mois se détachent, et l'année prend toute la largeur
	local base = math.max(1, room // columns)
	local starts = {}
	for month = 1, 12 do
		starts[month] = math.floor((yday(o.year, month, 1) - 1 + offset) / 7) + 1
	end
	local free = math.max(0, room - base * columns)
	local gaps = {} -- l'espace en plus avant une colonne
	local slots = { 1 } -- le bord gauche, puis le début de chaque mois (sauf janvier)
	for month = 2, 12 do
		slots[#slots + 1] = starts[month]
	end
	local share, extra = free // (#slots + 1), free % (#slots + 1) -- + 1 : le bord droit
	for k, col in ipairs(slots) do
		gaps[col] = (gaps[col] or 0) + share + (k <= extra and 1 or 0)
	end
	local cells, at, x = {}, {}, 0
	for col = 1, columns do
		x = x + (gaps[col] or 0)
		at[col] = x -- la position de la colonne, depuis le trait
		cells[col] = base
		x = x + base
	end
	local marks = math.max(1, base - 1) -- les carrés par case, puis une colonne d'air
	local accent = o.accent or M.ACCENT
	local out = {}
	for row = 1, 7 do
		local parts = { " " .. fit(names[row], label_w - 1), edge .. b.v .. off }
		for col = 1, columns do
			local i = (col - 1) * 7 + row - offset
			local cell = cells[col]
			parts[#parts + 1] = string.rep(" ", gaps[col] or 0)
			if i < 1 or i > count then
				parts[#parts + 1] = string.rep(" ", cell)
			else
				local key = dates.key_any(o.year, 1, i)
				local secs = math.floor(math.max(0, o.days[key] or 0))
				local color = (secs > 0 and assemble.day_color(secs, cfg)) or year_view.EMPTY_COLOR
				local mark = (key == o.today_key) and year_view.TODAY or year_view.DAY
				local shown = math.min(marks, cell)
				local text = string.rep(mark, shown) .. string.rep(" ", cell - shown)
				if key == o.day_key then
					text = assemble.SELECTED .. convert.fg(color) .. text .. convert.RESET
				else
					text = convert.fg(color) .. text .. convert.RESET
				end
				parts[#parts + 1] = text
			end
		end
		out[row] = fit(table.concat(parts), width)
	end
	-- les mois : chacun sous la semaine de son 1er jour ; le mois choisi rempli jusqu'au mois suivant
	local axis = { " " .. fit(centered(tostring(o.year), label_w - 1), label_w - 1), edge .. b.v .. off }
	local cursor = 1 -- la prochaine colonne de semaine à écrire
	local function x_of(col) -- la position d'une colonne depuis le trait (columns + 1 : la fin)
		return col > columns and x or at[col]
	end
	for month = 1, 12 do
		local first = starts[month]
		local last = (starts[month + 1] or (columns + 1)) - 1
		if first >= cursor then
			axis[#axis + 1] = string.rep(" ", x_of(first) - x_of(cursor))
			local span = x_of(last + 1) - x_of(first)
			local name = (labels.months_short or {})[month] or labels.months[month]
			local text = centered(name, span)
			if month == o.month then
				text = convert.bg(accent) .. convert.fg(convert.contrast(accent)) .. text .. convert.RESET
			end
			axis[#axis + 1] = text
			cursor = last + 1
		end
	end
	out[8] = fit(table.concat(axis), width)
	return out
end

-- Les zones de la page : { x, y, w, h } (x et y à partir de 1), pour une fenêtre de width x height. Les traits entre les
-- zones ne leur appartiennent pas.
function M.zones(width, height)
	local z = {}
	z.stats = { x = 1, y = 1, w = width, h = 1 }
	z.year = { x = 1, y = 3, w = width, h = M.YEAR_HEIGHT }
	local bottom_y = z.year.y + z.year.h + 1 -- sous le trait
	local bottom_h = height - bottom_y - 1 -- le trait du bas, puis l'aide
	local month_w = math.floor(width * M.MONTH_SHARE)
	local right_x = month_w + 2 -- après le trait vertical
	local right_w = width - right_x + 1
	z.month = { x = 1, y = bottom_y, w = month_w, h = bottom_h }
	local week_h = math.floor(bottom_h * M.WEEK_SHARE)
	z.week = { x = right_x, y = bottom_y, w = right_w - M.WEEK_SIDE - 1, h = week_h }
	z.week_side = { x = width - M.WEEK_SIDE + 1, y = bottom_y, w = M.WEEK_SIDE, h = week_h }
	local projects_y = bottom_y + week_h + 1
	local projects_h = bottom_h - week_h - 1 - M.TIMELINE_HEIGHT
	local day_w = math.floor(right_w * M.PROJECTS_SHARE)
	z.day_projects = { x = right_x, y = projects_y, w = day_w, h = projects_h }
	z.week_projects = { x = right_x + day_w + 1, y = projects_y, w = right_w - day_w - 1, h = projects_h }
	z.timeline = { x = right_x, y = projects_y + projects_h, w = right_w, h = M.TIMELINE_HEIGHT }
	z.help = { x = 1, y = height, w = width, h = 1 }
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
	local function line(y, x1, x2, char)
		for x = x1, x2 do
			grid[y][x] = edge .. char .. off
		end
	end
	local function column(x, y1, y2, char)
		for y = y1, y2 do
			grid[y][x] = edge .. char .. off
		end
	end
	local function put(x, y, char)
		grid[y][x] = edge .. char .. off
	end
	-- les traits entre les zones
	local below_year = z.year.y + z.year.h
	local above_help = z.help.y - 1
	local divider = z.month.x + z.month.w -- le trait vertical entre le mois et la droite
	line(2, 1, width, b.h)
	line(below_year, 1, width, b.h)
	line(above_help, 1, width, b.h)
	column(divider, below_year + 1, above_help - 1, b.v)
	put(divider, below_year, b.t)
	put(divider, above_help, b.b)
	local side = z.week_side.x - 1 -- le trait entre la semaine et ses chiffres
	column(side, z.week.y, z.week.y + z.week.h - 1, b.v)
	put(side, below_year, b.t)
	local under_week = z.week.y + z.week.h
	line(under_week, divider + 1, width, b.h)
	put(divider, under_week, b.l)
	put(side, under_week, b.b)
	local between = z.week_projects.x - 1 -- le trait entre les projets du jour et ceux de la semaine
	column(between, z.day_projects.y, z.day_projects.y + z.day_projects.h - 1, b.v)
	put(between, under_week, b.t)
	local above_timeline = z.timeline.y - 1
	if above_timeline > under_week then
		line(above_timeline, divider + 1, width, b.h)
		put(divider, above_timeline, b.l)
		put(between, above_timeline, b.b)
	end
	local out = {}
	for y = 1, height do
		out[y] = table.concat(grid[y])
	end
	for i, text in ipairs(M.year_lines(o, z.year.w)) do
		out[z.year.y + i - 1] = text
	end
	-- les chiffres de l'année, en haut ; l'aide et la légende, en bas
	out[z.stats.y] = centered(M.join_parts(M.year_parts(o), width), width)
	local help = " " .. (o.labels.board_help or "")
	local legend = o.legend or ""
	if vw(help) + vw(legend) + 2 <= width then
		out[z.help.y] = help .. string.rep(" ", width - vw(help) - vw(legend)) .. legend
	else
		out[z.help.y] = fit(help, width)
	end
	return out
end

return M
