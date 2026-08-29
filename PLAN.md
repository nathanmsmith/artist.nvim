# Vim-Native Keybindings and Key Palette Plan

## Goal

Replace Artist's Emacs-derived keyboard shortcuts with a compact, discoverable
Vim-native interface. Entering the mode should be memorable, changing tools
should take one key, related tools should form lowercase/uppercase pairs, and
the complete interface should be visible without consulting the help file.

The new interface remains modal and buffer-local. Artist may deliberately
displace Normal-mode keys while it is enabled, but every displaced mapping
must be restored exactly when the mode is disabled.

## Entering and Leaving Artist Mode

Use `gA` as the default global toggle for Artist mode. It has no built-in
meaning in clean Neovim and provides a short mnemonic without occupying the
user's leader namespace.

- `gA` enables Artist in the current buffer when disabled and disables it when
  enabled.
- `<C-c><C-c>` remains an in-mode exit mapping.
- `<Plug>(artist-toggle)` is the stable public target behind `gA`.
- Also expose `<Plug>(artist-enable)` and `<Plug>(artist-disable)` for users who
  prefer explicit mappings.
- Install `gA` only when that key is not already mapped. Never replace an
  existing user mapping.
- Do not install the concrete default when `g:no_plugin_maps`,
  `g:artist_no_mappings`, or `mappings = false` disables default mappings.
- Commands remain available regardless of mapping configuration.

## Tool Keymap

Tool mappings are buffer-local single characters. A lowercase key selects the
base tool and its uppercase form selects the shifted variant. The order below
is both the display order in the palette and the traversal order for tool
cycling.

| Key | Tool | Key | Shifted tool |
| --- | --- | --- | --- |
| `b` | Pen | `B` | Pen Line |
| `l` | Line | `L` | Straight Line |
| `m` | Poly-line | `M` | Straight Poly-line |
| `r` | Rectangle | `R` | Square |
| `e` | Ellipse | `E` | Circle |
| `s` | Spray | `S` | Spray Radius |
| `t` | Text (see-through) | `T` | Text (overwrite) |
| `x` | Erase Character | `X` | Erase Rectangle |
| `v` | Vaporize Line | `V` | Vaporize Connected Lines |
| `d` | Cut Rectangle | `D` | Cut Square |
| `y` | Copy Rectangle | `Y` | Copy Square |
| `p` | Paste | | |
| `f` | Flood Fill | | |

`b` is the mnemonic for brush, leaving `p` consistent with Vim's paste
vocabulary. Likewise, `d`, `y`, `p`, and `x` intentionally echo Vim's delete,
yank, paste, and character-delete vocabulary.

Lowercase `l` is deliberately reassigned from rightward movement to Line.
`h`, `j`, and `k` continue to move left, down, and up. Arrow keys remain
available in all four directions, so `<Right>` is the unambiguous rightward
movement key. Existing `C-b/C-n/C-p/C-f` movement aliases remain available.

Each tool must have an explicit public target named
`<Plug>(artist-tool-{operation})`, for example
`<Plug>(artist-tool-line)` and `<Plug>(artist-tool-straight-line)`.

## Tool Navigation and Core Controls

Adopt the following additional buffer-local mappings:

| Mapping | Action |
| --- | --- |
| `[a` | Select the previous tool |
| `]a` | Select the next tool |
| `~` | Select the current tool's shifted counterpart |
| `?` | Toggle the main key palette |
| `o` | Open the transient options palette |
| `<CR>` | Set or apply a point |
| counted `<CR>` / `<C-CR>` | Finish a poly-line |
| `h/j/k`, arrows, `C-b/C-n/C-p/C-f` | Move and update/draw the active operation |
| `<` / `>` | Toggle the first / second arrow endpoint |
| `<Esc>` / `<C-c>` | Cancel the current drawing or preview, but remain in Artist mode |
| `<C-c><C-c>` / `gA` | Exit Artist mode |

`[a` and `]a` follow the bracket-pair convention popularized by
vim-unimpaired. They accept counts: `3]a` advances three entries and `2[a`
moves back two. Cycling wraps and follows the exact tool order shown in the
tool table and floating palette, not the registry's alphabetical order.

Changing tools by any route retains the current behavior of cancelling an
unfinished operation before selecting the new tool.

Expose stable `<Plug>` targets for every action, using explicit names such as
`<Plug>(artist-next-tool)`, `<Plug>(artist-shift-tool)`, and
`<Plug>(artist-palette)`.

## Floating Key Palette

Implement a native Neovim floating window rather than depending on
which-key.nvim.

- Show the main palette automatically after Artist mode is enabled.
- Position it at the bottom center of the editor so it does not obscure the
  drawing cursor.
- Make it non-focusable and arrange entries into responsive columns.
- Show the tool keymap and core mode controls in distinct, readable groups.
- Highlight the active tool and update the highlight if the tool changes while
  the palette is visible.
