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
-- un texte à chercher tel quel dans un motif Lua (les codes de couleur contiennent des « [ »)
local function literal(text)
	return (text:gsub("[%[%]%%%.%-%+%*%?%^%$%(%)]", "%%%0"))
end
local GOLD = palette.COLORS[palette.DEFAULT_INDEX]
local U, U_OFF = view.UNDERLINE, view.UNDERLINE_OFF
local FILLED = convert.bg(GOLD) .. convert.fg(convert.contrast(GOLD))

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
local function list_page(over)
	local o = colors_page({
		tab = 2,
		button = false,
		colors_tab = false,
		help = {
			"d: default // q: close // Tab or Shift+Tab: change tab",
			"↑↓ or j k: choose // ←→ or h l: change",
		},
		list = {
			rows = {
				{ name = "Max months", value = "◀ 12" },
				{ name = "Anchor", value = "◀ last ▶" },
				{ name = "Week starts on", value = "◀ Monday ▶" },
			},
			selected = 2,
			hint = "Where the selected month goes.",
		},
	})
	for k, v in pairs(over or {}) do
		o[k] = v
	end
	return o
end
local MONTH = { lines = { "October 2026", "Mo Tu We Th Fr Sa Su", "      1  2  3  4  5" }, width = 20 }

-- ---- la taille : exactement la fenêtre, à toutes les tailles, dans les deux sortes d'onglets
local sizes_ok = true
for _, make in ipairs({ colors_page, list_page }) do
	for _, size in ipairs({ { 80, 42 }, { 120, 40 }, { 200, 60 }, { 70, 42 }, { 300, 90 } }) do
		for _, preview in ipairs({ false, true }) do
			local lines = view.draw(make({ preview = preview and MONTH or nil }), size[1], size[2])
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
end
check("toujours exactement la taille de la fenêtre (lignes et colonnes), avec ou sans aperçu", sizes_ok, true)

-- ---- le cadre et ses jonctions (120 x 42, avec l'aperçu à droite)
local lines, shown = view.draw(colors_page({ preview = MONTH }), 120, 42)
local plain = {}
for i, line in ipairs(lines) do
	plain[i] = strip(line)
end
check("120 x 42 : l'aperçu est à droite", shown, true)
check("le haut commence par ╭ et finit par ╮", plain[1]:sub(1, #"╭") .. plain[1]:sub(-#"╮"), "╭╮")
check("le haut : les jonctions ┬ entre les onglets et avant l'aperçu", select(2, plain[1]:gsub("┬", "")), 4)
check(
	"sous les onglets : ├ … ┤, avec les jonctions ┴",
	plain[3]:sub(1, #"├") .. select(2, plain[3]:gsub("┴", "")),
	"├3"
)
check("le bas : une jonction ┴ sous la séparation avec l'aperçu", select(2, plain[42]:gsub("┴", "")), 1)
check("le bas commence par ╰ et finit par ╯", plain[42]:sub(1, #"╰") .. plain[42]:sub(-#"╯"), "╰╯")

-- ---- les onglets : l'onglet ouvert rempli de sa couleur, du trait du haut à celui du bas
local widths = view.tab_widths(57)
check("largeurs des onglets : 4 cases + 3 traits = la largeur", widths[1] + widths[2] + widths[3] + widths[4] + 3, 57)
check("largeurs des onglets : au plus 1 colonne d'écart", widths[1] - widths[4] <= 1, true)
check(
	"l'onglet ouvert (Colors) sur le fond de l'accent",
	lines[2]:find(literal(FILLED) .. "[^\27]*Colors") ~= nil,
	true
)
check("les autres onglets : pas de fond", lines[2]:find(literal(FILLED) .. "[^\27]*Calendar"), nil)
check(
	"au-dessus de l'onglet ouvert : des demi-blocs de sa couleur (à la place du trait)",
	lines[1]:find(convert.fg(GOLD) .. "▄▄▄▄", 1, true) ~= nil,
	true
)
check(
	"en dessous de l'onglet ouvert : des demi-blocs de sa couleur",
	lines[3]:find(convert.fg(GOLD) .. "▀▀▀▀", 1, true) ~= nil,
	true
)
check(
	"les demi-blocs sont au-dessus de l'onglet ouvert (après le 1er ┬, pas sur le titre)",
	plain[1]:find("▄", 1, true) > plain[1]:find("┬", 1, true),
	true
)
local general = view.draw(list_page({ tab = 3 }), 120, 42)
check("l'onglet ouvert suit (General)", general[2]:find(literal(FILLED) .. "[^\27]*General") ~= nil, true)
check("plus de crochets autour de l'onglet ouvert", plain[2]:find("[", 1, true), nil)

-- ---- les lignes divisées en parts égales (« a // b // c »)
check("parts : les morceaux d'une ligne d'aide", table.concat(view.parts("a: b // c d //e"), "|"), "a: b|c d|e")
check("parts : sans « // », un seul morceau", table.concat(view.parts("seul"), "|"), "seul")
check(
	"spread : 3 parts égales de 10 colonnes, « // » entre elles",
	view.spread({ "aa", "bb", "cc" }, 34, false),
	"    aa    //    bb    //    cc    "
)
check("spread : toujours la largeur demandée", utf8.len(view.spread({ "aa", "bbbb" }, 31, false)), 31)
check(
	"spread : seul le texte est souligné (pas les espaces ni le « // »)",
	view.spread({ "aa", "bb" }, 22, true),
	"    " .. U .. "aa" .. U_OFF .. "    //    " .. U .. "bb" .. U_OFF .. "    "
)
local tight = view.spread({ string.rep("x", 20), "y" }, 30, false)
check(
	"spread : un morceau trop long pour sa part : espacement régulier, rien de coupé",
	strip(tight):find(string.rep("x", 20), 1, true) ~= nil and strip(tight):find("y", 1, true) ~= nil,
	true
)
check("spread : rien", view.spread({}, 5, false), "     ")
-- dans la page : l'aide divisée en 3 puis en 2, soulignée morceau par morceau
local help_line = lines[5]
check(
	"l'aide (1re ligne) : « d: default » souligné seul",
	help_line:find(U .. "d: default" .. U_OFF, 1, true) ~= nil,
	true
)
check(
	"l'aide (1re ligne) : « q: close » souligné seul",
	help_line:find(U .. "q: close" .. U_OFF, 1, true) ~= nil,
	true
)
check(
	"l'aide (1re ligne) : le dernier morceau souligné seul",
	help_line:find(U .. "Tab or Shift+Tab: change tab" .. U_OFF, 1, true) ~= nil,
	true
)
check(
	"l'aide : le « // » n'est pas souligné",
	help_line:find(U .. "//", 1, true) == nil and help_line:find("//" .. U_OFF, 1, true) == nil,
	true
)
check("l'aide (1re ligne) : deux « // »", select(2, plain[5]:gsub("//", "")), 2)
check("l'aide (2e ligne) : un « // »", select(2, plain[7]:gsub("//", "")), 1)
check("l'aide n'est plus collée à gauche (centrée dans sa part)", plain[5]:find("d: default", 1, true) > 4, true)
-- de l'air : une ligne vide sous les onglets, entre les deux lignes d'aide, et avant le bouton
local function empty_left(i)
	return plain[i]:match("^│( *)│") ~= nil
end
check("une ligne vide sous les onglets", empty_left(4), true)
check("une ligne vide entre les deux lignes d'aide", empty_left(6), true)
check("une ligne vide avant le bouton", empty_left(8) and plain[9]:find("╭─", 1, true) ~= nil, true)
check(
	"spread : un morceau qui remplirait toute sa part n'y est pas collé (au moins une colonne d'air de chaque côté)",
	view.spread({ "aaaa", "bbbb" }, 10, false):find("//bbbb", 1, true),
	nil
)
check(
	"spread : sans la place pour des parts égales, la ligne reste centrée",
	(function()
		-- 3 morceaux de 20 + 1 + 1, des « // » : il reste 2 colonnes à répartir des deux côtés
		local line = view.spread({ string.rep("x", 20), "y", "z" }, 40, false)
		local left = #line:match("^( *)")
		local right = #line:match("( *)$")
		return math.abs(left - right) <= 1
	end)(),
	true
)

-- ---- le bouton y : encadré ; actif, rempli de sa couleur sur 3 lignes
local button_row
for i, line in ipairs(plain) do
	if line:find("y: use your theme colors", 1, true) then
		button_row = i
	end
end
check("le bouton : son cadre au-dessus", plain[button_row - 1]:find("│ ╭─", 1, true) ~= nil, true)
check("le bouton : son cadre en dessous", plain[button_row + 1]:find("│ ╰─", 1, true) ~= nil, true)
check("le bouton inactif : pas de couleur de fond", lines[button_row]:find(convert.bg(GOLD), 1, true), nil)
local active =
	view.draw(colors_page({ button = { text = "y: use your theme colors", active = true, note = "n: back" } }), 120, 42)
check(
	"le bouton actif : son texte sur le fond de l'accent",
	active[button_row]:find(FILLED .. "  y: use your theme colors  ", 1, true) ~= nil,
	true
)
check(
	"le bouton actif : des demi-blocs de sa couleur au-dessus",
	active[button_row - 1]:find(convert.fg(GOLD) .. "▄▄▄", 1, true) ~= nil,
	true
)
check(
	"le bouton actif : et en dessous",
	active[button_row + 1]:find(convert.fg(GOLD) .. "▀▀▀", 1, true) ~= nil,
	true
)
check("le bouton actif : plus de traits", strip(active[button_row - 1]):find("╭", 1, true), nil)
check(
	"le bouton actif : même largeur que le bouton inactif",
	select(2, strip(active[button_row - 1]):gsub("▄", "")), -- (« ▄+ » ne marche pas : le + ne porterait que sur le dernier octet)
	select(2, plain[button_row - 1]:gsub("─", "")) + 2 -- les traits, plus les deux coins
)
check("la note à droite du bouton", strip(active[button_row]):find("colors    n: back", 1, true) ~= nil, true)

-- ---- l'aperçu du dégradé : collé au bord droit ; le titre souligné à gauche
local gradient_row
for i, line in ipairs(plain) do
	if line:find("Gradient color:", 1, true) then
		gradient_row = i
	end
end
check(
	"l'aperçu du dégradé : dans un cadre",
	plain[gradient_row]:find("│ Preview: 0h ████ 24h │", 1, true) ~= nil,
	true
)
local left_width = utf8.len(plain[4]:match("^│([^│]*)"))
local gradient_left =
	plain[gradient_row]:sub(utf8.offset(plain[gradient_row], 2), utf8.offset(plain[gradient_row], left_width + 2) - 1)
check(
	"l'aperçu du dégradé : collé au bord droit du panneau (une colonne de marge)",
	gradient_left:sub(-#"24h │ "),
	"24h │ "
)
check("l'aperçu n'est plus juste après le titre", plain[gradient_row]:find("Gradient color:  │", 1, true), nil)
local separator_row
for i = 4, #plain do
	if plain[i]:sub(1, #"├") == "├" then
		separator_row = separator_row or i
	end
end
check(
	"« Gradient color » descend : 2 lignes vides sous la séparation, puis le cadre de l'aperçu",
	gradient_row - separator_row,
	4 -- 2 lignes vides, puis le haut du cadre de l'aperçu
)
check(
	"le titre du dégradé souligné",
	lines[gradient_row]:find(U .. "Gradient color:" .. U_OFF, 1, true) ~= nil,
	true
)

-- ---- la grille : des cases de taille raisonnable, réparties ; le cadre AUTOUR de la case choisie
local joined = table.concat(lines, "\n")
local all_colors = true
for _, color in ipairs(palette.COLORS) do
	if not joined:find(convert.bg(color), 1, true) then
		all_colors = false
	end
end
check("les 16 couleurs sont dessinées", all_colors, true)
-- la case d'une couleur dans une grille : sa première ligne, sa hauteur, sa largeur
local function swatch_box(g, color)
	local bg = convert.bg(color)
	local top, height, width = nil, 0, 0
	for y, line in ipairs(g) do
		local count = select(2, line:gsub(literal(bg) .. " ", ""))
		if count > 0 then
			top = top or y
			height = height + 1
			width = count
		end
	end
	return top, height, width
end
local small = view.grid(palette.COLORS, 1, 60, 20)
local big = view.grid(palette.COLORS, 1, 160, 60)
check("la grille rend exactement la hauteur demandée", #small .. " " .. #big, "20 60")
local _, h_small = swatch_box(small, palette.COLORS[2])
local _, h_big, w_big = swatch_box(big, palette.COLORS[2])
check("une case : 2 lignes de haut", h_small, view.SWATCH_HEIGHT)
check("une grande fenêtre : les cases ne grossissent pas (2 lignes)", h_big, view.SWATCH_HEIGHT)
check("une grande fenêtre : au plus 10 colonnes de large", w_big, view.SWATCH_WIDTH)
local function row_distance(g)
	return select(1, swatch_box(g, palette.COLORS[5])) - select(1, swatch_box(g, palette.COLORS[1]))
end
check("c'est l'espace entre les cases qui grandit", row_distance(big) > row_distance(small), true)
-- le cadre de la case choisie : autour d'elle, pas dedans
local framed = view.grid(palette.COLORS, 6, 60, 20)
local top6, h6, w6 = swatch_box(framed, palette.COLORS[6])
check(
	"la case choisie garde toute sa couleur (le cadre n'est pas dedans)",
	h6 .. "x" .. w6,
	view.SWATCH_HEIGHT .. "x" .. view.SWATCH_WIDTH
)
check(
	"le cadre : la ligne au-dessus de la case",
	strip(framed[top6 - 1]):find("┌" .. string.rep("─", view.SWATCH_WIDTH) .. "┐", 1, true) ~= nil,
	true
)
check(
	"le cadre : la ligne en dessous de la case",
	strip(framed[top6 + view.SWATCH_HEIGHT]):find("└" .. string.rep("─", view.SWATCH_WIDTH) .. "┘", 1, true)
		~= nil,
	true
)
check(
	"le cadre : les côtés, juste à gauche et à droite de la couleur",
	framed[top6]:find("│" .. convert.RESET .. convert.bg(palette.COLORS[6]), 1, true) ~= nil
		and select(2, strip(framed[top6]):gsub("│", "")) == 2,
	true
)
check(
	"le cadre : sa couleur (clair, visible autour de toutes les couleurs)",
	framed[top6 - 1]:find(convert.fg(view.FRAME_COLOR) .. "┌", 1, true) ~= nil,
	true
)
check("une seule case encadrée", select(2, table.concat(framed, "\n"):gsub("┌", "")), 1)
check("dans la page : une seule case encadrée", select(2, joined:gsub("┌", "")), 1)

-- ---- le choix et la couleur enregistrée : divisés en 2, chacun souligné
local choice_line
for i, line in ipairs(plain) do
	if line:find("Choice:", 1, true) then
		choice_line = i
	end
end
check(
	"le choix souligné seul",
	lines[choice_line]:find(U .. "Choice: 3 Gold (#C9AB6B)" .. U_OFF, 1, true) ~= nil,
	true
)
check(
	"la couleur enregistrée soulignée seule",
	lines[choice_line]:find(U .. "Saved color: #C9AB6B" .. U_OFF, 1, true) ~= nil,
	true
)
check(
	"un « // » entre les deux, pas souligné",
	select(2, plain[choice_line]:gsub("//", "")) == 1 and lines[choice_line]:find(U .. "//", 1, true) == nil,
	true
)
check(
	"le choix n'est plus collé à gauche (centré dans sa moitié)",
	plain[choice_line]:find("Choice", 1, true) > 4,
	true
)
check(
	"« Choice » remonte : 2 lignes vides sous lui, puis l'avertissement, puis le message (et le bas du cadre)",
	#plain - choice_line,
	5 -- 2 lignes vides, l'avertissement, le message, le bas du cadre
)

-- ---- l'aperçu à droite : seulement s'il tient ; sinon le panneau prend toute la largeur
local narrow_lines, narrow_shown = view.draw(colors_page({ preview = MONTH }), 70, 42)
check("70 colonnes : pas la place de l'aperçu", narrow_shown, false)
check("70 colonnes : le haut sans la jonction de l'aperçu", select(2, strip(narrow_lines[1]):gsub("┬", "")), 3)
local tall_preview = { lines = {}, width = 20 }
for i = 1, 50 do
	tall_preview.lines[i] = "x" .. i
end
check(
	"un aperçu plus haut que la fenêtre : jamais coupé, pas affiché",
	select(2, view.draw(colors_page({ preview = tall_preview }), 200, 42)),
	false
)
check("sans aperçu (pas d'heures) : toute la largeur", select(2, view.draw(colors_page(), 200, 42)), false)
local month_row
for i, line in ipairs(plain) do
	if line:find("October 2026", 1, true) then
		month_row = i
	end
end
check("aperçu centré verticalement", math.abs(month_row - (42 / 2)) <= 3, true)
check("aperçu dans la zone de droite", utf8.len(plain[month_row]:match("^(.-)October")) > 60, true)
local wide = view.draw(colors_page({ preview = MONTH }), 200, 42)
check(
	"200 colonnes : le panneau de gauche prend 42 % de la largeur",
	utf8.len(strip(wide[4]):match("^│([^│]*)")),
	math.floor((200 - 3) * view.LEFT_SHARE)
)

-- ---- un onglet de réglages : répartis sur la hauteur, la valeur à droite, le choisi rempli, l'explication encadrée
local lp = view.draw(list_page(), 120, 42)
local lp_plain = {}
for i, line in ipairs(lp) do
	lp_plain[i] = strip(line)
end
local function row_of(name)
	for i, line in ipairs(lp_plain) do
		if line:find(name, 1, true) then
			return i
		end
	end
end
local r1, r2, r3 = row_of("Max months"), row_of("Anchor"), row_of("Week starts on")
check("réglages : dans l'ordre", r1 < r2 and r2 < r3, true)
check("réglages : répartis (pas collés les uns aux autres)", r2 - r1 > 2 and r3 - r2 > 2, true)
check("réglages : espacés régulièrement", math.abs((r2 - r1) - (r3 - r2)) <= 1, true)
check("réglages : le nom à gauche (3 colonnes de marge)", lp_plain[r1]:find("│   Max months", 1, true), 1)
check(
	"réglages : la valeur collée à droite (3 colonnes de marge)",
	lp_plain[r1]:match("◀ 12   │"),
	"◀ 12   │"
)
check("le réglage choisi : rempli de la couleur d'accent", lp[r2]:find(FILLED, 1, true) ~= nil, true)
check(
	"le réglage choisi : des demi-blocs au-dessus",
	lp[r2 - 1]:find(convert.fg(GOLD) .. "▄▄▄", 1, true) ~= nil,
	true
)
check("le réglage choisi : et en dessous", lp[r2 + 1]:find(convert.fg(GOLD) .. "▀▀▀", 1, true) ~= nil, true)
check("les autres réglages : pas remplis", lp[r1]:find(convert.bg(GOLD), 1, true), nil)
check("plus de « ▸ »", table.concat(lp_plain, "\n"):find("▸", 1, true), nil)
check(
	"une valeur avec ses couleurs (l'aperçu du trait) ne coupe pas le fond de la ligne choisie",
	view.settings_rows(
		{ { name = "Color", value = convert.fg("#3366CC") .. "╭─╮" .. convert.RESET .. " ▶" } },
		1,
		GOLD,
		40,
		5
	)[3]
		:find(convert.RESET .. FILLED .. " ▶", 1, true) ~= nil,
	true
)
local hint_row = row_of("Where the selected month goes.")
check(
	"l'explication : encadrée",
	lp_plain[hint_row - 1]:find("╭─", 1, true) ~= nil and lp_plain[hint_row + 1]:find("╰─", 1, true) ~= nil,
	true
)
check("l'explication : en bas (sous les réglages)", hint_row > r3, true)
check(
	"onglet de réglages : pas de grille de couleurs",
	table.concat(lp, "\n"):find(convert.bg(palette.COLORS[1]), 1, true),
	nil
)
check("onglet de réglages : pas de bouton", table.concat(lp_plain, "\n"):find("y: use", 1, true), nil)
check("settings_rows : la hauteur demandée, même sans réglages", #view.settings_rows({}, 1, GOLD, 30, 7), 7)
local packed = view.settings_rows({ { name = "a", value = "1" }, { name = "b", value = "2" } }, 1, GOLD, 30, 2)
check(
	"settings_rows : sans place autour, pas de demi-blocs (rien ne déborde)",
	#packed == 2 and table.concat(packed):find("▄", 1, true) == nil,
	true
)

-- ---- des blocs titrés (l'onglet Calendrier : Calendrier, puis Aperçu)
local SECTIONED = {
	{ name = "Max months", value = "◀ 12", heading = "Calendar", rule = false },
	{ name = "Anchor", value = "◀ last ▶" },
	{ name = "Timeline", value = "◀ yes ▶", heading = "Preview", rule = true },
}
check("blocs : les lignes en plus (titre et ligne vide ; trait et ligne vide)", view.section_lines(SECTIONED), 6)
check("blocs : sans titres, rien en plus", view.section_lines({ { name = "a", value = "1" } }), 0)
local sec = view.settings_rows(SECTIONED, 3, GOLD, 40, 15)
local sec_plain = {}
for i, line in ipairs(sec) do
	sec_plain[i] = strip(line)
end
local function sec_row(text)
	for i, line in ipairs(sec_plain) do
		if line:find(text, 1, true) then
			return i
		end
	end
end
check("blocs : la hauteur demandée", #sec, 15)
check("blocs : le titre souligné", sec[sec_row("Calendar")]:find(view.underline("Calendar"), 1, true) ~= nil, true)
check("blocs : le titre, une ligne vide, puis le premier réglage", sec_row("Max months") - sec_row("Calendar"), 2)
check(
	"blocs : le trait avant le second bloc, une ligne vide, puis son titre",
	sec_row("Preview") - sec_row("──"),
	2
)
local rule_lines = 0
for _, line in ipairs(sec_plain) do
	if line:find("──", 1, true) then
		rule_lines = rule_lines + 1
	end
end
check("blocs : un seul trait (pas au-dessus du premier bloc)", rule_lines, 1)
check("blocs : le trait sous les réglages du premier bloc", sec_row("──") > sec_row("Anchor"), true)
check(
	"blocs : le réglage choisi sous un titre a son demi-bloc au-dessus (sur la ligne vide, pas sur le titre)",
	sec[sec_row("Timeline") - 1]:find(convert.fg(GOLD) .. "▄", 1, true) ~= nil
		and sec_plain[sec_row("Preview")]:find("Preview", 1, true) ~= nil,
	true
)
local tight_sec = view.settings_rows(SECTIONED, 3, GOLD, 40, 3 + view.section_lines(SECTIONED))
check(
	"blocs : sans aucune place en plus, le demi-bloc au-dessus du choisi reste (sur la ligne vide sous le titre)",
	tight_sec[#tight_sec - 1]:find(convert.fg(GOLD) .. "▄", 1, true) ~= nil,
	true
)
local sec_left, sec_rows = view.minimum(list_page({ list = { rows = SECTIONED, selected = 1, hint = "x" } }))
check("blocs : la hauteur minimum compte les titres et le trait", sec_rows, select(2, view.minimum(list_page())) + 6)
check(
	"blocs : au minimum, tout est dessiné",
	view.draw(list_page({ list = { rows = SECTIONED, selected = 1, hint = "x" } }), sec_left + 2, sec_rows) ~= nil,
	true
)

-- ---- le message, en bas du panneau
local with_message = view.draw(colors_page({ message = " ✓ Saved." }), 120, 42)
check("le message : sur la dernière ligne du panneau", strip(with_message[41]):find("│ ✓ Saved.", 1, true), 1)

-- ---- trop petit : rien de dessiné, la taille qu'il faudrait
local min_left, min_rows = view.minimum(colors_page())
local none, need_cols = view.draw(colors_page(), min_left + 1, 60)
check("trop étroit : rien n'est dessiné", none, nil)
check("trop étroit : la largeur qu'il faudrait (le panneau + le cadre)", need_cols, min_left + 2)
check("trop bas : rien", view.draw(colors_page(), 200, min_rows - 1), nil)
check("trop bas : la hauteur qu'il faudrait", select(3, view.draw(colors_page(), 200, min_rows - 1)), min_rows)
check("pile à la taille minimum : dessiné", view.draw(colors_page(), min_left + 2, min_rows) ~= nil, true)
local last_chosen = colors_page()
last_chosen.colors_tab.index = 16
local at_min_last = strip(table.concat(view.draw(last_chosen, min_left + 2, min_rows), "\n"))
check(
	"au minimum, la dernière case choisie : son cadre est entier (la place au-dessus et en dessous)",
	select(2, at_min_last:gsub("┌", "")) == 1 and select(2, at_min_last:gsub("└", "")) == 1,
	true
)
local at_min_colors = view.draw(colors_page({ message = " ✓ Saved." }), min_left + 2, min_rows)
local at_min_text = strip(table.concat(at_min_colors, "\n"))
check(
	"au minimum (onglet Couleurs) : tout tient (le bouton, le dégradé, les 16 couleurs, le choix, le message)",
	#at_min_colors == min_rows
		and at_min_text:find("y: use your theme colors", 1, true) ~= nil
		and at_min_text:find("Preview", 1, true) ~= nil
		and at_min_text:find("Choice", 1, true) ~= nil
		and at_min_text:find("✓ Saved.", 1, true) ~= nil
		and select(2, table.concat(at_min_colors, "\n"):gsub(literal(convert.bg(palette.COLORS[16])) .. " ", ""))
			== 2 * view.SWATCH_WIDTH,
	true
)
local list_left, list_rows = view.minimum(list_page())
check(
	"pile à la taille minimum (onglet de réglages) : dessiné",
	view.draw(list_page(), list_left + 2, list_rows) ~= nil,
	true
)
check(
	"une ligne de moins que le minimum (onglet de réglages) : rien",
	view.draw(list_page(), list_left + 2, list_rows - 1),
	nil
)
local at_min = view.draw(list_page(), list_left + 2, list_rows)
check(
	"au minimum (onglet de réglages) : les réglages et leur explication tiennent, chacun avec sa ligne",
	#at_min == list_rows
		and strip(table.concat(at_min, "\n")):find("Week starts on", 1, true) ~= nil
		and strip(table.concat(at_min, "\n")):find("Where the selected month goes.", 1, true) ~= nil,
	true
)
check("le minimum du panneau : jamais moins que MIN_LEFT", min_left >= view.MIN_LEFT, true)
check("une aide plus longue élargit le minimum", view.minimum(colors_page({ help = { string.rep("x", 70) } })), 72)
check(
	"un réglage plus long élargit le minimum",
	view.minimum(list_page({
		list = { rows = { { name = string.rep("n", 40), value = string.rep("v", 30) } }, selected = 1, hint = "" },
	})),
	77
)

-- ---- les traits du cadre dans leur couleur
local colored = view.draw(colors_page({ edge = convert.fg("#3366CC"), b = assemble.BORDER_STYLES.double }), 120, 42)
check("le cadre : le style choisi (double)", strip(colored[1]):sub(1, #"╔"), "╔")
check("le cadre : la couleur choisie", colored[1]:find(convert.fg("#3366CC") .. "╔", 1, true), 1)

-- ---- une ligne trop longue n'est jamais plus large que son panneau (coupée)
local cut_lines = view.draw(colors_page({ message = " " .. string.rep("z", 300) }), 120, 42)
check("une ligne trop longue est coupée à la largeur du panneau", layout.visible_width(cut_lines[41]), 120)

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
