local root = vim.fn.getcwd()

vim.opt.runtimepath:prepend(root .. "/deps/mini.test")
vim.opt.runtimepath:prepend(root)

require("mini.test").setup({
  collect = { emulate_busted = false },
})
