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

-- ---- l'objectif dans la barre
local clock = utf8.char(0xF017) .. " "
check("goal_short : 7 h", status.goal_short(7), "7h")
check("goal_short : 7 h 30", status.goal_short(7.5), "7h30")
check("goal_short : 30 min", status.goal_short(0.5), "0h30")
check("goal_short : 24 h", status.goal_short(24), "24h")
check("sans objectif : comme avant", status.text(3725, nil), clock .. "01:02:05")
check("objectif 0 (aucun) : comme avant", status.text(3725, 0), clock .. "01:02:05")
check("objectif pas atteint : la durée, puis l'objectif", status.text(18750, 7), clock .. "05:12:30 / 7h")
check("objectif pas atteint, 7h30", status.text(18750, 7.5), clock .. "05:12:30 / 7h30")
check("objectif atteint pile : ✓", status.text(25200, 7), clock .. "✓ 07:00:00")
check("objectif dépassé : ✓", status.text(25390, 7), clock .. "✓ 07:03:10")
check("une seconde avant l'objectif : pas encore", status.text(25199, 7), clock .. "06:59:59 / 7h")
check("reached : oui", status.reached(25200, 7), true)
check("reached : pas encore", status.reached(25199, 7), false)
check("reached : sans objectif", status.reached(99999, nil), false)
check("reached : objectif 0", status.reached(99999, 0), false)

-- ---- goal_event : annoncer l'objectif une seule fois par jour, au moment où il est atteint
local function ev(seen, key, reached)
	local now_seen, announce = status.goal_event(seen, key, reached)
	return now_seen .. " " .. tostring(announce)
end
local D = "2026-10-13"
check("premier passage, objectif pas atteint : on note, rien à annoncer", ev(nil, D, false), D .. "=0 false")
check(
	"premier passage, objectif déjà atteint (WezTerm rouvert) : on note, rien à annoncer",
	ev(nil, D, true),
	D .. "=1 false"
)
check("l'objectif vient d'être atteint : on annonce", ev(D .. "=0", D, true), D .. "=1 true")
check("déjà atteint et annoncé : rien de plus", ev(D .. "=1", D, true), D .. "=1 false")
check("toujours pas atteint : rien", ev(D .. "=0", D, false), D .. "=0 false")
check("nouveau jour, première fois vu : on note, rien à annoncer", ev("2026-10-12=0", D, true), D .. "=1 false")
check(
	"objectif relevé en cours de journée (plus atteint), puis atteint de nouveau : on annonce",
	ev(D .. "=0", D, true),
	D .. "=1 true"
)

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
