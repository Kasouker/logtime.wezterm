-- plugin/logtime/calendar/overview.lua : la vue du mois et du jour, dessinée dans une zone de largeur x hauteur (l'aperçu
-- de la page F4). Aucune dépendance à WezTerm : se teste avec un simple interpréteur Lua.
--
--   ╭──────────┬────────┬────────┬─ … ─┬────────╮
--   │          │ Monday │Tuesday │     │ Sunday │   les jours de la semaine
--   ├──────────┼────────┼────────┼─ … ─┼────────┤
--   │  Week 1  │        │        │     │ 4      │   une ligne par semaine ; chaque jour du mois dans la couleur de
--   │          │        │        │     │ 2h10   │   sa durée (le numéro, puis la durée)
--   ├──────────┼────────┼ …
--   ╰──────────┴────────┴ …
--   8h05  1h55   Total  10h04   ✓ 8h goal reached
--   ████        Bot Discord           5h00  ████████████        40%
--   ████  ▆▆▆   Plug WT               3h00  ███████             25%   le détail du jour : deux barres verticales
--   ████  ███   …                                                      (actif, inactif), puis les projets
--   Active Idle
--    80%  20%
local load = ...
local dates = load("calendar/dates")
local stats = load("calendar/stats")
local assemble = load("calendar/assemble")
local convert = load("color/convert")
local layout = load("calendar/layout")
local idle = load("core/idle")
local activity = load("core/activity")
local status = load("status/status")
local palette = load("color/palette")

local M = {}

