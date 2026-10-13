-- plugin/logtime/color/gradient.lua : le dégradé de couleurs des jours.
-- 0 h : aucune couleur (le jour reste « transparent »). Dès qu'il y a du temps, une teinte CLAIRE qui fonce
-- progressivement jusqu'à une teinte FONCÉE à max_hours (24 h par défaut). Seule la luminosité change : la teinte et la
-- saturation restent celles de la couleur de départ.
-- Aucune dépendance à WezTerm : se teste avec un simple interpréteur Lua.
local load = ...
local convert = load("color/convert")

local M = {}

M.DEFAULT_COLOR = "#C9AB6B" -- l'or de la palette actuelle
M.DEFAULT_LIGHT = 0.80 -- luminosité (HSL) des jours très courts
M.DEFAULT_DARK = 0.30 -- luminosité (HSL) à max_hours
M.DEFAULT_HOURS = 24
M.DEFAULT_CURVE = 0.5 -- 1 = linéaire ; moins de 1 = les premières heures se distinguent mieux (0,5 : racine carrée)

-- "#RRGGBB" <-> teinte (0 à 360), saturation et luminosité (0 à 1)
function M.hex_to_hsl(hex)
local r, g, b = convert.rgb(hex)
r, g, b = r / 255, g / 255, b / 255
local max, min = math.max(r, g, b), math.min(r, g, b)
local l = (max + min) / 2
if max == min then
return 0, 0, l
end
local d = max - min
local s = d / (1 - math.abs(2 * l - 1))
local h
if max == r then
h = ((g - b) / d) % 6
elseif max == g then
h = (b - r) / d + 2
else
h = (r - g) / d + 4
end
return h * 60, s, l
end

function M.hsl_to_hex(h, s, l)
local c = (1 - math.abs(2 * l - 1)) * s
local x = c * (1 - math.abs((h / 60) % 2 - 1))
local m = l - c / 2
local r, g, b
local sector = math.floor((h % 360) / 60)
if sector == 0 then
r, g, b = c, x, 0
elseif sector == 1 then
r, g, b = x, c, 0
elseif sector == 2 then
r, g, b = 0, c, x
elseif sector == 3 then
r, g, b = 0, x, c
elseif sector == 4 then
r, g, b = x, 0, c
else
r, g, b = c, 0, x
end
local function byte(v)
return math.max(0, math.min(255, math.floor((v + m) * 255 + 0.5)))
end
return string.format("#%02X%02X%02X", byte(r), byte(g), byte(b))
end

local function number_or(value, default, low, high)
local n = tonumber(value)
if not n then
return default
end
return math.max(low, math.min(high, n))
end

-- Fabrique le dégradé. opts (tout est facultatif) :
--   color      "#RRGGBB" : la teinte de départ (l'or par défaut ; un code invalide est ignoré)
--   light      luminosité des jours très courts, de 0 à 1 (0,80)
--   dark       luminosité à max_hours, de 0 à 1 (0,30)
--   max_hours  durée qui donne la teinte la plus foncée (24)
--   curve      courbure : 1 = linéaire, 0,5 = les premières heures se distinguent mieux (0,5)
-- Renvoie { color = fonction, legend = fonction }.
--   color(secondes) : le code "#RRGGBB" du fond du jour, ou nil quand il n'y a pas de temps
--   legend()        : une barre de couleurs "0h ████████ 24h" pour la légende
function M.make(opts)
opts = opts or {}
local base = tostring(opts.color or "")
if not base:match("^#?%x%x%x%x%x%x$") then
base = M.DEFAULT_COLOR
end
local hue, saturation = M.hex_to_hsl(base)
local light = number_or(opts.light, M.DEFAULT_LIGHT, 0, 1)
local dark = number_or(opts.dark, M.DEFAULT_DARK, 0, 1)
local max_hours = number_or(opts.max_hours, M.DEFAULT_HOURS, 0.01, 1000)
local curve = number_or(opts.curve, M.DEFAULT_CURVE, 0.05, 10)

local g = {}
function g.color(secs)
if type(secs) ~= "number" or secs ~= secs or secs <= 0 then
return nil
end
local t = math.min(1, (secs / 3600) / max_hours)
return M.hsl_to_hex(hue, saturation, light + (dark - light) * (t ^ curve))
end

function g.legend()
local parts = {}
for i = 0, 7 do
local hours = (i == 0) and 0.5 or (max_hours * i / 7)
parts[#parts + 1] = convert.fg(g.color(hours * 3600)) .. "██" .. convert.RESET
end
return "0h " .. table.concat(parts) .. string.format(" %gh", max_hours)
end

return g
end

return M
