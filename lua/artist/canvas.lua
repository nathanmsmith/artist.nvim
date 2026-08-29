local M = {}

local directions = {
  ["-"] = { e = true, w = true },
  ["|"] = { n = true, s = true },
  ["+"] = { n = true, e = true, s = true, w = true },
  ["/"] = { ne = true, sw = true },
  ["\\"] = { nw = true, se = true },
  ["X"] = { ne = true, nw = true, se = true, sw = true },
}

local function copy_set(value)
  local result = {}
  for key in pairs(value or {}) do
    result[key] = true
  end
  return result
end

local function union(left, right)
  local result = copy_set(left)
  for key in pairs(right or {}) do
    result[key] = true
  end
  return result
end

local function has_orthogonal(value)
  return value.n or value.e or value.s or value.w
end

local function has_diagonal(value)
  return value.ne or value.nw or value.se or value.sw
end

local function character_for(value)
  if has_orthogonal(value) and has_diagonal(value) then
    return "+"
  end
  if (value.n or value.s) and (value.e or value.w) then
    return "+"
  end
  if value.n or value.s then
    return "|"
  end
  if value.e or value.w then
    return "-"
  end
  if (value.ne or value.sw) and (value.nw or value.se) then
    return "X"
  end
  if value.ne or value.sw then
    return "/"
  end
  if value.nw or value.se then
    return "\\"
  end
end

local function merge_character(existing, incoming)
  if existing == nil or existing == "" or existing == " " then
    return incoming
  end
  if existing == incoming then
    return existing
  end
  if directions[existing] and directions[incoming] then
    return character_for(union(directions[existing], directions[incoming]))
  end
  -- Drawing over prose should be predictable and reversible with undo.
  return incoming
end

local function point(row, col, char)
  return { row = row, col = col, char = char }
end

local function sign(value)
  if value < 0 then
    return -1
  elseif value > 0 then
    return 1
  end
  return 0
end

local function step_character(row_delta, col_delta)
  if row_delta == 0 then
    return "-"
  elseif col_delta == 0 then
    return "|"
  elseif sign(row_delta) == sign(col_delta) then
    return "\\"
  else
    return "/"
  end
end

local function key(row, col)
  return row .. ":" .. col
end

local function normalize(position)
  assert(type(position) == "table", "artist: a position must be a table")
  local row = tonumber(position.row or position[1])
  local col = tonumber(position.col or position[2])
  assert(row and col, "artist: a position needs row and col")
  return { row = math.max(1, math.floor(row)), col = math.max(1, math.floor(col)) }
end

