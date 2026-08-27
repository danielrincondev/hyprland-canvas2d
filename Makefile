LUA ?= lua
XDG_CONFIG_HOME ?= $(HOME)/.config
INSTALL_DIR ?= $(XDG_CONFIG_HOME)/hypr/canvas2d

.PHONY: all test verify benchmark install

all: test

test:
	$(LUA) tests/run.lua

verify:
	CANVAS2D_SOURCE="$(CURDIR)" Hyprland --verify-config --config tests/hyprland.lua

benchmark:
	$(LUA) tests/benchmark.lua

install:
	mkdir -p "$(INSTALL_DIR)"
	cp -R hypr/canvas2d/. "$(INSTALL_DIR)/"
	@printf 'Installed canvas2d in %s\n' "$(INSTALL_DIR)"
