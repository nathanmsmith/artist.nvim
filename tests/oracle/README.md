# Artist differential fixture generator

`generate.el` loads the checked-in, pinned `artist.el` and emits JSON golden
buffers. A normal test run consumes the checked-in fixture and does not need
Emacs.

To regenerate with GNU Emacs installed:

```sh
make oracle
```

Review fixture changes together with any upstream pin change. Do not regenerate
from an unpinned system copy of Artist.
