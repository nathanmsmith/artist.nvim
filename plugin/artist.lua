if vim.g.loaded_artist_nvim then
  return
end
vim.g.loaded_artist_nvim = true

vim.api.nvim_set_hl(0, "ArtistPreview", { default = true, link = "Visual" })
vim.api.nvim_set_hl(0, "ArtistMode", { default = true, link = "ModeMsg" })
vim.api.nvim_set_hl(0, "ArtistTool", { default = true, link = "IncSearch" })
vim.api.nvim_set_hl(0, "ArtistHint", { default = true, link = "Comment" })
require("artist")._create_commands()
