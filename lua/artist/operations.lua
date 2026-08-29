local geometry = require("artist.geometry")
local display_grid = require("artist.grid")
local patch_module = require("artist.patch")

local M = { copy_buffer = nil }

local function round(value)
  return math.floor(value + 0.5)
end

local function drawing_options(options)
  return {
    aspect_ratio = options.aspect_ratio,
    line_character = options.line_character,
    fill_character = options.fill_character,
    borderless = options.borderless_shapes,
    ellipse_left_character = options.ellipse_left_character,
    ellipse_right_character = options.ellipse_right_character,
    first_arrow = options.first_arrow,
    second_arrow = options.second_arrow,
    arrow_characters = options.arrow_characters,
  }
end

local function add_geometry(transaction, name, from, to, options)
  local points = geometry[name](from, to, drawing_options(options))
  transaction:add(points, { intersect = options.line_character == nil })
  return points
end

local function rectangle_bounds(from, to, square, aspect_ratio)
  from, to = geometry.normalize(from), geometry.normalize(to)
  if square then
    from, to = geometry.squarify(from, to, aspect_ratio)
  end
  return math.min(from.row, to.row), math.max(from.row, to.row), math.min(from.col, to.col), math.max(from.col, to.col)
end

local function copy_region(transaction, from, to, square, options)
  local top, bottom, left, right = rectangle_bounds(from, to, square, options.aspect_ratio)
  local lines = {}
  for row = top, bottom do
    local characters = {}
    for col = left, right do
      local raw = transaction.grid.rows[row] and transaction.grid.rows[row][col]
      if type(raw) == "table" and raw.continuation then
        if raw.lead < left then
          characters[#characters + 1] = " "
        end
      else
        characters[#characters + 1] = transaction:get(row, col)
      end
    end
    lines[#lines + 1] = table.concat(characters)
  end
  M.copy_buffer = lines
  local register = options.rectangle_register
  if register ~= false then
    pcall(vim.fn.setreg, type(register) == "string" and register or '"', lines, "b" .. (right - left + 1))
  end
  return lines, top, bottom, left, right
end

local orientations = {
  horizontal = { sx = 1, sy = 0, line = "-", accepts = { ["-"] = true, ["+"] = true } },
  vertical = { sx = 0, sy = 1, line = "|", accepts = { ["|"] = true, ["+"] = true } },
  slash = { sx = 1, sy = -1, line = "/", accepts = { ["/"] = true, X = true } },
  backslash = { sx = 1, sy = 1, line = "\\", accepts = { ["\\"] = true, X = true } },
}

local function orientations_at(character)
  if character == "-" then
    return { "horizontal" }
  elseif character == "|" then
    return { "vertical" }
  elseif character == "/" then
    return { "slash" }
  elseif character == "\\" then
    return { "backslash" }
  elseif character == "+" then
    return { "horizontal", "vertical" }
  elseif character == "X" then
    return { "slash", "backslash" }
  end
  return {}
end

local function find_endpoint(transaction, row, col, orientation, sign, fuzziness)
  local info = orientations[orientation]
  local current_row, current_col, last_row, last_col = row, col, row, col
  while current_row >= 1 and current_col >= 1 do
    local character = transaction:get(current_row, current_col)
    if info.accepts[character] then
      last_row, last_col = current_row, current_col
      current_row, current_col = current_row + sign * info.sy, current_col + sign * info.sx
    elseif character == " " then
      break
    else
      local found
      for distance = 1, fuzziness do
        local test_row = current_row + distance * sign * info.sy
        local test_col = current_col + distance * sign * info.sx
        if test_row < 1 or test_col < 1 then
          break
        end
        if info.accepts[transaction:get(test_row, test_col)] then
          current_row, current_col, found = test_row, test_col, true
          break
        end
      end
      if not found then
        break
      end
    end
  end
  return { row = last_row, col = last_col }
end

local function vaporize_orientation(transaction, row, col, orientation, options)
  local info = orientations[orientation]
  local first = find_endpoint(transaction, row, col, orientation, -1, options.vaporize_fuzziness or 1)
  local last = find_endpoint(transaction, row, col, orientation, 1, options.vaporize_fuzziness or 1)
  local current_row, current_col = first.row, first.col
  while true do
    local existing = transaction:get(current_row, current_col)
    transaction:set(current_row, current_col, patch_module.unintersection(info.line, existing, options.erase_character))
    if current_row == last.row and current_col == last.col then
      break
    end
    current_row, current_col = current_row + info.sy, current_col + info.sx
  end
  return first, last
end

local function vaporize(transaction, position, connected, options)
  local queue = { geometry.normalize(position) }
  local visited = {}
  while #queue > 0 do
    local current = table.remove(queue)
    for _, orientation in ipairs(orientations_at(transaction:get(current.row, current.col))) do
      local id = current.row .. ":" .. current.col .. ":" .. orientation
      if not visited[id] then
        visited[id] = true
        local first, last = vaporize_orientation(transaction, current.row, current.col, orientation, options)
        if connected then
          queue[#queue + 1] = first
          queue[#queue + 1] = last
        end
      end
    end
    if not connected then
      break
    end
  end
end

local function flood_fill(transaction, position, options)
  position = geometry.normalize(position)
  local source = transaction:get(position.row, position.col)
  local fill = options.fill_character or options.default_fill_character or "."
  if source == fill or position.row > transaction.grid:height() then
    return
  end
  local right = options.flood_fill_right_boundary
  if right == "fill_column" then
    right = options.fill_column or 80
  elseif type(right) ~= "number" then
    right = options.window_width or vim.o.columns
  end
  right = math.max(position.col, math.floor(right))
  local stack = { position }
  local queued = { [position.row .. ":" .. position.col] = true }
  while #stack > 0 do
    local seed = table.remove(stack)
    local left, run_right = seed.col, seed.col
    while left > 1 and transaction:get(seed.row, left - 1) == source do
      left = left - 1
    end
    while run_right < right and transaction:get(seed.row, run_right + 1) == source do
      run_right = run_right + 1
    end
    for col = left, run_right do
      transaction:set(seed.row, col, fill)
      for _, adjacent_row in ipairs({ seed.row - 1, seed.row + 1 }) do
        local id = adjacent_row .. ":" .. col
        if
          adjacent_row >= 1
          and adjacent_row <= transaction.grid:height()
          and not queued[id]
          and transaction:get(adjacent_row, col) == source
        then
          queued[id] = true
          stack[#stack + 1] = { row = adjacent_row, col = col }
        end
      end
    end
  end
end

local function render_text(text, options)
  local renderer = options.text_renderer
  if type(renderer) == "function" then
    local rendered = renderer(text, options)
    return type(rendered) == "string" and vim.split(rendered, "\n", { plain = true }) or rendered
  end
  local executable = options.figlet_executable or "figlet"
  if vim.fn.executable(executable) == 1 and vim.system then
    local result = vim.system({ executable, "-f", options.figlet_font or "standard", text }, { text = true }):wait()
    if result.code == 0 then
      return vim.split(result.stdout:gsub("\n$", ""), "\n", { plain = true })
    end
  end
  return { text }
end

local function insert_text(transaction, position, text, see_through, options)
  position = geometry.normalize(position)
  for row_offset, line in ipairs(render_text(text or "", options) or {}) do
    for col, character in ipairs(display_grid.decode_line(line, options.tabstop or 8)) do
      if type(character) ~= "table" then
        if not see_through or character ~= " " then
          transaction:set(position.row + row_offset - 1, position.col + col - 1, character)
        end
      end
    end
  end
end

local function spray(transaction, position, options)
  position = geometry.normalize(position)
  local radius = math.max(1, options.spray_radius or 4)
  local characters = options.spray_characters or { " ", ".", "-", "+", "m", "%", "*", "#" }
  local initial = options.spray_initial_character or "."
  local rng = options.rng or math.random
  for _ = 1, radius * radius do
    local angle = math.rad(rng(0, 358))
    local distance = rng(0, radius - 1)
    local row = position.row + round(distance * math.sin(angle))
    local col = position.col + round(distance * math.cos(angle))
    if row >= 1 and col >= 1 then
      local existing, next_character = transaction:get(row, col), initial
      for index, character in ipairs(characters) do
        if existing == character then
          next_character = characters[math.min(index + 1, #characters)]
          break
        end
      end
      transaction:set(row, col, next_character)
    end
  end
end

function M.execute(transaction, name, from, to, options)
  options = options or {}
  if
    name == "line"
    or name == "straight_line"
    or name == "rectangle"
    or name == "square"
    or name == "ellipse"
    or name == "circle"
  then
    return add_geometry(transaction, name, from, to, options)
  elseif name == "pen" then
    local position = geometry.normalize(to or from)
    transaction:set(
      position.row,
      position.col,
      options.line_character or options.fill_character or options.default_fill_character or "."
    )
  elseif name == "pen_line" then
    local points = geometry.line(
      from,
      to or from,
      { line_character = options.line_character or options.fill_character or options.default_fill_character or "." }
    )
    transaction:add(points)
    return points
  elseif name == "poly_line" or name == "straight_poly_line" then
    return add_geometry(transaction, name == "poly_line" and "line" or "straight_line", from, to, options)
  elseif name == "erase_character" then
    local position = geometry.normalize(to or from)
    transaction:set(position.row, position.col, options.erase_character or " ")
  elseif name == "erase_rectangle" then
    transaction:add(geometry.region(from, to, options.erase_character or " "))
  elseif name == "copy_rectangle" or name == "copy_square" or name == "cut_rectangle" or name == "cut_square" then
    local square = name:find("square", 1, true) ~= nil
    local _, top, bottom, left, right = copy_region(transaction, from, to, square, options)
    if name:find("cut", 1, true) then
      transaction:add(geometry.region({ top, left }, { bottom, right }, options.erase_character or " "))
    end
  elseif name == "paste" then
    local position = geometry.normalize(from)
    for offset, line in ipairs(M.copy_buffer or {}) do
      for col, character in ipairs(display_grid.decode_line(line, options.tabstop or 8)) do
        if type(character) ~= "table" then
          transaction:set(position.row + offset - 1, position.col + col - 1, character)
        end
      end
    end
  elseif name == "flood_fill" then
    flood_fill(transaction, from, options)
  elseif name == "vaporize_line" or name == "vaporize_lines" then
    vaporize(transaction, from, name == "vaporize_lines", options)
  elseif name == "text_see_through" or name == "text_overwrite" then
    insert_text(transaction, from, options.text, name == "text_see_through", options)
  elseif name == "spray" then
    spray(transaction, to or from, options)
  elseif name == "spray_radius" then
    from, to = geometry.normalize(from), geometry.normalize(to)
    options.spray_radius = math.max(1, round(math.sqrt((to.col - from.col) ^ 2 + (to.row - from.row) ^ 2)))
    return options.spray_radius
  else
    error("artist: operation is not implemented: " .. tostring(name))
  end
end

return M
