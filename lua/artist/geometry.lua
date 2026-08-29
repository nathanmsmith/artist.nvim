local patch = require("artist.patch")

local M = {}

local octants = {
  { 2, 1, 1, 0, 1, 1 },
  { 1, 2, 1, 1, 0, 1 },
  { -1, 2, 0, 1, -1, 1 },
  { -2, 1, -1, 1, -1, 0 },
  { -2, -1, -1, 0, -1, -1 },
  { -1, -2, -1, -1, 0, -1 },
  { 1, -2, 0, -1, 1, -1 },
  { 2, -1, 1, -1, 1, 0 },
}

local directions = {
  { 1, 0, "-" },
  { 1, 1, "\\" },
  { 0, 1, "|" },
  { -1, 1, "/" },
  { -1, 0, "-" },
  { -1, -1, "\\" },
  { 0, -1, "|" },
  { 1, -1, "/" },
}

local default_arrows = { ">", false, "v", "L", "<", false, "^", false }

---@param value number
---@return integer
local function round(value)
  return math.floor(value + 0.5)
end

---@param position Artist.PositionLike
---@return Artist.Position
function M.normalize(position)
  assert(type(position) == "table", "artist: a position must be a table")
  local row = tonumber(position.row or position[1])
  local col = tonumber(position.col or position[2])
  assert(row and col, "artist: a position needs row and col")
  return { row = math.max(1, math.floor(row)), col = math.max(1, math.floor(col)) }
end

---@param row integer
---@param col integer
---@param character string
---@return Artist.Point
local function point(row, col, character)
  return { row = row, col = col, char = character }
end

---@param x1 integer
---@param y1 integer
---@param x2 integer
---@param y2 integer
---@return integer
local function octant(x1, y1, x2, y2)
  if x1 <= x2 then
    if y1 <= y2 then
      return x2 - x1 >= y2 - y1 and 1 or 2
    end
    return x2 - x1 >= -(y2 - y1) and 8 or 7
  elseif y1 <= y2 then
    return -(x2 - x1) >= y2 - y1 and 4 or 3
  end
  return -(x2 - x1) >= -(y2 - y1) and 5 or 6
end

