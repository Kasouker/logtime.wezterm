-- plugin/logtime/core/day.lua : découpe des journées et décalage de minuit.
-- Aucune dépendance à WezTerm : se teste avec un simple interpréteur Lua.
local M = {}

-- Clé de la journée d'un instant (secondes epoch) : "2026-10-12", en heure locale.
-- `offset` décale le moment où la journée change. Avec -3600, la journée change à 01:00 au lieu de minuit.
function M.key(t, offset)
	return os.date("%Y-%m-%d", t + (offset or 0))
end

-- Ajoute l'intervalle [from, to] (secondes epoch) aux journées concernées, en le coupant à chaque minuit.
-- `days` est une table { ["2026-10-12"] = secondes }, modifiée sur place.
function M.add_interval(days, from, to, offset)
	offset = offset or 0
	while from < to do
		local t = os.date("*t", from + offset)
		local next_midnight = os.time({ year = t.year, month = t.month, day = t.day + 1, hour = 0, min = 0, sec = 0 })
		local stop = to
		if type(next_midnight) == "number" then
			stop = math.min(to, next_midnight - offset)
		end
		if stop <= from then
			stop = to -- garde-fou : ne jamais boucler sans avancer
		end
		local key = string.format("%04d-%02d-%02d", t.year, t.month, t.day)
		days[key] = (days[key] or 0) + (stop - from)
		from = stop
	end
end

return M
