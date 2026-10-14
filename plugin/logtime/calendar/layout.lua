-- plugin/logtime/calendar/layout.lua : combien de mois la fenêtre peut afficher, lesquels, et comment les placer côte à côte.
-- Aucune dépendance à WezTerm : se teste avec un simple interpréteur Lua.
local M = {}

M.BLOCK_WIDTH = 65 -- largeur d'un mois (c'est assemble.WIDTH)
M.BLOCK_HEIGHT = 21 -- hauteur du plus grand mois : titre, en-tête, 6 semaines de 3 lignes, totaux
M.GAP = 3 -- espaces entre deux mois côte à côte
M.RESERVED_ROWS = 4 -- lignes prises par l'aide (1), une ligne vide, une ligne vide, la légende (1)
M.MAX_MONTHS = 12 -- nombre de mois affichés au maximum : par défaut autant que la fenêtre peut en contenir, jusqu'à une année entière

local function strip_ansi(text)
return (text:gsub("\27%[[%?%d;]*%a", ""))
end

-- Largeur visible d'une ligne : les codes de couleur ne comptent pas, un caractère accentué compte pour un.
function M.visible_width(text)
	local plain = strip_ansi(text)
	return utf8.len(plain) or #plain
end

-- Combien de mois afficher, et sur combien de colonnes, dans une fenêtre de cols x rows.
-- Jamais plus que ce qui tient en entier (un mois n'est jamais coupé), jamais moins de un.
-- La forme est la plus carrée possible, avec le moins de cases vides : 4 mois = 2 x 2 plutôt que 4 x 1.
-- block_width (facultatif) : la largeur d'un mois (M.BLOCK_WIDTH par défaut ; plus large avec un objectif).
-- Renvoie { count, columns, rows }.
function M.plan(cols, rows, max_months, block_width)
local width = tonumber(block_width) or M.BLOCK_WIDTH
local max = math.floor(tonumber(max_months) or M.MAX_MONTHS)
max = math.max(1, math.min(max, 12))
cols = tonumber(cols) or 0
rows = tonumber(rows) or 0
-- Si même un seul mois ne tient pas en entier dans la fenêtre, on n'en affiche qu'un (le mois seul, avec ses totaux) :
-- aligner plusieurs mois coupés ne servirait à rien.
if cols < width or rows < M.RESERVED_ROWS + M.BLOCK_HEIGHT then
return { count = 1, columns = 1, rows = 1 }
end
local fit_cols = math.max(1, math.floor((cols + M.GAP) / (width + M.GAP)))
local fit_rows = math.max(1, math.floor((rows - M.RESERVED_ROWS + 1) / (M.BLOCK_HEIGHT + 1)))
local count = math.min(max, fit_cols * fit_rows)

local best
for columns = 1, math.min(fit_cols, count) do
local lines = math.ceil(count / columns)
if lines <= fit_rows then
local empty = columns * lines - count
local skew = math.abs(columns - lines)
if not best or empty < best.empty or (empty == best.empty and skew < best.skew) or (empty == best.empty and skew == best.skew and columns > best.columns) then
best = { count = count, columns = columns, rows = lines, empty = empty, skew = skew }
end
end
end
return { count = best.count, columns = best.columns, rows = best.rows }
end

-- Les mois à afficher, du plus ancien au plus récent : { { year, month }, ... }.
-- anchor = "last" (par défaut) : le mois choisi est le dernier, les précédents le précèdent ; "first" : il est le premier.
function M.months(year, month, count, anchor)
local out = {}
local first = (anchor == "first") and 0 or -(count - 1)
local base = year * 12 + (month - 1)
for i = 0, count - 1 do
local index = base + first + i
out[#out + 1] = { year = index // 12, month = index % 12 + 1 }
end
return out
end

-- Place les mois côte à côte. blocks : liste de { lines = {...}, width = n } ; columns : combien par rangée ;
-- gap : espaces entre deux mois. Une ligne vide sépare deux rangées. Les lignes sont complétées par des espaces
-- (largeur visible) pour que les colonnes restent alignées, même quand un mois est plus court qu'un autre.
function M.arrange(blocks, columns, gap)
gap = gap or M.GAP
local out = {}
local index = 1
while index <= #blocks do
		local group = {}
		for _ = 1, columns do
			if blocks[index] then
				group[#group + 1] = blocks[index]
				index = index + 1
			end
		end
		local height = 0
		for _, block in ipairs(group) do
			height = math.max(height, #block.lines)
		end
		for i = 1, height do
			local parts = {}
			for k, block in ipairs(group) do
				local line = block.lines[i] or ""
				if k < #group then
					local pad = (block.width or M.BLOCK_WIDTH) - M.visible_width(line)
					if pad > 0 then
						line = line .. string.rep(" ", pad)
					end
				end
				parts[#parts + 1] = line
			end
			out[#out + 1] = table.concat(parts, string.rep(" ", gap))
		end
		if index <= #blocks then
			out[#out + 1] = ""
		end
	end
	return out
end

-- Centre un texte (une liste de lignes) dans une fenêtre de cols x rows : ajoute des espaces devant chaque ligne et des
-- lignes vides en haut. body_width est la largeur du calendrier lui-même (c'est lui qu'on centre ; l'aide ou les totaux,
-- parfois plus larges, dépassent un peu à droite). La marge est réduite si une ligne ne tenait plus dans la fenêtre :
-- centrer ne doit jamais couper quelque chose qui tenait avant. Une taille inconnue ne donne aucune marge.
function M.center(lines, body_width, cols, rows)
local widest = 0
for _, line in ipairs(lines) do
widest = math.max(widest, M.visible_width(line))
end
local left, top = 0, 0
cols, rows = tonumber(cols), tonumber(rows)
if cols then
left = math.floor((cols - body_width) / 2)
left = math.max(0, math.min(left, math.floor(cols - widest)))
end
if rows then
top = math.max(0, math.floor((rows - #lines) / 2))
end
local out = {}
for _ = 1, top do
out[#out + 1] = ""
end
local margin = string.rep(" ", left)
for _, line in ipairs(lines) do
out[#out + 1] = (line == "") and "" or (margin .. line)
end
return out
end

return M
