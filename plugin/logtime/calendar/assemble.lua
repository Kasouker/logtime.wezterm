-- plugin/logtime/calendar/assemble.lua : dessine un mois du calendrier (texte avec couleurs ANSI).
-- Aucune dépendance à WezTerm : se teste avec un simple interpréteur Lua.
local load = ...
local convert = load("color/convert")
local dates = load("calendar/dates")
local stats = load("calendar/stats")

local M = {}

-- Largeur visible d'une ligne de semaine : 2 espaces + 7 colonnes de 9 caractères
M.WIDTH = 65

-- Les traits des encadrés (une grille : les cases partagent leurs traits), selon le style choisi.
--   tl tr bl br : les coins ; h v : les traits ; t b : les jonctions du haut et du bas ; l r : de gauche et de droite ;
--   x : les croisements.
M.BORDER_STYLES = {
	rounded = { tl = "╭", tr = "╮", bl = "╰", br = "╯", h = "─", v = "│", t = "┬", b = "┴", l = "├", r = "┤", x = "┼" },
	single = { tl = "┌", tr = "┐", bl = "└", br = "┘", h = "─", v = "│", t = "┬", b = "┴", l = "├", r = "┤", x = "┼" },
	double = { tl = "╔", tr = "╗", bl = "╚", br = "╝", h = "═", v = "║", t = "╦", b = "╩", l = "╠", r = "╣", x = "╬" },
	heavy = { tl = "┏", tr = "┓", bl = "┗", br = "┛", h = "━", v = "┃", t = "┳", b = "┻", l = "┣", r = "┫", x = "╋" },
}
M.BORDER_COLOR = "#8B8E99" -- le gris des jours vides (la couleur sera réglable à l'étape suivante)

local function borders_on(cfg)
	return (cfg or {}).borders == true
end

-- La largeur d'un mois avec ces réglages : 65, ou 66 avec les encadrés (le trait vertical prend la place de l'espace
-- entre deux cases ; il faut seulement une colonne de plus pour le trait de droite).
function M.width(cfg)
	return M.WIDTH + (borders_on(cfg) and 1 or 0)
end

-- La hauteur d'un mois en bloc : 21, ou 22 avec les encadrés (le trait horizontal prend la place de la ligne vide entre
-- deux semaines ; il faut seulement une ligne de plus pour le trait du haut).
function M.height(cfg)
	return M.HEIGHT + (borders_on(cfg) and 1 or 0)
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
borders = false, -- encadrés des cases (une grille)
border_style = "rounded", -- "rounded", "single", "double" ou "heavy" (voir M.BORDER_STYLES)
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
		header[#header + 1] = center(names[i], 9) -- avec les encadrés aussi : un nom de 3 lettres reste centré dans la case
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

-- Une semaine est validée si l'objectif est atteint au moins goal_days jours sur ses 7 jours (ceux des mois voisins
-- compris : la semaine du 28 septembre au 4 octobre compte aussi ses jours de septembre).
local function week_validated(days, year, month, first_day, goal_secs, goal_days)
	local reached = 0
	for d = first_day, first_day + 6 do
		if math.floor(math.max(0, days[dates.key_any(year, month, d)] or 0)) >= goal_secs then
			reached = reached + 1
		end
	end
	return reached >= goal_days
end

-- Les semaines validées d'un mois : combien, sur combien de semaines affichées (4 à 6). Sans objectif : nil.
function M.validated_weeks(days, year, month, cfg)
	cfg = with_defaults(cfg)
	if not stats.has_goal(cfg.goal_hours) then
		return nil
	end
	local goal_secs = cfg.goal_hours * 3600
	local goal_days = math.floor(tonumber(cfg.goal_days) or M.DEFAULTS.goal_days)
	local count_days = dates.days_in_month(year, month)
	local validated, total = 0, 0
	local day = 1 - dates.offset(year, month, cfg.week_starts_on)
	while day <= count_days do
		total = total + 1
		if week_validated(days, year, month, day, goal_secs, goal_days) then
			validated = validated + 1
		end
		day = day + 7
	end
	return validated, total
end

-- En haut, à côté du titre : « Total du mois : 42h10 / Jours actifs : 12 ».
local function totals_text(s, labels)
	return string.format("%s : %s / %s : %d", labels.total, stats.hm(s.total), labels.active, s.active)
end

-- En bas : « Semaines validées : 3/5 / Jours validés : 12/30 » (sur le nombre de jours du mois). Sans objectif : nil.
local function validated_text(days, year, month, cfg, s, labels)
	local weeks, total_weeks = M.validated_weeks(days, year, month, cfg)
	if not weeks then
		return nil
	end
	return string.format("%s : %d/%d / %s : %d/%d", labels.validated_weeks, weeks, total_weeks, labels.validated_days, s.goal_days, dates.days_in_month(year, month))
