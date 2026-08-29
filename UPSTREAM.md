# Upstream compatibility target

artist.nvim targets GNU Emacs Artist at commit
`f4f249a2249a7047ba41a659b8fcdcd7e1caf4e0`.

The checked-in [`artist.el`](artist.el) is the oracle source. Its SHA-256 is:

```text
1e64696677e51d59d5fd80e92099e8b112659a323898fedfb7a75ef329112efe
```

Drawing output, shifted-operation pairs, interaction kinds, intersection and
unintersection topology, aspect-ratio calculations, and trimming are treated
as compatibility behavior. Neovim-specific equivalents and non-applicable
Emacs integrations are documented in the README and help file.
