-- plugin/logtime/calendar/overview.lua : les morceaux de la vue d'ensemble (calendar/board.lua) qui ne sont pas des
-- zones de la page : les semaines du mois, le texte de l'objectif du jour, la frise d'un jour, la semaine réunie.
-- Aucune dépendance à WezTerm : se teste avec un simple interpréteur Lua.
local load = ...
local dates = load("calendar/dates")
local stats = load("calendar/stats")
local convert = load("color/convert")
local layout = load("calendar/layout")
local idle = load("core/idle")
local activity = load("core/activity")
local status = load("status/status")

local M = {}

M.PROJECTS = 5 -- les plus gros projets (le reste dans « autres »)
M.IDLE_COLOR = "#8B8E99"

local vw = layout.visible_width

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
-- Le texte de l'objectif du jour (atteint, ce qu'il manque, ou manqué pour un jour passé), ou "" sans objectif.
function M.goal_text(o, key, total)
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

M.TIMELINE_HEIGHT = 4 -- la frise : les heures, puis la frise dans son cadre
M.DAY_LENGTH = 24 * 3600
-- Les couleurs des projets, dans l'ordre (le plus gros projet d'abord, calendar/board.lua) : des teintes bien
-- différentes à la suite. Le gris (16) est pour « autres ».
M.TIMELINE_ORDER = { 3, 11, 1, 6, 13, 9, 2, 15, 5, 12, 7, 14, 10, 4, 8 }
M.OTHER_COLOR = "#8B8E99"

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

-- La frise du jour `key` : M.TIMELINE_HEIGHT lignes de `width` colonnes. `colors` : la couleur de chaque projet
-- ({ [projet] = "#RRGGBB" }, board.project_colors) ; un projet sans couleur (ou sans `colors`) est gris.
--   0h00                                                       24h00
--   ╭──────────────────────────────────────────────────────────────╮
--   │   ▓Netflix▓  ▓▓plug WT▓▓▓ ▓▓▓Bot Discord▓▓▓  ▓RL▓            │   chaque projet dans sa couleur, son nom
--   ╰──────────────────────────────────────────────────────────────╯   dedans s'il y tient
function M.timeline(o, key, width, colors)
	local b, edge = o.b, o.edge or ""
	local off = edge ~= "" and convert.RESET or ""
	local function e(s)
		return edge .. s .. off
	end
	local inner = width - 2
	local segments = o.timeline and o.timeline[key] or {}
	colors = colors or {}
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

return M
