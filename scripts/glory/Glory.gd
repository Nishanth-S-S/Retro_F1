extends Node
## Autoload "Glory": ROAD TO GLORY. You build a driver and climb F3 -> F2 -> F1 with your own
## hands on the wheel. The story ("The Climb") only covers getting to Formula One; once you sign
## an F1 contract the game hands over to an open-ended driver career driven by the simulation:
## real teams, real drivers, ageing, rookies, contracts, and retirement when you decide.
##
## State lives in GameManager.profile["glory"], one per save slot, so every save has its own
## driver. Races use the normal race scene (GameManager.career_race with "glory": true); the
## rest of the field is simulated with GPSim, and your finish on track slots you into it.

const SERIES := {
	"F3": {"name": "FORMULA 3", "rounds": 6, "stop": false, "spread": 2.5,
		"car": {"chassis": "chassis_balanced", "engine": "engine_compact_4", "gearbox": "gearbox_basic_6", "front_wing": "front_wing_balanced", "rear_wing": "rear_wing_balanced",
			"front_suspension": "suspension_balanced", "rear_suspension": "suspension_balanced", "brakes": "brakes_standard", "tires": "tires_medium"}},
	"F2": {"name": "FORMULA 2", "rounds": 6, "stop": true, "spread": 2.5,
		"car": {"chassis": "chassis_balanced", "engine": "engine_balanced_6", "gearbox": "gearbox_close_ratio", "front_wing": "front_wing_high_df", "rear_wing": "rear_wing_high_df",
			"front_suspension": "suspension_stiff", "rear_suspension": "suspension_stiff", "brakes": "brakes_racing", "tires": "tires_soft"}},
	"F1": {"name": "FORMULA ONE", "rounds": 10, "stop": true, "spread": 0.0,
		"car": {"chassis": "chassis_lightweight", "engine": "engine_high_output_8", "gearbox": "gearbox_seamless", "front_wing": "front_wing_cascade", "rear_wing": "rear_wing_twin_plane",
			"front_suspension": "suspension_stiff", "rear_suspension": "suspension_stiff", "brakes": "brakes_racing", "tires": "tires_ultra"}},
}
## Junior teams (F3 and F2 share them): name, short, colours, how good their car is.
const JUNIOR_TEAMS := [
	["premo", "Premo Racing", "PRE", "#d4202a", "#f4f6f2", 86], ["arte", "ARTE Grand Prix", "ART", "#1d2a44", "#c9d2e0", 85],
	["tridente", "Tridente", "TRI", "#1b4f9c", "#e8c440", 83], ["hightech", "Hightech GP", "HTG", "#f4f6f2", "#1d1d1d", 82],
	["campo", "Campo Racing", "CMP", "#d9471f", "#f4f6f2", 81], ["mvp", "MVP Motorsport", "MVP", "#f08a24", "#16233a", 81],
	["rodan", "Rodan Motorsport", "ROD", "#111111", "#c8a24a", 79], ["damz", "DAMZ", "DMZ", "#2a7de1", "#f4f6f2", 79],
	["amersfort", "Van Amersfort", "VAN", "#e94f8a", "#1b1b1b", 77], ["aixa", "AIXA Racing", "AIX", "#5a2c8c", "#f4f6f2", 76],
]
const JUNIOR_TRACKS: PackedStringArray = ["monza", "spielberg", "silverstone", "spa", "port_azure", "interlagos"]
const JUNIOR_ROUND_NAMES: PackedStringArray = ["ITALY", "AUSTRIA", "BRITAIN", "BELGIUM", "PORT AZURE", "SEASON FINALE"]
const POINTS: PackedInt32Array = [25, 18, 15, 12, 10, 8, 6, 4, 2, 1]
## The talent you start with: which stats your driver is born with an edge in.
const TALENTS := {
	"speed": {"name": "RAW SPEED", "note": "Fast over one lap and on the brakes. Rough in traffic.", "pace": 6, "starts": 2, "overtaking": 3, "consistency": -4, "racecraft": -2},
	"racer": {"name": "RACER", "note": "Brave wheel to wheel. Not the quickest alone.", "racecraft": 6, "overtaking": 5, "defending": 4, "pace": -2, "tyres": -2},
	"smooth": {"name": "SMOOTH", "note": "Consistent, kind to tyres, quick in the wet.", "consistency": 6, "tyres": 6, "wet": 4, "pace": -2, "overtaking": -3},
}
## Driver academies of real F1 teams, each looking for something different.
const ACADEMIES := {
	"rbr": {"name": "RED BISON JUNIOR TEAM", "wants": "pace", "pitch": "We can teach consistency. We can't teach speed."},
	"mer": {"name": "MERCURIO JUNIOR PROGRAMME", "wants": "consistency", "pitch": "Clean racing and good feedback. That's how you get a seat with us."},
	"fer": {"name": "FERRANO DRIVER ACADEMY", "wants": "racecraft", "pitch": "We want drivers who fight. Show us you can race."},
}
const SKILLS: PackedStringArray = ["pace", "starts", "racecraft", "consistency", "overtaking", "defending", "tyres", "wet"]
const CAST := {
	"elliot": {"name": "ELLIOT HAYES", "role": "RACE ENGINEER", "look": {"skin": 0, "hair": 3, "hair_color": 4, "accessory": 1, "outfit": 3, "face": 2}},
	"theo": {"name": "THEO LAURENT", "role": "THE PRODIGY", "look": {"skin": 0, "hair": 1, "hair_color": 2, "accessory": 0, "outfit": 2, "face": 2}},
	"marcus": {"name": "MARCUS REED", "role": "THE FRIEND", "look": {"skin": 3, "hair": 5, "hair_color": 7, "accessory": 0, "outfit": 2, "face": 1}},
	"luca": {"name": "LUCA MORETTI", "role": "THE PROFESSIONAL", "look": {"skin": 1, "hair": 0, "hair_color": 0, "accessory": 7, "outfit": 2, "face": 0}},
	"manager": {"name": "SAM RHODES", "role": "YOUR MANAGER", "look": {"skin": 2, "hair": 0, "hair_color": 0, "accessory": 2, "outfit": 1, "face": 1}},
	"reporter": {"name": "PADDOCK PRESS", "role": "REPORTER", "look": {"skin": 1, "hair": 2, "hair_color": 3, "accessory": 0, "outfit": 1, "face": 3}},
	"engineer2": {"name": "NADIA KRAUSE", "role": "F2 RACE ENGINEER", "look": {"skin": 0, "hair": 2, "hair_color": 1, "accessory": 1, "outfit": 3, "face": 2}},
	"principal": {"name": "TEAM PRINCIPAL", "role": "FORMULA ONE", "look": {"skin": 0, "hair": 4, "hair_color": 4, "accessory": 0, "outfit": 1, "face": 0}},
}

