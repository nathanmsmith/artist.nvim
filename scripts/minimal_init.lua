local root = vim.fn.getcwd()

if vim.env.ARTIST_COVERAGE == "1" then
  package.path = root
    .. "/deps/luarocks/share/lua/5.1/?.lua;"
    .. root
    .. "/deps/luarocks/share/lua/5.1/?/init.lua;"
    .. package.path
  package.cpath = root .. "/deps/luarocks/lib/lua/5.1/?.so;" .. package.cpath
  local luacov = require("luacov")
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = luacov.shutdown,
  })
end

vim.opt.runtimepath:prepend(root .. "/deps/mini.test")
vim.opt.runtimepath:prepend(root)

require("mini.test").setup({
  collect = { emulate_busted = false },
})
