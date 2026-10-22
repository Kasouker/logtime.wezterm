-- plugin/logtime/calendar/board.lua : la vue « tout en un » de la page F2 (touche a) : l'année, le mois, la semaine et
-- le jour choisis, sur toute la fenêtre, dans un cadre (comme la page F4). Aucune dépendance à WezTerm : se teste avec un
-- simple interpréteur Lua.
--
--   ╭───────────────────────────────────────────────────────────────────────────────────────────────────────────╮
--   │ Total de l'année : 412h10  |  Meilleur jour : 14 octobre (15h35)  |  Inactif : …  |  …    0h ████ 24h │
--   ├───────────────────────────────────────────────────────────────────────────────────────────────────────────┤
--   │                    l'année, comme l'ancienne vue de l'année (calendar/year.lua), centrée                   │
--   ├───────────────────────────────┬───────────────────────────────────────┬───────────────────────────────────┤
--   │ le mois choisi                │ la semaine choisie : 7 colonnes       │ les chiffres de la semaine        │
--   │                               ├───────────────────────────────────────┴───────────────────────────────────┤
--   │                               │ les projets du jour choisi            │ les meilleurs projets de la semaine │
--   │                               ├───────────────────────────────────────┴───────────────────────────────────┤
--   │                               │ la frise du jour choisi                                                     │
--   ├───────────────────────────────┴───────────────────────────────────────────────────────────────────────────┤
--   │ mois : Tab Maj+Tab | semaine : ↑ ↓ | jour : ← → | …                                                      │
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
local day_detail = load("calendar/day_detail")
local activity = load("core/activity")
local palette = load("color/palette")

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

