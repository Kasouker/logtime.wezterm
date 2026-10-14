-- tests/system/test_platform.lua : teste system/platform.lua. Aucune dépendance à WezTerm.
-- Lancer :   lua5.4 tests/system/test_platform.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]system[/\\]test_platform%.lua$") or "."
local globals_before = {}
for k in pairs(_G) do
	globals_before[k] = true
end
local platform = assert(loadfile(root .. "/plugin/logtime/system/platform.lua"))()

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

check("Windows 64 bits", platform.os_name("x86_64-pc-windows-msvc"), "windows")
check("Windows sur processeur ARM", platform.os_name("aarch64-pc-windows-msvc"), "windows")
check("macOS Intel", platform.os_name("x86_64-apple-darwin"), "macos")
check("macOS Apple Silicon", platform.os_name("aarch64-apple-darwin"), "macos")
check("Linux", platform.os_name("x86_64-unknown-linux-gnu"), "linux")
check("Linux ARM", platform.os_name("aarch64-unknown-linux-gnu"), "linux")
check("identifiant absent : Linux par défaut", platform.os_name(nil), "linux")
check("identifiant vide : Linux par défaut", platform.os_name(""), "linux")
check("identifiant inconnu : Linux par défaut", platform.os_name("quelque-chose"), "linux")

local win = platform.blocker_args("windows")
check("Windows : cmd.exe", win[1], "cmd.exe")
check("Windows : option /c", win[2], "/c")
check("Windows : ping qui dure 24 h, sortie jetée", win[3], "ping -n 86400 127.0.0.1>nul")
check("Windows : trois éléments", #win, 3)
local lin = platform.blocker_args("linux")
check("Linux : sh -c", lin[1] .. " " .. lin[2], "sh -c")
check("Linux : sleep qui dure 24 h, sans écho", lin[3], "stty -echo 2>/dev/null; exec sleep 86400")
local mac = platform.blocker_args("macos")
check("macOS : comme Linux", mac[3], lin[3])
check("système absent : comme Linux", platform.blocker_args(nil)[3], lin[3])
check(
	"deux appels donnent deux tables indépendantes",
	platform.blocker_args("windows") ~= platform.blocker_args("windows"),
	true
)

local leaked = {}
for k in pairs(_G) do
	if not globals_before[k] then
		leaked[#leaked + 1] = k
	end
end
check("aucune variable globale ajoutée", table.concat(leaked, ","), "")

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
