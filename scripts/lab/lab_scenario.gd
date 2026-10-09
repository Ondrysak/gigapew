class_name LabScenario
extends RefCounted

## One visual test in the lab: builds an isolated situation through the real
## game code, captures named screenshots and records checks. `run` is a
## coroutine; keep every wait inside it on Lab helpers so batch runs stay timed.

var lab: Lab

func title() -> String:
	return "Scenario"

func summary() -> String:
	return ""

func run() -> void:
	pass