var _rng := RandomNumberGenerator.new()
var _sim: GPSim
var _sim_key := ""


func _ready() -> void:
	_rng.randomize()


func state() -> Dictionary:
	return GameManager.profile.get("glory", {})


func active() -> bool:
	return not state().is_empty() and state().get("active", false)


func me() -> Dictionary:
	return state()["field"].get("me", {})


func series() -> Dictionary:
	return SERIES[state()["series"]]


func in_f1() -> bool:
	return str(state().get("series", "")) == "F1"


# ---------------------------------------------------------------- new game

## Starts Road to Glory with a driver you built.
func new_game(driver_name: String, number: int, look: Dictionary, talent: String) -> void:
	var t: Dictionary = TALENTS.get(talent, TALENTS["speed"])
	var you := {"id": "me", "name": driver_name, "number": number, "look": look, "age": 18, "team": "", "reserve": false,
		"ego": 50, "ego_cap": 85, "morale": 70, "fitness": 92, "talent": talent, "salary": 0}
	var caps := {}
	for key: String in SKILLS:
		you[key] = clampi(66 + int(t.get(key, 0)) + _rng.randi_range(-1, 1), 55, 80)
		caps[key] = clampi(93 + int(t.get(key, 0)) / 2, 88, 98)
	caps["fitness"] = 98
	you["caps"] = caps
	you["potential"] = caps["pace"]
	var g := {"active": true, "series": "F3", "season": 1, "year": 2027, "round": 0, "phase": "climb",
		"field": {"me": you}, "teams": [], "points": {}, "team_points": {}, "seat": "",
		"reputation": 10, "academy": "", "flags": {}, "story": ["intro"], "milestones": [], "stats": {"starts": 0, "wins": 0, "podiums": 0, "points": 0, "titles": 0},
		"objective": {}, "offers": [], "last": {}, "history": [], "f1_team": "", "contract": 0, "complete": false}
	GameManager.profile["glory"] = g
	_build_junior_season("F3", true)
	GameManager.save()


## Fills a junior series: ten teams, the story cast where they belong, and generated drivers.
func _build_junior_season(series_id: String, first: bool) -> void:
	var g := state()
	g["series"] = series_id
	g["round"] = 0
	g["teams"] = []
	for row: Array in JUNIOR_TEAMS:
		g["teams"].append({"id": row[0], "name": row[1], "short": row[2], "color": row[3], "color2": row[4],
			"car": float(row[5]) + _rng.randf_range(-1.5, 1.5) - (4.0 if series_id == "F3" else 0.0)})
	var field: Dictionary = g["field"]
	# Keep the player and the cast; everyone else from the last junior season moves on.
	for id: String in field.keys():
		if id != "me" and not CAST.has(id):
			field.erase(id)
	if first:
		field["theo"] = _cast_driver("theo", 76, 96, {"pace": 4, "starts": 2, "consistency": 1}, 18, 7)
		field["marcus"] = _cast_driver("marcus", 71, 91, {"racecraft": 3, "overtaking": 3}, 19, 22)
		field["luca"] = _cast_driver("luca", 72, 88, {"consistency": 7, "tyres": 5, "pace": -3}, 19, 11)
	var seats := {}
	for t: Dictionary in g["teams"]:
		seats[t["id"]] = []
	if first:
		# You and Luca share a midfield F3 team; Theo has the best seat; Marcus is scrapping too.
		_seat(field["me"], "campo", seats)
		_seat(field["luca"], "campo", seats)
		_seat(field["theo"], "premo", seats)
		_seat(field["marcus"], "amersfort", seats)
	else:
		_seat(field["me"], str(g["seat"]), seats)
		# The cast who race in this series this year: Theo always lands a top seat.
		for id: String in ["theo", "marcus", "luca"]:
			var d: Dictionary = field.get(id, {})
			if d.is_empty() or str(d.get("series", "F3")) != series_id:
				continue
			var open: Array = seats.keys().filter(func(k: String) -> bool: return (seats[k] as Array).size() < 2)
			var want := "premo" if id == "theo" else str(open[_rng.randi() % open.size()])
			_seat(d, want if open.has(want) else str(open[0]), seats)
	# Real junior drivers race in F2 alongside the cast.
	if series_id == "F2":
		var base: Array = SaveManager.load_json("res://data/career/drivers.json")
		for d: Dictionary in base:
			if d.get("reserve", false) and int(d["age"]) <= 27 and Career.driver_overall(d) <= 82:
				var copy := d.duplicate(true)
				copy["series"] = "F2"
				copy["home_team"] = copy["team"]
				var open: Array = seats.keys().filter(func(k: String) -> bool: return (seats[k] as Array).size() < 2)
				if open.is_empty():
					break
				_seat(copy, str(open[_rng.randi() % open.size()]), seats)
				field[copy["id"]] = copy
	var n := 0
	for t_id: String in seats:
		while (seats[t_id] as Array).size() < 2:
			var d := _generated(series_id, n)
			field[d["id"]] = d
			_seat(d, t_id, seats)
			n += 1
	g["points"] = {}
	g["team_points"] = {}
	for id: String in field:
		if str(field[id].get("series", "")) == series_id:
			g["points"][id] = 0
	for t: Dictionary in g["teams"]:
		g["team_points"][t["id"]] = 0
	_sim = null


