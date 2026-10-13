-- plugin/logtime/ui/screen.lua : dessiner du texte (avec couleurs ANSI) dans un onglet WezTerm, sans programme externe.
local M = {}

-- 1049h : écran alternatif ; 25l : curseur caché ; 7l : pas de retour à la ligne automatique
local START = "\27[?1049h\27[?25l\27[?7l"
-- 2J : efface l'écran ; H : curseur en haut à gauche
local CLEAR = "\27[2J\27[H"

-- Le texte à envoyer au terminal pour dessiner `text` (lignes séparées par "\n") dans une fenêtre de `rows` lignes.
-- Jamais plus de lignes que la fenêtre, sinon l'écran défilerait : on retire des lignes en trop à la fin, mais on
-- garde toujours les `keep_last` dernières (par exemple un pied de page).
-- `first` : premier dessin de la page (passe en écran alternatif et cache le curseur).
-- Les retours à la ligne deviennent "\r\n" : un terminal en mode sortie ne revient pas au début de la ligne avec "\n".
function M.frame(text, rows, first, keep_last)
	local lines = {}
	for line in (text .. "\n"):gmatch("(.-)\n") do
		lines[#lines + 1] = line
	end
	rows = math.max(rows or 24, 1)
	keep_last = math.min(keep_last or 0, rows)
	while #lines > rows do
		table.remove(lines, #lines - keep_last)
	end
	return (first and START or "") .. CLEAR .. table.concat(lines, "\r\n")
end

-- Les opérations qui ont besoin de WezTerm.
function M.bind(wezterm)
	local api = {}

	-- Le panneau portant cet identifiant, ou nil s'il n'existe plus.
	-- wezterm.mux.get_pane LÈVE une erreur ("pane id N not found in mux") pour un panneau disparu : on l'enveloppe.
function api.find_pane(id)
if id == nil or not (wezterm.mux and wezterm.mux.get_pane) then
return nil
end
local ok, pane = pcall(wezterm.mux.get_pane, id)
if ok then
return pane
end
return nil
end

-- Dessine `text` dans le panneau, à la taille actuelle de sa fenêtre.
function api.draw(pane, text, first, keep_last)
local dims = pane:get_dimensions()
pane:inject_output(M.frame(text, dims.viewport_rows, first, keep_last))
end

-- Redessine plus tard (après chaque délai, en secondes) : certains systèmes (ConPTY sous Windows) repeignent l'écran
	-- juste après le démarrage ou un redimensionnement, ce qui effacerait un dessin fait trop tôt.
	-- `redraw(pane)` n'est appelée que si le panneau existe encore.
function api.later(pane_id, delays, redraw)
if not (wezterm.time and wezterm.time.call_after) then
return
end
for _, delay in ipairs(delays) do
wezterm.time.call_after(delay, function()
local pane = api.find_pane(pane_id)
if pane then
pcall(redraw, pane)
end
end)
end
end

return api
end

return M
