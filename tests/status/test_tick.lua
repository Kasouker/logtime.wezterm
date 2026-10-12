-- tests/status/test_tick.lua : teste le comportement du compteur (plugin/init.lua) : comptage, veille de 65 min,
-- minuit, rechargement, erreurs. Fausse API WezTerm, dossier personnel temporaire.
-- Lancer :   lua5.4 tests/status/test_tick.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]status[/\\]test_tick%.lua$") or "."

local passed, failed = 0, 0
local label = ""
local function check(name, got, want)
	name = label .. name
	if got == want then
		passed = passed + 1
	else
		failed = failed + 1
		print(string.format("ÉCHEC  %s\n         attendu : %s\n         obtenu  : %s", name, tostring(want), tostring(got)))
	end
end

local globals_before = {}
for k in pairs(_G) do
	globals_before[k] = true
end

-- ---- un faux wezterm.GLOBAL aussi difficile que le vrai (voir plugin/init.lua) :
--   * une table lue dans GLOBAL est un objet "Value" qui ne se compare pas à un nombre ;
--   * en mode "wrapped", même les nombres lus sont des objets "Value" (additionnables, jamais comparables) ;
--   * ici, ÉCRIRE une table dans GLOBAL est une erreur : le plugin ne doit garder que des valeurs simples.
local VALUE = {}
VALUE.__index = VALUE
local function raw(x)
	if type(x) == "table" and getmetatable(x) == VALUE then
		return x.__v
	end
	return x
end
VALUE.__add = function(a, b) return raw(a) + raw(b) end
VALUE.__sub = function(a, b) return raw(a) - raw(b) end
VALUE.__mul = function(a, b) return raw(a) * raw(b) end
VALUE.__div = function(a, b) return raw(a) / raw(b) end
VALUE.__unm = function(a) return -raw(a) end
VALUE.__tostring = function(a) return tostring(raw(a)) end
-- pas de __lt ni de __le : comparer un Value à un nombre est une erreur, comme chez toi

local current_mode = "plain"
local function hostile_global(initial)
	local store = {}
	for k, v in pairs(initial or {}) do
		store[k] = v
	end
	return setmetatable({}, {
__index = function(_, k)
local v = store[k]
if type(v) == "table" or (current_mode == "wrapped" and type(v) == "number") then
return setmetatable({ __v = v }, VALUE)
end
return v
end,
__newindex = function(_, k, v)
if type(v) == "table" or type(v) == "function" or type(v) == "userdata" then
error("test : wezterm.GLOBAL n'accepte ici que des valeurs simples (reçu " .. type(v) .. " pour " .. tostring(k) .. ")", 2)
end
store[k] = v
end,
__pairs = function()
			return next, store, nil
		end,
	})
end

local clock = { now = 0 }
local real_time = os.time
os.time = function(t)
	if t then
		return real_time(t)
	end
	return clock.now
end
local function ts(y, mo, d, h, mi, s)
	return real_time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s })
end

