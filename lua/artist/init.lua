local canvas = require("artist.canvas")
local grid = require("artist.grid")
local operations = require("artist.operations")
local patch = require("artist.patch")
local registry = require("artist.registry")

local M = {}

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
  mouse_wheel = false,
  winbar = true,
  transparent_selection = true,
}

local config = vim.deepcopy(defaults)
local sessions = {}
local namespace = vim.api.nvim_create_namespace("artist.nvim")
local augroup
local original_mouse

local mapping_definitions = {
  { "<LeftMouse>", "mouse_down" },
  { "<LeftDrag>", "mouse_drag" },
  { "<LeftRelease>", "mouse_up" },
  { "<S-LeftMouse>", "shift_mouse_down" },
  { "<S-LeftDrag>", "mouse_drag" },
  { "<S-LeftRelease>", "mouse_up" },
  { "<MiddleMouse>", "pick_operation" },
  { "<S-MiddleMouse>", "pick_operation" },
  { "<RightMouse>", "pick_operation" },
  { "<S-RightMouse>", "pick_operation" },
  { "<CR>", "keyboard_point" },
  { "<C-CR>", "finish" },
  { "<", "toggle_first_arrow" },
  { ">", "toggle_second_arrow" },
  { "<C-c>", "cancel" },
  { "<C-c><C-c>", "disable" },
  { "<C-c><C-a><C-o>", "pick_operation" },
  { "<C-c><C-a><C-e>", "select_character", "erase_character" },
  { "<C-c><C-a><C-f>", "select_character", "fill_character" },
  { "<C-c><C-a><C-l>", "select_character", "line_character" },
  { "<C-c><C-a><C-r>", "toggle_setting", "rubber_banding" },
  { "<C-c><C-a><C-t>", "toggle_setting", "trim_line_endings" },
  { "<C-c><C-a><C-s>", "toggle_setting", "borderless_shapes" },
  { "<C-c><C-a>l", "select_tool", "line" },
  { "<C-c><C-a>L", "select_tool", "straight_line" },
  { "<C-c><C-a>r", "select_tool", "rectangle" },
  { "<C-c><C-a>R", "select_tool", "square" },
  { "<C-c><C-a>s", "select_tool", "square" },
  { "<C-c><C-a>p", "select_tool", "poly_line" },
  { "<C-c><C-a>P", "select_tool", "straight_poly_line" },
  { "<C-c><C-a>e", "select_tool", "ellipse" },
  { "<C-c><C-a>c", "select_tool", "circle" },
  { "<C-c><C-a>t", "select_tool", "text_see_through" },
  { "<C-c><C-a>T", "select_tool", "text_overwrite" },
  { "<C-c><C-a>S", "select_tool", "spray" },
  { "<C-c><C-a>z", "select_tool", "spray_radius" },
  { "<C-c><C-a><C-d>", "select_tool", "erase_character" },
  { "<C-c><C-a>E", "select_tool", "erase_rectangle" },
  { "<C-c><C-a>v", "select_tool", "vaporize_line" },
  { "<C-c><C-a>V", "select_tool", "vaporize_lines" },
  { "<C-c><C-a><C-k>", "select_tool", "cut_rectangle" },
  { "<C-c><C-a><M-w>", "select_tool", "copy_rectangle" },
  { "<C-c><C-a><C-y>", "select_tool", "paste" },
  { "<C-c><C-a>f", "select_tool", "flood_fill" },
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

local function resolve_buffer(bufnr)
  return (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
end

local function session_for(bufnr)
  bufnr = resolve_buffer(bufnr)
  return sessions[bufnr], bufnr
end

local function clear_preview(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
  end
end

local function position_at_cursor()
  local cursor = vim.api.nvim_win_get_cursor(0)
  return { row = cursor[1], col = vim.fn.virtcol(".") }
end

local function mouse_position(bufnr)
  local value = vim.fn.getmousepos()
  if value.winid == 0 or value.line < 1 or value.column < 1 or vim.api.nvim_win_get_buf(value.winid) ~= bufnr then
    return nil
  end
  vim.api.nvim_set_current_win(value.winid)
  pcall(vim.fn.cursor, { value.line, value.column, value.coladd or 0 })
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
  return { row = row, col = vim.fn.strdisplaywidth(prefix) + 1 + (value.coladd or 0) }
end

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

local function new_transaction(state)
  return patch.new(grid.from_buffer(state.bufnr), { trim_line_endings = state.options.trim_line_endings })
end

local function execute(state, transaction, operation, from, to, extra)
  local options = effective_options(state, operation)
  if extra then
    options = vim.tbl_extend("force", options, extra)
  end
  return operations.execute(transaction, operation, from, to, options)
end

local function build_poly_transaction(state, current, operation)
  local transaction = new_transaction(state)
  local points = state.poly_points or {}
  operation = operation or state.tool
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
      local byte_col = 0
      if winid ~= -1 and vim.fn.exists("*virtcol2col") == 1 then
        byte_col = math.max(0, vim.fn.virtcol2col(winid, row, first) - 1)
      else
        local text = vim.api.nvim_buf_get_lines(state.bufnr, row - 1, row, false)[1] or ""
        byte_col = math.min(#text, first - 1)
      end
      vim.api.nvim_buf_set_extmark(state.bufnr, namespace, row - 1, byte_col, {
        virt_text = { { table.concat(rendered), "ArtistPreview" } },
        virt_text_pos = "overlay",
        hl_mode = "combine",
        priority = 200,
      })
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

local function stop_timer(state)
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end
end

local function commit(state, transaction)
  stop_timer(state)
  clear_preview(state.bufnr)
  if transaction then
    transaction:commit(state.bufnr)
  end
end

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

local function toolbar_text(state)
  local operation = registry.get(state.tool)
  local drawing = state.drag or state.anchor or state.transaction
  local arrows = (state.first_arrow and " <" or "") .. (state.second_arrow and " >" or "")
  return table.concat({
    "%#ArtistMode# ARTIST %*",
    "%#ArtistTool# [" .. state.tool .. arrows .. "] %*",
    drawing and "%#ArtistHint# drawing… %*" or "",
    "%=%#ArtistHint# <CR> draw  <C-CR> finish  <C-c> cancel %*",
  })
end

local function configure_window(state, winid)
  if state.active_windows[winid] then
    return
  end
  if state.previous.virtualedit[winid] == nil then
    state.previous.virtualedit[winid] = vim.wo[winid].virtualedit
    state.previous.wrap[winid] = vim.wo[winid].wrap
    state.previous.winbar[winid] = vim.wo[winid].winbar
    state.previous.winhighlight[winid] = vim.wo[winid].winhighlight
  end
  state.active_windows[winid] = true
  vim.wo[winid].virtualedit = "all"
  vim.wo[winid].wrap = false
  if state.options.winbar then
    vim.wo[winid].winbar = toolbar_text(state)
  end
  if state.options.transparent_selection then
    vim.wo[winid].winhighlight = with_highlight_override(vim.wo[winid].winhighlight, "Visual", "ArtistVisual")
  end
end

local function restore_window(state, winid)
  if not state.active_windows[winid] or not vim.api.nvim_win_is_valid(winid) then
    return
  end
  vim.wo[winid].virtualedit = state.previous.virtualedit[winid]
  vim.wo[winid].wrap = state.previous.wrap[winid]
  vim.wo[winid].winbar = state.previous.winbar[winid]
  vim.wo[winid].winhighlight = state.previous.winhighlight[winid]
  state.active_windows[winid] = nil
end

local function update_toolbar(state)
  if state.options.winbar then
    for winid in pairs(state.active_windows) do
      if vim.api.nvim_win_is_valid(winid) then
        vim.wo[winid].winbar = toolbar_text(state)
      end
    end
  end
end

local function all_mapping_definitions(state)
  local result = vim.deepcopy(mapping_definitions)
  for _, value in ipairs(movement_mappings) do
    result[#result + 1] = value
  end
  if state.options.mouse_wheel then
    result[#result + 1] = { "<ScrollWheelUp>", "previous_tool" }
    result[#result + 1] = { "<ScrollWheelDown>", "next_tool" }
  end
  return result
end

local function save_mapping(lhs)
  local value = vim.fn.maparg(lhs, "n", false, true)
  if type(value) == "table" and value.buffer == 1 and next(value) ~= nil then
    return value
  end
end

local function install_mappings(bufnr, state)
  if not state.options.mappings then
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
          M.keyboard_move(method, bufnr)
        end, { buffer = bufnr, silent = true, nowait = true, desc = "Artist: move and draw" })
      elseif method == "select_tool" then
        vim.keymap.set("n", lhs, function()
          M.set_tool(definition[3], bufnr)
        end, { buffer = bufnr, silent = true, nowait = true, desc = "Artist: select " .. definition[3] })
      elseif method == "select_character" or method == "toggle_setting" then
        vim.keymap.set("n", lhs, function()
          M[method](definition[3], bufnr)
        end, { buffer = bufnr, silent = true, nowait = true, desc = "Artist: configure " .. definition[3] })
      else
        vim.keymap.set("n", lhs, function()
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

local function remove_mappings(bufnr, state)
  if not state.options.mappings then
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

local function validate_options(options)
  if options.aspect_ratio ~= nil and (type(options.aspect_ratio) ~= "number" or options.aspect_ratio <= 0) then
    error("artist: aspect_ratio must be a positive number")
  end
  for _, name in ipairs({ "line_character", "fill_character", "erase_character" }) do
    if options[name] ~= nil and vim.fn.strchars(options[name]) ~= 1 then
      error("artist: " .. name .. " must be one character or nil")
    end
  end
end

function M.setup(options)
  vim.validate("options", options, "table", true)
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), options or {})
  local resolved = registry.resolve(config.tool)
  if not resolved then
    error("artist: unknown operation " .. tostring(config.tool))
  end
  config.tool = resolved
  validate_options(config)
end

function M.enable(bufnr, options)
  bufnr = resolve_buffer(bufnr)
  vim.validate("options", options, "table", true)
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
    previous = { virtualedit = {}, wrap = {}, winbar = {}, winhighlight = {} },
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
end

function M.disable(bufnr)
  local state
  state, bufnr = session_for(bufnr)
  if not state then
    return
  end
  M.cancel(bufnr)
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

function M.toggle(bufnr, options)
  bufnr = resolve_buffer(bufnr)
  if sessions[bufnr] then
    M.disable(bufnr)
  else
    M.enable(bufnr, options)
  end
end

function M.is_enabled(bufnr)
  return session_for(bufnr) ~= nil
end

function M.get_tool(bufnr)
  local state = session_for(bufnr)
  return state and state.tool or nil
end

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
  vim.api.nvim_exec_autocmds("User", {
    pattern = "ArtistToolChanged",
    modeline = false,
    data = { buf = bufnr, tool = resolved },
  })
end

function M.shift_tool(bufnr)
  local state = session_for(bufnr)
  if state then
    M.set_tool(registry.shifted(state.tool), bufnr)
  end
end

local function cycle_tool(delta, bufnr)
  local state = session_for(bufnr)
  if not state then
    return
  end
  local names, index = registry.names(), 1
  for candidate, name in ipairs(names) do
    if name == state.tool then
      index = candidate
      break
    end
  end
  M.set_tool(names[(index - 1 + delta) % #names + 1], bufnr)
end

function M.next_tool(bufnr)
  cycle_tool(1, bufnr)
end

function M.previous_tool(bufnr)
  cycle_tool(-1, bufnr)
end

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

function M.select_character(name, bufnr)
  local prompt = "Artist " .. name:gsub("_", " ") .. " (empty resets): "
  local value = vim.fn.input(prompt)
  if value == "" then
    value = name == "erase_character" and " " or nil
  end
  M.set_option(name, value, bufnr)
end

function M.toggle_setting(name, bufnr)
  local state = session_for(bufnr)
  if state then
    M.set_option(name, not state.options[name], bufnr)
  end
end

function M.toggle_first_arrow(bufnr)
  M.toggle_arrow("first", bufnr)
end

function M.toggle_second_arrow(bufnr)
  M.toggle_arrow("second", bufnr)
end

---Execute an operation directly. Display-cell positions are one-based.
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
  local operation = shifted and registry.shifted(state.tool) or state.tool
  local definition = registry.get(operation)
  if definition.kind == "one_point" then
    local transaction = new_transaction(state)
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
  end
  local transaction = definition.kind == "poly_point" and build_poly_transaction(state, nil, operation)
    or new_transaction(state)
  local start = definition.kind == "poly_point" and state.anchor or position
  state.drag = { operation = operation, start = start, current = position, transaction = transaction }
  if definition.kind == "continuous" then
    execute(state, transaction, operation, position, position)
  else
    execute(state, transaction, operation, start, position)
  end
  preview_operation(state, transaction, start, position, definition.kind)
  update_toolbar(state)
  if operation == "spray" and (state.options.timer_factory or vim.uv) then
    state.timer = state.options.timer_factory and state.options.timer_factory() or vim.uv.new_timer()
    state.timer:start(
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

function M.shift_mouse_down(bufnr)
  M.mouse_down(bufnr, true)
end

function M.mouse_drag(bufnr)
  local state = session_for(bufnr)
  if not state or not state.drag then
    return
  end
  local position = mouse_position(state.bufnr)
  if not position then
    return
  end
  local drag, definition = state.drag, registry.get(state.drag.operation)
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

function M.mouse_up(bufnr)
  local state = session_for(bufnr)
  if not state or not state.drag then
    return
  end
  stop_timer(state)
  local drag, definition = state.drag, registry.get(state.drag.operation)
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
    state.poly_points[#state.poly_points + 1] = position
    state.anchor, state.transaction = position, build_poly_transaction(state, nil, drag.operation)
    preview_operation(state, state.transaction, state.poly_points[1], position, definition.kind)
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

function M.keyboard_point(bufnr)
  local state = session_for(bufnr)
  if not state then
    return
  end
  local position, definition = state.keyboard_position or position_at_cursor(), registry.get(state.tool)
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
    local transaction, extra = new_transaction(state)
    if state.tool == "text_see_through" or state.tool == "text_overwrite" then
      extra = { text = vim.fn.input("Artist text: ") }
    end
    execute(state, transaction, state.tool, position, position, extra)
    commit(state, transaction)
  elseif definition.kind == "poly_point" then
    if not state.anchor then
      state.anchor, state.poly_points = position, { position }
      state.transaction = new_transaction(state)
    else
      state.poly_points[#state.poly_points + 1] = position
      state.anchor = position
      state.transaction = build_poly_transaction(state)
    end
    preview_operation(state, state.transaction, state.poly_points[1], position, definition.kind)
    if vim.v.count > 0 then
      M.finish(bufnr)
    end
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
  state.keyboard_position = after
  local visible_row = math.min(after.row, vim.api.nvim_buf_line_count(state.bufnr))
  local winid = vim.fn.bufwinid(state.bufnr)
  if winid ~= -1 then
    local byte_col = vim.fn.exists("*virtcol2col") == 1 and vim.fn.virtcol2col(winid, visible_row, after.col)
      or after.col
    local line = vim.api.nvim_buf_get_lines(state.bufnr, visible_row - 1, visible_row, false)[1] or ""
    local existing_width = vim.fn.strdisplaywidth(line)
    pcall(vim.api.nvim_win_set_cursor, winid, { visible_row, math.max(0, math.min(#line, byte_col - 1)) })
    if after.col > existing_width + 1 then
      pcall(vim.fn.cursor, { visible_row, #line + 1, after.col - existing_width - 1 })
    end
  end
  local definition = registry.get(state.tool)
  if definition.kind == "continuous" and state.continuous_active then
    execute(state, state.transaction, state.tool, before, after)
    preview_transaction(state, state.transaction)
    state.anchor = after
  elseif state.anchor and (definition.kind == "two_point" or definition.kind == "poly_point") then
    local transaction
    if definition.kind == "poly_point" then
      transaction = build_poly_transaction(state, after)
    else
      transaction = new_transaction(state)
      execute(state, transaction, state.tool, state.anchor, after)
    end
    preview_operation(state, transaction, state.anchor, after, definition.kind)
    state.preview_transaction = transaction
  end
end

function M.finish(bufnr)
  local state = session_for(bufnr)
  if not state then
    return
  end
  commit(state, state.preview_transaction or state.transaction)
  state.transaction, state.preview_transaction, state.anchor, state.drag, state.poly_points, state.continuous_active =
    nil, nil, nil, nil, nil, nil
  update_toolbar(state)
end

function M.cancel(bufnr)
  local state
  state, bufnr = session_for(bufnr)
  if not state then
    return
  end
  stop_timer(state)
  state.transaction, state.preview_transaction, state.anchor, state.drag, state.poly_points, state.continuous_active =
    nil, nil, nil, nil, nil, nil
  clear_preview(bufnr)
  update_toolbar(state)
end

function M.pick_operation(bufnr)
  local state = session_for(bufnr)
  if not state then
    return
  end
  local names = registry.names()
  vim.ui.select(names, {
    prompt = "Artist operation",
    format_item = function(name)
      return registry.get(name).label
    end,
  }, function(choice)
    if choice then
      M.set_tool(choice, bufnr)
    end
  end)
end

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
    end,
  })
end

M.tools = registry.names()
M.operations = registry.definitions
M.upstream_commit = "f4f249a2249a7047ba41a659b8fcdcd7e1caf4e0"
M.canvas = canvas

return M
