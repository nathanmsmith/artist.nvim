local H = require("tests.helpers")

local artist, eq = H.artist, H.eq
local T = H.new_set()

T["lines draw and merge"] = function()
  artist.draw("line", { 1, 1 }, { 1, 5 })
  artist.draw("line", { 1, 3 }, { 3, 3 })
  eq(H.lines(), { "--+--", "  |", "  |" })
end

T["shallow lines use clean segments"] = function()
  artist.draw("line", { 1, 1 }, { 3, 8 })
  eq(H.lines(), { "--", "  \\---", "      \\-" })
end

T["endpoint reversal follows Artist's directional glyph assignment"] = function()
  artist.draw("line", { 3, 8 }, { 1, 1 })
  eq(H.lines(), { "-\\", "  ---\\", "      --" })
end

T["rectangle rasterization"] = function()
  artist.draw("rectangle", { 1, 1 }, { 3, 5 })
  eq(H.lines(), { "+---+", "|   |", "+---+" })
end

T["erasing spaces preserves dimensions"] = function()
  artist.draw("rectangle", { 1, 1 }, { 3, 5 })
  artist.draw("erase", { 2, 2 }, { 2, 4 })
  eq(H.lines(), { "+---+", "|   |", "+---+" })
end

T["straight lines snap diagonally"] = function()
  artist.draw("straight_line", { 1, 1 }, { 3, 3 })
  eq(H.lines(), { [[\]], [[ \]], [[  \]] })
end

T["filled rectangles"] = function()
  artist.draw("rectangle", { 1, 1 }, { 3, 5 }, { fill_character = "." })
  eq(H.lines(), { "+---+", "|...|", "+---+" })
end

T["squares honor aspect ratio"] = function()
  artist.draw("square", { 1, 1 }, { 2, 5 }, { aspect_ratio = 2 })
  eq(H.lines(), { "+---+", "|   |", "+---+" })
end

T["flood fill is four-connected"] = function()
  H.reset({ "+---+", "|   |", "+---+" })
  artist.draw("flood_fill", { 2, 3 }, nil, { fill_character = ".", flood_fill_right_boundary = 20 })
  eq(H.lines(), { "+---+", "|...|", "+---+" })
end

T["rectangle copy and paste"] = function()
  H.reset({ "abcde", "fghij" })
  artist.draw("copy_rectangle", { 1, 2 }, { 2, 4 })
  artist.draw("paste", { 3, 1 })
  eq(H.lines(), { "abcde", "fghij", "bcd", "ghi" })
end

T["vaporize preserves crossing topology"] = function()
  H.reset({ "+---+", "|   |", "+---+" })
  artist.draw("vaporize_line", { 1, 3 })
  eq(H.lines(), { "|   |", "|   |", "+---+" })
end

T["connected vaporize terminates"] = function()
  H.reset({ "+---+", "|   |", "+---+" })
  artist.draw("vaporize_lines", { 1, 3 })
  eq(H.lines(), { "", "", "" })
end

T["line endpoint arrows"] = function()
  artist.draw("line", { 1, 1 }, { 1, 5 }, { first_arrow = true, second_arrow = true })
  eq(H.lines(), { "<--->" })
end

T["spray RNG is injectable"] = function()
  artist.draw("spray", { 1, 1 }, nil, {
    spray_radius = 2,
    rng = function(minimum)
      return minimum
    end,
  })
  eq(H.lines(), { "m" })
end

T["see-through text preserves blanks"] = function()
  H.reset({ "xxxxx" })
  artist.draw("text_see_through", { 1, 1 }, nil, {
    text = "A A",
    text_renderer = function(text)
      return { text }
    end,
  })
  eq(H.lines(), { "AxAxx" })
end

T["large flood fill respects its boundary"] = function()
  H.reset(vim.fn["repeat"]({ "" }, 40))
  artist.draw("flood_fill", { 20, 20 }, nil, { fill_character = ".", flood_fill_right_boundary = 60 })
  eq(#H.lines()[1], 60)
  eq(#H.lines()[40], 60)
end

return T
