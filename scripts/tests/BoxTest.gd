extends Node
## Headless check of BOX: the car drives itself into the pit lane, stops and rejoins, the
## pit arrows show when a stop is needed, and the two-compound rule is tracked.
##   godot --headless res://scenes/tests/BoxTest.tscn

func _ready() -> void:
	SaveManager.disabled = true
	GameManager.load_profile()
	GameManager.profile["career"] = {}
	AudioServer.set_bus_mute(0, true)
	Engine.time_scale = 8.0
	Engine.physics_ticks_per_second = 480
	Engine.max_physics_steps_per_frame = 64
	GameManager.session_mode = GameManager.MODE_RACE
	GameManager.session_weather = 0
	GameManager.mandatory_stop = true
	RaceManager.free_field_size = 8          # fast-forwarding twenty cars takes too long here
	var race := (load("res://scenes/Race.tscn") as PackedScene).instantiate() as RaceManager
	add_child(race)
	var ok := GameManager.race_laps == 3
	print("race laps %d" % GameManager.race_laps)
	race.player.is_player = false
	var driver := AIDriver.new()
	race.player.add_child(driver)
	driver.setup(race.player, race.line, {"pace": 0.95, "error_rate": 0.0}, 3)
	driver.others = race.cars
	while race.state != RaceManager.State.RACING:
		await get_tree().create_timer(0.2).timeout
	print("rule: '%s'  required %s" % [race.tyre_rule_text(), race.stop_required()])
	ok = ok and race.stop_required() and race.tyre_rule_text().begins_with("MUST PIT")
	race.player.damage = 70.0
	print("damaged 70 -> pit reason '%s'" % race.pit_reason())
	ok = ok and race.pit_reason() == "HEAVY DAMAGE"
	race.player.damage = 0.0
	# Arm BOX once the timer is running and let the autopilot take it in.
	while not race.player_timer.started:
		await get_tree().create_timer(0.2).timeout
	race.toggle_box()
	var phases := PackedStringArray()
	var waited := 0.0
	while waited < 240.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
		if race.pit_phase == "entry" and driver != null:
			driver.queue_free()
			driver = null
			race.player.is_player = true
		# Leaving the box is the player's job: hold the throttle once the crew is done.
		if race.pit_phase == "out":
			Input.action_press("throttle")
		else:
			Input.action_release("throttle")
		var phase := race.pit_phase if race.pit_phase != "" else "racing"
		if phases.is_empty() or phases[phases.size() - 1] != phase:
			phases.append(phase)
		if phases.size() > 3 and race.pit_phase == "":
			break
	print("box phases: %s  required after %s  rule '%s'" % [" > ".join(phases), race.stop_required(), race.tyre_rule_text()])
	ok = ok and " > ".join(phases).contains("entry > in > service > out > racing") and not race.stop_required() and not race.box_armed
	print("BOX TEST PASSED" if ok else "BOX TEST FAILED")
	get_tree().quit(0 if ok else 1)
