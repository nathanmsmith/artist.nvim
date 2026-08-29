local MiniTest = require("mini.test")
local Grid = require("artist.grid").Grid
local Patch = require("artist.patch").Patch

local eq = MiniTest.expect.equality
local T = MiniTest.new_set()

T["intersects incoming line characters"] = function()
  local patch = Patch.new(Grid.new({ "-" }))
  patch:set(1, 1, "|", { intersect = true })

  eq(patch:get(1, 1), "+")
  eq(patch.changes, { { row = 1, col = 1, before = "-", char = "+" } })
end

T["coalesces repeated writes to one change"] = function()
  local source = Grid.new({ "a" })
  local patch = Patch.new(source)
  patch:set(1, 1, "b")
  patch:set(1, 1, "c")

  eq(#patch.changes, 1)
  eq(patch.changes[1], { row = 1, col = 1, before = "a", char = "c" })
  eq(source:get(1, 1), "a")
end

T["recognizes patches with no effective changes"] = function()
  local patch = Patch.new(Grid.new({ "a" }))
  patch:set(1, 1, "a")
  eq(patch:is_empty(), true)
end

return T
