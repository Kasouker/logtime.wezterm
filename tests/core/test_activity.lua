-- tests/core/test_activity.lua : teste core/activity.lua (le temps par projet) et storage/projects.lua (son fichier).
-- Lancer :   lua5.4 tests/core/test_activity.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]core[/\\]test_activity%.lua$") or "."

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
local activity = load_module("core/activity")
local projects_storage = load_module("storage/projects")

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

-- ---- path_of : l'adresse du dossier, comme WezTerm la donne
check("Windows", activity.path_of("file:///C:/Users/alex/Projects/"), "C:/Users/alex/Projects")
check(
	"WSL : la distribution est retirée",
	activity.path_of("file://wsl.localhost/Ubuntu/home/max/42/"),
	"/home/max/42"
)
check("WSL (ancienne adresse wsl$)", activity.path_of("file://wsl$/Ubuntu/tmp/"), "/tmp")
check("Linux, avec un nom de machine", activity.path_of("file://pc-max/home/max/42/C05"), "/home/max/42/C05")
check("Mac", activity.path_of("file:///Users/max/dev/site/"), "/Users/max/dev/site")
check("espaces encodés (%20)", activity.path_of("file:///home/max/Mes%20projets/a"), "/home/max/Mes projets/a")
check("accents encodés", activity.path_of("file:///home/max/caf%C3%A9"), "/home/max/café")
check("déjà un chemin", activity.path_of("/home/max/42"), "/home/max/42")
check("chemin Windows avec des \\", activity.path_of("C:\\Users\\max\\dev"), "C:/Users/max/dev")
check("rien", activity.path_of(nil), nil)
check("vide", activity.path_of(""), nil)
check("pas une adresse de fichier", activity.path_of("https://example.com/"), nil)

-- ---- project_of : les deux premiers dossiers sous le dossier personnel
check(
	"sous le dossier personnel : deux dossiers",
	activity.project_of("C:/Users/alex/Projects/logtime.wezterm/plugin"),
	"Projects/logtime.wezterm"
)
check("un seul dossier", activity.project_of("C:/Users/alex/Projects"), "Projects")
check("Linux", activity.project_of("/home/max/42/C05/ex02"), "42/C05")
check("Mac", activity.project_of("/Users/max/dev/site/src"), "dev/site")
check("root", activity.project_of("/root/projet"), "projet")
check("Windows vu depuis WSL", activity.project_of("/mnt/c/Users/alex/Projects/x"), "Projects/x")
check("lettre de lecteur en minuscule, users en minuscule", activity.project_of("c:/users/alex/a/b/c"), "a/b")
check("le dossier personnel lui-même : rien", activity.project_of("C:/Users/alex"), nil)
check("le dossier personnel (Linux) : rien", activity.project_of("/home/max"), nil)
check("/homes n'est pas /home", activity.project_of("/homes/max/a"), "max/a")
check("/home/alexandra n'est pas /home/alex suivi de « andra »", activity.project_of("/home/alexandra/a"), "a")
check("hors du dossier personnel : les deux derniers", activity.project_of("/mnt/d/jeux/steam/common"), "steam/common")
check("hors du dossier personnel, un seul", activity.project_of("/tmp"), "tmp")
check("un lecteur Windows hors du dossier personnel", activity.project_of("D:/projets/site"), "projets/site")
check("/rootfoo n'est pas /root", activity.project_of("/rootfoo/a"), "rootfoo/a")
check("un lecteur Windows, un seul dossier : sans la lettre", activity.project_of("D:/site"), "site")
check("la racine : rien", activity.project_of("/"), nil)
check("la racine d'un lecteur : rien", activity.project_of("C:"), nil)

-- ---- clean_title
check(
	"le symbole animé de Claude retiré",
	activity.clean_title("◑ Configuration de WezTerm"),
	"Configuration de WezTerm"
)
check("une étoile", activity.clean_title("✳ Claude Code"), "Claude Code")
check("une icône Nerd Font", activity.clean_title(utf8.char(0xF489) .. " nvim"), "nvim")
check("un emoji", activity.clean_title("🚀 build"), "build")
check(".exe retiré", activity.clean_title("wslhost.exe"), "wslhost")
check(".EXE retiré", activity.clean_title("PING.EXE"), "PING")
check("un accent au début est gardé", activity.clean_title("Été 2026"), "Été 2026")
check("un chiffre au début est gardé", activity.clean_title("42 piscine"), "42 piscine")
check("espaces de la fin retirés", activity.clean_title("zsh   "), "zsh")
check("rien que des symboles", activity.clean_title("◑ ✳ "), nil)
check("pas de titre", activity.clean_title(nil), nil)

-- ---- label
check(
	"le dossier d'abord",
	activity.label("file:///C:/Users/alex/Projects/logtime.wezterm/", "◑ Claude"),
	"Projects/logtime.wezterm"
)
check("dossier personnel : le titre", activity.label("file:///C:/Users/alex/", "wslhost.exe"), "wslhost")
check("ni dossier ni titre : inconnu", activity.label(nil, nil), activity.OTHER)
check(
	"un nom trop long est coupé",
	activity.label(nil, string.rep("é", 50)),
	string.rep("é", activity.MAX_LEN - 1) .. "…"
)

