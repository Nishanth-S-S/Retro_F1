extends Node
## Autoload "Career": the team-principal layer. Owns teams, drivers, contracts, sponsors,
## the factory, board confidence and the dilemma events. All content is data in
## data/career/*.json; all state lives in GameManager.profile["career"] so it saves.

const SALARY_CAP := 55000            # $k per season for the two race seats
const COST_CAP := 70000              # $k per season of car spending (parts + factory)
const FACTORY_MAX := 5
## Price of each of the three scouting phases ($k). The last one reveals true potential.
const SCOUT_COSTS: PackedInt32Array = [400, 700, 1200]
const MAX_RESERVES := 3
## Share of a reserve driver's salary that is paid and counts against the cap.
const RESERVE_SALARY_SHARE := 0.3
const DEPARTMENTS := {
	"aero": {"name": "AERO DEPT", "note": "+1.5 car rating per level"},
	"power": {"name": "POWER UNIT", "note": "+1.5 car rating per level"},
	"pit": {"name": "PIT CREW", "note": "-0.5 s per pit stop per level"},
	"rd": {"name": "R&D LAB", "note": "unlocks new parts in the garage"},
}
const POINTS: PackedInt32Array = [25, 18, 15, 12, 10, 8, 6, 4, 2, 1]
const SPRINT_POINTS: PackedInt32Array = [8, 7, 6, 5, 4, 3, 2, 1]
const SEASON_PRIZE: PackedInt32Array = [30000, 26000, 23000, 20000, 17000, 15000, 13000, 11000, 9000, 8000, 7000]
const MAX_CARS := 4
const NEW_CAR_COST := 2500           # $k to build another chassis (counts against the cost cap)
const ENGINEER_SLOTS := 5            # a full engineering office
const MAX_RP := 400                  # unspent research points above this are lost
const TUNNEL_BONUS := 2.5            # car rating from a fully correlated wind-tunnel model
const MATERIAL_BONUS := 0.4          # car rating per material tier
const MATERIAL_COSTS: PackedInt32Array = [40, 80, 140, 220]
const ENGINEER_SPECS := {
	"aero": {"name": "AERODYNAMICIST", "short": "AERO", "note": "Wind-tunnel runs teach more. Cheaper aero materials."},
	"power": {"name": "ENGINE SPECIALIST", "short": "ENGINE", "note": "Cheaper power-unit materials."},
	"chassis": {"name": "CHASSIS DESIGNER", "short": "CHASSIS", "note": "Cheaper monocoque, brake and suspension materials."},
	"data": {"name": "DATA ANALYST", "short": "DATA", "note": "More research points every week."},
	"strategy": {"name": "STRATEGIST", "short": "STRATEGY", "note": "Faster pit stops in simulated races."},
}
## What research points buy: a material tier per area of each car.
const MATERIAL_AREAS := {
	"chassis": {"name": "MONOCOQUE", "spec": "chassis", "tiers": ["STEEL TUBE", "ALUMINIUM", "CARBON FIBRE", "CARBON-TITANIUM", "GRAPHENE WEAVE"]},
	"aero": {"name": "AERO SURFACES", "spec": "aero", "tiers": ["FIBREGLASS", "PRE-PREG CARBON", "HIGH-MODULUS CARBON", "FLEX-TUNED CARBON", "ACTIVE SKIN"]},
	"power": {"name": "POWER UNIT", "spec": "power", "tiers": ["CAST IRON", "ALUMINIUM ALLOY", "TITANIUM VALVES", "INCONEL EXHAUST", "CERAMIC MATRIX"]},
	"brakes": {"name": "BRAKES", "spec": "chassis", "tiers": ["STEEL DISCS", "VENTED STEEL", "CARBON-CERAMIC", "CARBON-CARBON", "CARBON-SILICON"]},
	"suspension": {"name": "SUSPENSION", "spec": "chassis", "tiers": ["STEEL ARMS", "CHROMOLY", "TITANIUM", "CARBON WISHBONES", "METAL MATRIX"]},
}
const TRACK_TYPES := {"monza": "HIGH SPEED", "silverstone": "FAST SWEEPS", "spa": "FOREST ROAD", "interlagos": "TECHNICAL", "spielberg": "HIGH SPEED",
	"falcon_ridge": "TECHNICAL", "tempo_park": "HIGH SPEED", "port_azure": "STREET", "silver_lake": "FAST SWEEPS", "nordhaven": "FOREST ROAD"}
## Seconds per lap a driver gains at home, on a favourite kind of track, or loses on a bogey one.
const HOME_GAIN := 0.25
const TYPE_GAIN := 0.15
## Driver training: how hard each driver is pushed between races.
const TRAINING_NAMES: PackedStringArray = ["REST", "NORMAL", "INTENSE", "EXTREME"]
const TRAINING_GAIN: PackedFloat32Array = [0.4, 1.0, 1.6, 2.2]
const TRAINING_FITNESS: PackedInt32Array = [12, 2, -9, -16]
const TRAINING_MORALE: PackedInt32Array = [2, 0, -2, -5]
const SIMULATOR_COST := 150          # $k per race for a driver's simulator programme
const BALANCE_NAMES: PackedStringArray = ["A PLANTED, UNDERSTEERY CAR", "A NEUTRAL CAR", "A POINTY, OVERSTEERY CAR"]
const AERO_NAMES: PackedStringArray = ["LOW DRAG / TOP SPEED", "A BALANCED WING LEVEL", "HIGH DOWNFORCE"]
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
var _stats_cache: Dictionary = {}
var _starter_cache := -1.0


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
	if c.has("regs") and not c["regs"].has("v"):
		# Early saves capped the wings below the slider's maximum from day one, which got
		# cars with full wing disqualified every race. Season one has no wing limit.
		c["regs"]["v"] = 2
		if int(c["season"]) == 1:
			c["regs"]["max_wing"] = CarSetup.WING_ANGLE_MAX
	if not c.has("date"):
		# Careers from before the calendar start on the Friday of their next race weekend.
		c["date"] = race_day(int(c["round"])) - 2
	if not c.has("cars"):
		# ...and careers from before engineers, multiple cars and FIA rules get those.
		_init_team_extras()
	return true


func team(id: String) -> Dictionary:
	for t: Dictionary in teams:
		if t["id"] == id:
			return t
	return {}


func my_team() -> Dictionary:
	return team(state().get("team", ""))


func driver(id: String) -> Dictionary:
	var d: Dictionary = state()["drivers"].get(id, {})
	if not d.is_empty() and not d.has("wet"):
		_ensure_traits(d)
	return d


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
		"people": {}, "inbox": [], "date": 0, "news": [],
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
	_init_team_extras()
	manager_contract()
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


## Derived numbers for a build, cached because the hub asks for them constantly.
func setup_stats(setup: CarSetup) -> CarStats:
	var key := JSON.stringify(setup.to_dict())
	if not _stats_cache.has(key):
		if _stats_cache.size() > 48:
			_stats_cache.clear()
		_stats_cache[key] = CarStats.compute(setup, _config)
	return _stats_cache[key]


## The car card's overall (30-99) for a build: every setup change moves it.
func build_rating(setup: CarSetup = null) -> float:
	var chosen := setup if setup else GameManager.setup
	return float(CarRatings.compute(chosen, setup_stats(chosen))["overall"])


## The overall of the car every team starts with: the baseline car_overall works from.
func _starter_rating() -> float:
	if _starter_cache < 0.0:
		var starter := CarSetup.new()
		var parts: Dictionary = GameManager.economy.get("starting_parts", {})
		for slot: String in parts:
			starter.install(slot, parts[slot])
		_starter_cache = build_rating(starter)
	return _starter_cache


## A team's car rating. For your own team it is the average of the cars your race drivers use.
func car_rating(team_id: String) -> float:
	var base: float = state()["team_cars"].get(team_id, 70.0)
	if team_id != state()["team"]:
		return base
	var total := 0.0
	for id: String in lineup():
		total += car_overall(car_for(id))
	return total / maxf(lineup().size(), 1)


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
	if lineup().has(id) or reserves().has(id):
		return false                 # too late: reports are written before the contract, not after
	GameManager.add_money(-scout_cost(d))
	d["scout_level"] = scout_level(d) + 1
	GameManager.save()
	return true


## What it costs to sign a driver: an academy fee for juniors, nothing for a free agent,
## and the release clause in their contract for anyone racing for a rival.
func driver_buyout(d: Dictionary) -> int:
	if str(d.get("team", "")) == "":
		return int(d.get("buyout", 0))
	return release_clause(d)


## The buyout written into a contracted driver's deal.
func release_clause(d: Dictionary) -> int:
	return int(float(d["salary"]) * 0.6 + maxf(0.0, driver_overall(d) - 65.0) * 380.0)


## Rival drivers you could buy out of their contracts, best first.
func poach_targets() -> Array:
	var out: Array = []
	for id: String in state()["drivers"]:
		var d := driver(id)
		if str(d["team"]) != "" and str(d["team"]) != str(state()["team"]) and not d.get("hidden", false) and not lineup().has(id) and not reserves().has(id):
			out.append(d)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return driver_overall(a) > driver_overall(b))
	return out


## Reputation your team needs before a contracted driver will even take the call.
func poach_reputation(d: Dictionary) -> int:
	return clampi(driver_overall(d) - 26, 30, 80)


