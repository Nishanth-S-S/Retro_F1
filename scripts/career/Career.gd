extends Node
## Autoload "Career": the team-principal layer. Owns teams, drivers, contracts, sponsors,
## the factory, board confidence and the dilemma events. All content is data in
## data/career/*.json; all state lives in GameManager.profile["career"] so it saves.

const SALARY_CAP := 55000            # $k per season for the two race seats
const COST_CAP := 70000              # $k per season of car spending (parts + factory)
const FACTORY_MAX := 5
## Price of each of the three scouting phases ($k). The last one reveals true potential.
const SCOUT_COSTS: PackedInt32Array = [400, 700, 1200]
const MAX_RESERVES := 2
## Share of a reserve driver's salary that is paid and counts against the cap.
const RESERVE_SALARY_SHARE := 0.3
const DEPARTMENTS := {
	"aero": {"name": "AERO DEPT", "note": "+1.5 car rating per level"},
	"power": {"name": "POWER UNIT", "note": "+1.5 car rating per level"},
	"pit": {"name": "PIT CREW", "note": "-0.5 s per pit stop per level"},
	"rd": {"name": "R&D LAB", "note": "unlocks new parts in the garage"},
}
const POINTS: PackedInt32Array = [25, 18, 15, 12, 10, 8, 6, 4, 2, 1]
const SEASON_PRIZE: PackedInt32Array = [30000, 26000, 23000, 20000, 17000, 15000, 13000, 11000, 9000, 8000, 7000]
const FIRST_NAMES: PackedStringArray = ["Teo", "Arlo", "Niko", "Juno", "Rafa", "Emil", "Kai", "Luca", "Mika", "Dario", "Yuki", "Sami", "Otto", "Remy", "Zane", "Ines", "Mara", "Tavi"]
const LAST_NAMES: PackedStringArray = ["Varga", "Okafor", "Brandt", "Ito", "Delacroix", "Whitlock", "Nilsen", "Moreau", "Kowal", "Santoro", "Hale", "Rahim", "Lund", "Pereira", "Novak", "Finch", "Aoki", "Castel"]

var teams: Array = []
var calendar: Array = []
var sponsors: Array = []
var events: Array = []
var rd_tiers: Array = []
var _base_drivers: Array = []
var _config: VehiclePhysicsConfig = preload("res://data/physics/default_physics.tres")
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	teams = _load("teams")
	calendar = _load("calendar")
	sponsors = _load("sponsors")
	events = _load("events")
	rd_tiers = _load("rd_tiers")
	_base_drivers = _load("drivers")
	_rng.randomize()


func _load(file: String) -> Array:
	var data: Variant = SaveManager.load_json("res://data/career/%s.json" % file)
	return data if data is Array else []


# ---------------------------------------------------------------- state access

func state() -> Dictionary:
	return GameManager.profile.get("career", {})


func active() -> bool:
	var c := state()
	if c.is_empty() or not c.get("active", false):
		return false
	if not c.has("reserves"):
		c["reserves"] = []
	if not c.has("people"):
		# Careers saved before the phone existed get their paddock filled in.
		c["inbox"] = []
		_generate_people()
	return true


func team(id: String) -> Dictionary:
	for t: Dictionary in teams:
		if t["id"] == id:
			return t
	return {}


func my_team() -> Dictionary:
	return team(state().get("team", ""))


func driver(id: String) -> Dictionary:
	return state()["drivers"].get(id, {})


func lineup() -> Array:
	return state()["lineup"]


func rd_level() -> int:
	return int(state()["factory"]["rd"]) if active() else 0


## Garage unlock tier of a part: 0 = available from the start.
func part_tier(part_id: String) -> int:
	for tier: Dictionary in rd_tiers:
		if (tier["unlocks"] as Array).has(part_id):
			return int(tier["level"])
	return 0


static func money_text(amount_k: float) -> String:
	if absf(amount_k) >= 1000.0:
		return "%s$%.1fM" % ["-" if amount_k < 0 else "", absf(amount_k) / 1000.0]
	return "%s$%dk" % ["-" if amount_k < 0 else "", int(absf(amount_k))]


# ---------------------------------------------------------------- new career

func new_career(team_id: String, manager: Dictionary) -> void:
	var drivers := {}
	for d: Dictionary in _base_drivers:
		var copy := d.duplicate(true)
		copy["morale"] = 60
		copy["junior"] = false
		drivers[d["id"]] = copy
	var career := {
		"active": true, "manager": manager, "team": team_id, "season": 1, "round": 0,
		"drivers": drivers, "lineup": [], "reserves": [], "number_one": "",
		"sponsor": {}, "sponsor_offers": [],
		"factory": {"aero": 0, "power": 0, "pit": 0, "rd": 0},
		"board": 60, "reputation": 50 - int(team(team_id)["expectation"]) * 2 + 10, "fia": 0, "cap_spent": 0, "car_bonus": 0.0,
		"points": {}, "team_points": {}, "team_cars": {},
		"pending_event": {}, "last_event": "", "promise": 0, "audited": false, "fired": false, "last_report": {},
		"people": {}, "inbox": [],
	}
	for t: Dictionary in teams:
		career["team_cars"][t["id"]] = float(t["car"])
		career["team_points"][t["id"]] = 0
	for id: String in drivers:
		career["points"][id] = 0
		if drivers[id]["team"] == team_id:
			career["lineup"].append(id)
	GameManager.profile["career"] = career
	GameManager.profile["money"] = int(team(team_id)["budget"])
	_generate_juniors()
	_generate_people()
	_add_starting_reserve()
	_refresh_sponsor_offers()
	_sync_unlocks()
	add_message("owner", "Welcome aboard. The target is simple: %s. Don't make me regret this." % board_target_text().to_lower())
	add_message("engineer", "Boss - I'll text you after every race with the damage report. Tap GO TO RACE when you're ready: you can drive it yourself, run the pit wall, or quick-sim.")
	add_message("scout", "I've got eyes on the junior leagues. Check the SCOUTING tab - a report costs %s and tells you a kid's real ceiling." % money_text(150))
	GameManager.save()
	EventBus.money_changed.emit(GameManager.money())


