-- plugin/logtime/color/convert.lua : conversions de couleurs (code hexadécimal, séquences ANSI, contraste du texte).
-- Aucune dépendance à WezTerm : se teste avec un simple interpréteur Lua.
local M = {}

M.RESET = "\27[0m"

-- "#C9AB6B" -> 201, 171, 107 (blanc si le code est invalide)
function M.rgb(hex)
	local r, g, b = tostring(hex):match("^#?(%x%x)(%x%x)(%x%x)$")
	if not r then
		return 255, 255, 255
	end
	return tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
end

-- Texte de cette couleur (24 bits)
function M.fg(hex)
	local r, g, b = M.rgb(hex)
	return string.format("\27[38;2;%d;%d;%dm", r, g, b)
end

-- Fond de cette couleur (24 bits)
function M.bg(hex)
	local r, g, b = M.rgb(hex)
	return string.format("\27[48;2;%d;%d;%dm", r, g, b)
end

-- Couleur de texte lisible (sombre ou claire) sur un fond donné
function M.contrast(hex)
	local r, g, b = M.rgb(hex)
	local luminance = 0.299 * r + 0.587 * g + 0.114 * b
	return luminance > 140 and "#17191F" or "#ECE6D9"
end

return M
