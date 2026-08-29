.PHONY: test format typecheck check oracle

NVIM ?= nvim
STYLUA ?= stylua
LUALS ?= mise exec -- lua-language-server
LUA_DIRS := lua plugin tests
VIMRUNTIME ?= $(shell NVIM_LOG_FILE=/tmp/artist-nvim-luals.log $(NVIM) --headless -u NONE -i NONE --cmd 'set noswapfile' +'lua io.write(vim.env.VIMRUNTIME)' +qa)

test:
	NVIM_LOG_FILE=/tmp/artist-nvim-test.log $(NVIM) --headless -u NONE -i NONE --cmd 'set noswapfile' -l tests/artist_spec.lua

format:
	$(STYLUA) $(LUA_DIRS)

typecheck:
	VIMRUNTIME="$(VIMRUNTIME)" $(LUALS) --check="$(CURDIR)" --checklevel=Warning --check_format=pretty

check:
	$(STYLUA) --check $(LUA_DIRS)
	$(MAKE) typecheck
	$(MAKE) test

oracle:
	emacs --batch --quick -l tests/oracle/generate.el > tests/fixtures/artist.json
