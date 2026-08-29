local M = {}

local Grid = {}
Grid.__index = Grid

local function split_codepoints(text)
  if text == "" then
    return {}
  end
  return vim.fn.split(text, "\\zs")
end

local function decode_line(text, tabstop)
  local cells = {}
  for _, character in ipairs(split_codepoints(text)) do
    if character == "\t" then
      local width = tabstop - (#cells % tabstop)
      for _ = 1, width do
        cells[#cells + 1] = " "
      end
    else
      local index = #cells
      while index > 0 and type(cells[index]) == "table" do
        index = index - 1
      end
      local combined = index > 0
        and type(cells[index]) == "string"
        and vim.fn.strdisplaywidth(cells[index] .. character) <= vim.fn.strdisplaywidth(cells[index])
      if combined then
        cells[index] = cells[index] .. character
      else
        local width = math.max(1, vim.fn.strdisplaywidth(character))
        local lead = #cells + 1
        cells[lead] = character
        for _ = 2, width do
          cells[#cells + 1] = { continuation = true, lead = lead }
        end
      end
    end
  end
  return cells
end

local function copy_row(row)
  local result = {}
  for index, value in ipairs(row or {}) do
    result[index] = type(value) == "table" and vim.deepcopy(value) or value
  end
  return result
end

function Grid.new(lines, options)
  options = options or {}
  local self = setmetatable({ rows = {}, original = vim.deepcopy(lines), tabstop = options.tabstop or 8 }, Grid)
  for index, line in ipairs(lines) do
    self.rows[index] = decode_line(line, self.tabstop)
  end
  return self
end

function Grid.from_buffer(bufnr)
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  return Grid.new(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { tabstop = vim.bo[bufnr].tabstop })
end

function Grid:clone()
  local result = setmetatable({ rows = {}, original = vim.deepcopy(self.original), tabstop = self.tabstop }, Grid)
  for index, row in ipairs(self.rows) do
    result.rows[index] = copy_row(row)
  end
  return result
end

function Grid:height()
  return #self.rows
end

function Grid:width(row)
  return #(self.rows[row] or {})
end

function Grid:get(row, col)
  if row < 1 or col < 1 then
    return nil
  end
  local cells = self.rows[row]
  local value = cells and cells[col]
  if type(value) == "table" and value.continuation then
    return cells[value.lead]
  end
  return value or " "
end

local function clear_glyph(cells, col)
  local value = cells[col]
  local lead = type(value) == "table" and value.lead or col
  if type(cells[lead]) ~= "string" then
    return
  end
  local width = math.max(1, vim.fn.strdisplaywidth(cells[lead]))
  cells[lead] = " "
  for index = lead + 1, lead + width - 1 do
    if type(cells[index]) == "table" and cells[index].lead == lead then
      cells[index] = " "
    end
  end
end

function Grid:set(row, col, character)
  assert(row >= 1 and col >= 1, "artist: grid coordinates are one-based")
  character = character == nil and " " or tostring(character)
  while #self.rows < row do
    self.rows[#self.rows + 1] = {}
  end
  local cells = self.rows[row]
  while #cells < col do
    cells[#cells + 1] = " "
  end
  clear_glyph(cells, col)
  local width = math.max(1, vim.fn.strdisplaywidth(character))
  for index = col + 1, col + width - 1 do
    if cells[index] ~= nil then
      clear_glyph(cells, index)
    end
  end
  cells[col] = character
  for index = col + 1, col + width - 1 do
    cells[index] = { continuation = true, lead = col }
  end
end

function Grid:render_row(row, trim)
  local cells = self.rows[row] or {}
  local output = {}
  for _, value in ipairs(cells) do
    if type(value) ~= "table" then
      output[#output + 1] = value
    end
  end
  local text = table.concat(output)
  return trim and text:gsub("%s+$", "") or text
end

function Grid:render(trim)
  local lines = {}
  for row = 1, math.max(1, #self.rows) do
    lines[row] = self:render_row(row, trim)
  end
  return lines
end

M.Grid = Grid
M.new = Grid.new
M.from_buffer = Grid.from_buffer
M.decode_line = decode_line

return M
