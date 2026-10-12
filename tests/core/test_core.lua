-- tests/core/test_core.lua : teste core/day.lua et core/counter.lua.
-- Aucune dépendance à WezTerm. Lancer :   lua5.4 tests/core/test_core.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]core[/\\]test_core%.lua$") or "."

local cache = {}
local function load_module(name)
	if not cache[name] then
		local chunk = assert(loadfile(root .. "/plugin/logtime/" .. name .. ".lua"))
		cache[name] = chunk(load_module)
	end
	return cache[name]
end
local day = load_module("core/day")
local counter = load_module("core/counter")

local passed, failed = 0, 0
local function check(name, got, want)
	if got == want then
		passed = passed + 1
	else
		failed = failed + 1
		print(string.format("ÉCHEC  %s\n         attendu : %s\n         obtenu  : %s", name, tostring(want), tostring(got)))
	end
end
local function ts(y, mo, d, h, mi, s)
	return os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s })
end
local function seq(start, n)
	local out = {}
	for i = 0, n - 1 do
		out[#out + 1] = start + i
	end
	return out
end
local function join(...)
	local out = {}
	for _, list in ipairs({ ... }) do
		for _, v in ipairs(list) do
			out[#out + 1] = v
		end
	end
	return out
end
local function total(days)
	local sum = 0
	for _, v in pairs(days) do
		sum = sum + v
	end
	return sum
end

-- ============================================================
-- core/day.lua
-- ============================================================
check("day.key : une date", day.key(ts(2026, 10, 12, 15, 30, 0)), "2026-10-12")
check("day.key : minuit pile", day.key(ts(2026, 10, 13, 0, 0, 0)), "2026-10-13")
check("day.key : 23:59:59", day.key(ts(2026, 10, 12, 23, 59, 59)), "2026-10-12")
check("day.key : décalage -3600, 00:30 est encore la veille", day.key(ts(2026, 10, 13, 0, 30, 0), -3600), "2026-10-12")
check("day.key : décalage -3600, 01:00 est le nouveau jour", day.key(ts(2026, 10, 13, 1, 0, 0), -3600), "2026-10-13")

local d = {}
day.add_interval(d, ts(2026, 10, 12, 12, 0, 0), ts(2026, 10, 12, 12, 0, 30))
check("add_interval : 30 s dans une journée", d["2026-10-12"], 30)
check("add_interval : une seule clé", total(d), 30)

d = {}
day.add_interval(d, ts(2026, 10, 12, 23, 30, 0), ts(2026, 10, 13, 0, 30, 0))
check("add_interval : à cheval sur minuit, avant", d["2026-10-12"], 1800)
check("add_interval : à cheval sur minuit, après", d["2026-10-13"], 1800)

d = {}
day.add_interval(d, ts(2026, 10, 11, 22, 0, 0), ts(2026, 10, 14, 2, 0, 0))
check("add_interval : sur plusieurs jours, premier jour", d["2026-10-11"], 2 * 3600)
check("add_interval : sur plusieurs jours, jour entier", d["2026-10-12"], 24 * 3600)
check("add_interval : sur plusieurs jours, second jour entier", d["2026-10-13"], 24 * 3600)
check("add_interval : sur plusieurs jours, dernier jour", d["2026-10-14"], 2 * 3600)

d = {}
day.add_interval(d, ts(2026, 10, 13, 0, 30, 0), ts(2026, 10, 13, 0, 30, 3), -3600)
check("add_interval : avec décalage, compté la veille", d["2026-10-12"], 3)
check("add_interval : avec décalage, rien le jour même", d["2026-10-13"], nil)

d = {}
day.add_interval(d, ts(2026, 10, 12, 12, 0, 0), ts(2026, 10, 12, 12, 0, 0))
check("add_interval : intervalle vide", next(d), nil)
day.add_interval(d, ts(2026, 10, 12, 12, 0, 10), ts(2026, 10, 12, 12, 0, 0))
check("add_interval : intervalle à l'envers ignoré", next(d), nil)

d = {}
day.add_interval(d, ts(2026, 10, 12, 12, 0, 0), ts(2026, 10, 12, 12, 0, 10))
day.add_interval(d, ts(2026, 10, 12, 12, 0, 10), ts(2026, 10, 12, 12, 0, 25))
check("add_interval : les ajouts successifs s'additionnent", d["2026-10-12"], 25)

-- passage à l'heure d'hiver : un jour de 25 h doit être compté en entier (seulement si ton fuseau en a un)
local dst_a = os.date("*t", ts(2026, 10, 24, 12, 0, 0)).isdst
local dst_b = os.date("*t", ts(2026, 10, 26, 12, 0, 0)).isdst
if dst_a ~= dst_b then
	d = {}
	day.add_interval(d, ts(2026, 10, 25, 0, 0, 0), ts(2026, 10, 26, 0, 0, 0))
	check("add_interval : jour de 25 h (changement d'heure) compté en entier", d["2026-10-25"], 25 * 3600)
	check("add_interval : rien n'est reporté sur le lendemain", d["2026-10-26"], nil)
else
	print("(info) ton fuseau horaire n'a pas de changement d'heure : test du jour de 25 h ignoré")
end

-- ============================================================
-- core/counter.lua
-- ============================================================
local base = { normal_gap = 5, sleep_limit = 3600, settle_time = 60, day_offset = 0 }

-- Rejoue des instants successifs en conservant l'état du budget de veille entre les appels
local function run(cfg, steps)
local days, last, state = {}, nil, {}
for _, now in ipairs(steps) do
counter.advance(days, last, now, cfg, state)
if last == nil or now > last then
last = now
end
end
return days
end

local t0 = ts(2026, 10, 9, 12, 0, 0)
check("10 s d'utilisation = 10 s", run(base, seq(t0, 11))["2026-10-09"], 10)

d = run(base, seq(ts(2026, 10, 9, 23, 59, 58), 6))
check("passage de minuit : avant", d["2026-10-09"], 2)
check("passage de minuit : après", d["2026-10-10"], 3)

check("veille de 10 min comptée en entier", run(base, { t0, t0 + 600 })["2026-10-09"], 600)

d = run(base, { ts(2026, 10, 9, 22, 0, 0), ts(2026, 10, 10, 6, 0, 0) })
check("nuit entière : 1 h comptée le soir", d["2026-10-09"], 3600)
check("nuit entière : rien le lendemain", d["2026-10-10"], nil)

d = run(base, { ts(2026, 10, 9, 23, 30, 0), ts(2026, 10, 10, 0, 30, 0) })
check("veille à cheval sur minuit : avant", d["2026-10-09"], 1800)
check("veille à cheval sur minuit : après", d["2026-10-10"], 1800)

d = run({ normal_gap = 5, sleep_limit = 0, settle_time = 60, day_offset = 0 }, join(seq(t0, 11), { t0 + 10 + 600 }))
check("sleep_limit = 0 : secondes normales comptées, veille ignorée", d["2026-10-09"], 10)

d = run({ normal_gap = 5, sleep_limit = 86400, settle_time = 60, day_offset = 0 }, { ts(2026, 10, 9, 22, 0, 0), ts(2026, 10, 10, 6, 0, 0) })
check("sleep_limit très grand : 2 h le soir", d["2026-10-09"], 7200)
check("sleep_limit très grand : 6 h le matin", d["2026-10-10"], 6 * 3600)

d = run({ normal_gap = 5, sleep_limit = 3600, settle_time = 60, day_offset = -3600 }, seq(ts(2026, 10, 10, 0, 30, 0), 4))
check("décalage de jour : 00:30 compte pour la veille", d["2026-10-09"], 3)

local days = {}
check("même seconde : rien", counter.advance(days, 100, 100, base), false)
check("horloge qui recule : rien", counter.advance(days, 100, 90, base), false)
check("premier appel (pas d'instant précédent) : rien", counter.advance(days, nil, 100, base), false)
check("temps ajouté : renvoie true", counter.advance({}, 100, 101, base), true)
check("écart au-delà du budget épuisé : renvoie false", counter.advance({}, 0, 7200, base, { budget = 3600 }), false)

-- ------------------------------------------------------------
-- Budget de veille PAR ÉPISODE (et non par écart), avec 65 minutes
-- ------------------------------------------------------------
local cfg65 = { normal_gap = 5, sleep_limit = 3900, settle_time = 60, day_offset = 0 }

-- La chronologie réelle relevée dans le journal Windows (heure de Paris) :
-- veille à 18:59:09, réveil technique à 20:04:15 pour hiberner, reprise le lendemain à 11:03:31.
local real = join(
seq(ts(2026, 10, 10, 18, 58, 0), 60),
{ ts(2026, 10, 10, 18, 59, 8), ts(2026, 10, 10, 20, 4, 15), ts(2026, 10, 10, 20, 4, 16), ts(2026, 10, 11, 11, 3, 31) },
seq(ts(2026, 10, 11, 11, 3, 31), 121)
)
d = run(cfg65, real)
check("chronologie réelle : veille de 65 min comptée UNE seule fois (59 + 3900 + 1 + 120)", total(d), 59 + 3900 + 1 + 120)
check("chronologie réelle : l'extinction ne compte pas, le 11 ne reçoit que l'utilisation", d["2026-10-11"], 120)

-- Sans état partagé (ancienne règle : un écart = son propre plafond), la même chronologie comptait 1 h de trop
local days_old, last_old = {}, nil
for _, now in ipairs(real) do
counter.advance(days_old, last_old, now, cfg65)
if last_old == nil or now > last_old then
last_old = now
end
end
check("sans état partagé : l'extinction comptait en trop (ancienne règle)", total(days_old) > total(d) + 3000, true)

local first = ts(2026, 10, 9, 22, 0, 0)
local steps = { first }
for k = 1, 7 do
steps[#steps + 1] = first + 3000 * k
end
check("réveils de maintenance toutes les 50 min : 65 min au total", total(run(cfg65, steps)), 3900)

local t1 = ts(2026, 10, 9, 14, 0, 0)
check("veille 30 min + 2 min d'utilisation + veille 40 min : tout compte",
total(run(cfg65, join({ t1, t1 + 1800 }, seq(t1 + 1800, 121), { t1 + 1800 + 120 + 2400 }))), 1800 + 120 + 2400)
check("moins de 60 s d'utilisation entre deux veilles : budget restant seulement",
total(run(cfg65, join({ t1, t1 + 1800 }, seq(t1 + 1800, 31), { t1 + 1800 + 30 + 4000 }))), 1800 + 30 + 2100)
check("60 s d'utilisation continue : le budget est rendu",
total(run(cfg65, join({ t1, t1 + 3900 }, seq(t1 + 3900, 61), { t1 + 3900 + 60 + 3000 }))), 3900 + 60 + 3000)
check("59 s d'utilisation : le budget n'est pas encore rendu",
total(run(cfg65, join({ t1, t1 + 3900 }, seq(t1 + 3900, 60), { t1 + 3900 + 59 + 3000 }))), 3900 + 59)

-- La frontière entre fonctionnement normal et trou : un écart de 5 s est normal, un écart de 6 s est un trou
local function spaced(start, n, step)
local out = {}
for i = 0, n - 1 do
out[#out + 1] = start + i * step
end
return out
end
check("écarts de 5 s (normal) pendant 60 s : le budget est rendu",
total(run(cfg65, join({ t1, t1 + 3900 }, spaced(t1 + 3900, 13, 5), { t1 + 3900 + 60 + 3000 }))), 3900 + 60 + 3000)
check("écarts de 6 s (des trous) : le budget n'est jamais rendu",
total(run(cfg65, join({ t1, t1 + 3900 }, spaced(t1 + 3900, 13, 6), { t1 + 3900 + 72 + 3000 }))), 3900)

-- une horloge qui recule ne doit pas non plus abîmer l'état conservé entre deux appels
local st_back = { budget = 5, calm = 7 }
counter.advance({}, 100, 90, cfg65, st_back)
check("horloge qui recule : budget de l'état intact", st_back.budget, 5)
check("horloge qui recule : calme de l'état intact", st_back.calm, 7)

-- sans settle_time dans la configuration : 60 s par défaut
local cfg_sans = { normal_gap = 5, sleep_limit = 3900, day_offset = 0 }
check("settle_time absent : 59 s ne rendent pas le budget",
total(run(cfg_sans, join({ t1, t1 + 3900 }, seq(t1 + 3900, 60), { t1 + 3900 + 59 + 3000 }))), 3900 + 59)
check("settle_time absent : 60 s rendent le budget",
total(run(cfg_sans, join({ t1, t1 + 3900 }, seq(t1 + 3900, 61), { t1 + 3900 + 60 + 3000 }))), 3900 + 60 + 3000)

local st = {}
counter.advance({}, 0, 3000, cfg65, st)
check("état : budget consommé", st.budget, 3000)
check("état : fonctionnement normal remis à zéro", st.calm, 0)
counter.advance({}, 3000, 3001, cfg65, st)
check("état : fonctionnement normal compté", st.calm, 1)

d = run(cfg65, { ts(2026, 10, 9, 23, 30, 0), ts(2026, 10, 10, 0, 30, 0) })
check("veille de 65 min à cheval sur minuit : avant", d["2026-10-09"], 1800)
check("veille de 65 min à cheval sur minuit : après", d["2026-10-10"], 1800)

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