func _seat(d: Dictionary, team_id: String, seats: Dictionary) -> void:
	d["team"] = team_id
	d["series"] = state()["series"]
	(seats[team_id] as Array).append(d["id"])
	if d["id"] == "me":
		state()["seat"] = team_id


func _cast_driver(id: String, base: int, cap: int, edge: Dictionary, age: int, number: int) -> Dictionary:
	var info: Dictionary = CAST[id]
	var d := {"id": id, "name": str(info["name"]).capitalize(), "number": number, "look": info["look"], "age": age, "ego": 70 if id == "theo" else 45,
		"ego_cap": 90, "morale": 75, "fitness": 93, "cast": true}
	var caps := {}
	for key: String in SKILLS:
		d[key] = base + int(edge.get(key, 0))
		caps[key] = clampi(cap + int(edge.get(key, 0)) / 2, base + 2, 99)
	caps["fitness"] = 97
	d["caps"] = caps
	d["potential"] = caps["pace"]
	return d


func _generated(series_id: String, n: int) -> Dictionary:
	var low := 58 if series_id == "F3" else 66
	var base := _rng.randi_range(low, low + 15)
	var d := {"id": "gl_%s_%d_%d" % [series_id, int(state()["season"]), n], "age": _rng.randi_range(17, 22) if series_id == "F3" else _rng.randi_range(19, 25),
		"name": "%s %s" % [Career.FIRST_NAMES[_rng.randi() % Career.FIRST_NAMES.size()], Career.LAST_NAMES[_rng.randi() % Career.LAST_NAMES.size()]],
		"number": _rng.randi_range(2, 99), "look": PixelArt.random_look(_rng.randi(), 2), "ego": _rng.randi_range(30, 85), "morale": 70, "fitness": 92}
	var caps := {}
	var growth := _rng.randi_range(2, 18)
	for key: String in SKILLS:
		d[key] = clampi(base + _rng.randi_range(-6, 6), 50, 90)
		caps[key] = clampi(int(d[key]) + growth + _rng.randi_range(-3, 3), int(d[key]), 97)
	caps["fitness"] = 96
	d["caps"] = caps
	d["potential"] = caps["pace"]
	return d


# ---------------------------------------------------------------- calendar and standings

func round_track(index: int = -1) -> String:
	var r := int(state()["round"]) if index < 0 else index
	if in_f1():
		return str(Career.calendar[r % Career.calendar.size()]["track"])
	return JUNIOR_TRACKS[r % JUNIOR_TRACKS.size()]


func round_name(index: int = -1) -> String:
	var r := int(state()["round"]) if index < 0 else index
	if in_f1():
		return str(Career.calendar[r % Career.calendar.size()]["name"]).to_upper()
	return "%s  %s" % [state()["series"], JUNIOR_ROUND_NAMES[r % JUNIOR_ROUND_NAMES.size()]]


func rounds() -> int:
	return int(series()["rounds"])


func season_over() -> bool:
	return int(state()["round"]) >= rounds()


func team(id: String) -> Dictionary:
	for t: Dictionary in state()["teams"]:
		if t["id"] == id:
			return t
	return {}


func my_team() -> Dictionary:
	return team(str(state()["seat"]))


func racing(id: String) -> bool:
	var d: Dictionary = state()["field"].get(id, {})
	return not d.is_empty() and str(d.get("series", "")) == str(state()["series"]) and str(d.get("team", "")) != "" and not d.get("reserve", false)


func standings() -> Array:
	var rows: Array = []
	var pts: Dictionary = state()["points"]
	for id: String in pts:
		var d: Dictionary = state()["field"].get(id, {})
		if d.is_empty():
			continue
		rows.append({"id": id, "name": d["name"], "team": d.get("team", ""), "points": int(pts[id])})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["points"] > b["points"] or (a["points"] == b["points"] and a["name"] < b["name"]))
	return rows


func my_position() -> int:
	var rows := standings()
	for i in rows.size():
		if rows[i]["id"] == "me":
			return i + 1
	return rows.size()


func overall(id: String = "me") -> int:
	var d: Dictionary = state()["field"].get(id, {})
	return Career.driver_overall(d) if not d.is_empty() else 0


# ---------------------------------------------------------------- race weekend

