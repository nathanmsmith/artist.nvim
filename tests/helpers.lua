local MiniTest = require("mini.test")
local artist = require("artist")

artist._create_commands()

local M = {
  artist = artist,
  canvas = require("artist.canvas"),
  expect = MiniTest.expect,
  eq = MiniTest.expect.equality,
}

function M.lines()
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

function M.reset(lines)
  if artist.is_enabled(0) then
    artist.disable(0)
  end
  vim.bo.modifiable = true
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines or { "" })
  vim.bo.modified = false
end

function M.new_set()
  return MiniTest.new_set({
    hooks = {
      pre_case = function()
        M.reset()
      end,
      post_case = function()
        if artist.is_enabled(0) then
          artist.disable(0)
        end
      end,
    },
  })
end

return M
