-- plugin/logtime/pages/settings_view.lua : le dessin de la page de personnalisation (F4), à la taille de la fenêtre.
-- Aucune dépendance à WezTerm : se teste avec un simple interpréteur Lua.
--
-- Toute la fenêtre est utilisée, dans un cadre :
--   ╭──────────┬▄▄▄▄▄▄▄▄┬──────────┬─────────┬────────────────────────────╮
--   │ Settings │ Colors │ Calendar │ General │                            │  l'onglet ouvert rempli de sa couleur,
--   ├──────────┴▀▀▀▀▀▀▀▀┴──────────┴─────────┤                            │  du trait du haut à celui du bas
--   │  d: default  //  q: close  //  Tab …    │          l'aperçu          │  chaque ligne d'aide divisée en parts
--   │  Arrows …: choose  //  Enter: save      │   (centré dans sa zone)    │  égales ; seul le texte est souligné
--   │ ╭──────────────────────────╮            │                            │
--   │ │ y: use your theme colors │  note      │                            │  rempli de sa couleur quand c'est actif
--   │ ╰──────────────────────────╯            │                            │
--   ├────────────────────────────────────────┤                            │
--   │ Gradient color:          ╭ Preview ╮   │                            │  l'aperçu du dégradé collé à droite
--   │   ┌────────┐                            │                            │
--   │   │████████│   ████████   ████████  …  │                            │  16 cases (2 lignes de haut), réparties
--   │   └────────┘                            │                            │  sur la place ; la choisie encadrée
--   │  Choice: …   //   Saved color: …        │                            │
--   ╰────────────────────────────────────────┴────────────────────────────╯
-- Onglets Calendrier et Général : les réglages répartis sur la hauteur (le nom à gauche, la valeur collée à droite), le
-- réglage choisi rempli comme l'onglet ouvert, et son explication encadrée en bas.
-- Si la fenêtre n'est pas assez large pour l'aperçu, le panneau de gauche prend toute la largeur.
local load = ...
local layout = load("calendar/layout")
local convert = load("color/convert")

local M = {}

