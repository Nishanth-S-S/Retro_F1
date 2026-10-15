extends Node
## Headless check that a career race you drive is booked from your finish on track:
## P1 on track wins the Grand Prix.   godot --headless res://scenes/tests/DriveResultTest.tscn

func _ready() -> void:
	SaveManager.disabled = true
	GameManager.load_profile()
	var ok := true
	var last := 0
	for track_position: int in [1, 4, 8]:
		Career.new_career("cad", {"name": "TEST", "look": PixelArt.default_look()})
		var drive_id: String = Career.lineup()[0]
		Career.build_drive(drive_id)
		var report := Career.finish_drive(track_position, true)
		var final := 0
		for m: Dictionary in report["mine"]:
			if m["name"] == report["driven"]:
				final = int(m["position"])
		print("P%d on track -> P%d of 22" % [track_position, final])
		ok = ok and final > last and (track_position != 1 or final == 1)
		last = final
	# A weekend opened in one career must not leak into another (switching save slot).
	SaveManager.slot = 1
	Career.new_career("mer", {"name": "TEST", "look": PixelArt.default_look()})
	Career.weekend_sim()
	SaveManager.slot = 2
	Career.new_career("aud", {"name": "TEST", "look": PixelArt.default_look()})
	var mine: Array = []
	for car in Career.weekend_sim().player_cars():
		mine.append(car["id"])
	mine.sort()
	var want := Career.race_lineup().duplicate()
	want.sort()
	var names: Array = mine.map(func(id: String) -> String: return str(Career.driver(id)["name"]))
	print("after switching from a Mercurio weekend to an Audo career, racing as: %s" % ", ".join(names))
	ok = ok and mine == want
	Career.build_drive(Career.lineup()[0])
	ok = ok and GameManager.career_race["driver_name"] == Career.driver(Career.lineup()[0])["name"]
	print("DRIVE RESULT TEST PASSED" if ok else "DRIVE RESULT TEST FAILED")
	get_tree().quit(0 if ok else 1)
