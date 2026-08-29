# Faithful Artist Mode Port Plan

## Verdict

This is not a matter of adding flood-fill and a few tools. The current plugin
is a solid Neovim drawing prototype, but a faithful Artist port requires
replacing its tool-centric core with Artist's operation registry, drawing
semantics, and interaction state machine.

Upstream exposes roughly 24 distinct operations, shifted variants, arrows,
filling, rectangle editing, text rendering, spray, vaporization, and full
keyboard control. The current plugin surfaces five tools, several with
materially different geometry or behavior. See the pinned
[upstream operation table](https://github.com/emacs-mirror/emacs/blob/f4f249a2249a7047ba41a659b8fcdcd7e1caf4e0/lisp/textmodes/artist.el#L634-L875).

## Where the Current Implementation Diverges

| Area | Artist behavior | Current state |
| --- | --- | --- |
| Lines | Arbitrary and snapped 8-direction lines; poly-lines; arrow endpoints | One Bresenham line |
| Pen | Single-character pen and connected pen-line | Freehand approximates pen-line only |
| Shapes | Rectangle/square and ellipse/circle; optional fill and borders | Rectangle and ellipse outlines |
| Editing | Erase char/rectangle, vaporize one/connected lines, cut/copy/paste rectangles and squares | Rectangle eraser only |
| Effects | Flood-fill, spray and radius selection | Missing |
| Text | Figlet/custom renderer, see-through and overwrite modes | Missing |
| Input | Mouse shifted variants, popup selection, wheel cycling, full keyboard drawing | Left drag and two-`RET` endpoints |
| Settings | Line/fill/erase characters, trimming, borders, arrows, fill bounds, spray settings, fuzziness | Pen character and nominal aspect ratio |

There are also compatibility bugs beneath the missing features:

- [`aspect_ratio`](lua/artist/canvas.lua#L182) only changes ellipse sample
  count; it does not change the geometry. Artist uses it to make squares and
  circles visually correct.
- Current ellipses interpret two points as bounding-box corners. Artist treats
  the first point as the center and expands through the second point using its
  midpoint ellipse algorithm.
- [`merge_character()`](lua/artist/canvas.lua#L60) merges more combinations
  than Artist. Artist deliberately only creates `+` for orthogonal crossings
  and `X` for opposing diagonals; other combinations overwrite. See
  [Artist's intersection rules](https://github.com/emacs-mirror/emacs/blob/f4f249a2249a7047ba41a659b8fcdcd7e1caf4e0/lisp/textmodes/artist.el#L2092-L2132).
- Coordinates are character indexes, not display-cell columns. Tabs,
  combining characters, and double-width Unicode will break mouse positioning
  or previews.
- Keyboard drawing does not update as the cursor moves because only `RET` and
  cancel are mapped. Artist maps directional movement into the active drawing
  operation and supports terminating poly-lines with a prefix argument. Its
  full keymap is visible
  [here](https://github.com/emacs-mirror/emacs/blob/f4f249a2249a7047ba41a659b8fcdcd7e1caf4e0/lisp/textmodes/artist.el#L477-L527).
- Artist trims trailing whitespace by default; the current tests explicitly
  require erased spaces to remain.

## Architecture

Retain the good Neovim shell: buffer-local sessions, extmark previews, option
restoration, atomic commits, commands, events, and the winbar.

Replace the drawing core with four layers.

### 1. Display-cell grid

Read and write virtual canvas cells consistently, including tabs, Unicode
width, virtual columns, rows beyond EOF, trimming, and configurable right
boundaries.

### 2. Patch/transaction engine

Operations should return a patch instead of editing immediately. Preview that
patch with extmarks, then commit it as one undo entry. The patch must preserve
original cells where operations need to undraw or unintersect.

### 3. Exact geometry and topology

Port or independently reproduce Artist's eight-point arbitrary line, snapped
line, square/circle aspect calculations, midpoint ellipse, intersection and
unintersection rules, filling spans, arrows, and line recognition. The
relevant upstream implementations begin with the
[eight-point line algorithm](https://github.com/emacs-mirror/emacs/blob/f4f249a2249a7047ba41a659b8fcdcd7e1caf4e0/lisp/textmodes/artist.el#L2391-L2445)
and
[ellipse/circle algorithms](https://github.com/emacs-mirror/emacs/blob/f4f249a2249a7047ba41a659b8fcdcd7e1caf4e0/lisp/textmodes/artist.el#L3458-L3610).

### 4. Operation state machine

Model Artist's four operation types directly:

- Continuous: pen, pen-line, spray, erase-character
- Poly-point: arbitrary and straight poly-lines
- One-point: paste, flood-fill, text, vaporize
- Two-point: lines, shapes, erase/cut/copy regions, spray radius

A data-driven operation registry should declare the shifted variant, drawing
kind, preview function, fill behavior, arrow capability, and completion hooks.
This is more scalable than adding branches to `mouse_drag()`.

## Implementation Order

### 1. Define compatibility

- Pin Artist to upstream commit
  `f4f249a2249a7047ba41a659b8fcdcd7e1caf4e0`.
- Treat drawing output and interaction semantics as compatible behavior.
- Give Emacs-only integrations such as Picture mode, `rect.el`, toolbars, and
  X pointer shapes documented Neovim equivalents.
- Decide and document the supported Neovim version range.

### 2. Build an oracle suite

- Generate golden fixtures by running the pinned `artist.el` in batch Emacs.
- Cover every octant, endpoint reversal, degenerate shapes, aspect ratios,
  crossings, existing prose, fill/border settings, and trailing whitespace.
- Check fixtures into the repository so normal CI does not require Emacs.
- Add property tests for cancellation, endpoint reversal, buffer isolation,
  option restoration, and one-step undo.

The current [test suite](tests/artist_spec.lua#L21) proves that the prototype
works but cannot measure Artist parity.

### 3. Replace the geometry core

- Implement arbitrary and straight lines.
- Implement rectangles and aspect-correct squares.
- Implement Artist-compatible ellipses and circles.
- Reproduce exact intersection and unintersection behavior.
- Add configurable line, fill, and erase characters.
- Add fill spans, borderless shapes, and trailing-whitespace trimming.

### 4. Implement the interaction engine

- Add cursor-movement drawing.
- Add continuous modes and poly-line termination.
- Add shifted mouse variants.
- Add first/second arrow toggling.
- Implement Artist's operation-switching rules during an active drawing.
- Ensure cancellation restores the buffer exactly.

### 5. Add edit and advanced operations

#### Flood-fill

- Use a four-connected scanline fill.
- Match cells identical to the starting cell.
- Respect configurable right boundaries and existing-buffer vertical bounds.
- Make filling with the source character a no-op.
- Compute a patch and commit the result as one undo entry.
- Support optional progress updates without splitting undo history.

#### Vaporize

- Recognize `-`, `|`, `/`, `\`, `+`, and `X` line topology.
- Bridge interruptions using configurable fuzziness.
- Preserve crossing lines through unintersection.
- Traverse lines connected at their endpoints.

#### Cut, copy, and paste

- Support inclusive rectangular and aspect-correct square regions.
- Preserve spaces and rectangular width.
- Interoperate with a documented blockwise Neovim register while retaining an
  internal rectangle buffer if required.

#### Spray

- Add repeated spraying while the pointer or keyboard operation is active.
- Progress characters from light to heavy.
- Add radius selection and preview.
- Inject the RNG and timer so tests are deterministic.

#### Text

- Provide a pluggable renderer.
- Support optional `figlet` integration.
- Implement both see-through and overwrite handling for blank characters.
- Test with a stub renderer so CI does not require `figlet`.

### 6. Finish the Neovim UI

- Expand `:ArtistTool` completion to every operation.
- Provide a complete operation picker.
- Show the active operation and drawing state in the winbar.
- Add commands and mappings for shifted tools, settings, and arrows.
- Optionally support mouse-wheel operation cycling.
- Preserve and restore every displaced mapping and option.
- Update the README and help file with all behavior and divergences.

## Configuration Parity

The public configuration should cover, or explicitly reject with a documented
reason, the following Artist settings:

- Rubber-banding and non-rubber-band endpoint characters
- Line, fill, default-fill, and erase characters
- Arrow characters
- Aspect ratio
- Trailing-whitespace trimming
- Flood-fill right boundary and incremental display
- Narrow-ellipse left and right characters
- Filled-shape borders
- Vaporize fuzziness
- Spray interval, radius, character progression, and initial character
- Text renderer, Figlet executable, and default font
- Rectangle/register interoperability

Pointer shape and Picture mode compatibility are platform-specific and should
be documented as non-applicable unless a meaningful Neovim equivalent is
implemented.

## Definition of Done

A credible faithful port must satisfy all of the following:

- All 24 upstream behaviors are present, not merely similarly named tools.
- Golden buffer output matches the pinned Artist version across the fixture
  corpus.
- Every operation works with both mouse and keyboard.
- Completed operations are one undo step; previews and cancellation never
  alter buffer history.
- Tabs, virtual space, multibyte text, multiple windows, multiple active
  buffers, and non-modifiable buffers are tested.
- Large fills and connected-line vaporization have performance and termination
  tests.
- Neovim-specific divergences are explicitly documented.
- Mode exit leaves no mappings, highlights, window options, timers, extmarks,
  or pending state behind.

## Repository and Licensing Prerequisites

Add a GPLv3 license


## Recommended First Slice

Do not add flood-fill directly to the current five-tool abstraction. The first
implementation slice should:

1. Pin the upstream target and establish licensing.
2. Add the differential fixture generator and initial golden cases.
3. Introduce the display-cell grid and patch engine.
4. Make arbitrary lines, straight lines, rectangles, squares, ellipses, and
   circles match the oracle.
5. Only then build flood-fill and the remaining operations on the compatible
   substrate.

This ordering produces measurable compatibility at every stage and avoids
having to rewrite each advanced tool after the canvas model changes.
