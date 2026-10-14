class_name RaceReport
extends RefCounted
## The chequered-flag summary after any career race: where your two cars finished, what
## the weekend earned, and one button back to HQ.


static func show(parent: Control, report: Dictionary) -> void:
	var modal := Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(modal)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	var panel := UIKit.panel(UIKit.PANEL, UIKit.LINE)
	panel.custom_minimum_size = Vector2(760, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(UIKit.title_bar(str(report["race"]), 54.0))
	for m: Dictionary in report["mine"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		box.add_child(row)
		var result := "P%d" % int(m["position"])
		var color := UIKit.GOOD if int(m["points"]) > 0 else UIKit.TEXT
		if m.get("dsq", false):
			result = "DSQ"
			color = UIKit.BAD
		elif m["dnf"]:
			result = "DNF"
			color = UIKit.BAD
		var place := UIKit.label(result, 44, color)
		place.custom_minimum_size = Vector2(150, 0)
		row.add_child(place)
		var who := VBoxContainer.new()
		who.alignment = BoxContainer.ALIGNMENT_CENTER
		who.add_theme_constant_override("separation", 0)
		row.add_child(who)
		who.add_child(UIKit.label(str(m["name"]).to_upper(), 24))
		var note := "+%d POINTS" % int(m["points"])
		if m.get("dsq", false):
			# An illegal car is thrown out however well it was driven.
			note = "ILLEGAL CAR: %s" % str(m.get("dsq_reason", "FAILED THE FIA CHECK"))
		who.add_child(UIKit.label(note, 15, UIKit.BAD if m.get("dsq", false) else UIKit.TEXT_DIM))
	var net := int(report["prize"]) + int(report["sponsor"]) - int(report["salaries"]) - int(report["upkeep"]) - int(report.get("staff", 0))
	var change := int(report["board_change"])
	var totals := HBoxContainer.new()
	totals.add_theme_constant_override("separation", 40)
	box.add_child(totals)
	totals.add_child(UIKit.label("%s%s" % ["+" if net >= 0 else "", UIKit.money(net)], 26, UIKit.GOOD if net >= 0 else UIKit.BAD))
	totals.add_child(UIKit.label("BOARD %+d" % change, 26, UIKit.GOOD if change >= 0 else UIKit.BAD))
	totals.add_child(UIKit.label("+%d RESEARCH" % int(report.get("research", 0)), 26, UIKit.ACCENT))
	if report.has("season"):
		var s: Dictionary = report["season"]
		box.add_child(UIKit.label("SEASON OVER  ·  P%d  ·  +%s" % [int(s["position"]), UIKit.money(s["payout"])], 22, UIKit.HOT))
	var done := UIKit.button("CONTINUE", 22, true)
	done.custom_minimum_size = Vector2(0, 66)
	done.pressed.connect(func() -> void: SceneManager.goto("career"))
	box.add_child(done)