-- La ligne du haut, sur `width` colonnes : les chiffres de l'année à gauche, la légende des couleurs (o.legend) tout à
-- droite. Les chiffres laissent leur place à la légende (les dernières parts sont retirées s'il le faut).
function M.stats_line(o, width)
	local legend = o.legend or ""
	local room = width - 2 - (legend ~= "" and vw(legend) + 3 or 0) -- l'air des bords, et au moins 3 avant la légende
	local left = " " .. M.join_parts(M.year_parts(o), room)
	return fit(left .. string.rep(" ", math.max(1, width - vw(left) - vw(legend) - 1)) .. legend .. " ", width)
end

-- La légende des couleurs du calendrier (assemble.legend), sans « * = aujourd'hui » au bout : comme sur la maquette,
-- seulement les couleurs (au bout de la ligne des chiffres de l'année).
function M.legend(legend, labels)
	local today = labels.today or ""
	if today ~= "" and legend:sub(-#today) == today then
		legend = legend:sub(1, -#today - 1)
	end
	return (legend:gsub("%s+$", ""))
end

M.ACCENT = "#8B8E99" -- la couleur du mois choisi sous l'année (sans o.accent)

M.MIN_BOTTOM = 24 -- l'année grandit tant qu'il reste au moins ces lignes en bas (le mois, la semaine, la frise)
M.MAX_ROW = 3 -- une ligne de jours : au plus 3 lignes d'écran

-- La hauteur de l'année pour une fenêtre de `height` lignes : 7 lignes de jours (chacune de 1 à M.MAX_ROW lignes
-- d'écran : la plus grande qui laisse M.MIN_BOTTOM lignes en bas), puis la ligne des mois.
function M.year_height(height)
	local row = 1
	for r = 2, M.MAX_ROW do
		if height - (7 * r + 1) - 5 >= M.MIN_BOTTOM then -- le cadre, les chiffres, leur trait, le trait sous l'année
			row = r
		end
	end
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
	-- des cases de la même largeur partout, aussi larges que possible (deux mois peuvent se toucher)
	local base = math.max(1, room // total)
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
-- toute la largeur (une colonne d'air de chaque côté) : 7 colonnes de jours et la colonne des semaines (à droite), de la
-- même largeur à une colonne près ; toutes les semaines exactement de la même hauteur (les lignes en trop autour du cadre, centré). Les noms des jours et du mois sont
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
	-- toutes les semaines de la même hauteur (les lignes en trop vont autour du cadre)
	local row_h = math.max(1, (height - 2 - (count - 1)) // count) -- le haut, le bas, un trait entre les semaines
	local rows = {}
	for w = 1, count do
		rows[w] = row_h
	end
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
	-- les lignes en trop (moins d'une semaine) : autant au-dessus qu'en dessous du cadre (la dernière, s'il en reste
	-- une, en dessous) : centré dans sa zone
	local blank = string.rep(" ", width)
	for _ = 1, (height - #out) // 2 do
		table.insert(out, 1, blank)
	end
	while #out < height do
		out[#out + 1] = blank
	end
	return out
end

-- La semaine du jour choisi : ses 7 jours, chacun { key, day (le numéro), total, idle, active }, et ses chiffres :
-- { days, total, idle, active_days, average, best (le jour le plus long, ou nil), reached (jours à l'objectif) }.
function M.week_stats(o)
	local keys = overview.week_keys(o.day_key or o.today_key, o.cfg.week_starts_on)
	local goal = stats.has_goal(o.cfg.goal_hours) and o.cfg.goal_hours * 3600 or nil
	local w = { days = {}, total = 0, idle = 0, active_days = 0, reached = 0 }
	for i, key in ipairs(keys) do
		local total = math.floor(math.max(0, o.days[key] or 0))
		local idle_secs = o.idle_days and idle.share(total, o.idle_days[key]) or 0
		local day =
			{ key = key, day = tonumber(key:sub(9, 10)), total = total, idle = idle_secs, active = total - idle_secs }
		w.days[i] = day
		w.total = w.total + total
		w.idle = w.idle + idle_secs
		if total > 0 then
			w.active_days = w.active_days + 1
		end
		if goal and total >= goal then
			w.reached = w.reached + 1
		end
		if total > 0 and (not w.best or total > w.best.total) then
			w.best = day
		end
	end
	w.average = w.active_days > 0 and w.total // w.active_days or 0
	return w
end

M.BAR_MAX = 3 -- une barre de la semaine : au plus 3 colonnes de large
-- la partie vide d'une barre : « ░ » gris foncé, comme les barres du détail d'un jour (calendar/day_detail.lua)
M.TRACK = day_detail.BAR_EMPTY_COLOR
M.TRACK_CHAR = "░"

-- Une barre verticale de `height` lignes et `width` colonnes, remplie à `share` (0 à 1) par le bas, en lignes entières
-- (une case coupée, comme « ▂ », laisserait un vide noir entre la barre et le « ░ » au-dessus), au moins une ligne
-- dès qu'il y a du temps ; le reste de sa place en « ░ » gris foncé (on voit toute la place de la barre, même vide),
-- comme les barres du détail d'un jour.
local function track_bar(share, height, color, width)
	share = math.max(0, math.min(1, share))
	local filled = math.floor(share * height + 0.5)
	if share > 0 then
		filled = math.max(1, filled)
	end
	local out = {}
	for line = 1, height do
		if line > height - filled then
			out[line] = convert.fg(color) .. string.rep("█", width) .. convert.RESET
		else
			out[line] = convert.fg(M.TRACK) .. string.rep(M.TRACK_CHAR, width) .. convert.RESET
		end
	end
	return out
end

-- Un texte de `width` colonnes, centré sur une barre qui commence à la colonne `at` (depuis 0) et fait `bar` de large
-- (sans sortir de sa place).
local function place(text, width, at, bar)
	local len = vw(text)
	local start = math.max(0, math.min(width - len, at + (bar - len) // 2))
	return fit(string.rep(" ", start) .. text, width)
end

-- La semaine choisie : exactement `height` lignes de `width` colonnes, dans son propre cadre (une colonne d'air de
-- chaque côté), les jours posés sur le trait du haut. 7 colonnes séparées par un trait ; dans chacune, la durée en haut, les barres (inactif en gris, actif dans la couleur du
-- jour, à l'échelle du jour le plus long de la semaine), leurs noms et leurs pourcentages en bas. Le jour choisi est
-- rempli de o.accent. Sans temps inactif compté (o.idle_days absent), seulement la barre de l'actif.
--   ╭─ Lun 12 ─┬─ Mar 13 ─┬ … ╮
--   │1h00  7h00│0h00  5h00│   │
--   │ ▆▆   ███ │      ███ │   │
--   │Inact Actif│ …       │   │
--   │ 13%  87% │          │   │
--   ╰──────────┴──────────┴ … ╯
function M.week_lines(o, width, height)
	local full_height = height
	height = height - 2 -- le haut et le bas du cadre
	local labels, cfg = o.labels, o.cfg
	local b, edge = o.b, o.edge or ""
	local off = edge ~= "" and convert.RESET or ""
	local function e(s_)
		return edge .. s_ .. off
	end
	local w = M.week_stats(o)
	local cells = split(math.max(7, width - 2 - 8), 7) -- une colonne d'air de chaque côté, 8 traits verticaux
	local scale = 3600 -- l'échelle des barres : le jour le plus long de la semaine (au moins une heure)
	for _, day in ipairs(w.days) do
		scale = math.max(scale, day.total)
	end
	local show_idle = o.idle_days and true or false -- (le temps inactif non compté : pas de tableau)
	-- les textes selon la colonne la plus étroite (toutes pareilles, jamais un mélange) : les deux durées, les noms des
	-- barres en entier et les deux pourcentages s'ils tiennent ; sinon le total, « I A » et le pourcentage de l'actif
	local narrowest = math.min(table.unpack(cells))
	local half_min = (narrowest - 1) // 2
	local both_durations = 2 * 5 + 1 <= narrowest -- « 10h04 10h04 »
	local idle_name, active_name = labels.board_idle_short or "", labels.board_active_short or ""
	if vw(idle_name) > half_min or vw(active_name) > narrowest - half_min - 1 then
		idle_name, active_name = labels.board_idle_letter or "", labels.board_active_letter or ""
	end
	local both_percents = 4 <= half_min -- « 100% »
	local accent = o.accent or M.ACCENT
	-- le trait du haut : « ─ Lun 12 ─ » au milieu de chaque colonne
	local names = {}
	for i = 1, 7 do
		local index = cfg.week_starts_on == "sunday" and ((i + 5) % 7 + 1) or i
		names[i] = labels.weekdays[index]
	end
	local top = {}
	for i, day in ipairs(w.days) do
		local cell = cells[i]
		local text = names[i] .. " " .. day.day
		if vw(text) + 2 > cell then
			text = vw(names[i]) + 2 <= cell and names[i] or ""
		end
		if text == "" then
			top[i] = e(string.rep(b.h, cell))
		else
			local before = (cell - vw(text) - 2) // 2
			top[i] = e(string.rep(b.h, before))
				.. " "
				.. text
				.. " "
				.. e(string.rep(b.h, cell - vw(text) - 2 - before))
		end
	end
	local out = { " " .. e(b.tl) .. table.concat(top, e(b.t)) .. e(b.tr) .. " " }
	-- chaque colonne : ses lignes
	local columns = {}
	for i, day in ipairs(w.days) do
		local cell = cells[i]
		local color = assemble.day_color(day.total, cfg) or overview.IDLE_COLOR
		local lines = {}
		local _, percent = idle.share(day.total, day.idle)
		if show_idle then
			-- deux barres, toujours, collées : l'inactif (gris) à gauche, l'actif (couleur du jour) à droite ; les deux
			-- ensemble centrées dans la case, les deux textes ensemble centrés sur elles
			local bw = math.min(M.BAR_MAX, math.max(1, (narrowest - 2) // 2)) -- la même largeur dans toutes les colonnes
			local pad = (cell - 2 * bw) // 2
			-- les deux textes ensemble (un espace entre eux), centrés sur les deux barres
			local function pair(a, b_)
				return place(a .. " " .. b_, cell, pad, 2 * bw)
			end
			local bar_h = math.max(1, height - 3)
			if day.total > 0 then
				lines[1] = both_durations and pair(stats.hm(day.idle), stats.hm(day.active))
					or centered(stats.hm(day.total), cell)
			else
				lines[1] = ""
			end
			local ib = track_bar(day.idle / scale, bar_h, overview.IDLE_COLOR, bw)
			local ab = track_bar(day.active / scale, bar_h, color, bw)
			for k = 1, bar_h do
				lines[#lines + 1] = string.rep(" ", pad) .. ib[k] .. ab[k]
			end
			lines[#lines + 1] = pair(idle_name, active_name)
			if day.total > 0 then
				lines[#lines + 1] = both_percents and pair(percent .. "%", (100 - percent) .. "%")
					or centered((100 - percent) .. "%", cell)
			else
				lines[#lines + 1] = ""
			end
		else
			-- le temps inactif n'est pas compté : seulement la barre de l'actif, centrée
			local bw = math.min(2 * M.BAR_MAX + 1, math.max(1, cell - 4))
			local pad = (cell - bw) // 2
			local bar_h = math.max(1, height - 2)
			lines[1] = centered(day.total > 0 and stats.hm(day.active) or "", cell)
			local ab = track_bar(day.active / scale, bar_h, color, bw)
			for k = 1, bar_h do
				lines[#lines + 1] = string.rep(" ", pad) .. ab[k]
			end
			lines[#lines + 1] = centered(day.total > 0 and "100%" or "", cell)
		end
		if day.key == o.day_key then
			for k, line in ipairs(lines) do
				-- le jour choisi : la colonne remplie de la couleur (les barres gardent leurs couleurs)
				local style = convert.bg(accent) .. convert.fg(convert.contrast(accent))
				lines[k] = style
					.. fit(line, cell):gsub("\27%[0m", convert.RESET .. convert.bg(accent))
					.. convert.RESET
			end
		end
		columns[i] = lines
	end
	for k = 1, height do
		local parts = {}
		for i = 1, 7 do
			parts[i] = fit(columns[i][k] or "", cells[i])
		end
		out[#out + 1] = " " .. e(b.v) .. table.concat(parts, e(b.v)) .. e(b.v) .. " "
	end
	local bottom = {}
	for i = 1, 7 do
		bottom[i] = string.rep(b.h, cells[i])
	end
	out[#out + 1] = " " .. e(b.bl .. table.concat(bottom, b.b) .. b.br) .. " "
	for k = 1, #out do
		out[k] = fit(out[k], width)
	end
	while #out < full_height do
		out[#out + 1] = string.rep(" ", width)
	end
	return out
end

-- La colonne des chiffres de la semaine (à droite des 7 colonnes) : `height` lignes de `width` colonnes. En haut, le
-- total, les jours actifs, la moyenne, l'inactif, le meilleur jour et l'objectif de la semaine ; en bas, le jour choisi.
function M.week_side_lines(o, width, height)
	local labels, c = o.labels, o.labels.colon
	local w = M.week_stats(o)
	local items = {
		string.format("%s%s%s", labels.board_week_total, c, stats.hm(w.total)),
		string.format("%s%s%d", labels.board_active_days, c, w.active_days),
		string.format("%s%s%s", labels.board_average, c, stats.hm(w.average)),
	}
	if o.idle_days and w.total > 0 then
		local _, percent = idle.share(w.total, w.idle)
		items[#items + 1] = string.format(labels.idle_year, stats.hm(w.idle), percent)
	end
	if w.best then
		local index = (
			os.date(
				"*t",
				os.time({
					year = tonumber(w.best.key:sub(1, 4)),
					month = tonumber(w.best.key:sub(6, 7)),
					day = w.best.day,
					hour = 12,
				})
			).wday + 5
		)
				% 7
			+ 1
		items[#items + 1] = string.format(
			"%s%s%s %d (%s)",
			labels.board_best,
			c,
			labels.weekdays[index],
			w.best.day,
			stats.hm(w.best.total)
		)
	end
	if stats.has_goal(o.cfg.goal_hours) then
		local goal_days = math.floor(tonumber(o.cfg.goal_days) or 5)
		local format = w.reached >= goal_days and labels.board_week_validated or labels.board_week_goal
		items[#items + 1] = string.format(format, w.reached, goal_days)
	end
	local out = {}
	for _, item in ipairs(items) do
		if #out < height - 3 then
			out[#out + 1] = fit(" " .. item, width)
		end
	end
	while #out < height - 2 do
		out[#out + 1] = string.rep(" ", width)
	end
	-- en bas : le jour choisi
	out[#out + 1] = fit(" " .. labels.board_selected .. c, width)
	out[#out + 1] = fit(" " .. day_detail.title(o.day_key or o.today_key, labels), width)
	return out
end

-- Les couleurs des projets de la semaine choisie, les mêmes dans les deux listes et sur la frise : les plus gros
-- projets de la semaine d'abord (dans l'ordre des couleurs de la frise), puis ceux du jour choisi qui n'en font pas
-- partie ; « autres » en gris. { [projet] = "#RRGGBB" }
function M.project_colors(o)
	local keys = overview.week_keys(o.day_key or o.today_key, o.cfg.week_starts_on)
	local week = overview.week_data(o, keys)
	local order = activity.top(week.projects[overview.WEEK_KEY], overview.PROJECTS)
	for _, item in ipairs(activity.top(o.projects and o.projects[o.day_key or o.today_key], overview.PROJECTS)) do
		order[#order + 1] = item
	end
	local colors, n = { [activity.OTHER] = overview.OTHER_COLOR }, 0
	for _, item in ipairs(order) do
		if not colors[item.label] then
			n = n + 1
			colors[item.label] = palette.COLORS[overview.TIMELINE_ORDER[(n - 1) % #overview.TIMELINE_ORDER + 1]]
		end
	end
	return colors
end

-- Une barre horizontale de `width` colonnes, remplie à `share` dans sa couleur, le reste en « ░ » gris foncé.
local function hbar(share, width, color)
	local filled = math.floor(math.max(0, math.min(1, share)) * width + 0.5)
	return convert.fg(color)
		.. string.rep("█", filled)
		.. convert.fg(M.TRACK)
		.. string.rep(M.TRACK_CHAR, width - filled)
		.. convert.RESET
end

-- Une liste de projets dans son cadre (une colonne d'air de chaque côté), le titre posé sur le trait du haut (à
-- gauche, ou au milieu si `middle`) : exactement `height` lignes de `width` colonnes.
--   ╭─ Par projet (temps actif) ─────────╮
--   │ Total  10h00                       │   `head` : la première ligne
--   │ ✓ objectif atteint                 │   `goal` : la deuxième (rien sans objectif)
--   │                                    │   (une ligne d'air s'il y a la place)
--   │ Bot Discord  5h00 ██████░░░░░  50% │   les plus gros projets (au moins une minute), le reste dans « autres »
--   ╰────────────────────────────────────╯
--   `of` : le temps par projet ({ [projet] = secondes }), `total` : le temps dont on prend la part (les pourcentages),
--   `color(projet)` : la couleur de sa barre, `empty` : le texte quand rien n'est compté.
local function project_box(o, width, height, title, middle, head, goal, of, total, color, empty)
	local b, edge = o.b, o.edge or ""
	local off = edge ~= "" and convert.RESET or ""
	local function e(s_)
		return edge .. s_ .. off
	end
	local inner_w = width - 4 -- l'air et les deux bords
	local inner_h = height - 2
	local rows = { " " .. head }
	if goal ~= "" then -- toujours sur sa ligne : les projets du jour et de la semaine commencent à la même hauteur
		rows[2] = " " .. goal
	end
	-- une ligne d'air sous la tête si les projets et « autres » tiennent quand même : selon la hauteur seulement (les
	-- deux listes, de même hauteur, commencent à la même ligne)
	local air = inner_h - #rows >= overview.PROJECTS + 2
	local room = inner_h - #rows - (air and 1 or 0) -- les lignes des projets
	local list = {}
	if total > 0 then
		local all = activity.top(of, overview.PROJECTS)
		if #all > room then -- pas la place pour tous : moins de projets, le reste dans « autres » (avec une seule
			-- ligne, « autres » tombe sous le cadre : seul le plus gros projet se voit)
			all = activity.top(of, math.max(1, room - 1))
		end
		for _, item in ipairs(all) do
			if item.secs >= 60 then -- moins d'une minute s'afficherait « 0h00 »
				list[#list + 1] = item
			end
		end
	end
	if total == 0 then
		rows[#rows + 1] = " " .. empty
	elseif air then
		rows[#rows + 1] = ""
	end
	-- les colonnes : le nom, la durée (« 10h04 »), la barre, le pourcentage (« 100% »)
	local longest = 0
	for _, item in ipairs(list) do
		longest = math.max(longest, vw(item.label == activity.OTHER and o.labels.detail_other or item.label))
	end
	local fixed = 1 + 1 + 5 + 1 + 1 + 4 + 1 -- l'air, la durée, le pourcentage et les espaces entre eux
	-- le nom le plus long (au plus 24), en laissant au moins 4 colonnes à la barre
	local name_w = math.max(1, math.min(longest, 24, inner_w - fixed - 4))
	local bar_w = math.max(1, inner_w - fixed - name_w)
	for _, item in ipairs(list) do
		local name = item.label == activity.OTHER and o.labels.detail_other or item.label
		local secs = math.min(item.secs, total) -- jamais plus que le total (deux fichiers fusionnés peuvent se contredire)
		local duration = stats.hm(secs)
		local percent = string.format("%d%%", math.floor(secs * 100 / total + 0.5))
		rows[#rows + 1] = " "
			.. fit(name, name_w)
			.. " "
			.. string.rep(" ", 5 - vw(duration))
			.. duration
			.. " "
			.. hbar(secs / total, bar_w, color(item.label))
			.. " "
			.. string.rep(" ", 4 - vw(percent))
			.. percent
	end
	local top
	if vw(title) + 4 > inner_w then
		title = ""
	end
	if title == "" then
		top = e(b.tl .. string.rep(b.h, inner_w) .. b.tr)
	else
		local before = middle and (inner_w - vw(title) - 2) // 2 or 1
		top = e(b.tl .. string.rep(b.h, before))
			.. " "
			.. title
			.. " "
			.. e(string.rep(b.h, inner_w - vw(title) - 2 - before) .. b.tr)
	end
	local out = { " " .. top .. " " }
	for k = 1, inner_h do
		out[#out + 1] = " " .. e(b.v) .. fit(rows[k] or "", inner_w) .. e(b.v) .. " "
	end
	out[#out + 1] = " " .. e(b.bl .. string.rep(b.h, inner_w) .. b.br) .. " "
	return out
end

-- Les projets du jour choisi (« Par projet (temps actif) ») : le total et l'objectif du jour, puis ses plus gros
-- projets. Exactement `height` lignes de `width` colonnes. `colors` : M.project_colors (nil : la couleur du jour).
function M.day_projects_lines(o, width, height, colors)
	local labels = o.labels
	local key = o.day_key or o.today_key
	local total = math.floor(math.max(0, o.days[key] or 0))
	local day_color = assemble.day_color(total, o.cfg) or overview.IDLE_COLOR
	local head = labels.detail_total .. "  " .. stats.hm(total)
	return project_box(
		o,
		width,
		height,
		labels.detail_projects,
		false,
		head,
		overview.goal_text(o, key, total),
		o.projects and o.projects[key],
		total,
		function(label)
			return colors and colors[label] or day_color
		end,
		labels.detail_empty
	)
end

-- Les meilleurs projets de la semaine choisie : le total de la semaine, puis ses plus gros projets. Exactement
-- `height` lignes de `width` colonnes. `colors` : M.project_colors (nil : la couleur de la moyenne de la semaine).
function M.week_projects_lines(o, width, height, colors)
	local labels = o.labels
	local w = M.week_stats(o)
	local keys = overview.week_keys(o.day_key or o.today_key, o.cfg.week_starts_on)
	local week = overview.week_data(o, keys)
	local week_color = assemble.day_color(w.average, o.cfg) or overview.IDLE_COLOR
	local head = labels.detail_total .. "  " .. stats.hm(w.total)
	local goal = ""
	if stats.has_goal(o.cfg.goal_hours) then
		local goal_days = math.floor(tonumber(o.cfg.goal_days) or 5)
		local format = w.reached >= goal_days and labels.board_week_validated or labels.board_week_goal
		goal = string.format(format, w.reached, goal_days)
	end
	return project_box(
		o,
		width,
		height,
		labels.board_week_projects or "",
		true,
		head,
		goal,
		week.projects[overview.WEEK_KEY],
		w.total,
		function(label)
			return colors and colors[label] or week_color
		end,
		labels.overview_week_empty
	)
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
		-- au bout de la dernière ligne seulement si elle ne passe sous aucun texte de l'aide (pas « à cheval »)
		local longest = 0
		for _, line in ipairs(lines) do
			longest = math.max(longest, vw((line:gsub("%s+$", ""))))
		end
		if #lines > 0 and longest + 2 + vw(legend) + 1 <= width then
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
-- mois ; la droite descend jusqu'au bas du cadre. Sans frise (`no_timeline`), les projets prennent sa place.
function M.zones(width, height, help_h, no_timeline)
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
	local timeline_h = no_timeline and 0 or M.TIMELINE_HEIGHT
	local projects_h = bottom_h - week_h - 1 - (no_timeline and 0 or timeline_h + 1)
	local day_w = math.floor(right_w * M.PROJECTS_SHARE)
	z.day_projects = { x = right_x, y = projects_y, w = day_w, h = projects_h }
	z.week_projects = { x = right_x + day_w + 1, y = projects_y, w = right_w - day_w - 1, h = projects_h }
	z.timeline = { x = right_x, y = projects_y + projects_h + 1, w = right_w, h = timeline_h }
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
	local help = M.help_lines(o.labels.board_help or "", nil, month_w) -- la légende est en haut (M.stats_line)
	local show_timeline = o.cfg.show_timeline ~= false
	local z = M.zones(width, height, #help, not show_timeline)
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
	if show_timeline then
		column(between, under_week, above_timeline)
		line(above_timeline, divider, width)
	else
		column(between, under_week, height)
	end
	-- le mois choisi, dans son propre cadre
	paste(M.month_lines(o, z.month.w, z.month.h), z.month.x, z.month.y)
	-- la semaine choisie, dans son propre cadre, puis ses chiffres à droite
	paste(M.week_lines(o, z.week.w, z.week.h), z.week.x, z.week.y)
	paste(M.week_side_lines(o, z.week_side.w, z.week_side.h), z.week_side.x, z.week_side.y)
	-- les projets du jour et de la semaine, et la frise du jour : un projet a la même couleur partout (sans frise, les
	-- barres gardent la couleur du jour, comme le détail d'un jour)
	local colors = show_timeline and M.project_colors(o) or nil
	paste(M.day_projects_lines(o, z.day_projects.w, z.day_projects.h, colors), z.day_projects.x, z.day_projects.y)
	paste(M.week_projects_lines(o, z.week_projects.w, z.week_projects.h, colors), z.week_projects.x, z.week_projects.y)
	if show_timeline then
		paste(overview.timeline(o, o.day_key or o.today_key, z.timeline.w - 2, colors), z.timeline.x + 1, z.timeline.y)
	end
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
	-- les chiffres de l'année et la légende, en haut ; l'aide, en bas à gauche (sous le mois)
	local inner = z.stats.w
	inside(z.stats.y, M.stats_line(o, inner))
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
