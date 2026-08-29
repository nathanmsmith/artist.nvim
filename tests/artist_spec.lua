local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)

local artist = require("artist")
local canvas = require("artist.canvas")
artist._create_commands()

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

local fixture_file = assert(io.open(root .. "/tests/fixtures/artist.json", "r"))
local fixtures = vim.json.decode(fixture_file:read("*a"))
fixture_file:close()
for _, fixture in ipairs(fixtures) do
  reset()
  artist.draw(fixture.operation, fixture.from, fixture.to)
  equal(fixture.lines, vim.api.nvim_buf_get_lines(0, 0, -1, false), "oracle fixture: " .. fixture.name)
end

equal("+", canvas.merge_character("-", "|"), "orthogonal lines intersect")
equal("X", canvas.merge_character("/", "\\"), "diagonal lines intersect")
equal("/", canvas.merge_character("-", "/"), "unrelated line directions overwrite")
equal(24, #artist.tools, "all upstream operations are registered")

reset()
artist.draw("line", { 1, 1 }, { 1, 5 })
artist.draw("line", { 1, 3 }, { 3, 3 })
equal({ "--+--", "  |", "  |" }, vim.api.nvim_buf_get_lines(0, 0, -1, false), "lines draw and merge")

reset()
artist.draw("line", { 1, 1 }, { 3, 8 })
equal({ "--", "  \\---", "      \\-" }, vim.api.nvim_buf_get_lines(0, 0, -1, false), "shallow lines use clean segments")

reset()
artist.draw("line", { 3, 8 }, { 1, 1 })
equal(
  { "-\\", "  ---\\", "      --" },
  vim.api.nvim_buf_get_lines(0, 0, -1, false),
  "endpoint reversal follows Artist's directional glyph assignment"
)

reset()
artist.draw("line", { 1, 1 }, { 1, 3 })
vim.cmd("silent undo")
equal({ "" }, vim.api.nvim_buf_get_lines(0, 0, -1, false), "a completed shape is one undoable change")

reset()
artist.draw("rectangle", { 1, 1 }, { 3, 5 })
equal({ "+---+", "|   |", "+---+" }, vim.api.nvim_buf_get_lines(0, 0, -1, false), "rectangle rasterization")

artist.draw("erase", { 2, 2 }, { 2, 4 })
equal({ "+---+", "|   |", "+---+" }, vim.api.nvim_buf_get_lines(0, 0, -1, false), "erasing spaces preserves dimensions")

reset()
artist.draw("straight_line", { 1, 1 }, { 3, 3 })
equal({ [[\]], [[ \]], [[  \]] }, vim.api.nvim_buf_get_lines(0, 0, -1, false), "straight lines snap diagonally")

reset()
artist.draw("rectangle", { 1, 1 }, { 3, 5 }, { fill_character = "." })
equal({ "+---+", "|...|", "+---+" }, vim.api.nvim_buf_get_lines(0, 0, -1, false), "filled rectangles")

reset()
artist.draw("square", { 1, 1 }, { 2, 5 }, { aspect_ratio = 2 })
equal({ "+---+", "|   |", "+---+" }, vim.api.nvim_buf_get_lines(0, 0, -1, false), "squares honor aspect ratio")

reset({ "+---+", "|   |", "+---+" })
artist.draw("flood_fill", { 2, 3 }, nil, { fill_character = ".", flood_fill_right_boundary = 20 })
equal({ "+---+", "|...|", "+---+" }, vim.api.nvim_buf_get_lines(0, 0, -1, false), "four-connected flood fill")

reset({ "abcde", "fghij" })
artist.draw("copy_rectangle", { 1, 2 }, { 2, 4 })
artist.draw("paste", { 3, 1 })
equal({ "abcde", "fghij", "bcd", "ghi" }, vim.api.nvim_buf_get_lines(0, 0, -1, false), "rectangle copy and paste")

reset({ "+---+", "|   |", "+---+" })
artist.draw("vaporize_line", { 1, 3 })
equal(
  { "|   |", "|   |", "+---+" },
  vim.api.nvim_buf_get_lines(0, 0, -1, false),
  "vaporize preserves crossing topology"
)

reset({ "+---+", "|   |", "+---+" })
artist.draw("vaporize_lines", { 1, 3 })
equal({ "", "", "" }, vim.api.nvim_buf_get_lines(0, 0, -1, false), "connected vaporize terminates")

reset()
artist.draw("line", { 1, 1 }, { 1, 5 }, { first_arrow = true, second_arrow = true })
equal({ "<--->" }, vim.api.nvim_buf_get_lines(0, 0, -1, false), "line endpoint arrows")

reset()
artist.draw("spray", { 1, 1 }, nil, {
  spray_radius = 2,
  rng = function(minimum)
    return minimum
  end,
})
equal({ "m" }, vim.api.nvim_buf_get_lines(0, 0, -1, false), "spray RNG is injectable")

reset({ "xxxxx" })
artist.draw("text_see_through", { 1, 1 }, nil, {
  text = "A A",
  text_renderer = function(text)
    return { text }
  end,
})
equal({ "AxAxx" }, vim.api.nvim_buf_get_lines(0, 0, -1, false), "see-through text preserves blanks")

reset({ "\twide界" })
artist.draw("pen", { 1, 2 }, nil, { line_character = "Z", trim_line_endings = false })
local display_line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]
equal(" Z      wide界", display_line, "tabs are addressed as display cells")

