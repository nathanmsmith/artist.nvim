.PHONY: test format check

NVIM ?= nvim
STYLUA ?= stylua
LUA_DIRS := lua plugin tests

test:
	NVIM_LOG_FILE=/tmp/artist-nvim-test.log $(NVIM) --headless -u NONE -i NONE --cmd 'set noswapfile' -l tests/artist_spec.lua

format:
	$(STYLUA) $(LUA_DIRS)

check:
	$(STYLUA) --check $(LUA_DIRS)
	$(MAKE) test
