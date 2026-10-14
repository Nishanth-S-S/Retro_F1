class_name RaceReport
extends RefCounted
## The chequered-flag summary shown after any career race (driven, pit wall or quick sim).


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
	panel.custom_minimum_size = Vector2(800, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	box.add_child(Art.make(Vector2(0, 20), func(a: Control) -> void: PixelArt.draw_checker(a, Rect2(Vector2.ZERO, a.size), 10.0, Color.WHITE, UIKit.INK)))
	box.add_child(UIKit.title_bar("CHEQUERED FLAG", 50.0))
	box.add_child(UIKit.label(str(report["race"]).to_upper(), 12, UIKit.TEXT_DIM))
	var headline := PackedStringArray()
	for m: Dictionary in report["mine"]:
		headline.append("%s %s" % [str(m["name"]).get_slice(" ", 1).to_upper(), "DNF" if m["dnf"] else "P%d" % int(m["position"])])
	box.add_child(UIKit.label("    ".join(headline), 28))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	box.add_child(cols)
	var top := VBoxContainer.new()
	top.add_theme_constant_override("separation", 0)
	cols.add_child(top)
	var rows: Array = report["top"]
	for i in rows.size():
		var r: Dictionary = rows[i]
		top.add_child(UIKit.label("%2d  %-20s %s  %2d" % [i + 1, str(r["name"]).to_upper().left(20), r["short"], Career.POINTS[i]], 13, UIKit.BAD if r["is_player"] else UIKit.TEXT))
	var money := VBoxContainer.new()
	money.add_theme_constant_override("separation", 2)
	cols.add_child(money)
	for info: Array in [["PRIZE MONEY", int(report["prize"])], ["SPONSOR", int(report["sponsor"])], ["DRIVER SALARIES", -int(report["salaries"])], ["FACTORY UPKEEP", -int(report["upkeep"])]]:
		money.add_child(UIKit.label("%-16s %s" % [info[0], UIKit.money(info[1])], 13, UIKit.GOOD if int(info[1]) >= 0 else UIKit.BAD))
	var change := int(report["board_change"])
	money.add_child(UIKit.spacer(6))
	money.add_child(UIKit.label("BOARD CONFIDENCE %+d  (now %d)" % [change, int(report["board"])], 14, UIKit.GOOD if change >= 0 else UIKit.BAD))
	if report.has("season"):
		var s: Dictionary = report["season"]
		money.add_child(UIKit.label("SEASON OVER: P%d, prize %s" % [int(s["position"]), UIKit.money(s["payout"])], 14, UIKit.ACCENT))
	money.add_child(UIKit.label("Check your phone - the paddock has opinions.", 12, UIKit.TEXT_DIM))
	var done := UIKit.button("BACK TO HQ", 18, true)
	done.custom_minimum_size = Vector2(0, 56)
	done.pressed.connect(func() -> void: SceneManager.goto("career"))
	box.add_child(done)
