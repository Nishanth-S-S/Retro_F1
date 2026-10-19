class_name RaceResults
extends RefCounted
## Builds the end-of-session summary and pays out money, research and challenges.
## All amounts come from data/progression so they are easy to rebalance.


static func build(mode: String, player_timer: LapTimer, position: int, total_cars: int, classification: Array, rec: TelemetryRecorder, track: TrackData, session: Dictionary) -> Dictionary:
	var eco := GameManager.economy
	var profile := GameManager.profile
	var results := {
		"mode": mode,
		"position": position,
		"total_cars": total_cars,
		"classification": classification,
		"laps": player_timer.lap_times.duplicate(),
		"lap_valid": player_timer.lap_valid.duplicate(),
		"best_lap": player_timer.best_lap,
		"total_time": player_timer.total_time,
		"average_lap": (player_timer.total_time / player_timer.lap_times.size()) if player_timer.lap_times.size() > 0 else 0.0,
		"best_sectors": Array(player_timer.best_sectors),
		"personal_best": float(GameManager.record()["best_lap"]),
		"new_pb": session.get("new_pb", false),
		"money": 0,
		"research": 0,
		"reward_lines": [],
		"finished": session.get("finished", false),
	}
	var lines: Array = results["reward_lines"]
	var money := 0
	var research := 0
	# --- first ever completed lap
	if player_timer.lap_times.size() > 0 and not profile["first_lap_done"]:
		profile["first_lap_done"] = true
		var bonus := int(eco.get("first_lap_research", 10))
		research += bonus
		pass
	# --- career grand prix: the career books the result, free-play rewards do not apply
	var career_race := not GameManager.career_race.is_empty()
	if career_race and GameManager.career_race.get("glory", false):
		# Road to Glory books its own races (and the F1 test).
		if GameManager.career_race.get("test", false):
			results["glory_report"] = Glory.finish_test(player_timer.best_lap, float(session.get("ideal_lap", 0.0)))
		else:
			results["glory_report"] = Glory.finish_drive(position, results["finished"] and not session.get("destroyed", false))
		GameManager.career_race = {}
		results["glory"] = true
	elif career_race:
		var completed: bool = results["finished"] and not session.get("destroyed", false)
		var report := Career.finish_drive(position, completed)
		results["career_report"] = report
		for m: Dictionary in report["mine"]:
			lines.append("%s: %s" % [m["name"], "DNF" if m["dnf"] else "P%d of 22, +%d pts" % [int(m["position"]), int(m["points"])]])
		lines.append("Prize %s  ·  Sponsor %s  ·  Salaries %s" % [Career.money_text(report["prize"]), Career.money_text(report["sponsor"]), Career.money_text(-int(report["salaries"]))])
		lines.append("Board confidence %+d (now %d)" % [int(report["board_change"]), int(report["board"])])
	# --- mode rewards
	if career_race:
		pass
	elif mode == GameManager.MODE_RACE and results["finished"]:
		var money_table: Array = eco.get("race_money", [])
		var research_table: Array = eco.get("race_research", [])
		var idx := clampi(position - 1, 0, money_table.size() - 1)
		money += int(money_table[idx])
		research += int(research_table[idx])
		lines.append("Race result P%d  +$%d" % [position, int(money_table[idx])])
	elif mode == GameManager.MODE_TIME_TRIAL and player_timer.best_lap > 0.0:
		# Targets are set for a 3.8 km lap and scale with the circuit's length; one claim each.
		var lap_scale := track.length / 3786.0
		for target: Dictionary in eco.get("time_trial_targets", []):
			var name: String = target["name"]
			if player_timer.best_lap <= float(target["time"]) * lap_scale and not profile["claimed_targets"].has(name):
				profile["claimed_targets"].append(name)
				money += int(target["money"])
				research += int(target["research"])
				lines.append("%s target beaten (%s)  +$%d" % [name, LapTimer.format_time(float(target["time"]) * lap_scale), int(target["money"])])
	# --- engineering challenges (any mode)
	for challenge: Dictionary in GameManager.challenges:
		var id: String = challenge["id"]
		if career_race or GameManager.is_challenge_done(id):
			continue
		var done := false
		match challenge["type"]:
			"max_speed":
				done = rec.max_speed * 3.6 >= float(challenge["target"])
			"sector_time":
				var sector := int(challenge["sector"])
				done = GameManager.track_id == "monza" and player_timer.best_sectors[sector] > 0.0 and player_timer.best_sectors[sector] <= float(challenge["target"])
			"race_win":
				done = mode == GameManager.MODE_RACE and results["finished"] and position == 1
		if done:
			profile["completed_challenges"].append(id)
			money += int(challenge["money"])
			research += int(challenge["research"])
			lines.append("Challenge: %s  +$%d" % [challenge["title"], int(challenge["money"])])
	# --- wrecked car
	if session.get("destroyed", false):
		var key := "explosion_penalty_test" if mode == GameManager.MODE_TEST else "explosion_penalty"
		var penalty := mini(int(eco.get(key, 1000)), GameManager.money())
		GameManager.add_money(-penalty)
		results["destroyed"] = true
		results["penalty"] = penalty
		lines.append("Car destroyed - rebuild cost  -$%d" % penalty)
	results["money"] = money
	results["research"] = research
	if money > 0:
		GameManager.add_money(money)
	if research > 0:
		GameManager.add_research(research)
	# --- analysis
	results["report"] = TelemetryAnalyzer.driving_report(rec, track)
	var laps_done := player_timer.lap_times.size()
	var compare: Array = []
	var compare_note := ""
	if laps_done > 0:
		var subject_lap := laps_done               # telemetry lap numbers are 1-based
		var subject := TelemetryAnalyzer.corner_stats(rec, track, subject_lap)
		var reference: Array = session.get("previous_pb_corners", [])
		var is_best: bool = session.get("pb_lap_number", -1) == subject_lap
		if not is_best and not (GameManager.record()["best_lap_corners"] as Array).is_empty():
			reference = GameManager.record()["best_lap_corners"]
		if reference.is_empty():
			compare_note = "Reference lap set. Drive another lap to compare corners."
		else:
			compare = TelemetryAnalyzer.worst_corners(subject, reference)
		results["graph_lap"] = TelemetryAnalyzer.lap_series(rec, subject_lap)
		var best_number: int = session.get("session_best_lap_number", subject_lap)
		results["graph_reference"] = TelemetryAnalyzer.lap_series(rec, best_number) if best_number != subject_lap else {}
		results["graph_lap_number"] = subject_lap
		results["graph_reference_number"] = best_number
	else:
		compare_note = "Complete a lap to unlock corner analysis."
	results["corners"] = compare
	results["corner_note"] = compare_note
	results["track_length"] = track.length
	GameManager.save()
	return results