-- toute écriture doit rester dans le dossier personnel temporaire
local home = os.tmpname()
os.remove(home)
os.execute("mkdir -p '" .. home .. "'")
local outside = {}
local real_open = io.open
io.open = function(path, mode)
	if mode and (mode:find("w") or mode:find("a") or mode:find("%+")) and path:sub(1, #home) ~= home then
		outside[#outside + 1] = path
	end
	return real_open(path, mode)
end

local ICON = utf8.char(0xF017)
local function fresh()
	os.execute("rm -f '" .. home .. "'/.logtime.json*")
	local logs = { error = {}, info = {} }
	local fake = {
		GLOBAL = hostile_global(),
		home_dir = home,
		log_error = function(m)
			logs.error[#logs.error + 1] = m
		end,
		log_info = function(m)
			logs.info[#logs.info + 1] = m
		end,
	}
	package.loaded["wezterm"] = fake
	local M = assert(loadfile(root .. "/plugin/init.lua"))(root)
	return M, fake, logs
end

local function scenarios()
local t0 = ts(2026, 10, 12, 12, 0, 0)
local M, fake, logs = fresh()
check("le chargement est écrit dans les journaux", #logs.info, 1)
check("version", type(M.version), "string")
clock.now = t0
check("premier appel : 00:00:00", M.tick(nil), ICON .. " 00:00:00")
for i = 1, 10 do
	clock.now = t0 + i
	M.tick(nil)
end
check("10 s : 00:00:10", M.tick(nil), ICON .. " 00:00:10")
clock.now = t0 + 11
M.tick(nil)
check("même seconde, deux appels : une seule seconde comptée", M.tick(nil), ICON .. " 00:00:11")
clock.now = t0 + 11 + 600
check("veille de 10 min comptée : 00:10:11", M.tick(nil), ICON .. " 00:10:11")
check("today_seconds est cohérent", M.today_seconds(), 611)
clock.now = t0 + 11 + 600 + 20000
check("budget de veille partagé et plafonné à 65 min : 01:05:11", M.tick(nil), ICON .. " 01:05:11")

M, fake = fresh()
clock.now = t0
M.tick(nil)
clock.now = t0 + 3900
M.tick(nil)
for i = 1, 60 do
	clock.now = t0 + 3900 + i
	M.tick(nil)
end
clock.now = t0 + 3960 + 3000
check("60 s d'utilisation rendent le budget : 01:56:00", M.tick(nil), ICON .. " 01:56:00")

M, fake = fresh()
clock.now = t0
M.tick(nil)
clock.now = t0 + 3900
M.tick(nil)
for i = 1, 59 do
	clock.now = t0 + 3900 + i
	M.tick(nil)
end
clock.now = t0 + 3959 + 3000
check("59 s ne le rendent pas : 01:05:59", M.tick(nil), ICON .. " 01:05:59")

M, fake = fresh()
local m0 = ts(2026, 10, 12, 23, 59, 58)
local text
for i = 0, 5 do
	clock.now = m0 + i
	text = M.tick(nil)
end
check("minuit : 3 s pour le nouveau jour", text, ICON .. " 00:00:03")

-- rechargement de la config : nouveau chargement du module, même wezterm.GLOBAL
local M2 = assert(loadfile(root .. "/plugin/init.lua"))(root)
clock.now = m0 + 6
check("après rechargement : le comptage continue", M2.tick(nil), ICON .. " 00:00:04")

-- une erreur ne casse pas la barre, et n'est écrite qu'une fois
M, fake, logs = fresh()
clock.now = t0
M.tick(nil)
clock.now = "oups" -- une horloge absurde fait échouer le comptage
local shown = M.tick(nil)
check("erreur : un texte d'alerte est renvoyé", type(shown) == "string" and shown:find("erreur", 1, true) ~= nil, true)
M.tick(nil)
M.tick(nil)
check("erreur : écrite une seule fois dans les journaux", #logs.error, 1)
local foreign = {}
for k in pairs(fake.GLOBAL) do
	if not k:find("^logtime_") then
		foreign[#foreign + 1] = k
	end
end
check("GLOBAL : seulement des clés logtime_*", table.concat(foreign, ","), "")
clock.now = t0 + 5
check("erreur : le comptage reprend dès que l'horloge est normale", M.tick(nil), ICON .. " 00:00:05")
clock.now = "oups"
M.tick(nil)
check("erreur : si elle revient après un passage normal, elle est de nouveau écrite (elle n'est pas masquée)", #logs.error, 2)
clock.now = t0 + 7
M.tick(nil)

-- dossier du plugin introuvable : erreur claire
package.loaded["wezterm"] = { GLOBAL = {}, home_dir = home, plugin = { list = function() return {} end }, config_dir = "/inexistant" }
local ok, err = pcall(function()
	return assert(loadfile(root .. "/plugin/init.lua"))()
end)
check("sans dossier transmis ni autre piste : erreur claire", ok == false and tostring(err):find("introuvable", 1, true) ~= nil, true)

end

current_mode = "plain"
label = ""
scenarios()
current_mode = "wrapped"
label = "[nombres Value] "
scenarios()

check("aucune écriture en dehors du dossier personnel", #outside, 0)
local leaked = {}
for k in pairs(_G) do
	if not globals_before[k] then
		leaked[#leaked + 1] = k
	end
end
check("aucune variable globale ajoutée", table.concat(leaked, ","), "")
os.execute("rm -rf '" .. home .. "'")

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
