-- plugin/logtime/calendar/day_detail.lua : le détail d'un jour (touche Entrée dans le calendrier) : le total, l'objectif,
-- la part active et inactive, et la semaine du jour. Aucune dépendance à WezTerm : se teste avec un simple interpréteur Lua.
local load = ...
local assemble = load("calendar/assemble")
local dates = load("calendar/dates")
local stats = load("calendar/stats")
local convert = load("color/convert")
local idle = load("core/idle")
local status = load("status/status")
local activity = load("core/activity")

local M = {}

M.BAR = 20 -- la largeur des barres
M.LABEL = 9 -- la colonne des noms (« Inactif » et des espaces)
M.MIN_WIDTH = 46 -- la largeur du contenu au minimum (sans cadre)
M.BAR_EMPTY_COLOR = "#3B404C"
M.PROJECTS = 5 -- les plus gros projets affichés (le reste dans « autres »)
M.PROJECT_NAME = 30 -- la colonne des noms de projets
M.PROJECT_BAR = 12 -- la largeur de leurs barres
M.IDLE_COLOR = "#8B8E99"

local function visible_len(s)
	local plain = s:gsub("\27%[[%d;]*m", "")
	return utf8.len(plain) or #plain
end

-- "2026-10-14" -> 2026, 10, 14
local function split(key)
	local y, m, d = tostring(key):match("^(%d+)-(%d+)-(%d+)$")
	return tonumber(y), tonumber(m), tonumber(d)
end

-- Le jour en toutes lettres, selon le modèle de la langue (labels.detail_date) : « Mercredi 14 octobre 2026 ».
function M.title(key, labels)
	local y, m, d = split(key)
	local wday = os.date("*t", os.time({ year = y, month = m, day = d, hour = 12 })).wday -- 1 = dimanche
	local fields = {
		weekday = labels.weekdays_long[(wday + 5) % 7 + 1], -- la liste commence au lundi
		day = tostring(d),
		month = labels.months[m],
		month_lower = labels.months[m]:lower(), -- les accents (é, û) ne sont pas touchés, seulement A-Z
		year = tostring(y),
	}
	return (labels.detail_date:gsub("{([%w_]+)}", fields))
end

-- Une barre de `size` caractères (M.BAR par défaut), remplie selon part / total.
local function bar(part, total, color, size)
	size = size or M.BAR
	local filled = total > 0 and math.floor(part * size / total + 0.5) or 0
	return convert.fg(color)
		.. string.rep("█", filled)
		.. convert.fg(M.BAR_EMPTY_COLOR)
		.. string.rep("░", size - filled)
		.. convert.RESET
end

-- Un nom coupé ou complété à `width` caractères.
local function fit(text, width)
	local len = utf8.len(text) or #text
	if len > width then
		return text:sub(1, utf8.offset(text, width) - 1) .. "…"
	end
	return text .. string.rep(" ", width - len)
end

