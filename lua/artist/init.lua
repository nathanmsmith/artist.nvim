local canvas = require("artist.canvas")
local grid = require("artist.grid")
local operations = require("artist.operations")
local patch = require("artist.patch")
local registry = require("artist.registry")

local M = {}

---@type Artist.Options
local defaults = {
  tool = "pen_line",
  aspect_ratio = 1,
  rubber_banding = true,
  first_character = "1",
  second_character = "2",
  line_character = nil,
  fill_character = nil,
  default_fill_character = ".",
  pen_character = "*", -- compatibility name for the former freehand tool
  erase_character = " ",
  arrow_characters = { ">", false, "v", "L", "<", false, "^", false },
  first_arrow = false,
  second_arrow = false,
  trim_line_endings = true,
  flood_fill_right_boundary = "window_width",
  fill_column = 80,
  flood_fill_incremental = false,
  ellipse_left_character = "(",
  ellipse_right_character = ")",
  borderless_shapes = false,
  vaporize_fuzziness = 1,
  spray_interval = 0.2,
  spray_radius = 4,
  spray_characters = { " ", ".", "-", "+", "m", "%", "*", "#" },
  spray_initial_character = ".",
  timer_factory = nil,
  text_renderer = nil,
  figlet_executable = "figlet",
  figlet_font = "standard",
  rectangle_register = '"',
  mappings = true,
  keymaps = {},
  show_palette_on_enable = true,
  mouse_wheel = false,
  statusline = true,
  transparent_selection = true,
}

---@type Artist.Options
local config = vim.deepcopy(defaults)
---@type table<integer, Artist.Session>
local sessions = {}
local namespace = vim.api.nvim_create_namespace("artist.nvim")
local palette_namespace = vim.api.nvim_create_namespace("artist.nvim.palette")
local augroup
local original_mouse

-- This is intentionally ordered: it is the source of truth for mappings,
-- palette presentation, and tool traversal.
local key_spec = {
  {
    action = "pen",
    lhs = "b",
    method = "select_tool",
    arg = "pen",
    label = "Pen",
    shifted = "pen_line",
    group = "tools",
  },
  {
    action = "pen_line",
    lhs = "B",
    method = "select_tool",
    arg = "pen_line",
    label = "Pen Line",
    shifted = "pen",
    group = "tools",
  },
  {
    action = "line",
    lhs = "n",
    method = "select_tool",
    arg = "line",
    label = "Line",
    shifted = "straight_line",
    group = "tools",
  },
  {
    action = "straight_line",
    lhs = "N",
    method = "select_tool",
    arg = "straight_line",
    label = "Straight Line",
    shifted = "line",
    group = "tools",
  },
  {
    action = "poly_line",
    lhs = "m",
    method = "select_tool",
    arg = "poly_line",
    label = "Poly-line",
    shifted = "straight_poly_line",
    group = "tools",
  },
  {
    action = "straight_poly_line",
    lhs = "M",
    method = "select_tool",
    arg = "straight_poly_line",
    label = "Straight Poly-line",
    shifted = "poly_line",
    group = "tools",
  },
  {
    action = "rectangle",
    lhs = "r",
    method = "select_tool",
    arg = "rectangle",
    label = "Rectangle",
    shifted = "square",
    group = "tools",
  },
  {
    action = "square",
    lhs = "R",
    method = "select_tool",
    arg = "square",
    label = "Square",
    shifted = "rectangle",
    group = "tools",
  },
  {
    action = "ellipse",
    lhs = "e",
    method = "select_tool",
    arg = "ellipse",
    label = "Ellipse",
    shifted = "circle",
    group = "tools",
  },
  {
    action = "circle",
    lhs = "E",
    method = "select_tool",
    arg = "circle",
    label = "Circle",
    shifted = "ellipse",
    group = "tools",
  },
  {
    action = "spray",
    lhs = "s",
    method = "select_tool",
    arg = "spray",
    label = "Spray",
    shifted = "spray_radius",
    group = "tools",
  },
  {
    action = "spray_radius",
    lhs = "S",
    method = "select_tool",
    arg = "spray_radius",
    label = "Spray Radius",
    shifted = "spray",
    group = "tools",
  },
  {
    action = "text_see_through",
    lhs = "t",
    method = "select_tool",
    arg = "text_see_through",
    label = "Text",
    shifted = "text_overwrite",
    group = "tools",
  },
  {
    action = "text_overwrite",
    lhs = "T",
    method = "select_tool",
    arg = "text_overwrite",
    label = "Text Overwrite",
    shifted = "text_see_through",
    group = "tools",
  },
  {
    action = "erase_character",
    lhs = "x",
    method = "select_tool",
    arg = "erase_character",
    label = "Erase Character",
    shifted = "erase_rectangle",
    group = "tools",
  },
  {
    action = "erase_rectangle",
    lhs = "X",
    method = "select_tool",
    arg = "erase_rectangle",
    label = "Erase Rectangle",
    shifted = "erase_character",
    group = "tools",
  },
  {
    action = "vaporize_line",
    lhs = "v",
    method = "select_tool",
    arg = "vaporize_line",
    label = "Vaporize Line",
    shifted = "vaporize_lines",
    group = "tools",
  },
  {
    action = "vaporize_lines",
    lhs = "V",
    method = "select_tool",
    arg = "vaporize_lines",
    label = "Vaporize Connected",
    shifted = "vaporize_line",
    group = "tools",
  },
  {
    action = "cut_rectangle",
    lhs = "d",
    method = "select_tool",
    arg = "cut_rectangle",
    label = "Cut Rectangle",
    shifted = "cut_square",
    group = "tools",
  },
  {
    action = "cut_square",
    lhs = "D",
    method = "select_tool",
    arg = "cut_square",
    label = "Cut Square",
    shifted = "cut_rectangle",
    group = "tools",
  },
  {
    action = "copy_rectangle",
    lhs = "y",
    method = "select_tool",
    arg = "copy_rectangle",
    label = "Copy Rectangle",
    shifted = "copy_square",
    group = "tools",
  },
  {
    action = "copy_square",
    lhs = "Y",
    method = "select_tool",
    arg = "copy_square",
    label = "Copy Square",
    shifted = "copy_rectangle",
    group = "tools",
  },
  {
    action = "paste",
    lhs = "p",
    method = "select_tool",
    arg = "paste",
    label = "Paste",
    group = "tools",
  },
  {
    action = "flood_fill",
    lhs = "f",
    method = "select_tool",
    arg = "flood_fill",
    label = "Flood Fill",
    group = "tools",
  },
  {
    action = "previous_tool",
    lhs = "[a",
    method = "previous_tool",
    label = "Previous tool",
    group = "controls",
  },
  {
    action = "next_tool",
    lhs = "]a",
    method = "next_tool",
    label = "Next tool",
    group = "controls",
  },
  {
    action = "shift_tool",
    lhs = "~",
    method = "shift_tool",
    label = "Shift tool",
    group = "controls",
  },
  {
    action = "palette",
    lhs = "?",
    method = "toggle_palette",
    label = "Key palette",
    group = "controls",
  },
  {
    action = "options_palette",
    lhs = "o",
    method = "show_options_palette",
    label = "Options",
    group = "controls",
  },
  {
    action = "keyboard_point",
    lhs = "<CR>",
    method = "keyboard_point",
    label = "Set point",
    group = "controls",
  },
  {
    action = "finish",
    lhs = false,
    method = "finish",
    label = "Finish",
    group = "controls",
  },
  {
    action = "toggle_first_arrow",
    lhs = "<",
    method = "toggle_first_arrow",
    label = "First arrow",
    group = "controls",
  },
  {
    action = "toggle_second_arrow",
    lhs = ">",
    method = "toggle_second_arrow",
    label = "Second arrow",
    group = "controls",
  },
  {
    action = "cancel",
    lhs = "<Esc>",
    method = "escape",
    label = "Cancel / exit",
    group = "controls",
  },
  {
    action = "cancel_ctrl",
    lhs = "<C-c>",
    method = "cancel",
    label = "Cancel",
    group = "controls",
  },
  {
    action = "undo",
    lhs = "u",
    method = "keyboard_undo",
    label = "Undo vertex / drawing",
    group = "controls",
  },
  {
    action = "backspace",
    lhs = "<BS>",
    method = "keyboard_backspace",
    label = "Previous vertex / left",
    group = "controls",
  },
  {
    action = "disable",
    lhs = "<C-c><C-c>",
    method = "disable",
    label = "Exit Artist",
    group = "controls",
  },
}

