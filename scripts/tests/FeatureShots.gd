extends Node
## Dev tool: screenshots of the engineers / cars / FIA / driver card / wind tunnel /
## difficulty screens, an overview of every circuit's scenery, and a wet race.
##   godot res://scenes/tests/FeatureShots.tscn -- <out dir>

var _dir := ""


func _ready() -> void:
	if get_tree().current_scene == self:
		var runner := Node.new()
		runner.set_script(get_script())
		get_tree().root.add_child.call_deferred(runner)
		return
	SaveManager.disabled = true
	GameManager.load_profile()
	AudioServer.set_bus_mute(0, true)
	_dir = OS.get_cmdline_user_args()[0]
	_run()


func _shot(name: String, wait: float = 0.35) -> void:
	await get_tree().create_timer(wait).timeout
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_dir, name])
	print("shot ", name)


func _goto(path: String) -> Node:
	get_tree().change_scene_to_file(path)
	await get_tree().create_timer(0.3).timeout
	return get_tree().current_scene


func _run() -> void:
	GameManager.profile["tutorial_seen"] = true
	var only := OS.get_cmdline_user_args()[1] if OS.get_cmdline_user_args().size() > 1 else ""
	if only == "" or only == "ui":
		await _ui()
	if only == "" or only == "tracks":
		await _tracks()
	if only == "" or only == "race":
		await _race()
	get_tree().quit()


func _ui() -> void:
	Career.new_career("wil", {"name": "ALEX STONE", "look": {"skin": 2, "hair": 1, "hair_color": 0, "accessory": 1, "outfit": 0}})
	Career.state()["rp"] = 260
	Career.build_new_car()
	Career.upgrade_material("car1", "aero")
	Career.upgrade_material("car1", "aero")
	Career.upgrade_material("car2", "chassis")
	Career.assign_car(Career.lineup()[1], "car2")
	Career.state()["last_best"] = 3
	var hub := await _goto("res://scenes/career/CareerHub.tscn")
	await _shot("a_hq")
	hub.call("_show_tab", 1)
	await _shot("b_drivers")
	HubPanels.driver_card(hub, Career.lineup()[0])
	await _shot("c_driver_card")
	HubPanels.training_screen(hub, Career.lineup()[0])
	await _shot("c_training")
	Career.state()["date"] = Career.race_day(0) - 2
	HubPanels.practice_sheet(hub)
	await _shot("c_practice")
	hub.call("_close_modal")
	hub.call("_show_tab", 0)
	await _shot("c_hq_practice_day")
	HubPanels.manager_card(hub)
	await _shot("c_manager_card")
	hub.call("_close_modal")
	Career.state()["season_review"] = {"season": 1, "position": 4, "payout": 20000, "champion": "Maks Verstoppen", "team_champion": "Red Bison Racing", "contract": "renew"}
	HubPanels.season_review(hub)
	await _shot("c_season_review")
	Career.state()["season_review"] = {}
	hub.call("_close_modal")
	Career.state()["board"] = 30
	Career._queue_event({}, [{"id": Career.lineup()[0], "position": 12, "dnf": false, "points": 0}, {"id": Career.lineup()[1], "position": 14, "dnf": false, "points": 0}])
	hub.call("_check_interrupts")
	await _shot("c_decision")
	hub.call("_close_modal")
	Career.state()["pending_event"] = {}
	Career.state()["board"] = 60
	RaceReport.show(hub, {"race": "Falcon Ridge GP", "mine": [{"name": "Alex Albron", "position": 3, "dnf": false, "points": 15}, {"name": "Karlos Saenz", "position": 9, "dnf": true, "dsq": true, "dsq_reason": "REAR WING ANGLE 10, MAXIMUM 9", "points": 0}], "prize": 2400, "sponsor": 900, "salaries": 1800, "upkeep": 300, "staff": 280, "research": 31, "board_change": 6, "board": 66})
	await _shot("c_report")
	hub = await _goto("res://scenes/career/CareerHub.tscn")
	var junior: String = Career.market()[0]["id"]
	Career.scout(junior)
	HubPanels.driver_card(hub, junior)
	await _shot("c_driver_card_partial")
	hub.call("_close_modal")
	hub.call("_show_tab", 2)
	await _shot("d_scouting")
	hub.set("_show_rivals", true)
	hub.call("_show_tab", 2)
	await _shot("d_rivals")
	hub.call("_show_tab", 3)
	await _shot("e_standings")
	hub.call("_show_tab", 0)
	HubPanels.staff_sheet(hub)
	await _shot("e_hire")
	HubPanels.sponsor_sheet(hub)
	await _shot("e_sponsors")
	hub.call("_close_modal")
	await _goto("res://scenes/Saves.tscn")
	await _shot("e_careers")
	hub = await _goto("res://scenes/career/CareerHub.tscn")
	Career.add_message("boss_mer", "We have triggered Albon's release clause.", {"type": "poach", "driver": Career.lineup()[0], "team": "mer", "cash": 9000, "yes": "RELEASE  +$9.0M", "no": "COUNTER  +20% PAY"})
	hub.call("_open_phone")
	await _shot("f_phone")
	await _goto("res://scenes/career/RaceDay.tscn")
	await _shot("g_raceday")
	var garage := await _goto("res://scenes/Garage.tscn")
	await _shot("h_garage")
	garage.call("_refresh_car_card")
	(garage.get("_details") as Control).visible = true
	await _shot("h_car_card")
	(garage.get("_details") as Control).visible = false
	(garage.get("_workshop") as WorkshopUI).open()
	await _shot("h_workshop")
	(garage.get("_workshop") as WorkshopUI).visible = false
	garage.call("_show_picker", "engine")
	await _shot("h_garage_engine")
	garage.call("_show_picker", "rear_wing")
	await _shot("h_garage_wing")
	var tunnel: WindTunnelUI = garage.get("_tunnel")
	tunnel.open()
	tunnel.call("_start_run")
	await _shot("i_tunnel_running", 1.6)
	await _shot("i_tunnel_done", 2.4)
	tunnel.visible = false
	var menu := await _goto("res://scenes/MainMenu.tscn")
	(menu.get("_difficulty") as DifficultyPanel).open()
	await _shot("j_difficulty")


