GODOT ?= $(HOME)/.local/opt/godot/4.7.2/godot
# Space-separated lab scenarios (see `python3 tools/lab.py --list`), or all.
SCENARIOS ?= all
LAB_OUT ?= lab_shots

.PHONY: release-linux lab lab-shots icons

release-linux:
	python3 tools/release_linux.py --godot "$(GODOT)"

# Interactive visual test lab (sandboxed profile; F1 scenario list, F12 capture).
lab:
	"$(GODOT)" --path . res://scenes/lab/lab.tscn

# Headless screenshots + checks for SCENARIOS into LAB_OUT.
lab-shots:
	python3 tools/lab.py $(SCENARIOS) --out "$(LAB_OUT)" --godot "$(GODOT)"

# Re-render pixel-art icons from tools/icons/art_*.py, then import them.
icons:
	python3 tools/icons/build.py
	"$(GODOT)" --headless --path . --import
