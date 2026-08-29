if vim.g.loaded_artist_nvim then
  return
end
vim.g.loaded_artist_nvim = true

vim.api.nvim_set_hl(0, "ArtistPreview", { default = true, link = "Visual" })
require("artist")._create_commands()