local function deduplicate(points)
  local result, indexes = {}, {}
  for _, value in ipairs(points) do
    local id = key(value.row, value.col)
    local index = indexes[id]
    if index then
      result[index].char = merge_character(result[index].char, value.char)
    else
      indexes[id] = #result + 1
      result[#result + 1] = value
    end
  end
  return result
end

---Return the cells for a Bresenham line.
---@param from table
---@param to table
---@return table[]
function M.line(from, to)
  from, to = normalize(from), normalize(to)
  local x1, y1, x2, y2 = from.col, from.row, to.col, to.row
  local dx, sx = math.abs(x2 - x1), x1 < x2 and 1 or -1
  local dy, sy = -math.abs(y2 - y1), y1 < y2 and 1 or -1
  local err = dx + dy
  local coordinates = {}

  while true do
    coordinates[#coordinates + 1] = { row = y1, col = x1 }
    if x1 == x2 and y1 == y2 then
      break
    end
    local twice = 2 * err
    if twice >= dy then
      err, x1 = err + dy, x1 + sx
    end
    if twice <= dx then
      err, y1 = err + dx, y1 + sy
    end
  end

  local result = {}
  for index, current in ipairs(coordinates) do
    local neighbor = coordinates[index - 1] or coordinates[index + 1] or current
    local char = step_character(current.row - neighbor.row, current.col - neighbor.col)
    result[#result + 1] = point(current.row, current.col, char)
  end
  return result
end

---Return the cells for an axis-aligned rectangle.
function M.rectangle(from, to)
  from, to = normalize(from), normalize(to)
  local top, bottom = math.min(from.row, to.row), math.max(from.row, to.row)
  local left, right = math.min(from.col, to.col), math.max(from.col, to.col)
  if top == bottom or left == right then
    return M.line(from, to)
  end
  local result = {}
  for col = left, right do
    local char = (col == left or col == right) and "+" or "-"
    result[#result + 1] = point(top, col, char)
    result[#result + 1] = point(bottom, col, char)
  end
  for row = top + 1, bottom - 1 do
    result[#result + 1] = point(row, left, "|")
    result[#result + 1] = point(row, right, "|")
  end
  return deduplicate(result)
end

---Return the cells for an ellipse fitted inside the two corners.
function M.ellipse(from, to, options)
  from, to = normalize(from), normalize(to)
  options = options or {}
  local top, bottom = math.min(from.row, to.row), math.max(from.row, to.row)
  local left, right = math.min(from.col, to.col), math.max(from.col, to.col)
  local rx, ry = (right - left) / 2, (bottom - top) / 2
  if rx == 0 or ry == 0 then
    return M.line(from, to)
  end

  local cx, cy = (left + right) / 2, (top + bottom) / 2
  local aspect = tonumber(options.aspect_ratio) or 1
  local samples = math.max(24, math.ceil(2 * math.pi * math.max(rx, ry * aspect) * 2))
  local coordinates, seen = {}, {}
  for index = 0, samples - 1 do
    local angle = (index / samples) * 2 * math.pi
    local row = math.floor(cy + ry * math.sin(angle) + 0.5)
    local col = math.floor(cx + rx * math.cos(angle) + 0.5)
    local id = key(row, col)
    if not seen[id] then
      seen[id] = true
      coordinates[#coordinates + 1] = { row = row, col = col, angle = angle }
    end
  end

  local result = {}
  for _, value in ipairs(coordinates) do
    local tangent_row = ry * math.cos(value.angle)
    local tangent_col = -rx * math.sin(value.angle)
    local char
    if math.abs(tangent_col) > math.abs(tangent_row) * 2 then
      char = "-"
    elseif math.abs(tangent_row) > math.abs(tangent_col) * 2 then
      char = "|"
    elseif sign(tangent_row) == sign(tangent_col) then
      char = "\\"
    else
      char = "/"
    end
    result[#result + 1] = point(value.row, value.col, char)
  end
  return result
end

---Return every cell inside an axis-aligned region as an eraser point.
function M.erase(from, to)
  from, to = normalize(from), normalize(to)
  local result = {}
  for row = math.min(from.row, to.row), math.max(from.row, to.row) do
    for col = math.min(from.col, to.col), math.max(from.col, to.col) do
      result[#result + 1] = point(row, col, " ")
    end
  end
  return result
end

local function split_chars(value)
  if value == "" then
    return {}
  end
  return vim.fn.split(value, "\\zs")
end

---Apply cells to a buffer as one undoable change.
---@param bufnr integer
---@param points table[]
---@param options? table
function M.apply(bufnr, points, options)
  options = options or {}
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  vim.validate("bufnr", bufnr, "number")
  if not vim.api.nvim_buf_is_valid(bufnr) then
    error("artist: invalid buffer " .. bufnr)
  end
  if vim.bo[bufnr].modifiable == false then
    error("artist: buffer is not modifiable")
  end
  if #points == 0 then
    return
  end

  points = deduplicate(points)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local min_row, max_row
  for _, value in ipairs(points) do
    min_row = math.min(min_row or value.row, value.row)
    max_row = math.max(max_row or value.row, value.row)
  end
  local first = math.min(min_row, line_count)
  local lines = vim.api.nvim_buf_get_lines(bufnr, first - 1, math.min(max_row, line_count), false)
  while #lines < max_row - first + 1 do
    lines[#lines + 1] = ""
  end

  local rows = {}
  for _, value in ipairs(points) do
    local index = value.row - first + 1
    local chars = rows[index]
    if not chars then
      chars = split_chars(lines[index] or "")
      rows[index] = chars
    end
    while #chars < value.col do
      chars[#chars + 1] = " "
    end
    if options.overwrite or value.char == " " then
      chars[value.col] = value.char
    else
      chars[value.col] = merge_character(chars[value.col], value.char)
    end
  end
  for index, chars in pairs(rows) do
    lines[index] = table.concat(chars)
  end
  vim.api.nvim_buf_set_lines(bufnr, first - 1, math.min(max_row, line_count), false, lines)
end

M.merge_character = merge_character
M.deduplicate = deduplicate

return M
