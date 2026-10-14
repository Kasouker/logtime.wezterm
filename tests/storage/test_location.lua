-- tests/storage/test_location.lua : teste storage/location.lua (le dossier des fichiers et la copie depuis l'ancien
-- emplacement). Lancer :   lua5.4 tests/storage/test_location.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]storage[/\\]test_location%.lua$") or "."
local location = assert(loadfile(root .. "/plugin/logtime/storage/location.lua"))()

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

local function read(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text
end
local function write(path, text)
	local f = assert(io.open(path, "wb"))
	f:write(text)
	f:close()
end
local function new_dirs()
	local base = os.tmpname()
	os.remove(base)
	local old, new = base .. "/home", base .. "/home/.local/share/logtime"
	os.execute("mkdir -p '" .. new .. "'")
	return base, old, new
end

-- ---- le dossier et la commande qui le crée
check("dossier (Windows)", location.dir("C:\\Users\\max", "\\"), "C:\\Users\\max\\.local\\share\\logtime")
check("dossier (Linux)", location.dir("/home/max", "/"), "/home/max/.local/share/logtime")
check(
	"création sous Windows : cmd.exe /c mkdir (crée aussi les dossiers au-dessus)",
	table.concat(location.mkdir_args("windows", "C:\\a\\b"), " "),
	"cmd.exe /c mkdir C:\\a\\b"
)
check("création sous Linux : mkdir -p", table.concat(location.mkdir_args("linux", "/a/b"), " "), "mkdir -p /a/b")
check("création sous macOS : mkdir -p", table.concat(location.mkdir_args("macos", "/a/b"), " "), "mkdir -p /a/b")
check(
	"le dossier, sous un nom qui contient des espaces, reste un seul argument",
	location.mkdir_args("windows", "C:\\Users\\Jean Paul\\x")[4],
	"C:\\Users\\Jean Paul\\x"
)

-- ---- writable
local base, old, new = new_dirs()
check("writable : un dossier qui existe", location.writable(new, "/"), true)
check("writable : le fichier d'essai est retiré", read(new .. "/.logtime_probe"), nil)
check("writable : un dossier qui n'existe pas", location.writable(new .. "/absent", "/"), false)

-- ---- migrate : copie, jamais de déplacement
write(old .. "/.logtime.json", '{"2026-10-10":15231}')
write(old .. "/.logtime_settings.json", '{"max_months":3}')
write(old .. "/.logtime.json.bak", "copie de sécurité")
local copied, problems = location.migrate(old, new, "/")
check("migrate : deux fichiers copiés", table.concat(copied, ","), ".logtime.json,.logtime_settings.json")
check("migrate : aucun problème", #problems, 0)
check("migrate : contenu identique (heures)", read(new .. "/.logtime.json"), '{"2026-10-10":15231}')
check("migrate : contenu identique (réglages)", read(new .. "/.logtime_settings.json"), '{"max_months":3}')
check("migrate : l'original est toujours là (heures)", read(old .. "/.logtime.json"), '{"2026-10-10":15231}')
check("migrate : l'original est toujours là (réglages)", read(old .. "/.logtime_settings.json"), '{"max_months":3}')
check("migrate : les copies de sécurité (.bak) ne sont pas copiées", read(new .. "/.logtime.json.bak"), nil)
check("migrate : aucun fichier temporaire laissé", read(new .. "/.logtime.json.tmp"), nil)
check("migrate : un fichier absent n'est pas inventé", read(new .. "/.logtime_idle.json"), nil)

-- une seconde fois : rien n'est recopié, rien n'est remplacé
write(new .. "/.logtime.json", '{"2026-10-11":1}')
copied, problems = location.migrate(old, new, "/")
check("migrate, deuxième fois : rien de copié", #copied, 0)
check(
	"migrate, deuxième fois : le nouveau fichier n'est pas remplacé",
	read(new .. "/.logtime.json"),
	'{"2026-10-11":1}'
)

-- un fichier ajouté plus tard à l'ancien emplacement (et absent du nouveau) est copié
write(old .. "/.logtime_idle.json", '{"2026-10-10":60}')
copied = location.migrate(old, new, "/")
check("migrate : un fichier qui manque encore est copié", table.concat(copied, ","), ".logtime_idle.json")

-- l'écriture échoue : le problème est donné, rien n'est laissé, l'original est intact
os.execute("rm -rf '" .. base .. "'")
base, old, new = new_dirs()
write(old .. "/.logtime_projects.json", '{"2026-10-10":{"a":1}}')
local real_open = io.open
io.open = function(path, mode)
	if mode == "wb" and path:find("/share/logtime/", 1, true) then
		return nil, path .. ": Permission denied"
	end
	return real_open(path, mode)
end
copied, problems = location.migrate(old, new, "/")
io.open = real_open
check("échec : rien de copié", #copied, 0)
check("échec : un problème", #problems, 1)
check(
	"échec : le problème nomme le fichier",
	problems[1] and problems[1]:find(".logtime_projects.json : ", 1, true),
	1
)
check("échec : l'original est intact", read(old .. "/.logtime_projects.json"), '{"2026-10-10":{"a":1}}')
check("échec : rien dans le nouveau dossier", read(new .. "/.logtime_projects.json"), nil)

-- la copie relue n'est pas identique (disque qui ment) : refusée, fichier temporaire retiré
io.open = function(path, mode)
	if mode == "rb" and path:find("%.tmp$") then
		local f = real_open(path, mode)
		return {
			read = function()
				return "abîmé"
			end,
			close = function()
				f:close()
			end,
		}
	end
	return real_open(path, mode)
end
copied, problems = location.migrate(old, new, "/")
io.open = real_open
check("vérification : refusée", #copied == 0 and #problems == 1, true)
check("vérification : la raison est donnée", problems[1] and problems[1]:find("vérification", 1, true) ~= nil, true)
check("vérification : fichier temporaire retiré", read(new .. "/.logtime_projects.json.tmp"), nil)
check("vérification : rien dans le nouveau dossier", read(new .. "/.logtime_projects.json"), nil)

-- l'écriture n'échoue qu'à la fermeture (disque plein) : refusée, même si la relecture semble bonne
io.open = function(path, mode)
	if mode == "wb" and path:find("%.tmp$") then
		local f = real_open(path, mode)
		return {
			write = function(self, text)
				f:write(text)
				return self
			end,
			close = function()
				f:close()
				return nil, "No space left on device"
			end,
		}
	end
	return real_open(path, mode)
end
copied, problems = location.migrate(old, new, "/")
io.open = real_open
check("fermeture en échec : refusée", #copied == 0 and #problems == 1, true)
check(
	"fermeture en échec : la raison du système est donnée",
	problems[1] and problems[1]:find("No space left on device", 1, true) ~= nil,
	true
)
check("fermeture en échec : fichier temporaire retiré", read(new .. "/.logtime_projects.json.tmp"), nil)
check("fermeture en échec : rien dans le nouveau dossier", read(new .. "/.logtime_projects.json"), nil)

-- le renommage échoue : refusé, fichier temporaire retiré
local real_rename = os.rename
os.rename = function()
	return nil, "refusé"
end
copied, problems = location.migrate(old, new, "/")
os.rename = real_rename
check("renommage : refusé", #copied == 0 and #problems == 1, true)
check("renommage : fichier temporaire retiré", read(new .. "/.logtime_projects.json.tmp"), nil)
check("renommage : l'original est intact", read(old .. "/.logtime_projects.json"), '{"2026-10-10":{"a":1}}')

-- tout marche à nouveau : la copie se fait
copied, problems = location.migrate(old, new, "/")
check("ensuite : copié", table.concat(copied, ","), ".logtime_projects.json")
check("ensuite : contenu identique", read(new .. "/.logtime_projects.json"), '{"2026-10-10":{"a":1}}')
os.execute("rm -rf '" .. base .. "'")

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
