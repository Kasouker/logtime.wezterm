-- tests/core/test_idle.lua : teste core/idle.lua (le temps inactif). Lancer :   lua5.4 tests/core/test_idle.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]core[/\\]test_idle%.lua$") or "."

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
local idle = load_module("core/idle")
local counter = load_module("core/counter")
local day = load_module("core/day")

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

-- ---- note : la dernière activité
check("note : première empreinte, c'est une activité", idle.note(nil, "a", nil, 100), 100)
check("note : empreinte changée, activité maintenant", idle.note("a", "b", 50, 100), 100)
check("note : rien n'a bougé, la même qu'avant", idle.note("a", "a", 50, 100), 50)
check(
	"note : rien n'a bougé mais pas d'activité connue (rechargement) : maintenant",
	idle.note("a", "a", nil, 100),
	100
)

-- ---- span : la part inactive du temps compté
check("span : activité inconnue, rien d'inactif", idle.span(nil, nil, 99, 100, 300), nil)
check("span : 299 s sans bouger, pas encore", idle.span(1, nil, 299, 300, 300), nil)
check(
	"span : 300 s sans bouger, tout depuis la dernière activité devient inactif",
	idle.span(1, nil, 300, 301, 300),
	1
)
check("span : ensuite, seulement le nouveau temps", idle.span(1, 1, 301, 302, 300), 301)
check("span : une nouvelle pause (autre activité) recommence en arrière", idle.span(500, 1, 900, 901, 300), 500)
check("span : rien de compté, rien d'inactif", idle.span(1, nil, 400, 400, 300), nil)
check("span : sans idle_after, 5 minutes", idle.span(0, nil, 299, 300, nil), 0)
check("span : sans idle_after, 4 min 59 non", idle.span(0, nil, 298, 299, nil), nil)

-- ---- share : la part d'un total
local function share(total, i)
	local secs, percent = idle.share(total, i)
	return secs .. " " .. percent
end
check("share : 1h30 sur 10h", share(36000, 5400), "5400 15")
check("share : rien d'inactif", share(36000, nil), "0 0")
check("share : rien de compté", share(0, 100), "0 0")
check("share : jamais plus que le total", share(100, 500), "100 100")
check("share : arrondi (1/3 = 33 %)", share(3, 1), "1 33")
check("share : arrondi (2/3 = 67 %)", share(3, 2), "2 67")

-- ---- active_days : les heures sans l'inactif (count_idle = false)
local source = { ["2026-10-14"] = 36000, ["2026-10-13"] = 100, ["2026-10-12"] = 7200 }
local act = idle.active_days(source, { ["2026-10-14"] = 5400, ["2026-10-13"] = 500 })
check("active_days : 10h - 1h30", act["2026-10-14"], 30600)
check("active_days : jamais en dessous de zéro", act["2026-10-13"], 0)
check("active_days : un jour sans inactif reste entier", act["2026-10-12"], 7200)
check("active_days : les heures d'origine ne sont pas touchées", source["2026-10-14"], 36000)
check("active_days : sans inactif du tout", idle.active_days(source, nil)["2026-10-14"], 36000)

-- ---- une journée simulée, comme dans le plugin : à chaque seconde, compter, noter l'inactif, puis l'activité
local function simulate(script)
	local days, idle_days = {}, {}
	local state = {}
	local last, last_activity, marked, fp
	local t = os.time({ year = 2026, month = 10, day = 14, hour = script.start or 10 })
	for _, part in ipairs(script) do
		for _ = 1, part.secs, part.step or 1 do
			local now = t + (part.step or 1)
			local added, counted = counter.advance(days, last, now, { normal_gap = 5, sleep_limit = 3900 }, state)
			if added then
				local start = idle.span(last_activity, marked, last, last + counted, 300)
				if start then
					marked = last_activity
					day.add_interval(idle_days, start, last + counted)
				end
			end
			local current = part.active and tostring(now) or "même écran"
			last_activity = idle.note(fp, current, last_activity, now)
			fp = current
			last = now
			t = now
		end
	end
	return days, idle_days
end
local K = "2026-10-14"
local d, i = simulate({ { secs = 600, active = true }, { secs = 3600 }, { secs = 600, active = true } })
-- le premier passage ne compte rien (pas d'instant précédent) : 1h20 moins une seconde
check("journée : 10 min de travail, 1 h de pause, 10 min de travail : 1h20 comptées", d[K], 4799)
check("journée : la pause d'une heure compte une heure d'inactivité (les 5 premières minutes comprises)", i[K], 3600)
d, i = simulate({ { secs = 600, active = true }, { secs = 299 }, { secs = 600, active = true } })
check("journée : une pause de moins de 5 min n'est pas inactive", i[K], nil)
check("journée : mais elle est comptée", d[K], 1498)
d, i = simulate({ { secs = 60, active = true }, { secs = 600 }, { secs = 60, active = true }, { secs = 400 } })
-- la première seconde d'une pause, l'écran a encore changé (on vient d'arrêter) : c'est la dernière activité.
-- La 1re pause s'arrête à la reprise (la seconde de reprise est comptée avant de voir l'activité) : 600 s ;
-- la 2de va jusqu'à la fin : 399 s.
check("journée : deux pauses (10 min et 6 min 40) : 999 s inactives", i[K], 999)
d, i = simulate({ { secs = 1200 } })
check(
	"journée : WezTerm ouvert, rien ne bouge : la première empreinte compte comme activité, le reste est inactif",
	i[K],
	1199
)
-- une pause qui passe minuit : l'inactif est coupé à minuit comme le compteur
d, i = simulate({ start = 23, { secs = 3000, active = true }, { secs = 1200 } })
check("minuit : 20 min inactives, dont 10 avant minuit (moins la première seconde de la pause)", i[K], 599)
check("minuit : et 10 après", i["2026-10-15"], 600)
-- une mise en veille (un écart de 30 min sans mise à jour) : comptée par le compteur, et inactive
d, i = simulate({ { secs = 600, active = true }, { secs = 1800, step = 1800 }, { secs = 60, active = true } })
check("veille : comptée (10 min + 30 min + 1 min, moins le premier passage)", d[K], 2459)
check("veille : les 30 min sont inactives", i[K], 1800)
-- une veille de 2 h : le compteur n'en compte que 65 min (sleep_limit) ; l'inactif pas plus
d, i = simulate({ { secs = 600, active = true }, { secs = 7200, step = 7200 } })
check("longue veille : 10 min + 65 min comptées", d[K], 599 + 3900)
check("longue veille : 65 min inactives, pas 2 h", i[K], 3900)

local leaked = {}
for k in pairs(_G) do
	if not globals_before[k] then
		leaked[#leaked + 1] = k
	end
end
check("aucune variable globale ajoutée", table.concat(leaked, ","), "")

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
