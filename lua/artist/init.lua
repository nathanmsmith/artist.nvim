local canvas = require("artist.canvas")

local M = {}

local defaults = {
  tool = "line",
  aspect_ratio = 1,
  pen_character = "*",
  mappings = true,
}

local tools = {
  line = canvas.line,
  rectangle = canvas.rectangle,
  ellipse = canvas.ellipse,
  erase = canvas.erase,
  freehand = function(from, to, options)
    local result = canvas.line(from, to)
    for _, value in ipairs(result) do
      value.char = options.pen_character or "*"
    end
    return result
  end,
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
  { "<C-c>", "cancel" },
  { "<CR>", "keyboard_point" },
}

local function resolve_buffer(bufnr)
  if bufnr == nil or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local function session_for(bufnr)
  bufnr = resolve_buffer(bufnr)
  return sessions[bufnr], bufnr
end

local function position_at_cursor()
  local cursor = vim.api.nvim_win_get_cursor(0)
  return { row = cursor[1], col = cursor[2] + 1 }
end

local function mouse_position(bufnr)
  local value = vim.fn.getmousepos()
  if value.winid == 0 or value.line < 1 or value.column < 1 then
    return nil
  end
  if vim.api.nvim_win_get_buf(value.winid) ~= bufnr then
    return nil
  end
  vim.api.nvim_set_current_win(value.winid)
  local coladd = value.coladd or 0
  pcall(vim.fn.cursor, { value.line, value.column, coladd })

  local row = value.line
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if row == line_count then
    local last_position = vim.fn.screenpos(value.winid, line_count, 1)
    if last_position.row > 0 and value.screenrow > last_position.row then
      row = row + value.screenrow - last_position.row
    end
  end

  -- `column` stops at one byte past the end of the line. Horizontal mouse
  -- movement in virtual space is reported separately in `coladd`.
  local line = vim.api.nvim_buf_get_lines(bufnr, value.line - 1, value.line, false)[1] or ""
  local prefix = line:sub(1, value.column - 1)
  local character_column = vim.fn.strchars(prefix) + 1
  return { row = row, col = character_column + coladd }
end

local function points_for(state, from, to)
  local rasterizer = tools[state.tool]
  return rasterizer(from, to, {
    aspect_ratio = state.options.aspect_ratio,
    pen_character = state.options.pen_character,
  })
end