local mouse_mapping_definitions = {
  { "<LeftMouse>", "mouse_down" },
  { "<2-LeftMouse>", "mouse_double_click" },
  { "<LeftDrag>", "mouse_drag" },
  { "<LeftRelease>", "mouse_up" },
  { "<S-LeftMouse>", "shift_mouse_down" },
  { "<2-S-LeftMouse>", "mouse_double_click" },
  { "<S-LeftDrag>", "mouse_drag" },
  { "<S-LeftRelease>", "mouse_up" },
  { "<MiddleMouse>", "pick_operation" },
  { "<S-MiddleMouse>", "pick_operation" },
  { "<RightMouse>", "pick_operation" },
  { "<S-RightMouse>", "pick_operation" },
}

local movement_mappings = {
  { "h", "h" },
  { "j", "j" },
  { "k", "k" },
  { "l", "l" },
  { "<Left>", "h" },
  { "<Down>", "j" },
  { "<Up>", "k" },
  { "<Right>", "l" },
  { "<C-b>", "h" },
  { "<C-n>", "j" },
  { "<C-p>", "k" },
  { "<C-f>", "l" },
}

---Resolve a buffer number, defaulting nil or 0 to the current buffer.
---@param bufnr? integer
---@return integer
local function resolve_buffer(bufnr)
  if bufnr == nil or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

---Returns the Artist.Session for a given buffer.
---@param bufnr? integer
---@return Artist.Session? state
---@return integer bufnr
local function session_for(bufnr)
  bufnr = resolve_buffer(bufnr)
  return sessions[bufnr], bufnr
end

---Retrieve an operation from its name.
---@param name string
---@return Artist.OperationDefinition
local function operation_definition(name)
  return assert(registry.get(name), "artist: unknown operation " .. name)
end

