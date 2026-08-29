if vim.g.loaded_artist_nvim then
  return
end
vim.g.loaded_artist_nvim = true

local function set_highlights()
  vim.api.nvim_set_hl(0, "ArtistPreview", { default = true, link = "Visual" })
  vim.api.nvim_set_hl(0, "ArtistMode", { default = true, link = "ModeMsg" })
  vim.api.nvim_set_hl(0, "ArtistTool", { default = true, link = "IncSearch" })
  vim.api.nvim_set_hl(0, "ArtistHint", { default = true, link = "Comment" })
  vim.api.nvim_set_hl(0, "ArtistVisual", { default = true, bg = "NONE" })
end

set_highlights()
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("artist.nvim.highlights", { clear = true }),
  callback = set_highlights,
})
require("artist")._create_commands()
