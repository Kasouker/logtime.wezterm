-- plugin/logtime/calendar/year.lua : la vue de l'année (touche a dans le calendrier), façon GitHub : une colonne par
-- semaine, une ligne par jour de la semaine, chaque jour un petit carré dans la couleur du jour (la même que dans les
-- cases du calendrier). Aucune dépendance à WezTerm : se teste avec un simple interpréteur Lua.
local load = ...
local assemble = load("calendar/assemble")
local dates = load("calendar/dates")
local stats = load("calendar/stats")
local convert = load("color/convert")

local M = {}

M.LABEL = 5 -- la colonne des jours de la semaine : « Lun » et deux espaces
M.DAY = "■"
M.TODAY = "◆"
M.EMPTY_COLOR = "#3B404C" -- un jour sans travail : un carré gris foncé

-- Le nombre de jours de l'année (365 ou 366).
local function days_in_year(year)
	return os.date("*t", os.time({ year = year, month = 12, day = 31, hour = 12 })).yday
end

-- Le numéro du jour dans l'année (1 pour le 1er janvier).
local function yday(year, month, day)
	return os.date("*t", os.time({ year = year, month = month, day = day, hour = 12 })).yday
end

-- Le nombre de colonnes (semaines) de l'année : 53 ou 54 selon le jour du 1er janvier.
function M.columns(year, week_starts_on)
	local offset = dates.offset(year, 1, week_starts_on)
	return math.ceil((offset + days_in_year(year)) / 7)
end

-- La largeur du contenu (sans cadre ni marge) : les jours de la semaine, puis 2 caractères par semaine.
local function content_width(year, cfg)
	return M.LABEL + 2 * M.columns(year, cfg.week_starts_on)
end

-- Les premières lettres d'un texte, comptées en caractères (les accents en prennent deux en octets).
local function first_chars(text, n)
	local stop = utf8.offset(text, n + 1)
	return stop and text:sub(1, stop - 1) or text
end

local function visible_len(s)
	local plain = s:gsub("\27%[[%d;]*m", "")
	return utf8.len(plain) or #plain
end

-- Les statistiques de l'année : total, jours actifs, meilleur jour, jours et semaines validés (avec un objectif).
function M.year_stats(days, year, cfg)
	local offset = dates.offset(year, 1, cfg.week_starts_on)
	local goal_secs = stats.has_goal(cfg.goal_hours) and cfg.goal_hours * 3600 or nil
	local s = { total = 0, active = 0, best_secs = 0, goal_days = 0, weeks = 0, validated_weeks = 0 }
	for i = 1, days_in_year(year) do
		local key = dates.key_any(year, 1, i)
		local secs = math.floor(math.max(0, days[key] or 0))
		s.total = s.total + secs
		if secs > 0 then
			s.active = s.active + 1
		end
		if secs > s.best_secs then
			s.best_secs, s.best_key = secs, key
		end
		if goal_secs and secs >= goal_secs then
			s.goal_days = s.goal_days + 1
		end
	end
	s.days = days_in_year(year)
	s.average = s.active > 0 and math.floor(s.total / s.active) or 0
	-- une semaine est validée si l'objectif est atteint goal_days jours sur ses 7 jours (ceux des années voisines compris)
	local goal_days = math.floor(tonumber(cfg.goal_days) or 5)
	s.weeks = M.columns(year, cfg.week_starts_on)
	if goal_secs then
		for col = 1, s.weeks do
			local reached = 0
			for row = 1, 7 do
				local i = (col - 1) * 7 + row - offset
				if math.floor(math.max(0, days[dates.key_any(year, 1, i)] or 0)) >= goal_secs then
					reached = reached + 1
				end
			end
			if reached >= goal_days then
				s.validated_weeks = s.validated_weeks + 1
			end
		end
	end
	return s
end

