extends Node
## Headless check of fuel burn and the on-track pit stop.  godot --headless res://scenes/tests/PitTest.tscn

func _ready() -> void:
	SaveManager.disabled = true
	GameManager.load_profile()
	GameManager.profile["career"] = {}
	AudioServer.set_bus_mute(0, true)
	Engine.time_scale = 8.0
	Engine.physics_ticks_per_second = 480
	Engine.max_physics_steps_per_frame = 64
	GameManager.session_mode = GameManager.MODE_RACE
	var race := (load("res://scenes/Race.tscn") as PackedScene).instantiate() as RaceManager
	add_child(race)
	race.player.is_player = false
	var driver := AIDriver.new()
	race.player.add_child(driver)
	driver.setup(race.player, race.line, {"pace": 0.95, "error_rate": 0.0}, 3)
	driver.others = race.cars
	while race.player_timer.laps_completed < 1:
		await get_tree().create_timer(1.0).timeout
	var burned := 100.0 - race.player.fuel
	print("fuel after 1 racing lap: %.1f%% left (burned %.1f%%)" % [race.player.fuel, burned])
	var ok := burned > 8.0 and burned < 30.0
	# Hand back to the "player" and roll a damaged, half-empty car into the pit lane.
	driver.queue_free()
	await get_tree().physics_frame
	race.player.is_player = true
	var track := race.track
	var lane := -(track.half_width + TrackData.PIT_WIDTH * 0.55)
	race.player.place(track.position_at(track.pit_start + 15.0, lane), track.heading_at(track.pit_start + 15.0))
	race.player.damage = 50.0
	race.player.fuel = 40.0
	var tyres_before: String = race.player.setup.parts["tires"]
	var phases := PackedStringArray()
	var stop := 0.0
	var waited := 0.0
	while waited < 40.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
		if phases.is_empty() or phases[phases.size() - 1] != race.pit_phase:
			phases.append(race.pit_phase if race.pit_phase != "" else "racing")
		stop = maxf(stop, race._pit_total)
		if phases.size() > 2 and race.pit_phase == "":
			break
	print("pit phases: %s  stop %.1f s  tyres %s -> %s" % [" > ".join(phases), stop, tyres_before, race.player.setup.parts["tires"]])
	print("after stop: damage %.0f fuel %.0f autopilot %s required now %s" % [race.player.damage, race.player.fuel, race.player.autopilot, race._stop_still_required()])
	ok = ok and " > ".join(phases).contains("in > service > out") and race.player.damage < 20.0 and race.player.fuel > 98.0 and not race.player.autopilot
	ok = ok and race.player.setup.parts["tires"] != tyres_before and not race._stop_still_required() and stop > 1.5
	print("PIT TEST PASSED" if ok else "PIT TEST FAILED")
	get_tree().quit(0 if ok else 1)
