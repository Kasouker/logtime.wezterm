-- tools/afficher_mois.lua : affiche un mois du calendrier dans le terminal, à partir du fichier des heures.
-- LECTURE SEULE : ce programme n'écrit jamais rien.
--
-- Utilisation :
--   lua5.4 tools/afficher_mois.lua [FICHIER] [ANNEE MOIS] [--en] [--dimanche] [--objectif=HEURES]
-- Exemples :
--   lua5.4 tools/afficher_mois.lua /mnt/c/Users/TON_NOM/.local/share/logtime/.logtime.json
--   lua5.4 tools/afficher_mois.lua /mnt/c/Users/TON_NOM/.local/share/logtime/.logtime.json 2026 9 --dimanche --objectif=3
-- Sans FICHIER : ~/.local/share/logtime/.logtime.json (sous WSL, c'est le dossier personnel de Linux, pas celui de Windows).
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tools[/\\]afficher_mois%.lua$") or "."

local cache = {}
local function load_module(name)
	if not cache[name] then
		local chunk = assert(loadfile(root .. "/plugin/logtime/" .. name .. ".lua"))
		cache[name] = chunk(load_module)
	end
	return cache[name]
end

local function fail(message)
	io.stderr:write(message .. "\n")
	os.exit(1)
end

local positional = {}
local lang, week, goal = "fr", "monday", nil
for _, a in ipairs(arg) do
	if a == "--en" then
		lang = "en"
	elseif a == "--dimanche" or a == "--sunday" then
		week = "sunday"
	elseif a:match("^%-%-objectif=") or a:match("^%-%-goal=") then
		goal = tonumber(a:match("=(.*)$"))
		if not goal or goal <= 0 then
			fail("objectif invalide : " .. a)
		end
	elseif a:sub(1, 2) == "--" then
		fail("option inconnue : " .. a)
	else
		positional[#positional + 1] = a
	end
end

local path = positional[1] or ((os.getenv("HOME") or ".") .. "/.local/share/logtime/.logtime.json")
local today = os.date("*t")
local year, month = today.year, today.month
if positional[2] or positional[3] then
	year, month = tonumber(positional[2]), tonumber(positional[3])
	if not year or not month then
		fail("il faut l'année ET le mois, par exemple : 2026 9")
	end
end
if year % 1 ~= 0 or month % 1 ~= 0 or month < 1 or month > 12 or year < 1970 or year > 2200 then
	fail("date invalide : " .. tostring(year) .. " " .. tostring(month))
end

local storage = load_module("storage/days")
local days, state, why = storage.load(path)
if state == "absent" then
	fail("fichier introuvable : " .. path)
end
if state == "corrupt" then
	fail("fichier illisible (" .. tostring(why) .. ") : " .. path .. " (rien n'a été modifié)")
end

local assemble = load_module("calendar/assemble")
local labels = load_module("i18n/" .. lang)
local cfg = { week_starts_on = week, goal_hours = goal }
io.write(assemble.render_month(days, year, month, os.date("%Y-%m-%d"), cfg, labels), "\n")
