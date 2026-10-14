-- plugin/logtime/pages/calendar_page.lua : la page du calendrier (un onglet où l'on change de mois avec les flèches).
local load = ...
local assemble = load("calendar/assemble")
local layout = load("calendar/layout")
local screen = load("ui/screen")
local keytable = load("ui/keytable")
local safe = load("ui/safe")
local gradient = load("color/gradient")

local M = {}

M.TABLE_NAME = "logtime_page"

-- ctx fournit ce que la page ne sait pas faire seule :
--   wezterm       l'API de WezTerm
--   G             wezterm.GLOBAL
--   num(v)        convertit une valeur lue dans GLOBAL en vrai nombre (nil si elle est absente)
--   days()        les heures par jour (table { ["2026-10-12"] = secondes })
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
	--   logtime_page_pane (le panneau de la page), logtime_page_year, logtime_page_month (le mois affiché)
	local function page_id()
		return num(G.logtime_page_pane)
	end

	local function current_month()
		local t = os.date("*t", os.time() + (ctx.cfg().day_offset or 0))
		return t.year, t.month
	end

	local function selected_month()
		local year, month = num(G.logtime_page_year), num(G.logtime_page_month)
		if not year or not month then
			return current_month()
		end
		return year, month
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

	-- Le texte de la page : une ligne d'aide, puis le ou les mois. Le nombre de mois dépend de la taille de la fenêtre
-- (dims = { cols, rows } ; sans taille, un seul mois). Renvoie le texte, le nombre de mois affichés et la largeur
-- du calendrier (la largeur qu'on centre).
	function page.build_text(dims)
		local labels, cfg = ctx.labels(), with_gradient(ctx.cfg())
		local year, month = selected_month()
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
		return help .. "\n\n" .. table.concat(body, "\n") .. "\n\n" .. assemble.legend(cfg, labels), plan.count, width
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
		safe.trace(wezterm, string.format("logtime : dessin du mois %d-%02d dans le panneau %s (%d mois)", year, month, tostring(pane:pane_id()), count))
		ui.draw(pane, centered(text, dims, width), first)
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
		G.logtime_page_year, G.logtime_page_month = current_month()
		safe.trace(wezterm, "logtime : page ouverte dans le panneau " .. tostring(page_pane:pane_id()))

		redraw(page_pane, true)
		redraw_later(page_pane:pane_id(), { 0.4, 1.2 })
		keytable.activate(wezterm, window, page_pane, M.TABLE_NAME)
	end

	local function show(year, month, pane)
		if year < 1970 or year > 2200 then
			return
		end
		G.logtime_page_year, G.logtime_page_month = year, month
		redraw(pane, false)
	end

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
		local year, month = current_month()
		show(year, month, pane)
	end

	local function refresh(window, pane)
		redraw(pane, false)
	end

	local function close(window, pane)
		G.logtime_page_pane = nil
		keytable.leave(wezterm, window, pane)
		window:perform_action(act.CloseCurrentTab({ confirm = false }), pane)
	end

	-- Les touches de la page.
	function page.bindings()
		return {
			{ key = "h", run = shift_month(-1) },
			{ key = "LeftArrow", run = shift_month(-1) },
			{ key = "l", run = shift_month(1) },
			{ key = "RightArrow", run = shift_month(1) },
			{ key = "t", run = go_today },
			{ key = "r", run = refresh },
			{ key = "q", run = close },
			{ key = "Escape", run = close },
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
