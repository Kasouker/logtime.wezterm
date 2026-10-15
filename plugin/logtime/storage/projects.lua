-- plugin/logtime/storage/projects.lua : le format du fichier du temps par projet (.logtime_projects.json).
-- Aucune dépendance à WezTerm : se teste avec un simple interpréteur Lua.
--   {"2026-10-14":{"Projects/logtime.wezterm":8040,"42/C05":3600}}
-- Un objet : une date, puis un objet (un nom de projet, puis un nombre de secondes). La lecture et l'écriture prudentes
-- sont celles de storage/days.lua (load et save, avec ce format).
local load = ...
local json = load("settings/json")
local store = load("settings/store")

local M = {}

local DATE = "^%d%d%d%d%-%d%d%-%d%d$"

local function valid_secs(secs)
	return type(secs) == "number" and secs >= 0 and secs == secs and secs < math.huge
end

local function sorted_keys(t)
	local keys = {}
	for key in pairs(t) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	return keys
end

-- Les projets -> le texte du fichier. Dates et noms triés, secondes entières, rien d'invalide n'est écrit.
function M.encode(projects)
	local out = {}
	for _, key in ipairs(sorted_keys(projects or {})) do
		local of_day = projects[key]
		if type(key) == "string" and key:match(DATE) and type(of_day) == "table" then
			local parts = {}
			for _, label in ipairs(sorted_keys(of_day)) do
				local secs = of_day[label]
				if type(label) == "string" and valid_secs(secs) and secs >= 1 then
					parts[#parts + 1] = store.encode_string(label) .. ":" .. string.format("%d", math.floor(secs))
				end
			end
			if #parts > 0 then
				out[#out + 1] = '"' .. key .. '":{' .. table.concat(parts, ",") .. "}"
			end
		end
	end
	return "{" .. table.concat(out, ",") .. "}"
end

-- Le texte du fichier -> les projets. Strict : au moindre doute, nil et la raison (un fichier abîmé n'est jamais pris
-- pour un fichier vide).
function M.decode(text)
	local value, err = json.decode(text)
	if value == nil then
		return nil, err
	end
	if type(value) ~= "table" or json.is_array(value) then
		return nil, "not a JSON object"
	end
	local projects = {}
	for key, of_day in pairs(value) do
		if type(key) ~= "string" or not key:match(DATE) then
			return nil, "key that is not a date: " .. tostring(key)
		end
		if type(of_day) ~= "table" or json.is_array(of_day) then
			return nil, "not an object for " .. key
		end
		projects[key] = {}
		for label, secs in pairs(of_day) do
			if type(label) ~= "string" or not valid_secs(secs) then
				return nil, "invalid value for " .. key .. " / " .. tostring(label)
			end
			projects[key][label] = secs
		end
	end
	return projects
end

return M
