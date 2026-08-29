local H = require("tests.helpers")

local T = H.new_set()

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

T["registers all upstream operations"] = function()
  H.eq(#H.artist.tools, 24)
end

return T