## Signs a driver into the seat held by `replace_id` ("reserve" = the bench). Free agents and
## juniors come from the market; a driver under contract elsewhere is poached by paying the
## release clause. Returns "" or the reason it failed.
func sign_driver(id: String, replace_id: String) -> String:
	var d := driver(id)
	var from_team := str(d.get("team", ""))
	var poached := from_team != "" and from_team != str(state()["team"])
	var fee := driver_buyout(d)
	if poached and int(state()["reputation"]) < poach_reputation(d):
		return "%s won't leave %s for you yet (needs reputation %d)." % [d["name"], team(from_team)["short"], poach_reputation(d)]
	if replace_id == "reserve" and reserves().size() >= MAX_RESERVES:
		return "Both reserve seats are taken."
	if salary_total(replace_id, id) > SALARY_CAP:
		return "Over the salary cap (%s)." % money_text(SALARY_CAP)
	if GameManager.money() < fee:
		return "Not enough cash for the %s buyout." % money_text(fee)
	GameManager.add_money(-fee)
	# The full card (potential, conditions, car taste) only exists if the scouts finished
	# their report before the contract was signed.
	d["known"] = scout_level(d) >= 3
	if poached:
		state()["reputation"] = maxi(0, int(state()["reputation"]) - 1)
		add_message("boss_%s" % from_team, "You triggered %s's release clause. %s wired, lawyers satisfied. I won't forget this." % [str(d["name"]).get_slice(" ", 1), money_text(fee)])
	if replace_id == "reserve":
		d["team"] = state()["team"]
		d["junior"] = false
		d["morale"] = 70
		reserves().append(id)
		if not state()["points"].has(id):
			state()["points"][id] = 0
		if poached:
			_backfill_team(from_team)
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
	_hand_over_car(replace_id, id)
	if state()["number_one"] == replace_id:
		state()["number_one"] = ""
	if not state()["points"].has(id):
		state()["points"][id] = 0
	if poached:
		_backfill_team(from_team)
	GameManager.save()
	return ""


## A rival that lost a driver promotes the best free agent it can find.
func _backfill_team(team_id: String) -> void:
	var best: Dictionary = {}
	for d: Dictionary in market():
		if not d.get("junior", false) and (best.is_empty() or driver_overall(d) > driver_overall(best)):
			best = d
	if best.is_empty():
		for d: Dictionary in market():
			if best.is_empty() or driver_overall(d) > driver_overall(best):
				best = d
	if best.is_empty():
		return
	best["team"] = team_id
	best["junior"] = false
	if not state()["points"].has(best["id"]):
		state()["points"][best["id"]] = 0


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
	_hand_over_car(seat_id, reserve_id)
	driver(seat_id)["morale"] = maxi(5, int(driver(seat_id)["morale"]) - 20)
	driver(reserve_id)["morale"] = mini(100, int(driver(reserve_id)["morale"]) + 15)
	if state()["number_one"] == seat_id:
		state()["number_one"] = ""
	GameManager.save()
	return ""


## Releases a race driver; the best reserve takes the seat. Needs someone on the bench.
func release_driver(id: String) -> String:
	if reserves().is_empty():
		return "SIGN A RESERVE FIRST - SOMEONE HAS TO TAKE THE SEAT"
	var best := ""
	for r: String in reserves():
		if best == "" or driver_overall(driver(r)) > driver_overall(driver(best)):
			best = r
	var error := promote_reserve(best, id)
	if error != "":
		return error
	release_reserve(id)
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


## Points for a round: sprints pay the top eight 8-1, the finale pays double.
func points_table(round_info: Dictionary) -> PackedInt32Array:
	var table := SPRINT_POINTS if str(round_info.get("format", "gp")) == "sprint" else POINTS
	if round_info.get("double", false):
		var doubled := PackedInt32Array()
		for p in table:
			doubled.append(p * 2)
		return doubled
	return table


