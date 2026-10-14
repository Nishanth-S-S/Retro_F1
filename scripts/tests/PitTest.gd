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
	# Park a damaged, half-empty car in the service box.
	driver.queue_free()
	var track := race.track
	race.player.place(track.position_at(track.pit_box, -(track.half_width + 4.0)), track.heading_at(track.pit_box))
	race.player.damage = 50.0
	race.player.fuel = 40.0
	await get_tree().create_timer(0.5).timeout
	var stop := race.pit_timer
	print("pit stop started: %.1f s remaining, surface %d, off-track %s" % [stop, race.player.surface_front, race.player.off_track])
	ok = ok and stop > 5.0 and not race.player.off_track and race.player.surface_front == VehiclePhysicsConfig.Surface.ASPHALT
	while race.pit_timer > 0.0:
		await get_tree().create_timer(0.5).timeout
	print("after stop: damage %.0f fuel %.0f controls %s" % [race.player.damage, race.player.fuel, race.player.controls_enabled])
	ok = ok and race.player.damage == 0.0 and race.player.fuel == 100.0 and race.player.controls_enabled
	print("PIT TEST PASSED" if ok else "PIT TEST FAILED")
	get_tree().quit(0 if ok else 1)
