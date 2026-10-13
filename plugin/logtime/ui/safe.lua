-- plugin/logtime/ui/safe.lua : une action qui plante ne doit jamais disparaître en silence.
local M = {}

-- Enveloppe `fn` : si elle plante, l'erreur est écrite dans les journaux de WezTerm ET affichée dans une notification.
-- Renvoie une fonction (window, pane, ...) utilisable comme action de touche ou comme gestionnaire d'événement.
function M.wrap(wezterm, name, fn)
	return function(window, pane, ...)
		local ok, err = pcall(fn, window, pane, ...)
		if not ok then
			local message = string.format("logtime (%s) : %s", name, tostring(err))
			wezterm.log_error(message)
			pcall(function()
				window:toast_notification("logtime", message, nil, 10000)
			end)
		end
	end
end

return M
