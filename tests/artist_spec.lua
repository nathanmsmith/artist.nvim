local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)

local artist = require("artist")
local canvas = require("artist.canvas")

local function equal(expected, actual, message)
  if not vim.deep_equal(expected, actual) then
    error(
      (message or "values differ") .. "\nexpected: " .. vim.inspect(expected) .. "\nactual: " .. vim.inspect(actual)
    )
  end
end

local function reset(lines)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines or { "" })
  vim.bo.modified = false
end

equal("+", canvas.merge_character("-", "|"), "orthogonal lines intersect")
equal("X", canvas.merge_character("/", "\\"), "diagonal lines intersect")

reset()
artist.draw("line", { 1, 1 }, { 1, 5 })
artist.draw("line", { 1, 3 }, { 3, 3 })
equal({ "--+--", "  |", "  |" }, vim.api.nvim_buf_get_lines(0, 0, -1, false), "lines draw and merge")

reset()
artist.draw("line", { 1, 1 }, { 3, 8 })
equal({ "--", "  \\---", "      \\-" }, vim.api.nvim_buf_get_lines(0, 0, -1, false), "shallow lines use clean segments")

reset()
artist.draw("line", { 1, 1 }, { 1, 3 })
vim.cmd("silent undo")
equal({ "" }, vim.api.nvim_buf_get_lines(0, 0, -1, false), "a completed shape is one undoable change")

reset()
artist.draw("rectangle", { 1, 1 }, { 3, 5 })
equal({ "+---+", "|   |", "+---+" }, vim.api.nvim_buf_get_lines(0, 0, -1, false), "rectangle rasterization")

artist.draw("erase", { 2, 2 }, { 2, 4 })
equal({ "+---+", "|   |", "+---+" }, vim.api.nvim_buf_get_lines(0, 0, -1, false), "erasing spaces preserves dimensions")

local old_mouse = vim.o.mouse
local old_virtualedit = vim.wo.virtualedit
vim.keymap.set("n", "<CR>", ":let g:artist_original_mapping = 1<CR>", { buffer = true })
local old_enter_mapping = vim.fn.maparg("<CR>", "n", false, true).rhs
artist.enable()
equal(true, artist.is_enabled(), "mode enables")
equal("all", vim.wo.virtualedit, "mode enables virtual editing")
artist.set_tool("ellipse")
equal("ellipse", artist.get_tool(), "tool changes")
vim.api.nvim_win_set_cursor(0, { 1, 0 })
artist.keyboard_point()
equal(1, #vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, {}), "keyboard drawing creates a preview")
artist.cancel()
equal(0, #vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, {}), "cancel clears the preview")
artist.disable()
equal(false, artist.is_enabled(), "mode disables")
equal(old_mouse, vim.o.mouse, "mouse option restores")
equal(old_virtualedit, vim.wo.virtualedit, "virtualedit restores")
equal(old_enter_mapping, vim.fn.maparg("<CR>", "n", false, true).rhs, "buffer mapping restores")
vim.keymap.del("n", "<CR>", { buffer = true })

artist._create_commands()
equal(2, vim.fn.exists(":Artist"), "commands register")

vim.bo.modified = false
print("artist.nvim: all tests passed")
