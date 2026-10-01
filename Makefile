GODOT ?= $(HOME)/.local/opt/godot/4.7.2/godot

.PHONY: release-linux
release-linux:
	python3 tools/release_linux.py --godot "$(GODOT)"
