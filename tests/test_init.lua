-- tests/test_init.lua : teste plugin/init.lua avec une fausse API WezTerm. Lancer :   lua5.4 tests/test_init.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]test_init%.lua$") or "."

-- Horloge simulée : os.time() sans argument renvoie clock.now
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

local passed, failed = 0, 0
local function check(name, got, want)
	if got == want then
		passed = passed + 1
	else
		failed = failed + 1
		print(string.format("ÉCHEC  %s\n         attendu : %s\n         obtenu  : %s", name, tostring(want), tostring(got)))
	end
end

-- Fausse API WezTerm. GLOBAL se comporte comme le vrai : les tables sont COPIÉES à la lecture et à l'écriture,
-- donc modifier une table lue sans la réaffecter ne change rien.
local function deep_copy(v)
if type(v) ~= "table" then
return v
end
local out = {}
for k, x in pairs(v) do
out[k] = deep_copy(x)
end
return out
end

local function new_wezterm(opts)
opts = opts or {}
local store = opts.store or {}
local w = {
store = store,
GLOBAL = setmetatable({}, {
__index = function(_, k)
return deep_copy(store[k])
end,
__newindex = function(_, k, v)
store[k] = deep_copy(v)
end,
}),
config_dir = opts.config_dir,
home_dir = "/tmp",
logs = { error = {}, info = {} },
plugin = {
list = function()
return opts.plugins or {}
end,
},
}
function w.log_error(m)
w.logs.error[#w.logs.error + 1] = m
end
function w.log_info(m)
w.logs.info[#w.logs.info + 1] = m
end
return w
end

local function load_plugin(opts, given)
local w = new_wezterm(opts)
package.loaded["wezterm"] = w
local chunk = assert(loadfile(root .. "/plugin/init.lua"))
return chunk(given), w
end

local globals_before = {}
for k in pairs(_G) do
globals_before[k] = true
end
local path_before = package.path

-- ============================================================
-- Retrouver le dossier du plugin
-- ============================================================
local M, w = load_plugin({}, root)
check("dossier transmis par le chargeur : le plugin se charge", type(M.tick), "function")
check("une ligne de chargement dans les journaux", #w.logs.info, 1)
check("la version est dans le journal", w.logs.info[1]:find(M.version, 1, true) ~= nil, true)
check("le dossier est dans le journal", w.logs.info[1]:find(root, 1, true) ~= nil, true)

M = load_plugin({ plugins = { { plugin_dir = "/nimporte/quoi" }, { plugin_dir = root } } }, nil)
check("sans dossier transmis : trouvé par la liste des plugins de WezTerm", type(M.tick), "function")

local tmp = os.tmpname()
os.remove(tmp)
os.execute("mkdir -p " .. tmp)
os.execute("ln -s " .. io.popen("cd " .. root .. " && pwd"):read("*l") .. " " .. tmp .. "/logtime.wezterm")
M = load_plugin({ config_dir = tmp }, nil)
check("sans autre piste : trouvé dans le dossier de config", type(M.tick), "function")
os.execute("rm -rf " .. tmp)

local ok, err = pcall(load_plugin, { config_dir = "/inexistant" }, "/inexistant")
check("aucune piste : erreur", ok, false)
check("aucune piste : message clair", tostring(err):find("introuvable", 1, true) ~= nil, true)
check("aucune piste : le message dit ce que le dossier doit contenir", tostring(err):find("counter.lua", 1, true) ~= nil, true)

-- ============================================================
-- Le compteur
-- ============================================================
M, w = load_plugin({}, root)
clock.now = ts(2026, 10, 12, 10, 0, 0)
local text = M.tick(nil)
check("premier appel : 00:00:00", text, utf8.char(0xF017) .. " 00:00:00")
for _ = 1, 5 do
clock.now = clock.now + 1
text = M.tick(nil)
end
check("5 s plus tard : 00:00:05", text, utf8.char(0xF017) .. " 00:00:05")
check("today_seconds : 5", M.today_seconds(), 5)

-- plusieurs fenêtres appellent tick la même seconde : aucun double comptage
M.tick(nil)
M.tick(nil)
M.tick(nil)
check("appels répétés dans la même seconde : rien de plus", M.today_seconds(), 5)

-- un rechargement de la configuration recrée le plugin mais garde GLOBAL : le comptage continue
local store = w.store
M = load_plugin({ store = store }, root)
clock.now = clock.now + 1
check("après un rechargement de la config : le total continue (6 s)", M.tick(nil), utf8.char(0xF017) .. " 00:00:06")

-- GLOBAL copie les tables : le plugin doit réaffecter, sinon rien ne serait gardé
check("les journées sont bien dans GLOBAL après réaffectation", store.logtime_days ~= nil and next(store.logtime_days) ~= nil, true)

-- ------------------------------------------------------------
-- La chronologie réelle relevée dans le journal Windows (veille 65 min comptée une seule fois)
-- ------------------------------------------------------------
M = load_plugin({}, root)
local function tick_at(t)
clock.now = t
M.tick(nil)
end
for i = 0, 59 do
tick_at(ts(2026, 10, 10, 18, 58, 0) + i)
end
for _, t in ipairs({ ts(2026, 10, 10, 18, 59, 8), ts(2026, 10, 10, 20, 4, 15), ts(2026, 10, 10, 20, 4, 16), ts(2026, 10, 11, 11, 3, 31) }) do
tick_at(t)
end
for i = 0, 120 do
tick_at(ts(2026, 10, 11, 11, 3, 31) + i)
end
clock.now = ts(2026, 10, 10, 23, 0, 0)
check("chronologie réelle, le 10 : travail + veille de 65 min, sans l'extinction (59 + 3900 + 1)", M.today_seconds(), 59 + 3900 + 1)
clock.now = ts(2026, 10, 11, 11, 5, 31)
check("chronologie réelle, le 11 : seulement l'utilisation (120)", M.today_seconds(), 120)

-- Deux veilles séparées par une vraie reprise (plus de 60 s d'utilisation) : chacune compte en entier
M = load_plugin({}, root)
local base_t = ts(2026, 10, 9, 14, 0, 0)
tick_at(base_t)
tick_at(base_t + 1800) -- première veille : 30 min
for i = 1, 120 do
	tick_at(base_t + 1800 + i) -- 2 min d'utilisation continue : le budget de veille est rendu
end
tick_at(base_t + 1800 + 120 + 2400) -- seconde veille : 40 min
clock.now = ts(2026, 10, 9, 23, 0, 0)
check("deux veilles séparées par une vraie reprise : tout compte (1800 + 120 + 2400)", M.today_seconds(), 1800 + 120 + 2400)

-- Une horloge qui recule ne perturbe pas le comptage : le dernier instant reste le plus récent vu
M = load_plugin({}, root)
local c0 = ts(2026, 10, 9, 15, 0, 0)
tick_at(c0)
tick_at(c0 + 20)
tick_at(c0 + 10) -- l'horloge a reculé
tick_at(c0 + 21)
clock.now = ts(2026, 10, 9, 23, 0, 0)
check("horloge qui recule : seulement le temps réellement écoulé (21 s, pas 31)", M.today_seconds(), 21)

-- ------------------------------------------------------------
-- Une erreur ne casse jamais la barre
-- ------------------------------------------------------------
M, w = load_plugin({}, root)
clock.now = ts(2026, 10, 12, 10, 0, 0)
M.tick(nil)
w.store.logtime_days = "abîmé" -- état corrompu : le comptage va échouer
clock.now = clock.now + 1
local broken = M.tick(nil)
check("état corrompu : tick renvoie un texte au lieu de planter", type(broken), "string")
check("état corrompu : le texte parle d'erreur", broken:find("erreur", 1, true) ~= nil, true)
check("état corrompu : une ligne dans les journaux", #w.logs.error, 1)
for _ = 1, 5 do
	clock.now = clock.now + 1
	M.tick(nil)
end
check("état corrompu : l'erreur n'est écrite qu'une fois (pas une par seconde)", #w.logs.error, 1)

-- ============================================================
-- Aucun effet de bord
-- ============================================================
local leaked = {}
for k in pairs(_G) do
	if not globals_before[k] then
		leaked[#leaked + 1] = k
	end
end
check("aucune variable globale ajoutée", table.concat(leaked, ","), "")
check("package.path inchangé", package.path, path_before)
M, w = load_plugin({}, root)
clock.now = ts(2026, 10, 12, 10, 0, 0)
M.tick(nil)
clock.now = clock.now + 3
M.tick(nil)
local foreign = {}
for k in pairs(w.store) do
	if not k:find("^logtime_") then
		foreign[#foreign + 1] = k
	end
end
check("wezterm.GLOBAL : seulement des clés logtime_*", table.concat(foreign, ","), "")

os.time = real_time
print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
