-- plugin/logtime/storage/timeline.lua : le format du fichier de la frise (.logtime_timeline.json).
-- Aucune dépendance à WezTerm : se teste avec un simple interpréteur Lua.
--   {"2026-10-15":[[32400,36000,"42/C05"],[36000,39600,"Projet_Perso/logtime.wezterm"]]}
-- Un objet : une date, puis une liste de morceaux [début, fin, projet] (en secondes depuis le début de la journée).
-- La lecture et l'écriture prudentes sont celles de storage/days.lua (load et save, avec ce format).
local load = ...
local json = load("settings/json")
local store = load("settings/store")

local M = {}

local DATE = "^%d%d%d%d%-%d%d%-%d%d$"
local DAY = 26 * 3600 -- une journée peut durer 25 h (changement d'heure) : un peu de marge

local function valid_segment(seg)
	return type(seg) == "table"
		and type(seg[1]) == "number"
		and type(seg[2]) == "number"
		and type(seg[3]) == "string"
		and seg[1] >= 0
		and seg[2] > seg[1]
		and seg[2] <= DAY
		and seg[1] == seg[1]
		and seg[2] == seg[2]
end

-- La frise -> le texte du fichier. Dates triées, secondes entières, rien d'invalide n'est écrit.
function M.encode(timeline)
	local keys = {}
	for key in pairs(timeline or {}) do
		if type(key) == "string" and key:match(DATE) then
			keys[#keys + 1] = key
		end
	end
	table.sort(keys)
	local out = {}
	for _, key in ipairs(keys) do
		local parts = {}
		for _, seg in ipairs(timeline[key]) do
			if valid_segment(seg) then
				parts[#parts + 1] =
					string.format("[%d,%d,%s]", math.floor(seg[1]), math.floor(seg[2]), store.encode_string(seg[3]))
			end
		end
		if #parts > 0 then
			out[#out + 1] = '"' .. key .. '":[' .. table.concat(parts, ",") .. "]"
		end
	end
	return "{" .. table.concat(out, ",") .. "}"
end

-- Le texte du fichier -> la frise. Strict : au moindre doute, nil et la raison (un fichier abîmé n'est jamais pris
-- pour un fichier vide).
function M.decode(text)
	local value, err = json.decode(text)
	if value == nil then
		return nil, err
	end
	if type(value) ~= "table" or json.is_array(value) then
		return nil, "not a JSON object"
	end
	local timeline = {}
	for key, list in pairs(value) do
		if type(key) ~= "string" or not key:match(DATE) then
			return nil, "key that is not a date: " .. tostring(key)
		end
		if type(list) ~= "table" or (next(list) ~= nil and not json.is_array(list)) then
			return nil, "not a list for " .. key
		end
		local day = {}
		for i, seg in ipairs(list) do
			if not valid_segment(seg) then
				return nil, "invalid segment " .. i .. " for " .. key
			end
			day[i] = { seg[1], seg[2], seg[3] }
		end
		timeline[key] = day
	end
	return timeline
end

return M
