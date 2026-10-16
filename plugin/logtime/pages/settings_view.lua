-- plugin/logtime/pages/settings_view.lua : le dessin de la page de personnalisation (F4), à la taille de la fenêtre.
-- Aucune dépendance à WezTerm : se teste avec un simple interpréteur Lua.
--
-- Toute la fenêtre est utilisée, dans un cadre :
--   ╭──────────┬────────┬──────────┬─────────┬────────────────────────────╮
--   │ Settings │ Colors │ Calendar │ General │                            │  l'onglet ouvert sur fond coloré
--   ├──────────┴────────┴──────────┴─────────┤                            │
--   │ d: default // q: close // …  (souligné) │          l'aperçu          │
--   │ Arrows or h j k l: … (souligné)         │   (centré dans sa zone)    │
--   │ ╭──────────────────────────╮            │                            │
--   │ │ y: use your theme colors │            │                            │  coloré quand c'est actif
--   │ ╰──────────────────────────╯            │                            │
--   ├────────────────────────────────────────┤                            │
--   │ Gradient color:  ╭ Preview: … ╮         │                            │
--   │  ██████  ██████  ██████  ██████         │                            │  les 16 couleurs, qui grandissent
--   │  …                                      │                            │  avec la fenêtre ; la choisie
--   │ Choice: … // Saved color: …  (soulignés) │                            │  dans un cadre blanc ou noir
--   ╰────────────────────────────────────────┴────────────────────────────╯
-- Si la fenêtre n'est pas assez large pour l'aperçu, le panneau de gauche prend toute la largeur.
local load = ...
local layout = load("calendar/layout")
local convert = load("color/convert")

local M = {}

M.LEFT_SHARE = 0.42 -- la part de la largeur pour le panneau de gauche (quand l'aperçu est à droite)
M.MIN_LEFT = 57 -- la largeur minimum du panneau de gauche (sans ses traits) : une explication de réglage fait 55 au plus
M.COLUMNS, M.ROWS = 4, 4 -- les 16 couleurs
M.MIN_SWATCH_HEIGHT = 2 -- une case de couleur : au moins 2 lignes (le cadre de la case choisie : haut et bas)
M.MIN_SWATCH_WIDTH = 6
M.SWATCH_GAP_X, M.SWATCH_GAP_Y = 2, 1

M.UNDERLINE, M.UNDERLINE_OFF = "\27[4m", "\27[24m"

local vw = layout.visible_width

function M.underline(text)
	return M.UNDERLINE .. text .. M.UNDERLINE_OFF
end

-- Complète une ligne jusqu'à `width` colonnes ; trop longue, elle est coupée (sans ses couleurs : un cas qui ne doit
-- pas arriver avec les largeurs minimum, mais une page ne doit jamais déborder de son cadre).
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
	local left = math.max(0, math.floor((width - vw(text)) / 2))
	return fit(string.rep(" ", left) .. text, width)
end

-- Les largeurs des 4 cases d'onglets dans `width` colonnes (3 traits entre elles) : le reste va aux premières.
function M.tab_widths(width)
	local inner = width - 3
	local base, extra = inner // 4, inner % 4
	local widths = {}
	for i = 1, 4 do
		widths[i] = base + (i <= extra and 1 or 0)
	end
	return widths
end

-- Une case de couleur : `w` x `h`, sur le fond de la couleur ; la case choisie a un cadre blanc ou noir (le plus
-- visible sur cette couleur) dessiné DANS la case.
function M.swatch(hex, selected, w, h)
	local bg = convert.bg(hex)
	local lines = {}
	for row = 1, h do
		local text
		if selected and row == 1 then
			text = "┌" .. string.rep("─", w - 2) .. "┐"
		elseif selected and row == h then
			text = "└" .. string.rep("─", w - 2) .. "┘"
		elseif selected then
			text = "│" .. string.rep(" ", w - 2) .. "│"
		else
			text = string.rep(" ", w)
		end
		local fg = selected and convert.fg(convert.contrast(hex)) or ""
		lines[row] = bg .. fg .. text .. convert.RESET
	end
	return lines
end

