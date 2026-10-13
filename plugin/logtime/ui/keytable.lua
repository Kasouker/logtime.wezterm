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
function M.build(wezterm, bindings, is_page)
	local act = wezterm.action
	local out = {}
	for _, binding in ipairs(bindings) do
		local key, run = binding.key, binding.run
		out[#out + 1] = {
			key = key,
			action = wezterm.action_callback(safe.wrap(wezterm, "page", function(window, pane)
if not is_page(pane) then
window:perform_action(act.PopKeyTable, pane)
window:perform_action(act.SendKey({ key = key }), pane)
return
end
run(window, pane)
end)),
		}
	end
	return out
end

-- Active les touches de la page (elles restent actives jusqu'à leur retrait).
function M.activate(wezterm, window, pane, name)
window:perform_action(wezterm.action.ActivateKeyTable({ name = name, one_shot = false }), pane)
end

-- Retire les touches de la page.
function M.leave(wezterm, window, pane)
window:perform_action(wezterm.action.PopKeyTable, pane)
end

return M
