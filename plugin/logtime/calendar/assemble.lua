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
	rounded = {
		tl = "╭",
		tr = "╮",
		bl = "╰",
		br = "╯",
		h = "─",
		v = "│",
		t = "┬",
		b = "┴",
		l = "├",
		r = "┤",
		x = "┼",
	},
	single = {
		tl = "┌",
		tr = "┐",
		bl = "└",
		br = "┘",
		h = "─",
		v = "│",
		t = "┬",
		b = "┴",
		l = "├",
		r = "┤",
		x = "┼",
	},
	double = {
		tl = "╔",
		tr = "╗",
		bl = "╚",
		br = "╝",
		h = "═",
		v = "║",
		t = "╦",
		b = "╩",
		l = "╠",
		r = "╣",
		x = "╬",
	},
	heavy = {
		tl = "┏",
		tr = "┓",
		bl = "┗",
		br = "┛",
		h = "━",
		v = "┃",
		t = "┳",
		b = "┻",
		l = "┣",
		r = "┫",
		x = "╋",
	},
}
M.BORDER_COLOR = "#8B8E99" -- la couleur des traits par défaut : le gris des jours vides (réglage border_color)

local function borders_on(cfg)
	return (cfg or {}).borders == true
end

-- La largeur d'un mois avec ces réglages : toujours 65. Avec les encadrés, la marge de gauche passe de 2 espaces à 1 (le
-- trait vertical sépare déjà les mois) : le trait de droite tient dans la même largeur.
function M.width(cfg)
	return M.WIDTH
end

-- Hauteur d'un mois encadré : le haut du cadre (avec le titre), la jonction (avec les jours de la semaine), toujours 6
-- semaines de 2 lignes séparées par un trait, le bas du cadre (avec les semaines et jours validés) : 1 + 1 + 12 + 5 + 1.
M.FRAMED_HEIGHT = 20

-- La hauteur d'un mois en bloc : 21, ou 20 avec les encadrés (les textes sont posés sur les traits).
function M.height(cfg)
	return borders_on(cfg) and M.FRAMED_HEIGHT or M.HEIGHT
end

-- Avec les encadrés : une marge d'un espace, et 62 colonnes entre les deux traits verticaux du cadre (65 - 1 - 2).
local MARGIN = " "
local INNER = 62

local function visible_len(s)
	local plain = s:gsub("\27%[[%d;]*m", "")
	return utf8.len(plain) or #plain
end

-- Les traits et leur couleur (code ANSI), ou nil sans encadrés. Aussi utilisé par la page de personnalisation : les
-- mêmes traits partout.
function M.border_of(cfg)
	if not borders_on(cfg) then
		return nil
	end
	local color = cfg.border_color
	if type(color) ~= "string" or not color:match("^#%x%x%x%x%x%x$") then
		color = M.BORDER_COLOR -- une couleur absente ou mal écrite : le gris
	end
	return M.BORDER_STYLES[cfg.border_style] or M.BORDER_STYLES.rounded, convert.fg(color)
end

