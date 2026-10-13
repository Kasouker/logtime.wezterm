-- plugin/logtime/calendar/stats.lua : les statistiques d'un mois (total, jours actifs, moyenne, meilleur jour, série).
-- Aucune dépendance à WezTerm : se teste avec un simple interpréteur Lua.
local load = ...
local dates = load("calendar/dates")

local M = {}

-- 25020 -> "6h57"
function M.hm(secs)
local total_minutes = math.floor(math.max(0, secs) / 60)
return string.format("%dh%02d", math.floor(total_minutes / 60), total_minutes % 60)
end

-- Nombre de jours consécutifs avec du temps compté, jusqu'à aujourd'hui.
-- Si rien n'est encore compté aujourd'hui, on part d'hier.
function M.streak(days, today_key)
	local y, m, d = tostring(today_key):match("^(%d+)-(%d+)-(%d+)$")
	if not y then
		return 0
	end
	local t = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
	if (days[today_key] or 0) <= 0 then
		t = t - 86400
	end
	local count = 0
	while (days[os.date("%Y-%m-%d", t)] or 0) > 0 do
		count = count + 1
		t = t - 86400
	end
	return count
end

-- Les statistiques d'un mois. goal_hours (facultatif) : nombre d'heures qui comptent pour « objectif atteint ».
-- Renvoie { total, active, average, best_day, best_secs, goal_days } (best_day vaut nil s'il n'y a rien ce mois-ci).
function M.month_stats(days, year, month, goal_hours)
	local goal_secs = goal_hours and goal_hours * 3600 or nil
	local total, active, goal_days = 0, 0, 0
	local best_day, best_secs = nil, 0
	for day = 1, dates.days_in_month(year, month) do
		local secs = math.floor(math.max(0, days[dates.key(year, month, day)] or 0))
		total = total + secs
		if secs > 0 then
			active = active + 1
		end
		if secs > best_secs then
			best_day, best_secs = day, secs
		end
		if goal_secs and secs >= goal_secs then
			goal_days = goal_days + 1
		end
	end
	return {
		total = total,
		active = active,
		average = active > 0 and total / active or 0,
		best_day = best_day,
		best_secs = best_secs,
		goal_days = goal_days,
	}
end

return M
