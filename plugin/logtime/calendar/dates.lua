-- plugin/logtime/calendar/dates.lua : le calendrier des dates (longueur des mois, jour de la semaine du 1er, clés de date).
-- Aucune dépendance à WezTerm : se teste avec un simple interpréteur Lua.
local M = {}

-- "2026-10-05" pour (2026, 10, 5)
function M.key(year, month, day)
	return string.format("%04d-%02d-%02d", year, month, day)
end

-- La clé d'un jour qui peut sortir du mois : (2026, 10, 0) -> "2026-09-30", (2026, 10, 32) -> "2026-11-01".
-- À midi, pour ne jamais tomber sur un changement d'heure.
function M.key_any(year, month, day)
	return os.date("%Y-%m-%d", os.time({ year = year, month = month, day = day, hour = 12 }))
end

-- Nombre de jours du mois (28 à 31, février des années bissextiles compris)
function M.days_in_month(year, month)
	return os.date("*t", os.time({ year = year, month = month + 1, day = 0, hour = 12 })).day
end

-- Jour de la semaine du 1er du mois : 1 = dimanche ... 7 = samedi
function M.first_wday(year, month)
	return os.date("*t", os.time({ year = year, month = month, day = 1, hour = 12 })).wday
end

-- Nombre de cases vides avant le 1er du mois, selon le premier jour de la semaine ("monday" par défaut, ou "sunday")
function M.offset(year, month, week_starts_on)
	local first = M.first_wday(year, month)
	if week_starts_on == "sunday" then
		return first - 1
	end
	return (first - 2) % 7
end

return M
