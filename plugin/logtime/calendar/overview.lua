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

local M = {}

M.DETAIL_HEIGHT = 10 -- les lignes du détail du jour, sous la grille (une ligne vide comprise)
M.WEEK_LABEL_WIDTH = 10 -- la colonne « Week 1 »
M.MIN_CELL = 6 -- un jour : au moins 6 colonnes (« 4h13 » et de l'air)
M.MIN_ROW = 2 -- une semaine : au moins 2 lignes (le numéro, puis la durée)
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

-- Les noms des jours, dans l'ordre de la semaine (lundi ou dimanche d'abord) : les noms longs s'ils tiennent.
local function day_names(labels, week_starts_on, width)
	local long, short = labels.weekdays_long or labels.weekdays, labels.weekdays
	local names = {}
	for i = 1, 7 do
		-- les listes commencent au lundi
		local index = week_starts_on == "sunday" and ((i + 5) % 7 + 1) or i
		names[i] = (vw(long[index]) <= width - 2) and long[index] or short[index]
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
	local row = (height - 3 - count) // count -- le haut, les noms, leur trait ; un trait sous chaque semaine
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
	local function rule(left, mid, right)
		local parts = { string.rep(b.h, lw) }
		for _ = 1, 7 do
			parts[#parts + 1] = string.rep(b.h, cell)
		end
		return e(left .. table.concat(parts, mid) .. right)
	end
	local out = { rule(b.tl, b.t, b.tr) }
	local names = day_names(o.labels, o.cfg.week_starts_on, cell)
	local header = { centered(o.labels.months[o.month] or "", lw) } -- le nom du mois, au-dessus des semaines
	for i = 1, 7 do
		header[#header + 1] = centered(names[i], cell)
	end
	out[#out + 1] = e(b.v) .. table.concat(header, e(b.v)) .. e(b.v)
	out[#out + 1] = rule(b.l, b.x, b.r)
	for w, week in ipairs(weeks) do
		for line = 1, row do
			local label = line == math.max(1, (row + 1) // 2)
					and centered(string.format(o.labels.overview_week or "Week %d", w), lw)
				or string.rep(" ", lw)
			local parts = { label }
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
						text = " " .. stats.hm(secs)
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
			out[#out + 1] = e(b.v) .. table.concat(parts, e(b.v)) .. e(b.v)
		end
		out[#out + 1] = w < count and rule(b.l, b.x, b.r) or rule(b.bl, b.b, b.br)
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

-- Le détail du jour `key` : exactement `height` lignes de `width` colonnes.
--   o = { days, idle_days, projects, cfg, labels, today_key }
function M.detail(o, key, width, height)
	local labels = o.labels
	local total = math.floor(math.max(0, o.days[key] or 0))
	local idle_secs, idle_percent = idle.share(total, o.idle_days and o.idle_days[key])
	local active = total - idle_secs
	local color = assemble.day_color(total, o.cfg) or M.IDLE_COLOR
	local bar_height = height - 3 -- les durées au-dessus, les noms et les pourcentages en dessous
	local bw = M.BAR_WIDTH
	-- la colonne de chaque barre : assez large pour son nom dans la langue choisie (« Inactif »), et pour « 100% »
	local col = math.max(bw, vw(labels.detail_active), vw(labels.detail_idle), 6)
	local left_width = 2 * col + 3
	local function two(a, b)
		return " " .. centered(a, col) .. " " .. centered(b, col) .. " "
	end
	local left = { fit(two(stats.hm(active), stats.hm(idle_secs)), left_width) }
	local active_bar = M.vertical_bar(total > 0 and active / total or 0, bar_height, color, bw)
	local idle_bar = M.vertical_bar(total > 0 and idle_secs / total or 0, bar_height, M.IDLE_COLOR, bw)
	for i = 1, bar_height do
		left[#left + 1] = fit(two(active_bar[i], idle_bar[i]), left_width)
	end
	left[#left + 1] = fit(two(labels.detail_active, labels.detail_idle), left_width)
	local active_percent = total > 0 and (100 - idle_percent) or 0
	left[#left + 1] = fit(two(active_percent .. "%", (total > 0 and idle_percent or 0) .. "%"), left_width)
	-- à droite : le total et l'objectif, puis les projets
	local right_width = width - left_width - 2
	local right = {}
	local goal_text = ""
	if stats.has_goal(o.cfg.goal_hours) then
		local goal = status.goal_short(o.cfg.goal_hours)
		local missing = stats.hm(o.cfg.goal_hours * 3600 - total)
		if total >= o.cfg.goal_hours * 3600 then
			goal_text = string.format(labels.detail_goal_reached, goal)
		elseif o.today_key and key < o.today_key then
			goal_text = string.format(labels.detail_goal_failed, goal, missing)
		else
			goal_text = string.format(labels.detail_goal_missing, goal, missing)
		end
	end
	right[1] = fit(labels.detail_total .. "  " .. stats.hm(total) .. "   " .. goal_text, right_width)
	local list = {}
	for _, item in ipairs(activity.top(o.projects and o.projects[key], M.PROJECTS)) do
		if item.secs >= 60 then
			list[#list + 1] = item
		end
	end
	if total == 0 then
		right[2] = fit(labels.detail_empty, right_width)
	end
	local name_width = math.min(24, math.max(10, right_width // 3))
	for _, item in ipairs(list) do -- (s'il y en a plus que de lignes, les derniers ne sont simplement pas dessinés)
		local name = item.label == activity.OTHER and labels.detail_other or item.label
		local secs = math.min(item.secs, total)
		local percent = string.format("%3d%%", math.floor(secs * 100 / math.max(1, total) + 0.5))
		local duration = stats.hm(secs)
		local bar_width = math.max(4, right_width - name_width - 2 - 6 - 2 - 2 - vw(percent))
		right[#right + 1] = fit(name, name_width)
			.. "  "
			.. string.rep(" ", 6 - vw(duration))
			.. duration
			.. "  "
			.. hbar(secs / math.max(1, total), bar_width, color)
			.. "  "
			.. percent
	end
	local out = {}
	for i = 1, height do
		out[i] = fit((left[i] or "") .. "  " .. fit(right[i] or "", right_width), width)
	end
	return out
end

-- La largeur et la hauteur minimum de la vue.
function M.minimum(weeks)
	local count = weeks or 6
	return M.WEEK_LABEL_WIDTH + 9 + 7 * M.MIN_CELL, 3 + count * (M.MIN_ROW + 1) + M.DETAIL_HEIGHT
end

-- Toute la vue (la grille du mois, puis le détail du jour `o.day_key`) : exactement `height` lignes de `width`
-- colonnes, ou nil si la zone est trop petite.
--   o = { days, idle_days, projects, year, month, today_key, day_key, cfg, labels, b, edge }
function M.render(o, width, height)
	local weeks = #M.weeks(o.year, o.month, o.cfg.week_starts_on)
	local min_w, min_h = M.minimum(weeks)
	if width < min_w or height < min_h then
		return nil
	end
	local grid = M.grid(o, width, height - M.DETAIL_HEIGHT)
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
	out[#out + 1] = string.rep(" ", width)
	for _, line in ipairs(M.detail(o, o.day_key or o.today_key, width, M.DETAIL_HEIGHT - 1)) do
		out[#out + 1] = line
	end
	while #out < height do
		out[#out + 1] = string.rep(" ", width)
	end
	return out
end

return M
