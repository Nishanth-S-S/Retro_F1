extends Node
## Headless persistence checks: round trip, corrupted file, missing file, zero-lap session.
##   godot --headless res://scenes/tests/SaveTest.tscn

var _failures := 0


func _check(condition: bool, text: String) -> void:
	print("%s  %s" % ["PASS" if condition else "FAIL", text])
	if not condition:
		_failures += 1


func _ready() -> void:
	SaveManager.save_path = "user://apex_assembly_test_save.json"
	SaveManager.delete_save()
	GameManager.load_profile()
	_check(GameManager.money() == 25000, "fresh profile starts with $25,000")
	_check(BuildValidator.is_ready(GameManager.setup), "starting build is complete and driveable")
	_check(GameManager.setup.parts["engine"] == "engine_compact_4" and GameManager.setup.parts["tires"] == "tires_hard", "starting build matches the spec")
	_check(PartDB.all_ids().size() >= 20, "%d parts defined (>= 20)" % PartDB.all_ids().size())
	# Economy rules.
	_check(not GameManager.buy_part("engine_turbo_6"), "R&D-locked part cannot be bought")
	_check(not GameManager.is_unlocked("tires_medium"), "medium tires start locked")
	Career.new_career("wil", {"name": "TEST", "look": PixelArt.default_look()})
	_check(Career.active() and GameManager.money() == 40000 and Career.lineup().size() == 2, "new career sets team budget and two drivers")
	_check(Career.upgrade("rd") == "" and GameManager.is_unlocked("tires_medium"), "R&D level 1 unlocks parts")
	_check(int(Career.state()["cap_spent"]) == 2000, "factory spending counts against the cost cap")
	GameManager.profile["story_progress"] = 6
	_check(GameManager.buy_part("chassis_lightweight"), "unlocked part can be bought")
	_check(GameManager.install_part("chassis", "chassis_lightweight"), "owned part installs")
	_check(not GameManager.install_part("engine", "chassis_lightweight"), "part refuses the wrong hardpoint")
	_check(GameManager.buy_part("tires_soft") and GameManager.install_part("tires", "tires_soft"), "buy + fit soft tires")
	GameManager.setup.rear_wing_angle = 8
	GameManager.setup.ballast_position = 0.2
	GameManager.set_setting("camera_rotation", true)
	GameManager.record()["best_lap"] = 91.234
	GameManager.save()
	var money := GameManager.money()
	# Round trip.
	GameManager.load_profile()
	_check(GameManager.money() == money and Career.active() and Career.state()["team"] == "wil", "money and career persist")
	_check(GameManager.is_owned("chassis_lightweight"), "owned parts persist")
	_check(GameManager.setup.parts["chassis"] == "chassis_lightweight" and GameManager.setup.parts["tires"] == "tires_soft", "installed parts persist")
	_check(GameManager.setup.rear_wing_angle == 8 and is_equal_approx(GameManager.setup.ballast_position, 0.2), "car setup persists")
	_check(bool(GameManager.setting("camera_rotation")), "settings persist")
	_check(is_equal_approx(float(GameManager.record()["best_lap"]), 91.234), "best lap persists")
	# Build validation.
	GameManager.remove_part("rear_wing")
	GameManager.remove_part("tires")
	var report := BuildValidator.report(GameManager.setup)
	_check(report.contains("Rear Wing") and report.contains("Tires") and not BuildValidator.is_ready(GameManager.setup), "validator lists missing parts")
	# Corrupted save.
	var file := FileAccess.open(SaveManager.save_path, FileAccess.WRITE)
	file.store_string("{ this is not json !!")
	file.close()
	GameManager.load_profile()
	_check(GameManager.money() == 25000 and not Career.active() and BuildValidator.is_ready(GameManager.setup), "corrupted save falls back to a default profile")
	# Stats respond to parts.
	var config: VehiclePhysicsConfig = load("res://data/physics/default_physics.tres")
	var base := CarStats.compute(GameManager.setup, config)
	var modified := GameManager.setup.duplicate_setup()
	modified.install("ballast", "ballast_30")
	modified.ballast_position = 1.0
	var rear := CarStats.compute(modified, config)
	modified.ballast_position = 0.0
	var front := CarStats.compute(modified, config)
	_check(rear.front_weight < base.front_weight and front.front_weight > base.front_weight, "ballast position moves weight distribution (%.1f%% / %.1f%% / %.1f%% front)" % [front.front_weight * 100, base.front_weight * 100, rear.front_weight * 100])
	_check(rear.cg_x < base.cg_x and front.cg_x > base.cg_x, "centre of mass moves with ballast")
	modified.install("front_wing", "front_wing_high_df")
	var aero := CarStats.compute(modified, config)
	_check(aero.front_aero > front.front_aero and aero.top_speed < front.top_speed, "high-downforce front wing: more front aero, less top speed")
	SaveManager.delete_save()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path.replace(".json", ".corrupt.json")))
	# Leaving a session with zero laps must not break the results screen.
	SaveManager.disabled = true
	GameManager.load_profile()
	GameManager.session_mode = GameManager.MODE_TEST
	var race := (load("res://scenes/Race.tscn") as PackedScene).instantiate() as RaceManager
	add_child(race)
	await get_tree().create_timer(0.3).timeout
	var results := RaceResults.build(race.mode, race.player_timer, 1, 1, [], race.telemetry, race.track, {"new_pb": false, "finished": false})
	_check(int(results["money"]) == 0 and (results["laps"] as Array).is_empty(), "zero-lap test drive produces empty results and pays nothing")
	GameManager.last_results = results
	var screen := (load("res://scenes/Results.tscn") as PackedScene).instantiate()
	add_child(screen)
	await get_tree().process_frame
	_check(true, "results screen builds from an empty session")
	print("\n%s (%d failures)" % ["ALL CHECKS PASSED" if _failures == 0 else "SOME CHECKS FAILED", _failures])
	get_tree().quit(_failures)
