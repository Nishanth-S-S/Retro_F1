extends Node
## End-to-end smoke test of the real scenes in a real window, driven by script:
## garage (buy + fit parts, overlays) -> time trial with an AI at the wheel -> results.
## Saves a screenshot at each stage.   godot res://scenes/tests/FlowTest.tscn -- <out dir>

var _dir := ""


func _ready() -> void:
	if get_tree().current_scene == self:
		# Re-home under the root so this runner survives scene changes.
		var runner := Node.new()
		runner.set_script(get_script())
		get_tree().root.add_child.call_deferred(runner)
		return
	SaveManager.disabled = true
	GameManager.load_profile()
	AudioServer.set_bus_mute(0, true)
	_dir = OS.get_cmdline_user_args()[0]
	_run()


func _shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_dir, name])
	print("shot ", name)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _scene() -> Node:
	return get_tree().current_scene


func _run() -> void:
	# --- garage: buy and fit parts through the same GameManager calls the UI uses
	get_tree().change_scene_to_file("res://scenes/Garage.tscn")
	await _wait(0.6)
	var garage := _scene()
	GameManager.profile["story_progress"] = 4
	assert(GameManager.buy_part("front_wing_high_df"))
	assert(GameManager.buy_part("tires_soft"))
	assert(GameManager.buy_part("ballast_30"))
	garage.call("_on_slot_tapped", "front_wing")
	garage.call("_install", PartDB.get_part("front_wing_high_df"), "front_wing")
	garage.call("_install", PartDB.get_part("tires_soft"), "tires")
	garage.call("_install", PartDB.get_part("ballast_30"), "ballast")
	GameManager.setup.ballast_position = 1.0
	EventBus.setup_changed.emit()
	await _wait(0.5)
	await _shot("0_garage_picker")
	garage.call("_show_picker", "")
	await _wait(0.3)
	await _shot("0_garage_overview")
	(garage.get("_workspace") as BlueprintWorkspace).show_mass = true
	await _wait(0.8)
	await _shot("1_garage_mass")
	(garage.get("_workspace") as BlueprintWorkspace).show_mass = false
	(garage.get("_workspace") as BlueprintWorkspace).show_aero = true
	# Simulate a drag in progress to capture slot highlighting.
	var drag := garage.get("_drag") as PartDragHandler
	var ws := garage.get("_workspace") as BlueprintWorkspace
	drag.begin(PartDB.get_part("front_wing_balanced"), ws.global_position + ws.slot_position("front_wing") + Vector2(-40, 30))
	await _wait(0.3)
	await _shot("2_garage_aero_drag")
	drag.release(ws.global_position + ws.slot_position("front_wing"))
	await _wait(0.5)
	GameManager.remove_part("rear_wing")
	await _wait(0.3)
	garage.call("_launch", GameManager.MODE_TEST)
	await _wait(0.4)
	await _shot("3_garage_not_ready")
	GameManager.install_part("rear_wing", "rear_wing_balanced")
	GameManager.install_part("front_wing", "front_wing_high_df")
	# --- time trial, AI drives two laps at 6x speed
	Engine.time_scale = 6.0
	Engine.physics_ticks_per_second = 360
	Engine.max_physics_steps_per_frame = 32
	GameManager.session_mode = GameManager.MODE_TIME_TRIAL
	get_tree().change_scene_to_file("res://scenes/Race.tscn")
	await _wait(1.0)
	var race := _scene() as RaceManager
	race.player.is_player = false
	var driver := AIDriver.new()
	race.player.add_child(driver)
	driver.setup(race.player, race.line, {"pace": 0.96, "error_rate": 0.0, "consistency": 0.9}, 3)
	driver.others = race.cars
	while race.player_timer.laps_completed < 1:
		await _wait(1.0)
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	await _wait(6.0)
	race.player._apply_damage(64.0)
	await _wait(8.0)
	await _shot("4_time_trial_ghost")
	Engine.time_scale = 6.0
	Engine.physics_ticks_per_second = 360
	while race.player_timer.laps_completed < 3:
		await _wait(1.0)
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	race.toggle_pause()
	await _shot("5_pause")
	race.toggle_pause()
	race.player._apply_damage(50.0)
	await _wait(1.0)
	await _shot("6_explosion")
	await _wait(3.5)
	await _shot("7_results_destroyed")
	print("results: ", JSON.stringify(GameManager.last_results.get("reward_lines", [])), " money ", GameManager.money(), " rp ", GameManager.research())
	print("corners: ", JSON.stringify(GameManager.last_results.get("corners", [])))
	get_tree().quit()
