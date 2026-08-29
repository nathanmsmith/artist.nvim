.PHONY: test test-file format typecheck check oracle

NVIM ?= nvim
STYLUA ?= stylua
LUALS ?= mise exec -- lua-language-server
LUA_DIRS := lua plugin tests scripts
VIMRUNTIME ?= $(shell NVIM_LOG_FILE=/tmp/artist-nvim-luals.log $(NVIM) --headless -u NONE -i NONE --cmd 'set noswapfile' +'lua io.write(vim.env.VIMRUNTIME)' +qa)
MINITEST_DIR := deps/mini.test
MINITEST_VERSION := v0.18.0

test: $(MINITEST_DIR)/lua/mini/test.lua
	NVIM_LOG_FILE=/tmp/artist-nvim-test.log $(NVIM) --headless --noplugin -i NONE --cmd 'set noswapfile' -u scripts/minimal_init.lua -c 'lua MiniTest.run()'

test-file: $(MINITEST_DIR)/lua/mini/test.lua
	NVIM_LOG_FILE=/tmp/artist-nvim-test.log $(NVIM) --headless --noplugin -i NONE --cmd 'set noswapfile' -u scripts/minimal_init.lua -c "lua MiniTest.run_file('$(FILE)')"

format:
	$(STYLUA) $(LUA_DIRS)

typecheck: $(MINITEST_DIR)/lua/mini/test.lua
	VIMRUNTIME="$(VIMRUNTIME)" $(LUALS) --check="$(CURDIR)" --checklevel=Warning --check_format=pretty

check:
	$(STYLUA) --check $(LUA_DIRS)
	$(MAKE) typecheck
	$(MAKE) test

oracle:
	emacs --batch --quick -l tests/oracle/generate.el > tests/fixtures/artist.json

$(MINITEST_DIR)/lua/mini/test.lua:
	mkdir -p deps
	git clone --filter=blob:none --depth 1 --branch $(MINITEST_VERSION) https://github.com/nvim-mini/mini.test.git $(MINITEST_DIR)
