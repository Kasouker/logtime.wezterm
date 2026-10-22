-- tests/color/test_convert.lua : teste color/convert.lua (les codes de couleur, le contraste).
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
print(string.format("\n%d vérifications réussies, %d échecs", passed, failed))
os.exit(failed == 0 and 0 or 1)