func _entries() -> Array:
	var out: Array = []
	var g := state()
	for id: String in g["field"]:
		if not racing(id):
			continue
		var d: Dictionary = g["field"][id]
		var t := team(str(d["team"]))
		out.append({"id": id, "name": d["name"], "team": t["id"], "short": t["short"], "color": t["color"], "color2": t.get("color2", "#f4f6f2"), "number": d["number"],
			"is_player": id == "me", "car": float(t["car"]), "pace": float(d["pace"]), "racecraft": float(d["racecraft"]), "consistency": float(d["consistency"]),
			"ego": float(d["ego"]), "morale": float(d["morale"]), "wet": float(d["wet"]), "tyres": float(d["tyres"]), "overtaking": float(d["overtaking"]),
			"defending": float(d["defending"]), "starts": float(d["starts"]), "form": 0.0})
	return out


## This weekend's simulation (qualifying already run), kept until the race is booked.
func weekend() -> GPSim:
	var key := "%d|%s|%d|%d" % [SaveManager.slot, state()["series"], int(state()["season"]), int(state()["round"])]
	if _sim == null or key != _sim_key:
		_sim_key = key
		_sim = GPSim.new()
		_sim.setup(_entries(), {"laps": 20, "rain": 0.12, "wear": 1.0, "safety_car": 0.05}, 2, int(Time.get_ticks_usec()))
		if _opener():
			# The story starts at the back: P19 at Monza.
			var times: Array = []
			for car in _sim.cars:
				if car["id"] != "me":
					times.append(float(car["quali"]))
			times.sort()
			for car in _sim.cars:
				if car["id"] == "me":
					car["quali"] = (float(times[times.size() - 2]) + float(times[times.size() - 1])) * 0.5
			_sim.regrid()
	return _sim


func _opener() -> bool:
	return int(state()["season"]) == 1 and int(state()["round"]) == 0 and state()["series"] == "F3"


func grid_position() -> int:
	for car in weekend().cars:
		if car["id"] == "me":
			return int(car["position"])
	return 0


## The car each series races (everyone has the same one below F1).
func car_setup() -> CarSetup:
	var data: Dictionary = GameManager.default_profile()["car_setup"]
	var parts: Dictionary = series()["car"]
	for slot: String in parts:
		if PartDB.has_part(parts[slot]):
			data["parts"][slot] = parts[slot]
	return CarSetup.from_dict(data)


func prepare_drive() -> void:
	build_drive()
	GameManager.start_session(GameManager.MODE_RACE)


## Sets up the on-track race: you against the seven cars around you on the grid.
func build_drive() -> void:
	var sim := weekend()
	var index := 0
	for i in sim.cars.size():
		if sim.cars[i]["id"] == "me":
			index = i
	var start := clampi(index - 3, 0, sim.cars.size() - 8)
	var mine_car := float(my_team()["car"])
	var rivals: Array = []
	var parts: Dictionary = series()["car"]
	for i in range(start, start + 8):
		var car: Dictionary = sim.cars[i]
		if car["id"] == "me":
			continue
		var d: Dictionary = state()["field"][car["id"]]
		var setup := parts.duplicate()
		rivals.append({"id": car["id"], "name": car["name"], "color": car["color"], "color2": car.get("color2", "#f4f6f2"),
			"pace": clampf(0.95 + (float(car["car"]) - mine_car) * 0.004, 0.88, 0.99), "braking_accuracy": clampf(float(d["consistency"]) / 100.0, 0.7, 0.97),
			"consistency": clampf(float(d["consistency"]) / 100.0, 0.7, 0.97), "aggression": clampf(float(d["ego"]) / 100.0, 0.3, 0.9), "tire_management": 0.7,
			"error_rate": clampf((100.0 - float(d["consistency"])) / 170.0, 0.03, 0.2), "wet": clampf(float(d["wet"]) / 100.0, 0.4, 1.0),
			"attrs": Career.driver_attributes(d), "setup": setup})
	var t := my_team()
	GameManager.track_id = round_track()
	GameManager.session_weather = sim.weather
	GameManager.session_night = false
	GameManager.race_laps = GameManager.RACE_LAPS
	GameManager.mandatory_stop = bool(series()["stop"]) and sim.weather == 0
	GameManager.career_race = {"glory": true, "driver": "me", "driver_name": me()["name"], "rivals": rivals, "race": round_name(),
		"attrs": Career.driver_attributes(me()), "setup": car_setup().to_dict(), "livery": [t["color"], t.get("color2", "#f4f6f2")],
		"grid_slot": index - start}
	GameManager.active_mission = -1
	GameManager.session_mode = GameManager.MODE_RACE


## Books a race you drove: `track_position` is your finish among the eight cars on track.
func finish_drive(track_position: int, completed: bool) -> Dictionary:
	var info: Dictionary = GameManager.career_race
	var sim := weekend()
	while not sim.finished():
		Career.auto_strategy(sim)
		sim.step()
	var order: Array = sim.cars.duplicate()
	var mine: Dictionary = {}
	for car: Dictionary in order:
		if car["id"] == "me":
			mine = car
	order.erase(mine)
	if not completed:
		mine["dnf"] = true
		order.append(mine)
	else:
		mine["dnf"] = false
		var rival_ids: Array = info["rivals"].map(func(r: Dictionary) -> String: return r["id"])
		var slots: Array = []
		for i in order.size():
			if rival_ids.has(order[i]["id"]) and not order[i]["dnf"]:
				slots.append(i)
		var at := order.size()
		if track_position - 1 < slots.size():
			at = slots[track_position - 1]
		elif not slots.is_empty():
			at = int(slots[slots.size() - 1]) + 1
		# The cars on track stand in for the whole race: P1 on track wins it.
		if not slots.is_empty():
			var share := float(slots.size() + 1 - clampi(track_position, 1, slots.size() + 1)) / float(maxi(1, slots.size()))
			at = maxi(0, at - int(round(int(slots[0]) * share)))
		while at > 0 and order[at - 1]["dnf"]:
			at -= 1
		order.insert(at, mine)
	GameManager.career_race = {}
	return _book(order)


