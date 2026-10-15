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
	print("DRIVE RESULT TEST PASSED" if ok else "DRIVE RESULT TEST FAILED")
	get_tree().quit(0 if ok else 1)
