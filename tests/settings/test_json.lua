-- tests/settings/test_json.lua : teste settings/json.lua (lecture d'un texte JSON, y compris un fichier modifié à la main
-- ou abîmé). Aucune dépendance à WezTerm. Lancer :   lua5.4 tests/settings/test_json.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]settings[/\\]test_json%.lua$") or "."

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
local json = load_module("settings/json")

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
local function bad(name, text)
	local value, err = json.decode(text)
	check(name .. " : refusé", value, nil)
	check(name .. " : avec un message en français", type(err) == "string" and #err > 5, true)
end

-- ---- valeurs simples
check("nombre entier", json.decode("12"), 12)
check("nombre négatif", json.decode("-3"), -3)
check("nombre décimal", json.decode("0.8"), 0.8)
check("zéro", json.decode("0"), 0)
check("exposant", json.decode("1e2"), 100)
check("exposant négatif", json.decode("5E-1"), 0.5)
check("vrai", json.decode("true"), true)
check("faux", json.decode("false"), false)
check("null est la valeur spéciale", json.decode("null"), json.null)
check("texte", json.decode('"abc"'), "abc")
check("texte vide", json.decode('""'), "")
check("texte avec accents", json.decode('"Février ✓"'), "Février ✓")
check("espaces autour", json.decode("  \n\t 42 \r\n"), 42)

-- ---- échappements
check("guillemet échappé", json.decode('"a\\"b"'), 'a"b')
check("antislash échappé", json.decode('"a\\\\b"'), "a\\b")
check("barre échappée", json.decode('"a\\/b"'), "a/b")
check("retour à la ligne échappé", json.decode('"a\\nb"'), "a\nb")
check("tabulation échappée", json.decode('"a\\tb"'), "a\tb")
check("séquence \\u simple", json.decode('"\\u00e9"'), "é")
check("séquence \\u majuscule", json.decode('"\\u00C9"'), "É")
check("paire de substitution (émoji)", json.decode('"\\ud83d\\ude00"'), "😀")
check("texte long sans échappement", json.decode('"' .. string.rep("x", 5000) .. '"'), string.rep("x", 5000))

-- ---- objets et listes
local object = json.decode('{"a": 1, "b": "deux", "c": true, "d": null, "e": [1, 2, 3], "f": {"g": 4}}')
check("objet : un nombre", object.a, 1)
check("objet : un texte", object.b, "deux")
check("objet : un booléen", object.c, true)
check("objet : null", object.d, json.null)
check("objet : une liste", #object.e == 3 and object.e[3] == 3, true)
check("objet : un objet imbriqué", object.f.g, 4)
check("objet vide", next(json.decode("{}")), nil)
check("objet vide avec espaces", next(json.decode("{ \n }")), nil)
check("liste vide", #json.decode("[]"), 0)
check("une liste vide est reconnue comme une liste", json.is_array(json.decode("[]")), true)
check("une liste pleine est reconnue comme une liste", json.is_array(json.decode("[1, 2]")), true)
check("un objet vide n'est pas une liste", json.is_array(json.decode("{}")), false)
check("un objet n'est pas une liste", json.is_array(json.decode('{"a": 1}')), false)
check("un nombre n'est pas une liste", json.is_array(12), false)
check("nil n'est pas une liste", json.is_array(nil), false)
check("une liste dans un objet est reconnue", json.is_array(json.decode('{"a": [1]}').a), true)
check("clé en double : la dernière gagne", json.decode('{"a": 1, "a": 2}').a, 2)
check("clé avec un échappement", json.decode('{"a\\u0062": 1}').ab, 1)
check("marque BOM au début", json.decode('\239\187\191{"a": 1}').a, 1)
check(
	"lecture d'un fichier écrit par le plugin",
	json.decode('{\n  "gradient_color": "#3366CC",\n  "max_months": 6\n}\n').max_months,
	6
)
local nested = string.rep("[", 30) .. string.rep("]", 30)
check("imbrication à 30 niveaux acceptée", type(json.decode(nested)), "table")

-- ---- refus (un fichier abîmé ne fait jamais planter la lecture)
bad("texte vide", "")
bad("seulement des espaces", "   \n  ")
bad("accolade non fermée", '{"a": 1')
bad("accolade en trop", '{"a": 1}}')
bad("virgule en trop à la fin", '{"a": 1,}')
bad("virgule manquante", '{"a": 1 "b": 2}')
bad("deux-points manquant", '{"a" 1}')
bad("clé sans guillemets", "{a: 1}")
bad("clé avec guillemets simples", "{'a': 1}")
bad("texte non terminé", '{"a": "abc')
bad("échappement inconnu", '"a\\qb"')
bad("séquence \\u trop courte", '"\\u12"')
bad("substitution seule (haut)", '"\\ud83d"')
bad("substitution seule (bas)", '"\\ude00"')
bad("saut de ligne brut dans un texte", '"a\nb"')
bad("tabulation brute dans un texte", '"a\tb"')
bad("nombre avec zéro au début", "012")
bad("nombre avec point final", "1.")
bad("nombre avec exposant incomplet", "1e")
bad("moins seul", "-")
bad("valeur inconnue", "undefined")
bad("TRUE en majuscules", "TRUE")
bad("texte en trop après la valeur", "12 abc")
bad("deux valeurs de suite", "1 2")
bad("liste non fermée", "[1, 2")
bad("liste avec virgule en trop", "[1, 2,]")
bad("commentaire", '{"a": 1} // note')
bad("trop d'imbrications", string.rep("[", 100) .. string.rep("]", 100))
bad("octets au hasard", "\255\254\0\1")
check("valeur qui n'est pas un texte : refusée", json.decode(nil), nil)
check("valeur qui n'est pas un texte : refusée (nombre)", json.decode(12), nil)
check("valeur qui n'est pas un texte : message", type(select(2, json.decode(nil))), "string")

-- ---- jamais de plantage, même sur des morceaux au hasard
local seed = 99
local function rnd(n)
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed % n
end
local pieces =
	{ "{", "}", "[", "]", ",", ":", '"', "\\", "a", "1", "-", ".", "e", "true", "null", " ", "\n", "\\u", "00", "é" }
local crashed = false
for _ = 1, 3000 do
	local parts = {}
	for i = 1, 1 + rnd(14) do
		parts[i] = pieces[1 + rnd(#pieces)]
	end
	local ok = pcall(json.decode, table.concat(parts))
	if not ok then
		crashed = true
	end
end
check("3000 textes au hasard : aucun plantage", crashed, false)

local leaked = {}
for k in pairs(_G) do
	if not globals_before[k] then
		leaked[#leaked + 1] = k
	end
end
check("aucune variable globale ajoutée", table.concat(leaked, ","), "")

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
