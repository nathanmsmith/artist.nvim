vim.opt.runtimepath:prepend(vim.fn.getcwd())

_G.artist = require("artist")
artist._create_commands()