func _generate_juniors() -> void:
	var drivers: Dictionary = state()["drivers"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(state()["team"]) + str(Time.get_ticks_usec()))
	for i in 14:
		var pace := rng.randi_range(58, 76)
		# Three kinds of prospect: rare gems, solid pros, and busts who have already peaked.
		var roll := rng.randf()
		var potential := pace + rng.randi_range(1, 5)
		if roll < 0.18:
			potential = rng.randi_range(90, 98)
		elif roll < 0.65:
			potential = mini(90, pace + rng.randi_range(8, 16))
		# The price follows paddock hype, not the truth - which is why you scout.
		var hype := clampi(pace + rng.randi_range(-7, 7), 56, 82)
		var id := "jr_%d_%d" % [int(state()["season"]), i]
		drivers[id] = {
			"id": id, "name": "%s %s" % [FIRST_NAMES[rng.randi() % FIRST_NAMES.size()], LAST_NAMES[rng.randi() % LAST_NAMES.size()]],
			"team": "", "academy": teams[rng.randi() % teams.size()]["id"], "league": "FORMULA B" if hype >= 68 else "FORMULA C",
			"pace": pace, "racecraft": pace + rng.randi_range(-6, 4), "consistency": pace + rng.randi_range(-8, 3),
			"potential": potential, "ego": rng.randi_range(25, 85), "age": rng.randi_range(17, 21), "hype": hype,
			"salary": 250 + (hype - 56) * 40, "buyout": 300 + (hype - 56) * 220, "number": rng.randi_range(2, 99),
			"morale": 70, "junior": true, "scout_level": 0,
		}


func _add_starting_reserve() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pace := rng.randi_range(66, 72)
	var id := "res_%d" % (rng.randi() % 100000)
	state()["drivers"][id] = {
		"id": id, "name": "%s %s" % [FIRST_NAMES[rng.randi() % FIRST_NAMES.size()], LAST_NAMES[rng.randi() % LAST_NAMES.size()]],
		"team": state()["team"], "pace": pace, "racecraft": pace - 2, "consistency": pace - 3, "potential": pace + rng.randi_range(4, 10),
		"ego": 35, "age": rng.randi_range(20, 23), "salary": 500, "buyout": 0, "number": rng.randi_range(2, 99), "morale": 70, "junior": false, "scout_level": 3,
	}
	state()["reserves"].append(id)


func _sync_unlocks() -> void:
	GameManager.profile["story_progress"] = rd_level()


# ---------------------------------------------------------------- ratings

func driver_overall(d: Dictionary) -> int:
	return int(round(float(d["pace"]) * 0.5 + float(d["racecraft"]) * 0.25 + float(d["consistency"]) * 0.25))


## 45-90 score for the car the player has built in the garage.
func build_rating() -> float:
	var s := CarStats.compute(GameManager.setup, _config)
	if not s.valid:
		return 40.0
	var cornering := s.mech_grip_g + s.downforce_200 / (s.mass * VehiclePhysicsConfig.GRAVITY) * 0.5
	var score := 0.3 * clampf(inverse_lerp(250.0, 560.0, s.power_to_weight), 0.0, 1.0) + 0.2 * clampf(inverse_lerp(200.0, 310.0, s.top_speed * 3.6), 0.0, 1.0)
	score += 0.3 * clampf(inverse_lerp(1.5, 2.4, cornering), 0.0, 1.0) + 0.2 * clampf(inverse_lerp(1.9, 3.3, s.braking_g), 0.0, 1.0)
	return 45.0 + 45.0 * score


func car_rating(team_id: String) -> float:
	var base: float = state()["team_cars"].get(team_id, 70.0)
	if team_id != state()["team"]:
		return base
	# Your car = the team's baseline, plus what you built in the garage, plus the factory.
	var f: Dictionary = state()["factory"]
	return clampf(base + (build_rating() - 60.0) * 0.6 + (int(f["aero"]) + int(f["power"])) * 1.5 + float(state()["car_bonus"]), 40.0, 99.0)


func team_drivers(team_id: String) -> Array:
	if team_id == state()["team"]:
		return lineup()
	var out: Array = []
	for id: String in state()["drivers"]:
		if state()["drivers"][id]["team"] == team_id:
			out.append(id)
	return out


func team_rating(team_id: String) -> int:
	var total := 0.0
	var ids := team_drivers(team_id)
	for id: String in ids:
		total += driver_overall(driver(id))
	var avg := total / maxf(ids.size(), 1)
	var pit := 60.0 + 8.0 * (int(state()["factory"]["pit"]) if team_id == state()["team"] else 2)
	return int(round(car_rating(team_id) * 0.5 + avg * 0.35 + pit * 0.15))


# ---------------------------------------------------------------- drivers and contracts

func salary_total(replace_id: String = "", with_id: String = "") -> int:
	var total := 0.0
	for id: String in lineup():
		total += float(driver(with_id if id == replace_id else id)["salary"])
	for id: String in reserves():
		total += float(driver(id)["salary"]) * RESERVE_SALARY_SHARE
	if replace_id == "reserve" and with_id != "":
		total += float(driver(with_id)["salary"]) * RESERVE_SALARY_SHARE
	return int(total)


func reserves() -> Array:
	return state().get("reserves", [])


## Overall rating a driver would have at full potential.
func potential_overall(d: Dictionary) -> int:
	var growth := maxf(0.0, float(d["potential"]) - float(d["pace"]))
	return int(round(float(d["potential"]) * 0.5 + minf(97.0, float(d["racecraft"]) + growth * 0.7) * 0.25 + minf(97.0, float(d["consistency"]) + growth * 0.7) * 0.25))


func market() -> Array:
	var out: Array = []
	for id: String in state()["drivers"]:
		var d: Dictionary = state()["drivers"][id]
		if d["team"] == "" and not lineup().has(id) and not reserves().has(id) and not d.get("hidden", false):
			out.append(d)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["pace"]) > int(b["pace"]))
	return out


func scout_level(d: Dictionary) -> int:
	return int(d.get("scout_level", 3))


func scout_cost(d: Dictionary) -> int:
	return SCOUT_COSTS[clampi(scout_level(d), 0, SCOUT_COSTS.size() - 1)]


## Pays for the next scouting phase. Phase 1 reveals pace, phase 2 racecraft and consistency,
## phase 3 ego and the driver's potential overall.
func scout(id: String) -> bool:
	var d := driver(id)
	if d.is_empty() or scout_level(d) >= 3 or GameManager.money() < scout_cost(d):
		return false
	GameManager.add_money(-scout_cost(d))
	d["scout_level"] = scout_level(d) + 1
	GameManager.save()
	return true


