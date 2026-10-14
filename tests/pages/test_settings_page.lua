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
local settings_page = load_module("pages/settings_page")
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
-- le dessin (fonction pure)
-- ============================================================
local function render(state, labels)
	local lines, width = settings_page.render(state, labels or fr)
	return lines, width
end
local lines, width = render({ index = 3, current = "#C9AB6B", message = 0 })
check("23 lignes, toujours", #lines, 23)
check("la largeur à centrer est celle du tableau (57)", width, 57)
check("la largeur annoncée est GRID_WIDTH", settings_page.GRID_WIDTH, 57)
local plain = {}
for i, line in ipairs(lines) do
	plain[i] = strip(line)
end
check("ligne 1 : le titre et les onglets (Couleurs affiché)", plain[1], "  Logtime : Personnalisation  [Couleurs]  Calendrier ")
check("ligne 2 : l'aide, première partie", plain[2], "  " .. fr.settings_help1)
check("ligne 3 : l'aide, seconde partie", plain[3], "  " .. fr.settings_help2)
check("ligne 4 : vide", plain[4], "")
check("ligne 5 : l'intitulé du tableau", plain[5], "  Couleur du dégradé")
check("ligne 6 : vide", plain[6], "")
local grid_ok, widths_ok = true, true
for row = 0, 3 do
	local numbers, names = plain[7 + row * 3], plain[8 + row * 3]
	for col = 0, 3 do
		local index = row * 4 + col + 1
		local start = 3 + col * 14
		local number_cell, name_cell = usub(numbers, start, start + 12), usub(names, start, start + 12)
		if not number_cell:find(tostring(index), 1, true) then
			grid_ok = false
		end
		if not name_cell:find(fr.palette[index], 1, true) then
			grid_ok = false
		end
	end
	if layout.visible_width(lines[7 + row * 3]) ~= 57 or layout.visible_width(lines[8 + row * 3]) ~= 57 then
		widths_ok = false
	end
	if row < 3 and plain[9 + row * 3] ~= "" then
		grid_ok = false
	end
end
check("le tableau : les 16 numéros et les 16 noms, à leur place", grid_ok, true)
check("le tableau : chaque ligne fait exactement 57 colonnes", widths_ok, true)
check("ligne 18 : vide", plain[18], "")
check("ligne 19 : l'aperçu du dégradé", plain[19]:find("  Aperçu : 0h", 1, true), 1)
check("ligne 19 : l'aperçu va jusqu'à 24h", plain[19]:sub(-4), " 24h")
check("ligne 20 : le choix", plain[20], "  Choix : 3 Or (#C9AB6B)")
check("ligne 21 : la couleur enregistrée", plain[21], "  Couleur enregistrée : #C9AB6B")
check("ligne 22 : vide (dégradé actif)", plain[22], "")
check("ligne 23 : vide (aucun message)", plain[23], "")

local colors_ok, contrast_ok = true, true
local joined = table.concat(lines, "\n")
for i, color in ipairs(palette.COLORS) do
	if not joined:find(convert.bg(color), 1, true) then
		colors_ok = false
	end
	if not joined:find(convert.bg(color) .. convert.fg(convert.contrast(color)), 1, true) then
		contrast_ok = false
	end
end
check("chaque couleur est dessinée sur son propre fond", colors_ok, true)
check("le texte de chaque couleur est lisible (contraste automatique)", contrast_ok, true)
check("l'aperçu utilise le dégradé de la couleur choisie", lines[19]:find(gradient.make({ color = palette.COLORS[3] }).legend(), 1, true) ~= nil, true)

-- la couleur choisie est entre crochets
local function brackets(state)
	local ls = render(state)
	local found = {}
	for row = 0, 3 do
		for _, offset in ipairs({ 0, 1 }) do
			local line = strip(ls[7 + row * 3 + offset])
			for col = 0, 3 do
				local start = 3 + col * 14
				if usub(line, start, start) == "[" and usub(line, start + 12, start + 12) == "]" then
					found[#found + 1] = row * 4 + col + 1
				end
			end
		end
	end
	return found
end
local every_selected_ok = true
for index = 1, 16 do
	local found = brackets({ index = index, message = 0 })
	if not (#found == 2 and found[1] == index and found[2] == index) then
		every_selected_ok = false
	end
end
check("pour les 16 choix : la couleur choisie (et elle seule) est entre crochets, sur ses deux lignes", every_selected_ok, true)
check("le choix change la ligne « Choix »", strip(render({ index = 11, message = 0 })[20]), "  Choix : 11 Bleu (#6989C9)")
check("le choix 16 : le gris", strip(render({ index = 16, message = 0 })[20]), "  Choix : 16 Gris (#999999)")

-- la couleur enregistrée
check("couleur enregistrée absente : ligne vide", strip(render({ index = 3, message = 0 })[21]), "")
check("couleur enregistrée hors palette : « personnalisée »", strip(render({ index = 3, current = "#123456", message = 0 })[21]), "  Couleur enregistrée : #123456 (personnalisée)")
-- dégradé désactivé
check("dégradé désactivé : la ligne d'avertissement", strip(render({ index = 3, gradient_off = true, message = 0 })[22]), "  " .. fr.settings_gradient_off)
-- messages
check("message : enregistré", strip(render({ index = 3, message = settings_page.MESSAGE.SAVED })[23]), "  " .. fr.settings_saved)
check("message : échec", strip(render({ index = 3, message = settings_page.MESSAGE.FAILED })[23]), "  " .. fr.settings_failed)
check("message inconnu : ligne vide", strip(render({ index = 3, message = 99 })[23]), "")
local stable = true
for _, state in ipairs({ { index = 1, message = 0 }, { index = 16, current = "#C9AB6B", gradient_off = true, message = 1 }, { index = 8, current = "#123456", message = 2 } }) do
	if #render(state) ~= 23 then
		stable = false
	end
end
check("le nombre de lignes ne change jamais (la page ne saute pas)", stable, true)
local english = render({ index = 3, current = "#C9AB6B", message = 1 }, en)
check("anglais : le titre et les onglets", strip(english[1]), "  Logtime : Settings  [Colors]  Calendar ")
check("anglais : le nom de la couleur", strip(english[20]), "  Choice: 3 Gold (#C9AB6B)")
check("anglais : le message", strip(english[23]), "  " .. en.settings_saved)
check("anglais : les noms dans le tableau", strip(english[8]):find("Gold", 1, true) ~= nil, true)

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
	w.next_id = 500
	function w.new_pane(cols, rows)
		w.next_id = w.next_id + 1
		local tab = { activated = false }
		function tab:activate() self.activated = true end
		local pane = { id = w.next_id, injected = {}, dims = { viewport_rows = rows or opts.rows or 40, cols = cols or opts.cols or 120 }, the_tab = tab }
		function pane:pane_id() return self.id end
		function pane:get_dimensions() return self.dims end
		function pane:inject_output(text) self.injected[#self.injected + 1] = text end
		function pane:tab() return self.the_tab end
		w.panes[pane.id] = pane
		return pane
	end
	local env = { w = w, home = home, path = opts.path or (home .. "/.logtime_settings.json"), cfg = { gradient_color = opts.color }, applied = {}, refreshed = 0 }
	if opts.gradient == false then
		env.cfg.gradient = false
	end
	local win = { performed = {} }
	function win:perform_action(action, pane) self.performed[#self.performed + 1] = action.kind end
	function win:toast_notification() end
	function win:mux_window()
		return { spawn_tab = function(_, spec)
			local pane = w.new_pane()
			w.spawned[#w.spawned + 1] = pane
			return pane.the_tab, pane, nil
		end }
	end
	env.window = win
	env.page = settings_page.create({
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
		end,
		refresh_calendar = opts.refresh or function(window, pane) env.refreshed = env.refreshed + 1 end,
	})
	env.table = env.page.key_table()
	return env
end
-- Comme WezTerm : une touche de la page émet son événement
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
check("sans taille connue : la page entière", #got == 23 and fits == true, true)
got, got_width, fits = env.page.build_lines({ cols = 57, rows = 23 })
check("57 x 23 : la page tient (taille exacte)", fits, true)
got, got_width, fits = env.page.build_lines({ cols = 56, rows = 40 })
check("56 colonnes : trop étroit : message", fits == false and #got == 2, true)
check("56 colonnes : le message dit la taille nécessaire", strip(got[2]), "Il faut au moins 57 colonnes sur 23 lignes.")
check("56 colonnes : le titre du message", strip(got[1]), "Fenêtre trop petite")
got, got_width, fits = env.page.build_lines({ cols = 120, rows = 22 })
check("22 lignes : trop bas : message", fits, false)
got, got_width, fits = env.page.build_lines({ cols = 200, rows = 60 })
check("200 x 60 : la page tient", fits, true)

-- ---- l'ouverture
env = open({})
check("ouverture : un onglet est ouvert", #env.w.spawned, 1)
check("ouverture : l'onglet est activé", env.pane.the_tab.activated, true)
check("ouverture : un dessin envoyé", #env.pane.injected >= 1, true)
check("ouverture : les touches de la page sont activées", env.window.performed[#env.window.performed], "ActivateKeyTable")
check("ouverture : deux redessins différés (0,4 s et 1,2 s)", #env.w.timers == 2 and env.w.timers[1].seconds == 0.4 and env.w.timers[2].seconds == 1.2, true)
check("ouverture : le choix de départ est l'or (pas de couleur enregistrée)", chosen(env.pane), 3)
check("ouverture : le journal note l'ouverture", #env.w.logs.info >= 1 and env.w.logs.info[1]:find("page de personnalisation ouverte dans le panneau " .. env.pane.id, 1, true) ~= nil, true)
check("ouverture : aucune erreur", #env.w.logs.error, 0)
env.page.open(env.window, env.w.new_pane())
check("ouvrir deux fois : pas de second onglet", #env.w.spawned, 1)
local before = #env.pane.injected
env.page.open(env.window, env.w.new_pane())
check("ouvrir deux fois : la page existante est redessinée", #env.pane.injected, before + 1)

-- le choix de départ suit la couleur enregistrée
for _, case in ipairs({ { "#6989C9", 11 }, { "#c96969", 1 }, { "#999999", 16 }, { "#3366CC", 11 }, { "#808080", 16 }, { "pas une couleur", 3 }, { nil, 3 } }) do
local e = open({ color = case[1] })
check("choix de départ pour la couleur " .. tostring(case[1]) .. " : " .. case[2], chosen(e.pane), case[2])
end
local e = open({ color = "#123456" })
check("couleur enregistrée hors palette : indiquée comme personnalisée", table.concat(shown_lines(e.pane), "\n"):find("(personnalisée)", 1, true) ~= nil, true)
e = open({ color = "#6989C9" })
check("couleur enregistrée de la palette : indiquée sans « personnalisée »", table.concat(shown_lines(e.pane), "\n"):find("Couleur enregistrée : #6989C9", 1, true) ~= nil and table.concat(shown_lines(e.pane), "\n"):find("personnalisée", 1, true) == nil, true)
e = open({ gradient = false })
check("dégradé désactivé : l'avertissement est affiché", table.concat(shown_lines(e.pane), "\n"):find("Dégradé désactivé", 1, true) ~= nil, true)
e = open({})
check("dégradé actif : pas d'avertissement", table.concat(shown_lines(e.pane), "\n"):find("Dégradé désactivé", 1, true), nil)

-- ---- le centrage dans la fenêtre
e = open({ cols = 120, rows = 40 })
local shown = shown_lines(e.pane)
check("centré : (40 - 23) / 2 = 8 lignes vides en haut", (function()
local n = 0
for _, line in ipairs(shown) do
if line ~= "" then
break
end
n = n + 1
end
return n
end)(), 8)
local _, title_line = (function()
for i, line in ipairs(shown) do
if line:find("Personnalisation", 1, true) then
return i, line
end
end
end)()
check("centré : marge à gauche (120 - 57) / 2 = 31, plus 2 espaces", leading(title_line), 31 + 2)
check("centré : le dessin tient dans la fenêtre", #shown <= 40, true)

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
check("les 16 cases sont atteignables", (function()
local reached = {}
for row = 0, 3 do
for col = 0, 3 do
local keys = {}
for _ = 1, 4 do keys[#keys + 1] = "k" end
for _ = 1, 4 do keys[#keys + 1] = "h" end
for _ = 1, row do keys[#keys + 1] = "j" end
for _ = 1, col do keys[#keys + 1] = "l" end
reached[index_after(keys)] = true
end
end
local n = 0
for _ in pairs(reached) do n = n + 1 end
return n
end)(), 16)
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
check("Entrée : la couleur est appliquée tout de suite", #e.applied == 1 and e.applied[1].gradient_color == "#6989C9", true)
check("Entrée : le calendrier est redessiné une fois", e.refreshed, 1)
check("Entrée : le message « enregistré » est affiché", table.concat(shown_lines(e.pane), "\n"):find("✓ Enregistré", 1, true) ~= nil, true)
check("Entrée : la couleur enregistrée est mise à jour dans la page", table.concat(shown_lines(e.pane), "\n"):find("Couleur enregistrée : #6989C9", 1, true) ~= nil, true)
check("Entrée : aucune erreur", #e.w.logs.error, 0)
check("Entrée : pas de copie de sécurité au premier enregistrement", read(e.path .. ".bak"), nil)
press(e, "l", e.pane)
check("un déplacement efface le message", table.concat(shown_lines(e.pane), "\n"):find("✓ Enregistré", 1, true), nil)
press(e, "Enter", e.pane)
check("un second enregistrement : le fichier a la nouvelle couleur", read(e.path), '{\n  "gradient_color": "#7969C9"\n}\n')
check("un second enregistrement : la copie de sécurité est l'ancien état", read(e.path .. ".bak"), '{\n  "gradient_color": "#6989C9"\n}\n')
check("un second enregistrement : deux couleurs appliquées au total", #e.applied, 2)

-- les autres réglages du fichier sont gardés
e = open({})
write(e.path, '{"max_months": 4, "lang": "en", "gradient": true}')
press(e, "Enter", e.pane)
check("Entrée garde les autres réglages du fichier (dans l'ordre du schéma)", read(e.path), '{\n  "lang": "en",\n  "max_months": 4,\n  "gradient": true,\n  "gradient_color": "#C9AB6B"\n}\n')
-- un réglage inconnu ou incorrect du fichier n'empêche pas l'enregistrement
e = open({})
write(e.path, '{"gradiant": true, "max_months": 100, "center": false}')
press(e, "Enter", e.pane)
check("Entrée avec des réglages incorrects dans le fichier : ils sont ignorés, les bons gardés", read(e.path), '{\n  "center": false,\n  "gradient_color": "#C9AB6B"\n}\n')
-- fichier illisible : mis de côté, jamais perdu
e = open({})
write(e.path, "{ illisible")
press(e, "Enter", e.pane)
check("fichier illisible : le nouveau fichier est bon", read(e.path), '{\n  "gradient_color": "#C9AB6B"\n}\n')
check("fichier illisible : l'ancien est mis de côté", (function()
local p = io.popen("ls -1A '" .. e.home .. "'")
for name in p:lines() do
if name:find(".corrupt-", 1, true) then
p:close()
return read(e.home .. "/" .. name)
end
end
p:close()
end)(), "{ illisible")
check("fichier illisible : message « enregistré » quand même", table.concat(shown_lines(e.pane), "\n"):find("✓ Enregistré", 1, true) ~= nil, true)
-- fichier illisible avec une bonne copie de sécurité : ses réglages sont repris
e = open({})
write(e.path, "abîmé")
write(e.path .. ".bak", '{"max_months": 5}')
press(e, "Enter", e.pane)
check("fichier illisible avec copie : les réglages de la copie sont repris", read(e.path), '{\n  "max_months": 5,\n  "gradient_color": "#C9AB6B"\n}\n')

-- échec d'enregistrement : le dossier n'existe pas
e = open({ path = "/tmp/dossier_qui_nexiste_pas_logtime/sous/.logtime_settings.json" })
press(e, "Enter", e.pane)
check("échec : le message d'échec est affiché", table.concat(shown_lines(e.pane), "\n"):find("✗ Enregistrement impossible", 1, true) ~= nil, true)
check("échec : l'erreur est écrite dans les journaux", #e.w.logs.error == 1 and e.w.logs.error[1]:find("enregistrement des réglages impossible", 1, true) ~= nil, true)
check("échec : rien n'est appliqué", #e.applied, 0)
check("échec : le calendrier n'est pas redessiné", e.refreshed, 0)
check("échec : la page reste utilisable (on peut se déplacer)", (function()
press(e, "l", e.pane)
return chosen(e.pane)
end)(), 4)
-- le calendrier ne répond pas : ça n'empêche pas l'enregistrement
e = open({ refresh = function() error("boum") end })
press(e, "Enter", e.pane)
check("le redessin du calendrier plante : l'enregistrement a réussi quand même", read(e.path) ~= nil and table.concat(shown_lines(e.pane), "\n"):find("✓ Enregistré", 1, true) ~= nil, true)
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
check(key .. " : les touches de la page sont retirées puis l'onglet est fermé", table.concat(e.window.performed, ","):match("PopKeyTable,CloseCurrentTab$") ~= nil, true)
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
check("touche dans un autre onglet : les touches de la page sont retirées puis la touche est rendue", table.concat(e.window.performed, ",", performed_before + 1), "PopKeyTable,SendKey")
check("touche dans un autre onglet : le choix n'a pas bougé", chosen(e.pane), 3)

-- ---- le redimensionnement
e = open({ cols = 120, rows = 40 })
local drawn = #e.pane.injected
e.w.timers = {}
e.pane.dims.cols = 50
e.page.on_resize(e.window, e.pane)
check("redimensionnement : la page est redessinée", #e.pane.injected, drawn + 1)
check("redimensionnement : trop étroit, le message remplace la page", table.concat(shown_lines(e.pane), "\n"):find("Fenêtre trop petite", 1, true) ~= nil, true)
check("redimensionnement : deux redessins différés", #e.w.timers == 2 and e.w.timers[1].seconds == 0.3 and e.w.timers[2].seconds == 1.0, true)
e.pane.dims.cols = 120
e.page.on_resize(e.window, e.pane)
check("agrandi : la page revient", table.concat(shown_lines(e.pane), "\n"):find("Couleur du dégradé", 1, true) ~= nil, true)
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

-- le dessin (fonction pure)
local cal = render({ tab = settings_page.TAB.CALENDAR, row = 1, values = { max_months = 12 }, message = 0 })
local cal_plain = {}
for i, line in ipairs(cal) do
	cal_plain[i] = strip(line)
end
check("onglet Calendrier : 23 lignes, comme l'onglet Couleurs", #cal, 23)
check("onglet Calendrier : ligne 1, l'onglet affiché est entre crochets", cal_plain[1], "  Logtime : Personnalisation   Couleurs  [Calendrier]")
check("onglet Calendrier : ligne 2, l'aide", cal_plain[2], "  " .. fr.settings_calendar_help1)
check("onglet Calendrier : ligne 3, l'aide", cal_plain[3], "  " .. fr.settings_calendar_help2)
check("onglet Calendrier : ligne 5, l'intitulé", cal_plain[5], "  Réglages du calendrier")
check("onglet Calendrier : ligne 7, le réglage choisi et sa valeur alignée", cal_plain[7], "▸ Mois affichés au maximum      ◀ 12")
check("onglet Calendrier : ligne 11, l'explication du réglage choisi", cal_plain[11], "  " .. fr.settings_hints.max_months)
check("onglet Calendrier : ligne 23 vide (aucun message)", cal_plain[23], "")
check("onglet Calendrier : le message « enregistré »", strip(render({ tab = 2, row = 1, values = { max_months = 6 }, message = settings_page.MESSAGE.SETTING_SAVED })[23]), "  " .. fr.settings_setting_saved)
check("onglet Calendrier : le message d'échec", strip(render({ tab = 2, row = 1, values = { max_months = 6 }, message = settings_page.MESSAGE.FAILED })[23]), "  " .. fr.settings_failed)
check("onglet Calendrier : valeur absente, la valeur par défaut (12)", strip(render({ tab = 2, row = 1, values = {}, message = 0 })[7]):match("◀ 12$") ~= nil, true)
check("onglet Calendrier : aucune ligne ne dépasse 57 colonnes (français et anglais)", (function()
	for _, labels in ipairs({ fr, en }) do
		for _, line in ipairs(render({ tab = 2, row = 1, values = { max_months = 6 }, message = 4 }, labels)) do
			if utf8.len(strip(line)) > 57 then
				return false
			end
		end
	end
	return true
end)(), true)
check("anglais : la barre d'onglets", strip(render({ tab = 2, row = 1, values = {}, message = 0 }, en)[1]), "  Logtime : Settings   Colors  [Calendar]")

-- la page, avec la fausse API
local function shown_text(env)
	return table.concat(shown_lines(env.pane), "\n")
end
local function months_line(env)
	for _, line in ipairs(shown_lines(env.pane)) do
		if line:find("Mois affichés au maximum", 1, true) then
			return line
		end
	end
end

e = open({})
press(e, "Tab", e.pane)
check("Tab : l'onglet Calendrier est affiché", shown_text(e):find("[Calendrier]", 1, true) ~= nil, true)
check("Tab : le réglage est affiché avec sa valeur (12 par défaut)", months_line(e):match("◀ 12$") ~= nil, true)
check("Tab : la page tient toujours dans 57 x 23", select(3, e.page.build_lines({ cols = 57, rows = 23 })), true)
check("Tab : rien n'est écrit en changeant d'onglet", read(e.path), nil)
press(e, "Tab", e.pane)
check("Tab deux fois : retour à l'onglet Couleurs", shown_text(e):find("[Couleurs]", 1, true) ~= nil, true)

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
check("↓ ↑ : le 1er réglage est de nouveau choisi", months_line(e):find("▸ Mois", 1, true) ~= nil, true)
check("↑ ↓ : rien n'est écrit", #e.applied, writes)
-- Entrée ne fait rien dans cet onglet (chaque changement y est déjà enregistré)
press(e, "Enter", e.pane)
check("Entrée dans l'onglet Calendrier : rien d'autre n'est enregistré", #e.applied, writes)

-- les autres réglages du fichier sont gardés
e = open({})
write(e.path, '{"gradient_color": "#6989C9", "lang": "en"}')
press(e, "Tab", e.pane)
press(e, "h", e.pane)
check("← garde les autres réglages du fichier", read(e.path), '{\n  "lang": "en",\n  "max_months": 11,\n  "gradient_color": "#6989C9"\n}\n')

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
check("échec (onglet Calendrier) : le message d'échec", shown_text(e):find("✗ Enregistrement impossible", 1, true) ~= nil, true)
check("échec (onglet Calendrier) : rien n'est appliqué", #e.applied, 0)
check("échec (onglet Calendrier) : la valeur affichée ne change pas", months_line(e):match("◀ 12$") ~= nil, true)

-- changer d'onglet garde la couleur choisie et efface le message
e = open({})
press(e, "l", e.pane)
press(e, "Enter", e.pane)
press(e, "Tab", e.pane)
check("Tab efface le message", shown_text(e):find("✓", 1, true), nil)
press(e, "Tab", e.pane)
check("Tab deux fois : la couleur choisie est gardée (4)", chosen(e.pane), 4)

-- ---- les choix et les oui/non (début de la semaine, place du mois, centrage)
local week_def = { kind = "enum", values = { "monday", "sunday" } }
local three_def = { kind = "enum", values = { "a", "b", "c" } }
local bool_def = { kind = "boolean" }
check("step choix : → passe à la valeur suivante", settings_page.step(week_def, "monday", 1), "sunday")
check("step choix : → après la dernière, retour à la première", settings_page.step(week_def, "sunday", 1), "monday")
check("step choix : ← avant la première, la dernière", settings_page.step(three_def, "a", -1), "c")
check("step choix : ← dans une liste de trois", settings_page.step(three_def, "c", -1), "b")
check("step choix : valeur inconnue, on part de la première", settings_page.step(three_def, "zzz", 1), "b")
check("step oui/non : → inverse", settings_page.step(bool_def, true, 1), false)
check("step oui/non : ← inverse aussi", settings_page.step(bool_def, false, -1), true)
check("format choix : toujours les deux flèches", settings_page.format_value(week_def, "monday", "lundi"), "◀ lundi ▶")
check("format oui/non : toujours les deux flèches", settings_page.format_value(bool_def, false, "non"), "◀ non ▶")

local four = render({ tab = 2, row = 3, values = { max_months = 6, months_anchor = "first", week_starts_on = "sunday" }, message = 0 })
local four_plain = {}
for i, line in ipairs(four) do
	four_plain[i] = strip(line)
end
check("trois réglages : toujours 23 lignes", #four, 23)
check("ligne 7 : le nombre de mois", four_plain[7], "  Mois affichés au maximum      ◀ 6 ▶")
check("ligne 8 : la place du mois choisi (traduite)", four_plain[8], "  Place du mois choisi          ◀ au début ▶")
check("ligne 9 : le début de la semaine, choisi (▸)", four_plain[9], "▸ Début de la semaine           ◀ dimanche ▶")
check("ligne 10 : vide (le centrage n'est pas réglable : toujours centré)", four_plain[10], "")
check("le centrage n'apparaît pas dans la page", table.concat(four_plain, "\n"):find("centr", 1, true), nil)
check("ligne 11 : l'explication du réglage choisi (le 3e)", four_plain[11], "  " .. fr.settings_hints.week_starts_on)
local four_en = render({ tab = 2, row = 1, values = { months_anchor = "last", week_starts_on = "monday" }, message = 0 }, en)
check("anglais : le début de la semaine", strip(four_en[9]), "  Week starts on                ◀ Monday ▶")
check("chaque réglage de l'onglet a un nom, une explication et (si choix) ses valeurs, en français et en anglais", (function()
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
end)(), true)

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
check("↓ : le 2e réglage est choisi", setting_line(e, "Place du mois choisi"):find("▸", 1, true) ~= nil, true)
check("↓ : le 1er ne l'est plus", setting_line(e, "Mois affichés"):find("▸", 1, true), nil)
check("↓ : son explication est affichée", shown_text(e):find(fr.settings_hints.months_anchor, 1, true) ~= nil, true)
check("↓ : rien n'est écrit", read(e.path), nil)
press(e, "DownArrow", e.pane)
press(e, "l", e.pane)
check("→ sur le début de la semaine : dimanche est enregistré", read(e.path), '{\n  "week_starts_on": "sunday"\n}\n')
check("→ : appliqué tout de suite", e.applied[#e.applied].week_starts_on, "sunday")
check("→ : le calendrier est redessiné", e.refreshed, 1)
check("→ : la page montre dimanche", setting_line(e, "Début de la semaine"):find("◀ dimanche ▶", 1, true) ~= nil, true)
press(e, "l", e.pane)
check("→ encore : retour à lundi (en boucle)", read(e.path), '{\n  "week_starts_on": "monday"\n}\n')
press(e, "h", e.pane)
press(e, "d", e.pane)
check("d sur le début de la semaine : lundi (la valeur par défaut), rien de plus n'est écrit", read(e.path), '{\n  "week_starts_on": "monday"\n}\n')
press(e, "j", e.pane)
check("↓ au dernier réglage : il reste choisi", setting_line(e, "Début de la semaine"):find("▸", 1, true) ~= nil, true)
press(e, "k", e.pane)
press(e, "k", e.pane)
press(e, "k", e.pane)
check("↑ trois fois : bloqué au 1er réglage", setting_line(e, "Mois affichés"):find("▸", 1, true) ~= nil, true)
e = open({})
e.cfg.week_starts_on = "sunday"
press(e, "Tab", e.pane)
check("week_starts_on = sunday dans wezterm.lua : la page montre dimanche", setting_line(e, "Début de la semaine"):find("◀ dimanche ▶", 1, true) ~= nil, true)
e.cfg.week_starts_on = "mardi"
e.page.on_resize(e.window, e.pane)
check("week_starts_on incorrect : la page montre la valeur par défaut (lundi)", setting_line(e, "Début de la semaine"):find("◀ lundi ▶", 1, true) ~= nil, true)

-- rouvrir la page : on revient à l'onglet Couleurs
e = open({})
press(e, "Tab", e.pane)
e.w.GLOBAL.logtime_settings_pane = nil
e.page.open(e.window, e.w.new_pane())
check("rouvrir la page : l'onglet Couleurs est affiché", e.w.GLOBAL.logtime_settings_tab, settings_page.TAB.COLORS)

-- ---- les touches de la page
local expected_keys = { "h", "LeftArrow", "l", "RightArrow", "k", "UpArrow", "j", "DownArrow", "Enter", "d", "Tab", "q", "Escape" }
local actual = {}
for i, binding in ipairs(open({}).table) do
actual[i] = binding.key
end
check("treize touches, dans cet ordre", table.concat(actual, ","), table.concat(expected_keys, ","))
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
