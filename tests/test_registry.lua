local MiniTest = require("mini.test")
local registry = require("artist.registry")

local eq = MiniTest.expect.equality
local T = MiniTest.new_set()

T["resolves compatibility aliases"] = function()
  eq(registry.resolve("freehand"), "pen_line")
  eq(registry.resolve("straight-polyline"), "straight_poly_line")
  eq(registry.resolve("unknown"), nil)
end

T["returns sorted operation names"] = function()
  local names = registry.names()
  eq(#names, 24)
  eq(names[1], "circle")
  eq(names[#names], "vaporize_lines")
end

T["finds shifted counterparts"] = function()
  eq(registry.shifted("rectangle"), "square")
  eq(registry.shifted("square"), "rectangle")
end

return T
