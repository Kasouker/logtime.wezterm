-- plugin/logtime/pages/settings_page.lua : la page de personnalisation (touche F4), en onglets (Tab pour changer) :
--   Couleurs   : le choix de la couleur du dégradé : un tableau de seize couleurs numérotées, un aperçu, et Entrée
--                enregistre le choix dans le fichier de réglages et l'applique tout de suite au calendrier (sans recharger
--                WezTerm) ;
--   Calendrier : un réglage par ligne (pour l'instant le nombre de mois maximum) ; ← → change la valeur, enregistrée et
--                appliquée tout de suite.
-- Les seize couleurs sont celles du thème de WezTerm de l'utilisateur s'il a répondu « oui » à la question (touche y), sinon
-- la palette classique (touche n). Il peut changer d'avis à tout moment avec ces deux touches.
local load = ...
local layout = load("calendar/layout")
local screen = load("ui/screen")
local keytable = load("ui/keytable")
local safe = load("ui/safe")
local gradient = load("color/gradient")
local palette = load("color/palette")
local convert = load("color/convert")
local schema = load("settings/schema")
local assemble = load("calendar/assemble")

local M = {}

M.TABLE_NAME = "logtime_settings"
M.EVENT_PREFIX = "logtime-settings"

local COLUMNS = 4
local ROWS = 4
local CELL = 11 -- largeur d'une couleur, sans ses crochets
local LINES = 23 -- hauteur de la page, la même dans tous les onglets (la page ne saute pas quand on change d'onglet)
local NAME_WIDTH = 30 -- largeur du nom d'un réglage dans un onglet de réglages (les valeurs sont alignées après)

-- Les onglets de la page (gardés dans wezterm.GLOBAL sous forme de nombres).
M.TAB = { COLORS = 1, CALENDAR = 2, GENERAL = 3 }
M.TAB_COUNT = 3

-- Les réglages de l'onglet Calendrier, dans l'ordre d'affichage (leurs limites viennent de settings/schema.lua).
-- Pas de réglage du centrage : le calendrier est toujours centré (center = false reste possible dans wezterm.lua).
M.CALENDAR_SETTINGS = { "max_months", "months_anchor", "week_starts_on", "borders", "border_style", "border_color" }
-- Les réglages de l'onglet Général.
M.GENERAL_SETTINGS = { "lang", "goal_hours", "goal_days" }

-- Les onglets de réglages : leur liste de réglages et la clé (i18n) de leur intitulé. L'onglet Couleurs n'en fait pas partie.
M.LISTS = {
	[M.TAB.CALENDAR] = { settings = M.CALENDAR_SETTINGS, heading = "settings_calendar" },
	[M.TAB.GENERAL] = { settings = M.GENERAL_SETTINGS, heading = "settings_general" },
}

-- Les messages affichés en bas de la page (gardés dans wezterm.GLOBAL sous forme de nombres).
M.MESSAGE = { NONE = 0, SAVED = 1, FAILED = 2, CONSENT = 3, SETTING_SAVED = 4 }

-- Largeur du tableau de couleurs, avec la marge de gauche : 2 + 4 x (11 + 2 crochets) + 3 espaces.
M.GRID_WIDTH = 2 + COLUMNS * (CELL + 2) + (COLUMNS - 1)

local function center(text, width)
	local len = utf8.len(text) or #text
	if len >= width then
		return text
	end
	local left = math.floor((width - len) / 2)
	return string.rep(" ", left) .. text .. string.rep(" ", width - len - left)
end

local function truncate(text, width)
	if (utf8.len(text) or #text) <= width then
		return text
	end
	return text:sub(1, (utf8.offset(text, width + 1) or (#text + 1)) - 1)
end

-- Une couleur : deux lignes (le numéro, puis le nom) sur le fond de la couleur ; la couleur choisie est entre crochets.
local function cell(index, selected, colors, names)
	local hex = colors[index]
	local style = convert.bg(hex) .. convert.fg(convert.contrast(hex))
	local name = truncate(names[index] or "", CELL)
	local left, right = selected and "[" or " ", selected and "]" or " "
	return left .. style .. center(tostring(index), CELL) .. convert.RESET .. right, left .. style .. center(name, CELL) .. convert.RESET .. right
end

-- La ligne 1 : le titre, puis les onglets ; l'onglet affiché est entre crochets.
local function title_line(tab, labels)
	local names = labels.settings_tabs or {}
	local parts = {}
	for i = 1, M.TAB_COUNT do
		local name = names[i] or tostring(i)
		parts[i] = (i == tab) and ("[" .. name .. "]") or (" " .. name .. " ")
	end
	return "  " .. labels.settings_title .. "  " .. table.concat(parts, " ")
end

-- La valeur d'un réglage quand rien n'est choisi : sa valeur par défaut, sinon sa valeur « aucun » (none).
function M.fallback(definition)
	if definition.default ~= nil then
		return definition.default
	end
	return definition.none
end

-- La valeur d'un réglage, avec des flèches qui montrent dans quel sens elle peut encore changer.
--   Un nombre : « ◀ 12 » au maximum, « ◀ 6 ▶ » au milieu, «   1 ▶ » au minimum. S'il a une valeur « aucun » (none),
--   c'est elle qui est tout en bas : «   aucun ▶ », puis « ◀ 0h30 ▶ ».
--   Un choix ou un oui/non : les valeurs défilent en boucle, donc toujours les deux flèches : « ◀ lundi ▶ ».
-- shown : le texte à afficher (la valeur traduite) ; par défaut, la valeur elle-même.
function M.format_value(definition, value, shown)
	shown = shown or tostring(value)
	if definition.kind == "enum" or definition.kind == "boolean" or definition.kind == "color" then
		return "◀ " .. shown .. " ▶"
	end
	local lowest = (definition.none ~= nil) and definition.none or definition.min
	local left = (value > lowest) and "◀ " or "  "
	local right = (value < definition.max) and " ▶" or ""
	return left .. shown .. right
end

-- La valeur suivante quand on appuie sur ← (delta = -1) ou → (delta = 1).
--   Un nombre : step de plus ou de moins (1 par défaut), sans sortir de ses limites ; sous le minimum, la valeur
--   « aucun » s'il y en a une (et de « aucun », → donne le minimum).
--   Un choix : la valeur suivante (ou précédente) de la liste, en boucle.
--   Un oui/non : l'inverse.
function M.step(definition, value, delta)
	if definition.kind == "boolean" then
		return not value
	elseif definition.kind == "enum" then
		local values = definition.values
		local position = 1
		for i, allowed in ipairs(values) do
			if allowed == value then
				position = i
			end
		end
		return values[(position - 1 + delta) % #values + 1]
	end
	if definition.none ~= nil then
		if value == definition.none then
			return (delta > 0) and definition.min or definition.none
		end
		if delta < 0 and value <= definition.min then
			return definition.none
		end
	end
	local next_value = math.max(definition.min, math.min(definition.max, value + delta * (definition.step or 1)))
	return math.tointeger(next_value) or next_value
end

-- Les choix de la couleur du trait : le gris par défaut, puis les 16 couleurs de la palette proposée (la classique, ou
-- celles du thème). Renvoie { colors = { ... }, names = { ... } }.
function M.border_choices(colors, names, gray_name)
	local out = { colors = { assemble.BORDER_COLOR }, names = { gray_name or "gris" } }
	for i, color in ipairs(colors or {}) do
		out.colors[#out.colors + 1] = color
		out.names[#out.names + 1] = (names or {})[i] or color
	end
	return out
end

-- La position d'une couleur dans les choix (sans tenir compte des majuscules), ou nil.
local function choice_index(choices, value)
	for i, color in ipairs(choices.colors) do
		if type(value) == "string" and color:upper() == value:upper() then
			return i
		end
	end
	return nil
end

-- La couleur suivante (delta = 1) ou précédente (-1) dans les choix, en boucle. Une couleur qui n'y est pas (écrite à
-- la main) : on repart du gris.
function M.step_choice(choices, value, delta)
	local position = choice_index(choices, value) or 1
	return choices.colors[(position - 1 + delta) % #choices.colors + 1]
end

-- Une durée en heures, comme dans le calendrier : 7.5 -> « 7h30 », 8 -> « 8h00 ».
local function hours_text(hours)
	local minutes = math.floor(hours * 60 + 0.5)
	return string.format("%dh%02d", minutes // 60, minutes % 60)
end

-- Le texte affiché pour une valeur : sa traduction (settings_values dans i18n), sinon la valeur elle-même.
-- Les oui/non sont rangés sous les clés « yes » et « no », la valeur « aucun » sous « none ».
local function value_text(key, value, labels, state)
	local texts = labels.settings_values or {}
	local definition = schema.get(key) or {}
	if key == "border_color" then
		-- son nom, puis un aperçu du trait dans cette couleur et dans le style choisi
		local choices = state.border_choices or M.border_choices({}, {}, texts.border_gray)
		local index = choice_index(choices, value)
		local b = assemble.BORDER_STYLES[state.values.border_style] or assemble.BORDER_STYLES.rounded
		local name = index and choices.names[index] or value
		return name .. " " .. convert.fg(value) .. b.tl .. b.h .. b.tr .. convert.RESET
	end
	if type(value) == "boolean" then
		return (texts.boolean or {})[value and "yes" or "no"] or tostring(value)
	end
	if definition.none ~= nil and value == definition.none then
		return texts.none or tostring(value)
	end
	if key == "goal_hours" then
		return hours_text(value)
	end
	if key == "goal_days" then
		return string.format(texts.goal_days or "%d / 7", value)
	end
	return (texts[key] or {})[value] or tostring(value)
end

local function message_line(message, labels)
	if message == M.MESSAGE.SAVED then
		return "  " .. labels.settings_saved
	elseif message == M.MESSAGE.FAILED then
		return "  " .. labels.settings_failed
	elseif message == M.MESSAGE.CONSENT then
		return "  " .. labels.settings_consent_saved
	elseif message == M.MESSAGE.SETTING_SAVED then
		return "  " .. labels.settings_setting_saved
	end
	return ""
end

-- Un onglet de réglages (Calendrier, Général) : un réglage par ligne, le réglage choisi marqué par « ▸ », son explication
-- en dessous de la liste.
--   state = { tab = l'onglet, row = le numéro du réglage choisi, values = { max_months = 12, ... }, message = M.MESSAGE.* }
local function render_list(state, labels)
	local list = M.LISTS[state.tab]
	local names = labels.settings_names or {}
	local hints = labels.settings_hints or {}
	local lines = {
		title_line(state.tab, labels),
		"  " .. labels.settings_calendar_help1,
		"  " .. labels.settings_calendar_help2,
		"",
		"  " .. (labels[list.heading] or ""),
		"",
	}
	for i, key in ipairs(list.settings) do
		local definition = schema.get(key)
		local value = state.values[key]
		if value == nil then -- pas « or » : avec un oui/non, false or true donnerait true
			value = M.fallback(definition)
		end
		local name = names[key] or key
		local padding = string.rep(" ", math.max(1, NAME_WIDTH - (utf8.len(name) or #name)))
		lines[#lines + 1] = (i == state.row and "▸ " or "  ") .. name .. padding .. M.format_value(definition, value, value_text(key, value, labels, state))
	end
	lines[#lines + 1] = ""
	local selected = list.settings[state.row]
	lines[#lines + 1] = (selected and hints[selected]) and ("  " .. hints[selected]) or ""
	while #lines < LINES - 1 do
		lines[#lines + 1] = ""
	end
	lines[#lines + 1] = message_line(state.message, labels)
	return lines, M.GRID_WIDTH
end

-- Le texte de la page, sous forme de lignes. Toujours le même nombre de lignes (les lignes facultatives restent vides),
-- pour que la page ne saute pas quand un message apparaît.
--   state.tab = l'onglet affiché (M.TAB.COLORS par défaut) ; pour l'onglet Calendrier, voir render_calendar.
--   state = { index = 1 à 16 (la couleur choisie), current = "#RRGGBB" ou nil (la couleur enregistrée),
--             gradient_off = true si le dégradé est désactivé, message = M.MESSAGE.*,
--             colors = les 16 couleurs (la palette classique par défaut), names = leurs 16 noms (ceux de la palette classique
--             par défaut), consent_line = le texte de la question sur les couleurs du thème (ligne 4), ou nil }
-- Renvoie les lignes et la largeur du tableau de couleurs (la largeur qu'on centre).
function M.render(state, labels)
if M.LISTS[state.tab] then
	return render_list(state, labels)
end
local colors = state.colors or palette.COLORS
local names = state.names or labels.palette or {}
local lines = {}
lines[#lines + 1] = title_line(M.TAB.COLORS, labels)
lines[#lines + 1] = "  " .. labels.settings_help1
lines[#lines + 1] = "  " .. labels.settings_help2
lines[#lines + 1] = state.consent_line and ("  " .. state.consent_line) or ""
lines[#lines + 1] = "  " .. labels.settings_color
lines[#lines + 1] = ""
for row = 0, ROWS - 1 do
local first, second = { "  " }, { "  " }
for col = 0, COLUMNS - 1 do
local index = row * COLUMNS + col + 1
local a, b = cell(index, index == state.index, colors, names)
first[#first + 1] = a
second[#second + 1] = b
if col < COLUMNS - 1 then
first[#first + 1] = " "
second[#second + 1] = " "
end
end
lines[#lines + 1] = table.concat(first)
lines[#lines + 1] = table.concat(second)
if row < ROWS - 1 then
lines[#lines + 1] = ""
end
end
lines[#lines + 1] = ""
local chosen = colors[state.index]
lines[#lines + 1] = "  " .. labels.settings_preview .. " : " .. gradient.make({ color = chosen }).legend()
lines[#lines + 1] = "  " .. string.format(labels.settings_selected, state.index, names[state.index] or "", chosen)
if state.current then
local known = palette.index_of(state.current, colors) ~= nil
lines[#lines + 1] = "  " .. string.format(known and labels.settings_current or labels.settings_current_custom, state.current)
else
lines[#lines + 1] = ""
end
lines[#lines + 1] = state.gradient_off and ("  " .. labels.settings_gradient_off) or ""
lines[#lines + 1] = message_line(state.message, labels)
return lines, M.GRID_WIDTH
end

-- ctx fournit ce que la page ne sait pas faire seule :
--   wezterm, G (wezterm.GLOBAL), num(v)
--   cfg()               les réglages en cours (gradient_color, gradient)
--   labels()            les textes dans la langue choisie
--   blocker_args()      le programme qui garde l'onglet ouvert
--   store               settings/store (load, save)
--   settings_path()     le chemin du fichier de réglages
--   apply(changes)      applique tout de suite des réglages au plugin en cours { gradient_color = "#..." }
--   refresh_calendar(window, pane)   redessine la page du calendrier si elle est ouverte
-- Facultatifs (la question sur les couleurs du thème n'existe que si consent est fourni) :
--   consent()           la réponse enregistrée : true (oui), false (non) ou nil (pas encore répondu)
--   palette()           la palette à proposer : { kind = "theme", colors = {16 couleurs} } ou { kind = "classic",
--                       unavailable = "raison" } (ou { kind = "classic" })
--   settings_key()      le nom de la touche qui ouvre cette page (pour la notification)
function M.create(ctx)
local wezterm, G, num = ctx.wezterm, ctx.G, ctx.num
local act = wezterm.action
local ui = screen.bind(wezterm)
local page = {}

-- L'état de la page, dans wezterm.GLOBAL sous forme de simples nombres :
--   logtime_settings_pane (le panneau de la page), logtime_settings_index (la couleur choisie), logtime_settings_message
local function page_id()
		return num(G.logtime_settings_pane)
	end

	local function current_color()
		return palette.normalize(ctx.cfg().gradient_color)
	end

	-- La palette proposée : celle du thème si l'utilisateur a accepté et que le thème est lisible, sinon la classique.
-- Renvoie { kind, colors, unavailable }.
local function active_palette()
local given = ctx.palette and ctx.palette() or nil
if given and given.kind == "theme" and type(given.colors) == "table" and #given.colors == palette.COUNT then
return { kind = "theme", colors = given.colors }
end
return { kind = "classic", colors = palette.COLORS, unavailable = given and given.unavailable or nil }
end

-- Les choix de la couleur du trait : le gris, puis la palette proposée, avec ses noms.
local function border_choices()
local labels = ctx.labels()
local active = active_palette()
local names = (active.kind == "theme" and labels.palette_theme) or labels.palette
return M.border_choices(active.colors, names, (labels.settings_values or {}).border_gray)
end

-- Le numéro de cette couleur dans la palette proposée (exact, sinon le plus proche), ou nil.
local function position_in(color, colors)
return color and (palette.index_of(color, colors) or palette.nearest(color, colors)) or nil
end

local DEFAULT_COLOR = palette.COLORS[palette.DEFAULT_INDEX]

-- La couleur choisie au départ : celle qui est enregistrée (ou la plus proche si ce n'est pas une couleur de la palette).
	local function initial_index()
		local colors = active_palette().colors
		return position_in(current_color(), colors) or position_in(DEFAULT_COLOR, colors) or 1
	end

	local function selected_index()
		local index = num(G.logtime_settings_index)
		if not index or index < 1 or index > palette.COUNT then
			return initial_index()
		end
		return math.floor(index)
	end

	-- L'onglet affiché (logtime_settings_tab) et, dans un onglet de réglages, le réglage choisi (logtime_settings_row).
	local function current_tab()
		local tab = num(G.logtime_settings_tab)
		if M.LISTS[tab] then
			return tab
		end
		return M.TAB.COLORS
	end

	-- La liste des réglages de l'onglet affiché (nil dans l'onglet Couleurs).
	local function current_list()
		local list = M.LISTS[current_tab()]
		return list and list.settings or nil
	end

	local function current_row()
		local row = num(G.logtime_settings_row)
		local list = current_list() or {}
		if not row or row < 1 or row > #list then
			return 1
		end
		return math.floor(row)
	end

	-- La valeur en cours d'un réglage : celle du plugin, sinon sa valeur par défaut (ou « aucun »).
	local function setting_value(key)
		local value = ctx.cfg()[key]
		local ok, normalized = schema.validate(key, value)
		if ok then
			return normalized
		end
		return M.fallback(schema.get(key))
	end

	local function dims_of(pane)
		local ok, dims = pcall(function()
			return pane:get_dimensions()
		end)
		if ok and dims then
			return { cols = dims.cols, rows = dims.viewport_rows }
		end
		return nil
	end

	-- Le texte de la page (lignes) pour cette taille de fenêtre. Renvoie les lignes, la largeur à centrer, et true si la
	-- page tient en entier. Si elle ne tient pas, ce sont les lignes d'un message « fenêtre trop petite ».
function page.build_lines(dims)
local labels = ctx.labels()
local active = active_palette()
local consent_line
if ctx.consent then
local answer = ctx.consent()
if answer == nil then
consent_line = labels.consent_ask
elseif answer == true then
consent_line = (active.kind == "theme") and labels.consent_yes or labels.consent_unavailable
else
consent_line = labels.consent_no
end
end
local values = {}
for _, list in pairs(M.LISTS) do
	for _, key in ipairs(list.settings) do
		values[key] = setting_value(key)
	end
end
local lines, width = M.render({
tab = current_tab(),
row = current_row(),
values = values,
border_choices = border_choices(),
index = selected_index(),
current = current_color(),
gradient_off = ctx.cfg().gradient == false,
message = num(G.logtime_settings_message) or M.MESSAGE.NONE,
colors = active.colors,
names = (active.kind == "theme" and labels.palette_theme) or labels.palette,
consent_line = consent_line,
}, labels)
if dims and ((tonumber(dims.cols) or 0) < M.GRID_WIDTH or (tonumber(dims.rows) or 0) < #lines) then
local title = labels.settings_too_small
local hint = string.format(labels.settings_too_small_hint, M.GRID_WIDTH, #lines)
return { title, hint }, math.max(layout.visible_width(title), layout.visible_width(hint)), false
end
return lines, width, true
end

local function redraw(pane, first)
local dims = dims_of(pane)
local lines, width, fits = page.build_lines(dims)
if dims then
lines = layout.center(lines, width, dims.cols, dims.rows)
end
safe.trace(wezterm, string.format("logtime : dessin de la page de personnalisation dans le panneau %s (choix %d, %s)", tostring(pane:pane_id()), selected_index(), fits and "complète" or "fenêtre trop petite"))
ui.draw(pane, table.concat(lines, "\n"), first)
end

function page.is_page(pane)
local id = page_id()
return id ~= nil and pane:pane_id() == id
end

local function redraw_later(pane_id, delays)
ui.later(pane_id, delays, function(pane)
if page_id() == pane:pane_id() then
redraw(pane, false)
end
end)
end

-- Ouvre la page dans un nouvel onglet (ou remet devant celle qui existe déjà).
function page.open(window, pane)
local existing = ui.find_pane(page_id())
if existing then
pcall(function()
existing:tab():activate()
end)
keytable.activate(wezterm, window, existing, M.TABLE_NAME)
redraw(existing, false)
return
end
G.logtime_settings_pane = nil

local tab, page_pane = window:mux_window():spawn_tab({
domain = { DomainName = "local" },
args = ctx.blocker_args(),
})
pcall(function()
tab:activate()
end)

G.logtime_settings_pane = page_pane:pane_id()
G.logtime_settings_index = initial_index()
G.logtime_settings_message = M.MESSAGE.NONE
G.logtime_settings_tab = M.TAB.COLORS
G.logtime_settings_row = 1
safe.trace(wezterm, "logtime : page de personnalisation ouverte dans le panneau " .. tostring(page_pane:pane_id()))

redraw(page_pane, true)
redraw_later(page_pane:pane_id(), { 0.4, 1.2 })
keytable.activate(wezterm, window, page_pane, M.TABLE_NAME)
end

-- Enregistre un réglage dans le fichier de réglages (en gardant les autres réglages qui y sont) et l'applique tout de
-- suite. Renvoie true si c'est fait ; sinon l'erreur est écrite dans les journaux et le message d'échec est préparé.
local function store_setting(key, value)
	local path = ctx.settings_path()
	local current = ctx.store.load(path)
	current[key] = value
	local ok, err = ctx.store.save(path, current)
	if not ok then
		wezterm.log_error("logtime : enregistrement des réglages impossible : " .. tostring(err))
		G.logtime_settings_message = M.MESSAGE.FAILED
		return false
	end
	ctx.apply({ [key] = value })
	return true
end

-- Onglet Calendrier : enregistre la nouvelle valeur du réglage et redessine le calendrier s'il est ouvert.
local function change_setting(window, pane, key, value)
	if value == setting_value(key) then
		redraw(pane, false) -- déjà à cette valeur (au bord, ou déjà la valeur par défaut) : rien à écrire
		return
	end
	if store_setting(key, value) then
		G.logtime_settings_message = M.MESSAGE.SETTING_SAVED
		safe.trace(wezterm, "logtime : réglage enregistré : " .. key .. " = " .. tostring(value))
		pcall(ctx.refresh_calendar, window, pane)
	end
	redraw(pane, false)
end

local function move(delta_row, delta_col)
return function(window, pane)
local list = current_list()
if list then
	if delta_row ~= 0 then
		G.logtime_settings_row = math.max(1, math.min(#list, current_row() + delta_row))
		G.logtime_settings_message = M.MESSAGE.NONE
		redraw(pane, false)
	else
		local key = list[current_row()]
		local definition = schema.get(key)
		if definition.kind == "color" then
			change_setting(window, pane, key, M.step_choice(border_choices(), setting_value(key), delta_col))
		else
			change_setting(window, pane, key, M.step(definition, setting_value(key), delta_col))
		end
	end
	return
end
local index = selected_index() - 1
local row = math.max(0, math.min(ROWS - 1, index // COLUMNS + delta_row))
local col = math.max(0, math.min(COLUMNS - 1, index % COLUMNS + delta_col))
G.logtime_settings_index = row * COLUMNS + col + 1
G.logtime_settings_message = M.MESSAGE.NONE
redraw(pane, false)
end
end

-- Enregistre la couleur dans le fichier de réglages (en gardant les autres réglages qui y sont), l'applique tout de
	-- suite et redessine le calendrier s'il est ouvert.
local function save(window, pane, color)
if store_setting("gradient_color", color) then
G.logtime_settings_message = M.MESSAGE.SAVED
safe.trace(wezterm, "logtime : couleur enregistrée : " .. color)
pcall(ctx.refresh_calendar, window, pane)
end
redraw(pane, false)
end

-- Entrée : enregistre la couleur choisie (les onglets de réglages n'en ont pas besoin : chaque changement y est enregistré).
local function choose(window, pane)
if current_tab() ~= M.TAB.COLORS then
	return
end
save(window, pane, active_palette().colors[selected_index()])
end

-- d : la couleur par défaut du plugin (l'or), et dans la palette proposée la case qui lui ressemble le plus.
	-- Dans un onglet de réglages : la valeur par défaut du réglage choisi (ou « aucun » s'il n'en a pas).
	local function default(window, pane)
		local list = current_list()
		if list then
			local key = list[current_row()]
			change_setting(window, pane, key, M.fallback(schema.get(key)))
			return
		end
		G.logtime_settings_index = position_in(DEFAULT_COLOR, active_palette().colors) or 1
		save(window, pane, DEFAULT_COLOR)
	end

	-- Tab : l'onglet suivant (après le dernier, retour au premier).
	local function next_tab(window, pane)
		G.logtime_settings_tab = current_tab() % M.TAB_COUNT + 1
		G.logtime_settings_row = 1
		G.logtime_settings_message = M.MESSAGE.NONE
		redraw(pane, false)
	end

	-- y / n : la réponse à la question sur les couleurs du thème, enregistrée dans le fichier de réglages et appliquée
	-- tout de suite. La palette proposée change ; le choix se replace sur la couleur enregistrée (ou la plus proche).
	local function answer(value)
		return function(window, pane)
			if current_tab() ~= M.TAB.COLORS then
				return -- la question n'est affichée que dans l'onglet Couleurs
			end
			if store_setting("theme_colors", value) then
				G.logtime_settings_index = initial_index()
				G.logtime_settings_message = M.MESSAGE.CONSENT
				safe.trace(wezterm, "logtime : couleurs du thème : " .. (value and "oui" or "non"))
			end
			redraw(pane, false)
		end
	end

	-- Au chargement de la config : tant que l'utilisateur n'a pas répondu, une notification (une seule fois par session de
-- WezTerm) lui dit où répondre. Une notification qui échoue (Windows peut les masquer) ne gêne rien.
	function page.on_config_loaded(window, pane)
		if not ctx.consent or ctx.consent() ~= nil or num(G.logtime_consent_notified) then
			return
		end
		G.logtime_consent_notified = 1
		local labels = ctx.labels()
		pcall(function()
			window:toast_notification("logtime", string.format(labels.consent_toast, ctx.settings_key and ctx.settings_key() or "F4"), nil, 20000)
		end)
		safe.trace(wezterm, "logtime : notification : question sur les couleurs du thème")
	end

	local function close(window, pane)
		G.logtime_settings_pane = nil
		keytable.leave(wezterm, window, pane)
		window:perform_action(act.CloseCurrentTab({ confirm = false }), pane)
	end

	function page.bindings()
		local list = {
			{ key = "h", run = move(0, -1) },
			{ key = "LeftArrow", run = move(0, -1) },
			{ key = "l", run = move(0, 1) },
			{ key = "RightArrow", run = move(0, 1) },
			{ key = "k", run = move(-1, 0) },
			{ key = "UpArrow", run = move(-1, 0) },
			{ key = "j", run = move(1, 0) },
			{ key = "DownArrow", run = move(1, 0) },
			{ key = "Enter", run = choose },
			{ key = "d", run = default },
			{ key = "Tab", run = next_tab },
			{ key = "q", run = close },
			{ key = "Escape", run = close },
		}
		if ctx.consent then
			list[#list + 1] = { key = "y", run = answer(true) }
			list[#list + 1] = { key = "n", run = answer(false) }
		end
		return list
	end

	function page.key_table()
		return keytable.build(wezterm, page.bindings(), page.is_page, M.EVENT_PREFIX)
	end

	function page.on_resize(window, pane)
		local id = page_id()
		local page_pane = ui.find_pane(id)
		if not page_pane then
			return
		end
		redraw(page_pane, false)
		redraw_later(id, { 0.3, 1.0 })
	end

	return page
end

return M