## Simulates the whole race without driving it.
func quick_sim() -> Dictionary:
	var sim := weekend()
	while not sim.finished():
		Career.auto_strategy(sim)
		sim.step()
	var order: Array = sim.cars.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["dnf"] != b["dnf"]:
			return not a["dnf"]
		return int(a["position"]) < int(b["position"]))
	return _book(order)


## Points, stats, development, story, and on to the next round.
func _book(order: Array) -> Dictionary:
	var g := state()
	var grid := grid_position()
	var rows: Array = []
	var my_pos := 0
	for i in order.size():
		var car: Dictionary = order[i]
		var pos := i + 1
		var pts := POINTS[i] if i < POINTS.size() and not car["dnf"] else 0
		g["points"][car["id"]] = int(g["points"].get(car["id"], 0)) + pts
		g["team_points"][car["team"]] = int(g["team_points"].get(car["team"], 0)) + pts
		rows.append({"id": car["id"], "name": car["name"], "team": car["team"], "pos": pos, "dnf": car["dnf"], "points": pts})
		if car["id"] == "me":
			my_pos = 0 if car["dnf"] else pos
	var s: Dictionary = g["stats"]
	s["starts"] = int(s["starts"]) + 1
	if my_pos == 1:
		s["wins"] = int(s["wins"]) + 1
	if my_pos >= 1 and my_pos <= 3:
		s["podiums"] = int(s["podiums"]) + 1
	s["points"] = int(s["points"]) + (POINTS[my_pos - 1] if my_pos >= 1 and my_pos <= POINTS.size() else 0)
	_milestones(my_pos)
	var luca_pos := 0
	for r: Dictionary in rows:
		if r["id"] == "luca" and not r["dnf"]:
			luca_pos = int(r["pos"])
	var report := {"race": round_name(), "series": g["series"], "grid": grid, "position": my_pos, "rows": rows, "luca": luca_pos, "marcus": _pos_of(rows, "marcus"), "theo": _pos_of(rows, "theo")}
	g["last"] = report
	_develop_all(rows)
	g["reputation"] = clampi(int(g["reputation"]) + (8 if my_pos == 1 else (4 if my_pos > 0 and my_pos <= 3 else (1 if my_pos > 0 and my_pos <= 10 else -1))), 0, 100)
	_story_after_race(report)
	g["round"] = int(g["round"]) + 1
	_sim = null
	if season_over():
		_season_end()
	GameManager.save()
	return report


func _pos_of(rows: Array, id: String) -> int:
	for r: Dictionary in rows:
		if r["id"] == id:
			return 0 if r["dnf"] else int(r["pos"])
	return -1


func _milestones(pos: int) -> void:
	var g := state()
	var tag: String = g["series"]
	var flags: Dictionary = g["flags"]
	var add := func(key: String, text: String) -> void:
		if not flags.get(key, false):
			flags[key] = true
			(g["milestones"] as Array).append({"text": text, "season": int(g["season"]), "year": int(g["year"])})
	add.call("debut_" + tag, "%s DEBUT" % tag)
	if pos >= 1 and pos <= 3:
		add.call("podium_" + tag, "FIRST %s PODIUM" % tag)
	if pos == 1:
		add.call("win_" + tag, "FIRST %s WIN" % tag)


## After every race everyone learns; young drivers fastest, the best results most.
func _develop_all(rows: Array) -> void:
	var g := state()
	for r: Dictionary in rows:
		var d: Dictionary = g["field"].get(r["id"], {})
		if d.is_empty():
			continue
		var age := int(d["age"])
		var curve := 1.0 if age <= 21 else (0.7 if age <= 25 else (0.35 if age <= 29 else 0.1))
		var result := 1.35 if not r["dnf"] and int(r["pos"]) <= 5 else (1.0 if not r["dnf"] else 0.6)
		var boost := 1.3 if r["id"] == "me" else 1.0         # you put in the extra hours
		for key: String in SKILLS:
			var room := maxf(0.0, Career.stat_cap(d, key) - float(d[key]))
			var gain := minf(room, 0.35 * curve * result * boost * clampf(room / 8.0, 0.3, 1.5))
			if r["id"] == "me" and str(g["academy"]) != "" and ACADEMIES.has(g["academy"]) and ACADEMIES[g["academy"]]["wants"] == key:
				gain *= 1.4                                   # your academy works on what it values
			d[key] = float(d[key]) + gain


# ---------------------------------------------------------------- the story

## Scenes waiting to play on the hub, oldest first.
func next_scene() -> String:
	var q: Array = state().get("story", [])
	return str(q[0]) if not q.is_empty() else ""


func scene_done(id: String) -> void:
	var q: Array = state().get("story", [])
	q.erase(id)
	state()["flags"]["seen_" + id] = true
	GameManager.save()


func queue_scene(id: String) -> void:
	_queue(id)
	GameManager.save()


## Who you are fighting for the F1 seat: Marcus if he made F2, else Luca, else the next best.
func seat_rival() -> String:
	var field: Dictionary = state()["field"]
	for id: String in ["marcus", "luca"]:
		if field.has(id) and racing(id):
			return id
	for row: Dictionary in standings():
		if row["id"] != "me":
			return row["id"]
	return "theo"


