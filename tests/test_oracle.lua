local H = require("tests.helpers")

local T = H.new_set()

local fixture_file = assert(io.open(vim.fn.getcwd() .. "/tests/fixtures/artist.json", "r"))
local fixtures = vim.json.decode(fixture_file:read("*a"))
fixture_file:close()

for _, fixture in ipairs(fixtures) do
  T["matches Emacs oracle: " .. fixture.name] = function()
    H.artist.draw(fixture.operation, fixture.from, fixture.to)
    H.eq(H.lines(), fixture.lines)
  end
end

return T