---Clear the rendered preview from a buffer without modifying its contents.
---@param bufnr integer
local function clear_preview(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
  end
end

---Get the position of the cursor
---@return Artist.Position
local function position_at_cursor()
  local cursor = vim.api.nvim_win_get_cursor(0)
  return { row = cursor[1], col = vim.fn.virtcol(".") }
end

---Get the position of the mouse in a buffer.
---@param bufnr integer
---@return Artist.Position?
local function mouse_position(bufnr)
  local value = vim.fn.getmousepos()
  if value.winid == 0 or value.line < 1 or value.column < 1 or vim.api.nvim_win_get_buf(value.winid) ~= bufnr then
    return nil
  end
  local coladd = (value --[[@as table]]).coladd or 0
  vim.api.nvim_set_current_win(value.winid)
  pcall(vim.fn.cursor, { value.line, value.column, coladd })
  local row = value.line
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if row == line_count then
    local screen = vim.fn.screenpos(value.winid, line_count, 1)
    if screen.row > 0 and value.screenrow > screen.row then
      row = row + value.screenrow - screen.row
    end
  end
  local line = vim.api.nvim_buf_get_lines(bufnr, value.line - 1, value.line, false)[1] or ""
  local prefix = line:sub(1, math.max(0, value.column - 1))
  return { row = row, col = vim.fn.strdisplaywidth(prefix) + 1 + coladd }
end

---@param state Artist.Session
---@param operation string
---@return Artist.Options
local function effective_options(state, operation)
  local options = vim.deepcopy(state.options)
  options.first_arrow = state.first_arrow
  options.second_arrow = state.second_arrow
  if state.legacy_freehand and operation == "pen_line" and options.line_character == nil then
    options.line_character = options.pen_character
  end
  local winid = vim.fn.bufwinid(state.bufnr)
  options.window_width = winid ~= -1 and vim.api.nvim_win_get_width(winid) - 2 or vim.o.columns
  options.tabstop = vim.bo[state.bufnr].tabstop
  return options
end

---@param state Artist.Session
---@return Artist.Patch
local function new_transaction(state)
  return patch.new(grid.from_buffer(state.bufnr), { trim_line_endings = state.options.trim_line_endings })
end

---@param state Artist.Session
---@param transaction Artist.Patch
---@param operation string
---@param from Artist.PositionLike
---@param to? Artist.PositionLike
---@param extra? Artist.Options
---@return Artist.Point[]|integer|nil
local function execute(state, transaction, operation, from, to, extra)
  local options = effective_options(state, operation)
  if extra then
    options = vim.tbl_extend("force", options, extra)
  end
  return operations.execute(transaction, operation, from, to, options)
end

---@param state Artist.Session
---@param current? Artist.Position
---@param operation? string
---@return Artist.Patch
local function build_poly_transaction(state, current, operation)
  local transaction = new_transaction(state)
  local points = state.poly_points or {}
  operation = operation or state.poly_operation or state.tool
  for index = 2, #points do
    execute(state, transaction, operation, points[index - 1], points[index], {
      first_arrow = index == 2 and state.first_arrow or false,
      second_arrow = current == nil and index == #points and state.second_arrow or false,
    })
  end
  if current and #points > 0 then
    execute(state, transaction, operation, points[#points], current, {
      first_arrow = #points == 1 and state.first_arrow or false,
      second_arrow = state.second_arrow,
    })
  end
  return transaction
end

---@param left Artist.Position
---@param right Artist.Position
---@return boolean
local function same_position(left, right)
  return left.row == right.row and left.col == right.col
end

---@param state Artist.Session
---@param transaction? Artist.Patch
local function preview_transaction(state, transaction)
  clear_preview(state.bufnr)
  if not transaction or transaction:is_empty() then
    return
  end
  local by_row = {}
  for _, change in ipairs(transaction.changes) do
    if change.before ~= change.char then
      by_row[change.row] = by_row[change.row] or {}
      by_row[change.row][change.col] = change.char
    end
  end
  local line_count = vim.api.nvim_buf_line_count(state.bufnr)
  local virtual_rows = {}
  local virtual_last = line_count
  for row, replacements in pairs(by_row) do
    if row <= line_count then
      local first, last
      for col in pairs(replacements) do
        first, last = math.min(first or col, col), math.max(last or col, col)
      end
      local rendered = {}
      for col = first, last do
        rendered[#rendered + 1] = replacements[col] or transaction.grid:get(row, col)
      end
      local winid = vim.fn.bufwinid(state.bufnr)
      local text = vim.api.nvim_buf_get_lines(state.bufnr, row - 1, row, false)[1] or ""
      local text_width = vim.fn.strdisplaywidth(text)
      local byte_col = 0
      local padding = 0
      local window_col
      if first > text_width then
        byte_col = #text
        if winid ~= -1 then
          local leftcol = vim.api.nvim_win_call(winid, function()
            return vim.fn.winsaveview().leftcol
          end)
          window_col = first - leftcol - 1
        end
        if not window_col or window_col < 0 then
          window_col = nil
          padding = first - text_width - 1
        end
      elseif winid ~= -1 and vim.fn.exists("*virtcol2col") == 1 then
        byte_col = math.max(0, vim.fn.virtcol2col(winid, row, first) - 1)
        local columns = vim.fn.virtcol({ row, byte_col + 1 }, true)
        local anchor_col = type(columns) == "table" and columns[1] or columns
        padding = math.max(0, first - anchor_col)
      else
        byte_col = math.min(#text, first - 1)
      end
      local virt_text = {}
      if padding > 0 then
        virt_text[#virt_text + 1] = { string.rep(" ", padding), "" }
      end
      virt_text[#virt_text + 1] = { table.concat(rendered), "ArtistPreview" }
      local extmark = {
        virt_text = virt_text,
        hl_mode = "replace",
        priority = 200,
      }
      if window_col then
        extmark.virt_text_win_col = window_col
      else
        extmark.virt_text_pos = "overlay"
      end
      vim.api.nvim_buf_set_extmark(state.bufnr, namespace, row - 1, byte_col, extmark)
    else
      virtual_rows[row] = replacements
      virtual_last = math.max(virtual_last, row)
    end
  end
  if virtual_last > line_count then
    local lines = {}
    for row = line_count + 1, virtual_last do
      local replacements = virtual_rows[row] or {}
      local last = 0
      for col in pairs(replacements) do
        last = math.max(last, col)
      end
      local characters = {}
      for col = 1, last do
        characters[col] = replacements[col] or " "
      end
      lines[#lines + 1] = { { table.concat(characters), "ArtistPreview" } }
    end
    vim.api.nvim_buf_set_extmark(state.bufnr, namespace, line_count - 1, 0, {
      virt_lines = lines,
      virt_lines_above = false,
      priority = 200,
    })
  end
end

---@param state Artist.Session
---@param transaction Artist.Patch
---@param from Artist.Position
---@param to Artist.Position
---@param kind Artist.OperationKind
local function preview_operation(state, transaction, from, to, kind)
  if state.options.rubber_banding == false and (kind == "two_point" or kind == "poly_point") then
    local markers = new_transaction(state)
    markers:set(from.row, from.col, state.options.first_character or "1")
    markers:set(to.row, to.col, state.options.second_character or "2")
    preview_transaction(state, markers)
  else
    preview_transaction(state, transaction)
  end
end

---@param state Artist.Session
local function stop_timer(state)
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end
end

---@param state Artist.Session
---@param transaction? Artist.Patch
local function commit(state, transaction)
  stop_timer(state)
  clear_preview(state.bufnr)
  if transaction then
    transaction:commit(state.bufnr)
  end
end

---@param value string
---@param from string
---@param to string
---@return string
local function with_highlight_override(value, from, to)
  local result = {}
  for mapping in value:gmatch("[^,]+") do
    if not vim.startswith(mapping, from .. ":") then
      result[#result + 1] = mapping
    end
  end
  result[#result + 1] = from .. ":" .. to
  return table.concat(result, ",")
end

---@param state Artist.Session
---@return string
local function toolbar_text(state)
  local drawing = state.drag or state.anchor or state.transaction
  local arrows = (state.first_arrow and " <" or "") .. (state.second_arrow and " >" or "")
  return table.concat({
    "%#ArtistMode# ARTIST %*",
    "%#ArtistTool# [" .. state.tool .. arrows .. "] %*",
    drawing and "%#ArtistHint# drawing… %*" or "",
    "%=%#ArtistHint# <CR> point/finish  <BS> vertex  <Esc> cancel %*",
  })
end

---@param state Artist.Session
---@param winid integer
local function configure_window(state, winid)
  if state.active_windows[winid] then
    return
  end
  if state.previous.virtualedit[winid] == nil then
    state.previous.virtualedit[winid] = vim.wo[winid].virtualedit
    state.previous.wrap[winid] = vim.wo[winid].wrap
    state.previous.statusline[winid] = vim.wo[winid].statusline
    state.previous.winhighlight[winid] = vim.wo[winid].winhighlight
  end
  state.active_windows[winid] = true
  vim.wo[winid].virtualedit = "all"
  vim.wo[winid].wrap = false
  if state.options.statusline then
    vim.wo[winid].statusline = toolbar_text(state)
  end
  if state.options.transparent_selection then
    vim.wo[winid].winhighlight = with_highlight_override(vim.wo[winid].winhighlight, "Visual", "ArtistVisual")
  end
end

---@param state Artist.Session
---@param winid integer
local function restore_window(state, winid)
  if not state.active_windows[winid] or not vim.api.nvim_win_is_valid(winid) then
    return
  end
  vim.wo[winid].virtualedit = state.previous.virtualedit[winid]
  vim.wo[winid].wrap = state.previous.wrap[winid]
  vim.wo[winid].statusline = state.previous.statusline[winid]
  vim.wo[winid].winhighlight = state.previous.winhighlight[winid]
  state.active_windows[winid] = nil
end

---@param state Artist.Session
local function update_toolbar(state)
  if state.options.statusline then
    for winid in pairs(state.active_windows) do
      if vim.api.nvim_win_is_valid(winid) then
        vim.wo[winid].statusline = toolbar_text(state)
      end
    end
  end
end

local option_actions = {
  e = { "select_character", "erase_character" },
  f = { "select_character", "fill_character" },
  l = { "select_character", "line_character" },
  r = { "toggle_setting", "rubber_banding" },
  t = { "toggle_setting", "trim_line_endings" },
  s = { "toggle_setting", "borderless_shapes" },
}

---@param state Artist.Session
local function close_palette(state)
  if state.palette_win and vim.api.nvim_win_is_valid(state.palette_win) then
    pcall(vim.api.nvim_win_close, state.palette_win, true)
  end
  state.palette_win, state.palette_buf, state.palette_kind = nil, nil, nil
end

---@param state Artist.Session
---@param kind 'main'|'options'
local function show_palette(state, kind)
  close_palette(state)
  local owner = vim.fn.bufwinid(state.bufnr)
  -- A palette belongs to the visible, current session only.  This avoids a
  -- background enable unexpectedly putting a float over another buffer.
  if owner == -1 or owner ~= vim.api.nvim_get_current_win() then
    return
  end
  local lines = {}
  if kind == "options" then
    lines = {
      " Artist options (Esc exits)",
      " e erase character   f fill character   l line character",
      " r rubber banding     t trim whitespace   s borderless shapes",
    }
  else
    lines = { " Artist keys (? closes)" }
    local row = {}
    local item_width, item_spacing = 21, 2
    local available_width = math.max(1, vim.o.columns - 2)
    local column_count =
      math.max(1, math.min(4, math.floor((available_width - 1 + item_spacing) / (item_width + item_spacing))))
    for _, item in ipairs(key_spec) do
      if item.group == "tools" then
        row[#row + 1] = string.format("%-2s %-18s", item.lhs, item.label)
        if #row == column_count then
          lines[#lines + 1] = " " .. table.concat(row, "  ")
          row = {}
        end
      end
    end
    if #row > 0 then
      lines[#lines + 1] = " " .. table.concat(row, "  ")
    end
    lines[#lines + 1] = " [a/]a previous/next   ~ shifted   o options   <Esc> exit   <C-c> cancel"
  end
  local width = 1
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  local height = #lines
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    anchor = "SW",
    row = vim.o.lines - 2,
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    width = math.min(width, math.max(20, vim.o.columns - 2)),
    height = height,
    style = "minimal",
    focusable = false,
    zindex = 200,
    border = "rounded",
    noautocmd = true,
  })
  vim.wo[win].winblend = 0
  vim.api.nvim_buf_set_extmark(buf, palette_namespace, 0, 0, { end_row = 0, hl_group = "ArtistMode", hl_eol = true })
  if kind == "main" then
    local active_label = state.tool
    for _, item in ipairs(key_spec) do
      if item.arg == state.tool then
        active_label = item.label
        break
      end
    end
    for line_no, line in ipairs(lines) do
      local start = line:find(active_label, 1, true)
      if start then
        vim.api.nvim_buf_set_extmark(buf, palette_namespace, line_no - 1, start - 1, {
          end_row = line_no - 1,
          hl_group = "ArtistTool",
          hl_eol = true,
        })
      end
    end
  end
  state.palette_win, state.palette_buf, state.palette_kind = win, buf, kind
end

---@param state Artist.Session
local function refresh_palette(state)
  if state.palette_kind == "main" then
    show_palette(state, "main")
  end
end

---@param state Artist.Session
---@return table[]
local function all_mapping_definitions(state)
  local result = {}
  for _, item in ipairs(key_spec) do
    local lhs = state.options.keymaps[item.action]
    if lhs == nil then
      lhs = item.lhs
    end
    if lhs ~= false then
      result[#result + 1] = { lhs, item.method, item.arg, item.action }
    end
  end
  vim.list_extend(result, vim.deepcopy(mouse_mapping_definitions))
  for _, value in ipairs(movement_mappings) do
    result[#result + 1] = value
  end
  if state.options.mouse_wheel then
    result[#result + 1] = { "<ScrollWheelUp>", "previous_tool" }
    result[#result + 1] = { "<ScrollWheelDown>", "next_tool" }
  end
  return result
end

---@param lhs string
---@return table?
local function save_mapping(lhs)
  local value = vim.fn.maparg(lhs, "n", false, true)
  if type(value) == "table" and value.buffer == 1 and next(value) ~= nil then
    return value
  end
end

local function mapping_disabled_by_global()
  return vim.g.no_plugin_maps == true
    or vim.g.no_plugin_maps == 1
    or vim.g.artist_no_mappings == true
    or vim.g.artist_no_mappings == 1
end

---@param state Artist.Session
---@return boolean
local function concrete_mappings_enabled(state)
  return state.options.mappings ~= false and not mapping_disabled_by_global()
end

---@param bufnr integer
---@param state Artist.Session
local function install_mappings(bufnr, state)
  if not concrete_mappings_enabled(state) then
    return
  end
  state.saved_mappings = {}
  state.mapping_definitions = all_mapping_definitions(state)
  vim.api.nvim_buf_call(bufnr, function()
    for _, definition in ipairs(state.mapping_definitions) do
      local lhs, method = definition[1], definition[2]
      state.saved_mappings[lhs] = save_mapping(lhs)
      if #definition == 2 and (method == "h" or method == "j" or method == "k" or method == "l") then
        vim.keymap.set("n", lhs, function()
          if state.palette_kind == "options" and option_actions[lhs] then
            local action = option_actions[lhs]
            close_palette(state)
            M[action[1]](action[2], bufnr)
            return
          end
          close_palette(state)
          M.keyboard_move(method, bufnr)
        end, { buffer = bufnr, silent = true, nowait = true, desc = "Artist: move and draw" })
      elseif method == "select_tool" then
        vim.keymap.set("n", lhs, function()
          if state.palette_kind == "options" and option_actions[lhs] then
            local action = option_actions[lhs]
            close_palette(state)
            M[action[1]](action[2], bufnr)
            return
          end
          close_palette(state)
          M.set_tool(definition[3], bufnr)
        end, { buffer = bufnr, silent = true, nowait = true, desc = "Artist: select " .. definition[3] })
      elseif method == "select_character" or method == "toggle_setting" then
        vim.keymap.set("n", lhs, function()
          M[method](definition[3], bufnr)
        end, { buffer = bufnr, silent = true, nowait = true, desc = "Artist: configure " .. definition[3] })
      else
        vim.keymap.set("n", lhs, function()
          if state.palette_kind == "options" then
            if option_actions[lhs] then
              local action = option_actions[lhs]
              close_palette(state)
              M[action[1]](action[2], bufnr)
              return
            end
          end
          if method == "toggle_palette" then
            if state.palette_kind then
              close_palette(state)
            else
              show_palette(state, "main")
            end
            return
          elseif method == "show_options_palette" then
            show_palette(state, "options")
            return
          end
          close_palette(state)
          M[method](bufnr)
        end, {
          buffer = bufnr,
          silent = true,
          nowait = lhs ~= "<C-c>",
          desc = "Artist: " .. method:gsub("_", " "),
        })
      end
    end
  end)
end

---@param bufnr integer
---@param state Artist.Session
local function remove_mappings(bufnr, state)
  if not state.mapping_definitions then
    return
  end
  vim.api.nvim_buf_call(bufnr, function()
    for _, definition in ipairs(state.mapping_definitions or {}) do
      local lhs = definition[1]
      pcall(vim.keymap.del, "n", lhs, { buffer = bufnr })
      if state.saved_mappings[lhs] then
        pcall(vim.fn.mapset, "n", false, state.saved_mappings[lhs])
      end
    end
  end)
end

---@param options Artist.Options
local function validate_options(options)
  if options.aspect_ratio ~= nil and (type(options.aspect_ratio) ~= "number" or options.aspect_ratio <= 0) then
    error("artist: aspect_ratio must be a positive number")
  end
  for _, name in ipairs({ "line_character", "fill_character", "erase_character" }) do
    if options[name] ~= nil and vim.fn.strchars(options[name]) ~= 1 then
      error("artist: " .. name .. " must be one character or nil")
    end
  end
  if options.keymaps ~= nil and type(options.keymaps) ~= "table" then
    error("artist: keymaps must be a table")
  end
  if options.show_palette_on_enable ~= nil and type(options.show_palette_on_enable) ~= "boolean" then
    error("artist: show_palette_on_enable must be a boolean")
  end
end

---Configure defaults for future Artist sessions and direct draw calls.
---@param options? Artist.Options
function M.setup(options)
  vim.validate({ options = { options, "table", true } })
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), options or {})
  local resolved = registry.resolve(config.tool)
  if not resolved then
    error("artist: unknown operation " .. tostring(config.tool))
  end
  config.tool = resolved
  validate_options(config)
  M._install_global_mappings()
end

---Enable Artist mode in a buffer.
---@param bufnr? integer Defaults to the current buffer.
---@param options? Artist.Options Session-local option overrides.
function M.enable(bufnr, options)
  bufnr = resolve_buffer(bufnr)
  vim.validate({ options = { options, "table", true } })
  if not vim.api.nvim_buf_is_valid(bufnr) then
    error("artist: invalid buffer " .. tostring(bufnr))
  elseif not vim.bo[bufnr].modifiable then
    error("artist: buffer is not modifiable")
  elseif sessions[bufnr] then
    return
  end
  local effective = vim.tbl_deep_extend("force", vim.deepcopy(config), options or {})
  local requested_tool = effective.tool
  effective.tool = registry.resolve(requested_tool)
  if not effective.tool then
    error("artist: unknown operation " .. tostring(requested_tool))
  end
  validate_options(effective)
  local state = {
    bufnr = bufnr,
    tool = effective.tool,
    legacy_freehand = requested_tool == "freehand",
    options = effective,
    first_arrow = effective.first_arrow,
    second_arrow = effective.second_arrow,
    active_windows = {},
    previous = { virtualedit = {}, wrap = {}, statusline = {}, winhighlight = {} },
  }
  sessions[bufnr] = state
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(winid) == bufnr then
      configure_window(state, winid)
    end
  end
  original_mouse = original_mouse or vim.o.mouse
  if not vim.o.mouse:find("a", 1, true) then
    vim.o.mouse = "a"
  end
  install_mappings(bufnr, state)
  vim.b[bufnr].artist_enabled = true
  vim.b[bufnr].artist_tool = state.tool
  vim.api.nvim_exec_autocmds("User", { pattern = "ArtistEnabled", modeline = false, data = { buf = bufnr } })
  if state.options.show_palette_on_enable then
    show_palette(state, "main")
  end
end

---Disable Artist mode in a buffer.
---@param bufnr? integer Defaults to the current buffer.
function M.disable(bufnr)
  local state
  state, bufnr = session_for(bufnr)
  if not state then
    return
  end
  M.cancel(bufnr)
  close_palette(state)
  if vim.api.nvim_buf_is_valid(bufnr) then
    remove_mappings(bufnr, state)
    vim.b[bufnr].artist_enabled = false
    vim.b[bufnr].artist_tool = nil
  end
  for _, winid in ipairs(vim.tbl_keys(state.active_windows)) do
    restore_window(state, winid)
  end
  sessions[bufnr] = nil
  if next(sessions) == nil then
    vim.o.mouse = original_mouse
    original_mouse = nil
  end
  vim.api.nvim_exec_autocmds("User", { pattern = "ArtistDisabled", modeline = false, data = { buf = bufnr } })
end

---Toggle Artist mode in a buffer.
---@param bufnr? integer Defaults to the current buffer.
---@param options? Artist.Options Session-local option overrides when enabling.
function M.toggle(bufnr, options)
  bufnr = resolve_buffer(bufnr)
  if sessions[bufnr] then
    M.disable(bufnr)
  else
    M.enable(bufnr, options)
  end
end

---@param bufnr? integer
---@return boolean
function M.is_enabled(bufnr)
  return session_for(bufnr) ~= nil
end

---@param bufnr? integer
---@return string?
function M.get_tool(bufnr)
  local state = session_for(bufnr)
  return state and state.tool or nil
end

---@param name string
---@param bufnr? integer
function M.set_tool(name, bufnr)
  local resolved = registry.resolve(name)
  if not resolved then
    error("artist: unknown operation " .. tostring(name))
  end
  local state
  state, bufnr = session_for(bufnr)
  if not state then
    error("artist: Artist mode is not enabled in this buffer")
  end
  M.cancel(bufnr)
  state.tool = resolved
  state.legacy_freehand = name == "freehand"
  vim.b[bufnr].artist_tool = resolved
  update_toolbar(state)
  refresh_palette(state)
  vim.api.nvim_exec_autocmds("User", {
    pattern = "ArtistToolChanged",
    modeline = false,
    data = { buf = bufnr, tool = resolved },
  })
end

---@param bufnr? integer
function M.shift_tool(bufnr)
  local state = session_for(bufnr)
  if state then
    M.set_tool(assert(registry.shifted(state.tool)), bufnr)
  end
end

---@param delta integer
---@param bufnr? integer
local function cycle_tool(delta, bufnr)
  local state = session_for(bufnr)
  if not state then
    return
  end
  local names, index = {}, 1
  for _, item in ipairs(key_spec) do
    if item.group == "tools" then
      names[#names + 1] = item.arg
    end
  end
  for candidate, name in ipairs(names) do
    if name == state.tool then
      index = candidate
      break
    end
  end
  M.set_tool(names[(index - 1 + delta) % #names + 1], bufnr)
end

---@param bufnr? integer
function M.next_tool(bufnr)
  cycle_tool(vim.v.count1, bufnr)
end

---@param bufnr? integer
function M.previous_tool(bufnr)
  cycle_tool(-vim.v.count1, bufnr)
end

---@param bufnr? integer
function M.toggle_palette(bufnr)
  local state = session_for(bufnr)
  if not state then
    return
  end
  if state.palette_kind then
    close_palette(state)
  else
    show_palette(state, "main")
  end
end

---@param bufnr? integer
function M.show_options_palette(bufnr)
  local state = session_for(bufnr)
  if state then
    show_palette(state, "options")
  end
end

---@param which 'first'|'second'
---@param bufnr? integer
function M.toggle_arrow(which, bufnr)
  local state = session_for(bufnr)
  if not state then
    return
  end
  if which == "first" then
    state.first_arrow = not state.first_arrow
  elseif which == "second" then
    state.second_arrow = not state.second_arrow
  else
    error("artist: arrow must be 'first' or 'second'")
  end
  update_toolbar(state)
end

---@param name string
---@param value any
---@param bufnr? integer
function M.set_option(name, value, bufnr)
  local state = session_for(bufnr)
  if not state then
    error("artist: Artist mode is not enabled in this buffer")
  end
  local nil_settings = { line_character = true, fill_character = true, text_renderer = true }
  if defaults[name] == nil and not nil_settings[name] then
    error("artist: unknown setting " .. tostring(name))
  end
  local candidate = vim.deepcopy(state.options)
  candidate[name] = value
  validate_options(candidate)
  state.options = candidate
  update_toolbar(state)
end

---@param name 'line_character'|'fill_character'|'erase_character'
---@param bufnr? integer
function M.select_character(name, bufnr)
  local prompt = "Artist " .. name:gsub("_", " ") .. " (empty resets): "
  ---@type string?
  local value = vim.fn.input(prompt)
  if value == "" then
    value = name == "erase_character" and " " or nil
  end
  M.set_option(name, value, bufnr)
end

---@param name string
---@param bufnr? integer
function M.toggle_setting(name, bufnr)
  local state = session_for(bufnr)
  if state then
    M.set_option(name, not state.options[name], bufnr)
  end
end

---@param bufnr? integer
function M.toggle_first_arrow(bufnr)
  M.toggle_arrow("first", bufnr)
end

---@param bufnr? integer
function M.toggle_second_arrow(bufnr)
  M.toggle_arrow("second", bufnr)
end

---Execute an operation directly. Display-cell positions are one-based.
---@param name string
---@param from Artist.PositionLike
---@param to? Artist.PositionLike
---@param options? Artist.Options
---@return Artist.Change[]
function M.draw(name, from, to, options)
  options = options or {}
  local resolved = registry.resolve(name)
  if not resolved then
    error("artist: unknown operation " .. tostring(name))
  end
  local bufnr = resolve_buffer(options.bufnr)
  local effective = vim.tbl_deep_extend("force", vim.deepcopy(config), options)
  effective.tabstop = vim.bo[bufnr].tabstop
  if name == "freehand" and effective.line_character == nil then
    effective.line_character = effective.pen_character
  end
  validate_options(effective)
  local transaction = patch.new(grid.from_buffer(bufnr), { trim_line_endings = effective.trim_line_endings })
  operations.execute(transaction, resolved, from, to or from, effective)
  transaction:commit(bufnr)
  return transaction.changes
end

---@param bufnr? integer
---@param shifted? boolean
function M.mouse_down(bufnr, shifted)
  local state
  state, bufnr = session_for(bufnr)
  if not state then
    return
  end
  local position = mouse_position(bufnr)
  if not position then
    return
  end
  state.keyboard_position = nil
  local operation = state.tool
  if shifted then
    operation = assert(registry.shifted(state.tool))
  end
  local definition = operation_definition(operation)
  if definition.kind == "one_point" then
    local transaction = new_transaction(state)
    ---@type Artist.Options?
    local extra
    if operation == "text_see_through" or operation == "text_overwrite" then
      extra = { text = vim.fn.input("Artist text: ") }
    end
    execute(state, transaction, operation, position, position, extra)
    commit(state, transaction)
    return
  end
  if definition.kind == "poly_point" and not state.anchor then
    state.anchor = position
    state.poly_points = { position }
    state.poly_operation = operation
  end
  local transaction = definition.kind == "poly_point" and build_poly_transaction(state, nil, operation)
    or new_transaction(state)
  local start = position
  if definition.kind == "poly_point" then
    start = assert(state.anchor)
  end
  state.drag = { operation = operation, start = start, current = position, transaction = transaction }
  if definition.kind == "continuous" then
    execute(state, transaction, operation, position, position)
  else
    execute(state, transaction, operation, start, position)
  end
  preview_operation(state, transaction, start, position, definition.kind)
  update_toolbar(state)
  if operation == "spray" and (state.options.timer_factory or vim.uv) then
    local timer = state.options.timer_factory and state.options.timer_factory() or assert(vim.uv.new_timer())
    state.timer = timer
    timer:start(
      math.floor(state.options.spray_interval * 1000),
      math.floor(state.options.spray_interval * 1000),
      vim.schedule_wrap(function()
        if sessions[bufnr] == state and state.drag then
          execute(state, state.drag.transaction, "spray", state.drag.current, state.drag.current)
          preview_transaction(state, state.drag.transaction)
        end
      end)
    )
  end
end

---@param bufnr? integer
function M.shift_mouse_down(bufnr)
  M.mouse_down(bufnr, true)
end

---@param bufnr? integer
function M.mouse_drag(bufnr)
  local state = session_for(bufnr)
  if not state or not state.drag then
    return
  end
  local drag = assert(state.drag)
  local position = mouse_position(state.bufnr)
  if not position then
    return
  end
  local definition = operation_definition(drag.operation)
  if definition.kind == "continuous" then
    execute(state, drag.transaction, drag.operation, drag.current, position)
  elseif definition.kind == "poly_point" then
    drag.transaction = build_poly_transaction(state, position, drag.operation)
  else
    drag.transaction = new_transaction(state)
    execute(state, drag.transaction, drag.operation, drag.start, position)
  end
  drag.current = position
  preview_operation(state, drag.transaction, drag.start, position, definition.kind)
end

---@param bufnr? integer
function M.mouse_up(bufnr)
  local state = session_for(bufnr)
  if not state or not state.drag then
    return
  end
  stop_timer(state)
  local drag = assert(state.drag)
  local definition = operation_definition(drag.operation)
  local position = mouse_position(state.bufnr) or drag.current
  if definition.kind == "continuous" then
    execute(state, drag.transaction, drag.operation, drag.current, position)
  elseif definition.kind == "poly_point" then
    drag.transaction = build_poly_transaction(state, position, drag.operation)
  elseif drag.current.row ~= position.row or drag.current.col ~= position.col then
    drag.transaction = new_transaction(state)
    execute(state, drag.transaction, drag.operation, drag.start, position)
  end
  state.drag = nil
  if definition.kind == "poly_point" then
    local poly_points = assert(state.poly_points)
    if not same_position(poly_points[#poly_points], position) then
      poly_points[#poly_points + 1] = position
    end
    local transaction = build_poly_transaction(state, nil, drag.operation)
    state.anchor, state.transaction = position, transaction
    preview_operation(state, transaction, assert(poly_points[1]), position, definition.kind)
  elseif drag.operation == "spray_radius" then
    state.options.spray_radius = math.max(
      1,
      math.floor(math.sqrt((position.col - drag.start.col) ^ 2 + (position.row - drag.start.row) ^ 2) + 0.5)
    )
    clear_preview(state.bufnr)
  else
    commit(state, drag.transaction)
  end
  update_toolbar(state)
end

---Finish an active mouse polyline at the double-clicked point.
---@param bufnr? integer
function M.mouse_double_click(bufnr)
  local state
  state, bufnr = session_for(bufnr)
  if not state or not state.anchor or not state.poly_points then
    return
  end
  local position = mouse_position(bufnr)
  if not position then
    return
  end
  local points = assert(state.poly_points)
  if not same_position(assert(points[#points]), position) then
    points[#points + 1] = position
    state.anchor = position
    state.transaction = build_poly_transaction(state)
  end
  if #points >= 2 then
    M.finish(bufnr)
  end
end

---@param state Artist.Session
---@param position Artist.Position
local function set_keyboard_position(state, position)
  state.keyboard_position = { row = position.row, col = position.col }
  local visible_row = math.min(position.row, vim.api.nvim_buf_line_count(state.bufnr))
  local winid = vim.fn.bufwinid(state.bufnr)
  if winid == -1 then
    return
  end
  local byte_col = vim.fn.exists("*virtcol2col") == 1 and vim.fn.virtcol2col(winid, visible_row, position.col)
    or position.col
  local line = vim.api.nvim_buf_get_lines(state.bufnr, visible_row - 1, visible_row, false)[1] or ""
  local existing_width = vim.fn.strdisplaywidth(line)
  pcall(vim.api.nvim_win_set_cursor, winid, { visible_row, math.max(0, math.min(#line, byte_col - 1)) })
  if position.col > existing_width + 1 then
    pcall(vim.fn.cursor, { visible_row, #line + 1, position.col - existing_width - 1 })
  end
end

---@param bufnr? integer
function M.keyboard_point(bufnr)
  local state = session_for(bufnr)
  if not state then
    return
  end
  local position = state.keyboard_position or position_at_cursor()
  local definition = operation_definition(state.tool)
  if definition.kind == "continuous" then
    if state.continuous_active then
      commit(state, state.transaction)
      state.continuous_active, state.transaction, state.anchor = nil, nil, nil
    else
      state.continuous_active = true
      state.transaction = new_transaction(state)
      state.anchor = position
    end
  elseif definition.kind == "one_point" then
    local transaction = new_transaction(state)
    ---@type Artist.Options?
    local extra
    if state.tool == "text_see_through" or state.tool == "text_overwrite" then
      extra = { text = vim.fn.input("Artist text: ") }
    end
    execute(state, transaction, state.tool, position, position, extra)
    commit(state, transaction)
  elseif definition.kind == "poly_point" then
    if not state.anchor then
      state.anchor, state.poly_points = position, { position }
      state.poly_operation = state.tool
      state.transaction = new_transaction(state)
    else
      local poly_points = assert(state.poly_points)
      if same_position(poly_points[#poly_points], position) then
        if #poly_points >= 2 then
          M.finish(bufnr)
        end
        update_toolbar(state)
        return
      end
      poly_points[#poly_points + 1] = position
      state.anchor = position
      state.transaction = build_poly_transaction(state)
      state.preview_transaction = nil
    end
    preview_operation(
      state,
      assert(state.transaction),
      assert(state.poly_points and state.poly_points[1]),
      position,
      definition.kind
    )
  elseif not state.anchor then
    state.anchor = position
    local transaction = new_transaction(state)
    execute(state, transaction, state.tool, position, position)
    preview_operation(state, transaction, state.anchor, position, definition.kind)
  else
    local transaction = new_transaction(state)
    execute(state, transaction, state.tool, state.anchor, position)
    state.anchor = nil
    commit(state, transaction)
  end
  update_toolbar(state)
end

---@param motion 'h'|'j'|'k'|'l'
---@param bufnr? integer
function M.keyboard_move(motion, bufnr)
  local state = session_for(bufnr)
  if not state then
    return
  end
  local before = state.keyboard_position or position_at_cursor()
  local count = vim.v.count1
  local after = { row = before.row, col = before.col }
  if motion == "h" then
    after.col = math.max(1, after.col - count)
  elseif motion == "l" then
    after.col = after.col + count
  elseif motion == "j" then
    after.row = after.row + count
  elseif motion == "k" then
    after.row = math.max(1, after.row - count)
  end
  set_keyboard_position(state, after)
  local definition = operation_definition(state.tool)
  if definition.kind == "continuous" and state.continuous_active then
    local transaction = assert(state.transaction)
    execute(state, transaction, state.tool, before, after)
    preview_transaction(state, transaction)
    state.anchor = after
  elseif state.anchor and (definition.kind == "two_point" or definition.kind == "poly_point") then
    local anchor = assert(state.anchor)
    local transaction
    if definition.kind == "poly_point" then
      transaction = build_poly_transaction(state, after)
    else
      transaction = new_transaction(state)
      execute(state, transaction, state.tool, anchor, after)
    end
    preview_operation(state, transaction, anchor, after, definition.kind)
    state.preview_transaction = transaction
  end
end

---@param bufnr? integer
function M.finish(bufnr)
  local state = session_for(bufnr)
  if not state then
    return
  end
  commit(state, state.preview_transaction or state.transaction)
  state.transaction, state.preview_transaction, state.anchor, state.drag, state.poly_points, state.poly_operation, state.continuous_active =
    nil, nil, nil, nil, nil, nil, nil
  update_toolbar(state)
end

---@param bufnr? integer
function M.cancel(bufnr)
  local state
  state, bufnr = session_for(bufnr)
  if not state then
    return
  end
  stop_timer(state)
  state.transaction, state.preview_transaction, state.anchor, state.drag, state.poly_points, state.poly_operation, state.continuous_active =
    nil, nil, nil, nil, nil, nil, nil
  clear_preview(bufnr)
  update_toolbar(state)
end

---@param state Artist.Session
---@return boolean
local function drawing_active(state)
  return state.drag ~= nil or state.anchor ~= nil or state.transaction ~= nil or state.continuous_active == true
end

---Cancel an active drawing, or leave Artist mode when idle.
---@param bufnr? integer
function M.escape(bufnr)
  local state
  state, bufnr = session_for(bufnr)
  if not state then
    return
  end
  if drawing_active(state) then
    M.cancel(bufnr)
  else
    M.disable(bufnr)
  end
end

---Remove the most recent polyline vertex, cancel another active preview, or
---fall back to normal Vim undo while Artist is idle.
---@param bufnr? integer
function M.keyboard_undo(bufnr)
  local state
  state, bufnr = session_for(bufnr)
  if not state then
    return
  end
  if state.anchor and state.poly_points then
    local points = assert(state.poly_points)
    if #points <= 1 then
      M.cancel(bufnr)
      return
    end
    table.remove(points)
    local anchor = assert(points[#points])
    state.anchor = anchor
    state.transaction = build_poly_transaction(state)
    state.preview_transaction = nil
    set_keyboard_position(state, anchor)
    preview_operation(state, state.transaction, assert(points[1]), anchor, "poly_point")
    update_toolbar(state)
  elseif drawing_active(state) then
    M.cancel(bufnr)
  else
    vim.cmd("normal! " .. vim.v.count1 .. "u")
  end
end

---Remove a polyline vertex, otherwise move left like normal-mode Backspace.
---@param bufnr? integer
function M.keyboard_backspace(bufnr)
  local state = session_for(bufnr)
  if not state then
    return
  end
  if state.anchor and state.poly_points then
    M.keyboard_undo(bufnr)
  else
    M.keyboard_move("h", bufnr)
  end
end

---@param bufnr? integer
function M.pick_operation(bufnr)
  local state = session_for(bufnr)
  if not state then
    return
  end
  local names = registry.names()
  vim.ui.select(names, {
    prompt = "Artist operation",
    format_item = function(name)
      return operation_definition(name).label
    end,
  }, function(choice)
    if choice then
      M.set_tool(choice, bufnr)
    end
  end)
end

---Install stable public mapping targets and the optional conservative default.
function M._install_global_mappings()
  local function target(name, callback, desc)
    vim.keymap.set("n", "<Plug>(artist-" .. name .. ")", callback, { silent = true, desc = desc })
  end
  target("toggle", function()
    M.toggle()
  end, "Artist: toggle")
  target("enable", function()
    M.enable()
  end, "Artist: enable")
  target("disable", function()
    M.disable()
  end, "Artist: disable")
  target("next-tool", function()
    M.next_tool()
  end, "Artist: next tool")
  target("previous-tool", function()
    M.previous_tool()
  end, "Artist: previous tool")
  target("shift-tool", function()
    M.shift_tool()
  end, "Artist: shifted tool")
  target("palette", function()
    M.toggle_palette()
  end, "Artist: key palette")
  target("options-palette", function()
    M.show_options_palette()
  end, "Artist: options palette")
  target("finish", function()
    M.finish()
  end, "Artist: finish drawing")
  for _, item in ipairs(key_spec) do
    if item.method == "select_tool" then
      target("tool-" .. item.arg:gsub("_", "-"), function()
        M.set_tool(item.arg)
      end, "Artist: " .. item.label)
    end
  end
  for key, action in pairs(option_actions) do
    target("option-" .. ({
      e = "erase-character",
      f = "fill-character",
      l = "line-character",
      r = "rubber-banding",
      t = "trim-line-endings",
      s = "borderless-shapes",
    })[key], function()
      M[action[1]](action[2])
    end, "Artist: option")
  end
  local disabled = mapping_disabled_by_global() or config.mappings == false
  local existing = vim.fn.maparg("gA", "n", false, true)
  local ours = type(existing) == "table" and existing.rhs == "<Plug>(artist-toggle)"
  if disabled then
    if ours then
      pcall(vim.keymap.del, "n", "gA")
    end
  elseif type(existing) ~= "table" or next(existing) == nil then
    vim.keymap.set("n", "gA", "<Plug>(artist-toggle)", { remap = true, silent = true, desc = "Toggle Artist mode" })
  end
end

---Create Artist commands and lifecycle autocommands.
function M._create_commands()
  if augroup then
    return
  end
  local completion = function()
    return registry.names()
  end
  vim.api.nvim_create_user_command("Artist", function(command)
    local action = command.args ~= "" and command.args or "toggle"
    if action == "enable" then
      M.enable()
    elseif action == "disable" then
      M.disable()
    elseif action == "toggle" then
      M.toggle()
    else
      M.set_tool(action)
    end
  end, {
    nargs = "?",
    complete = function()
      return vim.list_extend({ "enable", "disable", "toggle" }, completion())
    end,
    desc = "Enable, disable, or configure Artist mode",
  })
  vim.api.nvim_create_user_command("ArtistTool", function(command)
    M.set_tool(command.args)
  end, { nargs = 1, complete = completion, desc = "Select the Artist operation" })
  vim.api.nvim_create_user_command("ArtistEnable", function()
    M.enable()
  end, { desc = "Enable Artist mode" })
  vim.api.nvim_create_user_command("ArtistDisable", function()
    M.disable()
  end, { desc = "Disable Artist mode" })
  vim.api.nvim_create_user_command("ArtistToggle", function()
    M.toggle()
  end, { desc = "Toggle Artist mode" })
  vim.api.nvim_create_user_command("ArtistShift", function()
    M.shift_tool()
  end, { desc = "Select the shifted Artist operation" })
  vim.api.nvim_create_user_command("ArtistPicker", function()
    M.pick_operation()
  end, { desc = "Open the Artist operation picker" })
  vim.api.nvim_create_user_command("ArtistPalette", function()
    M.toggle_palette()
  end, { desc = "Toggle the Artist key palette" })
  vim.api.nvim_create_user_command("ArtistArrow", function(command)
    M.toggle_arrow(command.args)
  end, {
    nargs = 1,
    complete = function()
      return { "first", "second" }
    end,
    desc = "Toggle an arrow endpoint",
  })
  vim.api.nvim_create_user_command("ArtistSet", function(command)
    local name, raw = command.args:match("^(%S+)%s*(.*)$")
    name = name and name:gsub("%-", "_")
    local value = raw
    if raw == "none" or raw == "default" then
      value = name == "erase_character" and " " or nil
    elseif raw == "true" then
      value = true
    elseif raw == "false" then
      value = false
    elseif tonumber(raw) then
      value = tonumber(raw)
    end
    M.set_option(name, value)
  end, {
    nargs = "+",
    complete = function(_, line)
      if vim.split(line, "%s+")[2] then
        return {}
      end
      return {
        "line_character",
        "fill_character",
        "erase_character",
        "aspect_ratio",
        "trim_line_endings",
        "borderless_shapes",
        "rubber_banding",
        "spray_radius",
        "vaporize_fuzziness",
      }
    end,
    desc = "Set an Artist session option",
  })

  augroup = vim.api.nvim_create_augroup("artist.nvim", { clear = true })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = augroup,
    callback = function(event)
      if sessions[event.buf] then
        M.disable(event.buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
    group = augroup,
    callback = function(event)
      local winid = vim.api.nvim_get_current_win()
      for active_bufnr, state in pairs(sessions) do
        if state.active_windows[winid] and active_bufnr ~= event.buf then
          restore_window(state, winid)
        end
      end
      local state = sessions[event.buf]
      if state and vim.api.nvim_win_get_buf(winid) == event.buf then
        configure_window(state, winid)
      end
      for _, palette_state in pairs(sessions) do
        if palette_state.palette_win and winid ~= palette_state.palette_win then
          close_palette(palette_state)
        end
      end
    end,
  })
  M._install_global_mappings()
end

M.tools = registry.names()
M.operations = registry.definitions
M.canvas = canvas

return M
