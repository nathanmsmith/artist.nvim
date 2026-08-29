local MiniTest = require("mini.test")

local child = MiniTest.new_child_neovim()
local eq = MiniTest.expect.equality
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/child_init.lua" })
    end,
    post_once = child.stop,
  },
})

local function lines()
  return child.api.nvim_buf_get_lines(0, 0, -1, false)
end

local function set_mouse(value)
  child.lua(
    [[
      _G.artist_test_mouse = ...
      vim.fn.getmousepos = function()
        return _G.artist_test_mouse
      end
    ]],
    { value }
  )
end

local function screen_row(winid)
  return child.fn.screenpos(winid, 1, 1).row
end

T["completed shape is one undoable change"] = function()
  child.lua([[artist.draw("line", { 1, 1 }, { 1, 3 })]])
  child.cmd("silent undo")
  eq(lines(), { "" })
end

T["non-modifiable buffers reject commits without changes"] = function()
  child.bo.modifiable = false
  local ok = child.lua_get([[select(1, pcall(artist.draw, "line", { 1, 1 }, { 1, 3 }))]])

  eq(ok, false)
  eq(lines(), { "" })
end

T["keyboard drawing remains a cancellable preview"] = function()
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.lua([[artist.enable(0, { tool = "pen", mappings = false })]])
  child.lua([[artist.keyboard_point(); artist.keyboard_move("l")]])

  eq(lines(), { "" })
  child.lua([[artist.cancel()]])
  eq(lines(), { "" })
end

T["mouse drag uses virtual columns and rows"] = function()
  local winid = child.api.nvim_get_current_win()
  child.lua([[artist.enable(0, { tool = "line" })]])
  local first_row = screen_row(winid)
  set_mouse({ line = 1, column = 1, coladd = 0, screenrow = first_row, winid = winid })

  child.lua([[artist.mouse_down()]])
  set_mouse({ line = 1, column = 1, coladd = 4, screenrow = first_row + 2, winid = winid })
  child.lua([[artist.mouse_drag()]])

  local marks = child.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })
  eq(#marks, 2)
  local virtual_line_count = 0
  for _, mark in ipairs(marks) do
    if mark[4].virt_lines then
      virtual_line_count = #mark[4].virt_lines
    end
  end
  eq(virtual_line_count, 2)

  child.lua([[artist.mouse_up()]])
  eq(lines(), { "--", "  \\-", "    \\" })
end

T["mouse drag reaches virtual rows"] = function()
  local winid = child.api.nvim_get_current_win()
  child.lua([[artist.enable(0, { tool = "line" })]])
  local first_row = screen_row(winid)
  set_mouse({ line = 1, column = 1, coladd = 0, screenrow = first_row, winid = winid })

  child.lua([[artist.mouse_down()]])
  set_mouse({ line = 1, column = 1, coladd = 0, screenrow = first_row + 2, winid = winid })
  child.lua([[artist.mouse_drag(); artist.mouse_up()]])

  eq(lines(), { "|", "|", "|" })
end

T["mouse drag preserves horizontal drawing"] = function()
  local winid = child.api.nvim_get_current_win()
  child.lua([[artist.enable(0, { tool = "line" })]])
  local first_row = screen_row(winid)
  set_mouse({ line = 1, column = 1, coladd = 0, screenrow = first_row, winid = winid })

  child.lua([[artist.mouse_down()]])
  set_mouse({ line = 1, column = 1, coladd = 4, screenrow = first_row, winid = winid })
  child.lua([[artist.mouse_drag(); artist.mouse_up()]])

  eq(lines(), { "-----" })
end

T["mode restores mappings and window options"] = function()
  local old_mouse = child.o.mouse
  local old_virtualedit = child.wo.virtualedit
  local old_wrap = child.wo.wrap
  local old_winbar = child.wo.winbar
  local old_winhighlight = child.wo.winhighlight
  child.wo.winhighlight = old_winhighlight == "" and "Normal:Normal" or old_winhighlight
  local artist_winhighlight = child.wo.winhighlight
  child.lua([[vim.keymap.set("n", "<CR>", ":let g:artist_original_mapping = 1<CR>", { buffer = true })]])
  local old_enter_mapping = child.fn.maparg("<CR>", "n", false, true).rhs

  child.lua([[artist.enable(0, { tool = "line" })]])
  eq(child.lua_get([[artist.is_enabled()]]), true)
  eq(child.wo.virtualedit, "all")
  eq(child.wo.winbar:find("ARTIST", 1, true) ~= nil, true)
  eq(child.wo.winbar:find("[line]", 1, true) ~= nil, true)
  eq(child.wo.winhighlight:find("Visual:ArtistVisual", 1, true) ~= nil, true)
  eq(child.wo.winhighlight:find("Normal:Normal", 1, true) ~= nil, true)

  child.lua([[artist.set_tool("ellipse")]])
  eq(child.lua_get([[artist.get_tool()]]), "ellipse")
  eq(child.wo.winbar:find("[ellipse]", 1, true) ~= nil, true)

  local artist_buffer = child.api.nvim_get_current_buf()
  local other_buffer = child.api.nvim_create_buf(false, true)
  child.api.nvim_win_set_buf(0, other_buffer)
  eq(child.wo.winbar, old_winbar)
  eq(child.wo.winhighlight, artist_winhighlight)
  eq(child.wo.virtualedit, old_virtualedit)

  child.api.nvim_win_set_buf(0, artist_buffer)
  eq(child.wo.winbar:find("[ellipse]", 1, true) ~= nil, true)
  child.api.nvim_buf_delete(other_buffer, { force = true })

  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.lua([[artist.keyboard_point()]])
  eq(#child.api.nvim_buf_get_extmarks(0, -1, 0, -1, {}), 1)
  child.lua([[artist.cancel()]])
  eq(#child.api.nvim_buf_get_extmarks(0, -1, 0, -1, {}), 0)
  child.lua([[artist.disable()]])

  eq(child.lua_get([[artist.is_enabled()]]), false)
  eq(child.o.mouse, old_mouse)
  eq(child.wo.virtualedit, old_virtualedit)
  eq(child.wo.wrap, old_wrap)
  eq(child.wo.winbar, old_winbar)
  eq(child.wo.winhighlight, artist_winhighlight)
  eq(child.fn.maparg("<CR>", "n", false, true).rhs, old_enter_mapping)
end

T["registers user commands"] = function()
  eq(child.fn.exists(":Artist"), 2)
  eq(child.fn.exists(":ArtistSet"), 2)
  eq(child.fn.exists(":ArtistPicker"), 2)
end

return T