-- La grille des 16 couleurs dans `width` x `height` (avec une marge d'une colonne à gauche). Les cases grandissent pour
-- remplir la place. Renvoie les lignes (exactement `height`).
function M.grid(colors, index, width, height)
	local gx, gy = M.SWATCH_GAP_X, M.SWATCH_GAP_Y
	local w = math.max(M.MIN_SWATCH_WIDTH, (width - 2 - (M.COLUMNS - 1) * gx) // M.COLUMNS)
	local h = math.max(M.MIN_SWATCH_HEIGHT, (height - (M.ROWS - 1) * gy) // M.ROWS)
	local out = {}
	for row = 0, M.ROWS - 1 do
		local cells = {}
		for col = 0, M.COLUMNS - 1 do
			local i = row * M.COLUMNS + col + 1
			cells[#cells + 1] = M.swatch(colors[i] or "#000000", i == index, w, h)
		end
		for line = 1, h do
			local parts = {}
			for col = 1, M.COLUMNS do
				parts[#parts + 1] = cells[col][line]
			end
			out[#out + 1] = fit(" " .. table.concat(parts, string.rep(" ", gx)), width)
		end
		if row < M.ROWS - 1 then
			for _ = 1, gy do
				out[#out + 1] = string.rep(" ", width)
			end
		end
	end
	while #out < height do
		out[#out + 1] = string.rep(" ", width)
	end
	return out
end

-- Le bouton « y : utiliser les couleurs de ton thème » : 3 lignes, encadré ; coloré (fond `accent`) quand c'est actif.
-- `note` (facultatif) : un texte à droite du bouton (l'état : thème introuvable, comment revenir…).
function M.button(text, active, accent, note, width)
	local inner = " " .. text .. " "
	local n = vw(inner)
	local style, off = "", ""
	if active then
		style, off = convert.bg(accent) .. convert.fg(convert.contrast(accent)), convert.RESET
	end
	local edge_style = active and convert.fg(accent) or ""
	local edge_off = active and convert.RESET or ""
	return {
		fit(" " .. edge_style .. "╭" .. string.rep("─", n) .. "╮" .. edge_off, width),
		fit(
			" "
				.. edge_style
				.. "│"
				.. edge_off
				.. style
				.. inner
				.. off
				.. edge_style
				.. "│"
				.. edge_off
				.. (note and ("  " .. note) or ""),
			width
		),
		fit(" " .. edge_style .. "╰" .. string.rep("─", n) .. "╯" .. edge_off, width),
	}
end

-- L'aperçu du dégradé, encadré, précédé de son titre souligné : 3 lignes.
local function gradient_box(title, preview_text, width)
	local label = " " .. M.underline(title) .. "  "
	local pad = string.rep(" ", vw(label))
	local n = vw(preview_text) + 2
	return {
		fit(pad .. "╭" .. string.rep("─", n) .. "╮", width),
		fit(label .. "│ " .. preview_text .. " │", width),
		fit(pad .. "╰" .. string.rep("─", n) .. "╯", width),
	}
end

local SEPARATOR = {} -- une ligne de séparation du panneau de gauche (├────┤)

-- Le contenu du panneau de gauche, sous la barre d'onglets : une liste de lignes (ou SEPARATOR), exactement `height`.
--   o.help        : les deux lignes d'aide (soulignées)
--   o.button      : { text, active, note } pour l'onglet Couleurs (sinon nil)
--   o.colors_tab  : { colors, index, gradient_title, gradient_preview, choice, saved, gradient_off } (onglet Couleurs)
--   o.list        : les lignes d'un onglet de réglages (Calendrier, Général)
--   o.message     : le message du bas (« ✓ Enregistré », la raison d'un échec…) ou ""
local function left_content(o, width, height)
	local top = {}
	for _, line in ipairs(o.help or {}) do
		top[#top + 1] = fit(" " .. M.underline(line), width)
	end
	if o.button then
		for _, line in ipairs(M.button(o.button.text, o.button.active, o.accent, o.button.note, width)) do
			top[#top + 1] = line
		end
	end
	top[#top + 1] = SEPARATOR
	local bottom = {}
	local c = o.colors_tab
	if c then
		for _, line in ipairs(gradient_box(c.gradient_title, c.gradient_preview, width)) do
			top[#top + 1] = line
		end
		top[#top + 1] = string.rep(" ", width)
		bottom[#bottom + 1] = string.rep(" ", width)
		local saved = c.saved and (" // " .. M.underline(c.saved)) or ""
		bottom[#bottom + 1] = fit(" " .. M.underline(c.choice) .. saved, width)
		bottom[#bottom + 1] = fit(c.gradient_off and (" " .. c.gradient_off) or "", width)
	else
		for _, line in ipairs(o.list or {}) do
			top[#top + 1] = fit(line, width)
		end
	end
	bottom[#bottom + 1] = fit(o.message and o.message ~= "" and o.message or "", width)
	local middle_height = height - #top - #bottom
	local middle = {}
	if c then
		middle = M.grid(c.colors, c.index, width, middle_height)
	else
		for _ = 1, middle_height do
			middle[#middle + 1] = string.rep(" ", width)
		end
	end
	local out = {}
	for _, list in ipairs({ top, middle, bottom }) do
		for _, line in ipairs(list) do
			out[#out + 1] = line
		end
	end
	return out
end

-- La hauteur minimum de la page (cadre compris) et la largeur minimum du panneau de gauche, pour ce contenu.
function M.minimum(o)
	local help_width = 0
	for _, line in ipairs(o.help or {}) do
		help_width = math.max(help_width, vw(line) + 2)
	end
	if o.button then
		help_width = math.max(help_width, vw(o.button.text) + 6 + (o.button.note and vw(o.button.note) + 2 or 0))
	end
	for _, line in ipairs(o.list or {}) do
		help_width = math.max(help_width, vw(line) + 1)
	end
	local left = math.max(M.MIN_LEFT, help_width)
	local rows = 3 + #(o.help or {}) + 1 + 1 -- cadre du haut, onglets, jonction ; aide ; séparation ; cadre du bas
	if o.button then
		rows = rows + 3
	end
	if o.colors_tab then
		rows = rows + 3 + 1 + (M.ROWS * M.MIN_SWATCH_HEIGHT + (M.ROWS - 1) * M.SWATCH_GAP_Y) + 3 + 1
	else
		rows = rows + #(o.list or {}) + 1
	end
	return left, rows
end

-- Dessine toute la page dans une fenêtre de `cols` x `rows`. Renvoie les lignes (exactement `rows`, chacune de `cols`
-- colonnes) et true si l'aperçu est affiché ; ou nil, la largeur et la hauteur qu'il faudrait (fenêtre trop petite).
--   o.b, o.edge  : les traits du cadre (assemble.BORDER_STYLES) et leur couleur (un code de couleur, ou "")
--   o.accent     : la couleur de l'onglet ouvert et du bouton actif ("#RRGGBB")
--   o.tabs       : les 4 noms de la barre d'onglets (le titre, puis les 3 onglets) ; o.tab : l'onglet ouvert (1 à 3)
--   o.preview    : { lines, width } ou nil
function M.draw(o, cols, rows)
	local min_left, min_rows = M.minimum(o)
	if cols < min_left + 2 or rows < min_rows then
		return nil, min_left + 2, min_rows
	end
	local b, edge = o.b, o.edge or ""
	local off = edge ~= "" and convert.RESET or ""
	local function e(s) -- un trait du cadre, dans sa couleur
		return edge .. s .. off
	end
	-- la place : le panneau de gauche, et l'aperçu à droite s'il tient
	local left = math.max(min_left, math.floor((cols - 3) * M.LEFT_SHARE))
	local right = cols - 3 - left
	local preview = o.preview
	local show_preview = preview ~= nil and right >= preview.width + 2 and rows - 2 >= #preview.lines
	if not show_preview then
		left, right = cols - 2, 0
	end
	local inner_rows = rows - 2
	-- le panneau de droite : l'aperçu centré dans sa zone
	local right_lines = {}
	if show_preview then
		local top = math.max(0, math.floor((inner_rows - #preview.lines) / 2))
		-- centré par sa largeur (pas par chaque ligne : les lignes d'un mois n'ont pas toutes la même longueur)
		local margin = math.max(0, math.floor((right - preview.width) / 2))
		for i = 1, inner_rows do
			right_lines[i] = fit(string.rep(" ", margin) .. (preview.lines[i - top] or ""), right)
		end
	end
	local function with_right(i, line)
		if not show_preview then
			return line .. e(b.v)
		end
		return line .. e(b.v) .. right_lines[i] .. e(b.v)
	end
	-- la barre d'onglets
	local widths = M.tab_widths(left)
	local cells, tops = {}, {}
	for i = 1, 4 do
		local name = centered(o.tabs[i] or "", widths[i])
		if i == (o.tab or 1) + 1 then
			name = convert.bg(o.accent) .. convert.fg(convert.contrast(o.accent)) .. name .. convert.RESET
		end
		cells[i] = name
		tops[i] = string.rep(b.h, widths[i])
	end
	local out = {}
	out[1] = e(b.tl .. table.concat(tops, b.t) .. (show_preview and (b.t .. string.rep(b.h, right)) or "") .. b.tr)
	out[2] = with_right(1, e(b.v) .. table.concat(cells, e(b.v)))
	-- la jonction sous les onglets (├──┴──┤) : à droite, elle touche le trait qui sépare l'aperçu
	out[3] = e(b.l .. table.concat(tops, b.b) .. b.r) .. (show_preview and (right_lines[2] .. e(b.v)) or "")
	local content = left_content(o, left, inner_rows - 2)
	for i, line in ipairs(content) do
		local r = i + 2
		if line == SEPARATOR then
			local sep = e(b.l .. string.rep(b.h, left) .. b.r)
			out[#out + 1] = show_preview and (sep .. right_lines[r] .. e(b.v)) or sep
		else
			out[#out + 1] = with_right(r, e(b.v) .. line)
		end
	end
	out[#out + 1] = e(b.bl .. string.rep(b.h, left) .. (show_preview and (b.b .. string.rep(b.h, right)) or "") .. b.br)
	return out, show_preview
end

return M
