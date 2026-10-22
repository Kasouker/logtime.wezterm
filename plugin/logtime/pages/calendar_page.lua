-- plugin/logtime/pages/calendar_page.lua : la page du calendrier (un onglet où l'on change de mois avec les flèches).
local load = ...
local assemble = load("calendar/assemble")
local board = load("calendar/board")
local day_detail = load("calendar/day_detail")
local dates = load("calendar/dates")
local layout = load("calendar/layout")
local screen = load("ui/screen")
local keytable = load("ui/keytable")
local safe = load("ui/safe")
local gradient = load("color/gradient")
local stats = load("calendar/stats")
local idle = load("core/idle")
local convert = load("color/convert")

local M = {}

M.TABLE_NAME = "logtime_page"
M.VIEW = { MONTHS = 1, YEAR = 2, DAY = 3 } -- YEAR : la vue « tout en un » (calendar/board.lua)
M.DEFAULT_DIMS = { cols = 120, rows = 40 } -- la taille quand la fenêtre est inconnue (dans les tests)

-- ctx fournit ce que la page ne sait pas faire seule :
--   wezterm       l'API de WezTerm
--   G             wezterm.GLOBAL
--   num(v)        convertit une valeur lue dans GLOBAL en vrai nombre (nil si elle est absente)
--   days()        les heures par jour (table { ["2026-10-12"] = secondes })
--   idle_days()   le temps inactif par jour, même forme (facultatif)
--   projects()    le temps actif par projet et par jour : { ["2026-10-12"] = { [projet] = secondes } } (facultatif)
--   today_key()   la date du jour ("2026-10-12")
--   cfg()         les réglages (week_starts_on, goal_hours, day_offset, max_months, months_anchor, center, gradient...)
--   labels()      les textes dans la langue choisie
--   blocker_args() le programme qui garde l'onglet ouvert
function M.create(ctx)
	local wezterm, G, num = ctx.wezterm, ctx.G, ctx.num
	local act = wezterm.action
	local ui = screen.bind(wezterm)
	local page = {}

	-- L'état de la page, gardé dans wezterm.GLOBAL sous forme de simples nombres :
	--   logtime_page_pane (le panneau de la page), logtime_page_year, logtime_page_month (le mois affiché),
	--   logtime_page_day (le jour choisi dans ce mois, flèches), logtime_page_view (M.VIEW.MONTHS, M.VIEW.YEAR (touche a) ou
	--   M.VIEW.DAY (le détail du jour choisi, touche Entrée))
	local function page_id()
		return num(G.logtime_page_pane)
	end

	local function current_month()
		local t = os.date("*t", os.time() + (ctx.cfg().day_offset or 0))
		return t.year, t.month, t.day
	end

	local function selected_month()
		local year, month = num(G.logtime_page_year), num(G.logtime_page_month)
		if not year or not month then
			return current_month()
		end
		return year, month
	end

	-- Le jour choisi : année, mois, jour (aujourd'hui s'il n'y en a pas ; jamais plus loin que la fin du mois).
	local function selected_day()
		local year, month = selected_month()
		local d = num(G.logtime_page_day)
		if not d then
			local ty, tm, td = current_month()
			d = (ty == year and tm == month) and td or 1
		end
		return year, month, math.max(1, math.min(math.floor(d), dates.days_in_month(year, month)))
	end

	-- Les réglages, avec le dégradé de couleurs (voir color/gradient.lua, apply_to).
	local with_gradient = gradient.apply_to

	-- La taille de la fenêtre du panneau : { cols, rows } (nil si on ne peut pas la lire).
	local function dims_of(pane)
		local ok, dims = pcall(function()
			return pane:get_dimensions()
		end)
		if ok and dims then
			return { cols = dims.cols, rows = dims.viewport_rows }
		end
		return nil
	end

	-- Après la légende : « Aujourd'hui : 1h30 inactif sur 10h04 (15 %) » (rien si rien n'est compté aujourd'hui).
	local function idle_today(labels)
		local idle_days = ctx.idle_days and ctx.idle_days()
		if not idle_days then
			return "" -- pas de temps inactif (ou il n'est pas compté : réglage count_idle)
		end
		local today = ctx.today_key()
		local total = ctx.days()[today] or 0
		if total <= 0 then
			return ""
		end
		local secs, percent = idle.share(total, idle_days[today])
		return "     " .. string.format(labels.idle_today, stats.hm(secs), stats.hm(total), percent)
	end

	local function current_view()
		local view = num(G.logtime_page_view)
		if view == M.VIEW.YEAR or view == M.VIEW.DAY then
			return view
		end
		return M.VIEW.MONTHS
	end

	-- Le détail du jour choisi (calendar/day_detail.lua), avec sa ligne d'aide. S'il ne tient pas : le message
	-- « fenêtre trop petite ».
	local function build_day_text(dims, labels, cfg)
		local help = "  " .. labels.title .. "   " .. labels.day_help
		local key = dates.key(selected_day())
		local idle_days = ctx.idle_days and ctx.idle_days() or nil
		local projects = ctx.projects and ctx.projects() or nil
		local lines, width = day_detail.render(ctx.days(), idle_days, key, ctx.today_key(), cfg, labels, projects)
		local needed = #lines + 2
		if dims and ((tonumber(dims.cols) or 0) < width or (tonumber(dims.rows) or 0) < needed) then
			local title, hint = labels.too_small, string.format(labels.too_small_hint, width, needed)
			return title .. "\n" .. hint, 0, math.max(layout.visible_width(title), layout.visible_width(hint))
		end
		-- on centre le cadre ; l'aide, plus large, commence au même endroit et déborde à droite
		return help .. "\n\n" .. table.concat(lines, "\n"), 1, width
	end

	-- La vue « tout en un » (touche a, calendar/board.lua) : l'année, le mois, la semaine et le jour choisis, sur toute
	-- la fenêtre. Si elle ne tient pas : le message « fenêtre trop petite », avec la taille nécessaire.
	local function build_board_text(dims, labels, cfg)
		dims = dims or M.DEFAULT_DIMS
		local year, month = selected_month()
		local b = assemble.BORDER_STYLES[cfg.border_style] or assemble.BORDER_STYLES.rounded
		local border = cfg.border_color
		if type(border) ~= "string" or not border:match("^#%x%x%x%x%x%x$") then
			border = assemble.BORDER_COLOR
		end
		local lines, min_w, min_h = board.render({
			days = ctx.days(),
			idle_days = ctx.idle_days and ctx.idle_days() or nil,
			projects = ctx.projects and ctx.projects() or nil,
			timeline = ctx.timeline and ctx.timeline() or nil,
			year = year,
			month = month,
			day_key = dates.key(selected_day()),
			today_key = ctx.today_key(),
			cfg = cfg,
			labels = labels,
			b = b,
			edge = convert.fg(border),
			legend = board.legend(assemble.legend(cfg, labels), labels),
			-- le mois choisi sous l'année : rempli de la couleur choisie dans F4 (comme l'onglet ouvert de F4)
			accent = type(cfg.gradient_color) == "string"
					and cfg.gradient_color:match("^#%x%x%x%x%x%x$")
					and cfg.gradient_color
				or gradient.DEFAULT_COLOR,
		}, tonumber(dims.cols) or 0, tonumber(dims.rows) or 0)
		if not lines then
			local title, hint = labels.too_small, string.format(labels.too_small_hint, min_w, min_h)
			return title .. "\n" .. hint, 0, math.max(layout.visible_width(title), layout.visible_width(hint))
		end
		return table.concat(lines, "\n"), 12, tonumber(dims.cols)
	end

	-- Le texte de la page : une ligne d'aide, puis le ou les mois (ou l'année, touche a). Le nombre de mois dépend de la taille de la fenêtre
	-- (dims = { cols, rows } ; sans taille, un seul mois). Renvoie le texte, le nombre de mois affichés et la largeur
	-- du calendrier (la largeur qu'on centre).
	function page.build_text(dims)
		local labels, cfg = ctx.labels(), {}
		for key, value in pairs(with_gradient(ctx.cfg())) do
			cfg[key] = value -- une copie : la case choisie ne doit pas aller dans les vrais réglages
		end
		local year, month = selected_month()
		if current_view() == M.VIEW.YEAR then
			return build_board_text(dims, labels, cfg)
		end
		if current_view() == M.VIEW.DAY then
			return build_day_text(dims, labels, cfg)
		end
		cfg.selected_key = dates.key(selected_day())
		local help = "  " .. labels.title .. "   " .. labels.page_help
		local block_width, block_height = assemble.width(cfg), assemble.height(cfg) -- plus grand avec les encadrés
		local plan = { count = 1 }
		if dims then
			plan = layout.plan(dims.cols, dims.rows, cfg.max_months, block_width, block_height)
		end
		if plan.count <= 1 then
			local text = help .. "\n" .. assemble.render_month(ctx.days(), year, month, ctx.today_key(), cfg, labels)
			if dims then
				-- Même un seul mois ne tient pas en entier : un message à la place d'un calendrier coupé.
				local needed = select(2, text:gsub("\n", "\n")) + 1
				if (tonumber(dims.cols) or 0) < block_width or (tonumber(dims.rows) or 0) < needed then
					local title, hint = labels.too_small, string.format(labels.too_small_hint, block_width, needed)
					return title .. "\n" .. hint, 0, math.max(layout.visible_width(title), layout.visible_width(hint))
				end
			end
			-- l'inactif au bout de la légende (la dernière ligne), seulement s'il tient dans la fenêtre
			local with_idle = text .. idle_today(labels)
			local last_line = with_idle:match("([^\n]*)$")
			if not dims or layout.visible_width(last_line) <= (tonumber(dims.cols) or 0) then
				text = with_idle
			end
			return text, 1, block_width
		end
		local days, today = ctx.days(), ctx.today_key()
		local blocks = {}
		for _, shown in ipairs(layout.months(year, month, plan.count, cfg.months_anchor)) do
			local selected = shown.year == year and shown.month == month
			blocks[#blocks + 1] = assemble.month_block(days, shown.year, shown.month, today, cfg, labels, selected)
		end
		local body = layout.arrange(blocks, plan.columns, layout.GAP)
		local width = plan.columns * block_width + (plan.columns - 1) * layout.GAP
		return help .. "\n\n" .. table.concat(body, "\n") .. "\n\n" .. assemble.legend(cfg, labels) .. idle_today(
			labels
		),
			plan.count,
			width
	end

	-- Le texte, centré dans la fenêtre (réglage center = false pour le garder en haut à gauche).
	local function centered(text, dims, width)
		if not dims or ctx.cfg().center == false then
			return text
		end
		local lines = {}
		for line in (text .. "\n"):gmatch("(.-)\n") do
			lines[#lines + 1] = line
		end
		return table.concat(layout.center(lines, width, dims.cols, dims.rows), "\n")
	end

	local function redraw(pane, first)
		local year, month = selected_month()
		local dims = dims_of(pane)
		local text, count, width = page.build_text(dims)
		safe.trace(
			wezterm,
			string.format(
				"logtime: drawing month %d-%02d in pane %s (%d months)",
				year,
				month,
				tostring(pane:pane_id()),
				count
			)
		)
		ui.draw(pane, centered(text, dims, width), first)
		ui.title(pane, ctx.labels().title) -- « Logtime »
	end

	-- Ce panneau est-il la page ?
	function page.is_page(pane)
		local id = page_id()
		return id ~= nil and pane:pane_id() == id
	end

	-- Redessine plus tard, mais seulement si la page existe toujours.
	local function redraw_later(pane_id, delays)
		ui.later(pane_id, delays, function(pane)
			if page_id() == pane:pane_id() then
				redraw(pane, false)
			end
		end)
	end

	-- Ouvre la page dans un nouvel onglet (ou remet devant celle qui existe déjà).
	function page.open(window, pane)
		local existing = ui.find_pane(page_id())
		if existing then
			pcall(function()
				existing:tab():activate()
			end)
			keytable.activate(wezterm, window, existing, M.TABLE_NAME)
			redraw(existing, false)
			return
		end
		-- panneau périmé (onglet fermé autrement qu'avec q) : on l'oublie et on ouvre une nouvelle page
		G.logtime_page_pane = nil

		local tab, page_pane = window:mux_window():spawn_tab({
			domain = { DomainName = "local" },
			args = ctx.blocker_args(),
		})
		pcall(function()
			tab:activate()
		end)

		G.logtime_page_pane = page_pane:pane_id()
		G.logtime_page_year, G.logtime_page_month, G.logtime_page_day = current_month()
		G.logtime_page_view = M.VIEW.MONTHS
		safe.trace(wezterm, "logtime: page opened in pane " .. tostring(page_pane:pane_id()))

		redraw(page_pane, true)
		redraw_later(page_pane:pane_id(), { 0.4, 1.2 })
		keytable.activate(wezterm, window, page_pane, M.TABLE_NAME)
	end

	-- Affiche ce mois (et ce jour : sinon le même numéro de jour, ramené à la fin du mois s'il le faut).
	local function show(year, month, pane, d)
		if year < 1970 or year > 2200 then
			return
		end
		if not d then
			d = select(3, selected_day())
		end
		G.logtime_page_year, G.logtime_page_month = year, month
		G.logtime_page_day = math.min(d, dates.days_in_month(year, month))
		redraw(pane, false)
	end

	-- ← → ↑ ↓ : le jour d'avant / d'après, la semaine d'avant / d'après (on passe au mois voisin tout seul).
	local function shift_day(delta)
		return function(window, pane)
			local year, month, d = selected_day()
			local t = os.date("*t", os.time({ year = year, month = month, day = d + delta, hour = 12 }))
			show(t.year, t.month, pane, t.day)
		end
	end

	-- PgUp PgDn (et Tab, Maj+Tab) : un mois de plus ou de moins.
	local function shift_month(delta)
		return function(window, pane)
			local year, month = selected_month()
			month = month + delta
			if month < 1 then
				month, year = 12, year - 1
			elseif month > 12 then
				month, year = 1, year + 1
			end
			show(year, month, pane)
		end
	end

	local function go_today(window, pane)
		local year, month, d = current_month()
		show(year, month, pane, d)
	end

	-- Entrée : le détail du jour choisi, ou de nouveau le calendrier.
	local function toggle_detail(window, pane)
		local view = current_view()
		if view == M.VIEW.YEAR then
			return
		end
		G.logtime_page_view = (view == M.VIEW.DAY) and M.VIEW.MONTHS or M.VIEW.DAY
		redraw(pane, false)
	end

	-- a : la vue « tout en un », ou de nouveau les mois.
	local function toggle_view(window, pane)
		G.logtime_page_view = (current_view() == M.VIEW.YEAR) and M.VIEW.MONTHS or M.VIEW.YEAR
		redraw(pane, false)
	end

	local function refresh(window, pane)
		redraw(pane, false)
	end

	local function close(window, pane)
		G.logtime_page_pane = nil
		keytable.leave(wezterm, window, pane)
		window:perform_action(act.CloseCurrentTab({ confirm = false }), pane)
	end

	-- Échap : dans le détail du jour ou la vue « tout en un », retour au calendrier ; sinon fermer la page.
	local function back_or_close(window, pane)
		if current_view() == M.VIEW.DAY or current_view() == M.VIEW.YEAR then
			G.logtime_page_view = M.VIEW.MONTHS
			redraw(pane, false)
			return
		end
		close(window, pane)
	end

	-- Les touches de la page.
	function page.bindings()
		return {
			{ key = "h", run = shift_day(-1) },
			{ key = "LeftArrow", run = shift_day(-1) },
			{ key = "l", run = shift_day(1) },
			{ key = "RightArrow", run = shift_day(1) },
			{ key = "k", run = shift_day(-7) },
			{ key = "UpArrow", run = shift_day(-7) },
			{ key = "j", run = shift_day(7) },
			{ key = "DownArrow", run = shift_day(7) },
			{ key = "PageUp", run = shift_month(-1) },
			{ key = "PageDown", run = shift_month(1) },
			{ key = "Tab", run = shift_month(1) }, -- tous les claviers n'ont pas PgUp / PgDn
			{ key = "Tab", mods = "SHIFT", run = shift_month(-1) },
			{ key = "Enter", run = toggle_detail },
			{ key = "t", run = go_today },
			{ key = "a", run = toggle_view },
			{ key = "r", run = refresh },
			{ key = "q", run = close },
			{ key = "Escape", run = back_or_close },
		}
	end

	function page.key_table()
		return keytable.build(wezterm, page.bindings(), page.is_page, "logtime-page")
	end

	-- La fenêtre a changé de taille : on redessine la page (tout de suite, puis après les repeints du système).
	function page.on_resize(window, pane)
		local id = page_id()
		local page_pane = ui.find_pane(id)
		if not page_pane then
			return
		end
		redraw(page_pane, false)
		redraw_later(id, { 0.3, 1.0 })
	end

	return page
end

return M
