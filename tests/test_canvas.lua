local H = require("tests.helpers")
local geometry = require("artist.geometry")

local T = H.new_set()

T["geometry operations"] = require("mini.test").new_set({
  parametrize = {
    { "line", { 1, 1 }, { 2, 4 }, { line_character = "#" } },
    { "straight_line", { 1, 1 }, { 2, 4 }, { second_arrow = true } },
    { "rectangle", { 1, 1 }, { 3, 5 }, { fill_character = "." } },
    { "square", { 1, 1 }, { 2, 5 }, { aspect_ratio = 2 } },
    { "ellipse", { 3, 4 }, { 4, 6 }, { line_character = "e" } },
    { "circle", { 3, 4 }, { 4, 6 }, { aspect_ratio = 2 } },
  },
})

T["geometry operations"]["delegate with options"] = function(operation, from, to, options)
  H.eq(H.canvas[operation](from, to, options), geometry[operation](from, to, options))
end

T["erase()"] = require("mini.test").new_set({
  parametrize = {
    { false, " " },
    { { erase_character = "x" }, "x" },
  },
})

T["erase()"]["fills the selected region"] = function(options, character)
  options = options or nil
  H.eq(H.canvas.erase({ 2, 2 }, { 1, 3 }, options), {
    { row = 1, col = 2, char = character },
    { row = 1, col = 3, char = character },
    { row = 2, col = 2, char = character },
    { row = 2, col = 3, char = character },
  })
end

T["merge_character()"] = require("mini.test").new_set({
  parametrize = {
    { "-", "|", "+" },
    { "/", "\\", "X" },
    { "-", "/", "/" },
  },
})

T["merge_character()"]["merges line characters"] = function(existing, incoming, expected)
  H.eq(H.canvas.merge_character(existing, incoming), expected)
end

T["unmerge_character()"] = require("mini.test").new_set({
  parametrize = {
    { "-", "+", false, "|" },
    { "\\", "X", false, "/" },
    { "-", "-", false, " " },
    { "-", "-", "x", "x" },
    { "-", "a", false, "a" },
  },
})

T["unmerge_character()"]["removes line characters"] = function(line, existing, erase, expected)
  H.eq(H.canvas.unmerge_character(line, existing, erase or nil), expected)
end

T["deduplicate() returns an empty list for no points"] = function()
  H.eq(H.canvas.deduplicate(), {})
end

T["deduplicate() preserves order and merges repeated coordinates"] = function()
  local points = {
    { row = 1, col = 2, char = "-" },
    { row = 2, col = 1, char = "a" },
    { row = 1, col = 2, char = "|" },
  }
  local result = H.canvas.deduplicate(points)

  H.eq(result, {
    { row = 1, col = 2, char = "+" },
    { row = 2, col = 1, char = "a" },
  })
  result[2].char = "b"
  H.eq(points[2].char, "a")
end

T["apply() intersects points and trims changed lines by default"] = function()
  H.reset({ "--  " })
  local transaction = H.canvas.apply(0, {
    { row = 1, col = 2, char = "|" },
    { row = 2, col = 3, char = "x" },
  })

  H.eq(H.lines(), { "-+", "  x" })
  H.eq(transaction.changes, {
    { row = 1, col = 2, before = "-", char = "+" },
    { row = 2, col = 3, before = " ", char = "x" },
  })
end

T["apply() can overwrite and preserve trailing spaces"] = function()
  H.reset({ "-  " })
  local bufnr = vim.api.nvim_get_current_buf()
  local transaction = H.canvas.apply(bufnr, { { row = 1, col = 1, char = "|" } }, {
    overwrite = true,
    trim_line_endings = false,
  })

  H.eq(H.lines(), { "|  " })
  H.eq(transaction:get(1, 1), "|")
  H.eq(transaction.trim, false)
end

T["exports its grid and patch modules"] = function()
  H.eq(H.canvas.grid, require("artist.grid"))
  H.eq(H.canvas.patch, require("artist.patch"))
end

T["registers all upstream operations"] = function()
  H.eq(#H.artist.tools, 24)
end

return T
