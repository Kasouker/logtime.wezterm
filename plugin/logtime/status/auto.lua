-- plugin/logtime/status/auto.lua : où afficher le compteur, sans que l'utilisateur ait rien à brancher.
-- Aucune dépendance à WezTerm : se teste avec un simple interpréteur Lua.
--
-- Le plugin compte lui-même à chaque mise à jour de WezTerm (événement update-status), et affiche le compteur :
--   - à droite de la barre d'onglets normale de WezTerm ;
--   - ou dans la barre de tabline.wez, s'il est installé (il s'y ajoute) ;
--   - ou nulle part si l'utilisateur l'affiche déjà lui-même (il appelle tick() dans sa propre barre), ou s'il a choisi
--     status = false.
local M = {}

-- Un tick() venu d'ailleurs il y a au plus ce nombre de secondes : quelqu'un affiche déjà le compteur.
M.EXTERNAL_WINDOW = 3
-- Au démarrage de WezTerm, avec tabline : le temps de voir si l'utilisateur appelle tick() lui-même, avant de s'ajouter
-- à sa barre (sinon le compteur serait affiché deux fois).
M.GRACE = 3
-- La section de tabline.wez où le compteur s'ajoute (à droite, avant les sections y et z).
M.TABLINE_SECTION = "tabline_x"

-- Où afficher le compteur. info = {
--   enabled     = false si l'utilisateur a choisi status = false (sinon true),
--   now         = l'instant présent (secondes),
--   external_at = le dernier appel de tick() venu d'ailleurs (ou nil),
--   started_at  = le premier passage depuis le démarrage de WezTerm (ou nil),
--   has_tabline = true si tabline.wez est installé }
-- Renvoie "off", "external" (déjà affiché par l'utilisateur), "wait", "tabline" ou "right".
function M.choose(info)
	if info.enabled == false then
		return "off"
	end
	if info.external_at and info.now - info.external_at <= M.EXTERNAL_WINDOW then
		return "external"
	end
	if info.has_tabline then
		if info.started_at and info.now - info.started_at < M.GRACE then
			return "wait"
		end
		return "tabline"
	end
	return "right"
end

-- L'adresse de tabline.wez dans la liste des plugins installés (wezterm.plugin.list()), ou nil.
function M.find_tabline(plugins)
	for _, plugin in ipairs(plugins or {}) do
		local url = type(plugin) == "table" and plugin.url or nil
		if type(url) == "string" and url:find("tabline.wez", 1, true) then
			return url
		end
	end
	return nil
end

-- Ajoute le compteur au début d'une section de la configuration de tabline.wez, s'il n'y est pas déjà.
--   opts  : la table renvoyée par tabline.get_config() (tabline la relit à chaque mise à jour) ;
--   items : une fonction (le compteur), ou une liste d'éléments ajoutés ensemble, dans l'ordre (par exemple un style,
--           le compteur, puis "ResetAttributes") ; le premier élément sert à savoir s'ils y sont déjà.
-- Renvoie true si le compteur vient d'être ajouté.
function M.ensure_component(opts, items, section)
	if type(opts) ~= "table" then
		return false
	end
	if type(items) ~= "table" then
		items = { items }
	end
	opts.sections = opts.sections or {}
	section = section or M.TABLINE_SECTION
	local list = opts.sections[section]
	if type(list) ~= "table" then
		list = {}
		opts.sections[section] = list
	end
	for _, item in ipairs(list) do
		if item == items[1] then
			return false
		end
	end
	for i, item in ipairs(items) do
		table.insert(list, i, item)
	end
	return true
end

return M
