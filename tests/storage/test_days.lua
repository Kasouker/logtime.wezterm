-- tests/storage/test_days.lua : teste storage/days.lua (lecture et écriture des heures par jour).
-- Aucune dépendance à WezTerm. Lancer :   lua5.4 tests/storage/test_days.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]storage[/\\]test_days%.lua$") or "."
local globals_before = {}
for k in pairs(_G) do
	globals_before[k] = true
end
local days_mod = assert(loadfile(root .. "/plugin/logtime/storage/days.lua"))()

local passed, failed = 0, 0
local function check(name, got, want)
	if got == want then
		passed = passed + 1
	else
		failed = failed + 1
		print(string.format("ÉCHEC  %s\n         attendu : %s\n         obtenu  : %s", name, tostring(want), tostring(got)))
	end
end

local function tmpdir()
	local path = os.tmpname()
	os.remove(path)
	os.execute("mkdir -p '" .. path .. "'")
	return path
end
local function write(path, text)
	local f = assert(io.open(path, "wb"))
	f:write(text)
	f:close()
end
local function read(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text
end
local function same(a, b)
	for k, v in pairs(a) do
		if b[k] ~= v then
			return false
		end
	end
	for k, v in pairs(b) do
		if a[k] ~= v then
			return false
		end
	end
	return true
end

-- ============================================================
-- encode
-- ============================================================
check("encode : ton vrai historique", days_mod.encode({ ["2026-10-10"] = 15231, ["2026-10-11"] = 1900 }), '{"2026-10-10":15231,"2026-10-11":1900}')
check("encode : vide", days_mod.encode({}), "{}")
check("encode : nil", days_mod.encode(nil), "{}")
check("encode : dates triées", days_mod.encode({ ["2026-10-12"] = 3, ["2026-01-05"] = 1, ["2025-12-31"] = 2 }), '{"2025-12-31":2,"2026-01-05":1,"2026-10-12":3}')
check("encode : les secondes décimales deviennent entières", days_mod.encode({ ["2026-10-10"] = 15231.9 }), '{"2026-10-10":15231}')
check("encode : zéro conservé", days_mod.encode({ ["2026-10-10"] = 0 }), '{"2026-10-10":0}')
check("encode : grande valeur", days_mod.encode({ ["2026-10-10"] = 86400 * 3 }), '{"2026-10-10":259200}')
check("encode : clé qui n'est pas une date ignorée", days_mod.encode({ ["2026-10-10"] = 5, truc = 7 }), '{"2026-10-10":5}')
check("encode : valeur négative ignorée", days_mod.encode({ ["2026-10-10"] = -5 }), "{}")
check("encode : valeur non numérique ignorée", days_mod.encode({ ["2026-10-10"] = "beaucoup" }), "{}")
check("encode : NaN ignoré", days_mod.encode({ ["2026-10-10"] = 0 / 0 }), "{}")
check("encode : infini ignoré", days_mod.encode({ ["2026-10-10"] = math.huge }), "{}")

-- ============================================================
-- decode
-- ============================================================
local d = days_mod.decode('{"2026-10-10":15231,"2026-10-11":1900}')
check("decode : ton vrai historique, jour 1", d and d["2026-10-10"], 15231)
check("decode : ton vrai historique, jour 2", d and d["2026-10-11"], 1900)
d = days_mod.decode('  {\n  "2026-10-10" : 5 ,\n  "2026-10-11":6\n}\n')
check("decode : espaces et retours à la ligne tolérés", d and d["2026-10-10"] == 5 and d["2026-10-11"] == 6, true)
d = days_mod.decode('{"2026-10-10":15231.0}')
check("decode : décimale lue", d and d["2026-10-10"], 15231)
d = days_mod.decode('{"2026-10-10":1.5e3}')
check("decode : notation scientifique lue", d and d["2026-10-10"], 1500)
check("decode : objet vide", next(days_mod.decode("{}")), nil)
check("decode : objet vide avec espaces", next(days_mod.decode("{ \n }")), nil)
d = days_mod.decode('{"2026-10-10":5,"2026-10-10":9}')
check("decode : doublon, la dernière valeur gagne", d and d["2026-10-10"], 9)
d = days_mod.decode('\r\n{"2026-10-10":5}\r\n')
check("decode : fins de ligne Windows", d and d["2026-10-10"], 5)

local function rejected(name, text)
	local result, err = days_mod.decode(text)
	check("decode : " .. name .. " : refusé", result, nil)
	check("decode : " .. name .. " : une raison est donnée", type(err), "string")
end
rejected("texte vide", "")
rejected("espaces seulement", "   ")
rejected("pas un objet (tableau)", '["2026-10-10"]')
rejected("pas du JSON", "bonjour")
rejected("virgule en trop à la fin", '{"2026-10-10":5,}')
rejected("virgule en trop au début", '{,"2026-10-10":5}')
rejected("clé qui n'est pas une date", '{"hier":5}')
rejected("date mal formée", '{"2026-1-10":5}')
rejected("valeur négative", '{"2026-10-10":-5}')
rejected("valeur texte", '{"2026-10-10":"cinq"}')
rejected("valeur nulle (null)", '{"2026-10-10":null}')
rejected("deux-points manquant", '{"2026-10-10" 5}')
rejected("objet imbriqué", '{"2026-10-10":{"a":1}}')
rejected("accolade non fermée", '{"2026-10-10":5')
rejected("texte après l'objet", '{"2026-10-10":5} fin')
rejected("deux valeurs sans virgule", '{"2026-10-10":5 "2026-10-11":6}')
rejected("infini", '{"2026-10-10":inf}')
rejected("NaN", '{"2026-10-10":nan}')
rejected("fichier tronqué", '{"2026-10-10":15231,"2026-10-1')
local r, e = days_mod.decode(nil)
check("decode : nil refusé", r, nil)

-- aller-retour sur des jeux de données variés
local seed = 12345
local function rnd(n)
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed % n
end
local roundtrip_ok = true
for _ = 1, 50 do
	local days = {}
	for _ = 1, rnd(40) do
		days[string.format("%04d-%02d-%02d", 2020 + rnd(8), 1 + rnd(12), 1 + rnd(28))] = rnd(86400)
	end
	local back = days_mod.decode(days_mod.encode(days))
	if not back or not same(days, back) then
		roundtrip_ok = false
	end
end
check("aller-retour : 50 jeux de données aléatoires", roundtrip_ok, true)

-- ============================================================
-- load
-- ============================================================
local dir = tmpdir()
local file = dir .. "/.logtime.json"
local loaded, status = days_mod.load(file)
check("load : fichier absent", status, "absent")
check("load : fichier absent, historique vide", next(loaded), nil)

write(file, '{"2026-10-10":15231,"2026-10-11":1900}')
loaded, status = days_mod.load(file)
check("load : fichier lisible", status, "ok")
check("load : valeurs lues", loaded["2026-10-10"] == 15231 and loaded["2026-10-11"] == 1900, true)

write(file, '{"2026-10-10":152')
loaded, status = days_mod.load(file)
local _, _, why = days_mod.load(file)
check("load : fichier tronqué = corrompu", status, "corrupt")
check("load : fichier corrompu, une raison est donnée", type(why), "string")
check("load : le fichier corrompu n'est pas modifié par la lecture", read(file), '{"2026-10-10":152')

write(file, "")
check("load : fichier vide = corrompu", select(2, days_mod.load(file)), "corrupt")

-- ============================================================
-- save
-- ============================================================
os.remove(file)
local ok = days_mod.save(file, { ["2026-10-10"] = 15231, ["2026-10-11"] = 1900 })
check("save : réussit", ok, true)
check("save : contenu exact, identique à l'ancien format", read(file), '{"2026-10-10":15231,"2026-10-11":1900}')
check("save : aucun fichier temporaire laissé", read(file .. ".tmp"), nil)
ok = days_mod.save(file, { ["2026-10-10"] = 15300 })
check("save : écrase proprement l'ancien contenu", read(file), '{"2026-10-10":15300}')
check("save : aucun fichier temporaire laissé après écrasement", read(file .. ".tmp"), nil)
check("save puis load : on retrouve les mêmes valeurs", select(1, days_mod.load(file))["2026-10-10"], 15300)

-- disque qui tronque l'écriture sans le dire : la vérification doit le voir, l'ancien fichier reste intact
write(file, '{"2026-10-10":1}')
local real_open2 = io.open
io.open = function(p, m)
	if p:match("%.tmp$") and m == "wb" then
		local real = real_open2(p, m)
		return {
			write = function(_, text)
				real:write(text:sub(1, math.floor(#text / 2)))
				return true
			end,
			close = function()
				real:close()
			end,
		}
	end
	return real_open2(p, m)
end
ok, why = days_mod.save(file, { ["2026-10-10"] = 999999, ["2026-10-11"] = 5 })
io.open = real_open2
check("save : écriture tronquée détectée, échec", ok, false)
check("save : écriture tronquée, l'ancien fichier est intact", read(file), '{"2026-10-10":1}')
check("save : écriture tronquée, fichier temporaire supprimé", read(file .. ".tmp"), nil)

-- dossier inexistant : échec propre, rien n'est créé
ok, why = days_mod.save(dir .. "/inexistant/sous/.logtime.json", { ["2026-10-10"] = 1 })
check("save : dossier inexistant, échec", ok, false)
check("save : dossier inexistant, une raison est donnée", type(why), "string")

-- Windows : renommer par-dessus un fichier existant échoue. La sauvegarde doit quand même aboutir.
write(file, '{"2026-10-10":1}')
local real_rename = os.rename
os.rename = function(from, to)
local existing = io.open(to, "rb")
if existing then
existing:close()
return nil, "le fichier existe déjà (comportement de Windows)"
end
return real_rename(from, to)
end
local real_open = io.open
io.open = function(p, m)
if p == file and m == "wb" then
return nil, "écriture directe interdite dans ce test"
end
return real_open(p, m)
end
ok = days_mod.save(file, { ["2026-10-10"] = 777 })
io.open = real_open
check("save : même quand rename refuse d'écraser (Windows), la sauvegarde aboutit sans copie directe", ok, true)
check("save : Windows, contenu exact", read(file), '{"2026-10-10":777}')
check("save : Windows, aucun fichier temporaire laissé", read(file .. ".tmp"), nil)

-- Windows, cas extrême : rename ne marche jamais. Le dernier recours (copie directe) doit aboutir.
os.rename = function()
return nil, "toujours refusé"
end
ok = days_mod.save(file, { ["2026-10-10"] = 888 })
check("save : même quand rename échoue toujours, copie directe", ok, true)
check("save : copie directe, contenu exact", read(file), '{"2026-10-10":888}')
check("save : copie directe, aucun fichier temporaire laissé", read(file .. ".tmp"), nil)
os.rename = real_rename

-- ============================================================
-- backup et quarantine
-- ============================================================
write(file, '{"2026-10-10":4242}')
ok = days_mod.backup(file)
check("backup : réussit", ok, true)
check("backup : copie identique", read(file .. ".bak"), '{"2026-10-10":4242}')
check("backup : l'original n'est pas touché", read(file), '{"2026-10-10":4242}')
ok = days_mod.backup(dir .. "/absent.json")
check("backup : rien à copier", ok, false)

write(file, "pas du json")
local moved = days_mod.quarantine(file)
check("quarantine : un nouveau nom est renvoyé", type(moved), "string")
check("quarantine : le fichier abîmé est à son nouvel emplacement", read(moved), "pas du json")
check("quarantine : l'emplacement d'origine est libre", read(file), nil)
write(file, "encore abîmé")
local moved2 = days_mod.quarantine(file)
check("quarantine : deux mises de côté dans la même seconde ne s'écrasent pas", moved2 ~= moved and read(moved) == "pas du json" and read(moved2) == "encore abîmé", true)
check("quarantine : fichier absent, pas de plantage", select(1, days_mod.quarantine(dir .. "/absent.json")), nil)

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
os.execute("rm -rf '" .. dir .. "'")

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