func format_label(round_info: Dictionary) -> String:
	var parts := PackedStringArray(["SPRINT" if str(round_info.get("format", "gp")) == "sprint" else "GRAND PRIX"])
	if round_info.get("street", false):
		parts.append("STREET")
	if round_info.get("night", false):
		parts.append("NIGHT")
	if round_info.get("double", false):
		parts.append("DOUBLE POINTS")
	return "  ·  ".join(parts)


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
			var mine: bool = t["id"] == state()["team"]
			# Your drivers race the car you gave them, and how well it suits them matters.
			# Rivals' cars are scaled by the difficulty setting.
			var machine := driver_car_rating(id) if mine else car_rating(t["id"]) + Difficulty.sim_car_bonus()
			out.append({
				"id": id, "name": d["name"], "team": t["id"], "short": t["short"], "color": t["color"], "number": d["number"],
				"color2": t["color2"], "is_player": mine, "car": machine + (float(weekend_bonus().get("car", 0.0)) if mine else 0.0), "pace": float(d["pace"]),
				"racecraft": float(d["racecraft"]), "consistency": float(d["consistency"]), "ego": float(d["ego"]), "morale": float(d["morale"]),
				"wet": float(d["wet"]), "tyres": float(d["tyres"]) + (float(weekend_bonus().get("tyres", 0.0)) if mine else 0.0), "overtaking": float(d["overtaking"]), "defending": float(d["defending"]),
				"starts": float(d["starts"]), "form": track_form(d, round_track()) - (maxf(0.0, 60.0 - fitness(d)) * 0.02 if mine else 0.0),
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
	var dsq := _scrutineer(order)
	var table := points_table(calendar[mini(int(c["round"]), calendar.size() - 1)])
	for i in order.size():
		var car: Dictionary = order[i]
		var pts := table[i] if i < table.size() and not car["dnf"] else 0
		c["points"][car["id"]] = int(c["points"].get(car["id"], 0)) + pts
		c["team_points"][car["team"]] = int(c["team_points"][car["team"]]) + pts
		if car["is_player"]:
			mine.append({"id": car["id"], "name": car["name"], "position": i + 1, "dnf": car["dnf"], "points": pts, "dsq": car.get("dsq", false), "dsq_reason": car.get("dsq_reason", "")})
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
	var staff := int(engineer_salaries() / float(calendar.size()))
	# Simulator programmes and the boss's own wage.
	for id: String in lineup() + reserves():
		if driver(id).get("sim", false):
			staff += SIMULATOR_COST
	var contract: Dictionary = c["manager"].get("contract", {})
	c["manager"]["earned"] = int(c["manager"].get("earned", 0)) + int(float(contract.get("salary", 0)) / calendar.size())
	GameManager.add_money(prize + sponsor_income - salaries - upkeep - staff)
	# --- board
	var best := 99
	for m: Dictionary in mine:
		if not m["dnf"]:
			best = mini(best, int(m["position"]))
	# --- a new week at the factory: research points and a fresh wind-tunnel allowance
	c["last_best"] = best
	var research := research_income()
	c["rp"] = mini(MAX_RP, int(c["rp"]) + int(research["total"]))
	c["tunnel_used"] = 0
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
	var results_by_id := {}
	for car: Dictionary in order:
		results_by_id[car["id"]] = car
	for id: String in c["drivers"]:
		var d := driver(id)
		if str(d["team"]) != "":
			_develop(d, results_by_id.get(id, {}))
	if not c.has("results"):
		c["results"] = []
	var summary := PackedStringArray()
	for m: Dictionary in mine:
		summary.append("DNF" if m["dnf"] else "P%d" % int(m["position"]))
	c["results"].append({"season": int(c["season"]), "round": int(c["round"]), "result": " / ".join(summary), "winner": order[0]["name"]})
	_record_form(order)
	c["round"] = int(c["round"]) + 1
	c["date"] = int(c.get("date", 0)) + 1
	c["weekend"] = {}
	var report := {
		"race": calendar[int(c["round"]) - 1]["name"], "mine": mine, "prize": prize, "sponsor": sponsor_income, "salaries": salaries, "upkeep": upkeep,
		"board_change": board_change, "board": c["board"], "top": [], "staff": staff, "research": int(research["total"]), "dsq": dsq,
	}
	for i in mini(10, order.size()):
		report["top"].append({"name": order[i]["name"], "short": order[i]["short"], "color": order[i]["color"], "is_player": order[i]["is_player"], "dnf": order[i]["dnf"]})
	c["last_report"] = report
	_expire_offers()
	_post_race_messages(mine, flags)
	_poaching_round()
	if int(c["board"]) <= 0:
		c["fired"] = true
	else:
		_queue_event(flags, mine)
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
	var wins := 0
	for r: Dictionary in c.get("results", []):
		if str(r["result"]).begins_with("P1 ") or str(r["result"]) == "P1" or str(r["result"]).ends_with(" P1"):
			wins += 1
	if not c.has("history"):
		c["history"] = []
	c["history"].append({"season": int(c["season"]), "team": c["team"], "position": pos, "expected": int(my_team()["expectation"]), "points": int(c["team_points"][c["team"]]), "wins": wins})
	# The review screen at HQ walks you into the new season.
	c["season_review"] = report["season"].duplicate()
	c["season_review"]["team_champion"] = standings_teams()[0]["name"]
	var contract: Dictionary = c["manager"].get("contract", {})
	contract["years"] = int(contract.get("years", 1)) - 1
	if int(c["board"]) <= 0:
		c["fired"] = true
		return
	if int(contract.get("years", 1)) <= 0:
		# Contract over: the owners renew it only if they still believe in you.
		c["season_review"]["contract"] = "renew" if int(c["board"]) >= 45 else "expired"
	c["season"] = int(c["season"]) + 1
	c["round"] = 0
	c["date"] = 0
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
		d["season_gain"] = 0.0
		if int(d["age"]) > 36:
			d["pace"] = float(d["pace"]) - 0.8
		if d.get("junior", false) and d["team"] == "":
			c["drivers"].erase(id)      # last year's unsigned juniors move on
	_generate_juniors()
	_refresh_sponsor_offers()
	_new_season_rules()


# ---------------------------------------------------------------- dilemmas

func _event(id: String) -> Dictionary:
	for e: Dictionary in events:
		if e["id"] == id:
			return e
	return {}


## Everything a dilemma can depend on, as plain numbers (true = 1).
func _event_facts(flags: Dictionary, mine: Array) -> Dictionary:
	var c := state()
	var seats := lineup()
	var d1 := driver(seats[0])
	var d2 := driver(seats[1])
	var finished := 0
	var best := 99
	var points := 0
	var dsq := 0
	for m: Dictionary in mine:
		points += int(m.get("points", 0))
		dsq += 1 if m.get("dsq", false) else 0
		if not m["dnf"]:
			finished += 1
			best = mini(best, int(m["position"]))
	var illegal := 0
	for built: Dictionary in cars():
		illegal += 0 if car_violations(built).is_empty() else 1
	var pos := team_position()
	return {
		"collision": int(flags.get("collision", false)), "held": int(str(flags.get("held", "")) != ""), "wet": int(flags.get("wet", false)),
		"win": int(best == 1), "podium": int(best <= 3), "points": int(points > 0), "no_points": int(points == 0), "double_dnf": int(finished == 0), "dsq": dsq,
		"board": int(c["board"]), "rep": int(c["reputation"]), "cash": GameManager.money(), "cap": int(float(c["cap_spent"]) / COST_CAP * 100.0), "fia": int(c["fia"]),
		"audited": int(c["audited"]), "round": int(c["round"]), "position": pos, "expect": int(my_team()["expectation"]), "behind": pos - int(my_team()["expectation"]),
		"morale": mini(int(d1["morale"]), int(d2["morale"])), "ego": int(maxf(float(d1["ego"]), float(d2["ego"]))), "no_number_one": int(str(c["number_one"]) == ""),
		"no_sponsor": int((c["sponsor"] as Dictionary).is_empty()), "engineers": engineers().size(), "rp": int(c["rp"]), "illegal": illegal,
	}


## "board<35", "cap>80", "win", "!audited" ... against the facts.
static func _condition_holds(condition: String, facts: Dictionary) -> bool:
	for op: String in ["<", ">", "="]:
		if condition.contains(op):
			var value := float(facts.get(condition.get_slice(op, 0), 0))
			var limit := float(condition.get_slice(op, 1))
			return value < limit if op == "<" else (value > limit if op == ">" else is_equal_approx(value, limit))
	if condition.begins_with("!"):
		return int(facts.get(condition.substr(1), 0)) == 0
	return int(facts.get(condition, 0)) != 0


## Picks the dilemma for this week. Nothing is random: an event fires only when every one
## of its conditions is true for your team right now, the most pressing one wins, and
## nothing repeats within five races.
func _queue_event(flags: Dictionary, mine: Array) -> void:
	var c := state()
	var seats := lineup()
	var facts := _event_facts(flags, mine)
	var recent: Array = c.get("event_log", [])
	var pick: Dictionary = {}
	for e: Dictionary in events:
		if recent.has(e["id"]) or (not pick.is_empty() and int(e["priority"]) <= int(pick["priority"])):
			continue
		var ok := true
		for condition: String in e["if"]:
			ok = ok and _condition_holds(condition, facts)
		if ok:
			pick = e
	if pick.is_empty():
		c["pending_event"] = {}
		return
	var star: String = seats[0] if float(driver(seats[0])["ego"]) >= float(driver(seats[1])["ego"]) else seats[1]
	var low: String = seats[0] if int(driver(seats[0])["morale"]) <= int(driver(seats[1])["morale"]) else seats[1]
	var d1: String = seats[0]
	var d2: String = seats[1]
	if pick["id"] == "held_back" and flags.get("held", "") == d1:
		d1 = seats[1]
		d2 = seats[0]
	# The rival in the story is the team next to you in the championship.
	var table := standings_teams()
	var rival := ""
	for i in table.size():
		if table[i]["id"] == c["team"]:
			rival = str(table[i - 1 if i > 0 else 1]["name"])
	recent.append(pick["id"])
	while recent.size() > 5:
		recent.pop_front()
	c["event_log"] = recent
	c["last_event"] = pick["id"]
	if pick["id"] == "cost_cap_audit":
		c["audited"] = true
	c["pending_event"] = {"id": pick["id"], "d1": d1, "d2": d2, "star": star, "other": seats[1] if star == seats[0] else seats[0],
		"low": low, "high": seats[1] if low == seats[0] else seats[0], "rival": rival, "facts": facts}


func pending_event() -> Dictionary:
	var p: Dictionary = state().get("pending_event", {})
	if p.is_empty():
		return {}
	var e := _event(p["id"]).duplicate(true)
	if e.is_empty():
		return {}
	e["text"] = _fill(e["text"], p)
	e["why"] = _fill(str(e.get("why", "")), p)
	for option: Dictionary in e["options"]:
		option["text"] = _fill(option["text"], p)
		# Exactly what the choice costs and pays, spelled out before you pick.
		option["outcome"] = effects_text(option["effects"], p)
	return e


func _fill(text: String, p: Dictionary) -> String:
	var words := {
		"d1": driver(p["d1"]).get("name", "?"), "d2": driver(p["d2"]).get("name", "?"), "star": driver(p["star"]).get("name", "?"),
		"low": driver(str(p.get("low", p["d1"]))).get("name", "?"), "high": driver(str(p.get("high", p["d2"]))).get("name", "?"),
		"rival": p["rival"], "owner": my_team()["owner"], "team": my_team()["name"],
	}
	var facts: Dictionary = p.get("facts", {})
	for key: String in facts:
		words[key] = str(int(facts[key]))
	return text.format(words)


## One line listing every consequence of a set of effects: "+$2.5M  ·  BOARD -5  ·  ...".
func effects_text(effects: Dictionary, p: Dictionary) -> String:
	var parts := PackedStringArray()
	for key: String in effects:
		var v: Variant = effects[key]
		match key:
			"money":
				parts.append("%s%s" % ["+" if int(v) > 0 else "", money_text(float(v))])
			"board":
				parts.append("BOARD %+d" % int(v))
			"rep":
				parts.append("REPUTATION %+d" % int(v))
			"car":
				parts.append("CAR %+d" % int(v))
			"fia":
				parts.append("FIA ATTENTION %+d" % int(v))
			"cap":
				parts.append("COST CAP ROOM %s" % money_text(-float(v)))
			"rp":
				parts.append("RESEARCH %+d" % int(v))
			"tunnel":
				parts.append("+%d WIND-TUNNEL RUNS" % int(v))
			"promise":
				parts.append("PODIUM OWED IN %d RACES (OR BOARD -15)" % int(v))
			"number_one":
				parts.append("%s BECOMES NO.1" % str(driver(p["star"])["name"]).get_slice(" ", 1).to_upper())
			"gamble":
				var chance := int(round(float(v["chance"]) * 100.0))
				parts.append("%d%% CHANCE: %s   /   %d%%: %s" % [chance, effects_text(v["win"], p), 100 - chance, effects_text(v["lose"], p)])
			_:
				var who := driver(str(p.get(key.get_slice("_", 1), "")))
				if who.is_empty():
					continue
				var surname := str(who["name"]).get_slice(" ", 1).to_upper()
				if key.begins_with("morale_"):
					parts.append("%s MORALE %+d" % [surname, int(v)])
				elif key.begins_with("salary_"):
					parts.append("%s PAY %+d%%" % [surname, int(float(v) * 100.0)])
	return "  ·  ".join(parts) if not parts.is_empty() else "NOTHING CHANGES"


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
			"rp":
				c["rp"] = clampi(int(c["rp"]) + int(v), 0, MAX_RP)
				notes.append("Research %+d" % int(v))
			"tunnel":
				c["tunnel_used"] = int(c.get("tunnel_used", 0)) - int(v)
				notes.append("+%d wind-tunnel runs" % int(v))
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
			text = _pick(["Podium! Feels awsome. We can win one of these.", "Solid points. The car was alive today.", "Champagne tastes better than I remembered."])
		elif pos <= 10:
			text = _pick(["Points. I'll take it. We need more pace though.", "Decent day. Strategy was fine, the car wasn't.", "Top ten. Not what I signed up for, but ok."])
		else:
			text = _pick(["P%d. I can't race like this." % pos, "We were nowhere. Tell me there's an upgrade coming.", "Tuff one. Head down, next race."])
		if morale < 35:
			text += " " + _pick(["My manager wants a meeting.", "Honestly? I'm definately not happy here.", "Something has to change."])
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
			"poach":
				result = _sell_driver(offer["driver"], offer["team"], int(offer["cash"]))
			"poach_eng":
				result = _lose_engineer(offer["engineer"], offer["team"], int(offer["cash"]))
	elif offer["type"] == "poach":
		result = _counter_poach(offer)
	elif offer["type"] == "poach_eng":
		result = _counter_engineer(offer)
	GameManager.save()
	return result


func _sell_driver(id: String, to_team: String, cash: int) -> String:
	if not lineup().has(id):
		return "That driver is no longer yours to sell."
	var replacement: Dictionary = {}
	# The bench steps up first; only an empty bench sends you to the market.
	for r: String in reserves():
		if replacement.is_empty() or driver_overall(driver(r)) > driver_overall(replacement):
			replacement = driver(r)
	if not replacement.is_empty():
		reserves().erase(replacement["id"])
	else:
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
	_hand_over_car(id, replacement["id"])
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
	# The engineers and the cars belong to the team you are leaving.
	for id: String in c["engineers"]:
		c["staff"][id]["team"] = ""
	c.erase("cars")
	for id: String in ["owner", "engineer", "tech", "scout"]:
		c["people"][id]["team"] = team_id
	GameManager.profile["money"] = int(team(team_id)["budget"])
	EventBus.money_changed.emit(GameManager.money())
	_refresh_sponsor_offers()
	_init_team_extras()
	add_message("owner", "Welcome to %s. The target: %s." % [team(team_id)["name"], board_target_text().to_lower()])
	return "You are now team principal of %s." % team(team_id)["name"]


# ---------------------------------------------------------------- race weekend

var _weekend_sim: GPSim


## The simulation for the upcoming race (qualifying already run). Kept until the race is booked.
func weekend_sim() -> GPSim:
	if _weekend_sim == null:
		_weekend_sim = GPSim.new()
		_weekend_sim.setup(race_entries(), next_round(), int(state()["factory"]["pit"]), int(Time.get_ticks_usec()))
		_weekend_sim.pit_bonus += best_engineer("strategy") / 100.0 * 0.8
	return _weekend_sim


func clear_weekend() -> void:
	_weekend_sim = null
	quali_results = {}
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
## One-line note for HQ to show when it next opens (e.g. after a practice drive).
var last_note := ""
## Lap times set in this weekend's qualifying, per driver.
var quali_results: Dictionary = {}
## Driving at this fraction of the car's ideal lap is worth the driver's simulated grid slot
## (measured: an average AI driver laps at about 1.2x the ideal); every 1% faster or slower
## moves the qualifying time by QUALI_SPREAD seconds.
const QUALI_PAR := 1.215
const QUALI_SPREAD := 0.25


## Qualifying: one flying lap in the real driving game sets this driver's grid slot.
func prepare_quali(driver_id: String) -> void:
	build_drive(driver_id)
	GameManager.career_race["quali"] = driver_id
	GameManager.start_session(GameManager.MODE_TIME_TRIAL)


## Books a qualifying lap. `ratio` = lap time / the car's ideal lap on this track.
## Returns the new grid position.
func apply_quali(driver_id: String, lap_time: float, ratio: float) -> int:
	var sim := weekend_sim()
	quali_results[driver_id] = lap_time
	for car in sim.cars:
		if car["id"] == driver_id:
			car["quali"] = sim.base_quali(car) + (ratio - QUALI_PAR) * 100.0 * QUALI_SPREAD + float(weekend_bonus().get("quali", 0.0))
	sim.regrid()
	for car in sim.cars:
		if car["id"] == driver_id:
			return int(car["position"])
	return 0


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
	# You drive the car assigned to this driver; it becomes the car in the garage.
	set_active_car(str(car_for(driver_id)["id"]))
	var my_strength := driver_car_rating(driver_id)
	GameManager.session_weather = sim.weather
	GameManager.session_night = bool(next_round().get("night", false))
	var sprint := str(next_round().get("format", "gp")) == "sprint"
	GameManager.race_laps = GameManager.SPRINT_LAPS if sprint else GameManager.RACE_LAPS
	# Grand Prix rule: in the dry every car must use two different dry compounds - one stop.
	GameManager.mandatory_stop = not sprint and sim.weather == 0
	for i in range(start, start + 8):
		var car: Dictionary = sim.cars[i]
		if car["id"] == driver_id:
			continue
		var d := driver(car["id"])
		var delta := (float(car["car"]) - my_strength) * 0.6 + (driver_overall(d) - 80.0) * 0.3 + track_form(d, round_track()) * 6.0
		rivals.append({
			"id": car["id"], "name": car["name"], "color": car["color"], "color2": car.get("color2", "#f4f6f2"), "pace": clampf(0.93 + delta * 0.004, 0.86, 0.985),
			"braking_accuracy": clampf(float(d["consistency"]) / 100.0, 0.7, 0.97), "consistency": clampf(float(d["consistency"]) / 100.0, 0.7, 0.97),
			"aggression": clampf(float(d["ego"]) / 100.0, 0.3, 0.9), "tire_management": 0.7, "error_rate": clampf((100.0 - float(d["consistency"])) / 150.0, 0.03, 0.2),
			"wet": clampf(float(d["wet"]) / 100.0, 0.4, 1.0),
			"setup": {"tires": _rival_tires(sim.weather)},
		})
	GameManager.track_id = round_track()
	GameManager.career_race = {"driver": driver_id, "driver_name": driver(driver_id)["name"], "rivals": rivals, "race": next_round()["name"]}
	GameManager.active_mission = -1
	GameManager.session_mode = GameManager.MODE_RACE


## Rivals run your dry compound (a fair fight), and rain tyres when it is wet.
func _rival_tires(weather: int) -> String:
	if weather > 0:
		return "tires_inter" if weather == 1 else "tires_wet"
	var mine: String = GameManager.setup.parts.get("tires", "tires_hard")
	var part := PartDB.get_part(mine)
	return "tires_medium" if part == null or part.stat("wet", 0.0) > 0.0 else mine


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


# ---------------------------------------------------------------- driver traits and conditions

## Fills in the detailed card of a driver (wet skill, tyre care, home track, car taste...).
## Derived from the driver's id so the same driver always gets the same card.
func _ensure_traits(d: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(d["id"]) + str(d["name"]))
	var pace := float(d["pace"])
	d["wet"] = clampi(int(pace) + rng.randi_range(-13, 7), 40, 99)
	d["tyres"] = clampi(int(float(d["consistency"])) + rng.randi_range(-8, 8), 40, 99)
	d["overtaking"] = clampi(int(float(d["racecraft"])) + rng.randi_range(-7, 7), 40, 99)
	d["defending"] = clampi(int(float(d["racecraft"])) + rng.randi_range(-7, 7), 40, 99)
	d["starts"] = clampi(int(pace) + rng.randi_range(-10, 6), 40, 99)
	var ids := GameManager.TRACKS
	d["home"] = ids[rng.randi() % ids.size()]
	var types: Array = TRACK_TYPES.values()
	d["strong"] = types[rng.randi() % types.size()]
	d["weak"] = types[(types.find(d["strong"]) + 1 + rng.randi() % (types.size() - 1)) % types.size()]
	d["likes_balance"] = rng.randi_range(-1, 1)
	d["likes_aero"] = rng.randi_range(-1, 1)


## Seconds per lap this driver finds (or loses) at a circuit.
func track_form(d: Dictionary, track_id: String) -> float:
	var form := 0.0
	if str(d.get("home", "")) == track_id:
		form += HOME_GAIN
	var kind := str(TRACK_TYPES.get(track_id, ""))
	if str(d.get("strong", "")) == kind:
		form += TYPE_GAIN
	elif str(d.get("weak", "")) == kind:
		form -= TYPE_GAIN
	return form


func weather_label(d: Dictionary) -> String:
	var gap := float(d["wet"]) - float(d["pace"])
	if gap >= 2.0:
		return "RAIN MASTER  -  quicker than the field when it is wet"
	if gap <= -7.0:
		return "DRY SPECIALIST  -  loses time and takes risks in the rain"
	return "ALL CONDITIONS  -  no real weakness in wet or dry"


## Short tag for the next race: "HOME RACE", "LOVES STREET TRACKS", ... or "".
func form_note(d: Dictionary, track_id: String) -> String:
	if str(d.get("home", "")) == track_id:
		return "HOME RACE"
	var kind := str(TRACK_TYPES.get(track_id, ""))
	if str(d.get("strong", "")) == kind:
		return "LOVES %s TRACKS" % kind
	if str(d.get("weak", "")) == kind:
		return "STRUGGLES ON %s TRACKS" % kind
	return ""


# ---------------------------------------------------------------- setting up the factory floor

func _init_team_extras() -> void:
	var c := state()
	if not c.has("staff"):
		c["staff"] = {}
		c["engineers"] = []
		_generate_engineers(22, true)
	else:
		# New team: the office here already has a few people at their desks.
		c["engineers"] = []
		_generate_engineers(3, true)
	c["rp"] = int(c.get("rp", 30))
	c["last_best"] = 0
	c["tunnel_used"] = 0
	var first := {"id": "car1", "name": "%s-01" % my_team()["short"], "setup": GameManager.setup.to_dict(), "materials": {}, "tunnel": 0.0}
	for area: String in MATERIAL_AREAS:
		first["materials"][area] = 0
	c["cars"] = [first]
	c["car_count"] = 1
	c["active_car"] = "car1"
	c["car_of"] = {}
	if not c.has("regs"):
		c["regs"] = _default_regs()


func _generate_engineers(count: int, staff_some: bool) -> void:
	var c := state()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var specs: Array = ENGINEER_SPECS.keys()
	var house := 76 - int(my_team()["expectation"]) * 2
	for i in count:
		var id := "eng_%d_%d" % [int(c["season"]), rng.randi() % 1000000]
		var mine := staff_some and i < 3
		var employer := ""
		var skill := rng.randi_range(48, 84)
		if mine:
			employer = c["team"]
			skill = clampi(house + rng.randi_range(-7, 5), 45, 88)
		elif i % 2 == 0:
			# Half the paddock's good engineers already work for somebody.
			employer = teams[rng.randi() % teams.size()]["id"]
			if employer == c["team"]:
				employer = ""
			else:
				skill = rng.randi_range(68, 96)
		var salary := 180 + maxi(0, skill - 45) * 42
		c["staff"][id] = {
			"id": id, "name": "%s %s" % [FIRST_NAMES[rng.randi() % FIRST_NAMES.size()], LAST_NAMES[rng.randi() % LAST_NAMES.size()]],
			"spec": specs[i % specs.size()] if mine else specs[rng.randi() % specs.size()], "skill": skill, "salary": salary,
			"team": employer, "age": rng.randi_range(26, 58), "look": PixelArt.random_look(rng.randi(), 0 if rng.randf() < 0.6 else 3),
		}
		if mine:
			c["engineers"].append(id)


# ---------------------------------------------------------------- engineers and research

func engineers() -> Array:
	return state().get("engineers", [])


func engineer(id: String) -> Dictionary:
	return state()["staff"].get(id, {})


func max_engineers() -> int:
	return int(regs().get("max_engineers", ENGINEER_SLOTS))


## Everyone you could hire: free agents first, then people under contract at rival teams.
func engineer_market() -> Array:
	var out: Array = []
	for id: String in state()["staff"]:
		if not engineers().has(id):
			out.append(state()["staff"][id])
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if (str(a["team"]) == "") != (str(b["team"]) == ""):
			return str(a["team"]) == ""
		return int(a["skill"]) > int(b["skill"]))
	return out


## Buyout owed to a rival team for an engineer under contract there (0 for a free agent).
func engineer_buyout(e: Dictionary) -> int:
	return 0 if str(e["team"]) == "" or str(e["team"]) == str(state()["team"]) else int(float(e["salary"]) * 1.5)


func hire_engineer(id: String) -> String:
	var e := engineer(id)
	if e.is_empty() or engineers().has(id):
		return "Not available."
	if engineers().size() >= max_engineers():
		return "FIA headcount limit: %d engineers." % max_engineers()
	var fee := engineer_buyout(e)
	if GameManager.money() < fee:
		return "Not enough cash for the %s buyout." % money_text(fee)
	GameManager.add_money(-fee)
	if fee > 0:
		add_message("boss_%s" % e["team"], "So that's where %s went. Poaching my staff - noted." % e["name"])
	e["team"] = state()["team"]
	engineers().append(id)
	GameManager.save()
	return ""


## Letting an engineer go costs a quarter of a season's salary in severance.
func fire_engineer(id: String) -> String:
	if not engineers().has(id):
		return "Not on your staff."
	var e := engineer(id)
	var severance := int(float(e["salary"]) * 0.25)
	GameManager.add_money(-severance)
	engineers().erase(id)
	e["team"] = ""
	GameManager.save()
	return "%s released. Severance %s." % [e["name"], money_text(severance)]


func engineer_salaries() -> int:
	var total := 0
	for id: String in engineers():
		total += int(engineer(id)["salary"])
	return total


## 0-100: the combined skill of the office. Empty desks drag it down.
func engineering_rating() -> int:
	var total := 0.0
	for id: String in engineers():
		total += float(engineer(id)["skill"])
	return int(round(total / ENGINEER_SLOTS))


## Skill of your best engineer in a specialism (0 when you have nobody).
func best_engineer(spec: String) -> float:
	var best := 0.0
	for id: String in engineers():
		if str(engineer(id)["spec"]) == spec:
			best = maxf(best, float(engineer(id)["skill"]))
	return best


## Research points the office produces this week: engineer quality, scaled by how the
## last race went (good results bring data and motivation), plus the data analysts' share.
func research_income() -> Dictionary:
	var best := int(state().get("last_best", 0))
	var mult := 1.0
	var why := "no race yet"
	if best == 1:
		mult = 1.5
		why = "race win"
	elif best >= 2 and best <= 3:
		mult = 1.3
		why = "podium"
	elif best >= 4 and best <= 10:
		mult = 1.1
		why = "points finish"
	elif best >= 99:
		mult = 0.7
		why = "double DNF"
	elif best > 10:
		mult = 0.9
		why = "no points"
	var base := engineering_rating() * 0.55
	var data := best_engineer("data") * 0.12
	return {"base": int(round(base)), "mult": mult, "why": why, "data": int(round(data)), "total": int(round(base * mult + data))}


# ---------------------------------------------------------------- cars

func cars() -> Array:
	return state().get("cars", [])


func car(id: String) -> Dictionary:
	for c: Dictionary in cars():
		if c["id"] == id:
			return c
	return cars()[0] if not cars().is_empty() else {}


func active_car() -> Dictionary:
	return car(str(state().get("active_car", "")))


## The garage always edits GameManager.setup; this writes it back into the active car.
func sync_active_car() -> void:
	var c := state()
	if c.is_empty() or not c.has("cars") or (c["cars"] as Array).is_empty():
		return
	active_car()["setup"] = GameManager.setup.to_dict()


## Rolls another car into the garage (and onto the track, if you drive).
func set_active_car(id: String) -> void:
	if str(state().get("active_car", "")) == id:
		return
	sync_active_car()
	state()["active_car"] = id
	GameManager.setup = CarSetup.from_dict(active_car()["setup"])
	EventBus.setup_changed.emit()
	GameManager.save()


func car_setup(c: Dictionary) -> CarSetup:
	if c.get("id", "") == state().get("active_car", ""):
		return GameManager.setup
	return CarSetup.from_dict(c["setup"])


## The car a driver races. Unassigned drivers get the first car.
func car_for(driver_id: String) -> Dictionary:
	return car(str(state()["car_of"].get(driver_id, "")))


func assign_car(driver_id: String, car_id: String) -> void:
	state()["car_of"][driver_id] = car_id
	GameManager.save()


func _hand_over_car(from_driver: String, to_driver: String) -> void:
	var map: Dictionary = state()["car_of"]
	if map.has(from_driver):
		map[to_driver] = map[from_driver]
		map.erase(from_driver)


## Builds another car as a copy of the one in the garage. Returns "" or why it failed.
func build_new_car() -> String:
	var c := state()
	if cars().size() >= MAX_CARS:
		return "The garage only has room for %d cars." % MAX_CARS
	if GameManager.money() < NEW_CAR_COST:
		return "A new chassis costs %s." % money_text(NEW_CAR_COST)
	if NEW_CAR_COST > cap_left():
		return "A new chassis would break the cost cap."
	GameManager.add_money(-NEW_CAR_COST)
	charge_cap(NEW_CAR_COST)
	sync_active_car()
	c["car_count"] = int(c.get("car_count", cars().size())) + 1
	var built := {"id": "car%d" % int(c["car_count"]), "name": "%s-%02d" % [my_team()["short"], int(c["car_count"])], "setup": (active_car()["setup"] as Dictionary).duplicate(true), "materials": {}, "tunnel": 0.0}
	for area: String in MATERIAL_AREAS:
		built["materials"][area] = 0
	cars().append(built)
	GameManager.save()
	return ""


func scrap_car(id: String) -> String:
	if cars().size() <= 1:
		return "You need at least one car."
	var doomed := car(id)
	cars().erase(doomed)
	for driver_id: String in state()["car_of"].keys():
		if state()["car_of"][driver_id] == id:
			state()["car_of"].erase(driver_id)
	if state()["active_car"] == id:
		state()["active_car"] = ""
		set_active_car(str(cars()[0]["id"]))
	GameManager.save()
	return "%s scrapped." % doomed["name"]


## Overall of one car: the team's baseline, the build, the factory, materials and how much
## the wind tunnel has taught you about it.
func car_overall(c: Dictionary) -> float:
	if c.is_empty():
		return 40.0
	var f: Dictionary = state()["factory"]
	var tiers := 0
	for area: String in c["materials"]:
		tiers += int(c["materials"][area])
	var base: float = state()["team_cars"].get(state()["team"], 70.0)
	return clampf(base + (build_rating(car_setup(c)) - _starter_rating()) * 0.8 + (int(f["aero"]) + int(f["power"])) * 1.5 + float(state()["car_bonus"])
		+ tiers * MATERIAL_BONUS + float(c.get("tunnel", 0.0)) * TUNNEL_BONUS, 40.0, 99.0)


## 0-100: how well a car suits a driver's taste in balance and wing level.
func car_fit(d: Dictionary, c: Dictionary) -> int:
	if d.is_empty() or c.is_empty():
		return 0
	var s := setup_stats(car_setup(c))
	if not s.valid:
		return 0
	var balance_target: float = [-0.045, 0.0, 0.045][clampi(int(d["likes_balance"]) + 1, 0, 2)]
	var balance_score := 1.0 - clampf(absf(s.balance_index - balance_target) / 0.09, 0.0, 1.0)
	var cornering := s.mech_grip_g + s.downforce_200 / (s.mass * VehiclePhysicsConfig.GRAVITY) * 0.5
	var bias := clampf(inverse_lerp(1.5, 2.4, cornering), 0.0, 1.0) - clampf(inverse_lerp(200.0, 310.0, s.top_speed * 3.6), 0.0, 1.0)
	var aero_target: float = [-0.25, 0.0, 0.25][clampi(int(d["likes_aero"]) + 1, 0, 2)]
	var aero_score := 1.0 - clampf(absf(bias - aero_target) / 0.6, 0.0, 1.0)
	return int(round(45.0 + 55.0 * (0.55 * balance_score + 0.45 * aero_score)))


## What the car is worth in this driver's hands.
func driver_car_rating(driver_id: String) -> float:
	var c := car_for(driver_id)
	var fit := car_fit(driver(driver_id), c)
	return clampf(car_overall(c) + (fit - 75.0) * 0.07, 40.0, 99.0)


func car_taste(d: Dictionary) -> String:
	return "%s WITH %s" % [BALANCE_NAMES[clampi(int(d["likes_balance"]) + 1, 0, 2)], AERO_NAMES[clampi(int(d["likes_aero"]) + 1, 0, 2)]]


## Research points for the next material tier on an area of a car (0 = already the best).
func material_cost(c: Dictionary, area: String) -> int:
	var tier := int(c["materials"].get(area, 0))
	if tier >= MATERIAL_COSTS.size():
		return 0
	# A specialist in that field knows where to save.
	var discount := 1.0 - best_engineer(str(MATERIAL_AREAS[area]["spec"])) / 400.0
	return int(round(MATERIAL_COSTS[tier] * discount))


func upgrade_material(car_id: String, area: String) -> String:
	var c := car(car_id)
	var cost := material_cost(c, area)
	if cost <= 0:
		return "Already the best material there is."
	if int(state()["rp"]) < cost:
		return "Needs %d research points - your engineers have produced %d." % [cost, int(state()["rp"])]
	state()["rp"] = int(state()["rp"]) - cost
	c["materials"][area] = int(c["materials"].get(area, 0)) + 1
	GameManager.save()
	return ""


# ---------------------------------------------------------------- FIA regulations

func regs() -> Dictionary:
	return state().get("regs", {})


func _default_regs() -> Dictionary:
	var starter := CarSetup.new()
	var parts: Dictionary = GameManager.economy.get("starting_parts", {})
	for slot: String in parts:
		starter.install(slot, parts[slot])
	return {"min_weight": int(setup_stats(starter).mass) - 28, "max_wing": CarSetup.WING_ANGLE_MAX, "banned": [], "max_engineers": ENGINEER_SLOTS, "v": 2}


## Everything the scrutineers would object to on a car.
func car_violations(c: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if c.is_empty():
		return out
	var setup := car_setup(c)
	var rules := regs()
	var s := setup_stats(setup)
	if s.valid and s.mass < float(rules["min_weight"]):
		out.append("UNDERWEIGHT: %d kg, minimum %d kg (fit ballast)" % [int(s.mass), int(rules["min_weight"])])
	if setup.front_wing_angle > int(rules["max_wing"]):
		out.append("FRONT WING ANGLE %d, maximum %d" % [setup.front_wing_angle, int(rules["max_wing"])])
	if setup.rear_wing_angle > int(rules["max_wing"]):
		out.append("REAR WING ANGLE %d, maximum %d" % [setup.rear_wing_angle, int(rules["max_wing"])])
	for slot: String in setup.parts:
		if (rules["banned"] as Array).has(setup.parts[slot]):
			out.append("BANNED PART: %s" % PartDB.get_part(setup.parts[slot]).display_name.to_upper())
	return out


func is_banned(part_id: String) -> bool:
	return active() and (regs().get("banned", []) as Array).has(part_id)


## Post-race scrutineering. An illegal car is usually caught: the driver is disqualified,
## the team fined, and the FIA starts paying closer attention. Returns the names thrown out.
func _scrutineer(order: Array) -> Array:
	var c := state()
	var out: Array = []
	for entry: Dictionary in order.duplicate():
		if not entry["is_player"] or entry["dnf"]:
			continue
		var faults := car_violations(car_for(entry["id"]))
		if faults.is_empty() or _rng.randf() > 0.7 + 0.08 * int(c["fia"]):
			continue
		entry["dnf"] = true
		entry["dsq"] = true
		order.erase(entry)
		order.append(entry)
		out.append(entry["name"])
		c["fia"] = int(c["fia"]) + 1
		GameManager.add_money(-600)
		entry["dsq_reason"] = faults[0]
		add_message("tech", "DISQUALIFIED. The scrutineers threw %s out: %s. %s fine. Fix the car in the garage before the next race." % [entry["name"], faults[0].to_lower(), money_text(600)])
	if engineers().size() > max_engineers():
		GameManager.add_money(-400)
		c["fia"] = int(c["fia"]) + 1
		add_message("tech", "The FIA counted %d engineers in our office; the limit is %d. %s fine - and it repeats every race until someone goes." % [engineers().size(), max_engineers(), money_text(400)])
	return out


## Every winter the rulebook moves: minimum weight, wing limits, a banned part, headcount.
func _new_season_rules() -> void:
	var c := state()
	var rules := regs()
	rules["min_weight"] = int(rules["min_weight"]) + _rng.randi_range(-6, 10)
	rules["max_wing"] = _rng.randi_range(8, 10)
	rules["max_engineers"] = [5, 5, 5, 4, 6][_rng.randi() % 5]
	rules["banned"] = []
	var notes := PackedStringArray(["minimum weight %d kg" % int(rules["min_weight"]), "wing angles capped at %d" % int(rules["max_wing"]), "%d engineers per team" % int(rules["max_engineers"])])
	if _rng.randf() < 0.6:
		var pool: Array = []
		for tier: Dictionary in rd_tiers:
			if int(tier["level"]) >= 2:
				pool.append_array(tier["unlocks"])
		var banned: String = pool[_rng.randi() % pool.size()]
		rules["banned"] = [banned]
		notes.append("the %s is BANNED" % PartDB.get_part(banned).display_name)
	# A new rulebook means last year's wind-tunnel data only half applies.
	for built: Dictionary in cars():
		built["tunnel"] = float(built.get("tunnel", 0.0)) * 0.5
	c["tunnel_used"] = 0
	_generate_engineers(5, false)
	add_message("tech", "New FIA technical regulations for season %d: %s. Check every car on the FIA tab." % [int(c["season"]), ", ".join(notes)])


# ---------------------------------------------------------------- wind tunnel

## Aerodynamic testing restriction: the better you are doing, the fewer runs you get.
func tunnel_allowance() -> int:
	return 2 + (team_position() - 1) / 3


func tunnel_runs_left() -> int:
	return maxi(0, tunnel_allowance() - int(state().get("tunnel_used", 0)))


## One wind-tunnel run on a car. Each run improves how well the model matches the real
## car, which is worth car rating. Returns {"error"} or {"gain", "tunnel"}.
func run_tunnel(car_id: String) -> Dictionary:
	if tunnel_runs_left() <= 0:
		return {"error": "No wind-tunnel runs left this week (FIA allowance: %d)." % tunnel_allowance()}
	var c := car(car_id)
	var before := float(c.get("tunnel", 0.0))
	if before >= 1.0:
		return {"error": "This car's model is fully correlated - nothing left to learn until the rules change."}
	var gain := 0.1 + best_engineer("aero") / 100.0 * 0.14
	c["tunnel"] = minf(1.0, before + gain)
	state()["tunnel_used"] = int(state().get("tunnel_used", 0)) + 1
	GameManager.save()
	return {"gain": float(c["tunnel"]) - before, "tunnel": float(c["tunnel"])}


# ---------------------------------------------------------------- talent poaching

## Offers you did not answer before the next race go ahead without you.
func _expire_offers() -> void:
	var lapsed: Array = []
	for m: Dictionary in state()["inbox"]:
		if not m["done"] and str(m["offer"].get("type", "")) in ["poach", "poach_eng"]:
			lapsed.append(m)
	for m: Dictionary in lapsed:
		m["done"] = true
		var offer: Dictionary = m["offer"]
		var result := _sell_driver(offer["driver"], offer["team"], int(offer["cash"])) if offer["type"] == "poach" else _lose_engineer(offer["engineer"], offer["team"], int(offer["cash"]))
		add_message("owner", "You never answered %s. The clause was triggered without us. %s" % [team(offer["team"])["name"], result])


func _open_poach() -> bool:
	for m: Dictionary in state()["inbox"]:
		if not m["done"] and str(m["offer"].get("type", "")) in ["poach", "poach_eng"]:
			return true
	return false


## After every race rivals look at your people. Stars, unhappy drivers and good engineers
## attract a triggered release clause: match the money or take the buyout.
func _poaching_round() -> void:
	var c := state()
	if c["fired"] or _open_poach():
		return
	var rivals: Array = []
	for t: Dictionary in teams:
		if t["id"] != c["team"]:
			rivals.append(t)
	var rival: Dictionary = rivals[_rng.randi() % rivals.size()]
	for id: String in lineup():
		var d := driver(id)
		if is_injured(id):
			continue
		var chance := 0.04 + maxf(0.0, driver_overall(d) - 80.0) * 0.008 + (0.14 if int(d["morale"]) < 40 else 0.0) + (0.04 if float(c["team_cars"][rival["id"]]) > car_rating(c["team"]) else 0.0)
		if _rng.randf() < chance:
			var cash := release_clause(d)
			add_message("boss_%s" % rival["id"], "I'll be direct: we have triggered %s's release clause - %s. They are ready to sign with %s. Better the deal before the next race, or bank the buyout." % [d["name"], money_text(cash), rival["name"]],
				{"type": "poach", "driver": id, "team": rival["id"], "cash": cash, "yes": "RELEASE  +%s" % money_text(cash), "no": "COUNTER  +20%% PAY"})
			return
	if engineers().is_empty() or _rng.randf() > 0.13:
		return
	var target := ""
	for id: String in engineers():
		if target == "" or int(engineer(id)["skill"]) > int(engineer(target)["skill"]):
			target = id
	if int(engineer(target)["skill"]) < 62:
		return
	var e := engineer(target)
	var fee := int(float(e["salary"]) * 1.5)
	add_message("boss_%s" % rival["id"], "Your %s, %s, has an offer from us on the table. Buyout %s. Match it with a raise or wave goodbye." % [str(ENGINEER_SPECS[e["spec"]]["name"]).to_lower(), e["name"], money_text(fee)],
		{"type": "poach_eng", "engineer": target, "team": rival["id"], "cash": fee, "yes": "RELEASE  +%s" % money_text(fee), "no": "COUNTER  +20%% PAY"})


## The counter-offer: a 20% raise keeps a driver who still believes in the project.
func _counter_poach(offer: Dictionary) -> String:
	var id: String = offer["driver"]
	if not lineup().has(id):
		return "That driver has already gone."
	var d := driver(id)
	if int(d["morale"]) < 30:
		return "%s refused the raise and wants out. %s" % [d["name"], _sell_driver(id, offer["team"], int(offer["cash"]))]
	var old := int(d["salary"])
	d["salary"] = int(old * 1.2)
	if salary_total() > SALARY_CAP:
		d["salary"] = old
		return "The raise would break the salary cap. %s" % _sell_driver(id, offer["team"], int(offer["cash"]))
	d["morale"] = mini(100, int(d["morale"]) + 8)
	return "%s stays on %s a season." % [d["name"], money_text(float(d["salary"]))]


func _lose_engineer(id: String, to_team: String, cash: int) -> String:
	if not engineers().has(id):
		return "That engineer has already left."
	engineers().erase(id)
	engineer(id)["team"] = to_team
	GameManager.add_money(cash)
	return "%s joins %s. Buyout %s banked." % [engineer(id)["name"], team(to_team)["name"], money_text(cash)]


func _counter_engineer(offer: Dictionary) -> String:
	var id: String = offer["engineer"]
	if not engineers().has(id):
		return "That engineer has already left."
	var e := engineer(id)
	e["salary"] = int(float(e["salary"]) * 1.2)
	return "%s stays on %s a season." % [e["name"], money_text(float(e["salary"]))]


# ---------------------------------------------------------------- driver development

func training(id: String) -> int:
	return int(state().get("training", {}).get(id, 1))


func set_training(id: String, level: int) -> void:
	if not state().has("training"):
		state()["training"] = {}
	state()["training"][id] = clampi(level, 0, 3)
	GameManager.save()


func fitness(d: Dictionary) -> int:
	return int(d.get("fitness", 90))


## How much a driver improves per race, before the race result is known.
## Young drivers far from their potential learn fastest; veterans decline.
func development_rate(d: Dictionary) -> float:
	var age := int(d["age"])
	var curve := 1.0 if age <= 21 else (0.8 if age <= 24 else (0.45 if age <= 28 else (0.2 if age <= 32 else -0.25)))
	if curve < 0.0:
		return curve * 0.4
	var room := float(d["potential"]) - float(d["pace"])
	if room <= 0.05:
		return 0.0
	var mine: bool = lineup().has(d["id"]) or reserves().has(d["id"])
	var rate := 0.12 * curve * clampf(room / 6.0, 0.3, 1.5)
	if mine:
		rate *= TRAINING_GAIN[training(d["id"])]
		if d.get("sim", false):
			rate += 0.06 * curve
		# A star team-mate teaches a youngster.
		if age < 24:
			for other: String in lineup():
				if other != d["id"] and driver_overall(driver(other)) >= 85:
					rate *= 1.25
		if reserves().has(d["id"]):
			rate *= 0.5                       # the bench learns, but slower than racing
	return rate


## After each race: experience, training load, fitness and the occasional injury.
func _develop(d: Dictionary, result: Dictionary) -> void:
	var before := driver_overall(d)
	var gain := development_rate(d)
	if not result.is_empty() and gain > 0.0:
		gain *= 0.6 if result.get("dnf", false) else (1.35 if int(result.get("position", 22)) <= 10 else 1.0)
	var room := maxf(0.0, float(d["potential"]) - float(d["pace"]))
	if gain > 0.0:
		gain = minf(gain, room)
	d["pace"] = clampf(float(d["pace"]) + gain, 40.0, 99.0)
	for key: String in ["racecraft", "consistency"]:
		d[key] = clampf(float(d[key]) + gain * 0.8, 40.0, 99.0)
	for key: String in ["wet", "tyres", "overtaking", "defending", "starts"]:
		d[key] = clampf(float(d[key]) + gain * 0.6, 40.0, 99.0)
	var mine: bool = lineup().has(d["id"]) or reserves().has(d["id"])
	if mine:
		var level := training(d["id"])
		d["fitness"] = clampi(fitness(d) + TRAINING_FITNESS[level], 5, 100)
		d["morale"] = clampi(int(d["morale"]) + TRAINING_MORALE[level], 5, 100)
		# Run a driver into the ground and something gives.
		if fitness(d) < 40 and not is_injured(d["id"]) and _rng.randf() < (40.0 - fitness(d)) / 90.0:
			_injure(d, _rng.randi_range(1, 2), "worn out by the training load")
			d["fitness"] = 60
	d["last_gain"] = driver_overall(d) - before
	d["season_gain"] = float(d.get("season_gain", 0.0)) + gain


# ---------------------------------------------------------------- the manager

func manager_contract() -> Dictionary:
	var m: Dictionary = state()["manager"]
	if not m.has("contract"):
		m["contract"] = {"salary": int(float(my_team()["budget"]) * 0.02), "years": 2}
	return m["contract"]


## 30-99: how good a team principal you have proven to be.
func manager_rating() -> int:
	var c := state()
	var score := 55.0 + (int(c["reputation"]) - 50) * 0.3 + (int(c["board"]) - 50) * 0.1
	for h: Dictionary in c.get("history", []):
		score += clampf((int(h["expected"]) - int(h["position"])) * 3.0, -9.0, 12.0) + int(h["wins"]) * 1.0
	return clampi(int(round(score)), 30, 99)


func job_security() -> String:
	var board := int(state()["board"])
	if board >= 80:
		return "UNTOUCHABLE"
	if board >= 60:
		return "SAFE"
	if board >= 40:
		return "STABLE"
	return "UNDER PRESSURE" if board >= 20 else "ON THE BRINK"


## Teams that would hire you now, with the release fee they would pay your current team.
func interested_teams() -> Array:
	var out: Array = []
	var rating := manager_rating()
	for t: Dictionary in teams:
		if t["id"] == state()["team"]:
			continue
		var needed := 40 + (11 - int(t["expectation"])) * 4
		if rating >= needed:
			out.append({"team": t, "salary": int(float(t["budget"]) * 0.022), "fee": int(float(manager_contract()["salary"]) * maxi(1, int(manager_contract()["years"])) * 0.5)})
	return out


## Move to another team: they buy out your contract and give you a fresh two-year deal.
func move_to_team(team_id: String) -> String:
	var deal: Dictionary = {}
	for offer: Dictionary in interested_teams():
		if offer["team"]["id"] == team_id:
			deal = offer
	var result := _switch_team(team_id)
	state()["manager"]["contract"] = {"salary": int(deal.get("salary", float(my_team()["budget"]) * 0.02)), "years": 2}
	return result


## Season review answer when the contract has run out: sign the renewal, or leave.
func renew_contract() -> void:
	var contract := manager_contract()
	contract["salary"] = int(float(contract["salary"]) * 1.1)
	contract["years"] = 2
	state()["season_review"] = {}
	GameManager.save()


# ---------------------------------------------------------------- the calendar

## The season runs day by day from 1 March. Each race weekend is Friday practice,
## Saturday qualifying and the Sunday race; the Friday of the week before is a test day.
const MONTHS: PackedStringArray = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
const WEEKDAYS: PackedStringArray = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
const FIRST_RACE_GAP := 13           # days from 1 March to the first race Sunday (at least)
const RACE_SPACING := 14


func _season_start_unix() -> int:
	var year := 2026 + int(state().get("season", 1))
	return Time.get_unix_time_from_datetime_dict({"year": year, "month": 3, "day": 1, "hour": 12, "minute": 0, "second": 0})


func date_dict(day: int) -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(_season_start_unix() + day * 86400)


func date_text(day: int = -1) -> String:
	var d := date_dict(int(state().get("date", 0)) if day < 0 else day)
	return "%s %d %s" % [WEEKDAYS[int(d["weekday"])], int(d["day"]), MONTHS[int(d["month"]) - 1]]


## Day of the season (0 = 1 March) on which round `index` is raced: always a Sunday.
func race_day(index: int) -> int:
	var first := FIRST_RACE_GAP
	while int(date_dict(first)["weekday"]) != 0:
		first += 1
	return first + index * RACE_SPACING


func today() -> int:
	return int(state().get("date", 0))


## What happens on a day: "race", "quali", "practice", "test" or "rest", with the round.
func day_event(day: int = -1) -> Dictionary:
	var d := today() if day < 0 else day
	for i in range(int(state()["round"]), calendar.size()):
		var r := race_day(i)
		match r - d:
			0:
				return {"type": "race", "round": i}
			1:
				return {"type": "quali", "round": i}
			2:
				return {"type": "practice", "round": i}
			9:
				return {"type": "test", "round": i}
	return {"type": "rest", "round": int(state()["round"])}


func day_title(event: Dictionary) -> String:
	var name := str(calendar[mini(int(event["round"]), calendar.size() - 1)]["name"]).to_upper()
	match str(event["type"]):
		"race":
			return "RACE DAY  ·  %s" % name
		"quali":
			return "QUALIFYING  ·  %s" % name
		"practice":
			return "FREE PRACTICE  ·  %s" % name
		"test":
			return "TEST DAY"
	return "FACTORY DAY"


## Next day. A race day cannot be skipped - it has to be raced (or simulated) first.
## Returns false when it stopped at a race.
func next_day() -> bool:
	var c := state()
	if day_event()["type"] == "race" or season_over():
		return false
	c["date"] = today() + 1
	_daily_news()
	GameManager.save()
	return true


## Sim forward: "week", "race" (to the next race day) or "month". Stops at a race day.
func sim_ahead(span: String) -> int:
	var days := 7 if span == "week" else (30 if span == "month" else 999)
	var moved := 0
	while moved < days:
		if span == "race" and day_event()["type"] == "race":
			break
		if not next_day():
			break
		moved += 1
	return moved


func news() -> Array:
	return state().get("news", [])


func _add_news(text: String) -> void:
	var c := state()
	if not c.has("news"):
		c["news"] = []
	c["news"].push_front({"day": today(), "text": text})
	while c["news"].size() > 30:
		c["news"].pop_back()


## A little paddock news most days: rival developments, driver form, the forecast.
func _daily_news() -> void:
	var event := day_event()
	if event["type"] in ["practice", "quali"]:
		var r: Dictionary = calendar[int(event["round"])]
		_add_news("FORECAST for %s: %d%% chance of rain." % [r["name"], int(float(r["rain"]) * 100.0)])
		return
	if _rng.randf() > 0.4:
		return
	var t: Dictionary = teams[_rng.randi() % teams.size()]
	var hot := ""
	var best := -99.0
	for id: String in state()["drivers"]:
		var d := driver(id)
		if str(d["team"]) != "" and _form_average(d) > best:
			best = _form_average(d)
			hot = id
	var stories: Array = [
		"%s bring a new floor to the next race." % t["name"],
		"%s are said to be over budget on their new car." % t["name"],
		"Wind-tunnel time is the talk of the paddock: %s ran double shifts this week." % t["name"],
	]
	if hot != "" and best > 0.5:
		stories.append("%s is the driver in form - rated up after recent results." % driver(hot)["name"])
	if t["id"] != state()["team"]:
		var target: Array = team_drivers(t["id"])
		if not target.is_empty():
			stories.append("Rumour: %s unsettled at %s." % [driver(target[0])["name"], t["short"]])
	_add_news(stories[_rng.randi() % stories.size()])


# ---------------------------------------------------------------- practice

const PRACTICE_PROGRAMS := {
	"setup": {"name": "SETUP WORK", "note": "Dial the car in for this track: +0.6 car rating this weekend, +8 research."},
	"long_runs": {"name": "RACE SIMULATION", "note": "Long runs on old tyres: better tyre care this weekend, +6 research, a little fitness."},
	"quali": {"name": "QUALIFYING SIMS", "note": "Low fuel, new tyres: faster qualifying this weekend."},
	"rookie": {"name": "YOUNG DRIVER DAY", "note": "Reserves run and learn three times as fast; their form gets a rating."},
}


func weekend_bonus() -> Dictionary:
	return state().get("weekend", {})


func practice_done() -> bool:
	return int(state().get("practice_day", -1)) == today()


## Runs a practice or test session with a programme and up to two drivers (reserves too).
## Returns one result row per driver: name, session position, what they gained.
func run_practice(program: String, driver_ids: Array) -> Array:
	var c := state()
	c["practice_day"] = today()
	if not c.has("weekend"):
		c["weekend"] = {}
	var w: Dictionary = c["weekend"]
	match program:
		"setup":
			w["car"] = minf(1.5, float(w.get("car", 0.0)) + 0.6)
			c["rp"] = mini(MAX_RP, int(c["rp"]) + 8)
		"long_runs":
			w["tyres"] = minf(10.0, float(w.get("tyres", 0.0)) + 5.0)
			c["rp"] = mini(MAX_RP, int(c["rp"]) + 6)
		"quali":
			w["quali"] = maxf(-0.4, float(w.get("quali", 0.0)) - 0.15)
	var rows: Array = []
	for id: String in driver_ids:
		var d := driver(id)
		# Session order: driver and car against the field, plus the day's noise.
		var strength := float(driver_overall(d)) * 0.5 + driver_car_rating(id) * 0.5 + _rng.randfn(0.0, 2.0)
		var position := 1
		for t: Dictionary in teams:
			if t["id"] != c["team"] and float(t["car"]) * 0.5 + 82.0 * 0.5 > strength:
				position += 2
		position = clampi(position + _rng.randi_range(-1, 1), 1, 22)
		var expected := _expected_position(d, driver_car_rating(id))
		_log_form(d, "FP P%d" % position, clampf((expected - position) / 3.0, -3.0, 3.0) * 0.6)
		var gain := development_rate(d) * (3.0 if program == "rookie" and reserves().has(id) else 0.35)
		d["pace"] = minf(99.0, float(d["pace"]) + maxf(gain, 0.0))
		d["fitness"] = clampi(fitness(d) - (4 if program == "long_runs" else 2), 5, 100)
		rows.append({"name": d["name"], "position": position, "gain": gain})
	GameManager.save()
	return rows


## Drive the practice yourself in the real game, on this weekend's circuit.
func prepare_practice(driver_id: String) -> void:
	build_drive(driver_id)
	GameManager.career_race = {"practice": driver_id, "driver_name": driver(driver_id)["name"]}
	GameManager.start_session(GameManager.MODE_TEST)


func finish_practice_drive(laps: int) -> String:
	var c := state()
	c["practice_day"] = today()
	if not c.has("weekend"):
		c["weekend"] = {}
	var bonus := minf(1.5, 0.35 * laps)
	c["weekend"]["car"] = minf(1.5, float(c["weekend"].get("car", 0.0)) + bonus)
	c["rp"] = mini(MAX_RP, int(c["rp"]) + 4 * laps)
	GameManager.save()
	return "PRACTICE: %d LAPS  ·  CAR +%.1f THIS WEEKEND  ·  +%d RESEARCH" % [laps, bonus, 4 * laps]


# ---------------------------------------------------------------- form and ratings

## Where a driver should finish on paper: their car and their overall against the field.
func _expected_position(d: Dictionary, car: float) -> float:
	var mine := car * 0.6 + driver_overall(d) * 0.4
	var better := 0
	for t: Dictionary in teams:
		for id: String in team_drivers(t["id"]):
			if id == d["id"]:
				continue
			var other := driver(id)
			if car_rating(t["id"]) * 0.6 + driver_overall(other) * 0.4 > mine:
				better += 1
	return float(better + 1)


func _log_form(d: Dictionary, label: String, score: float) -> void:
	if not d.has("log"):
		d["log"] = []
	var log: Array = d["log"]
	log.push_front({"r": label, "s": snappedf(score, 0.01)})
	while log.size() > 6:
		log.pop_back()


func _form_average(d: Dictionary) -> float:
	var log: Array = d.get("log", [])
	if log.is_empty():
		return 0.0
	var total := 0.0
	for entry: Dictionary in log.slice(0, 5):
		total += float(entry["s"])
	return total / mini(log.size(), 5)


## After each race every driver who raced gets a form score: finishing position against
## where their car and rating said they should be, a bonus for beating the team-mate,
## a penalty for crashing out. Ratings then drift with the last five scores, and young
## drivers who keep over-performing have their potential raised (and the reverse).
func _record_form(order: Array) -> void:
	var by_team := {}
	for i in order.size():
		var car: Dictionary = order[i]
		if not by_team.has(car["team"]):
			by_team[car["team"]] = []
		by_team[car["team"]].append(i)
	for i in order.size():
		var car: Dictionary = order[i]
		var d := driver(car["id"])
		if d.is_empty() or d.get("hidden", false):
			continue
		var expected := _expected_position(d, float(car["car"]))
		var score := clampf((expected - (i + 1)) / 3.0, -3.0, 3.0)
		var label := "P%d" % (i + 1)
		if car["dnf"]:
			score = -2.0 if car.get("crashed", false) else 0.0
			label = "DSQ" if car.get("dsq", false) else "DNF"
		var mates: Array = by_team.get(car["team"], [])
		if mates.size() == 2 and mates[0] == i and not car["dnf"]:
			score += 0.5
		_log_form(d, label, score)
		_rate_from_form(d)
	# Reserves who did not race drift back towards neutral form.
	for id: String in reserves():
		var d := driver(id)
		if not d.has("log"):
			d["log"] = []


func _rate_from_form(d: Dictionary) -> void:
	var form := _form_average(d)
	var before := driver_overall(d)
	var shift := form * 0.12
	d["pace"] = clampf(float(d["pace"]) + shift, 40.0, 99.0)
	d["racecraft"] = clampf(float(d["racecraft"]) + shift * 0.7, 40.0, 99.0)
	d["consistency"] = clampf(float(d["consistency"]) + shift * 0.7, 40.0, 99.0)
	if int(d["age"]) <= 26:
		d["potential"] = clampf(float(d["potential"]) + form * 0.15, float(d["pace"]), 99.0)
	elif form < 0.0:
		d["potential"] = maxf(float(d["pace"]), float(d["potential"]) + form * 0.05)
	d["form_change"] = int(d.get("form_change", 0)) + driver_overall(d) - before