M.LEFT_SHARE = 0.42 -- la part de la largeur pour le panneau de gauche (quand l'aperçu est à droite)
M.MIN_LEFT = 57 -- la largeur minimum du panneau de gauche (sans ses traits) : une explication de réglage fait 55 au plus
M.COLUMNS, M.ROWS = 4, 4 -- les 16 couleurs
M.SWATCH_WIDTH = 10 -- une case de couleur : 10 colonnes (moins si la place manque)...
M.MIN_SWATCH_WIDTH = 6
M.SWATCH_HEIGHT = 2 -- ... sur 2 lignes ; l'espace entre les cases grandit avec la fenêtre
M.FRAME_COLOR = "#ECE6D9" -- le cadre de la case choisie (clair : il se voit autour de toutes les couleurs)
M.SEPARATOR_TEXT = "//"
M.GRADIENT_GAP = 2 -- lignes vides entre la séparation et l'aperçu du dégradé
M.CHOICE_GAP = 2 -- lignes vides entre le choix et le bas du panneau (les couleurs ont moins d'air autour d'elles)

M.UNDERLINE, M.UNDERLINE_OFF = "\27[4m", "\27[24m"
local UPPER_HALF, LOWER_HALF = "▀", "▄"

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

-- Les morceaux d'une ligne d'aide écrite « a // b // c ».
function M.parts(text)
	local out = {}
	for part in (tostring(text or "") .. " // "):gmatch("(.-)%s*//%s*") do
		if part:match("%S") then
			out[#out + 1] = part:match("^%s*(.-)%s*$")
		end
	end
	return out
end

-- Une ligne divisée en autant de parts égales qu'il y a de morceaux : chaque morceau centré dans sa part, « // » entre
-- les parts, seul le texte souligné (pas les espaces). Si un morceau ne tient pas dans sa part, les morceaux sont
-- espacés régulièrement. Renvoie une ligne de `width` colonnes.
function M.spread(parts, width, underline)
	local n = #parts
	if n == 0 then
		return string.rep(" ", width)
	end
	local style = underline and M.underline or function(t)
		return t
	end
	local sep = M.SEPARATOR_TEXT
	local column = (width - #sep * (n - 1)) // n
	local fits = true
	for _, part in ipairs(parts) do
		if vw(part) > column - 2 then -- au moins une colonne d'air de chaque côté (sinon il touche le « // » ou le cadre)
			fits = false
		end
	end
	local pieces = {}
	if fits then
		for i, part in ipairs(parts) do
			local len = vw(part)
			local left = (column - len) // 2
			pieces[i] = string.rep(" ", left) .. style(part) .. string.rep(" ", column - len - left)
		end
		return fit(table.concat(pieces, sep), width)
	end
	-- pas la place pour des parts égales : un espacement régulier entre les morceaux
	local total = #sep * (n - 1)
	for _, part in ipairs(parts) do
		total = total + vw(part)
	end
	local gap = math.max(1, (width - total) // (2 * n))
	for i, part in ipairs(parts) do
		pieces[i] = string.rep(" ", gap) .. style(part) .. string.rep(" ", gap)
	end
	local line = table.concat(pieces, sep)
	return fit(string.rep(" ", math.max(0, (width - vw(line)) // 2)) .. line, width) -- centrée
end

-- La largeur minimum d'une ligne divisée (les morceaux, les « // », une colonne de chaque côté de chacun).
local function spread_width(parts)
	local total = #M.SEPARATOR_TEXT * math.max(0, #parts - 1)
	for _, part in ipairs(parts) do
		total = total + vw(part) + 2
	end
	return total
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

local function filled(accent)
	return convert.bg(accent) .. convert.fg(convert.contrast(accent))
end

-- Le bouton « y : utiliser les couleurs de ton thème » : 3 lignes. Inactif : encadré. Actif : rempli de la couleur
-- `accent` sur ses 3 lignes (des demi-blocs en haut et en bas, à la place du cadre). `note` : un texte à sa droite.
function M.button(text, active, accent, note, width)
	local inner = " " .. text .. " "
	local n = vw(inner)
	local after = note and ("  " .. note) or ""
	if active then
		local half = convert.fg(accent)
		return {
			fit(" " .. half .. string.rep(LOWER_HALF, n + 2) .. convert.RESET, width),
			fit(" " .. filled(accent) .. " " .. inner .. " " .. convert.RESET .. after, width),
			fit(" " .. half .. string.rep(UPPER_HALF, n + 2) .. convert.RESET, width),
		}
	end
	return {
		fit(" ╭" .. string.rep("─", n) .. "╮", width),
		fit(" │" .. inner .. "│" .. after, width),
		fit(" ╰" .. string.rep("─", n) .. "╯", width),
	}
end

-- Le titre du dégradé (souligné) à gauche, et son aperçu encadré collé au bord droit : 3 lignes.
local function gradient_box(title, preview_text, width)
	local n = vw(preview_text) + 2
	local box_width = n + 2
	local label = " " .. M.underline(title)
	local left = math.max(0, width - box_width - 1)
	return {
		fit(string.rep(" ", left) .. "╭" .. string.rep("─", n) .. "╮", width),
		fit(fit(label, left) .. "│ " .. preview_text .. " │", width),
		fit(string.rep(" ", left) .. "╰" .. string.rep("─", n) .. "╯", width),
	}
end

-- Répartit `free` cases vides en `count` espaces (le reste aux premiers).
local function share(free, count)
	local out = {}
	for i = 1, count do
		out[i] = free // count + (i <= free % count and 1 or 0)
	end
	return out
end

-- La grille des 16 couleurs dans `width` x `height` : des cases de M.SWATCH_HEIGHT lignes, réparties régulièrement
-- (l'espace entre elles grandit avec la place) ; la case choisie a un cadre AUTOUR d'elle, dans cet espace.
-- Renvoie les lignes (exactement `height`).
function M.grid(colors, index, width, height)
	local cols, rows = M.COLUMNS, M.ROWS
	local sw = math.max(M.MIN_SWATCH_WIDTH, math.min(M.SWATCH_WIDTH, (width - 2 * (cols + 1)) // cols))
	local sh = M.SWATCH_HEIGHT
	local gaps_x = share(math.max(0, width - cols * sw), cols + 1)
	local gaps_y = share(math.max(0, height - rows * sh), rows + 1)
	-- la toile : une case par caractère (le texte affiché, avec ses codes de couleur)
	local canvas = {}
	for y = 1, height do
		canvas[y] = {}
		for x = 1, width do
			canvas[y][x] = " "
		end
	end
	local function put(x, y, text)
		if canvas[y] and x >= 1 and x <= width then
			canvas[y][x] = text
		end
	end
	local frame = convert.fg(M.FRAME_COLOR)
	local y = gaps_y[1]
	for row = 0, rows - 1 do
		local x = gaps_x[1]
		for col = 0, cols - 1 do
			local i = row * cols + col + 1
			local fill = convert.bg(colors[i] or "#000000") .. " " .. convert.RESET
			for dy = 1, sh do
				for dx = 1, sw do
					put(x + dx, y + dy, fill)
				end
			end
			if i == index then
				put(x, y, frame .. "┌" .. convert.RESET)
				put(x + sw + 1, y, frame .. "┐" .. convert.RESET)
				put(x, y + sh + 1, frame .. "└" .. convert.RESET)
				put(x + sw + 1, y + sh + 1, frame .. "┘" .. convert.RESET)
				for dx = 1, sw do
					put(x + dx, y, frame .. "─" .. convert.RESET)
					put(x + dx, y + sh + 1, frame .. "─" .. convert.RESET)
				end
				for dy = 1, sh do
					put(x, y + dy, frame .. "│" .. convert.RESET)
					put(x + sw + 1, y + dy, frame .. "│" .. convert.RESET)
				end
			end
			x = x + sw + gaps_x[col + 2]
		end
		y = y + sh + gaps_y[row + 2]
	end
	local out = {}
	for line = 1, height do
		out[line] = table.concat(canvas[line])
	end
	return out
end

-- Les réglages d'un onglet (Calendrier, Général) dans `width` x `height` : un par ligne, répartis sur la hauteur, le
-- nom à gauche et la valeur collée à droite ; le réglage choisi est rempli de la couleur `accent` (avec des demi-blocs
-- au-dessus et en dessous quand il y a la place). rows = { { name, value }, ... }, selected = son numéro.
function M.settings_rows(rows, selected, accent, width, height)
	local out = {}
	for i = 1, height do
		out[i] = string.rep(" ", width)
	end
	local count = #rows
	if count == 0 then
		return out
	end
	local gaps = share(math.max(0, height - count), count + 1)
	local y = gaps[1]
	local style = filled(accent)
	for i, row in ipairs(rows) do
		y = y + 1
		local name, value = "   " .. row.name, row.value .. "   "
		local room = width - vw(name)
		local line = name .. string.rep(" ", math.max(1, room - vw(value))) .. value
		if i == selected then
			-- les couleurs de la valeur (l'aperçu du trait) ne doivent pas effacer le fond de la ligne
			line = style
				.. line:gsub("\27%[0m", convert.RESET .. style)
				.. string.rep(" ", math.max(0, width - vw(line)))
				.. convert.RESET
			if gaps[i] >= 1 then
				out[y - 1] = convert.fg(accent) .. string.rep(LOWER_HALF, width) .. convert.RESET
			end
			if gaps[i + 1] >= 1 and y + 1 <= height then
				out[y + 1] = convert.fg(accent) .. string.rep(UPPER_HALF, width) .. convert.RESET
			end
		end
		out[y] = fit(line, width)
		y = y + gaps[i + 1]
	end
	return out
end

-- Un texte encadré sur toute la largeur (l'explication du réglage choisi) : 3 lignes.
local function text_box(text, width)
	local n = width - 4
	return {
		fit(" ╭" .. string.rep("─", n) .. "╮", width),
		fit(" │ " .. fit(text or "", n - 2) .. " │", width),
		fit(" ╰" .. string.rep("─", n) .. "╯", width),
	}
end

local SEPARATOR = {} -- une ligne de séparation du panneau de gauche (├────┤)

-- Le contenu du panneau de gauche, sous la barre d'onglets : une liste de lignes (ou SEPARATOR), exactement `height`.
--   o.help        : les lignes d'aide, chacune écrite « a // b // c » (divisée en parts égales, soulignée)
--   o.button      : { text, active, note } pour l'onglet Couleurs (sinon nil)
--   o.colors_tab  : { colors, index, gradient_title, gradient_preview, choice, saved, gradient_off } (onglet Couleurs)
--   o.list        : { rows = { { name, value }, ... }, selected, hint } (onglets Calendrier et Général)
--   o.message     : le message du bas (« ✓ Enregistré », la raison d'un échec…) ou ""
local function left_content(o, width, height)
	local blank = string.rep(" ", width)
	-- une ligne vide sous les onglets, entre les lignes d'aide, et après la dernière (avant le bouton ou la séparation)
	local top = { blank }
	for _, line in ipairs(o.help or {}) do
		top[#top + 1] = M.spread(M.parts(line), width, true)
		top[#top + 1] = blank
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
		for _ = 1, M.GRADIENT_GAP do
			top[#top + 1] = blank
		end
		for _, line in ipairs(gradient_box(c.gradient_title, c.gradient_preview, width)) do
			top[#top + 1] = line
		end
		local choice = { c.choice }
		if c.saved then
			choice[2] = c.saved
		end
		bottom[#bottom + 1] = M.spread(choice, width, true)
		for _ = 1, M.CHOICE_GAP do
			bottom[#bottom + 1] = blank
		end
		bottom[#bottom + 1] = fit(c.gradient_off and (" " .. c.gradient_off) or "", width)
	elseif o.list then
		for _, line in ipairs(text_box(o.list.hint, width)) do
			bottom[#bottom + 1] = line
		end
	end
	bottom[#bottom + 1] = fit(o.message and o.message ~= "" and o.message or "", width)
	local middle_height = height - #top - #bottom
	local middle
	if c then
		middle = M.grid(c.colors, c.index, width, middle_height)
	elseif o.list then
		middle = M.settings_rows(o.list.rows or {}, o.list.selected, o.accent, width, middle_height)
	else
		middle = {}
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

-- La largeur minimum du panneau de gauche et la hauteur minimum de la page (cadre compris), pour ce contenu.
function M.minimum(o)
	local left = M.MIN_LEFT
	for _, line in ipairs(o.help or {}) do
		left = math.max(left, spread_width(M.parts(line)))
	end
	if o.button then
		left = math.max(left, vw(o.button.text) + 6 + (o.button.note and vw(o.button.note) + 2 or 0))
	end
	local c = o.colors_tab
	if c then
		left = math.max(left, vw(c.gradient_title) + vw(c.gradient_preview) + 8)
		left = math.max(left, spread_width({ c.choice, c.saved or "" }))
		left = math.max(left, M.COLUMNS * M.MIN_SWATCH_WIDTH + 2 * (M.COLUMNS + 1))
	end
	if o.list then
		for _, row in ipairs(o.list.rows or {}) do
			left = math.max(left, vw(row.name) + vw(row.value) + 7)
		end
	end
	-- le cadre du haut, les onglets et leur jonction ; l'aide (une ligne vide avant chaque ligne d'aide, et après la
	-- dernière) ; la séparation ; le cadre du bas
	local rows = 3 + (2 * #(o.help or {}) + 1) + 1 + 1
	if o.button then
		rows = rows + 3
	end
	if c then
		rows = rows + (M.GRADIENT_GAP + 3) + (M.ROWS * M.SWATCH_HEIGHT + (M.ROWS + 1)) + (1 + M.CHOICE_GAP + 2)
	elseif o.list then
		rows = rows + (2 * #(o.list.rows or {}) + 1) + 3 + 1
	else
		rows = rows + 1
	end
	return left, rows
end

-- Dessine toute la page dans une fenêtre de `cols` x `rows`. Renvoie les lignes (exactement `rows`, chacune de `cols`
-- colonnes) et true si l'aperçu est affiché ; ou nil, la largeur et la hauteur qu'il faudrait (fenêtre trop petite).
--   o.b, o.edge  : les traits du cadre (assemble.BORDER_STYLES) et leur couleur (un code de couleur, ou "")
--   o.accent     : la couleur de l'onglet ouvert, du bouton actif et du réglage choisi ("#RRGGBB")
--   o.tabs       : les 4 noms de la barre d'onglets (le titre, puis les 3 onglets) ; o.tab : l'onglet ouvert (1 à 3)
--   o.preview    : { draw = function(largeur, hauteur) -> lignes ou nil, min_width, min_height } (il remplit la
--                  zone de droite), ou { lines, width } (centré dans la zone), ou nil
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
	local show_preview
	if preview and preview.draw then
		-- un aperçu qui remplit toute la zone de droite, s'il y tient
		show_preview = right >= (preview.min_width or 1) and rows - 2 >= (preview.min_height or 1)
	else
		show_preview = preview ~= nil and right >= preview.width + 2 and rows - 2 >= #preview.lines
	end
	if not show_preview then
		left, right = cols - 2, 0
	end
	local inner_rows = rows - 2
	-- le panneau de droite : l'aperçu centré dans sa zone (par sa largeur : les lignes d'un mois n'ont pas toutes la
	-- même longueur)
	local right_lines = {}
	if show_preview and preview.draw then
		local drawn = preview.draw(right, inner_rows)
		if drawn then
			for i = 1, inner_rows do
				right_lines[i] = fit(drawn[i] or "", right)
			end
		else
			show_preview = false -- l'aperçu dit qu'il ne tient pas : le panneau de gauche prend toute la largeur
			left, right = cols - 2, 0
		end
	elseif show_preview then
		local top = math.max(0, math.floor((inner_rows - #preview.lines) / 2))
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
	-- la barre d'onglets : l'onglet ouvert rempli de sa couleur, du trait du haut à celui du bas (des demi-blocs à la
	-- place des traits, au-dessus et en dessous de lui)
	local widths = M.tab_widths(left)
	local open = (o.tab or 1) + 1
	local cells, tops, bottoms = {}, {}, {}
	for i = 1, 4 do
		local name = centered(o.tabs[i] or "", widths[i])
		if i == open then
			cells[i] = filled(o.accent) .. name .. convert.RESET
			tops[i] = convert.fg(o.accent) .. string.rep(LOWER_HALF, widths[i]) .. convert.RESET
			bottoms[i] = convert.fg(o.accent) .. string.rep(UPPER_HALF, widths[i]) .. convert.RESET
		else
			cells[i] = name
			tops[i] = e(string.rep(b.h, widths[i]))
			bottoms[i] = e(string.rep(b.h, widths[i]))
		end
	end
	local out = {}
	out[1] = e(b.tl)
		.. table.concat(tops, e(b.t))
		.. e((show_preview and (b.t .. string.rep(b.h, right)) or "") .. b.tr)
	out[2] = with_right(1, e(b.v) .. table.concat(cells, e(b.v)))
	-- la jonction sous les onglets (├──┴──┤) : à droite, elle touche le trait qui sépare l'aperçu
	out[3] = e(b.l) .. table.concat(bottoms, e(b.b)) .. e(b.r) .. (show_preview and (right_lines[2] .. e(b.v)) or "")
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