-- Dessine l'année. cfg : les réglages du calendrier, avec le dégradé (gradient.apply_to). Renvoie les lignes et la
-- largeur (celle qu'on centre). Avec les encadrés : l'année dans un cadre, le titre sur le haut, les validés sur le bas.
function M.render(days, year, today_key, cfg, labels)
	local offset = dates.offset(year, 1, cfg.week_starts_on)
	local columns = M.columns(year, cfg.week_starts_on)
	local width = content_width(year, cfg)
	local count = days_in_year(year)
	local s = M.year_stats(days, year, cfg)

	-- la ligne des mois : chaque nom au-dessus de la semaine de son 1er jour
	local header = {}
	local cursor = 0 -- la largeur déjà écrite
	for month = 1, 12 do
		local col = math.floor((yday(year, month, 1) - 1 + offset) / 7) + 1
		local at = M.LABEL + (col - 1) * 2
		if at >= cursor then
			local name = (labels.months_short or {})[month] or first_chars(labels.months[month], 3)
			header[#header + 1] = string.rep(" ", at - cursor) .. name
			cursor = at + utf8.len(name)
		end
	end
	local content = { table.concat(header) }

	-- une ligne par jour de la semaine
	local names = {}
	for i = 1, 7 do
		names[i] = labels.weekdays[i]
	end
	if cfg.week_starts_on == "sunday" then
		table.insert(names, 1, names[7])
		names[8] = nil
	end
	for row = 1, 7 do
		local parts = { names[row] .. string.rep(" ", M.LABEL - utf8.len(names[row])) }
		for col = 1, columns do
			local i = (col - 1) * 7 + row - offset
			if i < 1 or i > count then
				parts[#parts + 1] = "  "
			else
				local key = dates.key_any(year, 1, i)
				local secs = math.floor(math.max(0, days[key] or 0))
				local color = (secs > 0 and assemble.day_color(secs, cfg)) or M.EMPTY_COLOR
				local mark = (key == today_key) and M.TODAY or M.DAY
				parts[#parts + 1] = convert.fg(color) .. mark .. convert.RESET .. " "
			end
		end
		content[#content + 1] = table.concat(parts)
	end
	content[#content + 1] = ""

	-- les statistiques
	local line = { string.format("%s : %s", labels.average, stats.hm(s.average)) }
	if s.best_key then
		local _, m, d = s.best_key:match("^(%d+)-(%d+)-(%d+)$")
		line[#line + 1] = string.format(
			"%s : %d %s (%s)",
			labels.best,
			tonumber(d),
			labels.months[tonumber(m)],
			stats.hm(s.best_secs)
		)
	end
	content[#content + 1] = table.concat(line, "   ")
	local title =
		string.format("%d   %s : %s / %s : %d", year, labels.year_total, stats.hm(s.total), labels.active, s.active)
	local validated = nil
	if stats.has_goal(cfg.goal_hours) then
		validated = string.format(
			"%s : %d/%d / %s : %d/%d",
			labels.validated_weeks,
			s.validated_weeks,
			s.weeks,
			labels.validated_days,
			s.goal_days,
			s.days
		)
	end

	local b, color = assemble.border_of(cfg)
	if not b then
		local lines = { "  " .. title, "" }
		for _, l in ipairs(content) do
			lines[#lines + 1] = "  " .. l
		end
		if validated then
			lines[#lines + 1] = "  " .. validated
		end
		return lines, 2 + width
	end

	-- dans un cadre : « │ contenu │ », le titre posé sur le haut, les validés sur le bas
	local inner = width + 2
	local function edge(left, right, text)
		if not text then
			return " " .. color .. left .. string.rep(b.h, inner) .. right .. convert.RESET
		end
		local fill = inner - 1 - (visible_len(text) + 2)
		return " "
			.. color
			.. left
			.. b.h
			.. convert.RESET
			.. " "
			.. text
			.. " "
			.. color
			.. string.rep(b.h, fill)
			.. right
			.. convert.RESET
	end
	local v = color .. b.v .. convert.RESET
	local lines = { edge(b.tl, b.tr, title) }
	for _, l in ipairs(content) do
		lines[#lines + 1] = " " .. v .. " " .. l .. string.rep(" ", width - visible_len(l)) .. " " .. v
	end
	lines[#lines + 1] = edge(b.bl, b.br, validated)
	return lines, inner + 3
end

return M
