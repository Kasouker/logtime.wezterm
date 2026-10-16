-- tests/pages/test_settings_view.lua : teste pages/settings_view.lua (le dessin de la page F4, à la taille de la fenêtre).
-- Lancer :   lua5.4 tests/pages/test_settings_view.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]pages[/\\]test_settings_view%.lua$") or "."
local cache = {}
local function load_module(name)
	if not cache[name] then
		cache[name] = assert(loadfile(root .. "/plugin/logtime/" .. name .. ".lua"))(load_module)
	end
	return cache[name]
end
local view = load_module("pages/settings_view")
local assemble = load_module("calendar/assemble")
local palette = load_module("color/palette")
local convert = load_module("color/convert")
local layout = load_module("calendar/layout")

local passed, failed = 0, 0
local function check(name, got, want)
	if got == want then
		passed = passed + 1
	else
		failed = failed + 1
		print(
			string.format(
				"ÉCHEC  %s\n         attendu : %s\n         obtenu  : %s",
				name,
				tostring(want),
				tostring(got)
			)
		)
	end
end
local function strip(text)
	return (text:gsub("\27%[[%d;]*m", ""))
end
local GOLD = palette.COLORS[palette.DEFAULT_INDEX]
-- un texte à chercher tel quel dans un motif Lua (les codes de couleur contiennent des « [ »)
local function literal(text)
	return (text:gsub("[%[%]%%%.%-%+%*%?%^%$%(%)]", "%%%0"))
end

-- Une page de l'onglet Couleurs, avec ce qu'il faut changer.
local function colors_page(over)
	local o = {
		b = assemble.BORDER_STYLES.rounded,
		edge = "",
		accent = GOLD,
		tabs = { "Settings", "Colors", "Calendar", "General" },
		tab = 1,
		help = { "d: default // q: close // Tab or Shift+Tab: change tab", "Arrows or h j k l: choose // Enter: save" },
		button = { text = "y: use your theme colors", active = false },
		colors_tab = {
			colors = palette.COLORS,
			index = 3,
			gradient_title = "Gradient color:",
			gradient_preview = "Preview: 0h ████ 24h",
			choice = "Choice: 3 Gold (#C9AB6B)",
			saved = "Saved color: #C9AB6B",
		},
		message = "",
	}
	for k, v in pairs(over or {}) do
		o[k] = v
	end
	return o
end
local MONTH = { lines = { "October 2026", "Mo Tu We Th Fr Sa Su", "      1  2  3  4  5" }, width = 20 }

-- ---- la taille : exactement la fenêtre, à toutes les tailles
local sizes_ok = true
for _, size in ipairs({ { 80, 30 }, { 120, 40 }, { 200, 60 }, { 65, 30 }, { 300, 90 } }) do
	for _, preview in ipairs({ false, true }) do
		local lines = view.draw(colors_page({ preview = preview and MONTH or nil }), size[1], size[2])
		if not lines or #lines ~= size[2] then
			sizes_ok = size[1] .. "x" .. size[2] .. " : " .. tostring(lines and #lines)
		else
			for i, line in ipairs(lines) do
				if layout.visible_width(line) ~= size[1] then
					sizes_ok = size[1] .. "x" .. size[2] .. " ligne " .. i .. " : " .. layout.visible_width(line)
				end
			end
		end
	end
end
check("toujours exactement la taille de la fenêtre (lignes et colonnes), avec ou sans aperçu", sizes_ok, true)

-- ---- le cadre et ses jonctions (120 x 34, avec l'aperçu à droite)
local lines, shown = view.draw(colors_page({ preview = MONTH }), 120, 34)
local plain = {}
for i, line in ipairs(lines) do
	plain[i] = strip(line)
end
check("120 x 34 : l'aperçu est à droite", shown, true)
check(
	"le haut : coins, et une jonction ┬ entre chaque onglet et avant l'aperçu",
	select(2, plain[1]:gsub("┬", "")),
	4
)
check("le haut commence par ╭ et finit par ╮", plain[1]:sub(1, #"╭") .. plain[1]:sub(-#"╮"), "╭╮")
check(
	"la barre d'onglets : les 4 noms",
	plain[2]:find("Settings", 1, true) and plain[2]:find("General", 1, true) and true,
	true
)
check("sous les onglets : ├ … ┴ … ┤ (les onglets fermés par le bas)", plain[3]:sub(1, #"├"), "├")
check("sous les onglets : 3 jonctions ┴", select(2, plain[3]:gsub("┴", "")), 3)
check("le bas : une jonction ┴ sous la séparation avec l'aperçu", select(2, plain[34]:gsub("┴", "")), 1)
check("le bas commence par ╰ et finit par ╯", plain[34]:sub(1, #"╰") .. plain[34]:sub(-#"╯"), "╰╯")
local sep_count = 0
for i = 4, 33 do
	if plain[i]:sub(1, #"├") == "├" then
		sep_count = sep_count + 1
	end
end
check("une séparation entre l'aide et les couleurs", sep_count, 1)

-- ---- les onglets : des cases de largeurs presque égales ; l'onglet ouvert sur fond coloré
local widths = view.tab_widths(57)
check("largeurs des onglets : 4 cases + 3 traits = la largeur", widths[1] + widths[2] + widths[3] + widths[4] + 3, 57)
check("largeurs des onglets : au plus 1 colonne d'écart", widths[1] - widths[4] <= 1, true)
local accent_style = convert.bg(GOLD) .. convert.fg(convert.contrast(GOLD))
check(
	"l'onglet ouvert (Colors) sur le fond de l'accent",
	lines[2]:find(literal(accent_style) .. "[^\27]*Colors") ~= nil,
	true
)
check("les autres onglets : pas de fond", lines[2]:find(literal(accent_style) .. "[^\27]*Calendar"), nil)
check("le titre (Settings) : pas de fond", lines[2]:find(literal(accent_style) .. "[^\27]*Settings"), nil)
local general = view.draw(colors_page({ tab = 3, colors_tab = false, button = false, list = { " a" } }), 120, 34)
check("l'onglet ouvert suit (General)", general[2]:find(literal(accent_style) .. "[^\27]*General") ~= nil, true)
check("plus de crochets autour de l'onglet ouvert", plain[2]:find("[", 1, true), nil)

-- ---- les soulignés : l'aide, le titre du dégradé, le choix et la couleur enregistrée (comme la maquette)
local joined = table.concat(lines, "\n")
local U = view.UNDERLINE
check("l'aide (1re ligne) soulignée", joined:find(U .. "d: default // q: close", 1, true) ~= nil, true)
check("l'aide (2e ligne) soulignée", joined:find(U .. "Arrows or h j k l", 1, true) ~= nil, true)
check("le titre du dégradé souligné", joined:find(U .. "Gradient color:", 1, true) ~= nil, true)
check("le choix souligné", joined:find(U .. "Choice: 3 Gold (#C9AB6B)", 1, true) ~= nil, true)
check(
	"la couleur enregistrée soulignée, à part",
	joined:find(" // " .. U .. "Saved color: #C9AB6B", 1, true) ~= nil,
	true
)
check("le « // » entre les deux n'est pas souligné", joined:find(view.UNDERLINE_OFF .. " // ", 1, true) ~= nil, true)
check("le bouton n'est pas souligné", joined:find(U .. "y: use", 1, true), nil)

-- ---- le bouton y : encadré ; coloré seulement quand c'est actif
local button_row
for i, line in ipairs(plain) do
	if line:find("y: use your theme colors", 1, true) then
		button_row = i
	end
end
check("le bouton : son cadre au-dessus", plain[button_row - 1]:find("│ ╭─", 1, true) ~= nil, true)
check("le bouton : son cadre en dessous", plain[button_row + 1]:find("│ ╰─", 1, true) ~= nil, true)
check("le bouton : pas coloré quand ce n'est pas actif", lines[button_row]:find(convert.bg(GOLD), 1, true), nil)
local active =
	view.draw(colors_page({ button = { text = "y: use your theme colors", active = true, note = "n: back" } }), 120, 34)
check(
	"le bouton actif : son texte sur le fond de l'accent",
	active[button_row]:find(accent_style .. " y: use your theme colors ", 1, true) ~= nil,
	true
)
check(
	"le bouton actif : son cadre dans la couleur de l'accent",
	active[button_row - 1]:find(convert.fg(GOLD) .. "╭", 1, true) ~= nil,
	true
)
check("la note à droite du bouton", strip(active[button_row]):find("│  n: back", 1, true) ~= nil, true)

-- ---- l'aperçu du dégradé, encadré, à droite de son titre
local gradient_row
for i, line in ipairs(plain) do
	if line:find("Gradient color:", 1, true) then
		gradient_row = i
	end
end
check(
	"l'aperçu du dégradé : dans un cadre",
	plain[gradient_row]:find("Gradient color:  │ Preview: 0h", 1, true) ~= nil,
	true
)
check("son cadre au-dessus", plain[gradient_row - 1]:find("╭─", 1, true) ~= nil, true)
check("son cadre en dessous", plain[gradient_row + 1]:find("╰─", 1, true) ~= nil, true)

-- ---- la grille : 16 cases colorées, sans texte ; la case choisie dans un cadre blanc ou noir
local all_colors = true
for _, color in ipairs(palette.COLORS) do
	if not joined:find(convert.bg(color), 1, true) then
		all_colors = false
	end
end
check("les 16 couleurs sont dessinées", all_colors, true)
check("aucun nom de couleur dans la grille", joined:find("Red", 1, true) or joined:find("Teal", 1, true), nil)
local function swatch_size(cols, rows)
	local g = view.grid(palette.COLORS, 1, cols, rows)
	local first = g[1]
	local w = 0
	for run in first:gmatch(convert.bg(palette.COLORS[2]):gsub("[%[%]%%%.%-%+%*%?%^%$%(%)]", "%%%0") .. "[^\27]*") do
		w = utf8.len(strip(run))
	end
	local h = 0
	for _, line in ipairs(g) do
		if line:find(convert.bg(palette.COLORS[2]), 1, true) then
			h = h + 1
		else
			break
		end
	end
	return w, h, #g
end
local w1, h1, n1 = swatch_size(57, 20)
local w2, h2, n2 = swatch_size(100, 40)
check("la grille rend exactement la hauteur demandée", n1 .. " " .. n2, "20 40")
check("les cases grandissent en largeur avec la place", w2 > w1, true)
check("les cases grandissent en hauteur avec la place", h2 > h1, true)
check("une case : au moins 2 lignes, même serrée", select(2, swatch_size(57, 1)) >= view.MIN_SWATCH_HEIGHT, true)
local dark = view.swatch("#202020", true, 8, 3)
local light = view.swatch("#F0F0F0", true, 8, 3)
check(
	"case choisie sombre : un cadre blanc (le blanc adouci du plugin)",
	dark[1]:find(convert.fg(convert.contrast("#202020")) .. "┌──────┐", 1, true) ~= nil
		and convert.contrast("#202020") == "#ECE6D9",
	true
)
check(
	"case choisie claire : un cadre noir (le noir adouci du plugin)",
	light[1]:find(convert.fg(convert.contrast("#F0F0F0")) .. "┌──────┐", 1, true) ~= nil
		and convert.contrast("#F0F0F0") == "#17191F",
	true
)
check("case choisie : le cadre fait le tour (côtés)", strip(dark[2]), "│      │")
check("case choisie : le bas du cadre", strip(dark[3]), "└──────┘")
check("case non choisie : seulement la couleur", strip(view.swatch("#202020", false, 8, 3)[2]), "        ")
local frames = select(2, joined:gsub("┌", ""))
check("une seule case choisie", frames, 1)

-- ---- l'aperçu à droite : seulement s'il tient ; sinon le panneau prend toute la largeur
local narrow_lines, narrow_shown = view.draw(colors_page({ preview = MONTH }), 70, 34)
check("70 colonnes : pas la place de l'aperçu", narrow_shown, false)
check(
	"70 colonnes : le haut sans la jonction de l'aperçu (3 entre les onglets)",
	select(2, strip(narrow_lines[1]):gsub("┬", "")),
	3
)
local tall_preview = { lines = {}, width = 20 }
for i = 1, 50 do
	tall_preview.lines[i] = "x" .. i
end
check(
	"un aperçu plus haut que la fenêtre : jamais coupé, pas affiché",
	select(2, view.draw(colors_page({ preview = tall_preview }), 200, 40)),
	false
)
check("sans aperçu (pas d'heures) : toute la largeur", select(2, view.draw(colors_page(), 200, 40)), false)
-- l'aperçu est centré dans sa zone (horizontalement et verticalement)
local month_row
for i, line in ipairs(plain) do
	if line:find("October 2026", 1, true) then
		month_row = i
	end
end
check("aperçu centré verticalement", math.abs(month_row - (34 / 2)) <= 3, true)
local right_start = utf8.len(plain[month_row]:match("^(.-)October")) -- les colonnes avant le titre du mois
check("aperçu centré horizontalement (dans la zone de droite)", right_start > 120 / 2, true)
local wide = view.draw(colors_page({ preview = MONTH }), 200, 34)
check(
	"200 colonnes : le panneau de gauche prend 42 % de la largeur",
	utf8.len(strip(wide[4]):match("^│([^│]*)")),
	math.floor((200 - 3) * view.LEFT_SHARE)
)
check(
	"120 colonnes : 42 % (49) serait moins que le minimum : le panneau garde son minimum",
	utf8.len(plain[4]:match("^│([^│]*)")),
	view.minimum(colors_page())
)

-- ---- un onglet de réglages : ses lignes à la place des couleurs
local list = view.draw(
	colors_page({
		tab = 2,
		button = false,
		colors_tab = false,
		list = { " Calendar settings", "", " ▸ Max months   ◀ 12" },
	}),
	120,
	34
)
local list_text = strip(table.concat(list, "\n"))
check("onglet de réglages : la liste est affichée", list_text:find("▸ Max months", 1, true) ~= nil, true)
check(
	"onglet de réglages : pas de grille de couleurs",
	table.concat(list, "\n"):find(convert.bg(palette.COLORS[1]), 1, true),
	nil
)
check("onglet de réglages : pas de bouton", list_text:find("y: use", 1, true), nil)

-- ---- le message, en bas du panneau
local with_message = view.draw(colors_page({ message = " ✓ Saved." }), 120, 34)
check("le message : sur la dernière ligne du panneau", strip(with_message[33]):find("│ ✓ Saved.", 1, true), 1)

-- ---- trop petit : rien de dessiné, la taille qu'il faudrait
local min_left, min_rows = view.minimum(colors_page())
local none, need_cols, need_rows = view.draw(colors_page(), min_left + 1, 60)
check("trop étroit : rien n'est dessiné", none, nil)
check("trop étroit : la largeur qu'il faudrait (le panneau + le cadre)", need_cols, min_left + 2)
check("trop bas : rien", view.draw(colors_page(), 200, min_rows - 1), nil)
check("trop bas : la hauteur qu'il faudrait", select(3, view.draw(colors_page(), 200, min_rows - 1)), min_rows)
check("pile à la taille minimum : dessiné", view.draw(colors_page(), min_left + 2, min_rows) ~= nil, true)
check("le minimum du panneau : jamais moins que MIN_LEFT", min_left >= view.MIN_LEFT, true)
local wide_help = colors_page({ help = { string.rep("x", 70) } })
check("une aide plus longue élargit le minimum", view.minimum(wide_help), 72)
local wide_list = colors_page({ colors_tab = false, button = false, list = { string.rep("y", 66) } })
check("une liste plus longue élargit le minimum", view.minimum(wide_list), 67)

-- ---- les traits du cadre dans leur couleur
local colored = view.draw(colors_page({ edge = convert.fg("#3366CC"), b = assemble.BORDER_STYLES.double }), 120, 34)
check("le cadre : le style choisi (double)", strip(colored[1]):sub(1, #"╔"), "╔")
check("le cadre : la couleur choisie", colored[1]:find(convert.fg("#3366CC") .. "╔", 1, true), 1)

-- ---- une ligne trop longue n'est jamais plus large que son panneau (coupée)
local cut_lines = view.draw(colors_page({ message = " " .. string.rep("z", 300) }), 120, 34)
check("une ligne trop longue est coupée à la largeur du panneau", layout.visible_width(cut_lines[33]), 120)

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
