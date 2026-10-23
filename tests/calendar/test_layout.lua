-- tests/calendar/test_layout.lua : teste calendar/layout.lua (combien de mois, lesquels, côte à côte) et les morceaux
-- d'assemble.lua qui servent à afficher plusieurs mois (month_block, legend). Aucune dépendance à WezTerm.
-- Lancer :   lua5.4 tests/calendar/test_layout.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]calendar[/\\]test_layout%.lua$") or "."

local globals_before = {}
for k in pairs(_G) do
	globals_before[k] = true
end
local cache = {}
local function load_module(name)
	if not cache[name] then
		local chunk = assert(loadfile(root .. "/plugin/logtime/" .. name .. ".lua"))
		cache[name] = chunk(load_module)
	end
	return cache[name]
end
local layout = load_module("calendar/layout")
local assemble = load_module("calendar/assemble")
local dates = load_module("calendar/dates")
local fr = load_module("i18n/fr")
local en = load_module("i18n/en")

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
local function shape(plan)
	return plan.count .. ":" .. plan.columns .. "x" .. plan.rows
end

-- ============================================================
-- visible_width
-- ============================================================
check("largeur visible : texte simple", layout.visible_width("abc"), 3)
check("largeur visible : vide", layout.visible_width(""), 0)
check("largeur visible : les accents comptent pour un", layout.visible_width("Février"), 7)
check("largeur visible : le point médian compte pour un", layout.visible_width("·"), 1)
check("largeur visible : les couleurs ne comptent pas", layout.visible_width("\27[48;2;1;2;3mab\27[0m"), 2)
check("largeur visible : le gras ne compte pas", layout.visible_width("\27[1m  Octobre 2026\27[0m"), 14)
check("largeur visible : les codes d'écran alternatif ne comptent pas", layout.visible_width("\27[?1049hab"), 2)

-- ============================================================
-- cohérence des constantes avec le dessin
-- ============================================================
check("la largeur d'un mois est celle du dessin", layout.BLOCK_WIDTH, assemble.WIDTH)
check("la hauteur d'un mois est celle du dessin", layout.BLOCK_HEIGHT, assemble.HEIGHT)

-- ============================================================
-- plan : combien de mois, sur combien de colonnes
-- ============================================================
-- une colonne a besoin de 65 colonnes, deux de 133 (65 + 3 + 65) ; une rangée de 29 lignes, deux de 51 (8 + 21 + 1 + 21)
check("fenêtre de 65 x 29 : un seul mois", shape(layout.plan(65, 29)), "1:1x1")
check("fenêtre de 132 x 51 : une seule colonne tient, deux rangées", shape(layout.plan(132, 51)), "2:1x2")
check("fenêtre de 133 x 51 : 2 x 2", shape(layout.plan(133, 51)), "4:2x2")
check("fenêtre de 133 x 50 : une rangée de deux", shape(layout.plan(133, 50)), "2:2x1")
check("fenêtre de 133 x 29 : deux côte à côte", shape(layout.plan(133, 29)), "2:2x1")
check("fenêtre de 132 x 29 : un seul", shape(layout.plan(132, 29)), "1:1x1")
check("fenêtre de 120 x 40 (la taille par défaut de WezTerm) : un seul", shape(layout.plan(120, 40)), "1:1x1")
check("fenêtre de 200 x 64 : 2 x 2", shape(layout.plan(200, 64)), "4:2x2")
check("fenêtre de 65 x 100 : quatre empilés (une colonne)", shape(layout.plan(65, 100)), "4:1x4")
check(
	"fenêtre de 400 x 29 : cinq côte à côte (une seule rangée tient, et le plafond est de 12)",
	shape(layout.plan(400, 29)),
	"5:5x1"
)
check(
	"fenêtre de 269 x 95 : douze mois, 4 x 3 (le plafond par défaut est maintenant 12)",
	shape(layout.plan(269, 95)),
	"12:4x3"
)
check("fenêtre de 201 x 73 : neuf mois, 3 x 3", shape(layout.plan(201, 73)), "9:3x3")
check(
	"fenêtre de 250 x 64 : six mois, 3 x 2 (quatre seulement avec l'ancien plafond)",
	shape(layout.plan(250, 64)),
	"6:3x2"
)
check("fenêtre de 201 x 51 : six mois, 3 x 2", shape(layout.plan(201, 51)), "6:3x2")
check("fenêtre de 201 x 29 : trois côte à côte", shape(layout.plan(201, 29)), "3:3x1")
check("fenêtre de 20 x 5 : jamais moins de un", shape(layout.plan(20, 5)), "1:1x1")
check("très large mais trop basse (263 x 21) : un seul, jamais des mois coupés", shape(layout.plan(263, 21)), "1:1x1")
check("très large mais basse (224 x 10, plafond 3) : un seul", shape(layout.plan(224, 10, 3)), "1:1x1")
check("juste trop basse pour un mois (400 x 28) : un seul", shape(layout.plan(400, 28)), "1:1x1")
check("juste assez haute pour une rangée (400 x 29) : plusieurs", layout.plan(400, 29).count > 1, true)
check("très haute mais trop étroite (40 x 100) : un seul", shape(layout.plan(40, 100)), "1:1x1")
check("juste trop étroite pour un mois (64 x 100) : un seul", shape(layout.plan(64, 100)), "1:1x1")
check("juste assez large pour un mois (65 x 100) : empilés", layout.plan(65, 100).count > 1, true)
check("taille absente : un seul", shape(layout.plan(nil, nil)), "1:1x1")
check("taille à zéro : un seul", shape(layout.plan(0, 0)), "1:1x1")
check("taille négative : un seul", shape(layout.plan(-10, -10)), "1:1x1")
check("taille en texte : un seul", shape(layout.plan("beaucoup", "beaucoup")), "1:1x1")

