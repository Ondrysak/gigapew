extends MenuScreen

## Lifetime records from Profile.records plus the most recent run.

@export var runs_value: Label
@export var victories_value: Label
@export var total_kills_value: Label
@export var best_kills_value: Label
@export var best_score_value: Label
@export var deepest_stage_value: Label
@export var best_level_value: Label
@export var last_run_label: Label
@export var currency_bar: CurrencyBar

func refresh() -> void:
	var records := Profile.records
	runs_value.text = str(int(records.runs))
	victories_value.text = str(int(records.victories))
	total_kills_value.text = str(int(records.total_kills))
	best_kills_value.text = str(int(records.best_kills))
	best_score_value.text = str(int(records.best_score))
	deepest_stage_value.text = "%d HOTOVO" % int(records.deepest_stage) if int(records.deepest_stage) > 0 else "—"
	best_level_value.text = str(int(records.best_level)) if int(records.best_level) > 0 else "—"
	last_run_label.text = _describe_last_run(records.get("last_run", {}))

static func format_time(seconds: float) -> String:
	var total := int(seconds)
	return "%d:%02d" % [floori(seconds / 60.0), total % 60]

func _describe_last_run(run: Dictionary) -> String:
	if run.is_empty():
		return "Zatím žádná výprava. Vyraz do ulic a nech tu první účet."
	var definition := Profile.roster.find(StringName(str(run.get("class_id", ""))))
	var operator := definition.display_name.to_upper() if definition != null else "NĚKDO Z PARTY"
	var outcome := "TARTARUS UZAVŘEN" if bool(run.get("victory", false)) \
			else "PÁD PO %d HOTOVÝCH SEKTOR(ECH)" % int(run.get("stages_cleared", 0))
	var parts := PackedStringArray([
		operator,
		outcome,
		"%d BODŮ" % int(run.get("score", 0)),
		"%d ZABITÍ" % int(run.get("kills", 0)),
		format_time(float(run.get("time", 0.0))),
		"ÚR. %d" % int(run.get("level", 0)),
	])
	var banked: Variant = run.get("banked", {})
	if banked is Dictionary:
		for id in banked:
			if int(banked[id]) > 0:
				parts.append("+%d %s" % [int(banked[id]), currency_bar.label_for(StringName(str(id)))])
	return "  ·  ".join(parts)
