-- plugin/logtime/ui/resize.lua : réagir au redimensionnement de la fenêtre (y compris le plein écran).
local load = ...
local safe = load("ui/safe")

local M = {}

-- `on_resize(window, pane)` est appelée à chaque redimensionnement ; une erreur est signalée, jamais perdue.
function M.install(wezterm, on_resize)
	wezterm.on("window-resized", safe.wrap(wezterm, "redimensionnement", on_resize))
end

return M
