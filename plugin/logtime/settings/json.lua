-- plugin/logtime/settings/json.lua : lit un texte JSON (objets, listes, textes, nombres, true, false, null).
-- Aucune dépendance à WezTerm : se teste avec un simple interpréteur Lua, et un fichier modifié à la main ne peut pas
-- faire planter la lecture (toute erreur est renvoyée comme un message).
local M = {}

-- La valeur JSON « null » (une table unique, pour la distinguer de « clé absente »).
M.null = setmetatable({}, {
	__tostring = function()
		return "null"
	end,
})

-- Les listes sont marquées, pour qu'une liste vide « [] » ne soit pas prise pour un objet vide « {} ».
local ARRAY = {}

function M.is_array(value)
	return type(value) == "table" and getmetatable(value) == ARRAY
end

local MAX_DEPTH = 32
local ESCAPES = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function skip(text, i)
	return text:find("[^ \t\r\n]", i) or (#text + 1)
end

local parse_value

-- Un texte entre guillemets, à partir de la position i (le guillemet ouvrant).
local function parse_string(text, i)
	local out = {}
	local pos = i + 1
	while true do
		local run = text:match('^[^"\\%c]+', pos)
		if run then
			out[#out + 1] = run
			pos = pos + #run
		end
		local c = text:sub(pos, pos)
		if c == "" then
			return nil, "texte non terminé"
		elseif c == '"' then
			return table.concat(out), pos + 1
		elseif c == "\\" then
			local e = text:sub(pos + 1, pos + 1)
			if e == "u" then
				local hex = text:match("^%x%x%x%x", pos + 2)
				if not hex then
					return nil, "séquence \\u incorrecte près du caractère " .. pos
				end
				local code = tonumber(hex, 16)
				pos = pos + 6
				if code >= 0xD800 and code <= 0xDBFF then
					local low = text:match("^\\u(%x%x%x%x)", pos)
					local low_code = low and tonumber(low, 16)
					if not (low_code and low_code >= 0xDC00 and low_code <= 0xDFFF) then
						return nil, "caractère Unicode incomplet près du caractère " .. pos
					end
					code = 0x10000 + (code - 0xD800) * 0x400 + (low_code - 0xDC00)
					pos = pos + 6
				elseif code >= 0xDC00 and code <= 0xDFFF then
					return nil, "caractère Unicode incorrect près du caractère " .. (pos - 6)
				end
				out[#out + 1] = utf8.char(code)
			elseif ESCAPES[e] then
				out[#out + 1] = ESCAPES[e]
				pos = pos + 2
			else
				return nil, "séquence d'échappement inconnue près du caractère " .. pos
			end
		else
			return nil, "caractère de contrôle dans un texte près du caractère " .. pos
		end
	end
end

local function parse_number(text, i)
	local j = i
	if text:sub(j, j) == "-" then
		j = j + 1
	end
	local int = text:match("^%d+", j)
	if not int then
		return nil, "nombre attendu près du caractère " .. i
	end
	if #int > 1 and int:sub(1, 1) == "0" then
		return nil, "nombre incorrect (zéro au début) près du caractère " .. i
	end
	j = j + #int
	local frac = text:match("^%.%d+", j)
	if frac then
		j = j + #frac
	end
	local exp = text:match("^[eE][+-]?%d+", j)
	if exp then
		j = j + #exp
	end
	local value = tonumber(text:sub(i, j - 1))
	if value == nil then
		return nil, "nombre incorrect près du caractère " .. i
	end
	return value, j
end

local function parse_array(text, i, depth)
	local out = setmetatable({}, ARRAY)
	local pos = skip(text, i + 1)
	if text:sub(pos, pos) == "]" then
		return out, pos + 1
	end
	while true do
		local value, nextpos = parse_value(text, pos, depth + 1)
		if value == nil then
			return nil, nextpos
		end
		out[#out + 1] = value
		pos = skip(text, nextpos)
		local c = text:sub(pos, pos)
		if c == "]" then
			return out, pos + 1
		elseif c ~= "," then
			return nil, "« , » ou « ] » attendu près du caractère " .. pos
		end
		pos = skip(text, pos + 1)
	end
end

local function parse_object(text, i, depth)
	local out = {}
	local pos = skip(text, i + 1)
	if text:sub(pos, pos) == "}" then
		return out, pos + 1
	end
	while true do
		if text:sub(pos, pos) ~= '"' then
			return nil, "nom entre guillemets attendu près du caractère " .. pos
		end
		local key, after_key = parse_string(text, pos)
		if key == nil then
			return nil, after_key
		end
		pos = skip(text, after_key)
		if text:sub(pos, pos) ~= ":" then
			return nil, "« : » attendu près du caractère " .. pos
		end
		pos = skip(text, pos + 1)
		local value, nextpos = parse_value(text, pos, depth + 1)
		if value == nil then
			return nil, nextpos
		end
		out[key] = value
		pos = skip(text, nextpos)
		local c = text:sub(pos, pos)
		if c == "}" then
			return out, pos + 1
		elseif c ~= "," then
			return nil, "« , » ou « } » attendu près du caractère " .. pos
		end
		pos = skip(text, pos + 1)
	end
end

-- Renvoie la valeur et la position suivante, ou nil et un message.
parse_value = function(text, i, depth)
	if depth > MAX_DEPTH then
		return nil, "trop d'imbrications près du caractère " .. i
	end
	local c = text:sub(i, i)
	if c == "{" then
		return parse_object(text, i, depth)
	elseif c == "[" then
		return parse_array(text, i, depth)
	elseif c == '"' then
		return parse_string(text, i)
	elseif c == "-" or c:match("%d") then
		return parse_number(text, i)
	elseif text:sub(i, i + 3) == "true" then
		return true, i + 4
	elseif text:sub(i, i + 4) == "false" then
		return false, i + 5
	elseif text:sub(i, i + 3) == "null" then
		return M.null, i + 4
	elseif c == "" then
		return nil, "fin du texte inattendue"
	end
	return nil, "caractère inattendu « " .. c .. " » près du caractère " .. i
end

-- Lit un texte JSON. Renvoie la valeur, ou nil et un message en français.
function M.decode(text)
	if type(text) ~= "string" then
		return nil, "ce n'est pas un texte"
	end
	if text:sub(1, 3) == "\239\187\191" then
		text = text:sub(4) -- un fichier enregistré avec une marque d'ordre des octets (BOM)
	end
	local start = skip(text, 1)
	if start > #text then
		return nil, "le fichier est vide"
	end
	local value, nextpos = parse_value(text, start, 0)
	if value == nil then
		return nil, nextpos
	end
	local rest = skip(text, nextpos)
	if rest <= #text then
		return nil, "du texte en trop après la fin près du caractère " .. rest
	end
	return value
end

return M