## Signs a market driver into the seat held by `replace_id`. Returns "" or the reason it failed.
func sign_driver(id: String, replace_id: String) -> String:
	var d := driver(id)
	var fee := int(d.get("buyout", 0))
	if replace_id == "reserve" and reserves().size() >= MAX_RESERVES:
		return "Both reserve seats are taken."
	if salary_total(replace_id, id) > SALARY_CAP:
		return "Over the salary cap (%s)." % money_text(SALARY_CAP)
	if GameManager.money() < fee:
		return "Not enough cash for the %s buyout." % money_text(fee)
	GameManager.add_money(-fee)
	if replace_id == "reserve":
		d["team"] = state()["team"]
		d["junior"] = false
		d["morale"] = 70
		reserves().append(id)
		if not state()["points"].has(id):
			state()["points"][id] = 0
		GameManager.save()
		return ""
	var old := driver(replace_id)
	old["team"] = ""
	old["buyout"] = 0
	old["junior"] = false
	d["team"] = state()["team"]
	d["junior"] = false
	d["morale"] = 75
	var seats: Array = lineup()
	seats[seats.find(replace_id)] = id
	if state()["number_one"] == replace_id:
		state()["number_one"] = ""
	if not state()["points"].has(id):
		state()["points"][id] = 0
	GameManager.save()
	return ""


## Swaps a reserve into a race seat; the race driver drops to the bench.
func promote_reserve(reserve_id: String, seat_id: String) -> String:
	if not reserves().has(reserve_id) or not lineup().has(seat_id):
		return "Not possible."
	var seats: Array = lineup()
	var bench: Array = reserves()
	seats[seats.find(seat_id)] = reserve_id
	bench[bench.find(reserve_id)] = seat_id
	if salary_total() > SALARY_CAP:
		seats[seats.find(reserve_id)] = seat_id
		bench[bench.find(seat_id)] = reserve_id
		return "That swap would break the salary cap."
	driver(seat_id)["morale"] = maxi(5, int(driver(seat_id)["morale"]) - 20)
	driver(reserve_id)["morale"] = mini(100, int(driver(reserve_id)["morale"]) + 15)
	if state()["number_one"] == seat_id:
		state()["number_one"] = ""
	GameManager.save()
	return ""


func release_reserve(id: String) -> void:
	reserves().erase(id)
	driver(id)["team"] = ""
	driver(id)["buyout"] = 0
	GameManager.save()


# ---------------------------------------------------------------- injuries and stand-ins

func is_injured(id: String) -> bool:
	return int(driver(id).get("injured", 0)) > 0


## Who actually races this weekend: injured race drivers are replaced by a fit reserve,
## or by an emergency stand-in if the bench is empty.
func race_lineup() -> Array:
	var out: Array = []
	var bench: Array = reserves().duplicate()
	bench.sort_custom(func(a: String, b: String) -> bool: return driver_overall(driver(a)) > driver_overall(driver(b)))
	for id: String in lineup():
		if not is_injured(id):
			out.append(id)
			continue
		var sub := ""
		for r: String in bench:
			if not is_injured(r) and not out.has(r):
				sub = r
				break
		if sub == "":
			sub = _stand_in(out.size())
		else:
			bench.erase(sub)
		out.append(sub)
	return out


func _stand_in(index: int) -> String:
	var id := "standin_%d" % index
	if not state()["drivers"].has(id):
		state()["drivers"][id] = {"id": id, "name": "Stand-in Rookie", "team": "", "hidden": true, "pace": 60, "racecraft": 58, "consistency": 58, "potential": 60,
			"ego": 20, "age": 19, "salary": 0, "buyout": 0, "number": 90 + index, "morale": 60, "junior": false, "scout_level": 3}
	return id


func _injure(d: Dictionary, races: int, reason: String) -> void:
	d["injured"] = races
	d["crashes"] = 0
	var cover := "No reserve on the bench - we'll have to hire a stand-in rookie."
	for r: String in reserves():
		if not is_injured(r):
			cover = "%s steps in from the bench." % driver(r)["name"]
			break
	add_message("engineer", "Medical update: %s is OUT for %d race%s (%s). %s" % [d["name"], races, "" if races == 1 else "s", reason, cover])


## Called once per race for the contracted race drivers.
func _update_fitness(raced: Array) -> void:
	for id: String in lineup():
		var d := driver(id)
		if is_injured(id):
			d["injured"] = int(d["injured"]) - 1
			if int(d["injured"]) <= 0:
				add_message(id, "Doctors cleared me. I'm back in the car next race.")
			continue
		var crashed := false
		for car: Dictionary in raced:
			if car["id"] == id and car.get("crashed", false):
				crashed = true
		if crashed:
			d["crashes"] = int(d.get("crashes", 0)) + 1
			# Every shunt raises the odds that the next one hurts.
			if _rng.randf() < 0.12 + 0.14 * (int(d["crashes"]) - 1):
				_injure(d, _rng.randi_range(1, 3), "hurt in the crash")
		elif int(d["morale"]) < 20 and _rng.randf() < 0.3:
			_injure(d, _rng.randi_range(1, 2), "burnt out - the doctor has signed them off")


# ---------------------------------------------------------------- sponsors

func _refresh_sponsor_offers() -> void:
	var pool := sponsors.duplicate()
	pool.shuffle()
	var offers: Array = []
	for s: Dictionary in pool:
		if offers.size() < 3:
			var offer := s.duplicate()
			offer["negotiated"] = false
			offers.append(offer)
	state()["sponsor_offers"] = offers


func sign_sponsor(index: int) -> String:
	var offers: Array = state()["sponsor_offers"]
	var offer: Dictionary = offers[index]
	if int(state()["reputation"]) < int(offer["min_rep"]):
		return "%s want a team with more reputation (%d)." % [offer["name"], int(offer["min_rep"])]
	state()["sponsor"] = offer.duplicate()
	state()["sponsor"]["races_left"] = int(offer["races"])
	GameManager.add_money(int(offer["signing"]))
	offers.remove_at(index)
	GameManager.save()
	return ""


## One shot at a better deal. Reputation helps; failing makes the sponsor walk away.
func negotiate_sponsor(index: int) -> String:
	var offers: Array = state()["sponsor_offers"]
	var offer: Dictionary = offers[index]
	if offer["negotiated"]:
		return "They won't move any further."
	offer["negotiated"] = true
	var chance := clampf(0.35 + (int(state()["reputation"]) - int(offer["min_rep"])) / 100.0, 0.15, 0.85)
	if _rng.randf() < chance:
		offer["per_race"] = int(int(offer["per_race"]) * 1.2)
		offer["signing"] = int(int(offer["signing"]) * 1.15)
		GameManager.save()
		return "%s improved their offer." % offer["name"]
	offers.remove_at(index)
	GameManager.save()
	return "%s walked away from the table." % offer["name"]


