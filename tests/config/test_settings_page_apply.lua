-- tests/config/test_settings_page_apply.lua : teste la page de personnalisation BRANCHÉE sur le vrai plugin/init.lua :
-- la touche F4, le choix d'une couleur enregistré dans le fichier de réglages, appliqué tout de suite au calendrier
-- (ouvert ou non), conservé après un rechargement. Fausse API WezTerm.
-- Lancer :   lua5.4 tests/config/test_settings_page_apply.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]config[/\\]test_settings_page_apply%.lua$") or "."

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
clock.now = real_time({ year = 2026, month = 10, day = 13, hour = 12 })

local cache = {}
local function load_module(name)
if not cache[name] then
local chunk = assert(loadfile(root .. "/plugin/logtime/" .. name .. ".lua"))
cache[name] = chunk(load_module)
end
return cache[name]
end
local gradient = load_module("color/gradient")
local convert = load_module("color/convert")
local palette = load_module("color/palette")

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
-- Comme WezTerm : émettre un événement appelle les gestionnaires dans l'ordre, jusqu'à ce que l'un renvoie false
local current_w
local function fire(action, window, pane)
	for _, handler in ipairs(current_w.events[action.name] or {}) do
		if handler(window, pane) == false then
			return
		end
	end
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
local function strip(text)
	return (text:gsub("\27%[[%?%d;]*%a", ""):gsub("\r", ""))
end

