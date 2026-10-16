-- tests/pages/test_settings_page.lua : teste la page de personnalisation (pages/settings_page.lua) : le dessin du tableau de
-- couleurs, la navigation, l'enregistrement dans le fichier de réglages, les erreurs. Fausse API WezTerm.
-- Lancer :   lua5.4 tests/pages/test_settings_page.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]pages[/\\]test_settings_page%.lua$") or "."

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
load_module("ui/safe").debug = true -- ces tests lisent les traces du journal (éteintes par défaut)
local settings_page = load_module("pages/settings_page")
local settings_view = load_module("pages/settings_view")
local palette = load_module("color/palette")
local gradient = load_module("color/gradient")
local convert = load_module("color/convert")
local layout = load_module("calendar/layout")
local store = load_module("settings/store")
local schema = load_module("settings/schema")
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
local function leading(line)
	return #line:match("^( *)")
end
-- une partie d'une ligne, comptée en caractères (et non en octets : les accents en prennent deux)
local function usub(line, first, last)
	local from = utf8.offset(line, first)
	local to = utf8.offset(line, (last or utf8.len(line)) + 1)
	if not from then
		return ""
	end
	return line:sub(from, (to or (#line + 1)) - 1)
end

-- ============================================================
-- le message du bas (fonctions pures) ; le dessin de la page : tests/pages/test_settings_view.lua
-- ============================================================
check("message : enregistré", settings_page.message_line(settings_page.MESSAGE.SAVED, fr), " " .. fr.settings_saved)
check(
	"message : échec, avec la raison",
	settings_page.message_line(settings_page.MESSAGE.FAILED, fr, "disque plein", 60),
	" ✗ Pas enregistré : disque plein"
)
check(
	"message : échec sans raison connue",
	settings_page.message_line(settings_page.MESSAGE.FAILED, fr, nil, 60),
	" ✗ Pas enregistré : ?"
)
check(
	"message : réponse enregistrée",
	settings_page.message_line(settings_page.MESSAGE.CONSENT, fr),
	" " .. fr.settings_consent_saved
)
check(
	"message : réglage enregistré",
	settings_page.message_line(settings_page.MESSAGE.SETTING_SAVED, fr),
	" " .. fr.settings_setting_saved
)
check("message inconnu : rien", settings_page.message_line(99, fr), "")
-- une raison trop longue : on garde sa FIN (la cause), coupée par la gauche, sans dépasser la largeur du panneau
local long_reason = "cannot write: /home/vitia/.local/share/logtime/.logtime_settings.json.tmp: Permission denied"
local failure = settings_page.failure_line(en, long_reason, 57)
check("raison trop longue : la fin (la cause) est gardée", failure:sub(-#"Permission denied"), "Permission denied")
check("raison trop longue : coupée par la gauche avec …", failure:find("Not saved: …", 1, true) ~= nil, true)
check("raison trop longue : jamais plus large que le panneau", utf8.len(failure), 57)
check(
	"raison trop longue : un panneau plus large garde plus de texte",
	utf8.len(settings_page.failure_line(en, long_reason, 80)),
	80
)
local P = "/home/vitia/.local/share/logtime/.logtime_settings.json"
check(
	"raison sans le chemin du fichier temporaire",
	settings_page.short_reason("cannot write: " .. P .. ".tmp: Permission denied", P),
	"cannot write: Permission denied"
)
check(
	"raison sans le chemin du fichier (relecture)",
	settings_page.short_reason("check after writing failed: cannot read back: " .. P .. ".tmp: Permission denied", P),
	"check after writing failed: cannot read back: Permission denied"
)
check(
	"raison : un chemin avec des caractères spéciaux (Windows, parenthèses, %)",
	settings_page.short_reason("cannot write: C:\\Users\\a (1)\\x%.json.tmp: denied", "C:\\Users\\a (1)\\x%.json"),
	"cannot write: denied"
)
check("raison : sans chemin connu, inchangée", settings_page.short_reason("disk full", nil), "disk full")
check("raison : pas un texte", settings_page.short_reason(nil, P), "nil")
check("raison courte : entière", settings_page.failure_line(en, "disk full", 57), " ✗ Not saved: disk full")
check(
	"raison sur plusieurs lignes : une seule ligne",
	settings_page.failure_line(en, "a\nb\t c", 57),
	" ✗ Not saved: a b c"
)
local exact = string.rep("x", 57 - utf8.len(" ✗ Not saved: "))
check(
	"raison pile à la largeur : pas coupée",
	utf8.len(settings_page.failure_line(en, exact, 57))
		.. " "
		.. tostring(settings_page.failure_line(en, exact, 57):find("…", 1, true)),
	"57 nil"
)
check(
	"raison avec des accents : coupée sans casser un caractère",
	utf8.len(settings_page.failure_line(fr, string.rep("é", 100), 57)) ~= nil,
	true
)

-- ============================================================
-- la page, avec une fausse API WezTerm
-- ============================================================
local function new_env(opts)
	opts = opts or {}
	local home = os.tmpname()
	os.remove(home)
	os.execute("mkdir -p '" .. home .. "'")
	homes[#homes + 1] = home
	local w = { events = {}, logs = { error = {}, info = {} }, panes = {}, spawned = {}, timers = {}, GLOBAL = {} }
	w.log_error = function(m)
		w.logs.error[#w.logs.error + 1] = m
	end
	w.log_info = function(m)
		w.logs.info[#w.logs.info + 1] = m
	end
	w.action = {
		EmitEvent = function(name)
			return { kind = "EmitEvent", name = name }
		end,
		ActivateKeyTable = function(t)
			return { kind = "ActivateKeyTable", args = t }
		end,
		SendKey = function(t)
			return { kind = "SendKey", args = t }
		end,
		CloseCurrentTab = function(t)
			return { kind = "CloseCurrentTab", args = t }
		end,
		PopKeyTable = { kind = "PopKeyTable" },
	}
	w.on = function(event, handler)
		w.events[event] = w.events[event] or {}
		table.insert(w.events[event], handler)
	end
	w.time = {
		call_after = function(seconds, fn)
			w.timers[#w.timers + 1] = { seconds = seconds, fn = fn }
		end,
	}
	w.mux = {
		get_pane = function(id)
			local pane = w.panes[id]
			if not pane then
				error("pane id " .. tostring(id) .. " not found in mux")
			end
			return pane
		end,
	}
	w.next_id = 500
	function w.new_pane(cols, rows)
		w.next_id = w.next_id + 1
		local tab = { activated = false }
		function tab:activate()
			self.activated = true
		end
		local pane = {
			id = w.next_id,
			injected = {},
			dims = { viewport_rows = rows or opts.rows or 40, cols = cols or opts.cols or 120 },
			the_tab = tab,
		}
		function pane:pane_id()
			return self.id
		end
		function pane:get_dimensions()
			return self.dims
		end
		function pane:inject_output(text)
			self.injected[#self.injected + 1] = text
		end
		function pane:tab()
			return self.the_tab
		end
		w.panes[pane.id] = pane
		return pane
	end
	local env = {
		w = w,
		home = home,
		path = opts.path or (home .. "/.logtime_settings.json"),
		cfg = { gradient_color = opts.color },
		applied = {},
		refreshed = 0,
	}
	if opts.gradient == false then
		env.cfg.gradient = false
	end
	local win = { performed = {} }
	function win:perform_action(action, pane)
		self.performed[#self.performed + 1] = action.kind
	end
	function win:toast_notification() end
	function win:mux_window()
		return {
			spawn_tab = function(_, spec)
				local pane = w.new_pane()
				w.spawned[#w.spawned + 1] = pane
				return pane.the_tab, pane, nil
			end,
		}
	end
	env.window = win
	env.page = settings_page.create({
		wezterm = w,
		G = w.GLOBAL,
		num = function(v)
			return v
		end,
		cfg = function()
			return env.cfg
		end,
		labels = function()
			if opts.labels_from_cfg then
				return (env.cfg.lang == "en") and en or fr
			end
			return opts.labels or fr
		end,
		blocker_args = function()
			return platform.blocker_args("windows")
		end,
		store = store,
		settings_path = function()
			return env.path
		end,
		apply = function(changes)
			env.applied[#env.applied + 1] = changes
			for key, value in pairs(changes) do
				env.cfg[key] = value
			end
		end,
		refresh_calendar = opts.refresh or function(window, pane)
			env.refreshed = env.refreshed + 1
		end,
		days = opts.days and function()
			return opts.days
		end or nil,
		today_key = opts.days and function()
			return opts.today or "2026-10-14"
		end or nil,
	})
	env.table = env.page.key_table()
	return env
end
-- Comme WezTerm : une touche de la page émet son événement
-- key : "h", ou "SHIFT-Tab" pour une touche avec un modificateur
local function press(env, key, pane)
	local mods, plain_key = key:match("^(%u+)%-(.+)$")
	for _, binding in ipairs(env.table) do
		if binding.key == (plain_key or key) and binding.mods == mods then
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
local function shown_lines(pane)
	return lines_of(strip(frame_of(pane)))
end
local function chosen(pane)
	for _, line in ipairs(shown_lines(pane)) do
		local n = line:match("Choix : (%d+)") or line:match("Choice: (%d+)")
		if n then
			return tonumber(n)
		end
	end
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

-- ---- la taille de la fenêtre
local env = new_env({})
local got, got_width, fits = env.page.build_lines(nil)
check("sans taille connue : la page entière, à la taille par défaut (120 x 40)", #got == 40 and fits == true, true)
check("sans taille connue : la largeur par défaut", got_width, 120)
got, got_width, fits = env.page.build_lines({ cols = 40, rows = 60 })
check("40 colonnes : trop étroit : message", fits == false and #got == 2, true)
check("40 colonnes : le titre du message", strip(got[1]), "Fenêtre trop petite")
local need_cols, need_rows = strip(got[2]):match("il faut au moins (%d+) colonnes sur (%d+) lignes")
need_cols, need_rows = tonumber(need_cols), tonumber(need_rows)
check(
	"le message dit la taille nécessaire : la ligne d'aide la plus longue (ou 57) + sa marge + le cadre",
	need_cols,
	math.max(settings_view.MIN_LEFT, utf8.len(fr.settings_help_top) + 2) + 2
)
check(
	"à la taille nécessaire exactement : la page tient",
	select(3, env.page.build_lines({ cols = need_cols, rows = need_rows })),
	true
)
check(
	"une colonne de moins : trop étroit",
	select(3, env.page.build_lines({ cols = need_cols - 1, rows = need_rows })),
	false
)
check(
	"une ligne de moins : trop bas",
	select(3, env.page.build_lines({ cols = need_cols, rows = need_rows - 1 })),
	false
)
got, got_width, fits = env.page.build_lines({ cols = 200, rows = 60 })
check("200 x 60 : la page tient, sur toute la fenêtre", fits and #got == 60 and got_width == 200, true)

-- ---- l'ouverture
env = open({})
check("ouverture : un onglet est ouvert", #env.w.spawned, 1)
check("ouverture : l'onglet est activé", env.pane.the_tab.activated, true)
check("ouverture : un dessin envoyé", #env.pane.injected >= 1, true)
check(
	"ouverture : les touches de la page sont activées",
	env.window.performed[#env.window.performed],
	"ActivateKeyTable"
)
check(
	"ouverture : deux redessins différés (0,4 s et 1,2 s)",
	#env.w.timers == 2 and env.w.timers[1].seconds == 0.4 and env.w.timers[2].seconds == 1.2,
	true
)
check("ouverture : le choix de départ est l'or (pas de couleur enregistrée)", chosen(env.pane), 3)
check(
	"ouverture : le journal note l'ouverture",
	#env.w.logs.info >= 1 and env.w.logs.info[1]:find("settings page opened in pane " .. env.pane.id, 1, true) ~= nil,
	true
)
check("ouverture : aucune erreur", #env.w.logs.error, 0)
env.page.open(env.window, env.w.new_pane())
check("ouvrir deux fois : pas de second onglet", #env.w.spawned, 1)
local before = #env.pane.injected
env.page.open(env.window, env.w.new_pane())
check("ouvrir deux fois : la page existante est redessinée", #env.pane.injected, before + 1)

-- le choix de départ suit la couleur enregistrée
for _, case in ipairs({
	{ "#6989C9", 11 },
	{ "#c96969", 1 },
	{ "#999999", 16 },
	{ "#3366CC", 11 },
	{ "#808080", 16 },
	{ "pas une couleur", 3 },
	{ nil, 3 },
}) do
	local e = open({ color = case[1] })
	check("choix de départ pour la couleur " .. tostring(case[1]) .. " : " .. case[2], chosen(e.pane), case[2])
end
local e = open({ color = "#123456" })
check(
	"couleur enregistrée hors palette : indiquée comme personnalisée",
	table.concat(shown_lines(e.pane), "\n"):find("(personnalisée)", 1, true) ~= nil,
	true
)
e = open({ color = "#6989C9" })
check(
	"couleur enregistrée de la palette : indiquée sans « personnalisée »",
	table.concat(shown_lines(e.pane), "\n"):find("Couleur enregistrée : #6989C9", 1, true) ~= nil
		and table.concat(shown_lines(e.pane), "\n"):find("personnalisée", 1, true) == nil,
	true
)
e = open({ gradient = false })
check(
	"dégradé désactivé : l'avertissement est affiché",
	table.concat(shown_lines(e.pane), "\n"):find("Dégradé désactivé", 1, true) ~= nil,
	true
)
e = open({})
check(
	"dégradé actif : pas d'avertissement",
	table.concat(shown_lines(e.pane), "\n"):find("Dégradé désactivé", 1, true),
	nil
)

-- ---- la page remplit la fenêtre (elle n'est plus centrée au milieu de marges vides)
e = open({ cols = 120, rows = 40 })
local shown = shown_lines(e.pane)
check("plein écran : pas de ligne vide en haut, le cadre commence à la 1re ligne", shown[1]:sub(1, #"╭"), "╭")
check("plein écran : pas de marge à gauche", leading(shown[2]), 0)
check("plein écran : 40 lignes", #shown, 40)

-- ---- la navigation
e = open({})
local function index_after(keys)
	local env2 = open({})
	for _, k in ipairs(keys) do
		press(env2, k, env2.pane)
	end
	return chosen(env2.pane)
end
check("départ : 3 (ligne 1, colonne 3)", chosen(e.pane), 3)
check("l : vers la droite", index_after({ "l" }), 4)
check("l deux fois : bloqué au bord droit", index_after({ "l", "l" }), 4)
check("h : vers la gauche", index_after({ "h" }), 2)
check("h trois fois : bloqué au bord gauche", index_after({ "h", "h", "h" }), 1)
check("j : vers le bas (3 + 4)", index_after({ "j" }), 7)
check("k en haut : bloqué", index_after({ "k" }), 3)
check("j quatre fois : bloqué en bas (15)", index_after({ "j", "j", "j", "j" }), 15)
check("j puis k : retour", index_after({ "j", "k" }), 3)
check("flèche droite", index_after({ "RightArrow" }), 4)
check("flèche gauche", index_after({ "LeftArrow" }), 2)
check("flèche bas", index_after({ "DownArrow" }), 7)
check("flèche haut après bas", index_after({ "DownArrow", "UpArrow" }), 3)
check("de 3 en 16 : trois fois bas, une fois droite", index_after({ "j", "j", "j", "l" }), 16)
check(
	"les 16 cases sont atteignables",
	(function()
		local reached = {}
		for row = 0, 3 do
			for col = 0, 3 do
				local keys = {}
				for _ = 1, 4 do
					keys[#keys + 1] = "k"
				end
				for _ = 1, 4 do
					keys[#keys + 1] = "h"
				end
				for _ = 1, row do
					keys[#keys + 1] = "j"
				end
				for _ = 1, col do
					keys[#keys + 1] = "l"
				end
				reached[index_after(keys)] = true
			end
		end
		local n = 0
		for _ in pairs(reached) do
			n = n + 1
		end
		return n
	end)(),
	16
)
local count = #e.pane.injected
press(e, "l", e.pane)
check("chaque déplacement redessine la page", #e.pane.injected, count + 1)

-- ---- enregistrer avec Entrée
e = open({})
press(e, "j", e.pane)
press(e, "j", e.pane)
check("avant d'enregistrer : le choix est 11 (bleu)", chosen(e.pane), 11)
press(e, "Enter", e.pane)
check("Entrée : le fichier est écrit", read(e.path), '{\n  "gradient_color": "#6989C9"\n}\n')
check(
	"Entrée : la couleur est appliquée tout de suite",
	#e.applied == 1 and e.applied[1].gradient_color == "#6989C9",
	true
)
check("Entrée : le calendrier est redessiné une fois", e.refreshed, 1)
check(
	"Entrée : le message « enregistré » est affiché",
	table.concat(shown_lines(e.pane), "\n"):find("✓ Enregistré", 1, true) ~= nil,
	true
)
check(
	"Entrée : la couleur enregistrée est mise à jour dans la page",
	table.concat(shown_lines(e.pane), "\n"):find("Couleur enregistrée : #6989C9", 1, true) ~= nil,
	true
)
check("Entrée : aucune erreur", #e.w.logs.error, 0)
check("Entrée : pas de copie de sécurité au premier enregistrement", read(e.path .. ".bak"), nil)
press(e, "l", e.pane)
check(
	"un déplacement efface le message",
	table.concat(shown_lines(e.pane), "\n"):find("✓ Enregistré", 1, true),
	nil
)
press(e, "Enter", e.pane)
check(
	"un second enregistrement : le fichier a la nouvelle couleur",
	read(e.path),
	'{\n  "gradient_color": "#7969C9"\n}\n'
)
check(
	"un second enregistrement : la copie de sécurité est l'ancien état",
	read(e.path .. ".bak"),
	'{\n  "gradient_color": "#6989C9"\n}\n'
)
check("un second enregistrement : deux couleurs appliquées au total", #e.applied, 2)

-- les autres réglages du fichier sont gardés
e = open({})
write(e.path, '{"max_months": 4, "lang": "en", "gradient": true}')
press(e, "Enter", e.pane)
check(
	"Entrée garde les autres réglages du fichier (dans l'ordre du schéma)",
	read(e.path),
	'{\n  "lang": "en",\n  "max_months": 4,\n  "gradient": true,\n  "gradient_color": "#C9AB6B"\n}\n'
)
-- un réglage inconnu ou incorrect du fichier n'empêche pas l'enregistrement
e = open({})
write(e.path, '{"gradiant": true, "max_months": 100, "center": false}')
press(e, "Enter", e.pane)
check(
	"Entrée avec des réglages incorrects dans le fichier : ils sont ignorés, les bons gardés",
	read(e.path),
	'{\n  "center": false,\n  "gradient_color": "#C9AB6B"\n}\n'
)
-- fichier illisible : mis de côté, jamais perdu
e = open({})
write(e.path, "{ illisible")
press(e, "Enter", e.pane)
check("fichier illisible : le nouveau fichier est bon", read(e.path), '{\n  "gradient_color": "#C9AB6B"\n}\n')
check(
	"fichier illisible : l'ancien est mis de côté",
	(function()
		local p = io.popen("ls -1A '" .. e.home .. "'")
		for name in p:lines() do
			if name:find(".corrupt-", 1, true) then
				p:close()
				return read(e.home .. "/" .. name)
			end
		end
		p:close()
	end)(),
	"{ illisible"
)
check(
	"fichier illisible : message « enregistré » quand même",
	table.concat(shown_lines(e.pane), "\n"):find("✓ Enregistré", 1, true) ~= nil,
	true
)
-- fichier illisible avec une bonne copie de sécurité : ses réglages sont repris
e = open({})
write(e.path, "abîmé")
write(e.path .. ".bak", '{"max_months": 5}')
press(e, "Enter", e.pane)
check(
	"fichier illisible avec copie : les réglages de la copie sont repris",
	read(e.path),
	'{\n  "max_months": 5,\n  "gradient_color": "#C9AB6B"\n}\n'
)

-- échec d'enregistrement : le dossier n'existe pas
e = open({ path = "/tmp/dossier_qui_nexiste_pas_logtime/sous/.logtime_settings.json" })
press(e, "Enter", e.pane)
check(
	"échec : le message d'échec est affiché",
	table.concat(shown_lines(e.pane), "\n"):find("✗ Pas enregistré", 1, true) ~= nil,
	true
)
check(
	"échec : l'erreur est écrite dans les journaux",
	#e.w.logs.error == 1 and e.w.logs.error[1]:find("cannot save the settings", 1, true) ~= nil,
	true
)
check("échec : rien n'est appliqué", #e.applied, 0)
check("échec : le calendrier n'est pas redessiné", e.refreshed, 0)
check(
	"échec : la page reste utilisable (on peut se déplacer)",
	(function()
		press(e, "l", e.pane)
		return chosen(e.pane)
	end)(),
	4
)
-- le calendrier ne répond pas : ça n'empêche pas l'enregistrement
e = open({
	refresh = function()
		error("boum")
	end,
})
press(e, "Enter", e.pane)
check(
	"le redessin du calendrier plante : l'enregistrement a réussi quand même",
	read(e.path) ~= nil and table.concat(shown_lines(e.pane), "\n"):find("✓ Enregistré", 1, true) ~= nil,
	true
)
check("le redessin du calendrier plante : aucune erreur propagée", #e.w.logs.error, 0)

-- ---- d : la couleur par défaut
e = open({ color = "#6989C9" })
check("d : au départ, le bleu est choisi", chosen(e.pane), 11)
press(e, "d", e.pane)
check("d : le choix revient à l'or", chosen(e.pane), 3)
check("d : et l'or est enregistré", read(e.path), '{\n  "gradient_color": "#C9AB6B"\n}\n')
check("d : appliqué tout de suite", #e.applied == 1 and e.applied[1].gradient_color == "#C9AB6B", true)
check("d : message enregistré", table.concat(shown_lines(e.pane), "\n"):find("✓ Enregistré", 1, true) ~= nil, true)

-- ---- fermer
for _, key in ipairs({ "q", "Escape" }) do
	e = open({})
	press(e, key, e.pane)
	check(
		key .. " : les touches de la page sont retirées puis l'onglet est fermé",
		table.concat(e.window.performed, ","):match("PopKeyTable,CloseCurrentTab$") ~= nil,
		true
	)
	check(key .. " : la page n'est plus la page", e.w.GLOBAL.logtime_settings_pane, nil)
	check(key .. " : rien n'est écrit en fermant", read(e.path), nil)
end

-- ---- une touche hors de la page n'est jamais avalée
e = open({})
local other = e.w.new_pane()
check("is_page : le panneau de la page", e.page.is_page(e.pane), true)
check("is_page : un autre panneau", e.page.is_page(other), false)
local performed_before = #e.window.performed
press(e, "l", other)
check(
	"touche dans un autre onglet : les touches de la page sont retirées puis la touche est rendue",
	table.concat(e.window.performed, ",", performed_before + 1),
	"PopKeyTable,SendKey"
)
check("touche dans un autre onglet : le choix n'a pas bougé", chosen(e.pane), 3)

-- ---- le redimensionnement
e = open({ cols = 120, rows = 40 })
local drawn = #e.pane.injected
e.w.timers = {}
e.pane.dims.cols = 50
e.page.on_resize(e.window, e.pane)
check("redimensionnement : la page est redessinée", #e.pane.injected, drawn + 1)
check(
	"redimensionnement : trop étroit, le message remplace la page",
	table.concat(shown_lines(e.pane), "\n"):find("Fenêtre trop petite", 1, true) ~= nil,
	true
)
check(
	"redimensionnement : deux redessins différés",
	#e.w.timers == 2 and e.w.timers[1].seconds == 0.3 and e.w.timers[2].seconds == 1.0,
	true
)
e.pane.dims.cols = 120
e.page.on_resize(e.window, e.pane)
check(
	"agrandi : la page revient",
	table.concat(shown_lines(e.pane), "\n"):find("Couleur du dégradé", 1, true) ~= nil,
	true
)
check("agrandi : le choix est conservé", chosen(e.pane), 3)
local other_env = new_env({})
local before_resize = #other_env.w.panes
other_env.page.on_resize(other_env.window, other_env.w.new_pane())
check("redimensionnement sans page ouverte : rien ne se passe", #other_env.w.timers, 0)
e.w.GLOBAL.logtime_settings_pane = nil
e.pane.dims.cols = 80
local count_after = #e.pane.injected
e.page.on_resize(e.window, e.pane)
check("redimensionnement après fermeture : aucun dessin", #e.pane.injected, count_after)

-- ---- anglais
e = open({ labels = en })
check("anglais : titre", table.concat(shown_lines(e.pane), "\n"):find("Settings", 1, true) ~= nil, true)
press(e, "Enter", e.pane)
check("anglais : message", table.concat(shown_lines(e.pane), "\n"):find("✓ Saved", 1, true) ~= nil, true)

-- ============================================================
-- l'onglet Calendrier
-- ============================================================
local max_def = { key = "max_months", kind = "integer", min = 1, max = 12 }
check("valeur au maximum : seulement la flèche de gauche", settings_page.format_value(max_def, 12), "◀ 12")
check("valeur au milieu : les deux flèches", settings_page.format_value(max_def, 6), "◀ 6 ▶")
check("valeur au minimum : seulement la flèche de droite", settings_page.format_value(max_def, 1), "  1 ▶")
check("step : +1 au maximum reste au maximum", settings_page.step(max_def, 12, 1), 12)
check("step : -1 au minimum reste au minimum", settings_page.step(max_def, 1, -1), 1)
check("step : +1 au milieu", settings_page.step(max_def, 6, 1), 7)

-- les lignes de l'onglet (fonction pure) ; le cadre, l'aide et le message : tests/pages/test_settings_view.lua
-- Les réglages d'un onglet, lus comme des lignes « nom = valeur » (« ▸ » devant le réglage choisi), avec les numéros de
-- ligne d'avant : 1 et 2 vides, les réglages à partir de 3, une ligne vide, puis l'explication (la dernière).
local function list(state, labels)
	local data = settings_page.list_rows(state, labels or fr)
	local out = { "", "" }
	for i, row in ipairs(data.rows) do
		out[#out + 1] = (i == data.selected and "▸ " or "") .. row.name .. " = " .. row.value
	end
	out[#out + 1] = ""
	out[#out + 1] = data.hint
	return out
end
local cal = list({ tab = settings_page.TAB.CALENDAR, row = 1, values = { max_months = 12 } })
local cal_plain = {}
for i, line in ipairs(cal) do
	cal_plain[i] = strip(line)
end
check(
	"onglet Calendrier : le réglage choisi et sa valeur alignée",
	cal_plain[3],
	"▸ Mois affichés au maximum = ◀ 12"
)
check(
	"onglet Calendrier : l'explication du réglage choisi, en dernier",
	cal_plain[#cal_plain],
	fr.settings_hints.max_months
)
check(
	"onglet Calendrier : valeur absente, la valeur par défaut (12)",
	strip(list({ tab = 2, row = 1, values = {} })[3]):match("◀ 12$") ~= nil,
	true
)
check(
	"onglet Calendrier : aucune ligne plus large que le panneau minimum (français et anglais)",
	(function()
		for _, labels in ipairs({ fr, en }) do
			for _, line in ipairs(list({ tab = 2, row = 1, values = { max_months = 6 } }, labels)) do
				if utf8.len(strip(line)) > settings_view.MIN_LEFT then
					return strip(line)
				end
			end
		end
		return true
	end)(),
	true
)

-- la page, avec la fausse API
local function shown_text(env)
	return table.concat(shown_lines(env.pane), "\n")
end
-- Le texte d'une ligne dans le panneau de gauche : sans le cadre, ni les espaces qui complètent la ligne.
local function panel_text(line)
	local inner = line:match("^│(.*)$") or line
	return inner:match("^(.-)%s*│") or inner
end
local function months_line(env)
	for _, line in ipairs(shown_lines(env.pane)) do
		if line:find("Mois affichés au maximum", 1, true) then
			return panel_text(line)
		end
	end
end
-- Ce réglage est-il le réglage choisi ? Sa ligne est remplie de la couleur d'accent (la couleur enregistrée, ou l'or).
local function row_selected(env, name)
	local accent = palette.normalize(env.cfg.gradient_color) or palette.COLORS[palette.DEFAULT_INDEX]
	for line in (frame_of(env.pane) .. "\n"):gmatch("(.-)\n") do
		if strip(line):find(name, 1, true) then
			return line:find(convert.bg(accent), 1, true) ~= nil
		end
	end
	return false
end
-- L'onglet ouvert : son nom est dessiné sur le fond coloré de la barre d'onglets (la couleur enregistrée, ou l'or).
local function open_tab_is(env, name)
	local frame = frame_of(env.pane)
	local start = 1
	while true do
		local s = frame:find("\27[48;2;", start, true)
		if not s then
			return false
		end
		local stop = frame:find("\27[0m", s, true) or #frame
		if frame:sub(s, stop):find(name, 1, true) then
			return true
		end
		start = s + 1
	end
end

e = open({})
press(e, "Tab", e.pane)
check("Tab : l'onglet Calendrier est affiché", open_tab_is(e, "Calendrier"), true)
check("Tab : le réglage est affiché avec sa valeur (12 par défaut)", months_line(e):match("◀ 12$") ~= nil, true)
check("Tab : la page tient toujours dans 120 x 40", select(3, e.page.build_lines({ cols = 120, rows = 40 })), true)
check("Tab : rien n'est écrit en changeant d'onglet", read(e.path), nil)
press(e, "Tab", e.pane)
check("Tab deux fois : l'onglet Général", open_tab_is(e, "Général"), true)
press(e, "Tab", e.pane)
check("Tab trois fois : retour à l'onglet Couleurs", open_tab_is(e, "Couleurs"), true)

-- ← : la valeur baisse, est enregistrée, appliquée, et le calendrier redessiné
e = open({})
press(e, "Tab", e.pane)
press(e, "h", e.pane)
check("← : le fichier contient la nouvelle valeur", read(e.path), '{\n  "max_months": 11\n}\n')
check("← : appliquée tout de suite", #e.applied == 1 and e.applied[1].max_months == 11, true)
check("← : le calendrier est redessiné", e.refreshed, 1)
check("← : la page montre la nouvelle valeur", months_line(e):match("◀ 11 ▶$") ~= nil, true)
check("← : le message « enregistré »", shown_text(e):find(fr.settings_setting_saved, 1, true) ~= nil, true)
press(e, "LeftArrow", e.pane)
check("flèche gauche : une fois de plus (10)", read(e.path), '{\n  "max_months": 10\n}\n')
press(e, "l", e.pane)
check("→ : remonte à 11", read(e.path), '{\n  "max_months": 11\n}\n')
check("← ← → : la couleur n'a pas été touchée", e.cfg.gradient_color, nil)
press(e, "d", e.pane)
check("d : la valeur par défaut (12) est enregistrée", read(e.path), '{\n  "max_months": 12\n}\n')
local applied_before = #e.applied
press(e, "d", e.pane)
check("d déjà à la valeur par défaut : rien de plus n'est appliqué", #e.applied, applied_before)

-- → au maximum : rien n'est écrit
e = open({})
press(e, "Tab", e.pane)
press(e, "l", e.pane)
check("→ à 12 (le maximum) : rien n'est écrit", read(e.path), nil)
check("→ à 12 : rien n'est appliqué", #e.applied, 0)
check("→ à 12 : le calendrier n'est pas redessiné", e.refreshed, 0)
-- ← jusqu'au minimum, puis encore : reste à 1
for _ = 1, 15 do
	press(e, "h", e.pane)
end
check("← quinze fois : bloqué au minimum (1)", read(e.path), '{\n  "max_months": 1\n}\n')
check("au minimum : seulement la flèche de droite", months_line(e):match("  1 ▶$") ~= nil, true)
-- ↓ puis ↑ : retour au 1er réglage, rien n'est écrit en plus
local writes = #e.applied
press(e, "j", e.pane)
press(e, "k", e.pane)
check("↓ ↑ : le 1er réglage est de nouveau choisi", row_selected(e, "Mois affichés"), true)
check("↑ ↓ : rien n'est écrit", #e.applied, writes)
-- Entrée ne fait rien dans cet onglet (chaque changement y est déjà enregistré)
press(e, "Enter", e.pane)
check("Entrée dans l'onglet Calendrier : rien d'autre n'est enregistré", #e.applied, writes)

-- les autres réglages du fichier sont gardés
e = open({})
write(e.path, '{"gradient_color": "#6989C9", "lang": "en"}')
press(e, "Tab", e.pane)
press(e, "h", e.pane)
check(
	"← garde les autres réglages du fichier",
	read(e.path),
	'{\n  "lang": "en",\n  "max_months": 11,\n  "gradient_color": "#6989C9"\n}\n'
)

-- une valeur incorrecte dans wezterm.lua : la page montre la valeur par défaut, sans planter
e = open({})
e.cfg.max_months = 100
press(e, "Tab", e.pane)
check("max_months = 100 dans wezterm.lua : la page montre 12", months_line(e):match("◀ 12$") ~= nil, true)
check("max_months = 100 : aucune erreur", #e.w.logs.error, 0)
e.cfg.max_months = 4
e.page.on_resize(e.window, e.pane)
check("max_months = 4 dans wezterm.lua : la page montre 4", months_line(e):match("◀ 4 ▶$") ~= nil, true)

-- échec d'enregistrement
e = open({ path = "/tmp/dossier_qui_nexiste_pas_logtime/sous/.logtime_settings.json" })
press(e, "Tab", e.pane)
press(e, "h", e.pane)
check(
	"échec (onglet Calendrier) : le message d'échec",
	shown_text(e):find("✗ Pas enregistré", 1, true) ~= nil,
	true
)
check("échec (onglet Calendrier) : rien n'est appliqué", #e.applied, 0)
check("échec (onglet Calendrier) : la valeur affichée ne change pas", months_line(e):match("◀ 12$") ~= nil, true)

-- changer d'onglet garde la couleur choisie et efface le message
e = open({})
press(e, "l", e.pane)
press(e, "Enter", e.pane)
press(e, "Tab", e.pane)
check("Tab efface le message", shown_text(e):find("✓", 1, true), nil)
press(e, "Tab", e.pane)
press(e, "Tab", e.pane)
check("Tab trois fois : la couleur choisie est gardée (4)", chosen(e.pane), 4)

-- ---- les choix et les oui/non (début de la semaine, place du mois, centrage)
local week_def = { kind = "enum", values = { "monday", "sunday" } }
local three_def = { kind = "enum", values = { "a", "b", "c" } }
local bool_def = { kind = "boolean" }
check("step choix : → passe à la valeur suivante", settings_page.step(week_def, "monday", 1), "sunday")
check(
	"step choix : → après la dernière, retour à la première",
	settings_page.step(week_def, "sunday", 1),
	"monday"
)
check("step choix : ← avant la première, la dernière", settings_page.step(three_def, "a", -1), "c")
check("step choix : ← dans une liste de trois", settings_page.step(three_def, "c", -1), "b")
check("step choix : valeur inconnue, on part de la première", settings_page.step(three_def, "zzz", 1), "b")
check("step oui/non : → inverse", settings_page.step(bool_def, true, 1), false)
check("step oui/non : ← inverse aussi", settings_page.step(bool_def, false, -1), true)
check(
	"format choix : toujours les deux flèches",
	settings_page.format_value(week_def, "monday", "lundi"),
	"◀ lundi ▶"
)
check("format oui/non : toujours les deux flèches", settings_page.format_value(bool_def, false, "non"), "◀ non ▶")

local four = list({
	tab = 2,
	row = 3,
	values = { max_months = 6, months_anchor = "first", week_starts_on = "sunday" },
	message = 0,
})
local four_plain = {}
for i, line in ipairs(four) do
	four_plain[i] = strip(line)
end
check("l'onglet Calendrier : intitulé, ligne vide, 6 réglages, ligne vide, explication (10 lignes)", #four, 10)
check("onglet Calendrier : le nombre de mois", four_plain[3], "Mois affichés au maximum = ◀ 6 ▶")
check(
	"onglet Calendrier : la place du mois choisi (traduite)",
	four_plain[4],
	"Place du mois choisi = ◀ au début ▶"
)
check(
	"onglet Calendrier : le début de la semaine, choisi (▸)",
	four_plain[5],
	"▸ Début de la semaine = ◀ dimanche ▶"
)
check("onglet Calendrier : les encadrés, « non » par défaut", four_plain[6], "Encadrés = ◀ non ▶")
check(
	"onglet Calendrier : le style du trait, avec un aperçu",
	four_plain[7],
	"Style du trait = ◀ arrondi ╭─╮ ▶"
)
check("le centrage n'apparaît pas dans la page", table.concat(four_plain, "\n"):find("centr", 1, true), nil)
check(
	"onglet Calendrier : la couleur du trait, grise par défaut, avec un aperçu",
	four_plain[8],
	"Couleur du trait = ◀ Gris ╭─╮ ▶"
)
check("onglet Calendrier : l'explication du réglage choisi (le 3e)", four_plain[10], fr.settings_hints.week_starts_on)
local boxed = list({ tab = 2, row = 4, values = { borders = false, border_style = "heavy" }, message = 0 })
check(
	"encadrés « non » reste « non » (false n'est pas remplacé par la valeur par défaut)",
	strip(boxed[6]),
	"▸ Encadrés = ◀ non ▶"
)
check(
	"encadrés « oui »",
	strip(list({ tab = 2, row = 1, values = { borders = true }, message = 0 })[6]),
	"Encadrés = ◀ oui ▶"
)
check("style épais : son aperçu", strip(boxed[7]), "Style du trait = ◀ épais ┏━┓ ▶")
check(
	"anglais : le style double",
	strip(list({ tab = 2, row = 1, values = { border_style = "double" }, message = 0 }, en)[7]),
	"Border style = ◀ double ╔═╗ ▶"
)
local four_en =
	list({ tab = 2, row = 1, values = { months_anchor = "last", week_starts_on = "monday" }, message = 0 }, en)
check("anglais : le début de la semaine", strip(four_en[5]), "Week starts on = ◀ Monday ▶")
check(
	"chaque réglage de l'onglet a un nom, une explication et (si choix) ses valeurs, en français et en anglais",
	(function()
		for _, labels in ipairs({ fr, en }) do
			for _, key in ipairs(settings_page.CALENDAR_SETTINGS) do
				if not labels.settings_names[key] or not labels.settings_hints[key] then
					return key
				end
				if utf8.len(labels.settings_hints[key]) > 55 then
					return key .. " (explication trop longue)"
				end
				local definition = schema.get(key)
				if definition.kind == "enum" then
					for _, v in ipairs(definition.values) do
						if not (labels.settings_values[key] or {})[v] then
							return key .. "." .. v
						end
					end
				end
			end
		end
		return true
	end)(),
	true
)

-- dans la page : choisir un réglage avec ↓, le changer avec →
local function setting_line(env, name)
	for _, line in ipairs(shown_lines(env.pane)) do
		if line:find(name, 1, true) then
			return line
		end
	end
end
e = open({})
press(e, "Tab", e.pane)
press(e, "j", e.pane)
check("↓ : le 2e réglage est choisi", row_selected(e, "Place du mois choisi"), true)
check("↓ : le 1er ne l'est plus", row_selected(e, "Mois affichés"), false)
check("↓ : son explication est affichée", shown_text(e):find(fr.settings_hints.months_anchor, 1, true) ~= nil, true)
check("↓ : rien n'est écrit", read(e.path), nil)
press(e, "DownArrow", e.pane)
press(e, "l", e.pane)
check(
	"→ sur le début de la semaine : dimanche est enregistré",
	read(e.path),
	'{\n  "week_starts_on": "sunday"\n}\n'
)
check("→ : appliqué tout de suite", e.applied[#e.applied].week_starts_on, "sunday")
check("→ : le calendrier est redessiné", e.refreshed, 1)
check(
	"→ : la page montre dimanche",
	setting_line(e, "Début de la semaine"):find("◀ dimanche ▶", 1, true) ~= nil,
	true
)
press(e, "l", e.pane)
check("→ encore : retour à lundi (en boucle)", read(e.path), '{\n  "week_starts_on": "monday"\n}\n')
press(e, "h", e.pane)
press(e, "d", e.pane)
check(
	"d sur le début de la semaine : lundi (la valeur par défaut), rien de plus n'est écrit",
	read(e.path),
	'{\n  "week_starts_on": "monday"\n}\n'
)
press(e, "j", e.pane)
check("↓ : les encadrés", row_selected(e, "Encadrés  "), true)
press(e, "l", e.pane)
check(
	"→ sur les encadrés : « oui » est enregistré",
	read(e.path),
	'{\n  "week_starts_on": "monday",\n  "borders": true\n}\n'
)
check("→ sur les encadrés : appliqué tout de suite", e.cfg.borders, true)
check("→ sur les encadrés : le calendrier est redessiné", e.refreshed >= 3, true)
press(e, "j", e.pane)
press(e, "l", e.pane)
check(
	"→ sur le style : « simple » est enregistré",
	read(e.path),
	'{\n  "week_starts_on": "monday",\n  "borders": true,\n  "border_style": "single"\n}\n'
)
check(
	"→ sur le style : la page montre l'aperçu",
	setting_line(e, "Style du trait"):find("◀ simple ┌─┐ ▶", 1, true) ~= nil,
	true
)
press(e, "j", e.pane)
check("↓ : la couleur du trait", row_selected(e, "Couleur du trait"), true)
check(
	"couleur : l'aperçu suit le style choisi (simple)",
	setting_line(e, "Couleur du trait"):find("◀ Gris ┌─┐ ▶", 1, true) ~= nil,
	true
)
press(e, "l", e.pane)
check("→ sur la couleur : du gris au rouge (la 1re de la palette)", e.cfg.border_color, palette.COLORS[1])
check(
	"→ sur la couleur : enregistrée",
	read(e.path):find('"border_color": "' .. palette.COLORS[1] .. '"', 1, true) ~= nil,
	true
)
check(
	"→ sur la couleur : la page montre son nom",
	setting_line(e, "Couleur du trait"):find("◀ Rouge ┌─┐ ▶", 1, true) ~= nil,
	true
)
check(
	"→ sur la couleur : l'aperçu est dans cette couleur",
	frame_of(e.pane):find(convert.fg(palette.COLORS[1]) .. "┌─┐", 1, true) ~= nil,
	true
)
press(e, "h", e.pane)
press(e, "h", e.pane)
check("← ← : du rouge au gris, puis au dernier choix (en boucle)", e.cfg.border_color, palette.COLORS[16])
press(e, "d", e.pane)
check("d sur la couleur : le gris", e.cfg.border_color, "#8B8E99")
press(e, "j", e.pane)
check("↓ au dernier réglage (la couleur) : il reste choisi", row_selected(e, "Couleur du trait"), true)
press(e, "k", e.pane)
press(e, "k", e.pane)
press(e, "d", e.pane)
check(
	"d sur les encadrés : « non » (la valeur par défaut) est écrit",
	read(e.path),
	'{\n  "week_starts_on": "monday",\n  "borders": false,\n  "border_style": "single",\n  "border_color": "#8B8E99"\n}\n'
)
for _ = 1, 5 do
	press(e, "k", e.pane)
end
check("↑ cinq fois : bloqué au 1er réglage", row_selected(e, "Mois affichés"), true)
e = open({})
e.cfg.week_starts_on = "sunday"
press(e, "Tab", e.pane)
check(
	"week_starts_on = sunday dans wezterm.lua : la page montre dimanche",
	setting_line(e, "Début de la semaine"):find("◀ dimanche ▶", 1, true) ~= nil,
	true
)
e.cfg.week_starts_on = "mardi"
e.page.on_resize(e.window, e.pane)
check(
	"week_starts_on incorrect : la page montre la valeur par défaut (lundi)",
	setting_line(e, "Début de la semaine"):find("◀ lundi ▶", 1, true) ~= nil,
	true
)

-- ============================================================
-- l'onglet Général : langue, objectif par jour, jours par semaine
-- ============================================================
local goal_def = { kind = "number", min = 0.5, max = 24, none = 0, step = 0.5 }
check("objectif : de « aucun », → donne le minimum (0h30)", settings_page.step(goal_def, 0, 1), 0.5)
check("objectif : de « aucun », ← reste « aucun »", settings_page.step(goal_def, 0, -1), 0)
check("objectif : du minimum, ← donne « aucun »", settings_page.step(goal_def, 0.5, -1), 0)
check("objectif : → ajoute 30 min", settings_page.step(goal_def, 7.5, 1), 8)
check(
	"objectif : un nombre entier reste entier (8 et non 8.0)",
	math.type(settings_page.step(goal_def, 7.5, 1)),
	"integer"
)
check("objectif : bloqué à 24", settings_page.step(goal_def, 24, 1), 24)
check(
	"objectif : « aucun » n'a que la flèche de droite",
	settings_page.format_value(goal_def, 0, "aucun"),
	"  aucun ▶"
)
check(
	"objectif : au minimum, la flèche de gauche (vers « aucun »)",
	settings_page.format_value(goal_def, 0.5, "0h30"),
	"◀ 0h30 ▶"
)
check("fallback : la valeur par défaut", settings_page.fallback({ default = 5 }), 5)
check("fallback : sans valeur par défaut, « aucun »", settings_page.fallback({ none = 0 }), 0)
check(
	"fallback : false n'est pas remplacé par « aucun »",
	settings_page.fallback({ default = false, none = 0 }),
	false
)

local gen = list({
	tab = settings_page.TAB.GENERAL,
	row = 2,
	values = { lang = "fr", goal_hours = 7.5, goal_days = 4 },
	message = 0,
})
local gen_plain = {}
for i, line in ipairs(gen) do
	gen_plain[i] = strip(line)
end
check("onglet Général : intitulé, ligne vide, 3 réglages, ligne vide, explication (7 lignes)", #gen, 7)
check("onglet Général : la langue, dans sa propre langue", gen_plain[3], "Langue = ◀ français ▶")
check(
	"onglet Général : l'objectif en heures et minutes, choisi",
	gen_plain[4],
	"▸ Objectif par jour = ◀ 7h30 ▶"
)
check("onglet Général : les jours par semaine", gen_plain[5], "Jours d'objectif par semaine = ◀ 4 sur 7 ▶")
check("onglet Général : l'explication de l'objectif", gen_plain[7], fr.settings_hints.goal_hours)
local gen_none = list({ tab = 3, row = 1, values = { goal_hours = 0 }, message = 0 })
check("onglet Général : objectif 0 affiché « aucun »", strip(gen_none[4]), "Objectif par jour =   aucun ▶")
check(
	"onglet Général : sans valeurs, objectif « aucun » et 5 jours par défaut",
	strip(list({ tab = 3, row = 1, values = {}, message = 0 })[4])
		.. "|"
		.. strip(list({ tab = 3, row = 1, values = {}, message = 0 })[5]),
	"Objectif par jour =   aucun ▶|Jours d'objectif par semaine = ◀ 5 sur 7 ▶"
)
check(
	"onglet Général en anglais : English reste English, aucun devient none",
	strip(list({ tab = 3, row = 1, values = { lang = "en" }, message = 0 }, en)[3])
		.. "|"
		.. strip(list({ tab = 3, row = 1, values = {}, message = 0 }, en)[4]),
	"▸ Language = ◀ English ▶|Daily goal =   none ▶"
)
check(
	"chaque réglage de l'onglet Général a un nom et une explication de 55 caractères au plus (français et anglais)",
	(function()
		for _, labels in ipairs({ fr, en }) do
			for _, key in ipairs(settings_page.GENERAL_SETTINGS) do
				local hint = labels.settings_hints[key]
				if not labels.settings_names[key] or not hint or utf8.len(hint) > 55 then
					return key
				end
			end
		end
		return true
	end)(),
	true
)
check(
	"aucune ligne de l'onglet Général ne dépasse la largeur minimum du panneau",
	(function()
		for _, labels in ipairs({ fr, en }) do
			for row = 1, 3 do
				for _, line in
					ipairs(
						list({ tab = 3, row = row, values = { goal_hours = 23.5, goal_days = 7 }, message = 4 }, labels)
					)
				do
					if utf8.len(strip(line)) > settings_view.MIN_LEFT then
						return strip(line)
					end
				end
			end
		end
		return true
	end)(),
	true
)

-- dans la page
local function to_general(env)
	press(env, "Tab", env.pane)
	press(env, "Tab", env.pane)
end
e = open({})
press(e, "Tab", e.pane)
press(e, "j", e.pane)
press(e, "j", e.pane)
check("(avant : le 3e réglage de l'onglet Calendrier est choisi)", row_selected(e, "Début de la semaine"), true)
press(e, "Tab", e.pane)
check("Général : l'onglet est affiché", open_tab_is(e, "Général"), true)
check(
	"Général : le 1er réglage (la langue) est choisi, même si on était sur un autre réglage avant",
	row_selected(e, "Langue"),
	true
)
press(e, "j", e.pane)
press(e, "l", e.pane)
check("objectif → : 0h30 est enregistré", read(e.path), '{\n  "goal_hours": 0.5\n}\n')
check("objectif → : appliqué tout de suite", e.cfg.goal_hours, 0.5)
check(
	"objectif → : la page montre 0h30",
	setting_line(e, "Objectif par jour"):find("◀ 0h30 ▶", 1, true) ~= nil,
	true
)
for _ = 1, 15 do
	press(e, "l", e.pane)
end
check("objectif → seize fois : 8h00", read(e.path), '{\n  "goal_hours": 8\n}\n')
check("objectif : la page montre 8h00", setting_line(e, "Objectif par jour"):find("◀ 8h00 ▶", 1, true) ~= nil, true)
press(e, "d", e.pane)
check(
	"objectif d : « aucun » est écrit (0), pas retiré : il l'emporte sur wezterm.lua",
	read(e.path),
	'{\n  "goal_hours": 0\n}\n'
)
check("objectif d : appliqué (0)", e.cfg.goal_hours, 0)
check(
	"objectif d : la page montre « aucun »",
	setting_line(e, "Objectif par jour"):find("aucun ▶", 1, true) ~= nil,
	true
)
press(e, "j", e.pane)
press(e, "h", e.pane)
check("jours ← : 4 est enregistré", read(e.path), '{\n  "goal_hours": 0,\n  "goal_days": 4\n}\n')
-- l'objectif écrit dans wezterm.lua est montré
e = open({})
e.cfg.goal_hours = 7
to_general(e)
check(
	"goal_hours = 7 dans wezterm.lua : la page montre 7h00",
	setting_line(e, "Objectif par jour"):find("◀ 7h00 ▶", 1, true) ~= nil,
	true
)
press(e, "j", e.pane)
press(e, "h", e.pane)
check("de 7h00, ← : 6h30", read(e.path), '{\n  "goal_hours": 6.5\n}\n')
-- la langue : la page change de langue tout de suite
e = open({ labels_from_cfg = true })
e.cfg.lang = "fr" -- on part du français (la valeur par défaut est l'anglais)
to_general(e)
press(e, "l", e.pane)
check("langue → : English est enregistré", read(e.path), '{\n  "lang": "en"\n}\n')
check("langue → : appliqué tout de suite", e.cfg.lang, "en")
check("langue → : la page est redessinée en anglais", open_tab_is(e, "General"), true)
check("langue → : la langue garde son nom (English)", shown_text(e):find("◀ English ▶", 1, true) ~= nil, true)
press(e, "d", e.pane)
check(
	"langue d : retour à la valeur par défaut, l'anglais",
	shown_text(e):find("◀ English ▶", 1, true) ~= nil,
	true
)
check("langue d : enregistré", read(e.path), '{\n  "lang": "en"\n}\n')

-- la couleur du trait : les choix et le défilement (fonctions pures)
local choices = settings_page.border_choices(palette.COLORS, fr.palette, "Gris")
check("choix : 17 couleurs (le gris puis la palette)", #choices.colors, 17)
check("choix : le gris d'abord", choices.colors[1] .. " " .. choices.names[1], "#8B8E99 Gris")
check(
	"choix : puis la palette, avec ses noms",
	choices.colors[4] .. " " .. choices.names[4],
	palette.COLORS[3] .. " Or"
)
check("step_choice : du gris, → la 1re couleur", settings_page.step_choice(choices, "#8B8E99", 1), palette.COLORS[1])
check(
	"step_choice : sans tenir compte des minuscules",
	settings_page.step_choice(choices, "#8b8e99", 1),
	palette.COLORS[1]
)
check(
	"step_choice : de la dernière, → le gris",
	settings_page.step_choice(choices, palette.COLORS[16], 1),
	"#8B8E99"
)
check(
	"step_choice : une couleur écrite à la main, → on repart du gris",
	settings_page.step_choice(choices, "#123456", 1),
	palette.COLORS[1]
)
check(
	"couleur écrite à la main : affichée telle quelle",
	strip(list({ tab = 2, row = 1, values = { border_color = "#123456" }, border_choices = choices, message = 0 })[8]),
	"Couleur du trait = ◀ #123456 ╭─╮ ▶"
)
check(
	"anglais : la couleur du trait",
	strip(list({
		tab = 2,
		row = 1,
		values = { border_color = "#8B8E99" },
		border_choices = settings_page.border_choices(palette.COLORS, en.palette, en.settings_values.border_gray),
		message = 0,
	}, en)[8]),
	"Border color = ◀ Gray ╭─╮ ▶"
)
check(
	"aucune ligne de l'onglet Calendrier ne dépasse la largeur minimum du panneau, même avec le plus long nom de couleur",
	(function()
		local long = settings_page.border_choices(palette.COLORS, fr.palette_theme, "Gris")
		for i = 1, #long.colors do
			for _, line in
				ipairs(list({
					tab = 2,
					row = 6,
					values = { border_color = long.colors[i], border_style = "double" },
					border_choices = long,
					message = 4,
				}))
			do
				if utf8.len(strip(line)) > settings_view.MIN_LEFT then
					return strip(line)
				end
			end
		end
		return true
	end)(),
	true
)

-- ============================================================
-- toute la fenêtre est utilisée (le dessin lui-même : tests/pages/test_settings_view.lua)
-- ============================================================
local month_days = { ["2026-10-05"] = 8 * 3600, ["2026-10-06"] = 2 * 3600, ["2026-09-30"] = 4 * 3600 }
e = open({ days = month_days, cols = 200, rows = 60 })
local full = shown_lines(e.pane)
check("plein écran : autant de lignes que la fenêtre", #full, 60)
check(
	"plein écran : chaque ligne fait toute la largeur",
	(function()
		for i, line in ipairs(full) do
			if utf8.len(line) ~= 200 then
				return i .. " : " .. utf8.len(line)
			end
		end
		return true
	end)(),
	true
)
check("plein écran : le cadre commence en haut à gauche", full[1]:sub(1, #"╭"), "╭")
check("plein écran : et finit en bas à droite", full[60]:sub(-#"╯"), "╯")
check(
	"la barre d'onglets : le titre et les trois onglets, dans des cases séparées",
	full[2]:find("│", 1, true) ~= nil
		and full[2]:find("Personnalisation", 1, true) ~= nil
		and full[2]:find("Couleurs", 1, true) ~= nil
		and full[2]:find("Calendrier", 1, true) ~= nil
		and full[2]:find("Général", 1, true) ~= nil,
	true
)
check("la barre d'onglets : plus de crochets", full[2]:find("[", 1, true), nil)
local framed_text = frame_of(e.pane)
check(
	"l'onglet ouvert (Couleurs) sur fond coloré (la couleur enregistrée, ou l'or)",
	framed_text:find(convert.bg(palette.COLORS[palette.DEFAULT_INDEX]), 1, true) ~= nil
		and framed_text:find("Couleurs", 1, true) ~= nil,
	true
)
check(
	"l'aide est soulignée, morceau par morceau (pas les « // » ni les espaces)",
	framed_text:find("\27[4md : défaut\27[24m", 1, true) ~= nil
		and framed_text:find("\27[4mq : fermer\27[24m", 1, true) ~= nil
		and framed_text:find("\27[4mEntrée : enregistrer\27[24m", 1, true) ~= nil,
	true
)
check(
	"aperçu à droite : le mois actuel (son nom en haut à gauche de la grille), avec les jours de la semaine",
	table.concat(full, "\n"):find("Octobre", 1, true) ~= nil
		and table.concat(full, "\n"):find("Mercredi", 1, true) ~= nil,
	true
)
check(
	"aperçu : une ligne par semaine (« Semaine 1 » à « Semaine 5 » pour octobre 2026)",
	table.concat(full, "\n"):find("Semaine 1", 1, true) ~= nil
		and table.concat(full, "\n"):find("Semaine 5", 1, true) ~= nil,
	true
)
check(
	"aperçu : le détail du jour (le total et les barres actif / inactif)",
	table.concat(full, "\n"):find("Total", 1, true) ~= nil
		and table.concat(full, "\n"):find("Actif", 1, true) ~= nil
		and table.concat(full, "\n"):find("Inactif", 1, true) ~= nil,
	true
)
check("aperçu : les vraies heures (le 5 : 8h00)", table.concat(full, "\n"):find("8h00", 1, true) ~= nil, true)
check(
	"aperçu : pas les jours d'un autre mois (le 30 septembre : 4h00)",
	table.concat(full, "\n"):find("4h00", 1, true),
	nil
)
-- l'onglet Couleurs : la couleur sous le curseur, avant Entrée
local cursor_color = gradient.make({ color = palette.COLORS[4] }).color(8 * 3600)
press(e, "l", e.pane)
check(
	"aperçu : la couleur sous le curseur (4, jaune) colore déjà les jours",
	frame_of(e.pane):find(convert.bg(cursor_color), 1, true) ~= nil,
	true
)
check("aperçu : rien n'est enregistré pour autant", read(e.path), nil)
-- les réglages du calendrier changent l'aperçu tout de suite
press(e, "Tab", e.pane)
for _ = 1, 4 do
	press(e, "j", e.pane)
end
press(e, "l", e.pane)
press(e, "l", e.pane)
check(
	"aperçu : le style du trait (double) se voit tout de suite dans la grille de l'aperçu",
	shown_text(e):find("╬", 1, true) ~= nil,
	true
)
press(e, "k", e.pane)
press(e, "k", e.pane)
press(e, "l", e.pane)
check(
	"aperçu : le début de la semaine suit (dimanche d'abord)",
	(function()
		local text = shown_text(e)
		local sunday, monday = text:find("Dimanche", 1, true), text:find("Lundi", 1, true)
		return sunday ~= nil and monday ~= nil and sunday < monday
	end)(),
	true
)
-- le cadre de la page : toujours là, avec le style et la couleur du trait choisis (comme le calendrier)
e = open({ cols = 120, rows = 40 })
e.cfg.borders = false
e.page.on_resize(e.window, e.pane)
check(
	"le cadre de la page est toujours là, même sans les encadrés du calendrier",
	shown_lines(e.pane)[1]:sub(1, #"╭"),
	"╭"
)
e.cfg.border_style = "double"
e.cfg.border_color = "#3366CC"
e.page.on_resize(e.window, e.pane)
check(
	"le cadre suit le style et la couleur du trait",
	frame_of(e.pane):find(convert.fg("#3366CC") .. "╔", 1, true) ~= nil,
	true
)
-- les tailles de fenêtre
e = open({ days = month_days, cols = 100, rows = 40 })
local narrow = e.page.build_lines({ cols = 100, rows = 40 })
check("100 colonnes : pas la place de l'aperçu, la page prend toute la largeur", utf8.len(strip(narrow[1])), 100)
check("100 colonnes : pas d'aperçu", table.concat(narrow, "\n"):find("Octobre 2026", 1, true), nil)
local tiny, _, tiny_fits = e.page.build_lines({ cols = 40, rows = 60 })
check(
	"40 colonnes : trop petit : le message de la page",
	tiny_fits == false and strip(tiny[1]) == "Fenêtre trop petite",
	true
)
local short, _, short_fits = e.page.build_lines({ cols = 120, rows = 15 })
check(
	"15 lignes : trop bas : le message de la page",
	short_fits == false and strip(short[1]) == "Fenêtre trop petite",
	true
)
check(
	"trop petit : le message donne la taille qu'il faut",
	strip(short[2]):find("il faut au moins %d+ colonnes sur %d+ lignes") ~= nil,
	true
)
check(
	"sans heures (ctx.days absent) : jamais d'aperçu, toute la largeur pour les réglages",
	table.concat(open({}).page.build_lines({ cols = 200, rows = 60 }), "\n"):find("Total du mois", 1, true),
	nil
)
-- Shift+Tab : l'onglet précédent
e = open({})
press(e, "Tab", e.pane)
check("Tab : l'onglet suivant (Calendrier)", e.w.GLOBAL.logtime_settings_tab, settings_page.TAB.CALENDAR)
press(e, "SHIFT-Tab", e.pane)
check("Shift+Tab : l'onglet précédent (Couleurs)", e.w.GLOBAL.logtime_settings_tab, settings_page.TAB.COLORS)
press(e, "SHIFT-Tab", e.pane)
check(
	"Shift+Tab depuis le premier : le dernier (Général)",
	e.w.GLOBAL.logtime_settings_tab,
	settings_page.TAB.GENERAL
)

-- rouvrir la page : on revient à l'onglet Couleurs
e = open({})
press(e, "Tab", e.pane)
e.w.GLOBAL.logtime_settings_pane = nil
e.page.open(e.window, e.w.new_pane())
check("rouvrir la page : l'onglet Couleurs est affiché", e.w.GLOBAL.logtime_settings_tab, settings_page.TAB.COLORS)

-- ---- les touches de la page
local expected_keys = {
	"h",
	"LeftArrow",
	"l",
	"RightArrow",
	"k",
	"UpArrow",
	"j",
	"DownArrow",
	"Enter",
	"d",
	"Tab",
	"SHIFT+Tab",
	"q",
	"Escape",
}
local actual = {}
for i, binding in ipairs(open({}).table) do
	actual[i] = (binding.mods and (binding.mods .. "+") or "") .. binding.key
end
check(
	"quatorze touches, dans cet ordre (Shift+Tab compris)",
	table.concat(actual, ","),
	table.concat(expected_keys, ",")
)
check("les événements ont des noms fixes", open({}).table[9].action.name, "logtime-settings-Enter")
check("préfixe des événements", settings_page.EVENT_PREFIX, "logtime-settings")
check("nom de la table de touches", settings_page.TABLE_NAME, "logtime_settings")

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
