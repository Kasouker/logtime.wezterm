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
			return nil, "unterminated string"
		elseif c == '"' then
			return table.concat(out), pos + 1
		elseif c == "\\" then
			local e = text:sub(pos + 1, pos + 1)
			if e == "u" then
				local hex = text:match("^%x%x%x%x", pos + 2)
				if not hex then
					return nil, "invalid \\u escape near character " .. pos
				end
				local code = tonumber(hex, 16)
				pos = pos + 6
				if code >= 0xD800 and code <= 0xDBFF then
					local low = text:match("^\\u(%x%x%x%x)", pos)
					local low_code = low and tonumber(low, 16)
					if not (low_code and low_code >= 0xDC00 and low_code <= 0xDFFF) then
						return nil, "incomplete Unicode character near character " .. pos
					end
					code = 0x10000 + (code - 0xD800) * 0x400 + (low_code - 0xDC00)
					pos = pos + 6
				elseif code >= 0xDC00 and code <= 0xDFFF then
					return nil, "invalid Unicode character near character " .. (pos - 6)
				end
				out[#out + 1] = utf8.char(code)
			elseif ESCAPES[e] then
				out[#out + 1] = ESCAPES[e]
				pos = pos + 2
			else
				return nil, "unknown escape sequence near character " .. pos
			end
		else
			return nil, "control character in a string near character " .. pos
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
		return nil, "number expected near character " .. i
	end
	if #int > 1 and int:sub(1, 1) == "0" then
		return nil, "invalid number (leading zero) near character " .. i
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
		return nil, "invalid number near character " .. i
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
			return nil, '"," or "]" expected near character ' .. pos
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
			return nil, "quoted name expected near character " .. pos
		end
		local key, after_key = parse_string(text, pos)
		if key == nil then
			return nil, after_key
		end
		pos = skip(text, after_key)
		if text:sub(pos, pos) ~= ":" then
			return nil, '":" expected near character ' .. pos
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
			return nil, '"," or "}" expected near character ' .. pos
		end
		pos = skip(text, pos + 1)
	end
end

-- Renvoie la valeur et la position suivante, ou nil et un message.
parse_value = function(text, i, depth)
	if depth > MAX_DEPTH then
		return nil, "too deeply nested near character " .. i
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
		return nil, "unexpected end of text"
	end
	return nil, 'unexpected character "' .. c .. '" near character ' .. i
end

-- Lit un texte JSON. Renvoie la valeur, ou nil et un message en français.
function M.decode(text)
	if type(text) ~= "string" then
		return nil, "not a string"
	end
	if text:sub(1, 3) == "\239\187\191" then
		text = text:sub(4) -- un fichier enregistré avec une marque d'ordre des octets (BOM)
	end
	local start = skip(text, 1)
	if start > #text then
		return nil, "the file is empty"
	end
	local value, nextpos = parse_value(text, start, 0)
	if value == nil then
		return nil, nextpos
	end
	local rest = skip(text, nextpos)
	if rest <= #text then
		return nil, "extra text after the end near character " .. rest
	end
	return value
end

return M