local function clear_preview(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
  end
end

local function preview(bufnr, points)
  clear_preview(bufnr)
  if #points == 0 then
    return
  end
  local by_row = {}
  for _, value in ipairs(canvas.deduplicate(points)) do
    local row = by_row[value.row] or {}
    by_row[value.row] = row
    row[value.col] = value.char
  end
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local last_virtual_row = line_count
  for row_number, replacements in pairs(by_row) do
    if row_number <= line_count then
      local line = vim.api.nvim_buf_get_lines(bufnr, row_number - 1, row_number, false)[1] or ""
      local chars = line == "" and {} or vim.fn.split(line, "\\zs")
      local first, last
      for col in pairs(replacements) do
        first, last = math.min(first or col, col), math.max(last or col, col)
      end
      local anchor = math.min(first, #chars + 1)
      local rendered = {}
      for col = anchor, last do
        rendered[#rendered + 1] = replacements[col] or chars[col] or " "
      end
      vim.api.nvim_buf_set_extmark(bufnr, namespace, row_number - 1, math.min(anchor - 1, #line), {
        virt_text = { { table.concat(rendered), "ArtistPreview" } },
        virt_text_pos = "overlay",
        hl_mode = "combine",
        priority = 200,
      })
    else
      last_virtual_row = math.max(last_virtual_row, row_number)
    end
  end
  if last_virtual_row > line_count then
    local virtual_lines = {}
    for row_number = line_count + 1, last_virtual_row do
      local replacements = by_row[row_number] or {}
      local last = 0
      for col in pairs(replacements) do
        last = math.max(last, col)
      end
      local rendered = {}
      for col = 1, last do
        rendered[col] = replacements[col] or " "
      end
      virtual_lines[#virtual_lines + 1] = { { table.concat(rendered), "ArtistPreview" } }
    end
    vim.api.nvim_buf_set_extmark(bufnr, namespace, line_count - 1, 0, {
      virt_lines = virtual_lines,
      virt_lines_above = false,
      priority = 200,
    })
  end
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
  vim.api.nvim_buf_call(bufnr, function()
    for _, definition in ipairs(mapping_definitions) do
      local lhs, method = definition[1], definition[2]
      state.saved_mappings[lhs] = save_mapping(lhs)
      vim.keymap.set("n", lhs, function()
        M[method](bufnr)
      end, { buffer = bufnr, silent = true, nowait = true, desc = "Artist: " .. method:gsub("_", " ") })
    end
  end)
end

local function remove_mappings(bufnr, state)
  if not state.options.mappings then
    return
  end
  vim.api.nvim_buf_call(bufnr, function()
    for _, definition in ipairs(mapping_definitions) do
      local lhs = definition[1]
      pcall(vim.keymap.del, "n", lhs, { buffer = bufnr })
      local saved = state.saved_mappings and state.saved_mappings[lhs]
      if saved then
        pcall(vim.fn.mapset, "n", false, saved)
      end
    end
  end)
end

---Configure artist.nvim. Calling setup is optional.
function M.setup(options)
  vim.validate("options", options, "table", true)
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), options or {})
  if not tools[config.tool] then
    error("artist: unknown tool " .. tostring(config.tool))
  end
end

---Enable Artist mode in a buffer.
function M.enable(bufnr, options)
  bufnr = resolve_buffer(bufnr)
  vim.validate("options", options, "table", true)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    error("artist: invalid buffer " .. bufnr)
  end
  if sessions[bufnr] then
    return
  end
  local effective = vim.tbl_deep_extend("force", vim.deepcopy(config), options or {})
  if not tools[effective.tool] then
    error("artist: unknown tool " .. tostring(effective.tool))
  end
  local state = {
    tool = effective.tool,
    options = effective,
    previous = {
      virtualedit = {},
      wrap = {},
    },
  }
  sessions[bufnr] = state
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(winid) == bufnr then
      state.previous.virtualedit[winid] = vim.wo[winid].virtualedit
      state.previous.wrap[winid] = vim.wo[winid].wrap
      vim.wo[winid].virtualedit = "all"
      vim.wo[winid].wrap = false
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

---Disable Artist mode and restore the options and mappings it changed.
function M.disable(bufnr)
  local state
  state, bufnr = session_for(bufnr)
  if not state then
    return
  end
  clear_preview(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    remove_mappings(bufnr, state)
    vim.b[bufnr].artist_enabled = false
    vim.b[bufnr].artist_tool = nil
  end
  for winid, value in pairs(state.previous.virtualedit) do
    if vim.api.nvim_win_is_valid(winid) then
      vim.wo[winid].virtualedit = value
      vim.wo[winid].wrap = state.previous.wrap[winid]
    end
  end
  -- 'mouse' is global. Restore it only if no other Artist session needs it.
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
  local state = session_for(bufnr)
  return state ~= nil
end

function M.get_tool(bufnr)
  local state = session_for(bufnr)
  return state and state.tool or nil
end

function M.set_tool(tool, bufnr)
  if not tools[tool] then
    error("artist: unknown tool " .. tostring(tool))
  end
  local state
  state, bufnr = session_for(bufnr)
  if not state then
    error("artist: Artist mode is not enabled in this buffer")
  end
  M.cancel(bufnr)
  state.tool = tool
  vim.b[bufnr].artist_tool = tool
  vim.api.nvim_exec_autocmds(
    "User",
    { pattern = "ArtistToolChanged", modeline = false, data = { buf = bufnr, tool = tool } }
  )
end

---Draw a shape directly. Positions use one-based { row, col } coordinates.
function M.draw(tool, from, to, options)
  options = options or {}
  local rasterizer = tools[tool]
  if not rasterizer then
    error("artist: unknown tool " .. tostring(tool))
  end
  local bufnr = resolve_buffer(options.bufnr)
  local points = rasterizer(from, to, {
    aspect_ratio = options.aspect_ratio or config.aspect_ratio,
    pen_character = options.pen_character or config.pen_character,
  })
  canvas.apply(bufnr, points, { overwrite = options.overwrite or tool == "erase" })
  return points
end

function M.mouse_down(bufnr)
  local state
  state, bufnr = session_for(bufnr)
  if not state then
    return
  end
  local position = mouse_position(bufnr)
  if not position then
    return
  end
  state.drag = { start = position, current = position, points = {} }
  preview(bufnr, points_for(state, position, position))
end

function M.mouse_drag(bufnr)
  local state
  state, bufnr = session_for(bufnr)
  if not state or not state.drag then
    return
  end
  local position = mouse_position(bufnr)
  if not position then
    return
  end
  if state.tool == "freehand" then
    local segment = tools.freehand(state.drag.current, position, state.options)
    vim.list_extend(state.drag.points, segment)
    state.drag.current = position
    preview(bufnr, state.drag.points)
  else
    state.drag.current = position
    preview(bufnr, points_for(state, state.drag.start, position))
  end
end

function M.mouse_up(bufnr)
  local state
  state, bufnr = session_for(bufnr)
  if not state or not state.drag then
    return
  end
  local position = mouse_position(bufnr) or state.drag.current
  local points
  if state.tool == "freehand" then
    vim.list_extend(state.drag.points, tools.freehand(state.drag.current, position, state.options))
    points = state.drag.points
  else
    points = points_for(state, state.drag.start, position)
  end
  clear_preview(bufnr)
  state.drag = nil
  canvas.apply(bufnr, points, { overwrite = state.tool == "erase" })
end

---Place an anchor at the cursor, or finish a shape from the previous anchor.
function M.keyboard_point(bufnr)
  local state
  state, bufnr = session_for(bufnr)
  if not state then
    return
  end
  local position = position_at_cursor()
  if state.tool == "freehand" then
    canvas.apply(bufnr, { { row = position.row, col = position.col, char = state.options.pen_character } })
    return
  end
  if not state.anchor then
    state.anchor = position
    preview(bufnr, points_for(state, position, position))
    return
  end
  local points = points_for(state, state.anchor, position)
  clear_preview(bufnr)
  state.anchor = nil
  canvas.apply(bufnr, points, { overwrite = state.tool == "erase" })
end

function M.cancel(bufnr)
  local state
  state, bufnr = session_for(bufnr)
  if not state then
    return
  end
  state.anchor, state.drag = nil, nil
  clear_preview(bufnr)
end

function M._create_commands()
  if augroup then
    return
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
      return { "enable", "disable", "toggle", "line", "rectangle", "ellipse", "freehand", "erase" }
    end,
    desc = "Enable, disable, or configure Artist mode",
  })
  vim.api.nvim_create_user_command("ArtistTool", function(command)
    M.set_tool(command.args)
  end, {
    nargs = 1,
    complete = function()
      return { "line", "rectangle", "ellipse", "freehand", "erase" }
    end,
    desc = "Select the Artist drawing tool",
  })
  vim.api.nvim_create_user_command("ArtistEnable", function()
    M.enable()
  end, { desc = "Enable Artist mode" })
  vim.api.nvim_create_user_command("ArtistDisable", function()
    M.disable()
  end, { desc = "Disable Artist mode" })
  vim.api.nvim_create_user_command("ArtistToggle", function()
    M.toggle()
  end, { desc = "Toggle Artist mode" })

  augroup = vim.api.nvim_create_augroup("artist.nvim", { clear = true })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = augroup,
    callback = function(event)
      if sessions[event.buf] then
        M.disable(event.buf)
      end
    end,
  })
end

M.tools = vim.tbl_keys(tools)
table.sort(M.tools)

return M