# ---------------------------------------------------------------- factory and cost cap

func cap_left() -> int:
	return COST_CAP - int(state()["cap_spent"])


func charge_cap(amount: int) -> void:
	if active():
		state()["cap_spent"] = int(state()["cap_spent"]) + amount


func upgrade_cost(dept: String) -> int:
	var level := int(state()["factory"][dept])
	if dept == "rd":
		return int(rd_tiers[level]["cost"]) if level < rd_tiers.size() else 0
	return 2500 + level * 1800


func upgrade(dept: String) -> String:
	var level := int(state()["factory"][dept])
	var max_level := rd_tiers.size() if dept == "rd" else FACTORY_MAX
	if level >= max_level:
		return "Already at maximum."
	var cost := upgrade_cost(dept)
	if GameManager.money() < cost:
		return "Not enough cash."
	if cost > cap_left():
		return "That would break the cost cap."
	GameManager.add_money(-cost)
	charge_cap(cost)
	state()["factory"][dept] = level + 1
	_sync_unlocks()
	EventBus.inventory_changed.emit()
	GameManager.save()
	return ""


## Pay the engineers to pick, buy and fit the best available part for you (25% labour markup).
func commission_package() -> String:
	var best: VehiclePart = null
	var best_slot := ""
	var best_gain := 0.2
	var before := build_rating()
	for slot in CarSetup.SLOTS:
		if slot == "ballast":
			continue
		for part: VehiclePart in PartDB.parts_in(CarSetup.SLOT_CATEGORY[slot]):
			if GameManager.setup.parts.get(slot, "") == part.id or not GameManager.is_unlocked(part.id):
				continue
			var cost := 0 if GameManager.is_owned(part.id) else int(part.price * 1.25)
			if cost > GameManager.money() or cost > cap_left():
				continue
			var old: String = GameManager.setup.parts.get(slot, "")
			GameManager.setup.install(slot, part.id)
			var gain := build_rating() - before
			if old == "":
				GameManager.setup.remove(slot)
			else:
				GameManager.setup.install(slot, old)
			if gain > best_gain:
				best_gain = gain
				best = part
				best_slot = slot
	if best == null:
		return "The engineers have nothing better to offer right now. Upgrade R&D or free up budget."
	var price := 0 if GameManager.is_owned(best.id) else int(best.price * 1.25)
	GameManager.add_money(-price)
	charge_cap(price)
	if not GameManager.is_owned(best.id):
		GameManager.profile["owned_parts"].append(best.id)
	GameManager.install_part(best_slot, best.id)
	EventBus.inventory_changed.emit()
	return "Engineers fitted %s (%s) for %s.  Car build +%.1f." % [best.display_name, CarSetup.SLOT_LABELS[best_slot], money_text(price), best_gain]


# ---------------------------------------------------------------- season flow

func season_over() -> bool:
	return int(state()["round"]) >= calendar.size()


func next_round() -> Dictionary:
	return calendar[mini(int(state()["round"]), calendar.size() - 1)]


func round_track() -> String:
	return str(next_round().get("track", "falcon_ridge"))


func board_target_text() -> String:
	var e := int(my_team()["expectation"])
	if e <= 2:
		return "Wins and the title"
	if e <= 4:
		return "Regular podiums"
	return "Points finishes" if e <= 8 else "Beat the backmarkers"


## Entry list for the race simulation.
func race_entries() -> Array:
	var out: Array = []
	for t: Dictionary in teams:
		for id: String in (race_lineup() if t["id"] == state()["team"] else team_drivers(t["id"])):
			var d := driver(id)
			out.append({
				"id": id, "name": d["name"], "team": t["id"], "short": t["short"], "color": t["color"], "number": d["number"],
				"color2": t["color2"], "is_player": t["id"] == state()["team"], "car": car_rating(t["id"]), "pace": float(d["pace"]),
				"racecraft": float(d["racecraft"]), "consistency": float(d["consistency"]), "ego": float(d["ego"]), "morale": float(d["morale"]),
			})
	return out


func standings_drivers() -> Array:
	var rows: Array = []
	for id: String in state()["points"]:
		var d := driver(id)
		if d.is_empty() or (d["team"] == "" and not lineup().has(id)):
			continue
		rows.append({"id": id, "name": d["name"], "team": d["team"], "points": int(state()["points"][id])})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["points"] > b["points"])
	return rows


func standings_teams() -> Array:
	var rows: Array = []
	for t: Dictionary in teams:
		rows.append({"id": t["id"], "name": t["name"], "points": int(state()["team_points"][t["id"]])})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["points"] > b["points"])
	return rows


func team_position() -> int:
	var rows := standings_teams()
	for i in rows.size():
		if rows[i]["id"] == state()["team"]:
			return i + 1
	return rows.size()