## The F1 team principal who calls you (a fixed name for each team).
func principal_name() -> String:
	var team_id := str(state().get("f1_team", "")) if str(state().get("f1_team", "")) != "" else f1_suitor()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("principal_" + team_id)
	return "%s %s" % [["David", "Laurent", "Toto", "Andrea", "James", "Oliver", "Mattia", "Ayao", "Jonathan", "Graeme"][rng.randi() % 10], ["Mercer", "Hale", "Varga", "Castel", "Brandt", "Whitlock", "Nilsen", "Kowal"][rng.randi() % 8]]


## Scenes that come back every time their moment does (season ends, another year down).
const REPEATING: PackedStringArray = ["f3_end", "f2_stay", "f1_season_end", "test_result"]


func _queue(id: String) -> void:
	var g := state()
	if (g["flags"].get("seen_" + id, false) and not REPEATING.has(id)) or (g["story"] as Array).has(id):
		return
	(g["story"] as Array).append(id)


## Before a race: story beats that depend on the grid.
func before_race() -> void:
	var g := state()
	if g["phase"] != "climb":
		return
	if g["series"] == "F3" and int(g["round"]) >= 1 and grid_position() >= 15 and not g["flags"].get("seen_scout", false):
		g["objective"] = {"text": "FINISH P10 OR HIGHER", "target": 10, "scene": "scout"}
		_queue("scout")
	if g["series"] == "F2" and int(g["round"]) == rounds() - 1 and g["flags"].get("seen_f1_test", false):
		_queue("final_call")
	GameManager.save()


func _story_after_race(report: Dictionary) -> void:
	var g := state()
	if g["phase"] != "climb":
		return
	var pos := int(report["position"])
	if g["series"] == "F3" and int(g["round"]) == 0:
		g["flags"]["orders_ignored"] = report["luca"] > 0 and pos > 0 and pos < int(report["luca"]) and report["grid"] > 15
		_queue("monza_after")
	if pos > 0 and pos <= 10:
		_queue("theo_good_race")
	var objective: Dictionary = g["objective"]
	if not objective.is_empty():
		var met: bool = pos > 0 and pos <= int(objective["target"])
		g["flags"]["objective_met"] = met
		g["reputation"] = clampi(int(g["reputation"]) + (10 if met else -2), 0, 100)
		g["objective"] = {}
		_queue("scout_result")
	if g["series"] == "F3" and int(g["round"]) == 2:
		_queue("academies")
	if g["series"] == "F2" and int(g["round"]) == 0:
		_queue("f2_open")
	if g["series"] == "F2" and int(g["round"]) == 2 and _f1_interest() >= 35:
		_queue("f1_test")
	if g["series"] == "F2" and int(g["round"]) == 3 and g["flags"].get("seen_f1_test", false):
		_queue("theo_announced")


## How interested F1 teams are: your overall, results and reputation (0-100).
func _f1_interest() -> int:
	var g := state()
	var pos := my_position() if int(g["round"]) > 0 else 10
	return clampi(int((overall() - 70) * 2.5 + float(g["reputation"]) * 0.5 + (12 - pos) * 2.0 + float(g["flags"].get("test_score", 0))), 0, 100)


## The academy you chose ("" = independent).
func choose_academy(team_id: String) -> void:
	state()["academy"] = team_id
	state()["reputation"] = clampi(int(state()["reputation"]) + (5 if team_id != "" else 0), 0, 100)
	GameManager.save()


## The academies that want you: the ones whose favourite stat you are good at.
func academy_offers() -> Array:
	var out: Array = []
	for id: String in ACADEMIES:
		var wants: String = ACADEMIES[id]["wants"]
		if float(me()[wants]) >= 66.0 or my_position() <= 6:
			out.append(id)
	return out


## The real F1 team most likely to sign you (your academy's team if you joined one).
func f1_suitor() -> String:
	var g := state()
	if str(g["academy"]) != "":
		return str(g["academy"])
	var weakest := ""
	var low := 999.0
	for t: Dictionary in Career.teams:
		if float(t["car"]) < low:
			low = float(t["car"])
			weakest = t["id"]
	return weakest


## The F1 test: a time trial in an F1 car. `ratio` = best lap / the car's ideal lap.
func prepare_test() -> void:
	var t := Career.team(f1_suitor())
	GameManager.track_id = "monza"
	GameManager.session_weather = 0
	GameManager.session_night = false
	var data: Dictionary = GameManager.default_profile()["car_setup"]
	for slot: String in SERIES["F1"]["car"]:
		data["parts"][slot] = SERIES["F1"]["car"][slot]
	GameManager.career_race = {"glory": true, "test": true, "driver": "me", "driver_name": me()["name"], "rivals": [], "race": "F1 TEST",
		"attrs": Career.driver_attributes(me()), "setup": data, "livery": [t["color"], t["color2"]]}
	GameManager.start_session(GameManager.MODE_TIME_TRIAL)


func finish_test(best_lap: float, ideal: float) -> Dictionary:
	var g := state()
	GameManager.career_race = {}
	var ratio := best_lap / maxf(ideal, 1.0) if best_lap > 0.0 else 9.0
	# About 1.2x the ideal is a good lap from a rookie; every 1% better adds interest.
	var score := clampi(int(round((1.3 - ratio) * 200.0)), 0, 40)
	g["flags"]["test_score"] = score
	g["flags"]["test_done"] = true
	(g["milestones"] as Array).append({"text": "F1 TEST", "season": int(g["season"]), "year": int(g["year"])})
	g["reputation"] = clampi(int(g["reputation"]) + score / 4, 0, 100)
	_queue("test_result")
	GameManager.save()
	return {"score": score, "best": best_lap}


