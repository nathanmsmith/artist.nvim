local geometry = require("artist.geometry")
local grid = require("artist.grid")
local patch = require("artist.patch")

local M = {}

function M.line(from, to, options)
  return geometry.line(from, to, options)
end

function M.straight_line(from, to, options)
  return geometry.straight_line(from, to, options)
end

function M.rectangle(from, to, options)
  return geometry.rectangle(from, to, options)
end

function M.square(from, to, options)
  return geometry.square(from, to, options)
end

function M.ellipse(from, to, options)
  return geometry.ellipse(from, to, options)
end

function M.circle(from, to, options)
  return geometry.circle(from, to, options)
end

function M.erase(from, to, options)
  return geometry.region(from, to, (options and options.erase_character) or " ")
end

function M.merge_character(existing, incoming)
  return patch.intersection(incoming, existing)
end

function M.unmerge_character(line_character, existing, erase_character)
  return patch.unintersection(line_character, existing, erase_character)
end

function M.deduplicate(points)
  local result, indexes = {}, {}
  for _, value in ipairs(points or {}) do
    local id = value.row .. ":" .. value.col
    local index = indexes[id]
    if index then
      result[index].char = patch.intersection(value.char, result[index].char)
    else
      indexes[id] = #result + 1
      result[#result + 1] = vim.deepcopy(value)
    end
  end
  return result
end

---Apply display-cell changes to a buffer as one undoable transaction.
function M.apply(bufnr, points, options)
  options = options or {}
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  local transaction = patch.new(grid.from_buffer(bufnr), options)
  transaction:add(points, { intersect = not options.overwrite })
  transaction:commit(bufnr)
  return transaction
end

M.grid = grid
M.patch = patch

return M
