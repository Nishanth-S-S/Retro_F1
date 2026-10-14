extends Node
## Headless check of the team-building systems: engineers and research points, several
## cars, car-to-driver fit, materials, wind tunnel, FIA scrutineering, buyouts and
## poaching, difficulty and a wet on-track race with driving aids.
##   godot --headless res://scenes/tests/TeamTest.tscn

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _ready() -> void:
	SaveManager.disabled = true
	GameManager.load_profile()
	AudioServer.set_bus_mute(0, true)
	Career.new_career("wil", {"name": "TEST", "look": PixelArt.default_look()})
	var c := Career.state()
	# --- engineers and research
	_check(Career.engineers().size() == 3 and Career.engineer_market().size() >= 15, "3 engineers on staff, %d on the market" % Career.engineer_market().size())
	var before := int(Career.research_income()["total"])
	var hired := 0
	for e: Dictionary in Career.engineer_market():
		if str(e["team"]) == "" and Career.hire_engineer(e["id"]) == "":
			hired += 1
	_check(Career.engineers().size() == Career.max_engineers(), "hired up to the headcount limit (%d)" % Career.engineers().size())
	_check(int(Career.research_income()["total"]) > before, "more engineers -> more research (%d -> %d a week)" % [before, int(Career.research_income()["total"])])
	c["last_best"] = 1
	var win := int(Career.research_income()["total"])
	c["last_best"] = 15
	_check(win > int(Career.research_income()["total"]), "a win pays more research than P15 (%d vs %d)" % [win, int(Career.research_income()["total"])])
	var cash := GameManager.money()
	var note := Career.fire_engineer(Career.engineers()[0])
	_check(Career.engineers().size() == Career.max_engineers() - 1 and GameManager.money() < cash, "fire: %s" % note)
	var rival_eng: Dictionary = {}
	for e: Dictionary in Career.engineer_market():
		if str(e["team"]) != "":
			rival_eng = e
			break
	cash = GameManager.money()
	_check(Career.hire_engineer(rival_eng["id"]) == "" and GameManager.money() < cash, "poached %s (skill %d) for a buyout of %s" % [rival_eng["name"], int(rival_eng["skill"]), UIKit.money(cash - GameManager.money())])
	# --- cars, materials, fit
	_check(Career.build_new_car() == "" and Career.cars().size() == 2, "second car built")
	var d0 := Career.driver(Career.lineup()[0])
	var d1 := Career.driver(Career.lineup()[1])
	Career.assign_car(d1["id"], "car2")
	Career.set_active_car("car2")
	GameManager.setup.rear_wing_angle = 9
	GameManager.setup.front_wing_angle = 3
	Career.sync_active_car()
	_check(Career.car_setup(Career.car("car1")).rear_wing_angle != 9 and Career.car_setup(Career.car("car2")).rear_wing_angle == 9, "the two cars keep separate setups")
	print("     fits: %s on car1 %d / car2 %d,  %s on car1 %d / car2 %d" % [d0["name"], Career.car_fit(d0, Career.car("car1")), Career.car_fit(d0, Career.car("car2")), d1["name"], Career.car_fit(d1, Career.car("car1")), Career.car_fit(d1, Career.car("car2"))])
	_check(Career.car_fit(d1, Career.car("car1")) != Career.car_fit(d1, Career.car("car2")), "fit rating changes with the car")
	c["rp"] = 300
	var ovr := Career.car_overall(Career.car("car1"))
	_check(Career.upgrade_material("car1", "aero") == "" and Career.car_overall(Career.car("car1")) > ovr and int(c["rp"]) < 300, "material upgrade spends research and raises the car (%.1f -> %.1f)" % [ovr, Career.car_overall(Career.car("car1"))])
	c["rp"] = 0
	_check(Career.upgrade_material("car1", "aero") != "", "no research points, no upgrade")
	# --- wind tunnel
	var runs := Career.tunnel_runs_left()
	var outcome := Career.run_tunnel("car1")
	_check(outcome.has("gain") and Career.tunnel_runs_left() == runs - 1, "tunnel run: correlation +%d%%, %d runs left" % [int(float(outcome.get("gain", 0.0)) * 100.0), Career.tunnel_runs_left()])
	while Career.tunnel_runs_left() > 0:
		Career.run_tunnel("car1")
	_check(Career.run_tunnel("car1").has("error"), "FIA allowance stops further runs")
	# --- FIA scrutineering
	_check(Career.car_violations(Career.car("car1")).is_empty(), "starter car is legal (min weight %d kg, car %d kg)" % [int(Career.regs()["min_weight"]), int(Career.setup_stats(Career.car_setup(Career.car("car1"))).mass)])
	Career.set_active_car("car1")
	GameManager.setup.rear_wing_angle = 10
	Career.regs()["max_wing"] = 8
	_check(not Career.car_violations(Career.car("car1")).is_empty(), "wing over the limit is flagged: %s" % ", ".join(Career.car_violations(Career.car("car1"))))
	c["fia"] = 4          # certain to be caught
	var sim := GPSim.new()
	sim.setup(Career.race_entries(), Career.next_round(), 0, 5)
	while not sim.finished():
		Career.auto_strategy(sim)
		sim.step()
	var report := Career.apply_race(sim.cars, sim.flags)
	var thrown := false
	for m: Dictionary in report["mine"]:
		if m["id"] == d0["id"] and (m.get("dsq", false) or m["dnf"]):
			thrown = true
	_check(thrown and int(report["research"]) > 0, "illegal car disqualified: %s; week paid %d research" % [report["dsq"], int(report["research"])])
	GameManager.setup.rear_wing_angle = 5
	# --- buyouts and poaching
	var target: Dictionary = Career.poach_targets()[0]
	c["reputation"] = 10
	_check(Career.sign_driver(target["id"], "reserve") != "", "star refuses a low-reputation team: %s" % Career.sign_driver(target["id"], "reserve"))
	c["reputation"] = 95
	GameManager.profile["money"] = 90000
	var from_team := str(target["team"])
	var seat: String = Career.lineup()[1]
	var error := Career.sign_driver(target["id"], seat)
	_check(error == "" and Career.lineup().has(target["id"]) and Career.team_drivers(from_team).size() == 2 and GameManager.money() < 90000, "bought %s out of %s for %s; they signed a replacement (%s)" % [target["name"], from_team, UIKit.money(90000 - GameManager.money()), error])
	_check(Career.car_for(target["id"])["id"] == "car2", "new driver inherits the seat's car")
	Career.add_message("boss_mer", "poach", {"type": "poach", "driver": Career.lineup()[0], "team": "mer", "cash": 7000, "yes": "RELEASE", "no": "COUNTER"})
	var pay := int(Career.driver(Career.lineup()[0])["salary"])
	var kept := Career.resolve_offer(0, false)
	print("     counter-offer: %s" % kept)
	_check(Career.state()["inbox"][0]["done"], "poach offer answered")
	Career.add_message("boss_mer", "poach", {"type": "poach", "driver": Career.lineup()[0], "team": "mer", "cash": 7000})
	var leaving: String = Career.lineup()[0]
	Career._expire_offers()
	_check(not Career.lineup().has(leaving) and Career.lineup().size() == 2, "an ignored approach goes through: %s left" % Career.driver(leaving)["name"])
	var seen := 0
	for i in 60:
		Career._poaching_round()
		if Career._open_poach():
			seen += 1
			for m: Dictionary in Career.state()["inbox"]:
				m["done"] = true
	_check(seen > 0, "rivals made %d approaches in 60 race weeks" % seen)
	# --- home tracks and difficulty
	var home := Career.driver(Career.lineup()[0])
	_check(Career.track_form(home, str(home["home"])) >= Career.HOME_GAIN - Career.TYPE_GAIN, "home-track bonus: %s gains %.2f s at %s" % [home["name"], Career.track_form(home, str(home["home"])), home["home"]])
	Difficulty.apply_preset(0)
	var rookie := Difficulty.ai_pace_offset()
	Difficulty.apply_preset(4)
	_check(rookie < Difficulty.ai_pace_offset() and Difficulty.steer_assist() == 0.0 and Difficulty.damage_scale() > 1.5, "LEGEND is harder than ROOKIE (pace %+.2f vs %+.2f)" % [Difficulty.ai_pace_offset(), rookie])
	Difficulty.apply_preset(0)
	_check(Difficulty.steer_assist() > 0.3 and Difficulty.brake_assist() > 0.5 and int(GameManager.setting("abs")) == 2, "ROOKIE turns the aids on")
	# --- wet race on track with the rookie aids holding a throttle-only "driver" on the road
	Engine.time_scale = 10.0
	Engine.physics_ticks_per_second = 600
	Engine.max_physics_steps_per_frame = 64
	Career.end_career()
	for id: String in GameManager.TRACKS:
		GameManager.track_id = id
		GameManager.session_mode = GameManager.MODE_TEST
		GameManager.session_weather = 2 if id == "nordhaven" else 0
		var race := (load("res://scenes/Race.tscn") as PackedScene).instantiate() as RaceManager
		add_child(race)
		# Nobody steers: full steering and braking help must get the car round on their own.
		GameManager.profile["settings"]["diff_steer_assist"] = 1.0
		GameManager.profile["settings"]["diff_brake_assist"] = 1.0
		race.player.is_player = true
		var elapsed := 0.0
		var max_off := 0.0
		while race.player_timer.laps_completed < 1 and elapsed < 260.0:
			await get_tree().physics_frame
			race.player.input.touch_pedal = 0.8
			race.player.input.touch_pedal_active = true
			elapsed += 1.0 / 60.0
			if race.state == RaceManager.State.RACING:
				max_off = maxf(max_off, absf(race.player.lateral))
		_check(race.player_timer.laps_completed >= 1 and race.player.damage < 100.0, "%s (%s, %s): aids alone lapped in %.1f s, damage %d%%, max offset %.1f m" % [id, TrackTheme.label(id), WeatherFX.NAMES[race.weather], race.player_timer.best_lap, int(race.player.damage), max_off])
		race.queue_free()
		await get_tree().process_frame
	print("\n%s" % ("TEAM TEST PASSED" if _failures == 0 else "TEAM TEST FAILED (%d)" % _failures))
	get_tree().quit(_failures)