reset({ "é界x", "\tuntouched" })
artist.draw("pen", { 1, 3 }, nil, { line_character = "Z", trim_line_endings = false })
equal(
  { "é Zx", "\tuntouched" },
  vim.api.nvim_buf_get_lines(0, 0, -1, false),
  "combining and wide glyphs occupy their display cells without rewriting untouched rows"
)

reset(vim.fn["repeat"]({ "" }, 40))
artist.draw("flood_fill", { 20, 20 }, nil, { fill_character = ".", flood_fill_right_boundary = 60 })
equal(60, #vim.api.nvim_buf_get_lines(0, 0, 1, false)[1], "large flood fill reaches its configured boundary")
equal(60, #vim.api.nvim_buf_get_lines(0, 39, 40, false)[1], "large flood fill terminates at the vertical boundary")

reset()
vim.bo.modifiable = false
local modifiable_ok = pcall(artist.draw, "line", { 1, 1 }, { 1, 3 })
vim.bo.modifiable = true
equal(false, modifiable_ok, "non-modifiable buffers reject atomic commits")
equal({ "" }, vim.api.nvim_buf_get_lines(0, 0, -1, false), "non-modifiable buffers remain unchanged")

reset()
vim.api.nvim_win_set_cursor(0, { 1, 0 })
artist.enable(0, { tool = "pen", mappings = false })
artist.keyboard_point()
artist.keyboard_move("l")
equal({ "" }, vim.api.nvim_buf_get_lines(0, 0, -1, false), "keyboard continuous drawing remains a preview")
artist.cancel()
equal({ "" }, vim.api.nvim_buf_get_lines(0, 0, -1, false), "cancel restores continuous keyboard drawing exactly")
artist.disable()

reset({ "" })
local original_getmousepos = vim.fn.getmousepos
local mouse_winid = vim.api.nvim_get_current_win()
local fake_mouse = {
  line = 1,
  column = 1,
  coladd = 0,
  screenrow = 1,
  winid = mouse_winid,
}
---@diagnostic disable-next-line: duplicate-set-field
vim.fn.getmousepos = function()
  return fake_mouse
end
artist.enable(0, { tool = "line" })
local first_screen_row = vim.fn.screenpos(mouse_winid, 1, 1).row
fake_mouse.screenrow = first_screen_row
artist.mouse_down()
fake_mouse = {
  line = 1,
  column = 1,
  coladd = 4,
  screenrow = first_screen_row + 2,
  winid = mouse_winid,
}
artist.mouse_drag()
local drag_marks = vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })
equal(2, #drag_marks, "drag previews rows below the buffer")
local virtual_line_count = 0
for _, mark in ipairs(drag_marks) do
  if mark[4].virt_lines then
    virtual_line_count = #mark[4].virt_lines
  end
end
equal(2, virtual_line_count, "preview includes each virtual canvas row")
artist.mouse_up()
artist.disable()
equal({ "--", "  \\-", "    \\" }, vim.api.nvim_buf_get_lines(0, 0, -1, false), "mouse drag uses virtual columns")

reset({ "" })
artist.enable(0, { tool = "line" })
first_screen_row = vim.fn.screenpos(mouse_winid, 1, 1).row
fake_mouse = { line = 1, column = 1, coladd = 0, screenrow = first_screen_row, winid = mouse_winid }
artist.mouse_down()
fake_mouse = { line = 1, column = 1, coladd = 0, screenrow = first_screen_row + 2, winid = mouse_winid }
artist.mouse_drag()
artist.mouse_up()
artist.disable()
equal({ "|", "|", "|" }, vim.api.nvim_buf_get_lines(0, 0, -1, false), "mouse drag uses virtual rows")

reset({ "" })
artist.enable(0, { tool = "line" })
first_screen_row = vim.fn.screenpos(mouse_winid, 1, 1).row
fake_mouse = { line = 1, column = 1, coladd = 0, screenrow = first_screen_row, winid = mouse_winid }
artist.mouse_down()
fake_mouse = { line = 1, column = 1, coladd = 4, screenrow = first_screen_row, winid = mouse_winid }
artist.mouse_drag()
artist.mouse_up()
artist.disable()
equal({ "-----" }, vim.api.nvim_buf_get_lines(0, 0, -1, false), "mouse drag preserves horizontal drawing")
vim.fn.getmousepos = original_getmousepos

local old_mouse = vim.o.mouse
local old_virtualedit = vim.wo.virtualedit
local old_wrap = vim.wo.wrap
local old_winbar = vim.wo.winbar
local old_winhighlight = vim.wo.winhighlight
vim.wo.winhighlight = old_winhighlight == "" and "Normal:Normal" or old_winhighlight
local artist_previous_winhighlight = vim.wo.winhighlight
vim.keymap.set("n", "<CR>", ":let g:artist_original_mapping = 1<CR>", { buffer = true })
local old_enter_mapping = vim.fn.maparg("<CR>", "n", false, true).rhs
artist.enable(0, { tool = "line" })
equal(true, artist.is_enabled(), "mode enables")
equal("all", vim.wo.virtualedit, "mode enables virtual editing")
equal(true, vim.wo.winbar:find("ARTIST", 1, true) ~= nil, "mode displays its winbar")
equal(true, vim.wo.winbar:find("[line]", 1, true) ~= nil, "winbar highlights the active tool")
equal(true, vim.wo.winhighlight:find("Visual:ArtistVisual", 1, true) ~= nil, "Visual highlight becomes transparent")
equal(true, vim.wo.winhighlight:find("Normal:Normal", 1, true) ~= nil, "existing highlight overrides remain")
artist.set_tool("ellipse")
equal("ellipse", artist.get_tool(), "tool changes")
equal(true, vim.wo.winbar:find("[ellipse]", 1, true) ~= nil, "winbar updates with the active tool")
local artist_buffer = vim.api.nvim_get_current_buf()
local other_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(0, other_buffer)
equal(old_winbar, vim.wo.winbar, "winbar does not leak into another buffer")
equal(artist_previous_winhighlight, vim.wo.winhighlight, "highlight override does not leak into another buffer")
equal(old_virtualedit, vim.wo.virtualedit, "window options restore when leaving the Artist buffer")
vim.api.nvim_win_set_buf(0, artist_buffer)
equal(true, vim.wo.winbar:find("[ellipse]", 1, true) ~= nil, "winbar returns with the Artist buffer")
vim.api.nvim_buf_delete(other_buffer, { force = true })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
artist.keyboard_point()
equal(1, #vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, {}), "keyboard drawing creates a preview")
artist.cancel()
equal(0, #vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, {}), "cancel clears the preview")
artist.disable()
equal(false, artist.is_enabled(), "mode disables")
equal(old_mouse, vim.o.mouse, "mouse option restores")
equal(old_virtualedit, vim.wo.virtualedit, "virtualedit restores")
equal(old_wrap, vim.wo.wrap, "wrap restores")
equal(old_winbar, vim.wo.winbar, "winbar restores")
equal(artist_previous_winhighlight, vim.wo.winhighlight, "highlight overrides restore")
vim.wo.winhighlight = old_winhighlight
equal(old_enter_mapping, vim.fn.maparg("<CR>", "n", false, true).rhs, "buffer mapping restores")
vim.keymap.del("n", "<CR>", { buffer = true })

equal(2, vim.fn.exists(":Artist"), "commands register")
equal(2, vim.fn.exists(":ArtistSet"), "settings command registers")
equal(2, vim.fn.exists(":ArtistPicker"), "operation picker command registers")

vim.bo.modified = false
print("artist.nvim: all tests passed")
