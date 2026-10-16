-- plugin/logtime/ui/keytable.lua : les touches d'une page.
-- Une table de touches (key table) de WezTerm capte des touches seulement tant qu'elle est active.
local load = ...
local safe = load("ui/safe")

local M = {}

-- Construit la table de touches d'une page.
--   bindings : liste de { key = "h", run = function(window, pane) ... end }, avec mods (facultatif) : "SHIFT" pour
--              Shift+Tab ({ key = "Tab", mods = "SHIFT" }) ; son événement porte le nom « <préfixe>-SHIFT-Tab »
--   is_page  : function(pane) -> true si ce panneau est la page
--   prefix   : début du nom des événements ("logtime-page" : la touche h émet "logtime-page-h")
-- Chaque touche émet un événement à NOM FIXE, enregistré avec wezterm.on. On n'utilise pas wezterm.action_callback :
-- il donne à chaque fonction un identifiant généré à chaque évaluation de la config, et si WezTerm réévalue la config
-- (ce qui arrive en ouvrant un onglet ou une fenêtre), les identifiants ne correspondent plus et les touches ne font
-- plus rien, sans aucune erreur. Avec un nom fixe, n'importe quelle évaluation retrouve ses fonctions.
-- Une touche pressée AILLEURS que dans la page (autre onglet, page fermée à la souris) ne doit jamais gêner :
-- les touches de la page sont désactivées et la touche est rendue à l'onglet courant.
-- Chaque appel laisse une ligne dans les journaux : le nom de la touche de la page et si le panneau est la page.
function M.build(wezterm, bindings, is_page, prefix)
	local act = wezterm.action
	local out = {}
	for _, binding in ipairs(bindings) do
		local key, run, mods = binding.key, binding.run, binding.mods
		local event = (prefix or "logtime-page") .. "-" .. (mods and (mods .. "-") or "") .. key
		local handler = safe.wrap(wezterm, "page", function(window, pane)
			local on_page = is_page(pane)
			safe.trace(
				wezterm,
				string.format(
					"logtime (page): key %s, pane %s, is the page: %s",
					key,
					tostring(pane:pane_id()),
					tostring(on_page)
				)
			)
			if not on_page then
				window:perform_action(act.PopKeyTable, pane)
				window:perform_action(act.SendKey({ key = key, mods = mods }), pane)
				return
			end
			run(window, pane)
		end, true)
		wezterm.on(event, function(window, pane)
			handler(window, pane)
			return false -- si la même touche est enregistrée deux fois (config appliquée deux fois), la seconde n'est pas appelée
		end)
		out[#out + 1] = { key = key, mods = mods, action = act.EmitEvent(event) }
	end
	return out
end

-- Active les touches de la page (elles restent actives jusqu'à leur retrait).
function M.activate(wezterm, window, pane, name)
	safe.trace(wezterm, string.format('logtime: page keys "%s" enabled', name))
	window:perform_action(wezterm.action.ActivateKeyTable({ name = name, one_shot = false }), pane)
end

-- Retire les touches de la page.
function M.leave(wezterm, window, pane)
	safe.trace(wezterm, "logtime: page keys removed")
	window:perform_action(wezterm.action.PopKeyTable, pane)
end

return M