- Close the palette after the first mapped tool or action key.
- Make `?` toggle the palette at any time.
- Close and clean up the floating window on disable, buffer/window changes, or
  invalidation of its owning session.
- Keep the existing winbar as the persistent compact indication of Artist
  mode, active tool, and arrow state after the palette closes.

Add `show_palette_on_enable = true` to the default configuration. When false,
the automatic palette is suppressed, but `?`, `:ArtistPalette`, and
`<Plug>(artist-palette)` continue to open it manually.

The implementation must behave safely when `enable()` targets a buffer that
is not displayed in the current window: do not steal focus or create a palette
over an unrelated buffer.

## Options Palette

`o` replaces the main palette with a transient options menu. The next valid
key performs the corresponding action, then closes the menu. `<Esc>` closes it
without changing anything.

| Key | Option action |
| --- | --- |
| `e` | Choose the erase character |
| `f` | Choose the fill character |
| `l` | Choose the line character |
| `r` | Toggle rubber-banding |
| `t` | Toggle trailing-whitespace trimming |
| `s` | Toggle borderless shapes |

These keys preserve the useful mnemonics from the old Emacs-prefix mappings
without retaining the prefix itself. Commands such as `:ArtistSet` remain
available for all settings, including settings not represented in this small
menu.

Expose public targets for opening the options palette and for each option
action.

## Mapping Configuration and Compatibility

Keep `mappings` as the master boolean switch and add a `keymaps` table for
per-action overrides. Defaults are merged by action name, not by left-hand
side, so moving an action also removes its old concrete default.

For example:

```lua
require("artist").setup({
  keymaps = {
    line = "q",
    straight_line = "Q",
    palette = false,
  },
})
```

A value of `false` disables that concrete action mapping. `<Plug>` targets and
commands remain available when defaults are disabled so users can construct a
fully custom interface.

While Artist mode is active, its concrete single-key mappings deliberately
override global and buffer-local mappings. Save displaced buffer-local
mappings before installation and restore them exactly on exit; global
mappings naturally become visible again after the Artist buffer-local mapping
is removed.

Remove the old `C-c C-a ...` operation and setting shortcuts. The project has
no tagged release requiring a compatibility period, and retaining two complete
interfaces would add ambiguity to the palette and documentation. Preserve
`<C-c>` for cancellation and `<C-c><C-c>` for exit.

## Implementation Work

1. Define one ordered, data-driven key specification containing action names,
   concrete defaults, labels, tool names, shifted relationships, palette
   groups, and cycle order. Avoid duplicating the tool order across mapping,
   palette, and cycling code.
2. Add global `<Plug>` mappings and conditionally install `gA`, honoring
   existing mappings and all mapping-disable controls.
3. Replace the Emacs-prefixed tool definitions with the single-key mappings,
   remove `l` from keyboard movement, add `<Esc>`, `[a`/`]a`, `~`, `?`, and
   `o`, and preserve the existing mapping save/restore guarantees.
4. Extend cycling to accept `vim.v.count1` and traverse the ordered key
   specification.
5. Implement the main and options floating palettes with dedicated lifecycle
   helpers. Ensure every mapped action closes or transitions the palette as
   specified.
6. Add `show_palette_on_enable`, `keymaps`, and any palette state to the public
   types and option validation.
7. Add `:ArtistPalette` and document all new `<Plug>` targets.
8. Update README and `doc/artist.txt`, removing the old prefix table and
   documenting rightward keyboard movement through `<Right>` or `<C-f>`.

## Verification

Add integration coverage for at least the following:

- `gA` toggles a session and is not installed over an existing mapping.
- `g:no_plugin_maps`, `g:artist_no_mappings`, and `mappings = false` suppress
  the appropriate concrete defaults while leaving commands and `<Plug>`
  targets usable.
- Every single-key tool mapping selects the expected registry operation.
- Uppercase keys select the declared shifted variants.
- `l` selects Line; `<Right>` still moves and draws rightward.
- `[a` and `]a` wrap, follow palette order, and honor counts.
- `~` switches in both directions for every shifted pair.
- `<Esc>` cancels active previews without disabling Artist.
- The palette appears on enable by default, can be suppressed by
  `show_palette_on_enable`, toggles with `?`, highlights the active tool, and
  closes after an action.
- The options palette applies each character/toggle action and cancels cleanly.
- Palette windows are removed on disable and do not leak across buffers or
  windows.
- `keymaps` can move or disable individual defaults.
- Pre-existing buffer-local mappings displaced by every new key class are
  restored byte-for-byte on exit.
- Existing mouse mappings, keyboard drawing, commands, user events, undo
  behavior, and window-option restoration continue to pass.

## Definition of Done

The work is complete when the mapping and palette behavior above is covered by
tests, the README and help file match the implementation, `make check` passes,
and disabling Artist leaves no mappings, floats, extmarks, timers, or session
state behind.
