-- plugin/logtime/core/idle.lua : le temps inactif (rien ne bouge dans le terminal). Le compteur continue de tout
-- compter ; ce temps est seulement noté à part, pour montrer quelle part de la journée était inactive.
-- Aucune dépendance à WezTerm : se teste avec un simple interpréteur Lua.
local M = {}

-- Rien ne bouge pendant ce nombre de secondes : le temps est inactif (depuis la dernière activité, ces 5 minutes
-- comprises : une pause d'une heure compte une heure d'inactivité, pas 55 minutes).
M.IDLE_AFTER = 300

-- La dernière activité : `now` si l'empreinte a changé (ou si c'est la première), sinon la même qu'avant.
-- Une empreinte résume ce qu'on voit dans un panneau (le panneau, son titre, le curseur, le texte) : si elle change,
-- quelqu'un tape, lit (défile) ou un programme travaille.
function M.note(previous, current, last_activity, now)
	if previous ~= current or not last_activity then
		return now
	end
	return last_activity
end

-- La part inactive du temps compté [from, to]. Renvoie le début de la part inactive (elle va jusqu'à `to`), ou nil.
--   last_activity : la dernière activité (nil : inconnue, rien n'est inactif) ;
--   marked        : la dernière activité dont l'inactivité a déjà été notée (le début de l'épisode est déjà compté).
-- La première fois qu'un épisode dépasse idle_after, tout le temps depuis la dernière activité devient inactif (même
-- celui déjà compté comme actif) ; ensuite, seulement le nouveau temps.
function M.span(last_activity, marked, from, to, idle_after)
	if not last_activity or to <= from or to - last_activity < (idle_after or M.IDLE_AFTER) then
		return nil
	end
	if marked == last_activity then
		return from
	end
	return math.min(from, last_activity)
end

-- La part inactive d'un total : l'inactif (jamais plus que le total) et son pourcentage arrondi.
function M.share(total, idle)
	total = math.max(0, tonumber(total) or 0)
	idle = math.min(total, math.max(0, tonumber(idle) or 0))
	if total == 0 then
		return 0, 0
	end
	return idle, math.floor(idle * 100 / total + 0.5)
end

return M
