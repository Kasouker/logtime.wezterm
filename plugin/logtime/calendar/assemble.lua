-- plugin/logtime/calendar/assemble.lua : dessine un mois du calendrier (texte avec couleurs ANSI).
-- Aucune dépendance à WezTerm : se teste avec un simple interpréteur Lua.
local load = ...
local convert = load("color/convert")
local dates = load("calendar/dates")
local stats = load("calendar/stats")

local M = {}

-- Largeur visible d'une ligne de semaine : 2 espaces + 7 colonnes de 9 caractères
M.WIDTH = 65
-- Avec un objectif, une colonne de plus à droite : le résultat de la semaine (« ✓ 4/5 »).
M.WEEK_COLUMN = 8

-- La largeur d'un mois avec ces réglages : 65, ou 73 avec un objectif (la colonne de la semaine).
function M.width(cfg)
	return M.WIDTH + (stats.has_goal((cfg or {}).goal_hours) and M.WEEK_COLUMN or 0)
end

-- Hauteur d'un mois en bloc (month_block) : titre, en-tête, 6 semaines de 3 lignes, totaux. Les mois de 4 ou 5 semaines
-- sont complétés par des lignes vides, pour que les totaux soient toujours alignés d'un mois à l'autre.
M.HEIGHT = 21

-- Réglages par défaut. cell_color (facultatif) : une fonction secondes -> code couleur "#RRGGBB" (ou nil pour « pas de fond »),
-- qui remplace les quatre niveaux ci-dessous (c'est là que se branchera le dégradé).
M.DEFAULTS = {
week_starts_on = "monday",
goal_hours = nil,
goal_days = 5, -- jours où l'objectif est atteint qui font une semaine réussie
heat = { "#2E3644", "#5A5240", "#8C7A4A", "#C9AB6B" },
thresholds = { 1, 3, 6 },
cell_color = nil,
}

local function with_defaults(cfg)
local out = {}
for key, value in pairs(M.DEFAULTS) do
out[key] = value
end
for key, value in pairs(cfg or {}) do
out[key] = value
end
return out
end

-- Centre un texte dans une largeur donnée (compte les caractères, pas les octets)
local function center(s, width)
local len = utf8.len(s) or #s
if len >= width then
return s
end
local left = math.floor((width - len) / 2)
return string.rep(" ", left) .. s .. string.rep(" ", width - len - left)
end

-- Niveau de couleur d'un jour : 0 (rien) à 4 (le plus fort)
local function level(secs, thresholds)
if secs <= 0 then
		return 0
	end
	local hours = secs / 3600
	if hours >= thresholds[3] then
		return 4
	end
	if hours >= thresholds[2] then
		return 3
	end
	if hours >= thresholds[1] then
		return 2
	end
	return 1
end

-- La couleur de fond d'un jour (ou nil : pas de fond)
local function background(secs, cfg)
if cfg.cell_color then
return cfg.cell_color(secs)
end
local lv = level(secs, cfg.thresholds)
if lv == 0 then
return nil
end
return cfg.heat[lv]
end

local function style(secs, cfg)
local bg = background(secs, cfg)
if not bg then
return convert.fg("#8B8E99")
end
return convert.bg(bg) .. convert.fg(convert.contrast(bg))
end

-- L'en-tête des jours de la semaine
local function header_line(cfg, labels)
	local names = {}
	for i = 1, 7 do
		names[i] = labels.weekdays[i]
	end
	if cfg.week_starts_on == "sunday" then
		table.insert(names, 1, names[7])
		names[8] = nil
	end
	local header = { "  " }
	for i = 1, 7 do
		header[#header + 1] = center(names[i], 9)
	end
	if stats.has_goal(cfg.goal_hours) then
		header[#header + 1] = center(labels.week_column or "", M.WEEK_COLUMN)
	end
	return table.concat(header)
end

M.GOAL_MARK = "✓"
local STRIKE, NO_STRIKE = "\27[9m", "\27[29m"

-- La durée d'un jour (ligne 2 de sa case), centrée sur 8 caractères. Avec un objectif :
--   atteint                       : « ✓ 8h02 » ;
--   pas atteint, jour déjà passé  : la durée est rayée (seulement le texte, pas les espaces autour) ;
--   pas atteint, aujourd'hui ou plus tard : rien de spécial (la journée n'est pas finie).
-- Un jour sans rien garde son « · ». Les dates "AAAA-MM-JJ" se comparent comme du texte : l'ordre est le bon.
local function duration_text(secs, key, today_key, goal_secs)
	if secs <= 0 then
		return center("·", 8)
	end
	local text = stats.hm(secs)
	if not goal_secs then
		return center(text, 8)
	end
	if secs >= goal_secs then
		return center(M.GOAL_MARK .. " " .. text, 8)
	end
	if today_key and key < today_key then
		local padded = center(text, 8)
		local left = padded:match("^( *)")
		local right = string.rep(" ", 8 - #left - (utf8.len(text) or #text))
		return left .. STRIKE .. text .. NO_STRIKE .. right
	end
	return center(text, 8)
end

-- Le résultat d'une semaine (colonne de droite), centré sur M.WEEK_COLUMN : le nombre de jours où l'objectif est
-- atteint sur les 7 jours de la semaine (ceux des mois voisins compris), sur goal_days.
--   assez de jours        : « ✓ 4/5 » (même si la semaine n'est pas finie) ;
--   pas assez, semaine finie (son dernier jour est passé), avec du travail : « 2/5 » rayé ;
--   semaine sans aucun travail (vacances, avant l'installation du plugin) : « 0/5 », jamais rayé (comme un jour vide) ;
--   pas assez, semaine en cours ou à venir : « 1/5 » (elle peut encore réussir).
local function week_result(days, year, month, first_day, today_key, goal_secs, goal_days)
	local reached, worked = 0, false
	local last_key
	for d = first_day, first_day + 6 do
		last_key = dates.key_any(year, month, d)
		local secs = math.floor(math.max(0, days[last_key] or 0))
		if secs > 0 then
			worked = true
		end
		if secs >= goal_secs then
			reached = reached + 1
		end
	end
	local text = string.format("%d/%d", reached, goal_days)
	if reached >= goal_days then
		return center(M.GOAL_MARK .. " " .. text, M.WEEK_COLUMN)
	end
	if worked and today_key and last_key < today_key then
		local padded = center(text, M.WEEK_COLUMN)
		local left = padded:match("^( *)")
		return left .. STRIKE .. text .. NO_STRIKE .. string.rep(" ", M.WEEK_COLUMN - #left - #text)
	end
	return center(text, M.WEEK_COLUMN)
end

-- Les semaines : trois lignes par semaine (les numéros, les durées, une ligne vide). Avec un objectif, le résultat de
-- la semaine est au bout de la ligne des durées.
local function week_lines(days, year, month, today_key, cfg)
	local out = {}
	local goal_secs = stats.has_goal(cfg.goal_hours) and cfg.goal_hours * 3600 or nil
	local goal_days = math.floor(tonumber(cfg.goal_days) or M.DEFAULTS.goal_days)
	local count_days = dates.days_in_month(year, month)
	local day = 1 - dates.offset(year, month, cfg.week_starts_on)
	while day <= count_days do
		local first_day = day
		local l1, l2 = { "  " }, { "  " }
		for _ = 1, 7 do
			if day < 1 or day > count_days then
				l1[#l1 + 1] = string.rep(" ", 9)
				l2[#l2 + 1] = string.rep(" ", 9)
			else
				local key = dates.key(year, month, day)
				local secs = math.floor(math.max(0, days[key] or 0))
				local st = style(secs, cfg)
				local mark = (key == today_key) and "*" or " "
				l1[#l1 + 1] = st .. mark .. string.format("%2d", day) .. string.rep(" ", 5) .. convert.RESET .. " "
				l2[#l2 + 1] = st .. duration_text(secs, key, today_key, goal_secs) .. convert.RESET .. " "
			end
			day = day + 1
		end
		if goal_secs then
			l1[#l1 + 1] = string.rep(" ", M.WEEK_COLUMN)
			l2[#l2 + 1] = week_result(days, year, month, first_day, today_key, goal_secs, goal_days)
		end
		out[#out + 1] = table.concat(l1)
		out[#out + 1] = table.concat(l2)
		out[#out + 1] = ""
	end
	return out
end

-- La légende des couleurs en une ligne (seulement pour les quatre niveaux par défaut, sinon juste l'étoile)
local function legend_line(cfg, labels)
if cfg.cell_color then
	if cfg.legend_text then
		return "  " .. cfg.legend_text .. "     " .. labels.today
	end
	return "  " .. labels.today
end
local t = cfg.thresholds
local legend = {
{ cfg.heat[1], string.format("<%gh", t[1]) },
{ cfg.heat[2], string.format("%g-%gh", t[1], t[2]) },
{ cfg.heat[3], string.format("%g-%gh", t[2], t[3]) },
{ cfg.heat[4], string.format("%gh+", t[3]) },
}
local parts = {}
for _, item in ipairs(legend) do
parts[#parts + 1] = convert.fg(item[1]) .. "██" .. convert.RESET .. " " .. item[2]
end
return "  " .. table.concat(parts, "   ") .. "     " .. labels.today
end

-- La légende des couleurs (une ligne), pour la page qui affiche plusieurs mois.
function M.legend(cfg, labels)
return legend_line(with_defaults(cfg), labels)
end

-- Dessine un mois complet. Renvoie le texte (lignes séparées par "\n").
--   days      : { ["2026-10-12"] = secondes, ... }
--   today_key : "2026-10-12" (la case du jour est marquée d'une étoile)
--   cfg       : voir M.DEFAULTS (tout est facultatif)
--   labels    : le contenu de i18n/fr.lua ou i18n/en.lua
function M.render_month(days, year, month, today_key, cfg, labels)
	cfg = with_defaults(cfg)
	local lines = {}
	local function add(s)
		lines[#lines + 1] = s
	end

	add("")
	add(string.format("  %s : %s %d", labels.title, labels.months[month], year))
	add("")
	add(header_line(cfg, labels))
	for _, line in ipairs(week_lines(days, year, month, today_key, cfg)) do
		add(line)
	end

	-- Statistiques
	local s = stats.month_stats(days, year, month, cfg.goal_hours)
	add(string.format("  %s : %s   %s : %d   %s : %s", labels.total, stats.hm(s.total), labels.active, s.active, labels.average, stats.hm(s.average)))
	local line = {}
	if s.best_day then
		line[#line + 1] = string.format("%s : %d (%s)", labels.best, s.best_day, stats.hm(s.best_secs))
	end
	line[#line + 1] = string.format("%s : %d %s", labels.streak, stats.streak(days, today_key), labels.streak_unit)
	if stats.has_goal(cfg.goal_hours) then
		line[#line + 1] = string.format("%s : %d %s", labels.goal, s.goal_days, labels.goal_unit)
	end
	add("  " .. table.concat(line, "   "))

	add(legend_line(cfg, labels))
	return table.concat(lines, "\n")
end

-- Un mois en bloc compact, pour en afficher plusieurs côte à côte : le titre, l'en-tête, les semaines et une ligne de totaux.
-- selected : le titre est alors en gras. Renvoie { lines = { ... }, width = M.width(cfg) }.
function M.month_block(days, year, month, today_key, cfg, labels, selected)
cfg = with_defaults(cfg)
local title = string.format("  %s %d", labels.months[month], year)
if selected then
title = "\27[1m" .. title .. convert.RESET
end
local lines = { title, header_line(cfg, labels) }
for _, line in ipairs(week_lines(days, year, month, today_key, cfg)) do
lines[#lines + 1] = line
end
while #lines < M.HEIGHT - 1 do
lines[#lines + 1] = ""
end
local s = stats.month_stats(days, year, month, cfg.goal_hours)
lines[#lines + 1] = string.format("  %s : %s   %s : %d", labels.total, stats.hm(s.total), labels.active, s.active)
return { lines = lines, width = M.width(cfg) }
end

return M