end

-- Une ligne de traits de la grille : left .. (8 traits .. join) x 6 .. 8 traits .. right, dans la couleur des traits.
local function rule(left, join, right, b)
	local h8 = string.rep(b.h, 8)
	return "  " .. convert.fg(M.BORDER_COLOR) .. left .. string.rep(h8 .. join, 6) .. h8 .. right .. convert.RESET
end

-- Les semaines : trois lignes par semaine (les numéros, les durées, une ligne vide).
-- Avec les encadrés : un trait en haut, puis par semaine les numéros, les durées et un trait (celui du bas après la
-- dernière semaine) ; les cases sont séparées par un trait vertical au lieu d'un espace.
local function week_lines(days, year, month, today_key, cfg)
	local out = {}
	local goal_secs = stats.has_goal(cfg.goal_hours) and cfg.goal_hours * 3600 or nil
	local count_days = dates.days_in_month(year, month)
	local day = 1 - dates.offset(year, month, cfg.week_starts_on)
	local b = borders_on(cfg) and (M.BORDER_STYLES[cfg.border_style] or M.BORDER_STYLES.rounded) or nil
	local v = b and (convert.fg(M.BORDER_COLOR) .. b.v .. convert.RESET) or nil
	if b then
		out[#out + 1] = rule(b.tl, b.t, b.tr, b)
	end
	while day <= count_days do
		local l1, l2 = {}, {}
		for _ = 1, 7 do
			if day < 1 or day > count_days then
				l1[#l1 + 1] = string.rep(" ", 8)
				l2[#l2 + 1] = string.rep(" ", 8)
			else
				local key = dates.key(year, month, day)
				local secs = math.floor(math.max(0, days[key] or 0))
				local st = style(secs, cfg)
				local mark = (key == today_key) and "*" or " "
				l1[#l1 + 1] = st .. mark .. string.format("%2d", day) .. string.rep(" ", 5) .. convert.RESET
				l2[#l2 + 1] = st .. duration_text(secs, key, today_key, goal_secs) .. convert.RESET
			end
			day = day + 1
		end
		if b then
			out[#out + 1] = "  " .. v .. table.concat(l1, v) .. v
			out[#out + 1] = "  " .. v .. table.concat(l2, v) .. v
			out[#out + 1] = (day > count_days) and rule(b.bl, b.b, b.br, b) or rule(b.l, b.x, b.r, b)
		else
			out[#out + 1] = "  " .. table.concat(l1, " ") .. " "
			out[#out + 1] = "  " .. table.concat(l2, " ") .. " "
			out[#out + 1] = ""
		end
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

	local s = stats.month_stats(days, year, month, cfg.goal_hours)
	add("")
	add(string.format("  %s : %s %d   %s", labels.title, labels.months[month], year, totals_text(s, labels)))
	add("")
	add(header_line(cfg, labels))
	for _, line in ipairs(week_lines(days, year, month, today_key, cfg)) do
		add(line)
	end

	-- Statistiques (le total et les jours actifs sont en haut, à côté du titre)
	add(string.format("  %s : %s", labels.average, stats.hm(s.average)))
	local line = {}
	if s.best_day then
		line[#line + 1] = string.format("%s : %d (%s)", labels.best, s.best_day, stats.hm(s.best_secs))
	end
	line[#line + 1] = string.format("%s : %d %s", labels.streak, stats.streak(days, today_key), labels.streak_unit)
	add("  " .. table.concat(line, "   "))
	local validated = validated_text(days, year, month, cfg, s, labels)
	if validated then
		add("  " .. validated)
	end

	add(legend_line(cfg, labels))
	return table.concat(lines, "\n")
end

-- Un mois en bloc compact, pour en afficher plusieurs côte à côte : le titre avec le total et les jours actifs, l'en-tête,
-- les semaines, et en bas les semaines et jours validés (ligne vide sans objectif).
-- selected : le titre est alors en gras. Renvoie { lines = { ... }, width = M.width(cfg) }.
function M.month_block(days, year, month, today_key, cfg, labels, selected)
cfg = with_defaults(cfg)
local s = stats.month_stats(days, year, month, cfg.goal_hours)
local title = string.format("  %s %d", labels.months[month], year)
if selected then
title = "\27[1m" .. title .. convert.RESET
end
title = title .. "   " .. totals_text(s, labels)
local lines = { title, header_line(cfg, labels) }
for _, line in ipairs(week_lines(days, year, month, today_key, cfg)) do
lines[#lines + 1] = line
end
while #lines < M.height(cfg) - 1 do
lines[#lines + 1] = ""
end
local validated = validated_text(days, year, month, cfg, s, labels)
lines[#lines + 1] = validated and ("  " .. validated) or ""
return { lines = lines, width = M.width(cfg) }
end

return M