---@param from Artist.PositionLike
---@param to Artist.PositionLike
---@return Artist.Position[]
local function coordinates_for_line(from, to)
  from, to = M.normalize(from), M.normalize(to)
  local x1, y1, x2, y2 = from.col, from.row, to.col, to.row
  local info = octants[octant(x1, y1, x2, y2)]
  local dfdx, dfdy = -(y2 - y1), x2 - x1
  local x, y, f = x1, y1, 0
  local q = info[1] * dfdx + info[2] * dfdy
  local result = { { row = y, col = x } }
  while x ~= x2 or y ~= y2 do
    local offset = q >= 0 and 3 or 5
    local sx, sy = info[offset], info[offset + 1]
    x, y = x + sx, y + sy
    f = f + sx * dfdx + sy * dfdy
    q = 2 * f + info[1] * dfdx + info[2] * dfdy
    result[#result + 1] = { row = y, col = x }
  end
  return result
end

---@param left Artist.Position
---@param right Artist.Position
---@return string
local function character_between(left, right)
  if right.col > left.col then
    if right.row < left.row then
      return "/"
    elseif right.row > left.row then
      return "\\"
    end
    return "-"
  elseif right.col < left.col then
    if right.row < left.row then
      return "\\"
    elseif right.row > left.row then
      return "/"
    end
    return "-"
  elseif right.row == left.row then
    return "o"
  end
  return "|"
end

---@param coordinates Artist.Position[]
---@param character? string
---@return Artist.Point[]
local function add_characters(coordinates, character)
  local result = {}
  if #coordinates == 1 then
    return { point(coordinates[1].row, coordinates[1].col, character or "o") }
  end
  for index, value in ipairs(coordinates) do
    local neighbor = index == 1 and coordinates[2] or coordinates[index - 1]
    result[index] = point(value.row, value.col, character or character_between(neighbor, value))
  end
  return result
end

---@param from Artist.Position
---@param to Artist.Position
---@return integer
local function find_direction(from, to)
  local dx, dy = to.col - from.col, to.row - from.row
  if dx >= 2 * math.abs(dy) then
    return 1
  elseif dy >= 2 * math.abs(dx) then
    return 3
  elseif -dx >= 2 * math.abs(dy) then
    return 5
  elseif -dy >= 2 * math.abs(dx) then
    return 7
  elseif dx >= 0 and dy >= 0 then
    return 2
  elseif dx <= 0 and dy >= 0 then
    return 4
  elseif dx <= 0 and dy <= 0 then
    return 6
  end
  return 8
end

---@param points Artist.Point[]
---@param from Artist.Position
---@param to Artist.Position
---@param options Artist.Options
---@return Artist.Point[]
local function arrowed(points, from, to, options)
  if #points == 0 then
    return points
  end
  if options.first_arrow then
    local direction = find_direction(to, from)
    points[1].char = (options.arrow_characters or default_arrows)[direction] or points[1].char
  end
  if options.second_arrow then
    local direction = find_direction(from, to)
    points[#points].char = (options.arrow_characters or default_arrows)[direction] or points[#points].char
  end
  return points
end

---@param from Artist.PositionLike
---@param to Artist.PositionLike
---@param options? Artist.Options
---@return Artist.Point[]
function M.line(from, to, options)
  options = options or {}
  from, to = M.normalize(from), M.normalize(to)
  return arrowed(add_characters(coordinates_for_line(from, to), options.line_character), from, to, options)
end

---@param from Artist.PositionLike
---@param to Artist.PositionLike
---@param options? Artist.Options
---@return Artist.Point[]
function M.straight_line(from, to, options)
  options = options or {}
  from, to = M.normalize(from), M.normalize(to)
  local direction = find_direction(from, to)
  local info = directions[direction]
  local length
  if direction == 1 or direction == 2 or direction == 8 then
    length = to.col - from.col + 1
  elseif direction == 4 or direction == 5 or direction == 6 then
    length = from.col - to.col + 1
  else
    length = math.abs(to.row - from.row) + 1
  end
  local result = {}
  for index = 0, length - 1 do
    result[#result + 1] =
      point(from.row + index * info[2], from.col + index * info[1], options.line_character or info[3])
  end
  local actual_to = result[#result] and { row = result[#result].row, col = result[#result].col } or from
  return arrowed(result, from, actual_to, options)
end

---@param point_lists Artist.Point[][]
---@return Artist.Point[]
local function combine(point_lists)
  local result, indexes = {}, {}
  for _, list in ipairs(point_lists) do
    for _, value in ipairs(list) do
      local id = value.row .. ":" .. value.col
      local index = indexes[id]
      if index then
        result[index].char = patch.intersection(value.char, result[index].char)
      else
        indexes[id] = #result + 1
        result[#result + 1] = vim.deepcopy(value)
      end
    end
  end
  return result
end

---@param from Artist.Position
---@param to Artist.Position
---@param character string
---@return Artist.Point[]
local function fill_rectangle(from, to, character)
  local result = {}
  for row = math.min(from.row, to.row) + 1, math.max(from.row, to.row) - 1 do
    for col = math.min(from.col, to.col) + 1, math.max(from.col, to.col) - 1 do
      result[#result + 1] = point(row, col, character)
    end
  end
  return result
end

---@param from Artist.PositionLike
---@param to Artist.PositionLike
---@param options? Artist.Options
---@return Artist.Point[]
function M.rectangle(from, to, options)
  options = options or {}
  from, to = M.normalize(from), M.normalize(to)
  local line_character = options.line_character
  if options.borderless and options.fill_character then
    line_character = options.fill_character
  end
  local edge_options = { line_character = line_character }
  local top_right = { row = from.row, col = to.col }
  local bottom_left = { row = to.row, col = from.col }
  local result = combine({
    M.straight_line(from, top_right, edge_options),
    M.straight_line(top_right, to, edge_options),
    M.straight_line(to, bottom_left, edge_options),
    M.straight_line(bottom_left, from, edge_options),
  })
  if options.fill_character then
    vim.list_extend(result, fill_rectangle(from, to, options.fill_character))
  end
  return result
end

---@param from Artist.PositionLike
---@param to Artist.PositionLike
---@param aspect_ratio? number
---@return Artist.Position from
---@return Artist.Position to
function M.squarify(from, to, aspect_ratio)
  from, to = M.normalize(from), M.normalize(to)
  local dx, dy = to.col - from.col, to.row - from.row
  local sx, sy = dx < 0 and -1 or 1, dy < 0 and -1 or 1
  local aspect = tonumber(aspect_ratio) or 1
  if math.abs(dx) > math.abs(dy) then
    return from, { row = from.row + round(math.abs(dx) * sy / aspect), col = to.col }
  end
  return from, { row = to.row, col = from.col + round(math.abs(dy) * sx * aspect) }
end

---@param from Artist.PositionLike
---@param to Artist.PositionLike
---@param options? Artist.Options
---@return Artist.Point[]
function M.square(from, to, options)
  options = options or {}
  local first, second = M.squarify(from, to, options.aspect_ratio)
  return M.rectangle(first, second, options)
end

---@param rx integer
---@param ry integer
---@return Artist.Position[]
local function ellipse_quadrant(rx, ry)
  local rx2, ry2 = rx * rx, ry * ry
  local two_rx2, two_ry2 = 2 * rx2, 2 * ry2
  local x, y, px, py = 0, ry, 0, two_rx2 * ry
  local result = { { col = x, row = y } }
  local p = round(ry2 - rx2 * ry + 0.25 * rx2)
  while px < py do
    x, px = x + 1, px + two_ry2
    if p < 0 then
      p = p + ry2 + px
    else
      y, py = y - 1, py - two_rx2
      p = p + ry2 + px - py
    end
    result[#result + 1] = { col = x, row = y }
  end
  p = round(ry2 * (x + 0.5) ^ 2 + rx2 * (y - 1) ^ 2 - rx2 * ry2)
  while y > 0 do
    y, py = y - 1, py - two_rx2
    if p > 0 then
      p = p + rx2 - py
    else
      x, px = x + 1, px + two_ry2
      p = p + rx2 - py + px
    end
    result[#result + 1] = { col = x, row = y }
  end
  return result
end

---@param quadrant Artist.Position[]
---@param options Artist.Options
---@return Artist.Point[]
local function mirror_ellipse(quadrant, options)
  local characterized = add_characters(quadrant, options.line_character)
  if not options.line_character and characterized[#characterized].char == "/" then
    characterized[#characterized].char = options.ellipse_right_character or ")"
  end
  local right = vim.deepcopy(characterized)
  for index = #characterized - 1, 1, -1 do
    local value = characterized[index]
    local character = value.char == "/" and "\\" or (value.char == "\\" and "/" or value.char)
    right[#right + 1] = point(-value.row, value.col, character)
  end
  local result = vim.deepcopy(right)
  for index = #right - 1, 2, -1 do
    local value = right[index]
    local character = value.char == "/" and "\\" or (value.char == "\\" and "/" or value.char)
    if character == (options.ellipse_right_character or ")") then
      character = options.ellipse_left_character or "("
    end
    result[#result + 1] = point(value.row, -value.col, character)
  end
  return result
end

---@param center Artist.Position
---@param rx integer
---@param ry integer
---@param options Artist.Options
---@return Artist.Point[]
local function ellipse_general(center, rx, ry, options)
  if ry == 0 and rx ~= 0 then
    local result = {}
    local width, left = math.max(math.abs(2 * rx) - 1, 0), center.col - math.abs(rx) + 1
    for offset = 0, width - 1 do
      result[#result + 1] = point(center.row, left + offset, options.line_character or "-")
    end
    return result
  end
  local relative = mirror_ellipse(ellipse_quadrant(rx, ry), options)
  local result = {}
  for _, value in ipairs(relative) do
    result[#result + 1] = point(center.row + value.row, center.col + value.col, value.char)
  end
  if options.fill_character then
    local boundary = {}
    for _, value in ipairs(result) do
      local bounds = boundary[value.row] or { value.col, value.col }
      bounds[1], bounds[2] = math.min(bounds[1], value.col), math.max(bounds[2], value.col)
      boundary[value.row] = bounds
    end
    for row, bounds in pairs(boundary) do
      for col = bounds[1] + 1, bounds[2] - 1 do
        result[#result + 1] = point(row, col, options.fill_character)
      end
    end
  end
  return result
end

---@param center Artist.PositionLike
---@param through Artist.PositionLike
---@param options? Artist.Options
---@return Artist.Point[]
function M.ellipse(center, through, options)
  options = options or {}
  center, through = M.normalize(center), M.normalize(through)
  local rx = round(math.abs(through.col - center.col) * math.sqrt(2))
  local ry = round(math.abs(through.row - center.row) * math.sqrt(2))
  if options.borderless and options.fill_character then
    options = vim.tbl_extend("force", options, { line_character = options.fill_character })
  end
  return ellipse_general(center, rx, ry, options)
end

---@param center Artist.PositionLike
---@param through Artist.PositionLike
---@param options? Artist.Options
---@return Artist.Point[]
function M.circle(center, through, options)
  options = options or {}
  center, through = M.normalize(center), M.normalize(through)
  local aspect = tonumber(options.aspect_ratio) or 1
  local width, height = math.abs(through.col - center.col), math.abs(through.row - center.row)
  local rx = round(math.sqrt(width * width + (aspect * height) ^ 2))
  local ry = round(rx / aspect)
  if options.borderless and options.fill_character then
    options = vim.tbl_extend("force", options, { line_character = options.fill_character })
  end
  return ellipse_general(center, rx, ry, options)
end

---@param from Artist.PositionLike
---@param to Artist.PositionLike
---@param character string
---@return Artist.Point[]
function M.region(from, to, character)
  from, to = M.normalize(from), M.normalize(to)
  local result = {}
  for row = math.min(from.row, to.row), math.max(from.row, to.row) do
    for col = math.min(from.col, to.col), math.max(from.col, to.col) do
      result[#result + 1] = point(row, col, character)
    end
  end
  return result
end

M.erase = M.region
M.find_direction = find_direction
M.directions = directions

return M
