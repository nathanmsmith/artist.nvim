local H = require("tests.helpers")
local Grid = require("artist.grid").Grid

local eq = H.eq
local T = H.new_set()

T["addresses tabs as display cells"] = function()
  local grid = Grid.new({ "\twide界" }, { tabstop = 8 })
  grid:set(1, 2, "Z")
  eq(grid:render(false), { " Z      wide界" })
end

T["handles combining and wide glyph display cells"] = function()
  local grid = Grid.new({ "é界x", "\tuntouched" }, { tabstop = 8 })
  grid:set(1, 3, "Z")
  eq(grid:render(false), { "é Zx", "        untouched" })
end

T["clone isolates subsequent writes"] = function()
  local original = Grid.new({ "abc" })
  local clone = original:clone()
  clone:set(1, 2, "X")

  eq(original:render(), { "abc" })
  eq(clone:render(), { "aXc" })
end

T["draw addresses tabs as display cells"] = function()
  H.reset({ "\twide界" })
  H.artist.draw("pen", { 1, 2 }, nil, { line_character = "Z", trim_line_endings = false })
  eq(H.lines()[1], " Z      wide界")
end

T["draw preserves untouched rows with complex glyphs"] = function()
  H.reset({ "é界x", "\tuntouched" })
  H.artist.draw("pen", { 1, 3 }, nil, { line_character = "Z", trim_line_endings = false })
  eq(H.lines(), { "é Zx", "\tuntouched" })
end

return T