-- ---- add, retrait, cap, top
local t = os.time({ year = 2026, month = 10, day = 14, hour = 10 })
local p = {}
activity.add(p, "a", t, t + 600)
activity.add(p, "b", t + 600, t + 700)
activity.add(p, "a", t + 700, t + 760)
check("add : a", p["2026-10-14"].a, 660)
check("add : b", p["2026-10-14"].b, 100)
activity.add(p, "a", t, t + 60, nil, -1)
check("retrait", p["2026-10-14"].a, 600)
activity.add(p, "b", t, t + 500, nil, -1)
check("retrait : jamais en dessous de zéro (le projet disparaît)", p["2026-10-14"].b, nil)
local midnight = os.time({ year = 2026, month = 10, day = 14, hour = 23, min = 59, sec = 30 })
activity.add(p, "nuit", midnight, midnight + 60)
check("minuit : coupé (avant)", p["2026-10-14"].nuit, 30)
check("minuit : coupé (après)", p["2026-10-15"].nuit, 30)
local offset = os.time({ year = 2026, month = 10, day = 15, hour = 0, min = 30 })
local q = {}
activity.add(q, "x", offset, offset + 60, -3600)
check("décalage de minuit (la journée change à 1 h) : 0 h 30 compte pour la veille", q["2026-10-14"].x, 60)

local many = {}
for i = 1, activity.MAX_PER_DAY + 5 do
	activity.add(many, string.format("p%02d", i), t, t + i)
end
local count, other = 0, many["2026-10-14"][activity.OTHER]
for label in pairs(many["2026-10-14"]) do
	if label ~= activity.OTHER then
		count = count + 1
	end
end
check("cap : au plus 29 projets plus « autres »", count, activity.MAX_PER_DAY - 1)
check("cap : les plus petits dans « autres » (1 + 2 + ... + 6)", other, 21)
check("cap : le plus grand est gardé", many["2026-10-14"]["p35"], 35)
check("cap : le plus petit regroupé", many["2026-10-14"]["p01"], nil)

local exact = {}
for i = 1, activity.MAX_PER_DAY do
	activity.add(exact, string.format("p%02d", i), t, t + i)
end
check("cap : exactement 30 projets, le plus petit regroupé (29 + autres)", exact["2026-10-14"][activity.OTHER], 1)
check("top : un projet à 0 seconde (lu dans un fichier) n'est pas affiché", #activity.top({ a = 1, e = 0 }, 5), 1)
local top = activity.top({ a = 50, b = 300, c = 100, d = 10, [activity.OTHER] = 5, e = 0 }, 2)
check("top : 3 lignes (2 + autres)", #top, 3)
check("top : le plus grand d'abord", top[1].label .. "=" .. top[1].secs, "b=300")
check("top : puis le suivant", top[2].label .. "=" .. top[2].secs, "c=100")
check("top : autres = a + d + ce qui y était déjà", top[3].label .. "=" .. top[3].secs, activity.OTHER .. "=65")
check("top : à égalité, l'ordre alphabétique", activity.top({ z = 5, y = 5 }, 5)[1].label, "y")
check("top : rien", #activity.top(nil, 5), 0)
check("top : sans reste, pas de ligne autres", #activity.top({ a = 1 }, 5), 1)

-- ---- le fichier
local sample =
	{ ["2026-10-14"] = { ["Projects/logtime.wezterm"] = 8040.7, ['a "b" \\ c'] = 5 }, ["2026-10-13"] = { x = 1 } }
local text = projects_storage.encode(sample)
check(
	"encode : trié, secondes entières, textes protégés",
	text,
	'{"2026-10-13":{"x":1},"2026-10-14":{"Projects/logtime.wezterm":8040,"a \\"b\\" \\\\ c":5}}'
)
local back = projects_storage.decode(text)
check("decode : relu", back["2026-10-14"]['a "b" \\ c'], 5)
check("decode : relu (2)", back["2026-10-14"]["Projects/logtime.wezterm"], 8040)
check(
	"encode : rien d'invalide (date, valeur négative, moins d'une seconde)",
	projects_storage.encode({ x = { a = 5 }, ["2026-10-14"] = { a = -1, b = 0.5 } }),
	"{}"
)
check("encode : vide", projects_storage.encode({}), "{}")
check("decode : vide", next(projects_storage.decode("{}")), nil)
check("decode : accents", projects_storage.decode('{"2026-10-14":{"café":3}}')["2026-10-14"]["café"], 3)
local function refused(t_)
	local value, err = projects_storage.decode(t_)
	return value == nil and type(err) == "string"
end
check("decode : pas du JSON", refused("pas du json"), true)
check("decode : une liste", refused("[]"), true)
check("decode : une clé qui n'est pas une date", refused('{"hier":{"a":1}}'), true)
check("decode : un jour qui n'est pas un objet", refused('{"2026-10-14":5}'), true)
check("decode : un jour en liste", refused('{"2026-10-14":[1]}'), true)
check("decode : un jour en liste vide", refused('{"2026-10-14":[]}'), true)
check("decode : une valeur négative", refused('{"2026-10-14":{"a":-1}}'), true)
check("decode : une valeur texte", refused('{"2026-10-14":{"a":"1"}}'), true)
check("decode : pas du texte", refused(nil), true)

local leaked = {}
for k in pairs(_G) do
	if not globals_before[k] then
		leaked[#leaked + 1] = k
	end
end
check("aucune variable globale ajoutée", table.concat(leaked, ","), "")

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
