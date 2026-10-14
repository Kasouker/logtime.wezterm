-- plugin/logtime/core/activity.lua : le temps par projet. Chaque seconde comptée va au « projet » de l'onglet affiché :
-- son dossier (les deux premiers dossiers sous le dossier personnel), ou son titre si le dossier n'apprend rien.
-- Aucune dépendance à WezTerm : se teste avec un simple interpréteur Lua.
local load = ...
local day = load("core/day")

local M = {}

M.OTHER = "?" -- le projet inconnu, et les petits projets regroupés (affiché « autres »)
M.MAX_PER_DAY = 30 -- au-delà, les plus petits projets du jour sont regroupés dans M.OTHER
M.MAX_LEN = 40 -- la longueur maximum d'un nom de projet (en caractères)

-- Les débuts de chemin qui sont un dossier personnel (Linux, Mac, Windows, et Windows vu depuis WSL).
local HOMES = {
	"^/home/[^/]+",
	"^/Users/[^/]+",
	"^/root",
	"^/mnt/%a/[Uu]sers/[^/]+",
	"^%a:/[Uu]sers/[^/]+",
}

-- Coupe un nom trop long (en caractères, pas en octets).
local function shorten(text)
	if utf8.len(text) and utf8.len(text) > M.MAX_LEN then
		return text:sub(1, utf8.offset(text, M.MAX_LEN) - 1) .. "…"
	end
	return text
end

-- Le chemin d'une adresse de dossier, comme WezTerm la donne : "file:///C:/Users/x/projet/" -> "C:/Users/x/projet",
-- "file://wsl.localhost/Ubuntu/home/x/" -> "/home/x" (la distribution WSL est retirée), "%20" -> " ".
function M.path_of(cwd)
	if type(cwd) ~= "string" or cwd == "" then
		return nil
	end
	local host, path = cwd:match("^file://([^/]*)(/.*)$")
	if not path then
		path = cwd:match("^/.*$") or cwd:match("^%a:[/\\].*$")
		if not path then
			return nil
		end
	end
	path = path:gsub("%%(%x%x)", function(hex)
		return string.char(tonumber(hex, 16))
	end)
	path = path:gsub("\\", "/")
	if host and (host:lower() == "wsl.localhost" or host:lower() == "wsl$") then
		path = path:gsub("^/[^/]+", "") -- /Ubuntu/home/x -> /home/x
	end
	path = path:gsub("^/(%a:/)", "%1") -- /C:/Users -> C:/Users
	path = path:gsub("/+$", "")
	return path
end

-- Le projet d'un chemin : les deux premiers dossiers sous le dossier personnel ; hors du dossier personnel, les deux
-- derniers. nil si le chemin n'apprend rien (le dossier personnel lui-même, la racine).
function M.project_of(path)
	if not path or path == "" or path:match("^%a:$") then
		return nil
	end
	local rest
	for _, pattern in ipairs(HOMES) do
		local s, e = path:find(pattern)
		if s and (path:sub(e + 1, e + 1) == "/" or e == #path) then
			rest = path:sub(e + 2)
			break
		end
	end
	local parts = {}
	for part in (rest or path):gmatch("[^/]+") do
		parts[#parts + 1] = part
	end
	if rest then
		if #parts == 0 then
			return nil
		end
		return table.concat(parts, "/", 1, math.min(2, #parts))
	end
	if parts[1] and parts[1]:match("^%a:$") then
		table.remove(parts, 1)
	end
	if #parts == 0 then
		return nil
	end
	return table.concat(parts, "/", math.max(1, #parts - 1), #parts)
end

-- Un titre d'onglet, nettoyé : sans les symboles du début (« ◑ », « ✳ », icônes), sans « .exe ».
function M.clean_title(title)
	if type(title) ~= "string" then
		return nil
	end
	local start = nil
	for pos, code in utf8.codes(title) do
		local symbol = code < 128 and not string.char(code):match("%w")
			or (code >= 0x2000 and code <= 0x2BFF)
			or (code >= 0xE000 and code <= 0xF8FF)
			or code >= 0x1F000
		if not symbol then
			start = pos
			break
		end
	end
	if not start then
		return nil
	end
	local text = title:sub(start):gsub("%s+$", ""):gsub("%.[Ee][Xx][Ee]$", "")
	return text ~= "" and text or nil
end

-- Le projet d'un onglet : son dossier s'il apprend quelque chose, sinon son titre, sinon M.OTHER.
function M.label(cwd, title)
	local name = M.project_of(M.path_of(cwd)) or M.clean_title(title)
	return name and shorten(name) or M.OTHER
end

-- Les secondes de [from, to] vont au projet `label`, jour par jour (coupées à minuit comme le compteur).
-- sign = -1 : elles lui sont retirées (jamais en dessous de zéro). projects : { ["2026-10-14"] = { [label] = secondes } }.
function M.add(projects, label, from, to, offset, sign)
	local split = {}
	day.add_interval(split, from, to, offset)
	for key, secs in pairs(split) do
		local of_day = projects[key] or {}
		projects[key] = of_day
		local value = (of_day[label] or 0) + (sign or 1) * secs
		of_day[label] = value > 0 and value or nil
		M.cap(of_day)
	end
end

-- Au plus M.MAX_PER_DAY projets dans un jour : les plus petits sont regroupés dans M.OTHER.
function M.cap(of_day)
	local list = {}
	for label, secs in pairs(of_day) do
		if label ~= M.OTHER then
			list[#list + 1] = { label = label, secs = secs }
		end
	end
	if #list < M.MAX_PER_DAY then
		return
	end
	table.sort(list, function(a, b)
		return a.secs > b.secs or (a.secs == b.secs and a.label < b.label)
	end)
	for i = M.MAX_PER_DAY, #list do
		of_day[M.OTHER] = (of_day[M.OTHER] or 0) + list[i].secs
		of_day[list[i].label] = nil
	end
end

-- Les plus gros projets d'un jour, du plus grand au plus petit : { { label, secs }, ... }, au plus n ; le reste
-- (et M.OTHER) regroupé à la fin dans { label = M.OTHER }.
function M.top(of_day, n)
	local list, other = {}, 0
	for label, secs in pairs(of_day or {}) do
		if label == M.OTHER then
			other = other + secs
		elseif secs > 0 then
			list[#list + 1] = { label = label, secs = secs }
		end
	end
	table.sort(list, function(a, b)
		return a.secs > b.secs or (a.secs == b.secs and a.label < b.label)
	end)
	for i = #list, n + 1, -1 do
		other = other + list[i].secs
		list[i] = nil
	end
	if other > 0 then
		list[#list + 1] = { label = M.OTHER, secs = other }
	end
	return list
end

return M
