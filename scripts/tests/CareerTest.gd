extends Node
## Headless career soak test: plays two full seasons with random decisions and checks the
## books stay sane.   godot --headless res://scenes/tests/CareerTest.tscn

func _ready() -> void:
	SaveManager.disabled = true
	GameManager.load_profile()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var failures := 0
	for team_id: String in ["cad", "mcl"]:
		Career.new_career(team_id, {"name": "TEST", "look": PixelArt.default_look()})
		print("\n=== %s  cash %s  car %.0f  team %d ===" % [Career.my_team()["name"], UIKit.money(GameManager.money()), Career.car_rating(team_id), Career.team_rating(team_id)])
		print(Career.commission_package())
		print("upgrade aero: '%s'  rd: '%s'  rd level %d  medium unlocked %s" % [Career.upgrade("aero"), Career.upgrade("rd"), Career.rd_level(), GameManager.is_unlocked("tires_medium")])
		print("sponsor: '%s' / %s" % [Career.negotiate_sponsor(0), Career.sign_sponsor(0) if Career.state()["sponsor_offers"].size() > 0 else "-"])
		var market := Career.market()
		print("market %d, top: %s ovr %d" % [market.size(), market[0]["name"], Career.driver_overall(market[0])])
		var cash_before := GameManager.money()
		for phase in 3:
			Career.scout(market[0]["id"])
		print("3 scouting phases cost %s -> level %d, potential ovr %d (now %d); 4th scout allowed: %s" % [UIKit.money(cash_before - GameManager.money()), Career.scout_level(market[0]), Career.potential_overall(market[0]), Career.driver_overall(market[0]), Career.scout(market[0]["id"])])
		if Career.scout_level(market[0]) != 3 or cash_before - GameManager.money() != 2300:
			failures += 1
			print("FAIL: scouting phases")
		print("reserves at start: %d; sign 2nd reserve: '%s'; 3rd: '%s'" % [Career.reserves().size(), Career.sign_driver(market[1]["id"], "reserve"), Career.sign_driver(market[2]["id"], "reserve")])
		print("sign: '%s'" % Career.sign_driver(market[0]["id"], Career.lineup()[1]))
		var hurt: String = Career.lineup()[0]
		Career._injure(Career.driver(hurt), 2, "test")
		var racing := Career.race_lineup()
		print("injured %s -> racing %s" % [Career.driver(hurt)["name"], [Career.driver(racing[0])["name"], Career.driver(racing[1])["name"]]])
		if racing.has(hurt) or not Career.reserves().has(racing[0]) or Career.reserves().size() != 2:
			failures += 1
			print("FAIL: injury cover")
		var races := 0
		while Career.active() and not Career.state()["fired"] and races < 20:
			var sim := GPSim.new()
			sim.setup(Career.race_entries(), Career.next_round(), int(Career.state()["factory"]["pit"]), rng.randi())
			if sim.cars.size() != 22:
				failures += 1
				print("FAIL: grid has %d cars" % sim.cars.size())
			while not sim.finished():
				for car in sim.player_cars():
					# A crude human: box when the tires are gone or the weather turns.
					var wet: bool = car["tire"] == "I" or car["tire"] == "W"
					if sim.weather > 0 and not wet:
						car["pit_request"] = "I"
					elif sim.weather == 0 and wet:
						car["pit_request"] = "M"
					elif GPSim.tire_wear_fraction(car) >= 1.0 and sim.laps - sim.lap > 3:
						car["pit_request"] = "M" if sim.weather == 0 else car["tire"]
				sim.team_order = ["free", "hold", "swap"][rng.randi() % 3]
				sim.step()
			var report := Career.apply_race(sim.cars, sim.flags)
			races += 1
			var line := PackedStringArray()
			for m: Dictionary in report["mine"]:
				line.append("DNF" if m["dnf"] else "P%d" % int(m["position"]))
			var event := Career.pending_event()
			var outcome := ""
			if not event.is_empty():
				outcome = "%s -> %s" % [event["id"], Career.resolve_event(rng.randi() % (event["options"] as Array).size())]
			print("R%02d %-26s %-8s winner %-12s cash %-8s board %3d  %s" % [races, report["race"], "/".join(line), report["top"][0]["name"].get_slice(" ", 1), UIKit.money(GameManager.money()), int(Career.state()["board"]), outcome])
		var injuries := 0
		for m: Dictionary in Career.state()["inbox"]:
			if str(m["text"]).begins_with("Medical update"):
				injuries += 1
		print("medical updates in inbox: %d   lineup[0] injured now: %s" % [injuries, Career.is_injured(Career.lineup()[0])])
		print("after %d races: season %d  fired %s  P%d  car %.0f" % [races, int(Career.state()["season"]), Career.state()["fired"], Career.team_position(), Career.car_rating(team_id)])
	# --- phone, offers, quick sim and a race the "player" actually drives
	Career.new_career("wil", {"name": "TEST", "look": PixelArt.default_look()})
	var before_round := int(Career.state()["round"])
	var quick := Career.quick_sim()
	print("\nquick sim: %s  inbox %d  unread %d" % [quick["race"], Career.state()["inbox"].size(), Career.unread_count()])
	if int(Career.state()["round"]) != before_round + 1 or Career.state()["inbox"].size() < 4:
		failures += 1
		print("FAIL: quick sim did not book the race / send texts")
	Career.add_message("boss_mer", "bid", {"type": "bid", "driver": Career.lineup()[1], "team": "mer", "cash": 5000})
	Career.add_message("boss_fer", "job", {"type": "job", "team": "fer"})
	print("bid: %s" % Career.resolve_offer(1, true))
	print("job: %s  -> team %s lineup %s cash %s" % [Career.resolve_offer(0, true), Career.state()["team"], Career.lineup(), UIKit.money(GameManager.money())])
	if Career.state()["team"] != "fer" or Career.lineup().size() != 2 or Career.contacts().size() < 30:
		failures += 1
		print("FAIL: offers")
	Engine.time_scale = 10.0
	Engine.physics_ticks_per_second = 600
	Engine.max_physics_steps_per_frame = 64
	AudioServer.set_bus_mute(0, true)
	var drive_id: String = Career.lineup()[0]
	Career.build_drive(drive_id)
	var race := (load("res://scenes/Race.tscn") as PackedScene).instantiate() as RaceManager
	add_child(race)
	race.player.is_player = false
	var driver := AIDriver.new()
	race.player.add_child(driver)
	driver.setup(race.player, race.line, {"pace": 0.97, "error_rate": 0.0}, 3)
	driver.others = race.cars
	var names := PackedStringArray()
	for car in race.cars:
		names.append(car.driver_name.get_slice(" ", 1))
	print("on-track grid: %s" % ", ".join(names))
	while race.state != RaceManager.State.FINISHED:
		await get_tree().create_timer(1.0).timeout
	race.positions.update(race.cars, race.timers, race.track.length)
	var track_pos := race.positions.position_of(race.player)
	var results := RaceResults.build(race.mode, race.player_timer, track_pos, race.cars.size(), [], race.telemetry, race.track, race._session)
	print("drove to P%d on track -> %s  career race cleared %s" % [track_pos, results["reward_lines"], GameManager.career_race.is_empty()])
	if not results.has("career_report") or not GameManager.career_race.is_empty() or int(results["money"]) != 0:
		failures += 1
		print("FAIL: driven race")
	print("\n%s" % ("CAREER TEST PASSED" if failures == 0 else "CAREER TEST FAILED"))
	get_tree().quit(failures)