## Books a finished race: points, money, morale, board reaction, and queues a dilemma.
func apply_race(order: Array, flags: Dictionary) -> Dictionary:
	var c := state()
	var mine: Array = []
	var podiums := 0
	var points_scored := 0
	for i in order.size():
		var car: Dictionary = order[i]
		var pts := POINTS[i] if i < POINTS.size() and not car["dnf"] else 0
		c["points"][car["id"]] = int(c["points"].get(car["id"], 0)) + pts
		c["team_points"][car["team"]] = int(c["team_points"][car["team"]]) + pts
		if car["is_player"]:
			mine.append({"id": car["id"], "name": car["name"], "position": i + 1, "dnf": car["dnf"], "points": pts})
			points_scored += pts
			if i < 3 and not car["dnf"]:
				podiums += 1
			var d := driver(car["id"])
			var expected := int(my_team()["expectation"]) * 2
			d["morale"] = clampi(int(d["morale"]) + clampi(expected - (i + 1), -6, 6) + (-6 if car["dnf"] else 0), 5, 100)
	_update_fitness(order)
	# --- money
	var sponsor: Dictionary = c["sponsor"]
	var sponsor_income := 0
	if not sponsor.is_empty():
		sponsor_income = int(sponsor["per_race"]) + int(sponsor["podium_bonus"]) * podiums
		sponsor["races_left"] = int(sponsor["races_left"]) - 1
		if int(sponsor["races_left"]) <= 0:
			c["sponsor"] = {}
			_refresh_sponsor_offers()
	var prize := 600 + points_scored * 120
	var salaries := int(salary_total() / float(calendar.size()))
	var f: Dictionary = c["factory"]
	var upkeep := 150 * (int(f["aero"]) + int(f["power"]) + int(f["pit"]) + int(f["rd"]))
	GameManager.add_money(prize + sponsor_income - salaries - upkeep)
	# --- board
	var best := 99
	for m: Dictionary in mine:
		if not m["dnf"]:
			best = mini(best, int(m["position"]))
	var expected_best := int(round(int(my_team()["expectation"]) * 1.6 + 1.0))
	var board_change := clampi(int((expected_best - best) * 1.5), -10, 10) + podiums * 3
	if int(c["promise"]) > 0:
		if podiums > 0:
			c["promise"] = 0
			board_change += 8
		else:
			c["promise"] = int(c["promise"]) - 1
			if int(c["promise"]) == 0:
				board_change -= 15
	c["board"] = clampi(int(c["board"]) + board_change, 0, 100)
	c["reputation"] = clampi(int(c["reputation"]) + podiums * 2 + (1 if points_scored > 0 else -1), 0, 100)
	# --- the world moves on
	for t: Dictionary in teams:
		if t["id"] != c["team"]:
			c["team_cars"][t["id"]] = clampf(float(c["team_cars"][t["id"]]) + _rng.randf_range(-0.25, 0.4), 55.0, 96.0)
	for id: String in c["drivers"]:
		var d: Dictionary = c["drivers"][id]
		if int(d["age"]) < 25 and float(d["pace"]) < float(d["potential"]) and d["team"] != "":
			# Race seats develop fastest; the bench still learns.
			var gain := 0.25 if reserves().has(id) else 0.55
			d["pace"] = minf(float(d["potential"]), float(d["pace"]) + gain)
			d["racecraft"] = minf(97.0, float(d["racecraft"]) + gain * 0.7)
			d["consistency"] = minf(97.0, float(d["consistency"]) + gain * 0.7)
	if not c.has("results"):
		c["results"] = []
	var summary := PackedStringArray()
	for m: Dictionary in mine:
		summary.append("DNF" if m["dnf"] else "P%d" % int(m["position"]))
	c["results"].append({"season": int(c["season"]), "round": int(c["round"]), "result": " / ".join(summary), "winner": order[0]["name"]})
	c["round"] = int(c["round"]) + 1
	var report := {
		"race": calendar[int(c["round"]) - 1]["name"], "mine": mine, "prize": prize, "sponsor": sponsor_income, "salaries": salaries, "upkeep": upkeep,
		"board_change": board_change, "board": c["board"], "top": [],
	}
	for i in mini(10, order.size()):
		report["top"].append({"name": order[i]["name"], "short": order[i]["short"], "color": order[i]["color"], "is_player": order[i]["is_player"], "dnf": order[i]["dnf"]})
	c["last_report"] = report
	_post_race_messages(mine, flags)
	if int(c["board"]) <= 0:
		c["fired"] = true
	else:
		_queue_event(flags, best)
	if season_over() and not c["fired"]:
		_finish_season(report)
	GameManager.save()
	return report


func _finish_season(report: Dictionary) -> void:
	var c := state()
	var pos := team_position()
	var payout := SEASON_PRIZE[clampi(pos - 1, 0, SEASON_PRIZE.size() - 1)]
	GameManager.add_money(payout)
	var delta := (int(my_team()["expectation"]) - pos) * 6
	c["board"] = clampi(int(c["board"]) + delta, 0, 100)
	report["season"] = {"position": pos, "payout": payout, "board_change": delta, "champion": standings_drivers()[0]["name"], "season": c["season"]}
	if int(c["board"]) <= 0:
		c["fired"] = true
		return
	c["season"] = int(c["season"]) + 1
	c["round"] = 0
	c["results"] = []
	c["cap_spent"] = 0
	c["audited"] = false
	c["car_bonus"] = 0.0
	for id: String in c["points"]:
		c["points"][id] = 0
	for t: Dictionary in teams:
		c["team_points"][t["id"]] = 0
		if t["id"] != c["team"]:
			c["team_cars"][t["id"]] = clampf(float(c["team_cars"][t["id"]]) + _rng.randf_range(-3.0, 3.0), 58.0, 95.0)
	for id: String in c["drivers"].keys():
		var d: Dictionary = c["drivers"][id]
		d["age"] = int(d["age"]) + 1
		if int(d["age"]) > 36:
			d["pace"] = float(d["pace"]) - 0.8
		if d.get("junior", false) and d["team"] == "":
			c["drivers"].erase(id)      # last year's unsigned juniors move on
	_generate_juniors()
	_refresh_sponsor_offers()


# ---------------------------------------------------------------- dilemmas

func _event(id: String) -> Dictionary:
	for e: Dictionary in events:
		if e["id"] == id:
			return e
	return {}


func _queue_event(flags: Dictionary, _best_finish: int) -> void:
	var c := state()
	var seats := lineup()
	var star: String = seats[0] if float(driver(seats[0])["ego"]) >= float(driver(seats[1])["ego"]) else seats[1]
	var pick := ""
	if flags.get("collision", false):
		pick = "collision_blame"
	elif flags.get("held", "") != "" and _rng.randf() < 0.6:
		pick = "held_back"
	elif int(c["fia"]) >= 3:
		pick = "protest"
	elif int(c["cap_spent"]) > COST_CAP * 0.8 and not c["audited"]:
		pick = "cost_cap_audit"
		c["audited"] = true
	elif int(c["board"]) < 35 and c["last_event"] != "board_pressure":
		pick = "board_pressure"
	elif float(driver(star)["ego"]) >= 70.0 and c["number_one"] == "" and _rng.randf() < 0.35:
		pick = "number_one"
	elif _rng.randf() < 0.75:
		var pool: Array = []
		for e: Dictionary in events:
			if e["when"] == "any" and e["id"] != c["last_event"]:
				pool.append(e["id"])
		pick = pool[_rng.randi() % pool.size()]
	if pick == "":
		c["pending_event"] = {}
		return
	var d1: String = seats[0]
	var d2: String = seats[1]
	if pick == "held_back" and flags.get("held", "") == d1:
		d1 = seats[1]
		d2 = seats[0]
	var rivals: Array = []
	for t: Dictionary in teams:
		if t["id"] != c["team"]:
			rivals.append(t["name"])
	c["last_event"] = pick
	c["pending_event"] = {"id": pick, "d1": d1, "d2": d2, "star": star, "other": seats[1] if star == seats[0] else seats[0], "rival": rivals[_rng.randi() % rivals.size()]}


