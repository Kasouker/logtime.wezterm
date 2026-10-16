-- tests/core/test_timeline.lua : teste core/timeline.lua (la frise) et storage/timeline.lua (son fichier).
-- Lancer :   lua5.4 tests/core/test_timeline.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]core[/\\]test_timeline%.lua$") or "."
local cache = {}
local function load_module(name)
	if not cache[name] then
		cache[name] = assert(loadfile(root .. "/plugin/logtime/" .. name .. ".lua"))(load_module)
	end
	return cache[name]
end
local timeline = load_module("core/timeline")
local storage = load_module("storage/timeline")

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
-- Une journée sous forme de texte : « 32400-36000 a | … »
local function show(list)
	local out = {}
	for _, seg in ipairs(list or {}) do
		out[#out + 1] = seg[1] .. "-" .. seg[2] .. " " .. seg[3]
	end
	return table.concat(out, " | ")
end
local function at(h, m, s)
	return os.time({ year = 2026, month = 10, day = 15, hour = h, min = m or 0, sec = s or 0 })
end
local DAY = "2026-10-15"

-- ---- chaque seconde : le morceau s'allonge
local t = {}
for s = 0, 59 do
	timeline.add(t, "a", at(9, 0, s), at(9, 0, s + 1))
end
check("60 secondes du même projet : un seul morceau", show(t[DAY]), "32400-32460 a")
timeline.add(t, "b", at(9, 1), at(9, 2))
check("un autre projet : un nouveau morceau", show(t[DAY]), "32400-32460 a | 32460-32520 b")
timeline.add(t, "b", at(9, 2, 3), at(9, 3))
check("un petit trou (3 s) : le même morceau continue", show(t[DAY]), "32400-32460 a | 32460-32580 b")
timeline.add(t, "b", at(9, 10), at(9, 11))
check("un vrai trou (7 min) : un nouveau morceau", #t[DAY], 3)
timeline.add(t, "a", at(8, 0), at(8, 1))
check("un morceau plus tôt (dans le désordre) : remis en ordre", t[DAY][1][1], 28800)

-- ---- minuit, et le décalage de la journée
local night = {}
timeline.add(night, "late", at(23, 59, 30), at(23, 59, 30) + 60)
check("à cheval sur minuit : la fin de la veille", show(night[DAY]), "86370-86400 late")
check("à cheval sur minuit : le début du lendemain", show(night["2026-10-16"]), "0-30 late")
local shifted = {}
timeline.add(shifted, "x", at(0, 30), at(0, 31), -3600) -- la journée change à 1h00
check("journée qui change à 1h00 : 0h30 compte pour la veille", show(shifted["2026-10-14"]), "84600-84660 x")

-- ---- retirer une période (le temps inactif, noté après coup)
local r = { [DAY] = { { 32400, 36000, "a" }, { 36000, 39600, "b" } } }
timeline.remove(r, at(9, 30), at(10, 30))
check("retirer au milieu de deux morceaux : les deux sont coupés", show(r[DAY]), "32400-34200 a | 37800-39600 b")
timeline.remove(r, at(10, 40), at(10, 50))
check(
	"retirer au milieu d'un morceau : il est coupé en deux",
	show(r[DAY]),
	"32400-34200 a | 37800-38400 b | 39000-39600 b"
)
timeline.remove(r, at(0), at(23, 59, 59))
check("tout retirer : le jour disparaît", r[DAY], nil)
timeline.remove(r, at(9), at(10))
check("retirer un jour vide : rien ne plante", r[DAY], nil)

-- ---- normalize
local list = { { 100, 200, "b" }, { 0, 100, "a" }, { 150, 300, "c" }, { 300, 302, "c" } }
check(
	"normalize : trié ; un chevauchement d'un autre projet commence où le précédent finit ; le même projet réuni",
	show(timeline.normalize(list)),
	"0-100 a | 100-200 b | 200-302 c"
)
check(
	"normalize : un morceau entièrement recouvert disparaît",
	show(timeline.normalize({ { 0, 100, "a" }, { 10, 50, "b" } })),
	"0-100 a"
)
check("normalize : vide", #timeline.normalize({}), 0)

-- ---- la limite de morceaux par jour
local many = {}
for i = 1, timeline.MAX_PER_DAY + 10 do
	timeline.add(many, (i % 2 == 0) and "a" or "b", at(0) + i * 20, at(0) + i * 20 + 10)
end
check("au-delà de la limite : jamais plus de MAX_PER_DAY morceaux", #many[DAY], timeline.MAX_PER_DAY)
check(
	"au-delà de la limite : la journée reste couverte du premier au dernier",
	many[DAY][1][1] .. " " .. many[DAY][#many[DAY]][2],
	"20 " .. ((timeline.MAX_PER_DAY + 10) * 20 + 10)
)

-- ---- la fusion avec ce qu'un autre WezTerm a écrit
local mem = { [DAY] = { { 0, 100, "a" } } }
timeline.merge(mem, { [DAY] = { { 0, 100, "a" } }, ["2026-10-14"] = { { 5, 9, "z" } } }, nil)
check("fusion, première lecture : un jour qui n'était qu'au fichier est repris", show(mem["2026-10-14"]), "5-9 z")
check("fusion : un jour identique reste tel quel", show(mem[DAY]), "0-100 a")
local own = { [DAY] = { { 0, 50, "a" } } } -- l'inactif a été retiré après coup de 50 à 100
timeline.merge(own, { [DAY] = { { 0, 100, "a" } } }, { [DAY] = { { 0, 100, "a" } } })
check(
	"fusion : le fichier n'a pas changé depuis notre écriture : la mémoire gagne (l'inactif ne revient pas)",
	show(own[DAY]),
	"0-50 a"
)
local other = { [DAY] = { { 0, 50, "a" } } }
timeline.merge(other, { [DAY] = { { 0, 50, "a" }, { 200, 300, "b" } } }, { [DAY] = { { 0, 50, "a" } } })
check("fusion : un autre WezTerm a ajouté un morceau : il est repris", show(other[DAY]), "0-50 a | 200-300 b")

-- ---- le fichier
local sample = { [DAY] = { { 32400, 36000.7, 'a "b"' } }, ["2026-10-14"] = { { 0, 60, "x" } } }
local text = storage.encode(sample)
check(
	"encode : trié, secondes entières, textes protégés",
	text,
	'{"2026-10-14":[[0,60,"x"]],"2026-10-15":[[32400,36000,"a \\"b\\""]]}'
)
local back = storage.decode(text)
check("decode : relu", show(back[DAY]), '32400-36000 a "b"')
check(
	"encode : rien d'invalide (fin avant le début, plus d'une journée, date fausse)",
	storage.encode({ [DAY] = { { 10, 5, "a" }, { 0, 200000, "b" } }, x = { { 0, 1, "c" } } }),
	"{}"
)
check("encode : vide", storage.encode({}), "{}")
local function refused(t_)
	local value, err = storage.decode(t_)
	return value == nil and type(err) == "string"
end
check("decode : pas du JSON", refused("pas du json"), true)
check("decode : une liste", refused("[]"), true)
check("decode : une clé qui n'est pas une date", refused('{"hier":[]}'), true)
check("decode : un jour qui n'est pas une liste", refused('{"2026-10-15":{"a":1}}'), true)
check("decode : un morceau incomplet", refused('{"2026-10-15":[[1,2]]}'), true)
check("decode : un morceau à l'envers", refused('{"2026-10-15":[[5,2,"a"]]}'), true)
check("decode : un projet qui n'est pas du texte", refused('{"2026-10-15":[[1,2,3]]}'), true)
check("decode : un jour vide est accepté", next(storage.decode('{"2026-10-15":[]}')[DAY]), nil)

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
