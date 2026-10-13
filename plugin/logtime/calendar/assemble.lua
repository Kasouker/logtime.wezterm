-- plugin/logtime/calendar/assemble.lua : dessine un mois du calendrier (texte avec couleurs ANSI).
-- Aucune dépendance à WezTerm : se teste avec un simple interpréteur Lua.
local load = ...
local convert = load("color/convert")
local dates = load("calendar/dates")
local stats = load("calendar/stats")

local M = {}

-- Largeur visible d'une ligne de semaine : 2 espaces + 7 colonnes de 9 caractères
M.WIDTH = 65

-- Réglages par défaut. cell_color (facultatif) : une fonction secondes -> code couleur "#RRGGBB" (ou nil pour « pas de fond »),
-- qui remplace les quatre niveaux ci-dessous (c'est là que se branchera le dégradé).
M.DEFAULTS = {
	week_starts_on = "monday",
	goal_hours = nil,
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

-- En-tête des jours de la semaine
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
add(table.concat(header))

-- Les semaines
local count_days = dates.days_in_month(year, month)
local day = 1 - dates.offset(year, month, cfg.week_starts_on)
while day <= count_days do
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
local text = secs > 0 and stats.hm(secs) or "·"
l1[#l1 + 1] = st .. mark .. string.format("%2d", day) .. string.rep(" ", 5) .. convert.RESET .. " "
l2[#l2 + 1] = st .. center(text, 8) .. convert.RESET .. " "
end
day = day + 1
end
add(table.concat(l1))
add(table.concat(l2))
add("")
end

-- Statistiques
local s = stats.month_stats(days, year, month, cfg.goal_hours)
add(string.format("  %s : %s   %s : %d   %s : %s", labels.total, stats.hm(s.total), labels.active, s.active, labels.average, stats.hm(s.average)))
local line = {}
if s.best_day then
line[#line + 1] = string.format("%s : %d (%s)", labels.best, s.best_day, stats.hm(s.best_secs))
end
line[#line + 1] = string.format("%s : %d %s", labels.streak, stats.streak(days, today_key), labels.streak_unit)
if cfg.goal_hours then
line[#line + 1] = string.format("%s : %d %s", labels.goal, s.goal_days, labels.goal_unit)
end
add("  " .. table.concat(line, "   "))

-- Légende des couleurs (seulement pour les quatre niveaux par défaut)
if not cfg.cell_color then
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
add("  " .. table.concat(parts, "   ") .. "     " .. labels.today)
else
add("  " .. labels.today)
end

return table.concat(lines, "\n")
end

return M
