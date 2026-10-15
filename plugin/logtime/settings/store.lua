-- plugin/logtime/settings/store.lua : le fichier de réglages (lecture, écriture sûre, vérification des options).
-- Le fichier est un petit JSON lisible et modifiable à la main :
--   {
--     "gradient_color": "#3366CC",
--     "max_months": 6
--   }
-- Aucune dépendance à WezTerm : se teste avec un simple interpréteur Lua.
local load = ...
local json = load("settings/json")
local schema = load("settings/schema")

local M = {}

-- ------------------------------------------------------------
-- Lecture d'un texte
-- ------------------------------------------------------------
-- Renvoie les réglages valides et la liste des problèmes (réglage inconnu, valeur incorrecte), ou nil et la raison
-- si le texte n'est pas un objet JSON lisible. Un réglage à null est simplement ignoré (valeur par défaut).
function M.parse(text)
	local object, err = json.decode(text)
	if object == nil then
		return nil, err
	end
	if type(object) ~= "table" or object == json.null or json.is_array(object) then
		return nil, "the file must contain an object in braces { ... }"
	end
	local settings, problems = {}, {}
	local keys = {}
	for key in pairs(object) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		local value = object[key]
		if value ~= json.null then
			if not schema.is_known(key) then
				problems[#problems + 1] = 'unknown setting "' .. key .. '" (ignored)'
			else
				local good, normalized = schema.validate(key, value)
				if good then
					settings[key] = normalized
				else
					problems[#problems + 1] = '"' .. key .. '" ' .. normalized .. " (ignored)"
				end
			end
		end
	end
	return settings, problems
end

-- ------------------------------------------------------------
-- Écriture d'un texte
-- ------------------------------------------------------------
local function encode_string(text)
	local escaped = text:gsub('[%c"\\]', function(c)
		if c == '"' then
			return '\\"'
		elseif c == "\\" then
			return "\\\\"
		elseif c == "\n" then
			return "\\n"
		elseif c == "\t" then
			return "\\t"
		elseif c == "\r" then
			return "\\r"
		end
		return string.format("\\u%04x", c:byte())
	end)
	return '"' .. escaped .. '"'
end

M.encode_string = encode_string

local function encode_value(value)
	if type(value) == "string" then
		return encode_string(value)
	elseif type(value) == "boolean" then
		return tostring(value)
	elseif value == math.floor(value) and math.abs(value) < 1e15 then
		return string.format("%d", value)
	end
	return string.format("%.15g", value)
end

-- Le texte du fichier pour ces réglages : un nom par ligne, dans l'ordre du schéma. Un réglage absent n'est pas écrit.
-- Renvoie le texte, ou nil et la raison si une valeur est incorrecte (c'est une erreur de programmation, pas de l'utilisateur).
function M.encode(settings)
	local lines = {}
	for _, key in ipairs(schema.keys()) do
		local value = settings[key]
		if value ~= nil then
			local good, normalized = schema.validate(key, value)
			if not good then
				return nil, "« " .. key .. " » " .. normalized
			end
			lines[#lines + 1] = "  " .. encode_string(key) .. ": " .. encode_value(normalized)
		end
	end
	if #lines == 0 then
		return "{}\n"
	end
	return "{\n" .. table.concat(lines, ",\n") .. "\n}\n"
end

-- ------------------------------------------------------------
-- Le fichier
-- ------------------------------------------------------------
local function read_file(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text
end

local function write_file(path, text)
	local f, err = io.open(path, "wb")
	if not f then
		return false, tostring(err)
	end
	local written, write_err = f:write(text)
	local closed, close_err = f:close() -- l'écriture sur le disque peut n'échouer qu'ici
	if not written or not closed then
		return false, "incomplete write: " .. tostring(write_err or close_err)
	end
	return true
end

-- Lit le fichier. Renvoie (réglages, état, problèmes, depuis_la_copie) :
--   "absent"  : le fichier n'existe pas (normal au premier lancement) ;
--   "ok"      : lu correctement (les problèmes éventuels ne concernent que certains réglages, ignorés) ;
--   "corrupt" : le fichier existe mais n'est pas lisible. On essaie alors la copie de sécurité (.bak) ;
--               depuis_la_copie vaut true si elle a servi. Le fichier abîmé n'est jamais écrasé sans être mis de côté.
function M.load(path)
	local text = read_file(path)
	if text == nil then
		return {}, "absent", {}, false
	end
	local settings, problems = M.parse(text)
	if settings then
		return settings, "ok", problems, false
	end
	local reason = "the settings file is unreadable: " .. tostring(problems)
	local backup_text = read_file(path .. ".bak")
	if backup_text then
		local from_backup, backup_problems = M.parse(backup_text)
		if from_backup then
			local all = { reason .. "; the backup copy (.bak) is used instead" }
			for _, p in ipairs(backup_problems) do
				all[#all + 1] = p
			end
			return from_backup, "corrupt", all, true
		end
	end
	return {}, "corrupt", { reason .. "; the default values are used" }, false
end

local function exists(path)
	local f = io.open(path, "rb")
	if f then
		f:close()
		return true
	end
	return false
end

-- Met de côté un fichier illisible : <fichier>.corrupt-AAAAMMJJ-HHMMSS. Renvoie le nouveau nom, ou nil et la raison.
local function quarantine(path)
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

-- Écrit le texte : d'abord dans un fichier temporaire (relu pour vérifier), puis mis à sa place.
local function write_atomic(path, text)
	local tmp = path .. ".tmp"
	local ok, err = write_file(tmp, text)
	if not ok then
		os.remove(tmp)
		return false, "cannot write: " .. tostring(err)
	end
	-- La raison exacte est dans le message (voir storage/days.lua : un fichier tout juste écrit peut être bloqué un instant).
	local check, open_err = io.open(tmp, "rb")
	if not check then
		os.remove(tmp)
		return false, "check after writing failed: cannot read back: " .. tostring(open_err)
	end
	local back = check:read("*a")
	check:close()
	if back ~= text then
		os.remove(tmp)
		return false,
			string.format("check after writing failed: %d bytes read back instead of %d", back and #back or 0, #text)
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
	local copied, copy_err = write_file(path, text)
	if not copied then
		return false, "cannot put the file in place (content kept in " .. tmp .. ") : " .. tostring(copy_err)
	end
	os.remove(tmp)
	return true
end

-- Enregistre les réglages. Avant d'écrire : un fichier lisible est copié en .bak (le dernier état qui marchait) ;
-- un fichier illisible est mis de côté (.corrupt-...) au lieu d'être écrasé. Renvoie true, ou false et la raison.
function M.save(path, settings)
	local text, err = M.encode(settings)
	if not text then
		return false, err
	end
	local current = read_file(path)
	if current ~= nil then
		if M.parse(current) then
			write_file(path .. ".bak", current)
		else
			local moved, why = quarantine(path)
			if not moved then
				return false, "cannot set aside the unreadable file: " .. tostring(why)
			end
		end
	end
	return write_atomic(path, text)
end

-- ------------------------------------------------------------
-- Vérification des options passées à apply_to_config
-- ------------------------------------------------------------
-- La distance entre deux mots (le nombre de lettres à changer), pour proposer « tu voulais dire ... ? ».
local function distance(a, b)
	local previous = {}
	for j = 0, #b do
		previous[j] = j
	end
	for i = 1, #a do
		local row = { [0] = i }
		for j = 1, #b do
			local cost = (a:sub(i, i) == b:sub(j, j)) and 0 or 1
			row[j] = math.min(previous[j] + 1, row[j - 1] + 1, previous[j - 1] + cost)
		end
		previous = row
	end
	return previous[#b]
end

local function closest(key, known)
	local best, best_distance
	for _, candidate in ipairs(known) do
		local d = distance(key:lower(), candidate:lower())
		if d <= 2 and (best_distance == nil or d < best_distance) then
			best, best_distance = candidate, d
		end
	end
	return best
end

-- Vérifie la table de réglages donnée dans wezterm.lua. Renvoie la liste des messages (vide si tout va bien) :
-- table absente ou d'un autre type, option inconnue (avec une suggestion pour une faute de frappe), valeur incorrecte.
-- extra_known : la liste des autres noms d'options valables (ceux qui ne sont pas dans le schéma).
function M.check_options(opts, extra_known)
	if opts == nil then
		return {}
	end
	if type(opts) ~= "table" then
		return {
			"the second argument of apply_to_config must be a table, for example apply_to_config(config, { max_months = 6 }) (got: "
				.. type(opts)
				.. ")",
		}
	end
	local known, is_known = {}, {}
	for _, key in ipairs(schema.keys()) do
		known[#known + 1] = key
		is_known[key] = true
	end
	for _, key in ipairs(extra_known or {}) do
		known[#known + 1] = key
		is_known[key] = true
	end
	local messages = {}
	local keys = {}
	for key in pairs(opts) do
		keys[#keys + 1] = key
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	for _, key in ipairs(keys) do
		if type(key) ~= "string" then
			messages[#messages + 1] = "option without a name ("
				.. tostring(key)
				.. "): options are written name = value"
		elseif not is_known[key] then
			local suggestion = closest(key, known)
			if suggestion then
				messages[#messages + 1] = 'unknown option "'
					.. key
					.. '" (ignored); did you mean "'
					.. suggestion
					.. '"?'
			else
				messages[#messages + 1] = 'unknown option "' .. key .. '" (ignored)'
			end
		elseif schema.is_known(key) then
			local good, reason = schema.validate(key, opts[key])
			if not good then
				messages[#messages + 1] = '"' .. key .. '" ' .. reason
			end
		end
	end
	return messages
end

return M
