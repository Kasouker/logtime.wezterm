-- tests/status/test_status.lua : teste status/status.lua. Lancer :   lua5.4 tests/status/test_status.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]status[/\\]test_status%.lua$") or "."
local status = assert(loadfile(root .. "/plugin/logtime/status/status.lua"))()

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

check("0 s", status.hms(0), "00:00:00")
check("59 s", status.hms(59), "00:00:59")
check("60 s", status.hms(60), "00:01:00")
check("3599 s", status.hms(3599), "00:59:59")
check("3600 s", status.hms(3600), "01:00:00")
check("3725 s", status.hms(3725), "01:02:05")
check("une journée moins une seconde", status.hms(86399), "23:59:59")
check("plus de 24 h : les heures continuent", status.hms(90000), "25:00:00")
check("la partie décimale est ignorée", status.hms(3661.9), "01:01:01")
check("15231 s (4h13 du 10 octobre)", status.hms(15231), "04:13:51")

check("text : horloge puis durée", status.text(3725), utf8.char(0xF017) .. " 01:02:05")
check("text : commence par l'icône", status.text(0):sub(1, #utf8.char(0xF017)), utf8.char(0xF017))

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