## Whole-lap overview of each circuit so the scenery can be judged at a glance.
func _tracks() -> void:
	for id: String in GameManager.TRACKS:
		GameManager.track_id = id
		GameManager.career_race = {}
		var world := Node2D.new()
		var track := Track.new()
		world.add_child(track)
		get_tree().root.add_child(world)
		var cam := Camera2D.new()
		world.add_child(cam)
		var b := track.data.bounds.grow(170.0 * VehiclePhysicsConfig.PPM)
		cam.position = b.get_center()
		var z := minf(1280.0 / b.size.x, 720.0 / b.size.y)
		cam.zoom = Vector2(z, z)
		cam.make_current()
		await _shot("t_%s" % id, 0.5)
		# And a close-up at driving zoom somewhere scenic.
		cam.position = track.data.points[track.data.count / 3]
		cam.zoom = Vector2(0.75, 0.75)
		await _shot("u_%s_close" % id, 0.3)
		world.queue_free()
		await get_tree().process_frame


func _race() -> void:
	Career.end_career()
	GameManager.track_id = "interlagos"
	GameManager.session_mode = GameManager.MODE_RACE
	GameManager.session_weather = 0
	GameManager.session_night = false
	var race := (load("res://scenes/Race.tscn") as PackedScene).instantiate() as RaceManager
	get_tree().root.add_child(race)
	race.player.is_player = false
	var driver := AIDriver.new()
	race.player.add_child(driver)
	driver.setup(race.player, race.line, {"pace": 0.95, "error_rate": 0.0, "track_grip": WeatherFX.grip(2)}, 3)
	driver.others = race.cars
	await _shot("v_race_wet", 9.0)
	# A pit stop: hand the car back and roll it into the lane.
	driver.queue_free()
	await get_tree().physics_frame
	race.player.is_player = true
	race.player.damage = 55.0
	var lane := -(race.track.half_width + TrackData.PIT_WIDTH * 0.55)
	race.player.place(race.track.position_at(race.track.pit_start + 15.0, lane), race.track.heading_at(race.track.pit_start + 15.0))
	while race.pit_phase != "service":
		await get_tree().process_frame
	await _shot("w_pit_stop", 1.2)
	race.queue_free()
