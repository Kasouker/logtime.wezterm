-- tests/status/test_auto.lua : teste status/auto.lua (où afficher le compteur). Lancer :   lua5.4 tests/status/test_auto.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]status[/\\]test_auto%.lua$") or "."
local globals_before = {}
for k in pairs(_G) do
	globals_before[k] = true
end
local auto = assert(loadfile(root .. "/plugin/logtime/status/auto.lua"))()

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

-- ---- choose : où afficher le compteur
local function choose(info)
	info.now = info.now or 1000
	return auto.choose(info)
end
check("rien de spécial : à droite de la barre normale", choose({}), "right")
check("status = false : nulle part", choose({ enabled = false }), "off")
check(
	"status = false gagne sur tout le reste",
	choose({ enabled = false, has_tabline = true, external_at = 1000 }),
	"off"
)
check("tick() appelé ailleurs à l'instant : déjà affiché", choose({ external_at = 1000 }), "external")
check("tick() appelé ailleurs il y a 3 s : déjà affiché", choose({ external_at = 997 }), "external")
check(
	"tick() appelé ailleurs il y a 4 s : plus personne ne l'affiche, à droite",
	choose({ external_at = 996 }),
	"right"
)
check(
	"tick() appelé ailleurs, avec tabline : déjà affiché (pas de second compteur)",
	choose({ external_at = 999, has_tabline = true }),
	"external"
)
check("tabline, démarré à l'instant : attendre", choose({ has_tabline = true, started_at = 1000 }), "wait")
check("tabline, démarré il y a 2 s : attendre encore", choose({ has_tabline = true, started_at = 998 }), "wait")
check(
	"tabline, démarré il y a 3 s : s'ajouter à tabline",
	choose({ has_tabline = true, started_at = 997 }),
	"tabline"
)
check("tabline, sans instant de démarrage : s'ajouter à tabline", choose({ has_tabline = true }), "tabline")
check(
	"sans tabline, démarré à l'instant : à droite tout de suite (rien à attendre)",
	choose({ started_at = 1000 }),
	"right"
)

-- ---- find_tabline : tabline.wez dans la liste des plugins
local TABLINE = "https://github.com/michaelbrusegard/tabline.wez"
check(
	"find_tabline : trouvé",
	auto.find_tabline({ { url = "https://github.com/x/autre.wez" }, { url = TABLINE } }),
	TABLINE
)
check("find_tabline : absent", auto.find_tabline({ { url = "https://github.com/x/autre.wez" } }), nil)
check("find_tabline : liste vide", auto.find_tabline({}), nil)
check("find_tabline : pas de liste", auto.find_tabline(nil), nil)
check(
	"find_tabline : entrées bizarres ignorées",
	auto.find_tabline({ "texte", { url = 12 }, { component = "x" } }),
	nil
)
check(
	"find_tabline : « tabline.wez » au sens exact (le point n'est pas un joker)",
	auto.find_tabline({ { url = "https://github.com/x/tablineXwez" } }),
	nil
)

-- ---- ensure_component : s'ajouter une seule fois à la barre de tabline
local function component() end
local opts = { sections = { tabline_x = { "texte" }, tabline_y = { "datetime" } } }
check("ensure_component : ajouté", auto.ensure_component(opts, component), true)
check("ensure_component : au début de tabline_x", opts.sections.tabline_x[1], component)
check("ensure_component : ce qui y était reste après", opts.sections.tabline_x[2], "texte")
check("ensure_component : les autres sections ne bougent pas", #opts.sections.tabline_y, 1)
check("ensure_component : une seconde fois, rien n'est ajouté", auto.ensure_component(opts, component), false)
check("ensure_component : toujours deux éléments", #opts.sections.tabline_x, 2)
local empty = {}
check("ensure_component : sans sections, elles sont créées", auto.ensure_component(empty, component), true)
check("ensure_component : la section créée contient le compteur", empty.sections.tabline_x[1], component)
local custom = { sections = {} }
auto.ensure_component(custom, component, "tabline_a")
check("ensure_component : une autre section si on la donne", custom.sections.tabline_a[1], component)
check(
	"ensure_component : pas une table (tabline absent ou bizarre) : rien",
	auto.ensure_component(nil, component),
	false
)
local other = function() end
local shared = { sections = { tabline_x = { component } } }
check(
	"ensure_component : une autre fonction (nouvelle évaluation de la config) est ajoutée",
	auto.ensure_component(shared, other),
	true
)

-- plusieurs éléments ajoutés ensemble (le style, le compteur, puis la remise des couleurs de tabline)
local style = {}
local group = { style, component, "ResetAttributes" }
local with_group = { sections = { tabline_x = { "texte" } } }
check("ensure_component, plusieurs éléments : ajoutés", auto.ensure_component(with_group, group), true)
check(
	"ensure_component, plusieurs éléments : dans l'ordre, au début, avant ce qui y était",
	with_group.sections.tabline_x[1] == style
		and with_group.sections.tabline_x[2] == component
		and with_group.sections.tabline_x[3] == "ResetAttributes"
		and with_group.sections.tabline_x[4] == "texte",
	true
)
check(
	"ensure_component, plusieurs éléments : une seconde fois, rien",
	auto.ensure_component(with_group, group),
	false
)
check("ensure_component, plusieurs éléments : toujours 4 éléments", #with_group.sections.tabline_x, 4)

local leaked = {}
for k in pairs(_G) do
	if not globals_before[k] then
		leaked[#leaked + 1] = k
	end
end
check("aucune variable globale ajoutée", table.concat(leaked, ","), "")

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
