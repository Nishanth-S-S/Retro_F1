class_name TrackTheme
extends RefCounted
## What each circuit's surroundings look like: ground colours, vegetation, buildings,
## water and landmarks. Track.gd turns this into scenery; nothing here touches the racing.

const DEFAULT := "tempo_park"
const THEMES := {
	# Rocky desert canyon: sand, mesas, cacti, adobe houses and a solar farm.
	"falcon_ridge": {
		"label": "DESERT CANYON", "rain": 0.08,
		"ground": "c8a468", "stripe": "c29c5f", "patch": "b8925a", "gravel": "e6d3a4",
		"trees": ["cactus", "shrub", "cactus"], "tree_count": 520, "tree_a": "4f7a3a", "tree_b": "6b9a48",
		"buildings": "adobe", "building_count": 46, "rocks": 170, "landmark": "solar", "water": "",
		"fence": true,
	},
	# Harbour city: paved blocks, towers, palms, a quay with cranes and yachts on the sea.
	"port_azure": {
		"label": "HARBOUR CITY", "rain": 0.15,
		"ground": "9aa1a8", "stripe": "a1a8af", "patch": "8f969d", "gravel": "d9cba6",
		"trees": ["palm"], "tree_count": 260, "tree_a": "2f7d46", "tree_b": "4fa85e",
		"buildings": "city", "building_count": 150, "rocks": 0, "landmark": "harbour", "water": "sea",
		"walls": true,
	},
	# Royal park: striped lawns, big round trees, ponds, hedges and red-roofed villas.
	"tempo_park": {
		"label": "ROYAL PARK", "rain": 0.12,
		"ground": "3d7a3a", "stripe": "44853f", "patch": "357034", "gravel": "c9b58a",
		"trees": ["round", "round", "hedge"], "tree_count": 1000, "tree_a": "275c2c", "tree_b": "347a39",
		"buildings": "villa", "building_count": 34, "rocks": 0, "landmark": "ponds", "water": "",
		"fence": true,
	},
	# Skill test track on an old airfield apron: wide open, few distractions, cones and hangars.
	"apex_lab": {
		"label": "TEST TRACK", "rain": 0.1,
		"ground": "8a9c66", "stripe": "93a56d", "patch": "7f915d", "gravel": "d8ccaa",
		"trees": ["shrub", "round"], "tree_count": 160, "tree_a": "4a6b3a", "tree_b": "62884a",
		"buildings": "hangar", "building_count": 10, "rocks": 0, "landmark": "airfield", "water": "",
		"fence": true,
	},
	# Old airfield: pale windswept grass, runways, hangars, parked planes, the lake along one side.
	"silver_lake": {
		"label": "LAKESIDE AIRFIELD", "rain": 0.3,
		"ground": "7f9c58", "stripe": "86a35e", "patch": "748f50", "gravel": "cfc39c",
		"trees": ["round", "shrub"], "tree_count": 380, "tree_a": "3f6b34", "tree_b": "5a8a44",
		"buildings": "hangar", "building_count": 22, "rocks": 0, "landmark": "airfield", "water": "sea",
	},
	# Nordic forest: dark moss, dense pines, snow patches, red cabins and a fjord.
	"nordhaven": {
		"label": "NORDIC FOREST", "rain": 0.45,
		"ground": "2f5a3c", "stripe": "335f40", "patch": "294f35", "gravel": "b9b3a2",
		"trees": ["pine", "pine", "pine", "round"], "tree_count": 1900, "tree_a": "17402a", "tree_b": "2a6a40",
		"buildings": "cabin", "building_count": 60, "rocks": 80, "landmark": "snow", "water": "sea",
	},
	# --- real circuits
	# Monza: the old royal park outside Milan - trees, lawns, villas.
	"monza": {
		"label": "ROYAL PARK, MILAN", "rain": 0.12,
		"ground": "3f7a3a", "stripe": "47843f", "patch": "366f34", "gravel": "cdb98c",
		"trees": ["round", "round", "round", "hedge"], "tree_count": 1300, "tree_a": "24582a", "tree_b": "357a38",
		"buildings": "villa", "building_count": 40, "rocks": 0, "landmark": "ponds", "water": "",
		"fence": true, "extra": "banking",
	},
	# Silverstone: a wartime airfield in the English countryside.
	"silverstone": {
		"label": "ENGLISH AIRFIELD", "rain": 0.4,
		"ground": "6f9a52", "stripe": "77a35a", "patch": "66904b", "gravel": "cfc39c",
		"trees": ["round", "hedge", "shrub"], "tree_count": 520, "tree_a": "345f2e", "tree_b": "4d8240",
		"buildings": "hangar", "building_count": 26, "rocks": 0, "landmark": "airfield", "water": "",
		"fence": true, "extra": "wing",
	},
	# Spa: through the Ardennes forest - dense pines and wooden chalets.
	"spa": {
		"label": "ARDENNES FOREST", "rain": 0.55,
		"ground": "2f5a36", "stripe": "33603b", "patch": "2a5232", "gravel": "b9b3a2",
		"trees": ["pine", "pine", "round"], "tree_count": 2200, "tree_a": "173d27", "tree_b": "2b6a3e",
		"buildings": "cabin", "building_count": 50, "rocks": 50, "landmark": "", "water": "",
		"fence": true, "extra": "river",
	},
	# Interlagos: inside the city of Sao Paulo - streets, towers, palms.
	"interlagos": {
		"label": "SAO PAULO", "rain": 0.35,
		"ground": "9a9f98", "stripe": "a1a69f", "patch": "8d9590", "gravel": "d0bf95",
		"trees": ["palm", "round"], "tree_count": 300, "tree_a": "2f7d46", "tree_b": "4fa85e",
		"buildings": "city", "building_count": 150, "rocks": 0, "landmark": "", "water": "lake",
		"extra": "lake",
	},
	# Red Bull Ring: Styrian alpine meadows with rocks and farmhouses.
	"spielberg": {
		"label": "STYRIAN ALPS", "rain": 0.3,
		"ground": "6a9a4a", "stripe": "72a352", "patch": "5e8c42", "gravel": "c9c0a0",
		"trees": ["pine", "round", "shrub"], "tree_count": 900, "tree_a": "214a2c", "tree_b": "3f7a3a",
		"buildings": "cabin", "building_count": 40, "rocks": 140, "landmark": "", "water": "",
		"fence": true, "extra": "hills",
	},
}


static func of(track_id: String) -> Dictionary:
	return THEMES.get(track_id, THEMES[DEFAULT])


static func label(track_id: String) -> String:
	return str(of(track_id)["label"])


static func rain_chance(track_id: String) -> float:
	return float(of(track_id)["rain"])