func pending_event() -> Dictionary:
	var p: Dictionary = state().get("pending_event", {})
	if p.is_empty():
		return {}
	var e := _event(p["id"]).duplicate(true)
	if e.is_empty():
		return {}
	e["text"] = _fill(e["text"], p)
	for option: Dictionary in e["options"]:
		option["text"] = _fill(option["text"], p)
	return e


func _fill(text: String, p: Dictionary) -> String:
	return text.format({
		"d1": driver(p["d1"]).get("name", "?"), "d2": driver(p["d2"]).get("name", "?"), "star": driver(p["star"]).get("name", "?"),
		"rival": p["rival"], "owner": my_team()["owner"], "team": my_team()["name"],
	})


## Applies the chosen option and returns a one-line summary of what changed.
func resolve_event(option_index: int) -> String:
	var p: Dictionary = state()["pending_event"]
	var e := _event(p["id"])
	var effects: Dictionary = e["options"][option_index]["effects"]
	var notes := PackedStringArray()
	_apply_effects(effects, p, notes)
	state()["pending_event"] = {}
	if int(state()["board"]) <= 0:
		state()["fired"] = true
	GameManager.save()
	return "  ·  ".join(notes) if not notes.is_empty() else "Nothing changes. For now."


func _apply_effects(effects: Dictionary, p: Dictionary, notes: PackedStringArray) -> void:
	var c := state()
	for key: String in effects:
		var v: Variant = effects[key]
		match key:
			"money":
				GameManager.add_money(int(v))
				notes.append("Cash %s" % money_text(float(v)))
			"board":
				c["board"] = clampi(int(c["board"]) + int(v), 0, 100)
				notes.append("Board %+d" % int(v))
			"rep":
				c["reputation"] = clampi(int(c["reputation"]) + int(v), 0, 100)
				notes.append("Reputation %+d" % int(v))
			"car":
				c["car_bonus"] = float(c["car_bonus"]) + float(v)
				notes.append("Car %+d" % int(v))
			"fia":
				c["fia"] = maxi(0, int(c["fia"]) + int(v))
				if int(v) > 0:
					notes.append("FIA attention up")
			"cap":
				c["cap_spent"] = maxi(0, int(c["cap_spent"]) + int(v))
				notes.append("Cost cap room %s" % money_text(-float(v)))
			"promise":
				c["promise"] = int(v)
				notes.append("Podium promised within %d races" % int(v))
			"number_one":
				c["number_one"] = p["star"]
				notes.append("%s is number one" % driver(p["star"])["name"])
			"gamble":
				var won := _rng.randf() < float(v["chance"])
				notes.append("It worked" if won else "It backfired")
				_apply_effects(v["win"] if won else v["lose"], p, notes)
			_:
				if key.begins_with("morale_") or key.begins_with("salary_"):
					var who: String = p.get(key.get_slice("_", 1), "")
					var d := driver(who)
					if d.is_empty():
						continue
					if key.begins_with("morale_"):
						d["morale"] = clampi(int(d["morale"]) + int(v), 5, 100)
						notes.append("%s morale %+d" % [str(d["name"]).get_slice(" ", 1), int(v)])
					else:
						d["salary"] = int(int(d["salary"]) * (1.0 + float(v)))
						notes.append("%s salary now %s" % [str(d["name"]).get_slice(" ", 1), money_text(float(d["salary"]))])


func end_career() -> void:
	GameManager.profile["career"] = {}
	GameManager.profile["story_progress"] = 0
	GameManager.save()


# ---------------------------------------------------------------- people, phone and offers

func _generate_people() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(Time.get_ticks_usec()))
	var people := {}
	var roles := {"owner": ["OWNER'S OFFICE", 1], "engineer": ["RACE ENGINEER", 0], "tech": ["TECHNICAL DIRECTOR", 3], "scout": ["CHIEF SCOUT", 3]}
	for id: String in roles:
		people[id] = {"id": id, "name": "%s %s" % [FIRST_NAMES[rng.randi() % FIRST_NAMES.size()], LAST_NAMES[rng.randi() % LAST_NAMES.size()]], "role": roles[id][0], "team": state()["team"], "look": PixelArt.random_look(rng.randi(), roles[id][1])}
	for t: Dictionary in teams:
		var id := "boss_%s" % t["id"]
		people[id] = {"id": id, "name": "%s %s" % [FIRST_NAMES[rng.randi() % FIRST_NAMES.size()], LAST_NAMES[rng.randi() % LAST_NAMES.size()]], "role": "TEAM PRINCIPAL", "team": t["id"], "look": PixelArt.random_look(rng.randi(), 1)}
	state()["people"] = people


## Unified profile for anyone in the paddock: staff, rival bosses or drivers.
func person(id: String) -> Dictionary:
	if state()["people"].has(id):
		var p: Dictionary = state()["people"][id].duplicate()
		p["kind"] = "staff"
		return p
	var d := driver(id)
	if d.is_empty():
		return {}
	return {"id": id, "name": d["name"], "role": "JUNIOR DRIVER" if d.get("junior", false) else "DRIVER", "team": d["team"], "look": PixelArt.random_look(hash(id), 2), "kind": "driver"}


func contacts() -> Array:
	var out: Array = ["owner", "engineer", "tech", "scout"]
	out.append_array(lineup())
	out.append_array(reserves())
	for t: Dictionary in teams:
		if t["id"] != state()["team"]:
			out.append("boss_%s" % t["id"])
	for t: Dictionary in teams:
		if t["id"] != state()["team"]:
			out.append_array(team_drivers(t["id"]))
	return out


func add_message(from_id: String, text: String, offer: Dictionary = {}) -> void:
	var inbox: Array = state()["inbox"]
	inbox.push_front({"from": from_id, "text": text, "season": int(state()["season"]), "round": int(state()["round"]), "read": false, "offer": offer, "done": offer.is_empty()})
	while inbox.size() > 40:
		inbox.pop_back()


func unread_count() -> int:
	var n := 0
	for m: Dictionary in state().get("inbox", []):
		if not m["read"] or not m["done"]:
			n += 1
	return n


