-- plugin/logtime/ui/keytable.lua : les touches d'une page.
-- Une table de touches (key table) de WezTerm capte des touches seulement tant qu'elle est active.
local load = ...
local safe = load("ui/safe")

local M = {}

-- Construit la table de touches d'une page.
--   bindings : liste de { key = "h", run = function(window, pane) ... end }
--   is_page  : function(pane) -> true si ce panneau est la page
-- Une touche pressée AILLEURS que dans la page (autre onglet, page fermée à la souris) ne doit jamais gêner :
-- les touches de la page sont désactivées et la touche est rendue à l'onglet courant.
-- Chaque appel laisse une ligne dans les journaux : le nom de la touche de la page et si le panneau est la page.
function M.build(wezterm, bindings, is_page)
	local act = wezterm.action
	local out = {}
	for _, binding in ipairs(bindings) do
		local key, run = binding.key, binding.run
		out[#out + 1] = {
			key = key,
			action = wezterm.action_callback(safe.wrap(wezterm, "page", function(window, pane)
local on_page = is_page(pane)
safe.trace(wezterm, string.format("logtime (page) : touche %s, panneau %s, est la page : %s", key, tostring(pane:pane_id()), tostring(on_page)))
				if not on_page then
					window:perform_action(act.PopKeyTable, pane)
					window:perform_action(act.SendKey({ key = key }), pane)
					return
				end
				run(window, pane)
			end, true)),
		}
	end
	return out
end

-- Active les touches de la page (elles restent actives jusqu'à leur retrait).
function M.activate(wezterm, window, pane, name)
safe.trace(wezterm, string.format("logtime : touches de la page « %s » activées", name))
window:perform_action(wezterm.action.ActivateKeyTable({ name = name, one_shot = false }), pane)
end

-- Retire les touches de la page.
function M.leave(wezterm, window, pane)
safe.trace(wezterm, "logtime : touches de la page retirées")
window:perform_action(wezterm.action.PopKeyTable, pane)
end

return M
