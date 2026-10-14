-- plugin/logtime/storage/days.lua : lecture et écriture des heures par jour.
-- Aucune dépendance à WezTerm : se teste avec un simple interpréteur Lua.
--
-- Format du fichier (le même que l'ancien logtime, donc ton historique se relit tel quel) :
--   {"2026-10-10":15231,"2026-10-11":1900}
-- Un objet JSON à plat : une date, puis un nombre de secondes.
local M = {}

local DATE = "^%d%d%d%d%-%d%d%-%d%d$"

-- Les jours -> le texte du fichier. Dates triées, secondes entières, rien d'invalide n'est écrit.
function M.encode(days)
	local keys = {}
	for key, secs in pairs(days or {}) do
		if
			type(key) == "string"
			and key:match(DATE)
			and type(secs) == "number"
			and secs >= 0
			and secs == secs
			and secs < math.huge
		then
			keys[#keys + 1] = key
		end
	end
	table.sort(keys)
	local parts = {}
	for _, key in ipairs(keys) do
		parts[#parts + 1] = string.format('"%s":%d', key, math.floor(days[key]))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

-- Le texte du fichier -> les jours. Strict : au moindre doute, renvoie nil et la raison,
-- pour ne jamais prendre un fichier abîmé pour un historique vide.
function M.decode(text)
	if type(text) ~= "string" then
		return nil, "ce n'est pas du texte"
	end
	local body = text:match("^%s*{(.*)}%s*$")
	if not body then
		return nil, "ce n'est pas un objet JSON"
	end
	local days = {}
	if body:match("^%s*$") then
		return days
	end
	local n = #body
	local i = 1
	while true do
		local s, e, key, raw = body:find('^%s*"([^"]*)"%s*:%s*([^,%s]+)%s*', i)
		if not s then
			return nil, "entrée illisible près du caractère " .. i
		end
		if not key:match(DATE) then
			return nil, "clé qui n'est pas une date : " .. key
		end
		local value = tonumber(raw)
		if not value or value ~= value or value < 0 or value == math.huge then
			return nil, "valeur invalide pour " .. key .. " : " .. raw
		end
		days[key] = value
		i = e + 1
		if i > n then
			break
		end
		if body:sub(i, i) ~= "," then
			return nil, "virgule attendue près du caractère " .. i
		end
		i = i + 1
	end
	return days
end

-- Lit le fichier. Renvoie les jours et un état :
--   "absent"  : le fichier n'existe pas (historique vide, normal au premier lancement) ;
--   "ok"      : lu correctement ;
--   "corrupt" : le fichier existe mais n'est pas lisible : il ne faut PAS l'écraser sans le mettre de côté.
-- decode (facultatif) : un autre format de fichier (par défaut M.decode).
function M.load(path, decode)
	local f = io.open(path, "rb")
	if not f then
		return {}, "absent"
	end
	local text = f:read("*a")
	f:close()
	local days, err = (decode or M.decode)(text)
	if not days then
		return {}, "corrupt", err
	end
	return days, "ok"
end

-- Écrit le fichier : d'abord dans un fichier temporaire (relu pour vérifier), puis mis à sa place.
-- Renvoie true, ou false et la raison. En cas d'échec, l'ancien fichier n'est pas touché
-- (sauf dans le dernier recours Windows décrit plus bas, où le contenu reste dans le fichier .tmp).
-- encode (facultatif) : un autre format de fichier (par défaut M.encode).
function M.save(path, days, encode)
	local text = (encode or M.encode)(days)
	local tmp = path .. ".tmp"

	local f, err = io.open(tmp, "wb")
	if not f then
		return false, "écriture impossible : " .. tostring(err)
	end
	local written, write_err = f:write(text)
	local closed, close_err = f:close() -- l'écriture sur le disque peut n'échouer qu'ici
	if not written or not closed then
		os.remove(tmp)
		return false, "écriture incomplète : " .. tostring(write_err or close_err)
	end

	-- La raison exacte est dans le message : sous Windows, un antivirus ou l'indexation peut bloquer un instant un
	-- fichier tout juste écrit (la sauvegarde suivante, quelques secondes plus tard, réussit alors).
	local check, open_err = io.open(tmp, "rb")
	if not check then
		os.remove(tmp)
		return false, "la vérification après écriture a échoué : relecture impossible : " .. tostring(open_err)
	end
	local back = check:read("*a")
	check:close()
	if back ~= text then
		os.remove(tmp)
		return false,
			string.format(
				"la vérification après écriture a échoué : %d octets relus au lieu de %d",
				back and #back or 0,
				#text
			)
	end

	if os.rename(tmp, path) then
		return true
	end
	-- Windows refuse de renommer par-dessus un fichier existant : on retire l'ancien puis on renomme.
	os.remove(path)
	if os.rename(tmp, path) then
		return true
	end
	-- Dernier recours : copie directe. Le contenu reste dans le fichier .tmp tant que la copie n'a pas réussi.
	local out = io.open(path, "wb")
	if not out then
		return false, "impossible de mettre le fichier en place (contenu conservé dans " .. tmp .. ")"
	end
	out:write(text)
	out:close()
	os.remove(tmp)
	return true
end

-- Copie le fichier en <fichier>.bak (une copie de sécurité de l'état avant les écritures de la session).
function M.backup(path)
	local f = io.open(path, "rb")
	if not f then
		return false, "rien à copier"
	end
	local text = f:read("*a")
	f:close()
	local out, err = io.open(path .. ".bak", "wb")
	if not out then
		return false, tostring(err)
	end
	out:write(text)
	out:close()
	return true
end

-- Met de côté un fichier illisible : <fichier>.corrupt-AAAAMMJJ-HHMMSS. Renvoie le nouveau nom, ou nil et la raison.
local function exists(path)
	local f = io.open(path, "rb")
	if f then
		f:close()
		return true
	end
	return false
end

function M.quarantine(path)
	local base = path .. ".corrupt-" .. os.date("%Y%m%d-%H%M%S")
	local target = base
	local n = 1
	while exists(target) do
		n = n + 1
		target = base .. "-" .. n
	end
	local ok, err = os.rename(path, target)
	if not ok then
		return nil, tostring(err)
	end
	return target
end

return M