func mark_read() -> void:
	for m: Dictionary in state()["inbox"]:
		m["read"] = true
	GameManager.save()


func _pick(options: Array) -> String:
	return options[_rng.randi() % options.size()]


func _post_race_messages(mine: Array, flags: Dictionary) -> void:
	var c := state()
	for m: Dictionary in mine:
		var text := ""
		var pos := int(m["position"])
		var morale := int(driver(m["id"])["morale"])
		if m["dnf"]:
			text = _pick(["Gutted. That one hurts. Sorry boss.", "I had nothing left to save it. What happened to the car?", "Don't say anything. I know."])
		elif pos == 1:
			text = _pick(["YES!! Get in there! Drinks are on me!", "P1 baby. Told you. Now give me the upgrades first.", "That's what this team can do. Thank you, all of you."])
		elif pos <= 3:
			text = _pick(["Podium! Feels good. We can win one of these.", "Solid points. The car was alive today.", "Champagne tastes better than I remembered."])
		elif pos <= 10:
			text = _pick(["Points. I'll take it. We need more pace though.", "Decent day. Strategy was fine, the car wasn't.", "Top ten. Not what I signed up for, but ok."])
		else:
			text = _pick(["P%d. I can't race like this." % pos, "We were nowhere. Tell me there's an upgrade coming.", "Tough one. Head down, next race."])
		if morale < 35:
			text += " " + _pick(["My manager wants a meeting.", "Honestly? I'm not happy here.", "Something has to change."])
		add_message(m["id"], text)
	if flags.get("collision", false):
		add_message("engineer", "Both cars need new floors after that contact. Repair bill: %s. Sort those two out." % money_text(900))
		GameManager.add_money(-900)
	elif _rng.randf() < 0.3:
		var bill := _rng.randi_range(3, 9) * 100
		add_message("engineer", _pick(["Bad news: we cracked a gearbox casing. %s to replace it.", "Found a hydraulic leak in parc ferme. %s in parts.", "Front wing took kerb damage. %s for a new one."]) % money_text(bill))
		GameManager.add_money(-bill)
	if int(c["cap_spent"]) > COST_CAP * 0.75:
		add_message("tech", "We're at %d%% of the cost cap. Any more spending and the FIA will be measuring my office for an audit." % int(float(c["cap_spent"]) / COST_CAP * 100.0))
	elif _rng.randf() < 0.2:
		add_message("tech", _pick(["Wind tunnel numbers look promising. An AERO upgrade would pay off right now.", "The R&D lab has ideas they can't build. Fund the next level and I'll get you new parts.", "Pit stops were slow again. The crew needs investment."]))
	if _rng.randf() < 0.3:
		for d: Dictionary in market():
			if d.get("junior", false) and scout_level(d) < 3:
				d["scout_level"] = scout_level(d) + 1
				add_message("scout", "Free look: I watched %s in %s this weekend. Report is now %d/3 - check SCOUTING." % [d["name"], str(d["league"]).capitalize(), scout_level(d)])
				break
	# --- at most one offer per race
	var roll := _rng.randf()
	var rival: Dictionary = teams[_rng.randi() % teams.size()]
	while rival["id"] == c["team"]:
		rival = teams[_rng.randi() % teams.size()]
	if roll < 0.22:
		var brand: Dictionary = sponsors[_rng.randi() % sponsors.size()]
		var cash := _rng.randi_range(4, 14) * 100
		add_message("owner", "%s want a one-race sticker on the engine cover for %s. Easy money - but our title sponsor won't love it." % [brand["name"], money_text(cash)], {"type": "sticker", "cash": cash})
	elif roll < 0.37:
		var seat: String = lineup()[_rng.randi() % 2]
		var d := driver(seat)
		var bid := int(float(d["salary"]) * 0.5 + maxf(0.0, driver_overall(d) - 70.0) * 350.0)
		add_message("boss_%s" % rival["id"], "Straight to it: %s for %s. Cash, today. You'd need a replacement, I know. Think about it." % [money_text(bid), d["name"]], {"type": "bid", "driver": seat, "team": rival["id"], "cash": bid})
	elif roll < 0.47 and int(c["reputation"]) >= 58 and int(rival["expectation"]) <= int(my_team()["expectation"]) + 2:
		add_message("boss_%s" % rival["id"], "Our owners have noticed your work. The principal's chair at %s is yours if you want it. Budget %s. Yes or no?" % [rival["name"], money_text(float(rival["budget"]))], {"type": "job", "team": rival["id"]})
	elif roll < 0.62:
		add_message("boss_%s" % rival["id"], _pick(["Nice race. Shame about the result.", "See you in the stewards' room.", "Your number two looked quick today. Interesting.", "Lunch next week? I have a proposal about next year's rules."]))


## Accept or decline the offer attached to message `index`. Returns what happened.
func resolve_offer(index: int, accept: bool) -> String:
	var m: Dictionary = state()["inbox"][index]
	if m["done"]:
		return ""
	m["done"] = true
	var offer: Dictionary = m["offer"]
	var result := "Declined."
	if accept:
		match offer["type"]:
			"sticker":
				GameManager.add_money(int(offer["cash"]))
				state()["reputation"] = maxi(0, int(state()["reputation"]) - 1)
				result = "Deal done: %s banked." % money_text(float(offer["cash"]))
			"bid":
				result = _sell_driver(offer["driver"], offer["team"], int(offer["cash"]))
			"job":
				result = _switch_team(offer["team"])
	GameManager.save()
	return result


func _sell_driver(id: String, to_team: String, cash: int) -> String:
	if not lineup().has(id):
		return "That driver is no longer yours to sell."
	var replacement: Dictionary = {}
	for d: Dictionary in market():
		if salary_total(id, d["id"]) <= SALARY_CAP and (replacement.is_empty() or driver_overall(d) > driver_overall(replacement)):
			replacement = d
	if replacement.is_empty():
		return "No replacement fits under the salary cap - deal off."
	# The buying team releases its weakest driver to make room.
	var weakest := ""
	for other: String in team_drivers(to_team):
		if weakest == "" or driver_overall(driver(other)) < driver_overall(driver(weakest)):
			weakest = other
	if weakest != "":
		driver(weakest)["team"] = ""
		driver(weakest)["buyout"] = 0
	driver(id)["team"] = to_team
	replacement["team"] = state()["team"]
	replacement["junior"] = false
	var seats: Array = lineup()
	seats[seats.find(id)] = replacement["id"]
	if state()["number_one"] == id:
		state()["number_one"] = ""
	if not state()["points"].has(replacement["id"]):
		state()["points"][replacement["id"]] = 0
	GameManager.add_money(cash)
	return "%s sold for %s. %s takes the seat." % [driver(id)["name"], money_text(cash), replacement["name"]]


