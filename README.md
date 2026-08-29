# artist.nvim

[![CI](https://github.com/nathanmsmith/artist.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/nathanmsmith/artist.nvim/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/nathanmsmith/artist.nvim/graph/badge.svg)](https://codecov.io/gh/nathanmsmith/artist.nvim)

[GNU Emacs Artist mode](https://github.com/emacs-mirror/emacs/blob/f4f249a2249a7047ba41a659b8fcdcd7e1caf4e0/lisp/textmodes/artist.el), faithfully ported to Neovim.

Artist draws ASCII diagrams directly in a buffer. It uses display-cell
coordinates, so tabs, combining characters, double-width characters, virtual
columns, and rows below the end of the buffer behave consistently. Previews
are extmarks; a completed operation is committed as one undo entry.

```text
    +------------------+
    |                  |
----+-----------       |
    |          |       |
    +----------+-------+
```

The compatibility target is Artist from Emacs commit
`f4f249a2249a7047ba41a659b8fcdcd7e1caf4e0`; the corresponding source is
checked in as `artist.el`. artist.nvim supports Neovim 0.10 and newer and is
licensed under GPLv3.

## Installation

```lua
vim.pack.add({ "https://github.com/nathom/artist.nvim" })
```

For another package manager, install the repository normally and call
`require("artist").setup()` if you want to change defaults.

## Operations

Run `:Artist` to toggle the mode and `:ArtistTool {operation}` to select an
operation. `:ArtistPicker` opens `vim.ui.select`; `:ArtistShift` selects the
active operation's shifted counterpart. `:ArtistSet {setting} {value}` changes
a setting for the current buffer-local session.

| Drawing | Shifted variant |
| --- | --- |
| `pen` | `pen_line` |
| `line` | `straight_line` |
| `rectangle` | `square` |
| `poly_line` | `straight_poly_line` |
| `ellipse` | `circle` |
| `text_see_through` | `text_overwrite` |
| `spray` | `spray_radius` |
| `erase_character` | `erase_rectangle` |
| `vaporize_line` | `vaporize_lines` |
| `cut_rectangle` | `cut_square` |
| `copy_rectangle` | `copy_square` |
| `paste` | `paste` |
| `flood_fill` | `flood_fill` |

The old names `freehand` and `erase` remain aliases for `pen_line` and
`erase_rectangle`.

Mouse operations use left drag. Shift-left drag invokes the shifted variant.
Toggle Artist with `gA` (when it is unused), then use these buffer-local mappings:

| Mapping | Action |
| --- | --- |
| left drag / shift-left drag | Preview the normal / shifted operation |
| middle or right click | Open the operation picker |
| `<CR>` | Set a point, apply a one-point operation, or add a poly-line point |
| counted `<CR>` / `<C-CR>` | Finish a poly-line |
| `b/B`, `l/L`, `m/M`, `r/R`, `e/E`, `s/S`, `t/T` | Paired drawing tools (lowercase / shifted) |
| `x/X`, `v/V`, `d/D`, `y/Y`, `p`, `f` | Erase, vaporize, cut, copy, paste, and fill tools |
| `h/j/k`, arrows, `C-b/C-n/C-p/C-f` | Move and update/draw; use `<Right>` or `C-f` rightward |
| `[a` / `]a`, `~` | Previous / next tool and shifted counterpart |
| `?`, `o` | Toggle the key palette / open its options menu |
| `<` / `>` | Toggle the first / second arrow endpoint |
| `<Esc>` / `<C-c>` | Cancel without changing the buffer or undo history |
| `<C-c><C-c>` / `gA` | Exit Artist mode |

Set `mouse_wheel = true` to cycle operations with the mouse wheel. Every
displaced buffer mapping and the `virtualedit`, `wrap`, `winbar`,
`winhighlight`, and global `mouse` options are restored on exit.

## Configuration

```lua
require("artist").setup({
  tool = "pen_line",
  aspect_ratio = 1,
  rubber_banding = true,
  first_character = "1",         -- endpoint markers without rubber banding
  second_character = "2",

  line_character = nil,          -- nil selects - | / \\ by direction
  fill_character = nil,
  default_fill_character = ".",
  erase_character = " ",
  trim_line_endings = true,
  borderless_shapes = false,

  first_arrow = false,
  second_arrow = false,
  arrow_characters = { ">", false, "v", "L", "<", false, "^", false },
  ellipse_left_character = "(",
  ellipse_right_character = ")",

  flood_fill_right_boundary = "window_width", -- or a display column
  fill_column = 80,               -- used by the "fill_column" boundary
  flood_fill_incremental = false,
  vaporize_fuzziness = 1,

  spray_interval = 0.2,
  spray_radius = 4,
  spray_characters = { " ", ".", "-", "+", "m", "%", "*", "#" },
  spray_initial_character = ".",
  timer_factory = nil,            -- injectable libuv-compatible timer

  text_renderer = nil,           -- function(text, options) -> string[]
  figlet_executable = "figlet",
  figlet_font = "standard",
  rectangle_register = '"',     -- false disables register interop

  mappings = true,
  keymaps = {},                 -- per-action mapping overrides, or false to disable
  show_palette_on_enable = true,
  mouse_wheel = false,
  winbar = true,
  transparent_selection = true,
})
```

`text_renderer` is the portable extension point. With no renderer, Artist
uses Figlet when installed and falls back to unrendered text. Spray tests can
inject `rng(min, max)` per operation and a libuv-compatible `timer_factory`;
applications can change the radius through the shifted radius operation.
Rectangle copies are retained internally and also written blockwise to
`rectangle_register`.

Artist shows a short floating key palette on entry. Set
`show_palette_on_enable = false` to suppress it; `?` and `:ArtistPalette`
remain available. `mappings = false`, `g:no_plugin_maps`, or
`g:artist_no_mappings` suppress default concrete mappings, but commands and
the stable `<Plug>(artist-toggle)`, `<Plug>(artist-enable)`,
`<Plug>(artist-disable)`, `<Plug>(artist-palette)`,
`<Plug>(artist-next-tool)`, `<Plug>(artist-previous-tool)`,
`<Plug>(artist-shift-tool)`, and `<Plug>(artist-tool-{operation})` targets
remain available.

## Lua API

```lua
local artist = require("artist")

artist.enable(0)
artist.set_tool("rectangle")
artist.shift_tool()
artist.toggle_arrow("first")
artist.finish()
artist.cancel()
artist.disable()

-- Direct, atomic operations. Coordinates are one-based display cells.
artist.draw("line", { row = 2, col = 3 }, { row = 2, col = 12 })
artist.draw("flood_fill", { 4, 6 }, nil, { fill_character = "." })
artist.draw("text_see_through", { 8, 1 }, nil, { text = "hello" })
```

The public `artist.tools` list contains all 24 operations. Mode changes emit
the `ArtistEnabled`, `ArtistDisabled`, and `ArtistToolChanged` `User` events.

## Neovim equivalents and divergences

- Extmark overlays replace Emacs rubber-band buffer edits, so cancellation is
  history-free.
- A configurable blockwise Neovim register replaces `rect.el` integration.
- A winbar and `vim.ui.select` picker replace the mode-line, toolbar, and popup
  menu.
- Picture mode, X pointer shapes, and Emacs input queue display updates have
  no direct Neovim equivalent. `flood_fill_incremental` is accepted for
  compatibility but commits atomically after the patch is complete.

## Development

```sh
mise install
make test
make check
```

The first test run downloads the pinned `mini.test` dependency into the
ignored `deps/` directory. Tests are grouped by module and behavior, with
per-case setup and cleanup; stateful editor integration cases run in a fresh
child Neovim. Run one file while iterating with:

```sh
make test-file FILE=tests/test_grid.lua
```

`make check` runs StyLua, LuaLS diagnostics, and the full test suite. Normal
tests use checked-in fixtures and do not require Emacs or Figlet. See
`tests/oracle/README.md` to regenerate differential fixtures with Emacs.

To compute line coverage for the plugin code, install LuaRocks and run:

```sh
make coverage
```

This installs the pinned LuaCov version under `deps/`, instruments both the
test runner and child Neovim processes, and writes the detailed results to
`luacov.report.out`.