## The season is over: titles, offers, promotion - or another year where you are.
func _season_end() -> void:
	var g := state()
	var pos := my_position()
	var tag: String = g["series"]
	(g["milestones"] as Array).append({"text": "%s CHAMPIONSHIP: P%d" % [tag, pos], "season": int(g["season"]), "year": int(g["year"])})
	if pos == 1:
		g["stats"]["titles"] = int(g["stats"]["titles"]) + 1
	g["history"].append({"year": int(g["year"]), "series": tag, "team": str(my_team().get("name", "")), "pos": pos, "points": int(g["points"].get("me", 0))})
	if g["phase"] == "climb":
		if tag == "F3":
			g["offers"] = _junior_offers(pos)
			_queue("f3_end")
		elif tag == "F2":
			var signed := _f2_decides(pos)
			_queue("phone_call" if signed else "f2_stay")
	else:
		g["offers"] = _f1_offers()
		_queue("f1_season_end")


## F2 offers after F3: the champion picks from the best teams; outside the top ten, stay in F3.
func _junior_offers(pos: int) -> Array:
	var teams: Array = JUNIOR_TEAMS.duplicate()
	if pos > 10 and int(state()["reputation"]) < 40:
		return []
	var from := 0 if pos == 1 else (2 if pos <= 4 else 5)
	var out: Array = []
	for i in range(from, mini(from + 3, teams.size())):
		out.append(teams[i][0])
	return out


## Moves you up: F3 -> F2 with the team you picked (or "" to stay in F3).
func accept_junior_offer(team_id: String) -> void:
	var g := state()
	_age_world()
	g["season"] = int(g["season"]) + 1
	g["year"] = int(g["year"]) + 1
	if team_id == "":
		g["seat"] = "campo" if g["seat"] == "" else g["seat"]
		_build_junior_season("F3", false)
	else:
		g["seat"] = team_id
		# The cast moves up too, if they are good enough.
		for id: String in ["theo", "marcus", "luca"]:
			var d: Dictionary = g["field"][id]
			d["series"] = "F2" if Career.driver_overall(d) >= 70 or id == "theo" else "F3"
		g["field"]["theo"]["want"] = "premo"
		_build_junior_season("F2", false)
	g["offers"] = []
	GameManager.save()


## The finale decides it: beat Marcus (and be good enough) and the F1 call comes.
func _f2_decides(pos: int) -> bool:
	var g := state()
	var last: Dictionary = g["last"]
	var rival_pos := _pos_of(last.get("rows", []), seat_rival())
	var beat_marcus: bool = int(last.get("position", 0)) > 0 and (rival_pos <= 0 or int(last["position"]) < rival_pos)
	var interest := _f1_interest()
	var signed := (beat_marcus and interest >= 40) or pos <= 3 or interest >= 75
	g["flags"]["beat_marcus"] = beat_marcus
	g["f1_team"] = f1_suitor() if signed else ""
	return signed


## Another F2 year after missing out.
func stay_in_f2() -> void:
	var g := state()
	_age_world()
	g["season"] = int(g["season"]) + 1
	g["year"] = int(g["year"]) + 1
	for key: String in ["seen_f1_test", "seen_theo_announced", "seen_final_call", "seen_phone_call", "seen_f2_stay", "seen_test_result", "test_done"]:
		g["flags"].erase(key)
	_build_junior_season("F2", false)


## Formula One. The story ends here; the career that follows is yours.
func join_f1() -> void:
	var g := state()
	var team_id: String = g["f1_team"]
	_age_world()
	g["season"] = int(g["season"]) + 1
	g["year"] = int(g["year"]) + 1
	g["series"] = "F1"
	g["round"] = 0
	g["contract"] = 2
	(g["milestones"] as Array).append({"text": "FORMULA ONE CONTRACT", "season": int(g["season"]), "year": int(g["year"])})
	g["teams"] = []
	for t: Dictionary in Career.teams:
		g["teams"].append({"id": t["id"], "name": t["name"], "short": t["short"], "color": t["color"], "color2": t["color2"], "car": float(t["car"]),
			"potential": float(t.get("car_card", {}).get("potential", 95))})
	var field: Dictionary = g["field"]
	var base: Array = SaveManager.load_json("res://data/career/drivers.json")
	for d: Dictionary in base:
		if field.has(d["id"]):
			field[d["id"]]["series"] = "F1"
			field[d["id"]]["team"] = d["team"]
			field[d["id"]]["reserve"] = d.get("reserve", false)
			continue
		var copy := d.duplicate(true)
		copy["series"] = "F1"
		field[copy["id"]] = copy
	# Theo was announced for F1 during your last F2 season: he gets the junior team's seat.
	var theo_team := "rcb" if team_id != "rcb" else "has"
	if field.has("theo"):
		var dropped := ""
		for id: String in field:
			var d: Dictionary = field[id]
			if str(d.get("series", "")) == "F1" and d.get("team", "") == theo_team and not d.get("reserve", false) and id != "theo":
				if dropped == "" or Career.driver_overall(d) < Career.driver_overall(field[dropped]):
					dropped = id
		if dropped != "":
			field[dropped]["reserve"] = true
		field["theo"]["series"] = "F1"
		field["theo"]["team"] = theo_team
		field["theo"]["reserve"] = false
	# You take the weaker race seat at your new team; that driver drops to the bench.
	var weakest := ""
	for id: String in field:
		var d: Dictionary = field[id]
		if str(d.get("series", "")) == "F1" and d.get("team", "") == team_id and not d.get("reserve", false) and id != "me":
			if weakest == "" or Career.driver_overall(d) < Career.driver_overall(field[weakest]):
				weakest = id
	if weakest != "":
		field[weakest]["reserve"] = true
	var you := me()
	you["series"] = "F1"
	you["team"] = team_id
	you["reserve"] = false
	g["seat"] = team_id
	g["phase"] = "f1"
	g["points"] = {}
	g["team_points"] = {}
	for id: String in field:
		if racing(id):
			g["points"][id] = 0
	for t: Dictionary in g["teams"]:
		g["team_points"][t["id"]] = 0
	_sim = null
	GameManager.save()


