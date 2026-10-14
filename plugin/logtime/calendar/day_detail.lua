-- plugin/logtime/calendar/day_detail.lua : le détail d'un jour (touche Entrée dans le calendrier) : le total, l'objectif,
-- la part active et inactive, et la semaine du jour. Aucune dépendance à WezTerm : se teste avec un simple interpréteur Lua.
local load = ...
local assemble = load("calendar/assemble")
local dates = load("calendar/dates")
local stats = load("calendar/stats")
local convert = load("color/convert")
local idle = load("core/idle")
local status = load("status/status")

local M = {}

M.BAR = 20 -- la largeur des barres
M.LABEL = 9 -- la colonne des noms (« Inactif » et des espaces)
M.MIN_WIDTH = 46 -- la largeur du contenu au minimum (sans cadre)
M.BAR_EMPTY_COLOR = "#3B404C"
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

-- Une barre de M.BAR caractères, remplie selon part / total.
local function bar(part, total, color)
	local filled = total > 0 and math.floor(part * M.BAR / total + 0.5) or 0
	return convert.fg(color)
		.. string.rep("█", filled)
		.. convert.fg(M.BAR_EMPTY_COLOR)
		.. string.rep("░", M.BAR - filled)
		.. convert.RESET
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

-- Dessine le détail du jour `key`. idle_days peut manquer. Renvoie les lignes et la largeur (celle qu'on centre).
function M.render(days, idle_days, key, today_key, cfg, labels)
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
			.. string.format("  %3d %%", 100 - idle_percent)
		content[#content + 1] = row(labels.detail_idle, idle_secs)
			.. "   "
			.. bar(idle_secs, total, M.IDLE_COLOR)
			.. string.format("  %3d %%", idle_percent)
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
