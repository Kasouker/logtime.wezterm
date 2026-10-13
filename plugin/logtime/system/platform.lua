-- plugin/logtime/system/platform.lua : ce qui dépend du système (Windows, macOS, Linux).
-- Aucune dépendance à WezTerm : se teste avec un simple interpréteur Lua.
local M = {}

-- "windows", "macos" ou "linux", d'après l'identifiant du système de WezTerm (wezterm.target_triple)
function M.os_name(triple)
	triple = tostring(triple or "")
	if triple:find("windows", 1, true) then
		return "windows"
	end
	if triple:find("apple", 1, true) then
		return "macos"
	end
	return "linux"
end

-- Un programme qui ne fait rien et n'écrit rien : il garde un onglet ouvert pendant que le plugin dessine dedans.
-- Sous Windows, la sortie de ping est jetée (>nul) : sinon chaque réponse de ping s'écrirait par-dessus le calendrier.
function M.blocker_args(os_name)
	if os_name == "windows" then
		return { "cmd.exe", "/c", "ping -n 86400 127.0.0.1>nul" }
	end
	return { "sh", "-c", "stty -echo 2>/dev/null; exec sleep 86400" }
end

return M