-- « Par projet » : les plus gros projets du jour, en temps actif, avec leur part du total du jour (total > 0).
local function project_lines(of_day, total, color, labels)
	local list = {}
	for _, item in ipairs(activity.top(of_day, M.PROJECTS)) do
		if item.secs >= 60 then -- moins d'une minute s'afficherait « 0h00 » : la ligne n'apprend rien
			list[#list + 1] = item
		end
	end
	if #list == 0 then
		return {}
	end
	local out = { labels.detail_projects }
	for _, item in ipairs(list) do
		local name = item.label == activity.OTHER and labels.detail_other or item.label
		local secs = math.min(item.secs, total) -- jamais plus que le jour (deux fichiers fusionnés peuvent se contredire)
		local value = stats.hm(secs)
		out[#out + 1] = "  "
			.. fit(name, M.PROJECT_NAME - 1)
			.. string.rep(" ", 6 - #value + 1)
			.. value
			.. "   "
			.. bar(secs, total, color, M.PROJECT_BAR)
			.. "  "
			.. string.format(labels.percent, math.floor(secs * 100 / total + 0.5))
	end
	return out
end

-- « Inactif    1h30 »
local function row(name, secs)
	local value = stats.hm(secs)
	return name .. string.rep(" ", M.LABEL - utf8.len(name)) .. string.rep(" ", 6 - #value) .. value
end

-- La semaine du jour (les 7 jours, ceux des mois voisins compris) : le total et les jours où l'objectif est atteint.
function M.week(days, key, cfg)
	local y, m, d = split(key)
	local first = d - (dates.offset(y, m, cfg.week_starts_on) + d - 1) % 7
	local total, reached = 0, 0
	local goal_secs = stats.has_goal(cfg.goal_hours) and cfg.goal_hours * 3600 or nil
	for i = first, first + 6 do
		local secs = math.floor(math.max(0, days[dates.key_any(y, m, i)] or 0))
		total = total + secs
		if goal_secs and secs >= goal_secs then
			reached = reached + 1
		end
	end
	return total, reached
end

-- Dessine le détail du jour `key`. idle_days et projects (le temps par projet : { [date] = { [projet] = secondes } })
-- peuvent manquer. Renvoie les lignes et la largeur (celle qu'on centre).
function M.render(days, idle_days, key, today_key, cfg, labels, projects)
	local total = math.floor(math.max(0, days[key] or 0))
	local idle_secs, idle_percent = idle.share(total, idle_days and idle_days[key])
	local active = total - idle_secs
	local has_goal = stats.has_goal(cfg.goal_hours)
	local content = {}

	local title = M.title(key, labels)
	if key == today_key then
		title = title .. " · " .. labels.detail_today
	end

	local goal_text = ""
	if has_goal then
		local goal = status.goal_short(cfg.goal_hours)
		local missing = stats.hm(cfg.goal_hours * 3600 - total)
		if total >= cfg.goal_hours * 3600 then
			goal_text = "   " .. string.format(labels.detail_goal_reached, goal)
		elseif today_key and key < today_key then -- un jour passé : la journée est finie
			goal_text = "   " .. string.format(labels.detail_goal_failed, goal, missing)
		else
			goal_text = "   " .. string.format(labels.detail_goal_missing, goal, missing)
		end
	end
	content[#content + 1] = row(labels.detail_total, total) .. goal_text
	if total > 0 then
		local color = assemble.day_color(total, cfg) or M.IDLE_COLOR
		content[#content + 1] = row(labels.detail_active, active)
			.. "   "
			.. bar(active, total, color)
			.. "  "
			.. string.format(labels.percent, 100 - idle_percent)
		content[#content + 1] = row(labels.detail_idle, idle_secs)
			.. "   "
			.. bar(idle_secs, total, M.IDLE_COLOR)
			.. "  "
			.. string.format(labels.percent, idle_percent)
		local by_project = project_lines(projects and projects[key], total, color, labels)
		if #by_project > 0 then
			content[#content + 1] = ""
			for _, l in ipairs(by_project) do
				content[#content + 1] = l
			end
		end
	else
		content[#content + 1] = labels.detail_empty
	end
	content[#content + 1] = ""
	local week_total, reached = M.week(days, key, cfg)
	local week_text = ""
	if has_goal then
		local goal_days = math.floor(tonumber(cfg.goal_days) or 5)
		local format = reached >= goal_days and labels.detail_week_validated or labels.detail_week_goal
		week_text = "   " .. string.format(format, reached, goal_days)
	end
	content[#content + 1] = row(labels.detail_week, week_total) .. week_text

	local width = math.max(M.MIN_WIDTH, utf8.len(title) + 4)
	for _, l in ipairs(content) do
		width = math.max(width, visible_len(l))
	end

	local b, color = assemble.border_of(cfg)
	if not b then
		local lines = { "  " .. title, "" }
		for _, l in ipairs(content) do
			lines[#lines + 1] = (l == "") and "" or ("  " .. l)
		end
		return lines, width + 2
	end
	-- dans un cadre : le titre posé sur le haut
	local inner = width + 2
	local lines = {
		color .. b.tl .. b.h .. convert.RESET .. " " .. title .. " " .. color .. string.rep(
			b.h,
			inner - 3 - utf8.len(title)
		) .. b.tr .. convert.RESET,
	}
	local v = color .. b.v .. convert.RESET
	for _, l in ipairs(content) do
		lines[#lines + 1] = v .. " " .. l .. string.rep(" ", width - visible_len(l)) .. " " .. v
	end
	lines[#lines + 1] = color .. b.bl .. string.rep(b.h, inner) .. b.br .. convert.RESET
	return lines, inner + 2
end

return M