## After the story: contract offers from F1 teams that rate you.
func _f1_offers() -> Array:
	var g := state()
	var out: Array = []
	var ovr := overall()
	var pos := my_position()
	for t: Dictionary in g["teams"]:
		var bar := 70.0 + (float(t["car"]) - 75.0) * 0.9          # top teams want top drivers
		if ovr + (12 - pos) * 0.6 >= bar and t["id"] != g["seat"]:
			out.append(t["id"])
	out.sort_custom(func(a: String, b: String) -> bool: return float(team(a)["car"]) > float(team(b)["car"]))
	return out.slice(0, 3)


## Next F1 season: stay, or sign for `team_id`.
func next_f1_season(team_id: String = "") -> void:
	var g := state()
	if team_id != "" and team_id != g["seat"]:
		var field: Dictionary = g["field"]
		var weakest := ""
		for id: String in field:
			var d: Dictionary = field[id]
			if racing(id) and d["team"] == team_id and id != "me":
				if weakest == "" or Career.driver_overall(d) < Career.driver_overall(field[weakest]):
					weakest = id
		if weakest != "":
			field[weakest]["team"] = g["seat"]           # a straight swap of seats
		me()["team"] = team_id
		g["seat"] = team_id
		g["contract"] = 2
	else:
		g["contract"] = maxi(1, int(g["contract"]) - 1)
	_age_world()
	g["season"] = int(g["season"]) + 1
	g["year"] = int(g["year"]) + 1
	g["round"] = 0
	for t: Dictionary in g["teams"]:
		t["car"] = clampf(float(t["car"]) + _rng.randf_range(-3.0, 3.5), 60.0, float(t.get("potential", 96)))
	g["points"] = {}
	g["team_points"] = {}
	for id: String in g["field"]:
		if racing(id):
			g["points"][id] = 0
	for t: Dictionary in g["teams"]:
		g["team_points"][t["id"]] = 0
	g["offers"] = []
	_sim = null
	GameManager.save()


## A year passes: everyone ages, the young improve, veterans fade (pace first, racecraft and
## tyre care last), the oldest retire and rookies take their seats. You retire when you choose.
func _age_world() -> void:
	var g := state()
	var field: Dictionary = g["field"]
	for id: String in field.keys():
		var d: Dictionary = field[id]
		d["age"] = int(d["age"]) + 1
		var age := int(d["age"])
		if age >= 31:
			var fade := 0.6 + (age - 31) * 0.25
			d["pace"] = maxf(50.0, float(d["pace"]) - fade)
			d["starts"] = maxf(50.0, float(d["starts"]) - fade * 0.8)
			d["fitness"] = maxi(60, int(d.get("fitness", 92)) - 1)
			if age <= 34:
				for key: String in ["racecraft", "tyres", "consistency"]:
					d[key] = minf(Career.stat_cap(d, key) + 2.0, float(d[key]) + 0.6)
		if id != "me" and str(d.get("series", "")) == "F1" and age >= 37 and _rng.randf() < 0.35 + (age - 37) * 0.2:
			_retire(id)
	# Rookies: the best juniors and the cast get F1 seats that open up.
	if in_f1():
		_fill_f1_seats()


func _retire(id: String) -> void:
	var g := state()
	var d: Dictionary = g["field"][id]
	_news("%s retires after a long career." % d["name"])
	g["field"].erase(id)
	g["points"].erase(id)


func _fill_f1_seats() -> void:
	var g := state()
	for t: Dictionary in g["teams"]:
		var count := 0
		for id: String in g["field"]:
			if racing(id) and g["field"][id]["team"] == t["id"]:
				count += 1
		while count < 2:
			var pick := ""
			for id: String in ["theo", "marcus", "luca"]:
				if g["field"].has(id) and str(g["field"][id].get("series", "")) != "F1":
					pick = id
					break
			var d: Dictionary
			if pick != "":
				d = g["field"][pick]
			else:
				d = _generated("F2", _rng.randi() % 1000)
				d["age"] = _rng.randi_range(19, 21)
				for key: String in SKILLS:
					d[key] = float(d[key]) + 6.0
				g["field"][d["id"]] = d
			d["series"] = "F1"
			d["team"] = t["id"]
			d["reserve"] = false
			_news("%s gets an F1 seat with %s." % [d["name"], t["name"]])
			count += 1


func _news(text: String) -> void:
	var g := state()
	if not g.has("news"):
		g["news"] = []
	(g["news"] as Array).push_front(text)
	while (g["news"] as Array).size() > 12:
		(g["news"] as Array).pop_back()


## You decide when it ends.
func retire() -> void:
	var g := state()
	(g["milestones"] as Array).append({"text": "RETIRED AT %d" % int(me()["age"]), "season": int(g["season"]), "year": int(g["year"])})
	g["active"] = false
	g["retired"] = true
	GameManager.save()
