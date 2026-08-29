local M = {}

local definitions = {
  pen = { label = "Pen", kind = "continuous", shifted = "pen_line" },
  pen_line = { label = "Pen Line", kind = "continuous", shifted = "pen", arrows = true },
  line = { label = "Line", kind = "two_point", shifted = "straight_line", arrows = true, geometry = "line" },
  straight_line = {
    label = "Straight Line",
    kind = "two_point",
    shifted = "line",
    arrows = true,
    geometry = "straight_line",
  },
  rectangle = { label = "Rectangle", kind = "two_point", shifted = "square", fill = true, geometry = "rectangle" },
  square = { label = "Square", kind = "two_point", shifted = "rectangle", fill = true, geometry = "square" },
  poly_line = { label = "Poly-line", kind = "poly_point", shifted = "straight_poly_line", arrows = true },
  straight_poly_line = { label = "Straight Poly-line", kind = "poly_point", shifted = "poly_line", arrows = true },
  ellipse = { label = "Ellipse", kind = "two_point", shifted = "circle", fill = true, geometry = "ellipse" },
  circle = { label = "Circle", kind = "two_point", shifted = "ellipse", fill = true, geometry = "circle" },
  text_see_through = { label = "Text (see-through)", kind = "one_point", shifted = "text_overwrite" },
  text_overwrite = { label = "Text (overwrite)", kind = "one_point", shifted = "text_see_through" },
  spray = { label = "Spray", kind = "continuous", shifted = "spray_radius" },
  spray_radius = { label = "Spray Radius", kind = "two_point", shifted = "spray" },
  erase_character = { label = "Erase Character", kind = "continuous", shifted = "erase_rectangle" },
  erase_rectangle = { label = "Erase Rectangle", kind = "two_point", shifted = "erase_character" },
  vaporize_line = { label = "Vaporize Line", kind = "one_point", shifted = "vaporize_lines" },
  vaporize_lines = { label = "Vaporize Connected Lines", kind = "one_point", shifted = "vaporize_line" },
  cut_rectangle = { label = "Cut Rectangle", kind = "two_point", shifted = "cut_square" },
  cut_square = { label = "Cut Square", kind = "two_point", shifted = "cut_rectangle" },
  copy_rectangle = { label = "Copy Rectangle", kind = "two_point", shifted = "copy_square" },
  copy_square = { label = "Copy Square", kind = "two_point", shifted = "copy_rectangle" },
  paste = { label = "Paste", kind = "one_point", shifted = "paste" },
  flood_fill = { label = "Flood Fill", kind = "one_point", shifted = "flood_fill" },
}

local aliases = {
  freehand = "pen_line",
  erase = "erase_rectangle",
  sline = "straight_line",
  polyline = "poly_line",
  straight_polyline = "straight_poly_line",
  text_through = "text_see_through",
  text_overwrite = "text_overwrite",
  spray_can = "spray",
  flood = "flood_fill",
}

function M.resolve(name)
  name = tostring(name or ""):lower():gsub("[%s%-]+", "_")
  name = aliases[name] or name
  return definitions[name] and name or nil
end

function M.get(name)
  local resolved = M.resolve(name)
  return resolved and definitions[resolved] or nil
end

function M.names()
  local result = vim.tbl_keys(definitions)
  table.sort(result)
  return result
end

function M.shifted(name)
  local operation = M.get(name)
  return operation and operation.shifted or nil
end

M.definitions = definitions
M.aliases = aliases

return M
