extends Node
## Road to Glory:  godot --headless res://scenes/tests/GloryTest.tscn
## Plays The Climb by simulation (choosing the first option at every story choice), checks the
## field, the opener, a driven race being booked, promotion, the F1 contract, the open-ended
## F1 seasons and retirement.

var _failures := 0


func _check(ok: bool, text: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", text])
	if not ok:
		_failures += 1


func _ready() -> void:
	SaveManager.disabled = true
	GameManager.load_profile()
	Glory.new_game("TEST DRIVER", 27, PixelArt.default_look(), "speed")
	var g := Glory.state()
	var racing := 0
	for id: String in g["field"]:
		if Glory.racing(id):
			racing += 1
	_check(racing == 20 and g["seat"] == "campo" and Glory.racing("theo") and Glory.racing("luca"), "F3 field: %d drivers, you and Luca at Campo, Theo at Premo" % racing)
	_check(Glory.grid_position() == 19, "the opener starts from P%d (P19)" % Glory.grid_position())
	_check(Glory.next_scene() == "intro", "the story opens with the intro")
	# A driven race: the on-track field and a win on track books as a win.
	Glory.build_drive()
	var info: Dictionary = GameManager.career_race
	_check((info["rivals"] as Array).size() == 7 and info.has("setup") and info.has("attrs") and int(info["grid_slot"]) == 6, "drive: 7 rivals on track, you start 7th of the eight (P20 behind you), your stats drive the car")
	# The race scene takes the series car, your livery and your grid slot; the AI drives for you.
	Engine.time_scale = 8.0
	Engine.physics_ticks_per_second = 480
	Engine.max_physics_steps_per_frame = 64
	AudioServer.set_bus_mute(0, true)
	var race := (load("res://scenes/Race.tscn") as PackedScene).instantiate() as RaceManager
	add_child(race)
	_check(race.player.setup.parts["engine"] == "engine_compact_4" and race.cars.size() == 8, "race scene: F3 car (%s), 8 cars on track" % race.player.setup.parts["engine"])
	race.player.is_player = false
	race.player.takes_damage = false
	var driver := AIDriver.new()
	race.player.add_child(driver)
	driver.setup(race.player, race.line, {"pace": 0.97, "error_rate": 0.0, "attrs": info["attrs"]}, 3)
	driver.others = race.cars
	var waited := 0.0
	while race.state != RaceManager.State.FINISHED and waited < 1500.0:
		await get_tree().create_timer(1.0).timeout
		waited += 1.0
	race.positions.update(race.cars, race.timers, race.track.length)
	var on_track := race.positions.position_of(race.player)
	print("     race state %s  finished %s  destroyed %s  laps %d/%d  fuel %.0f" % [race.state, race._session.get("finished"), race._session.get("destroyed", false), race.player_timer.laps_completed, GameManager.race_laps, race.player.fuel])
	var results := RaceResults.build(race.mode, race.player_timer, on_track, race.cars.size(), [], race.telemetry, race.track, race._session)
	_check(results.get("glory", false) and Glory.state()["last"]["race"] != "" and int(g["round"]) == 1 and int(Glory.state()["last"]["position"]) > 0, "the driven race was booked by Road to Glory (P%d on track -> P%d)" % [on_track, int(Glory.state()["last"]["position"])])
	race.queue_free()
	Engine.time_scale = 1.0
	# And a win on track books as a win.
	g["round"] = 0
	g["points"]["me"] = 0
	Glory.build_drive()
	var report := Glory.finish_drive(1, true)
	_check(int(report["position"]) == 1 and int(g["points"]["me"]) == 25, "winning on track wins the race (P%d, %d pts)" % [int(report["position"]), int(g["points"]["me"])])
	# Make the driver good enough to climb, then simulate the rest.
	for key: String in Glory.SKILLS:
		Glory.me()[key] = 88.0
	var guard := 0
	while Glory.active() and str(g["series"]) != "F1" and guard < 200:
		guard += 1
		_play_scenes()
		if str(g["series"]) == "F1":
			break
		if not Glory.season_over():
			Glory.before_race()
			Glory.quick_sim()
	_play_scenes()
	print("     milestones: %s" % ", ".join((g["milestones"] as Array).map(func(m: Dictionary) -> String: return m["text"])))
	_check(str(g["series"]) == "F1" and g["phase"] == "f1", "reached Formula One (%s, %s)" % [g["series"], g.get("f1_team", "")])
	var count := {}
	for id: String in g["field"]:
		if Glory.racing(id):
			count[g["field"][id]["team"]] = int(count.get(g["field"][id]["team"], 0)) + 1
	var full := true
	for t: Dictionary in g["teams"]:
		full = full and int(count.get(t["id"], 0)) == 2
	_check(full and Glory.racing("me"), "F1 grid: two race drivers per real team, you included")
	var age := int(Glory.me()["age"])
	for season in 3:
		while not Glory.season_over():
			Glory.quick_sim()
		_play_scenes()
	_check(int(Glory.me()["age"]) == age + 3 and int(g["round"]) == 0, "three F1 seasons later you are %d" % int(Glory.me()["age"]))
	Glory.retire()
	_check(not Glory.active() and g.get("retired", false), "you retire when you choose")
	# The player can fail: a weak driver does not get an F2 seat.
	Glory.new_game("SLOW DRIVER", 99, PixelArt.default_look(), "smooth")
	g = Glory.state()
	for key: String in Glory.SKILLS:
		Glory.me()[key] = 52.0
	g["reputation"] = 0
	guard = 0
	while not Glory.season_over() and guard < 20:
		guard += 1
		Glory.quick_sim()
	_check(Glory.my_position() > 10 and (g["offers"] as Array).is_empty(), "P%d in F3 with no reputation: no F2 offers" % Glory.my_position())
	_play_scenes()
	_check(str(g["series"]) == "F3" and int(g["season"]) == 2, "so it is another season in F3")
	print("GLORY TEST PASSED" if _failures == 0 else "GLORY TEST FAILED (%d)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


## Plays queued scenes, taking the first choice (the F1 test is booked as a decent lap).
func _play_scenes() -> void:
	var guard := 0
	while Glory.next_scene() != "" and guard < 30:
		guard += 1
		var id := Glory.next_scene()
		var content := GloryStory.scene(id)
		var choices: Array = content.get("choices", [])
		var key: String = choices[0][0] if not choices.is_empty() else ""
		var action := GloryStory.choose(id, key)
		if action == "test":
			GameManager.career_race = {}
			Glory.finish_test(100.0, 85.0)
		elif action == "complete":
			Glory.join_f1()
