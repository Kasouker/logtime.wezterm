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
--   o = { days, idle_days, projects, timeline, year, month, day_key, today_key, cfg, labels, b, edge, legend }
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
