-- plugin/logtime/status/status.lua : le texte du compteur affiché dans la barre. Aucune dépendance à WezTerm.
local M = {}

-- 3725 -> "01:02:05"
function M.hms(secs)
	secs = math.floor(secs)
	local h = math.floor(secs / 3600)
	local m = math.floor((secs % 3600) / 60)
	return string.format("%02d:%02d:%02d", h, m, secs % 60)
end

-- Un objectif d'heures, court : 7 -> "7h", 7.5 -> "7h30".
function M.goal_short(hours)
	local minutes = math.floor(hours * 60 + 0.5)
	if minutes % 60 == 0 then
		return string.format("%dh", minutes // 60)
	end
	return string.format("%dh%02d", minutes // 60, minutes % 60)
end

-- L'objectif du jour est-il atteint ? (goal_hours : nil ou 0 = pas d'objectif)
function M.reached(secs, goal_hours)
	return type(goal_hours) == "number" and goal_hours > 0 and secs >= goal_hours * 3600
end

-- Le texte de la barre : une horloge puis la durée, par exemple "󰥔 01:02:05". Avec un objectif (goal_hours) :
--   pas encore atteint : "󰥔 05:12:30 / 7h" ;
--   atteint            : "󰥔 ✓ 07:03:10".
function M.text(secs, goal_hours)
	local clock = utf8.char(0xF017) .. " "
	if type(goal_hours) ~= "number" or goal_hours <= 0 then
		return clock .. M.hms(secs)
	end
	if M.reached(secs, goal_hours) then
		return clock .. "✓ " .. M.hms(secs)
	end
	return clock .. M.hms(secs) .. " / " .. M.goal_short(goal_hours)
end

return M
