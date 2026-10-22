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
local overview = load("calendar/overview")

local M = {}

M.MIN_WIDTH = 120 -- en dessous, la page demande d'agrandir la fenêtre (l'aide tient juste)
M.MIN_HEIGHT = 34
M.YEAR_HEIGHT = 8 -- au moins : les 7 jours de la semaine, puis la ligne des mois (voir M.year_height)
M.MONTH_SHARE = 0.5 -- la part de la largeur pour le mois (à gauche, en bas)
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

M.YEAR_SHARE = 0.35 -- l'année prend au plus cette part de la hauteur de la fenêtre
M.MAX_ROW = 3 -- une ligne de jours : au plus 3 lignes d'écran

-- La hauteur de l'année pour une fenêtre de `height` lignes : 7 lignes de jours (chacune de 1 à M.MAX_ROW lignes
-- d'écran, selon la place), puis la ligne des mois.
function M.year_height(height)
	local row = math.max(1, math.min(M.MAX_ROW, (math.floor(height * M.YEAR_SHARE) - 1) // 7))
	return 7 * row + 1
end

-- L'année : `height` lignes (M.year_height) de `width` colonnes, sur toute la largeur. Un bloc par mois, côte à côte,
-- avec SEULEMENT les jours de ce mois (une colonne par semaine, une ligne par jour de la semaine) ; la place en trop va
-- entre les mois. Chaque jour dans la couleur de ses heures (gris foncé sans travail), aujourd'hui « ◆ ». Les cases
-- grandissent avec la place : « ■ » (comme l'ancienne vue de l'année), puis des pavés de couleur. Les mois en dessous ;
-- on ne choisit pas un jour ici, seulement le mois (rempli de o.accent, sous son bloc).
--   Lun  ■ ■ ■ ■   ■ ■ ■ ■   ■ ■ ■ ■ ■   …
--   …
--   Dim  ■ ■ ■ ■   ■ ■ ■ ■   ■ ■ ■ ■ ■   …
--   2026    Jan       Fév       Mar      …
function M.year_lines(o, width, height)
	height = height or M.YEAR_HEIGHT
	local labels, cfg = o.labels, o.cfg
	local week_starts_on = cfg.week_starts_on
	local row_h = math.max(1, (height - 1) // 7) -- les lignes d'écran par jour de la semaine
	local label_w = 1 + year_view.LABEL -- une colonne d'air contre le cadre, puis « Lun » et deux espaces
	local room = width - label_w
	-- les mois : leurs cases vides avant le 1er, leur nombre de jours, leurs semaines (colonnes)
	local months, total = {}, 0
	for m = 1, 12 do
		local first = dates.offset(o.year, m, week_starts_on)
		local count = dates.days_in_month(o.year, m)
		local weeks = math.ceil((first + count) / 7)
		months[m] = { first = first, count = count, weeks = weeks }
		total = total + weeks
	end
	-- des cases de la même largeur partout ; au moins une colonne entre deux mois
	local base = math.max(1, (room - 13) // total)
	local free = math.max(0, room - base * total)
	local gaps = {} -- avant chaque mois (13 : après le dernier), la place en trop répartie régulièrement
	for k = 1, 13 do
		gaps[k] = k * free // 13 - (k - 1) * free // 13
	end
	local inner = base >= 2 and base - 1 or 1 -- la case, puis une colonne d'air
	local small = inner == 1 and row_h == 1 -- assez petit : les carrés de l'ancienne vue
	-- une case : ses lignes d'écran (row_h), larges de `base`
	local function cell(key, line)
		local secs = math.floor(math.max(0, o.days[key] or 0))
		local color = (secs > 0 and assemble.day_color(secs, cfg)) or year_view.EMPTY_COLOR
		local air = string.rep(" ", base - inner)
		local today = key == o.today_key
		if small then
			return convert.fg(color) .. (today and year_view.TODAY or year_view.DAY) .. convert.RESET .. air
		end
		if line == row_h and row_h > 1 then -- la dernière ligne : une demi-case (de l'air sous elle)
			return convert.fg(color) .. string.rep("▀", inner) .. convert.RESET .. air
		end
		local text = string.rep(" ", inner)
		if today and line == 1 then
			text = centered(year_view.TODAY, inner)
		end
		return convert.bg(color) .. convert.fg(convert.contrast(color)) .. text .. convert.RESET .. air
	end
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
		for line = 1, row_h do
			local parts = { " " .. fit(line == 1 and names[row] or "", year_view.LABEL) }
			for m = 1, 12 do
				local mo = months[m]
				parts[#parts + 1] = string.rep(" ", gaps[m])
				for col = 1, mo.weeks do
					local d = (col - 1) * 7 + row - mo.first
					if d < 1 or d > mo.count then
						parts[#parts + 1] = string.rep(" ", base)
					else
						parts[#parts + 1] = cell(dates.key(o.year, m, d), line)
					end
				end
			end
			out[#out + 1] = fit(table.concat(parts), width)
		end
	end
	-- les mois, en dessous : chacun centré sous son bloc (avec la moitié de l'air de chaque côté)
	local accent = o.accent or M.ACCENT
	local axis = { " " .. fit(tostring(o.year), year_view.LABEL) }
	local carry = 0 -- l'air laissé à droite du mois d'avant
	for m = 1, 12 do
		local before = gaps[m] - carry
		local after = gaps[m + 1] // 2
		carry = after
		if m == 12 then
			after = gaps[13]
		end
		local span = before + months[m].weeks * base + after
		local name = (labels.months_short or {})[m] or labels.months[m]
		local text = centered(name, span)
		if m == o.month then
			text = convert.bg(accent) .. convert.fg(convert.contrast(accent)) .. text .. convert.RESET
		end
		axis[#axis + 1] = text
	end
	out[#out + 1] = fit(table.concat(axis), width)
	return out
end

-- `total` partagé en `count` parts : les parts sont égales à 1 près (les plus grandes réparties régulièrement).
local function split(total, count)
	local out = {}
	for k = 1, count do
		out[k] = k * total // count - (k - 1) * total // count
	end
	return out
end

-- Le mois choisi : exactement `height` lignes de `width` colonnes. La grille du mois dans son propre cadre, qui prend
-- toute la place (une colonne d'air de chaque côté) : 7 colonnes de jours et la colonne des semaines (à droite), de la
-- même largeur à une colonne près ; les semaines de la même hauteur à une ligne près. Les noms des jours et du mois sont
-- posés sur le trait du haut, les semaines et jours validés sur celui du bas (comme le calendrier F2 avec les encadrés).
--   ╭─ Lun ─┬─ Mar ─┬─ … ─┬─ Dim ─┬─ Octobre ─╮
--   │ 12    │ 13    │     │ 18    │           │
--   │ ✓ 8h00│ 5h00  │     │       │ Semaine 3 │   la semaine choisie remplie de o.accent
--   ├───────┼───────┼─ … ─┼───────┼───────────┤
--   ╰─ Semaines validées : 1/5 / Jours validés : 6/31 ─┴───────┴───────╯
function M.month_lines(o, width, height)
	local labels, cfg = o.labels, o.cfg
	local b, edge = o.b, o.edge or ""
	local off = edge ~= "" and convert.RESET or ""
	local function e(s_)
		return edge .. s_ .. off
	end
	local weeks = overview.weeks(o.year, o.month, cfg.week_starts_on)
	local count = #weeks
	local cells = split(math.max(8, width - 2 - 9), 8) -- 8 colonnes, 9 traits verticaux, une colonne d'air de chaque côté
	local rows = split(math.max(count, height - 2 - (count - 1)), count) -- le haut, le bas, un trait entre les semaines
	local narrow = math.min(table.unpack(cells))
	-- un trait de la grille (8 morceaux) avec, au milieu de chaque morceau, un texte (ou rien)
	local function rule(l, mid, r, texts)
		local parts = {}
		for k = 1, 8 do
			local text, cell = texts and texts[k], cells[k]
			if text and text ~= "" and vw(text) + 2 <= cell then
				local before = (cell - vw(text) - 2) // 2
				parts[k] = e(string.rep(b.h, before))
					.. " "
					.. text
					.. " "
					.. e(string.rep(b.h, cell - vw(text) - 2 - before))
			else
				parts[k] = e(string.rep(b.h, cell))
			end
		end
		return " " .. e(l) .. table.concat(parts, e(mid)) .. e(r) .. " "
	end
	-- les noms : les jours en entier s'ils tiennent tous, sinon tous en abrégé ; le mois en entier s'il tient
	local long, short = labels.weekdays_long or labels.weekdays, labels.weekdays
	local fits = true
	for i = 1, 7 do
		fits = fits and vw(long[i]) + 2 <= narrow
	end
	local names = {}
	for i = 1, 7 do
		local index = cfg.week_starts_on == "sunday" and ((i + 5) % 7 + 1) or i
		names[i] = fits and long[index] or short[index]
	end
	local month_name = labels.months[o.month] or ""
	if vw(month_name) + 2 > cells[8] then
		month_name = (labels.months_short or {})[o.month] or month_name
	end
	names[8] = month_name
	local out = { rule(b.tl, b.t, b.tr, names) }
	-- la semaine du jour choisi
	local selected
	local _, sm, sd = (o.day_key or ""):match("^(%d+)-(%d+)-(%d+)$")
	if tonumber(sm) == o.month then
		for w, week in ipairs(weeks) do
			for i = 1, 7 do
				if week[i] == tonumber(sd) then
					selected = w
				end
			end
		end
	end
	local accent = o.accent or M.ACCENT
	local goal_secs = stats.has_goal(cfg.goal_hours) and cfg.goal_hours * 3600 or nil
	for w, week in ipairs(weeks) do
		local week_label = string.format(labels.overview_week or "Week %d", w)
		if vw(week_label) > cells[8] then
			week_label = string.format(labels.overview_week_short or "W%d", w)
		end
		local row = rows[w]
		local label_line = math.max(1, (row + 1) // 2)
		for line = 1, row do
			local parts = {}
			for i = 1, 7 do
				local d, cell = week[i], cells[i]
				if d then
					local key = dates.key(o.year, o.month, d)
					local secs = math.floor(math.max(0, o.days[key] or 0))
					local color = assemble.day_color(secs, cfg)
					local text = ""
					if line == 1 then
						text = " " .. (key == o.today_key and ("*" .. d) or tostring(d))
					elseif line == 2 and secs > 0 then
						text = " " .. assemble.goal_duration(secs, key, o.today_key, goal_secs)
						if vw(text) > cell then -- une case étroite : « ✓8h00 » plutôt qu'une durée coupée
							text = " " .. text:sub(2):gsub("^" .. assemble.GOAL_MARK .. " ", assemble.GOAL_MARK)
						end
					end
					text = fit(text, cell)
					if color then
						text = convert.bg(color) .. convert.fg(convert.contrast(color)) .. text .. convert.RESET
					end
					parts[i] = text
				else
					parts[i] = string.rep(" ", cell)
				end
			end
			local label = line == label_line and centered(week_label, cells[8]) or string.rep(" ", cells[8])
			if w == selected then
				label = convert.bg(accent) .. convert.fg(convert.contrast(accent)) .. label .. convert.RESET
			end
			parts[8] = label
			out[#out + 1] = " " .. e(b.v) .. table.concat(parts, e(b.v)) .. e(b.v) .. " "
		end
		if w < count then
			out[#out + 1] = rule(b.l, b.x, b.r)
		end
	end
	-- le bas : les semaines et jours validés posés dessus (s'ils tiennent), les jonctions ┴ gardées ailleurs
	local bottom = rule(b.bl, b.b, b.br)
	local validated = assemble.validated_text(o.days, o.year, o.month, cfg, nil, labels)
	local grid_w = 9 + cells[1] + cells[2] + cells[3] + cells[4] + cells[5] + cells[6] + cells[7] + cells[8]
	if validated and vw(validated) + 4 <= grid_w - 2 then
		local plain = bottom:gsub("\27%[[%d;]*m", "")
		local cover = 1 + 2 + vw(validated) + 2 -- l'air, « ╰─ », le texte entre deux espaces
		local rest = plain:sub(utf8.offset(plain, cover + 1))
		bottom = " " .. e(b.bl .. b.h) .. " " .. validated .. " " .. e(rest:sub(1, -2)) .. " "
	end
	out[#out + 1] = bottom
	for k = 1, #out do
		out[k] = fit(out[k], width)
	end
	while #out < height do
		out[#out + 1] = string.rep(" ", width)
	end
	return out
end

-- L'aide (« mois : Tab Maj+Tab | semaine : ↑ ↓ | … ») sur `width` colonnes : coupée entre ses parties (« | ») sur
-- autant de lignes qu'il faut, la légende des couleurs au bout de la dernière (ou sur une ligne à elle).
function M.help_lines(help, legend, width)
	local lines, current = {}, nil
	for part in (help .. " | "):gmatch("(.-) | ") do
		local candidate = current and (current .. " | " .. part) or part
		if current and vw(candidate) + 2 > width then
			lines[#lines + 1] = current
			current = part
		else
			current = candidate
		end
	end
	if current then
		lines[#lines + 1] = current
	end
	for k, line in ipairs(lines) do
		lines[k] = fit(" " .. line, width)
	end
	legend = (legend or ""):gsub("^%s+", "")
	if legend ~= "" then
		local last = (lines[#lines] or ""):gsub("%s+$", "")
		if #lines > 0 and vw(last) + 2 + vw(legend) + 1 <= width then
			lines[#lines] = last .. string.rep(" ", width - vw(last) - vw(legend) - 1) .. legend .. " "
		else
			lines[#lines + 1] = string.rep(" ", math.max(0, width - vw(legend) - 1))
				.. fit(legend .. " ", math.min(width, vw(legend) + 1))
		end
	end
	return lines
end

-- Les zones de la page : { x, y, w, h } (x et y à partir de 1), pour une fenêtre de width x height. Le cadre et les
-- traits entre les zones ne leur appartiennent pas. L'aide (help_h lignes, 2 par défaut) est en bas à gauche, sous le
-- mois ; la droite descend jusqu'au bas du cadre.
function M.zones(width, height, help_h)
	help_h = help_h or 2
	local z = {}
	local inner = width - 2 -- entre les deux bords du cadre
	z.stats = { x = 2, y = 2, w = inner, h = 1 }
	z.year = { x = 2, y = 4, w = inner, h = M.year_height(height) } -- sous le trait des chiffres
	local bottom_y = z.year.y + z.year.h + 1 -- sous le trait
	local bottom_h = height - bottom_y -- jusqu'au bas du cadre
	local month_w = math.floor(inner * M.MONTH_SHARE)
	z.month = { x = 2, y = bottom_y, w = month_w, h = bottom_h - help_h }
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
	z.help = { x = 2, y = height - help_h, w = month_w, h = help_h }
	return z
end

-- Les traits, par leurs directions : 1 vers le haut, 2 vers le bas, 4 vers la gauche, 8 vers la droite. Deux traits qui
-- se croisent additionnent leurs directions, et le bon caractère s'en déduit (├ ┬ ┼ …) : la grille du mois peut poser
-- son cadre sur les traits de la page.
local UP, DOWN, LEFT, RIGHT = 1, 2, 4, 8
local function box_chars(b)
	local by_mask = {
		[LEFT + RIGHT] = b.h,
		[UP + DOWN] = b.v,
		[DOWN + RIGHT] = b.tl,
		[DOWN + LEFT] = b.tr,
		[UP + RIGHT] = b.bl,
		[UP + LEFT] = b.br,
		[UP + DOWN + RIGHT] = b.l,
		[UP + DOWN + LEFT] = b.r,
		[DOWN + LEFT + RIGHT] = b.t,
		[UP + LEFT + RIGHT] = b.b,
		[UP + DOWN + LEFT + RIGHT] = b.x,
		[LEFT] = b.h,
		[RIGHT] = b.h,
		[UP] = b.v,
		[DOWN] = b.v,
	}
	-- un trait déjà dessiné : ses directions (un trait seul va des deux côtés)
	local by_char = {
		[b.h] = LEFT + RIGHT,
		[b.v] = UP + DOWN,
		[b.tl] = DOWN + RIGHT,
		[b.tr] = DOWN + LEFT,
		[b.bl] = UP + RIGHT,
		[b.br] = UP + LEFT,
		[b.l] = UP + DOWN + RIGHT,
		[b.r] = UP + DOWN + LEFT,
		[b.t] = DOWN + LEFT + RIGHT,
		[b.b] = UP + LEFT + RIGHT,
		[b.x] = UP + DOWN + LEFT + RIGHT,
	}
	return by_mask, by_char
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
	local by_mask, by_char = box_chars(b)
	local month_w = math.floor((width - 2) * M.MONTH_SHARE)
	local help = M.help_lines(o.labels.board_help or "", o.legend, month_w)
	local z = M.zones(width, height, #help)
	-- chaque case : un nombre (les directions d'un trait) ou un texte (un caractère visible, avec ses couleurs)
	local grid = {}
	for y = 1, height do
		grid[y] = {}
		for x = 1, width do
			grid[y][x] = " "
		end
	end
	local function link(x, y, mask)
		local current = grid[y][x]
		grid[y][x] = (type(current) == "number" and current or 0) | mask
	end
	-- un trait horizontal de x1 à x2 (ses bouts rejoignent ce qu'il touche), un trait vertical de y1 à y2
	local function line(y, x1, x2)
		for x = x1, x2 do
			link(x, y, (x > x1 and LEFT or 0) | (x < x2 and RIGHT or 0))
		end
	end
	local function column(x, y1, y2)
		for y = y1, y2 do
			link(x, y, (y > y1 and UP or 0) | (y < y2 and DOWN or 0))
		end
	end
	-- pose des lignes déjà dessinées (avec leurs couleurs) à partir de (x0, y0) : leurs traits se mêlent aux nôtres
	local function paste(lines, x0, y0)
		for i, text in ipairs(lines) do
			local y, x, k, style = y0 + i - 1, x0, 1, ""
			while k <= #text do
				local code = text:match("^\27%[[%d;]*m", k)
				if code then
					style = code == convert.RESET and "" or (style .. code)
					k = k + #code
				else
					local ch = text:match("^[%z\1-\127\194-\244][\128-\191]*", k)
					k = k + #ch
					if grid[y] and x >= 1 and x <= width then
						if by_char[ch] then
							link(x, y, by_char[ch])
						else
							grid[y][x] = style ~= "" and (style .. ch .. convert.RESET) or ch
						end
					end
					x = x + 1
				end
			end
		end
	end
	-- le cadre de la page, et les traits entre les zones
	local below_stats = z.stats.y + 1
	local below_year = z.year.y + z.year.h
	local divider = z.month.x + z.month.w -- le trait vertical entre le mois et la droite
	local side = z.week_side.x - 1 -- le trait entre la semaine et ses chiffres
	local under_week = z.week.y + z.week.h
	local between = z.week_projects.x - 1 -- le trait entre les projets du jour et ceux de la semaine
	local above_timeline = z.timeline.y - 1
	line(1, 1, width)
	line(height, 1, width)
	column(1, 1, height)
	column(width, 1, height)
	for _, y in ipairs({ below_stats, below_year }) do
		line(y, 1, width)
	end
	column(divider, below_year, height)
	column(side, below_year, under_week)
	line(under_week, divider, width)
	column(between, under_week, above_timeline)
	line(above_timeline, divider, width)
	-- le mois choisi, dans son propre cadre
	paste(M.month_lines(o, z.month.w, z.month.h), z.month.x, z.month.y)
	local out = {}
	for y = 1, height do
		local parts = {}
		for x = 1, width do
			local cell = grid[y][x]
			parts[x] = type(cell) == "number" and (edge .. (by_mask[cell] or " ") .. off) or cell
		end
		out[y] = table.concat(parts)
	end
	-- une ligne d'une zone qui prend toute la largeur entre les deux bords
	local function inside(y, text)
		out[y] = edge .. b.v .. off .. text .. edge .. b.v .. off
	end
	for i, text in ipairs(M.year_lines(o, z.year.w, z.year.h)) do
		inside(z.year.y + i - 1, text)
	end
	-- les chiffres de l'année, en haut ; l'aide et la légende, en bas à gauche (sous le mois)
	local inner = z.stats.w
	inside(z.stats.y, centered(M.join_parts(M.year_parts(o), inner - 2), inner))
	for k, text in ipairs(help) do
		local y = z.help.y + k - 1
		-- la ligne : le bord gauche, l'aide, puis la suite déjà dessinée (à partir du trait vertical du milieu)
		local rest = {}
		for x = divider, width do
			local cell = grid[y][x]
			rest[#rest + 1] = type(cell) == "number" and (edge .. (by_mask[cell] or " ") .. off) or cell
		end
		out[y] = edge .. b.v .. off .. text .. table.concat(rest)
	end
	return out
end

return M
