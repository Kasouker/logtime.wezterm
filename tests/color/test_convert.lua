-- tests/color/test_convert.lua : teste color/convert.lua (les codes de couleur, le contraste, le mélange).
-- Lancer :   lua5.4 tests/color/test_convert.lua
local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]color[/\\]test_convert%.lua$") or "."
local convert = assert(loadfile(root .. "/plugin/logtime/color/convert.lua"))()

local passed, failed = 0, 0
local function check(name, got, want)
	if got == want then
		passed = passed + 1
	else
		failed = failed + 1
		print(
			string.format(
				"ÉCHEC  %s\n         attendu : %s\n         obtenu  : %s",
				name,
				tostring(want),
				tostring(got)
			)
		)
	end
end

check("rgb", table.concat({ convert.rgb("#C9AB6B") }, " "), "201 171 107")
check("rgb : un code invalide donne du blanc", table.concat({ convert.rgb("zz") }, " "), "255 255 255")
check("fg", convert.fg("#010203"), "\27[38;2;1;2;3m")
check("bg", convert.bg("#010203"), "\27[48;2;1;2;3m")
check("contraste : texte sombre sur un fond clair", convert.contrast("#ECE6D9"), "#17191F")
check("contraste : texte clair sur un fond sombre", convert.contrast("#17191F"), "#ECE6D9")
-- le mélange : `top` posé sur `under` avec l'opacité alpha
check("mix : opacité 0, seulement le dessous", convert.mix("#FFFFFF", "#000000", 0), "#000000")
check("mix : opacité 1, seulement le dessus", convert.mix("#FFFFFF", "#000000", 1), "#FFFFFF")
check("mix : à moitié", convert.mix("#FFFFFF", "#000000", 0.5), "#808080")
check("mix : chaque composante à part", convert.mix("#FF0000", "#0000FF", 0.25), "#4000BF")
check("mix : l'opacité ramenée entre 0 et 1", convert.mix("#FFFFFF", "#000000", 7), "#FFFFFF")
check(
	"mix : la teinte des barres de F2 (35 % de clair sur le fond sombre)",
	convert.mix("#ECE6D9", "#1B1E25", 0.35),
	"#646464"
)

print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