-- le plafond de mois
check("plafond par défaut : 12 (une année), même dans une immense fenêtre", layout.plan(1000, 300).count, 12)
check("plafond de 2 : deux côte à côte", shape(layout.plan(1000, 300, 2)), "2:2x1")
check("plafond de 1 : un seul", shape(layout.plan(1000, 300, 1)), "1:1x1")
check("plafond de 3 : trois côte à côte", shape(layout.plan(1000, 300, 3)), "3:3x1")
check("plafond de 6 : 3 x 2", shape(layout.plan(1000, 300, 6)), "6:3x2")
check("plafond de 12 : 4 x 3", shape(layout.plan(1000, 300, 12)), "12:4x3")
check("plafond de 99 : ramené à 12", layout.plan(1000, 300, 99).count, 12)
check("plafond de 0 : ramené à 1", layout.plan(1000, 300, 0).count, 1)
check("plafond négatif : ramené à 1", layout.plan(1000, 300, -5).count, 1)
check("plafond décimal : arrondi vers le bas", layout.plan(1000, 300, 2.9).count, 2)
check("plafond en texte : le plafond par défaut", layout.plan(1000, 300, "beaucoup").count, 12)
check("plafond de 3 dans une fenêtre 2 x 2 : trois mois, une case vide", shape(layout.plan(133, 51, 3)), "3:2x2")
check(
	"plafond de 3, fenêtre de 201 x 51 : trois côte à côte plutôt que 2 x 2 avec une case vide",
	shape(layout.plan(201, 51, 3)),
	"3:3x1"
)

-- jamais un mois coupé : ce que le plan annonce tient toujours dans la fenêtre
local seed = 4242
local function rnd(n)
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed % n
end
local never_overflows = true
for _ = 1, 400 do
	local cols, rows, max = 20 + rnd(400), 5 + rnd(120), 1 + rnd(12)
	local plan = layout.plan(cols, rows, max)
	local used_cols = plan.columns * layout.BLOCK_WIDTH + (plan.columns - 1) * layout.GAP
	local used_rows = layout.RESERVED_ROWS + plan.rows * layout.BLOCK_HEIGHT + (plan.rows - 1)
	local ok = plan.count >= 1 and plan.count <= max and plan.columns * plan.rows >= plan.count
	if plan.count > 1 then
		ok = ok and used_cols <= cols and used_rows <= rows
	end
	if not ok then
		never_overflows = false
	end
end
check(
	"400 fenêtres au hasard : le plan tient toujours dans la fenêtre, sans dépasser le plafond",
	never_overflows,
	true
)
local grows = true
for cols = 60, 420, 7 do
	local previous = 0
	for rows = 20, 130, 5 do
		local count = layout.plan(cols, rows, 12).count
		if count < previous then
			grows = false
		end
		previous = count
	end
end
check("plus la fenêtre est haute, plus il y a de mois (jamais moins)", grows, true)

