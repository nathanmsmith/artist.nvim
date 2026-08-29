local grid = require("artist.grid")

local M = {}
local Patch = {}
Patch.__index = Patch

local function key(row, col)
  return row .. ":" .. col
end

function M.intersection(incoming, existing)
  if (existing == "-" and incoming == "|") or (existing == "|" and incoming == "-") then
    return "+"
  end
  if existing == "+" and (incoming == "-" or incoming == "|") then
    return "+"
  end
  if (existing == "\\" and incoming == "/") or (existing == "/" and incoming == "\\") then
    return "X"
  end
  if existing == "X" and (incoming == "/" or incoming == "\\") then
    return "X"
  end
  return incoming
end

function M.unintersection(line_character, existing, erase_character)
  if line_character == "-" and existing == "+" then
    return "|"
  elseif line_character == "|" and existing == "+" then
    return "-"
  elseif line_character == "\\" and existing == "X" then
    return "/"
  elseif line_character == "/" and existing == "X" then
    return "\\"
  elseif line_character == existing then
    return erase_character or " "
  end
  return existing
end

function Patch.new(source, options)
  options = options or {}
  if type(source) == "number" then
    source = grid.from_buffer(source)
  end
  return setmetatable({
    grid = source:clone(),
    original = source,
    changes = {},
    indexes = {},
    trim = options.trim_line_endings ~= false,
  }, Patch)
end

function Patch:get(row, col)
  return self.grid:get(row, col)
end

function Patch:set(row, col, character, options)
  options = options or {}
  if row < 1 or col < 1 then
    return
  end
  local before = self.grid:get(row, col)
  local after = options.intersect and M.intersection(character, before) or character
  self.grid:set(row, col, after)
  local id = key(row, col)
  local index = self.indexes[id]
  if index then
    self.changes[index].char = after
  else
    self.indexes[id] = #self.changes + 1
    self.changes[#self.changes + 1] = { row = row, col = col, before = before, char = after }
  end
end

function Patch:add(points, options)
  for _, value in ipairs(points or {}) do
    self:set(value.row, value.col, value.char, options)
  end
  return self
end

function Patch:is_empty()
  for _, change in ipairs(self.changes) do
    if change.before ~= change.char then
      return false
    end
  end
  return true
end

function Patch:commit(bufnr)
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  if self:is_empty() then
    return false
  end
  if not vim.api.nvim_buf_is_valid(bufnr) then
    error("artist: invalid buffer " .. tostring(bufnr))
  end
  if not vim.bo[bufnr].modifiable then
    error("artist: buffer is not modifiable")
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local changed_rows = {}
  local maximum_row = #lines
  for _, change in ipairs(self.changes) do
    if change.before ~= change.char then
      changed_rows[change.row] = true
      maximum_row = math.max(maximum_row, change.row)
    end
  end
  while #lines < maximum_row do
    lines[#lines + 1] = ""
  end
  for row in pairs(changed_rows) do
    lines[row] = self.grid:render_row(row, self.trim)
  end
  if vim.deep_equal(lines, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) then
    return false
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return true
end

M.Patch = Patch
M.new = Patch.new

return M
