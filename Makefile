LUA ?= lua
XDG_CONFIG_HOME ?= $(HOME)/.config
INSTALL_DIR ?= $(XDG_CONFIG_HOME)/hypr/grid

.PHONY: all test verify benchmark install

all: test

test:
	$(LUA) tests/run.lua

verify:
	GRID_SOURCE="$(CURDIR)" Hyprland --verify-config --config tests/hyprland.lua

benchmark:
	$(LUA) tests/benchmark.lua

install:
	mkdir -p "$(INSTALL_DIR)"
	cp -R hypr/grid/. "$(INSTALL_DIR)/"
	@printf 'Installed grid in %s\n' "$(INSTALL_DIR)"
