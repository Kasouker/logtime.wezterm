-- plugin/logtime/config/keys.lua : ajoute à la configuration de WezTerm la touche qui ouvre la page, les touches de la page
-- et le redessin au redimensionnement.
local load = ...
local safe = load("ui/safe")
local resize = load("ui/resize")

local M = {}

-- La touche qui ouvre la page émet un événement à nom fixe (voir ui/keytable.lua : pourquoi pas action_callback).
M.OPEN_EVENT = "logtime-open"

-- opts : { page = la page (open, key_table, on_resize), open_key = "F2", table_name = "logtime_page" }
function M.apply(config, wezterm, opts)
	config.keys = config.keys or {}
	for _, binding in ipairs(config.keys) do
		if binding.key == opts.open_key and (binding.mods == nil or binding.mods == "") then
			wezterm.log_error("logtime : la touche " .. opts.open_key .. " est déjà utilisée dans ta configuration ; vérifie qu'elle ne fait pas autre chose")
			break
		end
	end

	local open = safe.wrap(wezterm, "ouverture", function(window, pane)
opts.page.open(window, pane)
end, true)
	wezterm.on(M.OPEN_EVENT, function(window, pane)
open(window, pane)
return false -- si la config est appliquée deux fois, la page ne s'ouvre qu'une fois
end)
	table.insert(config.keys, { key = opts.open_key, action = wezterm.action.EmitEvent(M.OPEN_EVENT) })

	config.key_tables = config.key_tables or {}
	config.key_tables[opts.table_name] = opts.page.key_table()

	resize.install(wezterm, opts.page.on_resize)
	return config
end

return M
