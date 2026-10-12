-- plugin/logtime/status/status.lua : le texte du compteur affiché dans la barre. Aucune dépendance à WezTerm.
local M = {}

-- 3725 -> "01:02:05"
function M.hms(secs)
	secs = math.floor(secs)
	local h = math.floor(secs / 3600)
	local m = math.floor((secs % 3600) / 60)
	return string.format("%02d:%02d:%02d", h, m, secs % 60)
end

-- Le texte de la barre : une horloge puis la durée, par exemple "󰥔 01:02:05"
function M.text(secs)
	return utf8.char(0xF017) .. " " .. M.hms(secs)
end

return M
