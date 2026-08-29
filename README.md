# artist.nvim

[Artist mode](https://github.com/emacs-mirror/emacs/blob/master/lisp/textmodes/artist.el), for Neovim.

Draw ASCII diagrams directly in any buffer. Artist mode supports mouse and
keyboard drawing, keeps its mappings buffer-local, previews shapes before they
are committed, and leaves every completed shape as a single undoable edit.

```text
    +------------------+
    |                  |
----+-----------       |
    |          |       |
    +----------+-------+
```

## Installation

Add the plugin with Neovim's built-in package manager in `init.lua`:

```lua
vim.pack.add({
  "https://github.com/nathom/artist.nvim",
})
```

### Local checkout

The built-in manager can also install from a local Git repository:

```lua
vim.pack.add({
  {
    src = vim.fn.expand("~/Developer/artist.nvim"),
    name = "artist.nvim",
  },
})
```

Replace the path with the location of your checkout. `vim.pack` clones the
repository into Neovim's managed package directory, so commit local changes
before updating the installed copy. After making a new commit, run
`:lua vim.pack.update({ "artist.nvim" })`, confirm the update with `:write`,
and restart Neovim.

### Configuration

Configuration is optional; the defaults are:

```lua
require("artist").setup({
  tool = "line",
  aspect_ratio = 1,
  pen_character = "*",
  mappings = true,
})
```

## Usage

Run `:Artist` to toggle Artist mode in the current buffer. Select a tool with
`:ArtistTool line`, `rectangle`, `ellipse`, `freehand`, or `erase`, then drag
the left mouse button to draw. Intersecting horizontal and vertical lines are
joined with `+`; intersecting diagonals use `X`.

Artist mode installs these normal-mode buffer mappings:

| Mapping | Action |
| --- | --- |
| left mouse drag | Preview and draw the selected tool |
| `<CR>` | Place the first corner/end point, then draw to the cursor |
| `<C-c>` | Cancel the current preview |

The cursor can move past the end of a line or below the end of the buffer while
Artist mode is active. Artist restores `virtualedit`, `wrap`, `mouse`, and any
displaced buffer-local mappings when the mode is disabled.

Commands:

| Command | Action |
| --- | --- |
| `:Artist` / `:ArtistToggle` | Toggle Artist mode |
| `:ArtistEnable` | Enable Artist mode |
| `:ArtistDisable` | Disable Artist mode |
| `:ArtistTool {tool}` | Change the active tool |
| `:Artist {tool}` | Change the tool using the short form |

For keyboard-only drawing, move the cursor to one endpoint and press `<CR>`,
move to the other endpoint, and press `<CR>` again. The freehand tool places
the configured pen character on each `<CR>` press. The erase tool removes the
entire rectangle between the two selected points.

## Lua API

```lua
local artist = require("artist")

artist.enable(0)                  -- 0 or nil means the current buffer
artist.set_tool("rectangle")
artist.get_tool()                 -- "rectangle"
artist.is_enabled()               -- true
artist.cancel()                   -- discard an active preview
artist.disable()

-- Drawing without enabling the interactive mode; coordinates are one-based.
artist.draw("line", { row = 2, col = 3 }, { row = 2, col = 12 })
artist.draw("ellipse", { 4, 3 }, { 10, 20 }, { aspect_ratio = 1 })
```

Completed shapes update the buffer through the Neovim API, so normal undo and
redo work as expected. Artist mode also emits the `User` events
`ArtistEnabled`, `ArtistDisabled`, and `ArtistToolChanged`.

## Development

The test suite has no third-party dependencies. Run it with:

```sh
make test
```

This starts Neovim with no user configuration or ShaDa file and executes
`tests/artist_spec.lua`. `make check` additionally checks formatting with
[StyLua](https://github.com/JohnnyMorganz/StyLua).
