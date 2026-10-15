-- plugin/logtime/storage/location.lua : où ranger les fichiers du plugin.
-- Aucune dépendance à WezTerm : se teste avec un simple interpréteur Lua.
--
-- Les fichiers vont dans <dossier personnel>/.local/share/logtime/ (comme WezTerm, qui range ses journaux dans
-- .local/share/wezterm, même sous Windows). Pourquoi pas directement dans le dossier personnel : WezTerm recharge
-- toute sa config dès qu'un fichier change dans le dossier de la config ou dans l'un de ses sous-dossiers directs
-- (vérifié sous Windows). Avec une config en ~/.wezterm.lua (l'emplacement le plus courant), chaque sauvegarde
-- (toutes les 10 s) rechargeait la config, et les touches du calendrier se désactivaient. Trois niveaux plus bas,
-- aucune écriture ne déclenche de rechargement.
local M = {}

-- Les fichiers du plugin (mêmes noms qu'avant, quand ils étaient dans le dossier personnel).
M.FILES = { ".logtime.json", ".logtime_idle.json", ".logtime_projects.json", ".logtime_settings.json" }

-- Le dossier des fichiers : <dossier personnel>/.local/share/logtime
function M.dir(home, sep)
	return table.concat({ home, ".local", "share", "logtime" }, sep)
end

-- La commande qui crée le dossier (et ceux qui manquent au-dessus).
function M.mkdir_args(os_name, dir)
	if os_name == "windows" then
		return { "cmd.exe", "/c", "mkdir", dir }
	end
	return { "mkdir", "-p", dir }
end

local function read(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text
end

-- Le dossier existe-t-il et peut-il recevoir des fichiers ? (un fichier d'essai y est créé, puis retiré)
function M.writable(dir, sep)
	local probe = dir .. sep .. ".logtime_probe"
	local f = io.open(probe, "wb")
	if not f then
		return false
	end
	f:close()
	os.remove(probe)
	return true
end

-- Copie un fichier (jamais un déplacement : l'original n'est ni modifié ni supprimé). Écrit d'abord dans un fichier
-- temporaire, relu pour vérifier, puis mis à sa place. Renvoie true, ou false et la raison.
local function copy(from, to)
	local text = read(from)
	if not text then
		return false, "cannot read"
	end
	local tmp = to .. ".tmp"
	local f, err = io.open(tmp, "wb")
	if not f then
		return false, "cannot write: " .. tostring(err)
	end
	local written, write_err = f:write(text)
	local closed, close_err = f:close()
	if not written or not closed then
		os.remove(tmp)
		return false, "incomplete write: " .. tostring(write_err or close_err)
	end
	if read(tmp) ~= text then
		os.remove(tmp)
		return false, "check after writing failed"
	end
	local renamed, rename_err = os.rename(tmp, to)
	if not renamed then
		os.remove(tmp)
		return false, "cannot put in place: " .. tostring(rename_err)
	end
	return true
end

-- Copie dans new_dir chaque fichier de old_dir qui n'y est pas encore (l'ancien emplacement : le dossier personnel).
-- Un fichier déjà présent dans new_dir n'est jamais remplacé. Renvoie la liste des fichiers copiés et la liste des
-- problèmes (vide si tout va bien).
function M.migrate(old_dir, new_dir, sep)
	local copied, problems = {}, {}
	for _, name in ipairs(M.FILES) do
		local from, to = old_dir .. sep .. name, new_dir .. sep .. name
		if read(from) and not read(to) then
			local ok, err = copy(from, to)
			if ok then
				copied[#copied + 1] = name
			else
				problems[#problems + 1] = name .. " : " .. err
			end
		end
	end
	return copied, problems
end

return M
