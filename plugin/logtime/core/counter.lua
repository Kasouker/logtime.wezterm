-- plugin/logtime/core/counter.lua : le comptage. Aucune dépendance à WezTerm.
local load = ...
local day = load("core/day")

local M = {}

-- Fait avancer le compteur entre l'instant précédent (`last`) et maintenant (`now`).
-- Renvoie true si du temps a été ajouté, et combien (le temps ajouté va de `last` à `last` + ce nombre).
--
--   - un écart normal (<= cfg.normal_gap secondes) est compté en entier ;
--   - un écart plus long (veille, hibernation, blocage) est compté dans la limite d'un BUDGET DE VEILLE :
--     cfg.sleep_limit secondes au total par épisode, pas par écart. Un ordinateur qui se réveille un instant
--     pour hiberner, puis reprend le lendemain, a donc deux écarts qui se partagent le même budget :
--     la veille est comptée, l'extinction non ;
--   - le budget n'est rendu qu'après cfg.settle_time secondes (60 par défaut) de fonctionnement normal continu.
--
-- `state` est une table { budget = secondes déjà comptées dans l'épisode, calm = secondes de fonctionnement
-- normal d'affilée }, modifiée sur place : l'appelant la conserve d'un appel à l'autre.
-- Sans `state`, chaque écart est jugé seul (budget neuf à chaque appel).
function M.advance(days, last, now, cfg, state)
	if not last or now <= last then
		return false
	end
	state = state or {}
	local budget = state.budget or 0
	local calm = state.calm or 0
	local settle = cfg.settle_time or 60

	local gap = now - last
	local counted
	if gap <= cfg.normal_gap then
		counted = gap
		calm = calm + gap
		if calm >= settle then
			budget = 0
		end
	else
		counted = math.max(0, math.min(gap, cfg.sleep_limit - budget))
		budget = budget + counted
		calm = 0
	end

	state.budget = budget
	state.calm = calm

	if counted <= 0 then
		return false
	end
	day.add_interval(days, last, last + counted, cfg.day_offset)
	return true, counted
end

return M
