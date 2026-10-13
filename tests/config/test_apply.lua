-- tests/config/test_apply.lua : teste le branchement du plugin sur la configuration de WezTerm (plugin/init.lua :
-- apply_to_config, days_snapshot) avec une fausse API WezTerm aussi difficile que la vraie.
-- Lancer :   lua5.4 tests/config/test_apply.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]config[/\\]test_apply%.lua$") or "."

local globals_before = {}
for k in pairs(_G) do
	globals_before[k] = true
end

-- horloge simulée : mardi 13 octobre 2026, midi
local clock = { now = 0 }
local real_time = os.time
os.time = function(t)
	if t then
		return real_time(t)
	end
	return clock.now
end
local T0 = real_time({ year = 2026, month = 10, day = 13, hour = 12 })

-- toute écriture doit rester dans le dossier personnel temporaire
local homes = {}
local outside = {}
local real_open = io.open
io.open = function(path, mode)
	if mode and (mode:find("w") or mode:find("a") or mode:find("%+")) then
		local inside = false
		for _, home in ipairs(homes) do
			if path:sub(1, #home) == home then
				inside = true
			end
		end
		if not inside then
			outside[#outside + 1] = path
		end
	end
	return real_open(path, mode)
end

local passed, failed = 0, 0
-- Comme WezTerm : émettre un événement appelle les gestionnaires dans l'ordre, jusqu'à ce que l'un renvoie false
local current_w
local function fire(action, window, pane)
	for _, handler in ipairs(current_w.events[action.name] or {}) do
		if handler(window, pane) == false then
			return
		end
	end
end
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

-- ---- un faux wezterm.GLOBAL aussi difficile que le vrai
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

local current_mode = "plain"
local function hostile_global()
	local store = {}
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

local function write(path, text)
	local f = assert(real_open(path, "wb"))
	f:write(text)
	f:close()
end
local function read(path)
	local f = real_open(path, "rb")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text
end
local function strip(text)
	return (text:gsub("\27%[[%?%d;]*%a", ""):gsub("\r", ""))
end

local HISTORY = '{"2026-10-10":15231,"2026-10-11":1900}'

-- ---- l'environnement : dossier personnel temporaire, fausse API WezTerm, plugin chargé
local function new_env(opts)
opts = opts or {}
local home = os.tmpname()
os.remove(home)
os.execute("mkdir -p '" .. home .. "'")
homes[#homes + 1] = home
if opts.file ~= false then
write(home .. "/.logtime.json", opts.file or HISTORY)
end
local w = { logs = { error = {}, info = {} }, events = {}, timers = {}, panes = {}, spawned = {}, GLOBAL = hostile_global(), home_dir = home, target_triple = opts.triple or "x86_64-pc-windows-msvc" }
current_w = w
w.log_error = function(m) w.logs.error[#w.logs.error + 1] = m end
w.log_info = function(m) w.logs.info[#w.logs.info + 1] = m end
w.action = {
	EmitEvent = function(name) return { kind = "EmitEvent", name = name } end,
ActivateKeyTable = function(t) return { kind = "ActivateKeyTable", args = t } end,
SendKey = function(t) return { kind = "SendKey", args = t } end,
CloseCurrentTab = function(t) return { kind = "CloseCurrentTab", args = t } end,
PopKeyTable = { kind = "PopKeyTable" },
}
w.action_callback = function(fn) return { kind = "callback", fn = fn } end
w.on = function(event, handler)
w.events[event] = w.events[event] or {}
table.insert(w.events[event], handler)
end
w.time = { call_after = function(seconds, fn) w.timers[#w.timers + 1] = { seconds = seconds, fn = fn } end }
w.mux = { get_pane = function(id)
local pane = w.panes[id]
if not pane then
error("pane id " .. tostring(id) .. " not found in mux")
end
return pane
end }
w.next_id = 200
function w.new_pane()
w.next_id = w.next_id + 1
local tab = { activated = false }
function tab:activate() self.activated = true end
local pane = { id = w.next_id, injected = {}, dims = { viewport_rows = 40, cols = 120 }, the_tab = tab }
function pane:pane_id() return self.id end
function pane:get_dimensions() return self.dims end
function pane:inject_output(text) self.injected[#self.injected + 1] = text end
function pane:tab() return self.the_tab end
w.panes[pane.id] = pane
return pane
end
package.loaded["wezterm"] = w
local env = { home = home, w = w }
function env.load()
return assert(loadfile(root .. "/plugin/init.lua"))(root)
end
function env.window()
local win = { performed = {}, toasts = {} }
function win:perform_action(action, pane) self.performed[#self.performed + 1] = { action = action, pane = pane } end
function win:toast_notification(title, message) self.toasts[#self.toasts + 1] = message end
function win:mux_window()
return { spawn_tab = function(_, spec)
local pane = w.new_pane()
w.spawned[#w.spawned + 1] = { spec = spec, pane = pane }
return pane.the_tab, pane, nil
end }
end
return win
end
env.M = env.load()
return env
end
local function open_binding(config, key)
for _, b in ipairs(config.keys or {}) do
if b.key == key then
return function(window, pane) fire(b.action, window, pane) end
end
end
end
local function page_binding(config, key)
for _, b in ipairs(config.key_tables and config.key_tables.logtime_page or {}) do
if b.key == key then
return function(window, pane) fire(b.action, window, pane) end
end
end
end
local function last_text(pane)
return strip(pane.injected[#pane.injected])
end
local function cleanup(env)
os.execute("rm -rf '" .. env.home .. "'")
end

local function scenarios()
-- ============================================================
-- le branchement
-- ============================================================
clock.now = T0
local e = new_env()
local config = { keys = { { key = "d", mods = "CTRL|SHIFT", action = "split" } } }
local returned = e.M.apply_to_config(config)
check("apply : renvoie la même configuration", returned, config)
check("apply : ses touches sont ajoutées à la suite des tiennes", #config.keys == 2 and config.keys[1].key == "d" and config.keys[2].key == "F2", true)
check("apply : la table de touches de la page, avec 8 touches", #config.key_tables.logtime_page, 8)
check("apply : un gestionnaire de redimensionnement", e.w.events["window-resized"] ~= nil and #e.w.events["window-resized"], 1)
check("apply : aucune erreur", #e.w.logs.error, 0)

-- F2 avant même le premier tick : les heures viennent du fichier
local win = e.window()
open_binding(config, "F2")(win, e.w.new_pane())
check("F2 : un onglet est ouvert", #e.w.spawned, 1)
local page_pane = e.w.spawned[1].pane
local text = last_text(page_pane)
check("F2 : le mois en cours est dessiné", text:find("Logtime : Octobre 2026", 1, true) ~= nil, true)
check("F2 : tes heures du 10 octobre (4h13) viennent du fichier", text:find("4h13", 1, true) ~= nil, true)
check("F2 : tes heures du 11 octobre (0h31) viennent du fichier", text:find("0h31", 1, true) ~= nil, true)
check("F2 : sous Windows, l'onglet est gardé ouvert par ping", e.w.spawned[1].spec.args[3], "ping -n 86400 127.0.0.1>nul")
check("F2 : la ligne d'aide est en première ligne", text:match("^(.-)\n"), "  Logtime   ← → ou h l : mois   t : aujourd'hui   r : rafraîchir   q : fermer")
check("F2 : lire les heures n'écrit rien (rien de nouveau à sauvegarder)", read(e.home .. "/.logtime.json"), HISTORY)
check("F2 : aucune erreur", #e.w.logs.error, 0)

-- le temps compté après l'ouverture apparaît au rafraîchissement (r)
clock.now = T0
e.M.tick(nil)
clock.now = T0 + 600
e.M.tick(nil) -- 10 min de veille comptées
page_binding(config, "r")(e.window(), page_pane)
check("r : le temps compté depuis l'ouverture apparaît (0h10 aujourd'hui)", last_text(page_pane):find("0h10", 1, true) ~= nil, true)
check("r : et le total du mois est mis à jour (21 + ... : 4h13 + 0h31 + 0h10 = 4h55)", last_text(page_pane):find("Total du mois : 4h55", 1, true) ~= nil, true)
cleanup(e)

-- sous Linux
e = new_env({ triple = "x86_64-unknown-linux-gnu" })
config = e.M.apply_to_config({})
open_binding(config, "F2")(e.window(), e.w.new_pane())
check("Linux : l'onglet est gardé ouvert par sleep", e.w.spawned[1].spec.args[1], "sh")
cleanup(e)

-- les réglages
e = new_env()
config = e.M.apply_to_config({}, { week_starts_on = "sunday", lang = "en", open_key = "F3", goal_hours = 3 })
check("réglages : la touche choisie (F3) ouvre la page", open_binding(config, "F3") ~= nil and open_binding(config, "F2") == nil, true)
open_binding(config, "F3")(e.window(), e.w.new_pane())
text = last_text(e.w.spawned[1].pane)
check("réglages : en anglais", text:find("Logtime : October 2026", 1, true) ~= nil and text:find("q: close", 1, true) ~= nil, true)
check("réglages : la semaine commence le dimanche", text:find("Sun%s+Mon") ~= nil, true)
check("réglages : objectif de 3 h atteint 1 jour (le 10)", text:find("Goal reached : 1 d", 1, true) ~= nil, true)
cleanup(e)

e = new_env()
config = e.M.apply_to_config({}, { lang = "xx" })
open_binding(config, "F2")(e.window(), e.w.new_pane())
check("langue inconnue : retour au français", last_text(e.w.spawned[1].pane):find("Octobre 2026", 1, true) ~= nil, true)
check("langue inconnue : pas d'erreur", #e.w.logs.error, 0)
cleanup(e)

-- le décalage de journée (day_offset) décide quel jour est « aujourd'hui » (l'étoile)
e = new_env()
config = e.M.apply_to_config({}, { day_offset = 86400 })
open_binding(config, "F2")(e.window(), e.w.new_pane())
text = last_text(e.w.spawned[1].pane)
check("day_offset d'un jour : l'étoile est sur le 14", text:find("*14", 1, true) ~= nil and text:find("*13", 1, true) == nil, true)
cleanup(e)
e = new_env()
config = e.M.apply_to_config({})
open_binding(config, "F2")(e.window(), e.w.new_pane())
text = last_text(e.w.spawned[1].pane)
check("sans décalage : l'étoile est sur le 13", text:find("*13", 1, true) ~= nil and text:find("*14", 1, true) == nil, true)
cleanup(e)

-- une erreur ne casse jamais la configuration
e = new_env()
local ok, result = pcall(e.M.apply_to_config, nil)
check("configuration absente : pas de plantage", ok, true)
check("configuration absente : renvoie nil", result, nil)
check("configuration absente : l'erreur est journalisée", #e.w.logs.error == 1 and e.w.logs.error[1]:find("apply_to_config a échoué", 1, true) ~= nil, true)
cleanup(e)

e = new_env()
config = e.M.apply_to_config({})
check("configuration vide : complétée", #config.keys == 1 and config.key_tables.logtime_page ~= nil, true)
e.M.apply_to_config(config)
check("appliqué deux fois : pas de plantage, la touche en double est signalée", #config.keys == 2 and #e.w.logs.error == 1 and e.w.logs.error[1]:find("F2", 1, true) ~= nil, true)
cleanup(e)

-- fichier abîmé : la page s'ouvre quand même (mois vide), le fichier est mis de côté
e = new_env({ file = '{"2026-10-10":152' })
config = e.M.apply_to_config({})
ok = pcall(open_binding(config, "F2"), e.window(), e.w.new_pane())
text = last_text(e.w.spawned[1].pane)
check("fichier abîmé : la page s'ouvre", ok and #e.w.spawned == 1, true)
check("fichier abîmé : mois vide", text:find("Total du mois : 0h00", 1, true) ~= nil, true)
check("fichier abîmé : une seule erreur dans les journaux (le fichier mis de côté)", #e.w.logs.error, 1)
cleanup(e)

-- ============================================================
-- days_snapshot
-- ============================================================
e = new_env()
local snapshot = e.M.days_snapshot()
check("days_snapshot : les heures du fichier", snapshot["2026-10-10"] == 15231 and snapshot["2026-10-11"] == 1900, true)
snapshot["2026-10-10"] = 1
check("days_snapshot : c'est une copie (la modifier ne change rien)", e.M.days_snapshot()["2026-10-10"], 15231)
clock.now = T0
e.M.tick(nil)
clock.now = T0 + 60
e.M.tick(nil)
check("days_snapshot : le temps compté depuis est inclus", e.M.days_snapshot()["2026-10-13"], 60)
cleanup(e)

-- ============================================================
-- effets de bord
-- ============================================================
e = new_env()
config = e.M.apply_to_config({})
open_binding(config, "F2")(e.window(), e.w.new_pane())
local foreign = {}
for k in pairs(e.w.GLOBAL) do
if not k:find("^logtime_") then
foreign[#foreign + 1] = k
end
end
check("wezterm.GLOBAL : seulement des clés logtime_*", table.concat(foreign, ","), "")
cleanup(e)
end

current_mode = "plain"
label = ""
scenarios()
current_mode = "wrapped"
label = "[nombres Value] "
scenarios()

check("aucune écriture en dehors des dossiers temporaires", #outside, 0)
local leaked = {}
for k in pairs(_G) do
if not globals_before[k] then
leaked[#leaked + 1] = k
end
end
check("aucune variable globale ajoutée", table.concat(leaked, ","), "")

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