-- ============================================================
-- months : quels mois
-- ============================================================
local function list(months)
	local out = {}
	for _, m in ipairs(months) do
		out[#out + 1] = m.year .. "-" .. m.month
	end
	return table.concat(out, ",")
end
check("le mois choisi est le dernier (par défaut)", list(layout.months(2026, 10, 4)), "2026-7,2026-8,2026-9,2026-10")
check("ancre « last »", list(layout.months(2026, 10, 4, "last")), "2026-7,2026-8,2026-9,2026-10")
check(
	"ancre « first » : le mois choisi est le premier",
	list(layout.months(2026, 10, 4, "first")),
	"2026-10,2026-11,2026-12,2027-1"
)
check("ancre inconnue : comme « last »", list(layout.months(2026, 10, 2, "milieu")), "2026-9,2026-10")
check("un seul mois", list(layout.months(2026, 10, 1)), "2026-10")
check(
	"à cheval sur deux années (ancre « last »)",
	list(layout.months(2026, 1, 3, "last")),
	"2025-11,2025-12,2026-1"
)
check("à cheval sur deux années (ancre « first »)", list(layout.months(2026, 12, 2, "first")), "2026-12,2027-1")
check("décembre en dernier", list(layout.months(2026, 12, 3, "last")), "2026-10,2026-11,2026-12")
check(
	"douze mois : une année entière",
	list(layout.months(2026, 12, 12, "last")),
	"2026-1,2026-2,2026-3,2026-4,2026-5,2026-6,2026-7,2026-8,2026-9,2026-10,2026-11,2026-12"
)
local ordered = true
for count = 1, 12 do
	local months = layout.months(2026, 3, count)
	for i = 2, #months do
		local a, b = months[i - 1], months[i]
		if b.year * 12 + b.month ~= a.year * 12 + a.month + 1 then
			ordered = false
		end
	end
end
check("les mois se suivent toujours, un par un", ordered, true)
local m = layout.months(2026.0, 10.0, 2)
check("des nombres décimaux entiers donnent des mois utilisables", dates.key(m[1].year, m[1].month, 1), "2026-09-01")

-- ============================================================
-- arrange : côte à côte
-- ============================================================
local function block(lines, width)
	return { lines = lines, width = width }
end
local out = layout.arrange({ block({ "ab", "cd" }, 4), block({ "ef", "gh" }, 4) }, 2, 3)
check("deux blocs : première ligne", out[1], "ab     ef")
check("deux blocs : deuxième ligne", out[2], "cd     gh")
check("deux blocs : deux lignes en tout", #out, 2)
out = layout.arrange({ block({ "ab" }, 4), block({ "cd", "ef" }, 4) }, 2, 1)
check("un bloc plus court : ses lignes manquantes sont des espaces", out[2], "     ef")
check("le dernier bloc n'est pas rempli d'espaces à droite", out[1], "ab   cd")
out = layout.arrange({ block({ "a" }, 3), block({ "b" }, 3), block({ "c" }, 3), block({ "d" }, 3) }, 2, 1)
check("quatre blocs sur deux colonnes : 3 lignes (rangée, vide, rangée)", #out, 3)
check("deux rangées : première rangée", out[1], "a   b")
check("deux rangées : une ligne vide entre elles", out[2], "")
check("deux rangées : seconde rangée", out[3], "c   d")
out = layout.arrange({ block({ "a" }, 3), block({ "b" }, 3), block({ "c" }, 3) }, 2, 1)
check("trois blocs sur deux colonnes : la dernière rangée n'a qu'un bloc", out[3], "c")
out = layout.arrange({ block({ "a" }, 3), block({ "b" }, 3) }, 1, 1)
check("une colonne : les blocs sont empilés avec une ligne vide", table.concat(out, "|"), "a||b")
out = layout.arrange({ block({ "\27[1mab\27[0m", "x" }, 4), block({ "cd", "y" }, 4) }, 2, 2)
check("les couleurs ne faussent pas l'alignement (largeur visible)", layout.visible_width(out[1]), 4 + 2 + 2)
check("les couleurs sont conservées", out[1]:sub(1, 4), "\27[1m")
check("sans bloc : rien", #layout.arrange({}, 2, 3), 0)
out = layout.arrange({ block({ "é·" }, 4), block({ "x" }, 4) }, 2, 1)
check("les accents sont comptés comme un caractère", out[1], "é·  " .. " " .. "x")
out = layout.arrange({ block({ "a" }), block({ "b" }) }, 2)
check("largeur et espace par défaut", layout.visible_width(out[1]), layout.BLOCK_WIDTH + layout.GAP + 1)

-- ============================================================
-- assemble.month_block et assemble.legend
-- ============================================================
local days = { ["2026-10-10"] = 15231, ["2026-10-11"] = 1900, ["2026-10-12"] = 3600 }
local blk = assemble.month_block(days, 2026, 10, "2026-10-12", {}, fr, false)
check("month_block : la largeur annoncée", blk.width, assemble.WIDTH)
check("month_block : la hauteur est toujours la même", #blk.lines, assemble.HEIGHT)
check(
	"month_block : le titre, sans le préfixe du plugin, suivi du total et des jours actifs",
	strip(blk.lines[1]),
	"  Octobre 2026   Total du mois : 5h45 / Jours actifs : 3"
)
check("month_block : pas de gras si le mois n'est pas le choisi", blk.lines[1]:find("\27[1m", 1, true), nil)
check("month_block : l'en-tête est celui du dessin", strip(blk.lines[2]):match("^%s*(%a+)"), "Lun")
check("month_block sans objectif : la dernière ligne est vide (rien à valider)", strip(blk.lines[#blk.lines]), "")
local selected = assemble.month_block(days, 2026, 10, "2026-10-12", {}, fr, true)
check(
	"month_block : le mois choisi a son titre en gras (seulement le nom du mois)",
	selected.lines[1]:find("\27[1m  Octobre 2026\27[0m   Total", 1, true),
	1
)
check(
	"month_block : en gras, le reste est identique",
	table.concat(selected.lines, "\n", 2),
	table.concat(blk.lines, "\n", 2)
)
check(
	"month_block : anglais",
	strip(assemble.month_block(days, 2026, 10, "x", {}, en, false).lines[1]),
	"  October 2026   Month total: 5h45 / Active days: 3"
)
check(
	"month_block : semaine du dimanche",
	strip(assemble.month_block(days, 2026, 10, "x", { week_starts_on = "sunday" }, fr, false).lines[2]):match(
		"^%s*(%a+)"
	),
	"Dim"
)
local full = {}
for line in (strip(assemble.render_month(days, 2026, 10, "2026-10-12", {}, fr)) .. "\n"):gmatch("(.-)\n") do
	full[#full + 1] = line
end
local same_weeks = true
for i = 3, 18 do
	if strip(blk.lines[i - 1]) ~= full[i + 1] then
		same_weeks = false
	end
end
check("month_block : les semaines sont exactement celles du mois seul", same_weeks, true)
local legend_ok, heights_ok, widths_ok = true, true, true
for year = 2020, 2031 do
	for month = 1, 12 do
		for _, start in ipairs({ "monday", "sunday" }) do
			local b = assemble.month_block({}, year, month, "x", { week_starts_on = start }, fr, false)
			if #b.lines ~= layout.BLOCK_HEIGHT then
				heights_ok = false
			end
			for _, line in ipairs(b.lines) do
				if layout.visible_width(line) > layout.BLOCK_WIDTH then
					widths_ok = false
				end
			end
		end
	end
end
check("144 mois : tous ont exactement la hauteur prévue (4, 5 ou 6 semaines)", heights_ok, true)
check("144 mois : aucune ligne n'est plus large que prévu", widths_ok, true)
check(
	"legend : les quatre niveaux, puis l'étoile",
	strip(assemble.legend({}, fr)),
	"  ██ <1h   ██ 1-3h   ██ 3-6h   ██ 6h+     * = aujourd'hui"
)
check(
	"legend : avec une fonction de couleur, seulement l'étoile",
	strip(assemble.legend({ cell_color = function() end }, fr)),
	"  * = aujourd'hui"
)
check(
	"legend : seuils personnalisés",
	strip(assemble.legend({ thresholds = { 2, 4, 8 } }, fr)):find("<2h", 1, true) ~= nil,
	true
)

-- ============================================================
-- effets de bord
-- ============================================================
local leaked = {}
for k in pairs(_G) do
	if not globals_before[k] then
		leaked[#leaked + 1] = k
	end
end
check("aucune variable globale ajoutée", table.concat(leaked, ","), "")

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
