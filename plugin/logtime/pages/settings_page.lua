-- plugin/logtime/pages/settings_page.lua : la page de personnalisation (touche F4), pour l'instant le choix de la couleur
-- du dégradé : un tableau de seize couleurs numérotées, un aperçu, et Entrée enregistre le choix dans le fichier de
-- réglages et l'applique tout de suite au calendrier (sans recharger WezTerm).
local load = ...
local layout = load("calendar/layout")
local screen = load("ui/screen")
local keytable = load("ui/keytable")
local safe = load("ui/safe")
local gradient = load("color/gradient")
local palette = load("color/palette")
local convert = load("color/convert")

local M = {}

M.TABLE_NAME = "logtime_settings"
M.EVENT_PREFIX = "logtime-settings"

local COLUMNS = 4
local ROWS = 4
local CELL = 11 -- largeur d'une couleur, sans ses crochets

-- Les messages affichés en bas de la page (gardés dans wezterm.GLOBAL sous forme de nombres).
M.MESSAGE = { NONE = 0, SAVED = 1, FAILED = 2 }

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
local function cell(index, selected, labels)
local hex = palette.COLORS[index]
local style = convert.bg(hex) .. convert.fg(convert.contrast(hex))
local name = truncate((labels.palette or {})[index] or "", CELL)
local left, right = selected and "[" or " ", selected and "]" or " "
return left .. style .. center(tostring(index), CELL) .. convert.RESET .. right, left .. style .. center(name, CELL) .. convert.RESET .. right
end

-- Le texte de la page, sous forme de lignes. Toujours le même nombre de lignes (les lignes facultatives restent vides),
-- pour que la page ne saute pas quand un message apparaît.
--   state = { index = 1 à 16 (la couleur choisie), current = "#RRGGBB" ou nil (la couleur enregistrée),
--             gradient_off = true si le dégradé est désactivé, message = M.MESSAGE.* }
-- Renvoie les lignes et la largeur du tableau de couleurs (la largeur qu'on centre).
function M.render(state, labels)
	local lines = {}
	lines[#lines + 1] = "  " .. labels.title .. " : " .. labels.settings_title
	lines[#lines + 1] = "  " .. labels.settings_help1
	lines[#lines + 1] = "  " .. labels.settings_help2
	lines[#lines + 1] = ""
	lines[#lines + 1] = "  " .. labels.settings_color
	lines[#lines + 1] = ""
	for row = 0, ROWS - 1 do
		local first, second = { "  " }, { "  " }
		for col = 0, COLUMNS - 1 do
			local index = row * COLUMNS + col + 1
			local a, b = cell(index, index == state.index, labels)
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
	local chosen = palette.COLORS[state.index]
	lines[#lines + 1] = "  " .. labels.settings_preview .. " : " .. gradient.make({ color = chosen }).legend()
	lines[#lines + 1] = "  " .. string.format(labels.settings_selected, state.index, (labels.palette or {})[state.index] or "", chosen)
	if state.current then
		local known = palette.index_of(state.current) ~= nil
		lines[#lines + 1] = "  " .. string.format(known and labels.settings_current or labels.settings_current_custom, state.current)
	else
		lines[#lines + 1] = ""
	end
	lines[#lines + 1] = state.gradient_off and ("  " .. labels.settings_gradient_off) or ""
	if state.message == M.MESSAGE.SAVED then
		lines[#lines + 1] = "  " .. labels.settings_saved
	elseif state.message == M.MESSAGE.FAILED then
		lines[#lines + 1] = "  " .. labels.settings_failed
	else
		lines[#lines + 1] = ""
	end
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

	-- La couleur choisie au départ : celle qui est enregistrée (ou la plus proche si ce n'est pas une couleur de la palette).
local function initial_index()
local color = current_color()
return (color and (palette.index_of(color) or palette.nearest(color))) or palette.DEFAULT_INDEX
end

local function selected_index()
local index = num(G.logtime_settings_index)
if not index or index < 1 or index > palette.COUNT then
return initial_index()
end
return math.floor(index)
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
		local lines, width = M.render({
index = selected_index(),
			current = current_color(),
			gradient_off = ctx.cfg().gradient == false,
			message = num(G.logtime_settings_message) or M.MESSAGE.NONE,
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
		safe.trace(wezterm, "logtime : page de personnalisation ouverte dans le panneau " .. tostring(page_pane:pane_id()))

		redraw(page_pane, true)
		redraw_later(page_pane:pane_id(), { 0.4, 1.2 })
		keytable.activate(wezterm, window, page_pane, M.TABLE_NAME)
	end

	local function move(delta_row, delta_col)
		return function(window, pane)
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
		local path = ctx.settings_path()
		local current = ctx.store.load(path)
		current.gradient_color = color
		local ok, err = ctx.store.save(path, current)
		if ok then
			ctx.apply({ gradient_color = color })
			G.logtime_settings_message = M.MESSAGE.SAVED
			safe.trace(wezterm, "logtime : couleur enregistrée : " .. color)
			pcall(ctx.refresh_calendar, window, pane)
		else
			wezterm.log_error("logtime : enregistrement des réglages impossible : " .. tostring(err))
			G.logtime_settings_message = M.MESSAGE.FAILED
		end
		redraw(pane, false)
	end

	local function choose(window, pane)
		save(window, pane, palette.COLORS[selected_index()])
	end

	local function default(window, pane)
		G.logtime_settings_index = palette.DEFAULT_INDEX
		save(window, pane, palette.COLORS[palette.DEFAULT_INDEX])
	end

	local function close(window, pane)
		G.logtime_settings_pane = nil
		keytable.leave(wezterm, window, pane)
		window:perform_action(act.CloseCurrentTab({ confirm = false }), pane)
	end

	function page.bindings()
		return {
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
			{ key = "q", run = close },
			{ key = "Escape", run = close },
		}
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
