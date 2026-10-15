-- plugin/logtime/ui/safe.lua : une action qui plante ne doit jamais disparaître en silence.
local M = {}

-- Les traces (chaque touche, chaque dessin) ne vont dans les journaux qu'avec l'option debug = true : sinon elles
-- rempliraient les journaux de tout le monde. Les erreurs, elles, sont toujours écrites.
M.debug = false

-- Une ligne dans les journaux de WezTerm (seulement avec debug = true, et si WezTerm fournit log_info).
function M.trace(wezterm, message)
	if M.debug and wezterm.log_info then
		wezterm.log_info(message)
	end
end

-- Enveloppe `fn` : si elle plante, l'erreur est écrite dans les journaux de WezTerm ET affichée dans une notification.
-- Renvoie une fonction (window, pane, ...) utilisable comme action de touche ou comme gestionnaire d'événement.
-- trace : si vrai (et avec debug = true), chaque appel laisse deux lignes dans les journaux (appelée, puis terminée), ce qui permet de voir
-- si WezTerm appelle bien la fonction et si elle va au bout. Aucune frappe n'est enregistrée, seulement le nom de l'action.
function M.wrap(wezterm, name, fn, trace)
	return function(window, pane, ...)
		if trace then
			M.trace(wezterm, string.format("logtime (%s): called", name))
		end
		local ok, err = pcall(fn, window, pane, ...)
		if ok then
			if trace then
				M.trace(wezterm, string.format("logtime (%s): done", name))
			end
		else
			local message = string.format("logtime (%s): %s", name, tostring(err))
			wezterm.log_error(message)
			pcall(function()
				window:toast_notification("logtime", message, nil, 10000)
			end)
		end
	end
end

return M