M.DETAIL_HEIGHT = 10 -- les lignes du détail du jour, sous la grille (une ligne vide comprise)
M.WEEK_LABEL_WIDTH = 10 -- la colonne « Week 1 »
M.MIN_CELL = 6 -- un jour : au moins 6 colonnes (« 4h13 » et de l'air)
M.MIN_ROW = 2 -- une semaine : au moins 2 lignes (le numéro, puis la durée)...
M.MAX_ROW = 3 -- ... et au plus 3 (une ligne d'air) : la grille ne grossit pas avec la fenêtre
M.BAR_WIDTH = 4 -- une barre verticale (actif, inactif)
M.PROJECTS = 5 -- les plus gros projets (le reste dans « autres »)
M.IDLE_COLOR = "#8B8E99"
M.EMPTY_COLOR = "#3B404C"

local vw = layout.visible_width
local EIGHTHS = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }

local function fit(text, width)
	local len = vw(text)
	if len <= width then
		return text .. string.rep(" ", width - len)
	end
	local plain = text:gsub("\27%[[%d;]*m", "")
	local cut = plain:sub(1, (utf8.offset(plain, width + 1) or (#plain + 1)) - 1)
	return cut .. string.rep(" ", width - (utf8.len(cut) or #cut))
end

local function centered(text, width)
	local left = math.max(0, (width - vw(text)) // 2)
	return fit(string.rep(" ", left) .. text, width)
end

-- Les semaines du mois : { { jour ou nil, … 7 } , … }, selon le premier jour de la semaine.
function M.weeks(year, month, week_starts_on)
	local first = dates.offset(year, month, week_starts_on) -- les cases vides avant le 1er
	local count = dates.days_in_month(year, month)
	local weeks, day = {}, 1 - first
	while day <= count do
		local week = {}
		for i = 1, 7 do
			week[i] = (day >= 1 and day <= count) and day or false
			day = day + 1
		end
		weeks[#weeks + 1] = week
	end
	return weeks
end

-- Les noms des jours, dans l'ordre de la semaine (lundi ou dimanche d'abord) : les noms longs s'ils tiennent TOUS,
-- sinon tous en abrégé (jamais un mélange « Lundi … Mer »).
local function day_names(labels, week_starts_on, width)
	local long, short = labels.weekdays_long or labels.weekdays, labels.weekdays
	local fits = true
	for i = 1, 7 do
		fits = fits and vw(long[i]) <= width - 2
	end
	local names = {}
	for i = 1, 7 do
		-- les listes commencent au lundi
		local index = week_starts_on == "sunday" and ((i + 5) % 7 + 1) or i
		names[i] = fits and long[index] or short[index]
	end
	return names
end

-- La grille du mois : exactement `height` lignes de `width` colonnes, ou nil si elle ne tient pas.
--   o = { days, year, month, today_key, cfg, labels, b (les traits), edge (leur couleur) }
function M.grid(o, width, height)
	local weeks = M.weeks(o.year, o.month, o.cfg.week_starts_on)
	local count = #weeks
	local lw = M.WEEK_LABEL_WIDTH
	local cell = (width - lw - 9) // 7 -- 9 traits verticaux
	local avail = height - 3 - count -- le haut, les noms, leur trait ; un trait par semaine
	-- o.stretch : les semaines prennent toute la hauteur (les lignes en trop vont aux premières semaines) ; sinon au plus
	-- M.MAX_ROW lignes chacune
	local row = o.stretch and avail // count or math.min(M.MAX_ROW, avail // count)
	local tall = o.stretch and avail % count or 0 -- les semaines qui ont une ligne de plus
	if cell < M.MIN_CELL or row < M.MIN_ROW then
		return nil
	end
	local extra = width - lw - 9 - 7 * cell -- les colonnes en trop vont à la colonne des semaines
	lw = lw + extra
	local b, edge = o.b, o.edge or ""
	local off = edge ~= "" and convert.RESET or ""
	local function e(s)
		return edge .. s .. off
	end
	-- o.labels_right : la colonne des semaines (et le nom du mois) à droite des jours, au lieu de la gauche
	local function ordered(label, days)
		if o.labels_right then
			days[#days + 1] = label
			return days
		end
		table.insert(days, 1, label)
		return days
	end
	local function rule(left, mid, right)
		local parts = {}
		for _ = 1, 7 do
			parts[#parts + 1] = string.rep(b.h, cell)
		end
		return e(left .. table.concat(ordered(string.rep(b.h, lw), parts), mid) .. right)
	end
	local out = { rule(b.tl, b.t, b.tr) }
	local names = day_names(o.labels, o.cfg.week_starts_on, cell)
	local header = {}
	for i = 1, 7 do
		header[#header + 1] = centered(names[i], cell)
	end
	-- le nom du mois, au-dessus des semaines
	header = ordered(centered(o.labels.months[o.month] or "", lw), header)
	out[#out + 1] = e(b.v) .. table.concat(header, e(b.v)) .. e(b.v)
	out[#out + 1] = rule(b.l, b.x, b.r)
	-- o.week : la semaine du jour o.day_key est choisie, sa case « Semaine N » est remplie de la couleur o.accent
	local selected
	if o.week and o.day_key then
		local y, m, d = o.day_key:match("^(%d+)-(%d+)-(%d+)$")
		if tonumber(y) == o.year and tonumber(m) == o.month then
			for w, week in ipairs(weeks) do
				for i = 1, 7 do
					if week[i] == tonumber(d) then
						selected = w
					end
				end
			end
		end
	end
	local accent = o.accent or M.IDLE_COLOR
	local goal_secs = stats.has_goal(o.cfg.goal_hours) and o.cfg.goal_hours * 3600 or nil
	for w, week in ipairs(weeks) do
		local lines = row + (w <= tall and 1 or 0)
		for line = 1, lines do
			local label = line == math.max(1, (lines + 1) // 2)
					and centered(string.format(o.labels.overview_week or "Week %d", w), lw)
				or string.rep(" ", lw)
			if w == selected then
				label = convert.bg(accent) .. convert.fg(convert.contrast(accent)) .. label .. convert.RESET
			end
			local parts = {}
			for i = 1, 7 do
				local d = week[i]
				if d then
					local key = dates.key(o.year, o.month, d)
					local secs = math.floor(math.max(0, o.days[key] or 0))
					local color = assemble.day_color(secs, o.cfg)
					local text = ""
					if line == 1 then
						text = " " .. (key == o.today_key and ("*" .. d) or tostring(d))
					elseif line == 2 and secs > 0 then
						-- comme dans le calendrier F2 : « ✓ 8h02 » si l'objectif est atteint, rayée pour un jour passé manqué
						text = " " .. assemble.goal_duration(secs, key, o.today_key, goal_secs)
					end
					text = fit(text, cell)
					if color then
						text = convert.bg(color) .. convert.fg(convert.contrast(color)) .. text .. convert.RESET
					end
					parts[#parts + 1] = text
				else
					parts[#parts + 1] = string.rep(" ", cell)
				end
			end
			out[#out + 1] = e(b.v) .. table.concat(ordered(label, parts), e(b.v)) .. e(b.v)
		end
		out[#out + 1] = w < count and rule(b.l, b.x, b.r) or rule(b.bl, b.b, b.br)
	end
	-- avec un objectif, comme dans le calendrier F2 : « Semaines validées : 1/5 / Jours validés : 6/31 » sur le bas du
	-- cadre (s'il y tient)
	local validated = assemble.validated_text(o.days, o.year, o.month, o.cfg, nil, o.labels)
	if validated and vw(validated) + 4 <= width - 2 then
		local bottom = rule(b.bl, b.b, b.br)
		local plain = bottom:gsub("\27%[[%d;]*m", "")
		local rest = plain:sub((utf8.offset(plain, vw(validated) + 5) or (#plain + 1)))
		out[#out] = e(b.bl .. b.h) .. " " .. validated .. " " .. e(rest)
	end
	while #out < height do
		out[#out + 1] = string.rep(" ", width)
	end
	return out
end

-- Une barre verticale de `height` lignes et `width` colonnes, remplie à `share` (0 à 1) par le bas, au huitième de
-- ligne près (▁ ▂ … █). Vide, il reste son « sol » (▁ sur la ligne du bas, en gris).
function M.vertical_bar(share, height, color, width)
	local eighths = math.floor(math.max(0, math.min(1, share)) * height * 8 + 0.5)
	local out = {}
	for line = 1, height do
		local filled = eighths - (height - line) * 8 -- ce qui reste à remplir dans cette ligne (en huitièmes)
		local char = filled >= 8 and "█" or (filled > 0 and EIGHTHS[filled]) or nil
		if char then
			out[line] = convert.fg(color) .. string.rep(char, width) .. convert.RESET
		elseif line == height then
			out[line] = convert.fg(M.EMPTY_COLOR) .. string.rep("▁", width) .. convert.RESET
		else
			out[line] = string.rep(" ", width)
		end
	end
	return out
end

-- Une barre horizontale de `width` colonnes, remplie à `share`.
local function hbar(share, width, color)
	local filled = math.floor(math.max(0, math.min(1, share)) * width + 0.5)
	return convert.fg(color)
		.. string.rep("█", filled)
		.. convert.fg(M.EMPTY_COLOR)
		.. string.rep("░", width - filled)
		.. convert.RESET
end

-- Le texte de l'objectif du jour (atteint, ce qu'il manque, ou manqué pour un jour passé), ou "" sans objectif.
local function goal_text(o, key, total)
	if not stats.has_goal(o.cfg.goal_hours) then
		return ""
	end
	local labels = o.labels
	local goal = status.goal_short(o.cfg.goal_hours)
	local missing = stats.hm(o.cfg.goal_hours * 3600 - total)
	if total >= o.cfg.goal_hours * 3600 then
		return string.format(labels.detail_goal_reached, goal)
	elseif o.today_key and key < o.today_key then
		return string.format(labels.detail_goal_failed, goal, missing)
	end
	return string.format(labels.detail_goal_missing, goal, missing)
end

M.PERCENT_WIDTH = 6 -- la colonne des pourcentages (« 100% » et de l'air)
M.DURATION_WIDTH = 6 -- « 10h04 »

-- Les projets du détail du jour `key` : les plus gros (au moins une minute), le reste dans « autres ».
function M.day_projects(o, key)
	local projects = {}
	for _, item in ipairs(activity.top(o.projects and o.projects[key], M.PROJECTS)) do
		if item.secs >= 60 then
			projects[#projects + 1] = item
		end
	end
	return projects
end

-- Le détail du jour `key`, dans un tableau encadré : exactement `height` lignes de `width` colonnes.
--   ╭─────┬─────┬─────────────────────────────────────┬──────╮
--   │8h05 │1h55 │ Total  10h04       ✓ objectif atteint│      │   l'objectif aligné sur le début des barres
--   │     │     ├──────────────────────────────────────┼──────┤
--   │████ │     │ Bot Discord   5h00  ████████░░░░░░░░ │  40% │   un trait entre les projets s'il y a la place
--   │████ │ ▆▆▆ │ …                                    │      │
--   │Actif│Inact│                                      │      │
--   │ 80% │ 20% │                                      │      │
--   ╰─────┴─────┴──────────────────────────────────────┴──────╯
--   o = { days, idle_days, projects, cfg, labels, today_key, b (les traits), edge (leur couleur) }
--   opts (facultatif) = { goal = le texte à la place de l'objectif du jour, empty = le texte quand rien n'est compté }
function M.detail(o, key, width, height, opts)
	opts = opts or {}
	local labels = o.labels
	local b, edge = o.b, o.edge or ""
	local off = edge ~= "" and convert.RESET or ""
	local function e(s)
		return edge .. s .. off
	end
	local total = math.floor(math.max(0, o.days[key] or 0))
	local idle_secs, idle_percent = idle.share(total, o.idle_days and o.idle_days[key])
	local active = total - idle_secs
	local color = assemble.day_color(total, o.cfg) or M.IDLE_COLOR
	local inner = height - 2 -- sans le haut et le bas du cadre
	-- à gauche : deux colonnes (actif, inactif), assez larges pour leur nom dans la langue choisie
	local col = math.max(M.BAR_WIDTH + 2, vw(labels.detail_active) + 2, vw(labels.detail_idle) + 2, 6)
	local bar_height = math.max(1, inner - 3) -- la durée au-dessus, le nom et le pourcentage en dessous
	local active_bar = M.vertical_bar(total > 0 and active / total or 0, bar_height, color, M.BAR_WIDTH)
	local idle_bar = M.vertical_bar(total > 0 and idle_secs / total or 0, bar_height, M.IDLE_COLOR, M.BAR_WIDTH)
	-- count_idle = false : le temps inactif n'est pas compté, sa colonne disparaît (la place va à la liste)
	local show_idle = o.cfg.count_idle ~= false
	local active_column = { centered(stats.hm(active), col) }
	local idle_column = { centered(stats.hm(idle_secs), col) }
	for i = 1, bar_height do
		active_column[#active_column + 1] = centered(active_bar[i], col)
		idle_column[#idle_column + 1] = centered(idle_bar[i], col)
	end
	active_column[#active_column + 1] = centered(labels.detail_active, col)
	idle_column[#idle_column + 1] = centered(labels.detail_idle, col)
	active_column[#active_column + 1] = centered((total > 0 and (100 - idle_percent) or 0) .. "%", col)
	idle_column[#idle_column + 1] = centered((total > 0 and idle_percent or 0) .. "%", col)
	-- à droite : la liste (le total, puis les projets) et la colonne des pourcentages
	local columns = show_idle and 2 or 1
	local list_width = width - columns * col - columns - 3 - M.PERCENT_WIDTH -- les traits verticaux
	local name_width = math.min(24, math.max(10, list_width // 3))
	local bar_start = 1 + name_width + 2 + M.DURATION_WIDTH + 2 -- là où commencent les barres des projets
	local bar_width = math.max(4, list_width - bar_start - 1)
	local projects = M.day_projects(o, key)
	-- avec la frise, chaque projet a sa couleur (la même que sur la frise) ; sans elle, la couleur du jour
	local project_colors = o.cfg.show_timeline ~= false and M.day_colors(o, key) or nil
	-- les lignes de droite : { texte de la liste, texte du pourcentage } ou "rule" (un trait entre deux lignes)
	local total_text = " " .. labels.detail_total .. "  " .. stats.hm(total)
	local rows = { { fit(total_text, bar_start) .. (opts.goal or goal_text(o, key, total)), "" }, "rule" }
	if total == 0 then
		rows[#rows + 1] = { " " .. (opts.empty or labels.detail_empty), "" }
	end
	local spaced = #projects > 0 and (2 * #projects - 1) <= inner - 2 -- un trait entre les projets s'il y a la place
	for n, item in ipairs(projects) do
		local name = item.label == activity.OTHER and labels.detail_other or item.label
		local secs = math.min(item.secs, total)
		local duration = stats.hm(secs)
		rows[#rows + 1] = {
			" "
				.. fit(name, name_width)
				.. "  "
				.. string.rep(" ", M.DURATION_WIDTH - vw(duration))
				.. duration
				.. "  "
				.. hbar(secs / math.max(1, total), bar_width, project_colors and project_colors[item.label] or color),
			string.format("%d%%", math.floor(secs * 100 / math.max(1, total) + 0.5)),
		}
		if spaced and n < #projects then
			rows[#rows + 1] = "rule"
		end
	end
	local idle_top = show_idle and (string.rep(b.h, col) .. b.t) or ""
	local idle_bottom = show_idle and (string.rep(b.h, col) .. b.b) or ""
	local out = {
		e(
			b.tl
				.. string.rep(b.h, col)
				.. b.t
				.. idle_top
				.. string.rep(b.h, list_width)
				.. b.t
				.. string.rep(b.h, M.PERCENT_WIDTH)
				.. b.tr
		),
	}
	for i = 1, inner do
		local left = e(b.v) .. fit(active_column[i] or "", col)
		if show_idle then
			left = left .. e(b.v) .. fit(idle_column[i] or "", col)
		end
		local row = rows[i]
		if row == "rule" then
			out[#out + 1] = left
				.. e(b.l .. string.rep(b.h, list_width) .. b.x .. string.rep(b.h, M.PERCENT_WIDTH) .. b.r)
		else
			row = row or { "", "" }
			out[#out + 1] = left
				.. e(b.v)
				.. fit(row[1], list_width)
				.. e(b.v)
				.. string.rep(" ", math.max(0, M.PERCENT_WIDTH - 1 - vw(row[2])))
				.. row[2]
				.. " "
				.. e(b.v)
		end
	end
	out[#out + 1] = e(
		b.bl
			.. string.rep(b.h, col)
			.. b.b
			.. idle_bottom
			.. string.rep(b.h, list_width)
			.. b.b
			.. string.rep(b.h, M.PERCENT_WIDTH)
			.. b.br
	)
	for k = 1, #out do
		out[k] = fit(out[k], width)
	end
	return out
end

M.TIMELINE_HEIGHT = 4 -- la frise : les heures, puis la frise dans son cadre
M.DAY_LENGTH = 24 * 3600
-- Les couleurs des projets sur la frise, dans l'ordre (le plus gros projet du jour d'abord) : des teintes bien
-- différentes à la suite. Le gris (16) est pour « autres ».
M.TIMELINE_ORDER = { 3, 11, 1, 6, 13, 9, 2, 15, 5, 12, 7, 14, 10, 4, 8 }
M.OTHER_COLOR = "#8B8E99"

-- Les couleurs des projets d'un jour : { [projet] = "#RRGGBB" }, le plus gros projet du jour d'abord.
function M.timeline_colors(segments)
	local totals, labels = {}, {}
	for _, seg in ipairs(segments or {}) do
		if not totals[seg[3]] then
			labels[#labels + 1] = seg[3]
			totals[seg[3]] = 0
		end
		totals[seg[3]] = totals[seg[3]] + (seg[2] - seg[1])
	end
	table.sort(labels, function(a, b)
		if totals[a] ~= totals[b] then
			return totals[a] > totals[b]
		end
		return a < b
	end)
	local colors, n = {}, 0
	for _, label in ipairs(labels) do
		if label == activity.OTHER then
			colors[label] = M.OTHER_COLOR
		else
			n = n + 1
			colors[label] = palette.COLORS[M.TIMELINE_ORDER[(n - 1) % #M.TIMELINE_ORDER + 1]]
		end
	end
	return colors
end

-- Les couleurs des projets du jour `key`, les mêmes sur la frise et dans le détail : dans l'ordre des projets du détail
-- (le plus gros d'abord), « autres » en gris. Un projet de la frise absent du détail (regroupé dans « autres ») est gris
-- aussi. Sans temps par projet ce jour-là : les couleurs de la frise seule (M.timeline_colors).
function M.day_colors(o, key)
	local projects = M.day_projects(o, key)
	if #projects == 0 then
		return M.timeline_colors(o.timeline and o.timeline[key])
	end
	local colors, n = {}, 0
	for _, item in ipairs(projects) do
		if item.label == activity.OTHER then
			colors[item.label] = M.OTHER_COLOR
		else
			n = n + 1
			colors[item.label] = palette.COLORS[M.TIMELINE_ORDER[(n - 1) % #M.TIMELINE_ORDER + 1]]
		end
	end
	return colors
end

-- Le projet de chaque colonne de la frise : la journée découpée en `columns` parts égales ; dans chaque part, le projet
-- qui y a passé le plus de temps (ou nil si personne). Renvoie une liste de `columns` projets (ou false).
function M.timeline_columns(segments, columns)
	local out = {}
	local step = M.DAY_LENGTH / columns
	for c = 1, columns do
		local t0, t1 = (c - 1) * step, c * step
		local best, best_time = false, 0
		local time = {}
		for _, seg in ipairs(segments or {}) do
			local overlap = math.min(t1, seg[2]) - math.max(t0, seg[1])
			if overlap > 0 then
				time[seg[3]] = (time[seg[3]] or 0) + overlap
				if time[seg[3]] > best_time then
					best, best_time = seg[3], time[seg[3]]
				end
			end
		end
		out[c] = best
	end
	return out
end

-- Une ligne de frise : les colonnes (un projet ou false chacune), par suites du même projet, chacune dans sa couleur,
-- avec le nom dedans s'il y tient en entier (jamais un nom coupé).
local function band(columns, colors, labels)
	local parts = {}
	local c = 1
	while c <= #columns do
		local label = columns[c]
		local run = c
		while run + 1 <= #columns and columns[run + 1] == label do
			run = run + 1
		end
		local length = run - c + 1
		if label then
			local name = label == activity.OTHER and labels.detail_other or label
			local text = (vw(name) + 2 <= length) and centered(name, length) or string.rep(" ", length)
			local color = colors[label] or M.OTHER_COLOR
			parts[#parts + 1] = convert.bg(color) .. convert.fg(convert.contrast(color)) .. text .. convert.RESET
		else
			parts[#parts + 1] = string.rep(" ", length)
		end
		c = run + 1
	end
	return table.concat(parts)
end

-- « 0h00 », ou l'heure où la journée commence (`day_offset` : -3600 -> la journée commence à 1h00).
local function clock(seconds)
	seconds = seconds % (24 * 3600)
	return string.format("%dh%02d", seconds // 3600, (seconds % 3600) // 60)
end

-- La frise du jour `key` : M.TIMELINE_HEIGHT lignes de `width` colonnes.
--   0h00                                                       24h00
--   ╭──────────────────────────────────────────────────────────────╮
--   │   ▓Netflix▓  ▓▓plug WT▓▓▓ ▓▓▓Bot Discord▓▓▓  ▓RL▓            │   chaque projet dans sa couleur, son nom
--   ╰──────────────────────────────────────────────────────────────╯   dedans s'il y tient
function M.timeline(o, key, width)
	local b, edge = o.b, o.edge or ""
	local off = edge ~= "" and convert.RESET or ""
	local function e(s)
		return edge .. s .. off
	end
	local inner = width - 2
	local segments = o.timeline and o.timeline[key] or {}
	local colors = M.day_colors(o, key)
	local columns = M.timeline_columns(segments, inner)
	local start = -(o.cfg.day_offset or 0)
	-- la fin de la journée : « 24h00 » (et pas « 0h00 ») quand elle finit à minuit
	local first = clock(start)
	local last = (start % M.DAY_LENGTH == 0) and "24h00" or clock(start + M.DAY_LENGTH)
	local hours = " " .. first .. string.rep(" ", math.max(1, width - 2 - vw(first) - vw(last))) .. last .. " "
	return {
		fit(hours, width),
		e(b.tl .. string.rep(b.h, inner) .. b.tr),
		e(b.v) .. band(columns, colors, o.labels) .. e(b.v),
		e(b.bl .. string.rep(b.h, inner) .. b.br),
	}
end

-- Les 7 jours de la semaine qui contient `key` ("AAAA-MM-JJ"), ceux des mois voisins compris, dans l'ordre de la
-- semaine (lundi ou dimanche d'abord).
function M.week_keys(key, week_starts_on)
	local y, m, d = key:match("^(%d+)-(%d+)-(%d+)$")
	y, m, d = tonumber(y), tonumber(m), tonumber(d)
	local first = d - (dates.offset(y, m, week_starts_on) + d - 1) % 7
	local keys = {}
	for i = 0, 6 do
		keys[#keys + 1] = dates.key_any(y, m, first + i)
	end
	return keys
end

M.WEEK_KEY = "week" -- la semaine réunie en un seul « jour » (pour le dessiner comme un jour)

-- La semaine `keys` réunie : une copie de o où M.WEEK_KEY porte la somme des 7 jours (le total, l'inactif, les
-- projets). Renvoie aussi le nombre de jours où l'objectif est atteint.
function M.week_data(o, keys)
	local total, idle_total, projects, reached = 0, 0, {}, 0
	local goal = stats.has_goal(o.cfg.goal_hours) and o.cfg.goal_hours * 3600 or nil
	for _, k in ipairs(keys) do
		local secs = math.floor(math.max(0, o.days[k] or 0))
		total = total + secs
		idle_total = idle_total + idle.share(secs, o.idle_days and o.idle_days[k])
		for label, p in pairs(o.projects and o.projects[k] or {}) do
			projects[label] = (projects[label] or 0) + p
		end
		if goal and secs >= goal then
			reached = reached + 1
		end
	end
	local week = {}
	for k, value in pairs(o) do
		week[k] = value
	end
	week.days = { [M.WEEK_KEY] = total }
	week.idle_days = { [M.WEEK_KEY] = idle_total }
	week.projects = { [M.WEEK_KEY] = projects }
	return week, reached
end

-- Le détail de la semaine `keys` : le même tableau que celui du jour, avec les 7 jours additionnés ; à la place de
-- l'objectif du jour, combien de jours l'ont atteint (« 3/5 jours à l'objectif », « ✓ semaine validée »).
function M.week_detail(o, keys, width, height)
	local week, reached = M.week_data(o, keys)
	local goal = ""
	if stats.has_goal(o.cfg.goal_hours) then
		local goal_days = math.floor(tonumber(o.cfg.goal_days) or 5)
		local format = reached >= goal_days and o.labels.detail_week_validated or o.labels.detail_week_goal
		goal = string.format(format, reached, goal_days)
	end
	return M.detail(week, M.WEEK_KEY, width, height, { goal = goal, empty = o.labels.overview_week_empty })
end

-- La frise de la semaine `keys` : M.TIMELINE_HEIGHT lignes de `width` colonnes, une part par jour (de 0h00 à 24h00
-- chacune), séparées par un trait, le nom du jour au-dessus. Un projet garde la même couleur toute la semaine.
--    Lundi    Mardi    Mercredi   …
--   ╭────────┬────────┬────────┬ … ╮
--   │▓Bot▓  ▓│  ▓▓▓▓  │        │   │
--   ╰────────┴────────┴────────┴ … ╯
function M.week_timeline(o, keys, width)
	local b, edge = o.b, o.edge or ""
	local off = edge ~= "" and convert.RESET or ""
	local function e(s)
		return edge .. s .. off
	end
	local inner = width - 8 -- 2 bords et 6 traits entre les jours
	local base, extra = inner // 7, inner % 7
	local all = {}
	for _, k in ipairs(keys) do
		for _, seg in ipairs(o.timeline and o.timeline[k] or {}) do
			all[#all + 1] = seg
		end
	end
	local colors = M.timeline_colors(all)
	local names = day_names(o.labels, o.cfg.week_starts_on, base)
	local head, top, middle, bottom = { " " }, {}, {}, {}
	for i, k in ipairs(keys) do
		local w = base + (i <= extra and 1 or 0)
		head[#head + 1] = centered(names[i], w) .. " "
		top[#top + 1] = string.rep(b.h, w)
		bottom[#bottom + 1] = string.rep(b.h, w)
		middle[#middle + 1] = band(M.timeline_columns(o.timeline and o.timeline[k] or {}, w), colors, o.labels)
	end
	return {
		fit(table.concat(head), width),
		e(b.tl .. table.concat(top, b.t) .. b.tr),
		e(b.v) .. table.concat(middle, e(b.v)) .. e(b.v),
		e(b.bl .. table.concat(bottom, b.b) .. b.br),
	}
end

M.GRID_SHARE = 0.5 -- la grille du mois prend au plus cette part de la hauteur ; le détail du jour, le reste
M.MIN_DETAIL = 10 -- le détail : au moins 10 lignes (cadre compris)

-- La largeur et la hauteur minimum de la vue (une grille de `weeks` semaines).
function M.minimum(weeks)
	local count = weeks or 6
	return M.WEEK_LABEL_WIDTH + 9 + 7 * M.MIN_CELL, 3 + count * (M.MIN_ROW + 1) + M.MIN_DETAIL + M.TIMELINE_HEIGHT
end

-- Toute la vue (la grille du mois, puis le détail du jour `o.day_key`, ou de sa semaine si `o.week`, puis la frise du jour) : exactement `height` lignes de `width`
-- colonnes, ou nil si la zone est trop petite. La grille ne prend pas plus de M.GRID_SHARE de la hauteur (sinon elle
-- écrase le détail) ; le détail, juste dessous, prend tout le reste.
--   o = { days, idle_days, projects, timeline, year, month, today_key, day_key, week, accent, cfg, labels, b, edge }
function M.render(o, width, height)
	local weeks = #M.weeks(o.year, o.month, o.cfg.week_starts_on)
	local min_w, min_h = M.minimum(weeks)
	if width < min_w or height < min_h then
		return nil
	end
	local smallest_grid = 3 + weeks * (M.MIN_ROW + 1)
	local grid_height =
		math.max(smallest_grid, math.min(height - M.MIN_DETAIL - M.TIMELINE_HEIGHT, math.floor(height * M.GRID_SHARE)))
	local grid = M.grid(o, width, grid_height)
	if not grid then
		return nil
	end
	local out = {}
	for _, line in ipairs(grid) do
		out[#out + 1] = fit(line, width)
	end
	-- la grille n'utilise peut-être pas toute sa hauteur (les semaines ont une hauteur entière) : le détail juste dessous
	while #out > 0 and out[#out]:match("^ *$") do
		out[#out] = nil
	end
	local key = o.day_key or o.today_key
	local week = o.week and M.week_keys(key, o.cfg.week_starts_on)
	local show_timeline = o.cfg.show_timeline ~= false -- show_timeline = false : pas de frise, le détail prend sa place
	local below = show_timeline and M.TIMELINE_HEIGHT or 0
	local detail = week and M.week_detail(o, week, width, height - #out - below)
		or M.detail(o, key, width, height - #out - below)
	for _, line in ipairs(detail) do
		out[#out + 1] = line
	end
	-- la frise reste celle du jour, même en semaine (plus lisible ; celle de la semaine servira à F2)
	for _, line in ipairs(show_timeline and M.timeline(o, key, width) or {}) do
		out[#out + 1] = line
	end
	return out
end

return M