func _switch_team(team_id: String) -> String:
	var c := state()
	c["team"] = team_id
	var seats: Array = []
	for id: String in c["drivers"]:
		if c["drivers"][id]["team"] == team_id:
			seats.append(id)
	c["lineup"] = seats.slice(0, 2)
	for id: String in c["reserves"]:
		c["drivers"][id]["team"] = ""
	c["reserves"] = []
	c["number_one"] = ""
	c["sponsor"] = {}
	c["factory"] = {"aero": 0, "power": 0, "pit": 0, "rd": int(c["factory"]["rd"])}
	c["board"] = 60
	c["cap_spent"] = 0
	c["car_bonus"] = 0.0
	c["promise"] = 0
	for id: String in ["owner", "engineer", "tech", "scout"]:
		c["people"][id]["team"] = team_id
	GameManager.profile["money"] = int(team(team_id)["budget"])
	EventBus.money_changed.emit(GameManager.money())
	_refresh_sponsor_offers()
	add_message("owner", "Welcome to %s. The target: %s." % [team(team_id)["name"], board_target_text().to_lower()])
	return "You are now team principal of %s." % team(team_id)["name"]


# ---------------------------------------------------------------- race weekend

var _weekend_sim: GPSim


## The simulation for the upcoming race (qualifying already run). Kept until the race is booked.
func weekend_sim() -> GPSim:
	if _weekend_sim == null:
		_weekend_sim = GPSim.new()
		_weekend_sim.setup(race_entries(), next_round(), int(state()["factory"]["pit"]), int(Time.get_ticks_usec()))
	return _weekend_sim


func clear_weekend() -> void:
	_weekend_sim = null
	GameManager.career_race = {}


## Sensible automatic calls for the player's cars (quick sim, or the car you are not driving).
static func auto_strategy(sim: GPSim) -> void:
	for car in sim.player_cars():
		var wet: bool = car["tire"] == "I" or car["tire"] == "W"
		var left := sim.laps - sim.lap
		if sim.weather > 0 and not wet:
			car["pit_request"] = "W" if sim.weather == 2 else "I"
		elif sim.weather == 0 and wet:
			car["pit_request"] = "M"
		elif GPSim.tire_wear_fraction(car) >= 1.0 and left > 3:
			car["pit_request"] = ("S" if left <= 8 else "M") if sim.weather == 0 else car["tire"]


func quick_sim() -> Dictionary:
	var sim := weekend_sim()
	sim.team_order = "hold"
	while not sim.finished():
		auto_strategy(sim)
		sim.step()
	var report := apply_race(sim.cars, sim.flags)
	clear_weekend()
	return report


## Sets up the on-track race: you drive `driver_id` against the seven cars around you on the grid.
func prepare_drive(driver_id: String) -> void:
	build_drive(driver_id)
	GameManager.start_session(GameManager.MODE_RACE)


func build_drive(driver_id: String) -> void:
	var sim := weekend_sim()
	var index := 0
	for i in sim.cars.size():
		if sim.cars[i]["id"] == driver_id:
			index = i
	var start := clampi(index - 3, 0, sim.cars.size() - 8)
	var rivals: Array = []
	var my_strength := car_rating(state()["team"])
	for i in range(start, start + 8):
		var car: Dictionary = sim.cars[i]
		if car["id"] == driver_id:
			continue
		var d := driver(car["id"])
		var delta := (float(car["car"]) - my_strength) * 0.6 + (driver_overall(d) - 80.0) * 0.3
		rivals.append({
			"id": car["id"], "name": car["name"], "color": car["color"], "color2": car.get("color2", "#f4f6f2"), "pace": clampf(0.93 + delta * 0.004, 0.86, 0.985),
			"braking_accuracy": clampf(float(d["consistency"]) / 100.0, 0.7, 0.97), "consistency": clampf(float(d["consistency"]) / 100.0, 0.7, 0.97),
			"aggression": clampf(float(d["ego"]) / 100.0, 0.3, 0.9), "tire_management": 0.7, "error_rate": clampf((100.0 - float(d["consistency"])) / 150.0, 0.03, 0.2),
			"setup": {"tires": GameManager.setup.parts.get("tires", "tires_hard")},   # same compound as you: a fair fight
		})
	GameManager.track_id = round_track()
	GameManager.career_race = {"driver": driver_id, "driver_name": driver(driver_id)["name"], "rivals": rivals, "race": next_round()["name"]}
	GameManager.active_mission = -1
	GameManager.session_mode = GameManager.MODE_RACE


## Books a race the player drove. `track_position` is 1-8 among the cars that were on track.
func finish_drive(track_position: int, completed: bool) -> Dictionary:
	var info: Dictionary = GameManager.career_race
	var sim := weekend_sim()
	sim.team_order = "hold"
	while not sim.finished():
		auto_strategy(sim)
		sim.step()
	var order: Array = sim.cars.duplicate()
	var mine: Dictionary = {}
	for car: Dictionary in order:
		if car["id"] == info["driver"]:
			mine = car
	order.erase(mine)
	if not completed:
		mine["dnf"] = true
		mine["crashed"] = true
		order.append(mine)
	else:
		mine["dnf"] = false
		# Slot the driven car in relative to the rivals it actually raced.
		var rival_ids: Array = []
		for r: Dictionary in info["rivals"]:
			rival_ids.append(r["id"])
		var rival_slots: Array = []
		for i in order.size():
			if rival_ids.has(order[i]["id"]) and not order[i]["dnf"]:
				rival_slots.append(i)
		var insert_at := order.size()
		if track_position - 1 < rival_slots.size():
			insert_at = rival_slots[track_position - 1]
		elif not rival_slots.is_empty():
			insert_at = int(rival_slots[rival_slots.size() - 1]) + 1
		# Never place a finisher behind retired cars.
		while insert_at > 0 and order[insert_at - 1]["dnf"]:
			insert_at -= 1
		order.insert(insert_at, mine)
	var report := apply_race(order, sim.flags)
	report["driven"] = info["driver_name"]
	clear_weekend()
	return report