local HISTORY = '{"2026-10-10":15231,"2026-10-11":1900}'
local function new_env(dims)
	dims = dims or { cols = 120, rows = 40 }
	local home = os.tmpname()
	os.remove(home)
	os.execute("mkdir -p '" .. home .. "'")
	homes[#homes + 1] = home
	write(home .. "/.logtime.json", HISTORY)
	local w = { logs = { error = {}, info = {} }, events = {}, timers = {}, panes = {}, spawned = {}, GLOBAL = {}, home_dir = home, target_triple = "x86_64-pc-windows-msvc" }
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
	w.next_id = 700
	function w.new_pane()
		w.next_id = w.next_id + 1
		local tab = {}
		function tab:activate() end
		local pane = { id = w.next_id, injected = {}, dims = { viewport_rows = dims.rows, cols = dims.cols }, the_tab = tab }
		function pane:pane_id() return self.id end
		function pane:get_dimensions() return self.dims end
		function pane:inject_output(text) self.injected[#self.injected + 1] = text end
		function pane:tab() return self.the_tab end
		w.panes[pane.id] = pane
		return pane
	end
	package.loaded["wezterm"] = w
	local env = { home = home, w = w, path = home .. "/.logtime_settings.json" }
	function env.load()
		return assert(loadfile(root .. "/plugin/init.lua"))(root)
	end
	env.win = { performed = {} }
	function env.win:perform_action(action, pane) self.performed[#self.performed + 1] = action end
	function env.win:toast_notification() end
	function env.win:mux_window()
		return { spawn_tab = function(_, spec)
			local pane = w.new_pane()
			w.spawned[#w.spawned + 1] = pane
			return pane.the_tab, pane, nil
		end }
	end
	env.M = env.load()
	return env
end
local function open_key(env, config, key)
	for _, b in ipairs(config.keys or {}) do
		if b.key == key then
			fire(b.action, env.win, env.w.new_pane())
			return true
		end
	end
	return false
end
local function press(env, config, key, pane)
	for _, b in ipairs(config.key_tables.logtime_settings or {}) do
		if b.key == key then
			fire(b.action, env.win, pane)
			return
		end
	end
	error("touche inconnue : " .. key)
end
local function last_frame(pane)
	return pane.injected[#pane.injected]
end
local function plain_lines(pane)
	local out = {}
	for line in (strip(last_frame(pane)) .. "\n"):gmatch("(.-)\n") do
		out[#out + 1] = line
	end
	return table.concat(out, "\n")
end
local function chosen(pane)
	local n = plain_lines(pane):match("Choix : (%d+)") or plain_lines(pane):match("Choice: (%d+)")
	return tonumber(n)
end
local function bg(index)
	return convert.bg(gradient.make({ color = palette.COLORS[index] }).color(15231))
end
local function errors_with(env, text)
	local n = 0
	for _, message in ipairs(env.w.logs.error) do
		if message:find(text, 1, true) then
			n = n + 1
		end
	end
	return n
end
local function cleanup()
	for _, d in ipairs(homes) do
		os.execute("rm -rf '" .. d .. "'")
	end
end
local GOLD = convert.bg(gradient.make({}).color(15231))

-- ============================================================
-- la touche F4 et la table de touches
-- ============================================================
local e = new_env()
local config = e.M.apply_to_config({})
check("F4 et F2 sont ajoutées", (function()
	local keys = {}
	for _, b in ipairs(config.keys) do
		keys[b.key] = true
	end
	return keys.F2 == true and keys.F4 == true
end)(), true)
check("la table de touches de la personnalisation a quinze touches (dont Tab, y et n)", #config.key_tables.logtime_settings, 15)
check("celle du calendrier est intacte (huit touches)", #config.key_tables.logtime_page, 8)
check("un gestionnaire pour l'ouverture de la personnalisation", #e.w.events["logtime-settings-open"], 1)
check("un gestionnaire pour la touche Entrée", #e.w.events["logtime-settings-Enter"], 1)
check("deux gestionnaires de redimensionnement (calendrier et personnalisation)", #e.w.events["window-resized"], 2)
check("aucun avertissement", #e.w.logs.error, 0)

-- ============================================================
-- F4 ouvre la page, Entrée enregistre
-- ============================================================
check("F4 ouvre un onglet", open_key(e, config, "F4") and #e.w.spawned, 1)
local settings_pane = e.w.spawned[1]
check("la page de personnalisation est affichée", plain_lines(settings_pane):find("Logtime : Personnalisation", 1, true) ~= nil, true)
check("le choix de départ est l'or", chosen(settings_pane), 3)
check("les touches de la personnalisation sont activées", e.win.performed[#e.win.performed].args.name, "logtime_settings")
press(e, config, "j", settings_pane)
press(e, config, "j", settings_pane)
check("deux fois bas : le bleu (11)", chosen(settings_pane), 11)
press(e, config, "Enter", settings_pane)
check("Entrée : le fichier de réglages est créé dans le dossier personnel", read(e.path), '{\n  "gradient_color": "#6989C9"\n}\n')
check("Entrée : aucune erreur", #e.w.logs.error, 0)
check("Entrée : le message est affiché", plain_lines(settings_pane):find("✓ Enregistré", 1, true) ~= nil, true)

-- le calendrier ouvert ensuite utilise la nouvelle couleur
check("F2 ouvre le calendrier", open_key(e, config, "F2") and #e.w.spawned, 2)
local calendar_pane = e.w.spawned[2]
check("le calendrier utilise la couleur enregistrée (bleu)", last_frame(calendar_pane):find(bg(11), 1, true) ~= nil, true)
check("le calendrier n'utilise plus l'or", last_frame(calendar_pane):find(GOLD, 1, true), nil)
check("le calendrier ouvert dit toujours « Logtime » (la page est bien le calendrier)", plain_lines(calendar_pane):find("Octobre 2026", 1, true) ~= nil, true)
cleanup()

-- ============================================================
-- le calendrier déjà ouvert change tout de suite
-- ============================================================
e = new_env()
config = e.M.apply_to_config({})
open_key(e, config, "F2")
local calendar = e.w.spawned[1]
check("avant : le calendrier est en or", last_frame(calendar):find(GOLD, 1, true) ~= nil, true)
local frames_before = #calendar.injected
open_key(e, config, "F4")
local settings = e.w.spawned[2]
press(e, config, "j", settings)
press(e, config, "j", settings)
press(e, config, "Enter", settings)
check("après Entrée : le calendrier ouvert a été redessiné, sans rien toucher", #calendar.injected > frames_before, true)
check("après Entrée : il est maintenant bleu", last_frame(calendar):find(bg(11), 1, true) ~= nil, true)
check("après Entrée : il n'est plus en or", last_frame(calendar):find(GOLD, 1, true), nil)
press(e, config, "d", settings)
check("d : le calendrier revient à l'or tout de suite", last_frame(calendar):find(GOLD, 1, true) ~= nil and last_frame(calendar):find(bg(11), 1, true) == nil, true)
check("d : le fichier contient l'or", read(e.path), '{\n  "gradient_color": "#C9AB6B"\n}\n')
cleanup()

-- ============================================================
-- les réglages déjà présents
-- ============================================================
e = new_env()
write(e.path, '{"gradient_color": "#6989C9"}')
config = e.M.apply_to_config({})
open_key(e, config, "F4")
check("couleur déjà enregistrée dans le fichier : la page démarre dessus (11)", chosen(e.w.spawned[1]), 11)
check("elle l'affiche comme couleur enregistrée", plain_lines(e.w.spawned[1]):find("Couleur enregistrée : #6989C9", 1, true) ~= nil, true)
cleanup()

e = new_env()
config = e.M.apply_to_config({}, { gradient_color = "#7969C9" })
open_key(e, config, "F4")
check("couleur donnée dans wezterm.lua : la page démarre dessus (12)", chosen(e.w.spawned[1]), 12)
cleanup()

e = new_env()
write(e.path, '{"gradient": false}')
config = e.M.apply_to_config({})
open_key(e, config, "F4")
check("dégradé désactivé dans le fichier : la page le dit", plain_lines(e.w.spawned[1]):find("Dégradé désactivé", 1, true) ~= nil, true)
cleanup()

e = new_env()
write(e.path, '{"lang": "en", "max_months": 4}')
config = e.M.apply_to_config({})
open_key(e, config, "F4")
check("langue anglaise dans le fichier : la page est en anglais", plain_lines(e.w.spawned[1]):find("Logtime : Settings", 1, true) ~= nil, true)
press(e, config, "Enter", e.w.spawned[1])
check("enregistrer garde les autres réglages du fichier", read(e.path), '{\n  "lang": "en",\n  "max_months": 4,\n  "gradient_color": "#C9AB6B"\n}\n')
check("... et le message est en anglais", plain_lines(e.w.spawned[1]):find("✓ Saved", 1, true) ~= nil, true)
cleanup()

-- ============================================================
-- le choix survit à un rechargement de la config
-- ============================================================
e = new_env()
config = e.M.apply_to_config({})
open_key(e, config, "F4")
press(e, config, "k", e.w.spawned[1])
press(e, config, "h", e.w.spawned[1])
press(e, config, "Enter", e.w.spawned[1])
local index_saved = chosen(e.w.spawned[1])
e.w.events = {} -- un nouveau démarrage de WezTerm repart d'un état vide : ni gestionnaires, ni pages ouvertes, ni onglets
e.w.spawned = {}
e.w.GLOBAL = {}
e.M = e.load()
local config2 = e.M.apply_to_config({})
open_key(e, config2, "F2")
check("après un rechargement : le calendrier a la couleur enregistrée", e.w.spawned[1] ~= nil and last_frame(e.w.spawned[1]):find(bg(index_saved), 1, true) ~= nil, true)
open_key(e, config2, "F4")
check("après un rechargement : la page de personnalisation démarre sur la couleur enregistrée", chosen(e.w.spawned[2]), index_saved)
cleanup()

-- ============================================================
-- la touche, et ses conflits
-- ============================================================
e = new_env()
config = e.M.apply_to_config({}, { settings_key = "F5" })
check("settings_key = F5 : la touche F5 existe", open_key(e, config, "F5"), true)
check("settings_key = F5 : F4 n'est pas utilisée", (function()
for _, b in ipairs(config.keys) do
if b.key == "F4" then
return true
end
end
return false
end)(), false)
check("settings_key est une option connue : aucun avertissement", #e.w.logs.error, 0)
cleanup()

e = new_env()
config = e.M.apply_to_config({ keys = { { key = "F4", action = "autre chose" } } })
check("F4 déjà utilisée dans ta config : un avertissement", errors_with(e, "F4"), 1)
cleanup()

e = new_env()
config = e.M.apply_to_config({}, { settings_ke = "F5" })
check("faute de frappe sur settings_key : suggestion", errors_with(e, "tu voulais dire « settings_key » ?"), 1)
cleanup()

-- ============================================================
-- un échec d'enregistrement
-- ============================================================
e = new_env()
config = e.M.apply_to_config({}, { settings_file = "/tmp/dossier_inexistant_logtime/sous/reglages.json" })
open_key(e, config, "F2")
open_key(e, config, "F4")
local failing = e.w.spawned[2]
press(e, config, "j", failing)
press(e, config, "Enter", failing)
check("échec : le message est affiché", plain_lines(failing):find("✗ Enregistrement impossible", 1, true) ~= nil, true)
check("échec : l'erreur est dans les journaux", errors_with(e, "enregistrement des réglages impossible"), 1)
check("échec : le calendrier garde sa couleur (or)", last_frame(e.w.spawned[1]):find(GOLD, 1, true) ~= nil, true)
cleanup()

-- ============================================================
-- fermer la page ; les deux pages ensemble
-- ============================================================
e = new_env()
config = e.M.apply_to_config({})
open_key(e, config, "F2")
open_key(e, config, "F4")
check("les deux pages sont ouvertes dans deux onglets", #e.w.spawned, 2)
check("F4 a activé la table de touches de la personnalisation", e.win.performed[#e.win.performed].args.name, "logtime_settings")
open_key(e, config, "F2")
check("F2 sur un calendrier déjà ouvert ne crée pas un troisième onglet", #e.w.spawned, 2)
check("F2 a réactivé la table de touches du calendrier", e.win.performed[#e.win.performed].args.name, "logtime_page")
open_key(e, config, "F4")
check("F4 sur une page déjà ouverte ne crée pas un troisième onglet", #e.w.spawned, 2)
press(e, config, "q", e.w.spawned[2])
check("q ferme la page de personnalisation", e.w.GLOBAL.logtime_settings_pane, nil)
check("q laisse le calendrier ouvert", e.w.GLOBAL.logtime_page_pane ~= nil, true)
cleanup()

-- ============================================================
-- effets de bord
-- ============================================================
local leaked = {}
for k in pairs(_G) do
if not globals_before[k] then
leaked[#leaked + 1] = k
end
end
check("aucune variable globale ajoutée", table.concat(leaked, ","), "")

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