-- Retire la marge de deux espaces au début d'un texte, éventuellement placée après des codes de style (le titre en gras
-- du mois choisi commence par « \27[1m »).
local function without_margin(text)
	-- en Lua, « * » ne s'applique pas à un groupe entre parenthèses : on passe les codes de style un par un
	local codes, rest = "", text
	while true do
		local code = rest:match("^\27%[[%d;]*m")
		if not code then
			break
		end
		codes, rest = codes .. code, rest:sub(#code + 1)
	end
	return codes .. rest:gsub("^  ", "", 1)
end

-- Les caractères d'une ligne de traits de la grille : left, puis 7 fois 8 traits séparés par join, puis right (64).
local function rule_chars(left, join, right, b)
	local chars = { left }
	for cell = 1, 7 do
		for _ = 1, 8 do
			chars[#chars + 1] = b.h
		end
		if cell < 7 then
			chars[#chars + 1] = join
		end
	end
	chars[#chars + 1] = right
	return chars
end

-- Les caractères d'un trait sans jonction : left, 62 traits, right.
local function edge_chars(left, right, b)
	local chars = { left }
	for _ = 1, INNER do
		chars[#chars + 1] = b.h
	end
	chars[#chars + 1] = right
	return chars
end

-- Une ligne de traits avec un texte posé dessus, après le coin et un trait : « ╭─ Octobre 2026 ───╮ ». Le texte garde
-- ses couleurs (le gras du mois choisi), les traits ont la leur. Sans texte : la ligne de traits seule.
local function edge_with_text(chars, text, color)
	if not text or text == "" then
		return MARGIN .. color .. table.concat(chars) .. convert.RESET
	end
	text = without_margin(text)
	local covered = visible_len(text) + 2 -- le texte et un espace de chaque côté
	return MARGIN
		.. color
		.. chars[1]
		.. chars[2]
		.. convert.RESET
		.. " "
		.. text
		.. " "
		.. color
		.. table.concat(chars, "", 3 + covered)
		.. convert.RESET
end

-- Une ligne de texte dans le cadre d'un mois : « │ texte … │ ».
local function framed(text, b, color)
	local content = without_margin(text)
	local pad = math.max(0, INNER - 1 - visible_len(content))
	local v = color .. b.v .. convert.RESET
	return MARGIN .. v .. " " .. content .. string.rep(" ", pad) .. v
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

-- La couleur d'un jour ("#RRGGBB", ou nil : pas de couleur), la même que dans les cases du calendrier. La vue de
-- l'année s'en sert aussi (calendar/year.lua).
function M.day_color(secs, cfg)
	return background(secs, with_defaults(cfg))
end

-- La case choisie dans la page (cfg.selected_key) : en couleurs inversées (le texte prend la couleur du fond).
M.SELECTED = "\27[7m"

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
	local b, color = M.border_of(cfg)
	if b then
		-- la jonction entre le haut du cadre et les cases, chaque nom posé au milieu de sa case : « ├──Lun───┬──Mar─── »
		local parts = { MARGIN, color, b.l }
		for i = 1, 7 do
			local len = utf8.len(names[i]) or #names[i]
			local left = math.floor((8 - len) / 2)
			parts[#parts + 1] = string.rep(b.h, left)
				.. convert.RESET
				.. names[i]
				.. color
				.. string.rep(b.h, 8 - len - left)
			if i < 7 then
				parts[#parts + 1] = b.t
			end
		end
		parts[#parts + 1] = b.r .. convert.RESET
		return table.concat(parts)
	end
	local header = { "  " }
	for i = 1, 7 do
		header[#header + 1] = center(names[i], 9)
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
-- La durée d'un jour avec son objectif, sans espaces autour : « ✓ 8h02 », la durée rayée, ou la durée seule (aussi
-- pour l'aperçu de la page F4, calendar/overview.lua). Un jour sans rien : "".
function M.goal_duration(secs, key, today_key, goal_secs)
	if secs <= 0 then
		return ""
	end
	local text = stats.hm(secs)
	if goal_secs and secs >= goal_secs then
		return M.GOAL_MARK .. " " .. text
	end
	if goal_secs and today_key and key < today_key then
		return STRIKE .. text .. NO_STRIKE
	end
	return text
end

local function duration_text(secs, key, today_key, goal_secs)
	if secs <= 0 then
		return center("·", 8)
	end
	local text = M.goal_duration(secs, key, today_key, goal_secs)
	local plain = text:gsub("\27%[%d+m", "")
	local padded = center(plain, 8)
	local left = padded:match("^( *)")
	return left .. text .. string.rep(" ", 8 - #left - (utf8.len(plain) or #plain))
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
	local c = labels.colon
	return string.format("%s%s%s / %s%s%d", labels.total, c, stats.hm(s.total), labels.active, c, s.active)
end

-- En bas : « Semaines validées : 3/5 / Jours validés : 12/30 » (sur le nombre de jours du mois). Sans objectif : nil.
-- (s : les statistiques du mois ; sans elles, elles sont calculées : pour l'aperçu de la page F4)
function M.validated_text(days, year, month, cfg, s, labels)
	s = s or stats.month_stats(days, year, month, cfg.goal_hours)
	local weeks, total_weeks = M.validated_weeks(days, year, month, cfg)
	if not weeks then
		return nil
	end
	return string.format(
		"%s%s%d/%d / %s%s%d/%d",
		labels.validated_weeks,
		labels.colon,
		weeks,
		total_weeks,
		labels.validated_days,
		labels.colon,
		s.goal_days,
		dates.days_in_month(year, month)
	)
end

-- Une ligne de traits de la grille : left .. (8 traits .. join) x 6 .. 8 traits .. right, dans la couleur des traits.
local function rule(left, join, right, b, color)
	return MARGIN .. color .. table.concat(rule_chars(left, join, right, b)) .. convert.RESET
end

-- Les semaines : trois lignes par semaine (les numéros, les durées, une ligne vide).
-- Avec les encadrés : par semaine les numéros et les durées, et un trait « ├┼┤ » ENTRE deux semaines (le haut et le bas
-- de la grille sont les traits du cadre du mois) ; les cases sont séparées par un trait vertical. rows (facultatif) :
-- complète avec des semaines vides jusqu'à ce nombre (6 : tous les mois côte à côte ont la même hauteur).
local function week_lines(days, year, month, today_key, cfg, rows)
	local out = {}
	local goal_secs = stats.has_goal(cfg.goal_hours) and cfg.goal_hours * 3600 or nil
	local count_days = dates.days_in_month(year, month)
	local day = 1 - dates.offset(year, month, cfg.week_starts_on)
	local b, color = M.border_of(cfg)
	local v = b and (color .. b.v .. convert.RESET) or nil
	local weeks = {}
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
				if key == cfg.selected_key then
					st = st .. M.SELECTED
				end
				local mark = (key == today_key) and "*" or " "
				l1[#l1 + 1] = st .. mark .. string.format("%2d", day) .. string.rep(" ", 5) .. convert.RESET
				l2[#l2 + 1] = st .. duration_text(secs, key, today_key, goal_secs) .. convert.RESET
			end
			day = day + 1
		end
		weeks[#weeks + 1] = { l1, l2 }
	end
	if not b then
		for _, week in ipairs(weeks) do
			out[#out + 1] = "  " .. table.concat(week[1], " ") .. " "
			out[#out + 1] = "  " .. table.concat(week[2], " ") .. " "
			out[#out + 1] = ""
		end
		return out
	end
	local empty = {}
	for i = 1, 7 do
		empty[i] = string.rep(" ", 8)
	end
	while #weeks < (rows or 0) do
		weeks[#weeks + 1] = { empty, empty }
	end
	for i, week in ipairs(weeks) do
		out[#out + 1] = MARGIN .. v .. table.concat(week[1], v) .. v
		out[#out + 1] = MARGIN .. v .. table.concat(week[2], v) .. v
		if i < #weeks then
			out[#out + 1] = rule(b.l, b.x, b.r, b, color)
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
	local b, color = M.border_of(cfg)
	-- Avec les encadrés, le mois et ses statistiques sont dans un cadre ; la légende des couleurs reste dehors. Le titre perd
	-- alors « Logtime : » (il dépasserait du cadre ; la ligne d'aide au-dessus le dit déjà).
	local function text(s_)
		add(b and framed(s_, b, color) or s_)
	end
	add("")
	if b then
		add(
			edge_with_text(
				edge_chars(b.tl, b.tr, b),
				string.format("%s %d   %s", labels.months[month], year, totals_text(s, labels)),
				color
			)
		)
	else
		add(
			string.format(
				"  %s%s%s %d   %s",
				labels.title,
				labels.colon,
				labels.months[month],
				year,
				totals_text(s, labels)
			)
		)
		add("")
	end
	add(header_line(cfg, labels))
	for _, line in ipairs(week_lines(days, year, month, today_key, cfg)) do
		add(line)
	end
	if b then
		add(rule(b.l, b.b, b.r, b, color)) -- ferme la grille, avant les statistiques
	end

	-- Statistiques (le total et les jours actifs sont en haut, à côté du titre)
	text(string.format("  %s%s%s", labels.average, labels.colon, stats.hm(s.average)))
	local line = {}
	if s.best_day then
		line[#line + 1] = string.format("%s%s%d (%s)", labels.best, labels.colon, s.best_day, stats.hm(s.best_secs))
	end
	line[#line + 1] =
		string.format("%s%s%d %s", labels.streak, labels.colon, stats.streak(days, today_key), labels.streak_unit)
	text("  " .. table.concat(line, "   "))
	local validated = M.validated_text(days, year, month, cfg, s, labels)
	if b then
		add(edge_with_text(edge_chars(b.bl, b.br, b), validated, color)) -- les validés sur le bas du cadre
	elseif validated then
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
	local validated = M.validated_text(days, year, month, cfg, s, labels)
	local b, color = M.border_of(cfg)
	if b then
		-- Le mois dans son cadre, en 20 lignes : le titre sur le haut du cadre, les jours de la semaine sur la jonction,
		-- toujours 6 semaines (les dernières vides si besoin : les mois côte à côte ont la même hauteur), les semaines et
		-- jours validés sur le bas du cadre.
		local lines = { edge_with_text(edge_chars(b.tl, b.tr, b), title, color), header_line(cfg, labels) }
		for _, line in ipairs(week_lines(days, year, month, today_key, cfg, 6)) do
			lines[#lines + 1] = line
		end
		lines[#lines + 1] = edge_with_text(rule_chars(b.bl, b.b, b.br, b), validated, color)
		return { lines = lines, width = M.width(cfg) }
	end
	local lines = { title, header_line(cfg, labels) }
	for _, line in ipairs(week_lines(days, year, month, today_key, cfg)) do
		lines[#lines + 1] = line
	end
	while #lines < M.height(cfg) - 1 do
		lines[#lines + 1] = ""
	end
	lines[#lines + 1] = validated and ("  " .. validated) or ""
	return { lines = lines, width = M.width(cfg) }
end

return M
