-- tests/pages/test_settings_theme.lua : teste la question sur les couleurs du thème dans la page de personnalisation :
-- la ligne de question, les touches y et n, la palette du thème, l'enregistrement, et la notification au chargement.
-- Fausse API WezTerm. Lancer :   lua5.4 tests/pages/test_settings_theme.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]pages[/\\]test_settings_theme%.lua$") or "."

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
local settings_page = load_module("pages/settings_page")
local palette = load_module("color/palette")
local convert = load_module("color/convert")
local layout = load_module("calendar/layout")
local store = load_module("settings/store")
local platform = load_module("system/platform")
local fr = load_module("i18n/fr")
local en = load_module("i18n/en")

local homes = {}
local passed, failed = 0, 0
local function check(name, got, want)
if got == want then
passed = passed + 1
else
failed = failed + 1
print(string.format("ÉCHEC  %s\n         attendu : %s\n         obtenu  : %s", name, tostring(want), tostring(got)))
end
end
local function strip(text)
return (text:gsub("\27%[[%?%d;]*%a", ""):gsub("\r", ""))
end
local function lines_of(text)
local out = {}
for line in (text .. "\n"):gmatch("(.-)\n") do
out[#out + 1] = line
end
return out
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

-- le thème : 16 couleurs, l'or du plugin n'y est pas
local THEME = {
"#1E1E1E", "#CC3333", "#33CC33", "#CCCC33", "#3333CC", "#CC33CC", "#33CCCC", "#CCCCCC",
"#555555", "#FF5555", "#55FF55", "#FFFF55", "#5555FF", "#FF55FF", "#55FFFF", "#FFFFFF",
}

local function new_env(opts)
opts = opts or {}
local home = os.tmpname()
os.remove(home)
os.execute("mkdir -p '" .. home .. "'")
homes[#homes + 1] = home
local w = { events = {}, logs = { error = {}, info = {} }, panes = {}, spawned = {}, timers = {}, GLOBAL = opts.global or {} }
w.log_error = function(m) w.logs.error[#w.logs.error + 1] = m end
w.log_info = function(m) w.logs.info[#w.logs.info + 1] = m end
w.action = {
EmitEvent = function(name) return { kind = "EmitEvent", name = name } end,
ActivateKeyTable = function(t) return { kind = "ActivateKeyTable", args = t } end,
SendKey = function(t) return { kind = "SendKey", args = t } end,
CloseCurrentTab = function(t) return { kind = "CloseCurrentTab", args = t } end,
PopKeyTable = { kind = "PopKeyTable" },
}
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
w.next_id = 900
function w.new_pane()
w.next_id = w.next_id + 1
local tab = {}
function tab:activate() end
local pane = { id = w.next_id, injected = {}, dims = { viewport_rows = opts.rows or 40, cols = opts.cols or 120 }, the_tab = tab }
function pane:pane_id() return self.id end
function pane:get_dimensions() return self.dims end
function pane:inject_output(text) self.injected[#self.injected + 1] = text end
function pane:tab() return self.the_tab end
w.panes[pane.id] = pane
return pane
end
local env = { w = w, home = home, path = opts.path or (home .. "/.logtime_settings.json"), cfg = { gradient_color = opts.color }, applied = {}, consent = opts.consent, toasts = {} }
local win = { performed = {} }
function win:perform_action(action, pane) self.performed[#self.performed + 1] = action.kind end
if not opts.no_toast then
function win:toast_notification(title, message, url, timeout) env.toasts[#env.toasts + 1] = { title = title, message = message, timeout = timeout } end
end
function win:mux_window()
return { spawn_tab = function(_, spec)
local pane = w.new_pane()
w.spawned[#w.spawned + 1] = pane
return pane.the_tab, pane, nil
end }
end
env.window = win
local ctx = {
wezterm = w,
G = w.GLOBAL,
num = function(v) return v end,
cfg = function() return env.cfg end,
labels = function() return opts.labels or fr end,
blocker_args = function() return platform.blocker_args("windows") end,
store = store,
settings_path = function() return env.path end,
apply = function(changes)
env.applied[#env.applied + 1] = changes
for key, value in pairs(changes) do
env.cfg[key] = value
end
if changes.theme_colors ~= nil then
env.consent = changes.theme_colors
end
end,
refresh_calendar = function() end,
}
if not opts.no_consent then
ctx.consent = function() return env.consent end
ctx.settings_key = function() return opts.key or "F4" end
ctx.palette = function()
if env.consent == true then
if opts.theme_missing then
return { kind = "classic", unavailable = "pas de thème" }
end
return { kind = "theme", colors = THEME }
end
return { kind = "classic" }
end
end
env.page = settings_page.create(ctx)
env.table = env.page.key_table()
return env
end
local function press(env, key, pane)
for _, binding in ipairs(env.table) do
if binding.key == key then
for _, handler in ipairs(env.w.events[binding.action.name] or {}) do
if handler(env.window, pane) == false then
return
end
end
return
end
end
error("touche inconnue : " .. key)
end
local function frame_of(pane)
return pane.injected[#pane.injected]
end
local function shown(pane)
return strip(frame_of(pane))
end
local function line_containing(pane, text)
for _, line in ipairs(lines_of(shown(pane))) do
if line:find(text, 1, true) then
return line
end
end
end
local function chosen(pane)
local n = shown(pane):match("Choix : (%d+)") or shown(pane):match("Choice: (%d+)")
return tonumber(n)
end
local function open(opts)
local env = new_env(opts)
env.page.open(env.window, env.w.new_pane())
env.pane = env.w.spawned[1]
env.w.GLOBAL.logtime_settings_pane = env.pane.id
return env
end
local function cleanup()
for _, d in ipairs(homes) do
os.execute("rm -rf '" .. d .. "'")
end
end
local function has_colors(pane, list)
local raw = frame_of(pane)
for _, color in ipairs(list) do
if not raw:find(convert.bg(color), 1, true) then
return false
end
end
return true
end
local function has_any_color(pane, list)
local raw = frame_of(pane)
for _, color in ipairs(list) do
if raw:find(convert.bg(color), 1, true) then
return true
end
end
return false
end

-- ============================================================
-- les touches
-- ============================================================
local e = new_env({})
local keys = {}
for i, binding in ipairs(e.table) do
keys[i] = binding.key
end
check("avec la question : quatorze touches, y et n à la fin", #keys == 14 and keys[13] == "y" and keys[14] == "n", true)
check("les événements de y et n ont des noms fixes", e.table[13].action.name == "logtime-settings-y" and e.table[14].action.name == "logtime-settings-n", true)
e = new_env({ no_consent = true })
check("sans la question : douze touches, comme avant", #e.table, 12)

-- ============================================================
-- la ligne de question (ligne 4)
-- ============================================================
local function consent_line(opts)
local env = open(opts)
return lines_of(shown(env.pane))
end
local function row4(opts)
local env = open(opts)
local ls = lines_of(shown(env.pane))
for i, line in ipairs(ls) do
if line:find("Logtime : ", 1, true) or line:find("Settings", 1, true) then
return ls[i + 3]
end
end
end
check("pas encore répondu : la question et ses deux réponses", row4({}):gsub("^%s+", ""), "Couleurs de ton thème ?   y : oui   n : non")
check("répondu oui, thème lu : la réponse et la commande pour changer", (row4({ consent = true }):gsub("^%s+", "")), "Couleurs de ton thème : oui   (n : palette classique)")
check("répondu non : la réponse et la commande pour changer", (row4({ consent = false }):gsub("^%s+", "")), "Palette classique   (y : couleurs de ton thème)")
check("répondu oui mais thème introuvable : le dit", (row4({ consent = true, theme_missing = true }):gsub("^%s+", "")), "Thème introuvable : palette classique (n : arrêter)")
check("en anglais : la question", (row4({ labels = en }):gsub("^%s+", "")), "Use your theme's colors?   y: yes   n: no")
check("en anglais : oui", (row4({ labels = en, consent = true }):gsub("^%s+", "")), "Theme colors: on   (n: classic palette)")
check("en anglais : non", (row4({ labels = en, consent = false }):gsub("^%s+", "")), "Classic palette   (y: use your theme colors)")
check("en anglais : thème introuvable", (row4({ labels = en, consent = true, theme_missing = true }):gsub("^%s+", "")), "Theme not found: classic palette (n: stop)")
local narrow_ok = true
for _, labels in ipairs({ fr, en }) do
for _, line in ipairs({ labels.consent_ask, labels.consent_yes, labels.consent_no, labels.consent_unavailable }) do
if layout.visible_width("  " .. line) > settings_page.GRID_WIDTH then
narrow_ok = false
end
end
end
check("chaque ligne de question tient dans la largeur du tableau (57)", narrow_ok, true)
e = open({ no_consent = true })
check("sans la question : la ligne 4 est vide, comme avant", select(2, shown(e.pane):gsub("Couleurs de ton thème", "")), 0)
check("toujours 23 lignes avec la question", #(settings_page.render({ index = 1, consent_line = "x", message = 3 }, fr)), 23)

-- ============================================================
-- la palette du thème
-- ============================================================
e = open({ consent = true })
check("palette du thème : les 16 couleurs du thème sont dessinées", has_colors(e.pane, THEME), true)
check("palette du thème : aucune couleur de la palette classique", has_any_color(e.pane, palette.COLORS), false)
check("palette du thème : les noms sont ceux du thème (Noir, Rouge, ..., Blanc vif)", (function()
local text = shown(e.pane)
for _, name in ipairs({ "Noir", "Rouge", "Vert", "Jaune", "Bleu", "Magenta", "Cyan", "Blanc", "Gris", "Rouge vif", "Blanc vif" }) do
if not text:find(name, 1, true) then
return false
end
end
return true
end)(), true)
check("palette du thème : pas les noms de la palette classique (Citron, Turquoise)", shown(e.pane):find("Citron", 1, true) == nil and shown(e.pane):find("Turquoise", 1, true) == nil, true)
e = open({ consent = true, labels = en })
check("palette du thème en anglais : noms anglais", shown(e.pane):find("Lt Magenta", 1, true) ~= nil and shown(e.pane):find("Red", 1, true) ~= nil, true)
e = open({ consent = false })
check("palette classique : les 16 couleurs classiques", has_colors(e.pane, palette.COLORS), true)
check("palette classique : aucune couleur du thème", has_any_color(e.pane, { THEME[2], THEME[3], THEME[5] }), false)
e = open({})
check("avant d'avoir répondu : la palette classique", has_colors(e.pane, palette.COLORS), true)
e = open({ consent = true, theme_missing = true })
check("thème introuvable : la palette classique est utilisée", has_colors(e.pane, palette.COLORS), true)

-- ---- le choix de départ dans la palette du thème
e = open({ consent = true, color = "#CC3333" })
check("couleur du thème déjà enregistrée : choix = sa case (2)", chosen(e.pane), 2)
e = open({ consent = true, color = "#DD4444" })
check("couleur proche : la case de teinte la plus proche (2)", chosen(e.pane), 2)
e = open({ consent = true })
check("aucune couleur enregistrée : la case la plus proche de l'or (le jaune, 4)", chosen(e.pane), 4)
e = open({ consent = true, color = "#C9AB6B" })
check("l'or du plugin enregistré : la case jaune du thème (4), signalé comme personnalisé", chosen(e.pane) == 4 and shown(e.pane):find("(personnalisée)", 1, true) ~= nil, true)
e = open({ consent = true, color = "#CC3333" })
check("couleur du thème enregistrée : pas « personnalisée »", shown(e.pane):find("personnalisée", 1, true), nil)
check("la ligne « Choix » donne le nom et la couleur du thème", line_containing(e.pane, "Choix"):find("Choix : 2 Rouge (#CC3333)", 1, true) ~= nil, true)

-- ---- enregistrer un choix dans la palette du thème
e = open({ consent = true })
press(e, "j", e.pane)
check("la navigation fonctionne dans la palette du thème (4 puis 8)", chosen(e.pane), 8)
press(e, "k", e.pane)
press(e, "h", e.pane)
press(e, "h", e.pane)
check("de 4 : deux fois gauche = 2", chosen(e.pane), 2)
press(e, "Enter", e.pane)
check("Entrée enregistre la couleur du THÈME (pas celle de la palette classique)", read(e.path), '{\n  "gradient_color": "#CC3333"\n}\n')
check("... et l'applique", e.applied[1].gradient_color, "#CC3333")
press(e, "d", e.pane)
check("d enregistre toujours l'or du plugin", read(e.path), '{\n  "gradient_color": "#C9AB6B"\n}\n')
check("d : la case choisie est la plus proche de l'or dans le thème (4)", chosen(e.pane), 4)

-- ============================================================
-- répondre : y et n
-- ============================================================
e = open({})
press(e, "y", e.pane)
check("y : « theme_colors »: true est enregistré", read(e.path), '{\n  "theme_colors": true\n}\n')
check("y : appliqué tout de suite", #e.applied == 1 and e.applied[1].theme_colors == true, true)
check("y : le message de réponse enregistrée", shown(e.pane):find("✓ Réponse enregistrée.", 1, true) ~= nil, true)
check("y : la palette du thème est affichée", has_colors(e.pane, THEME) and not has_any_color(e.pane, palette.COLORS), true)
check("y : la ligne de question dit la nouvelle réponse et la commande inverse", line_containing(e.pane, "(n : palette classique)") ~= nil, true)
check("y : aucune erreur", #e.w.logs.error, 0)
press(e, "n", e.pane)
check("n : « theme_colors »: false est enregistré", read(e.path), '{\n  "theme_colors": false\n}\n')
check("n : la palette classique revient", has_colors(e.pane, palette.COLORS) and not has_any_color(e.pane, { THEME[2], THEME[5] }), true)
check("n : la ligne de question dit la commande pour revenir", line_containing(e.pane, "(y : couleurs de ton thème)") ~= nil, true)
check("n : la copie de sécurité garde l'état précédent", read(e.path .. ".bak"), '{\n  "theme_colors": true\n}\n')
press(e, "y", e.pane)
check("changer d'avis : y à nouveau", read(e.path), '{\n  "theme_colors": true\n}\n')
check("trois réponses appliquées", #e.applied, 3)
-- la couleur enregistrée reste, la case choisie suit dans la nouvelle palette
e = open({ color = "#CC3333" })
check("couleur du thème enregistrée mais palette classique : la case rouge (1)", chosen(e.pane), 1)
press(e, "y", e.pane)
check("après y : la case du thème qui porte cette couleur (2)", chosen(e.pane), 2)
press(e, "n", e.pane)
check("après n : retour à la case classique la plus proche (1)", chosen(e.pane), 1)
-- les autres réglages sont gardés
e = open({})
write(e.path, '{"max_months": 4, "gradient_color": "#CC3333"}')
press(e, "y", e.pane)
check("y garde les autres réglages du fichier", read(e.path), '{\n  "max_months": 4,\n  "gradient_color": "#CC3333",\n  "theme_colors": true\n}\n')
-- fichier illisible
e = open({})
write(e.path, "{ illisible")
press(e, "n", e.pane)
check("y/n sur un fichier illisible : le nouveau fichier est bon", read(e.path), '{\n  "theme_colors": false\n}\n')
check("y/n sur un fichier illisible : l'ancien est mis de côté", (function()
local p = io.popen("ls -1A '" .. e.home .. "'")
for name in p:lines() do
if name:find(".corrupt-", 1, true) then
p:close()
return read(e.home .. "/" .. name)
end
end
p:close()
end)(), "{ illisible")
-- échec d'enregistrement
e = open({ path = "/tmp/dossier_qui_nexiste_pas_logtime/sous/.logtime_settings.json" })
press(e, "y", e.pane)
check("échec : le message d'échec", shown(e.pane):find("✗ Enregistrement impossible", 1, true) ~= nil, true)
check("échec : rien n'est appliqué", #e.applied, 0)
check("échec : la palette ne change pas", has_colors(e.pane, palette.COLORS), true)
check("échec : l'erreur est dans les journaux", #e.w.logs.error == 1 and e.w.logs.error[1]:find("enregistrement des réglages impossible", 1, true) ~= nil, true)
-- un déplacement efface le message de réponse
e = open({})
press(e, "y", e.pane)
press(e, "l", e.pane)
check("un déplacement efface le message de réponse", shown(e.pane):find("Réponse enregistrée", 1, true), nil)
-- sans la question, y et n n'existent pas
e = open({ no_consent = true })
check("sans la question, la touche y n'existe pas", pcall(press, e, "y", e.pane), false)

-- ============================================================
-- la notification au chargement de la config
-- ============================================================
e = new_env({})
e.page.on_config_loaded(e.window, e.w.new_pane())
check("pas encore répondu : une notification", #e.toasts, 1)
check("la notification a pour titre logtime", e.toasts[1].title, "logtime")
check("la notification dit où répondre (F4) et comment (y / n)", e.toasts[1].message:find("F4", 1, true) ~= nil and e.toasts[1].message:find("y (oui)", 1, true) ~= nil and e.toasts[1].message:find("n (non)", 1, true) ~= nil, true)
check("la notification reste affichée un moment (20 s)", e.toasts[1].timeout, 20000)
e.page.on_config_loaded(e.window, e.w.new_pane())
check("une seule fois par session", #e.toasts, 1)
local shared = {}
local first = new_env({ global = shared })
first.page.on_config_loaded(first.window, first.w.new_pane())
local second = new_env({ global = shared })
second.page.on_config_loaded(second.window, second.w.new_pane())
check("une nouvelle évaluation de la config dans la même session : pas de seconde notification", #first.toasts + #second.toasts, 1)
local fresh = new_env({})
fresh.page.on_config_loaded(fresh.window, fresh.w.new_pane())
check("une nouvelle session de WezTerm : la notification revient", #fresh.toasts, 1)
for _, answered in ipairs({ true, false }) do
local env2 = new_env({ consent = answered })
env2.page.on_config_loaded(env2.window, env2.w.new_pane())
check("déjà répondu (" .. tostring(answered) .. ") : aucune notification", #env2.toasts, 0)
end
e = new_env({ key = "F5" })
e.page.on_config_loaded(e.window, e.w.new_pane())
check("la notification nomme la touche choisie (F5)", e.toasts[1].message:find("F5", 1, true) ~= nil and e.toasts[1].message:find("F4", 1, true) == nil, true)
e = new_env({ labels = en })
e.page.on_config_loaded(e.window, e.w.new_pane())
check("la notification en anglais", e.toasts[1].message:find("Use your theme's colors?", 1, true) ~= nil, true)
e = new_env({ no_consent = true })
e.page.on_config_loaded(e.window, e.w.new_pane())
check("sans la question : aucune notification", #e.toasts, 0)
e = new_env({ no_toast = true })
check("une fenêtre sans notifications : aucun plantage", pcall(e.page.on_config_loaded, e.window, e.w.new_pane()), true)
check("le journal note la notification", (function()
local env2 = new_env({})
env2.page.on_config_loaded(env2.window, env2.w.new_pane())
return #env2.w.logs.info == 1 and env2.w.logs.info[1]:find("notification", 1, true) ~= nil
end)(), true)

cleanup()
local leaked = {}
for k in pairs(_G) do
if not globals_before[k] then
leaked[#leaked + 1] = k
end
end
check("aucune variable globale ajoutée", table.concat(leaked, ","), "")

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
