-- plugin/logtime/core/timeline.lua : la frise de la journée, à quelle heure chaque projet a été utilisé.
-- Aucune dépendance à WezTerm : se teste avec un simple interpréteur Lua.
--
-- Pour chaque jour, une liste de morceaux triés { début, fin, projet }, en secondes depuis le début de la journée :
--   { ["2026-10-15"] = { { 32400, 36000, "42/C05" }, { 36000, 39600, "Projet_Perso/logtime.wezterm" } } }
-- Deux morceaux du même projet séparés de M.GAP secondes au plus n'en font qu'un (le compteur avance chaque seconde).
local M = {}

M.GAP = 5 -- secondes : au-delà, un nouveau morceau commence
M.MAX_PER_DAY = 2000 -- au-delà, les deux morceaux les plus proches sont réunis (jamais plus gros qu'un fichier raisonnable)

-- Découpe [from, to] (secondes epoch) en morceaux d'une journée : appelle fn(clé du jour, début, fin), le début et la
-- fin en secondes depuis le début de cette journée. `offset` décale le moment où la journée change (comme core/day).
function M.each_day(from, to, offset, fn)
	offset = offset or 0
	while from < to do
		local t = os.date("*t", from + offset)
		local start = os.time({ year = t.year, month = t.month, day = t.day, hour = 0, min = 0, sec = 0 }) - offset
		local next_start = os.time({ year = t.year, month = t.month, day = t.day + 1, hour = 0, min = 0, sec = 0 })
			- offset
		local stop = math.min(to, next_start)
		if stop <= from then
			stop = to -- garde-fou : ne jamais boucler sans avancer
		end
		fn(string.format("%04d-%02d-%02d", t.year, t.month, t.day), from - start, stop - start)
		from = stop
	end
end

-- Trie les morceaux d'un jour et réunit ceux qui se suivent (même projet, écart de M.GAP au plus) ; deux projets qui se
-- chevauchent : le second commence où le premier finit. Renvoie la liste (modifiée sur place).
function M.normalize(list)
	table.sort(list, function(a, b)
		if a[1] ~= b[1] then
			return a[1] < b[1]
		end
		return a[2] < b[2]
	end)
	local out = {}
	for _, seg in ipairs(list) do
		local last = out[#out]
		if last and seg[3] == last[3] and seg[1] <= last[2] + M.GAP then
			last[2] = math.max(last[2], seg[2])
		else
			if last and seg[1] < last[2] then
				seg = { last[2], seg[2], seg[3] }
			end
			if seg[2] > seg[1] then
				out[#out + 1] = { seg[1], seg[2], seg[3] }
			end
		end
	end
	for i = #list, 1, -1 do
		list[i] = nil
	end
	for i, seg in ipairs(out) do
		list[i] = seg
	end
	return list
end

-- Au plus M.MAX_PER_DAY morceaux : on réunit les deux voisins les plus proches (le second prend le projet du premier)
-- jusqu'à rentrer dans la limite. Ne touche à rien en dessous de la limite.
local function cap(list)
	while #list > M.MAX_PER_DAY do
		local best, best_gap = 2, math.huge
		for i = 2, #list do
			local gap = list[i][1] - list[i - 1][2]
			if gap < best_gap then
				best, best_gap = i, gap
			end
		end
		list[best - 1][2] = list[best][2]
		table.remove(list, best)
	end
end

-- Le projet `label` a été utilisé de `from` à `to` (secondes epoch).
function M.add(timeline, label, from, to, offset)
	M.each_day(from, to, offset, function(key, s, e)
		local list = timeline[key] or {}
		timeline[key] = list
		local last = list[#list]
		if last and last[3] == label and s >= last[1] and s <= last[2] + M.GAP then
			last[2] = math.max(last[2], e) -- le cas de chaque seconde : le dernier morceau s'allonge
		else
			list[#list + 1] = { s, e, label }
			if last and s < last[2] then
				M.normalize(list)
			end
		end
		cap(list)
	end)
end

-- Retire la période [from, to] (secondes epoch) de la frise : le temps inactif, noté après coup.
function M.remove(timeline, from, to, offset)
	M.each_day(from, to, offset, function(key, s, e)
		local list = timeline[key]
		if not list then
			return
		end
		local out = {}
		for _, seg in ipairs(list) do
			if seg[2] <= s or seg[1] >= e then
				out[#out + 1] = seg
			else
				if seg[1] < s then
					out[#out + 1] = { seg[1], s, seg[3] }
				end
				if seg[2] > e then
					out[#out + 1] = { e, seg[2], seg[3] }
				end
			end
		end
		timeline[key] = #out > 0 and out or nil
	end)
end

local function same(a, b)
	if a == nil or b == nil or #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i][1] ~= b[i][1] or a[i][2] ~= b[i][2] or a[i][3] ~= b[i][3] then
			return false
		end
	end
	return true
end

-- Reprend dans la mémoire ce qu'un autre WezTerm a écrit dans le fichier (même règle que les autres fichiers) : un jour
-- identique à `base` (ce que CE WezTerm a lu ou écrit en dernier) est le nôtre, on garde la mémoire (l'inactif retiré
-- après coup ne revient pas) ; sinon les morceaux des deux sont réunis.
function M.merge(mem, from_file, base)
	for key, list in pairs(from_file) do
		if not (base and same(base[key], list)) then
			local combined = {}
			for _, seg in ipairs(mem[key] or {}) do
				combined[#combined + 1] = { seg[1], seg[2], seg[3] }
			end
			for _, seg in ipairs(list) do
				combined[#combined + 1] = { seg[1], seg[2], seg[3] }
			end
			mem[key] = M.normalize(combined)
		end
	end
end

return M
