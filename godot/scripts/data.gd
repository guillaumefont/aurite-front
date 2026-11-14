extends Node
## Static game data: buildings, units, damage table, factions, missions.
## Autoloaded as `D`. Every def is normalised so optional keys always exist.

const T := 32
const MW := 64
const MH := 64
const WW := MW * T
const WH := MH * T
const GRASS := 0
const DIRT := 1
const SAND := 2
const ROCK := 3
const WATER := 4
const HARV_CAP := 700
const P0 := Vector2i(9, 53)
const ALT := 1.6

var BLD := {
	"hq": {"name": "Command Yard", "w": 3, "h": 3, "hp": 1600, "cost": 0, "time": 1, "pwr": 20, "sight": 7, "req": []},
	"power": {"name": "Reactor", "w": 2, "h": 2, "hp": 600, "cost": 300, "time": 7, "pwr": 100, "sight": 4, "req": ["hq"]},
	"refinery": {"name": "Refinery", "w": 3, "h": 3, "hp": 1000, "cost": 1400, "time": 13, "pwr": -30, "sight": 5, "req": ["power"]},
	"barracks": {"name": "Barracks", "w": 2, "h": 2, "hp": 700, "cost": 400, "time": 8, "pwr": -20, "sight": 5, "req": ["power"]},
	"factory": {"name": "War Factory", "w": 3, "h": 3, "hp": 1100, "cost": 1600, "time": 15, "pwr": -30, "sight": 5, "req": ["refinery"]},
	"turret": {"name": "Sentry Gun", "w": 1, "h": 1, "hp": 500, "cost": 500, "time": 8, "pwr": -15, "sight": 7, "req": ["barracks"], "weapon": "shell", "dmg": 30, "range": 6.0, "rof": 1.3},
	"repair": {"name": "Repair Bay", "w": 3, "h": 3, "hp": 900, "cost": 900, "time": 11, "pwr": -25, "sight": 4, "req": ["factory"]},
	"wall": {"name": "Barrier ×4", "w": 1, "h": 1, "hp": 450, "cost": 160, "time": 4, "pwr": 0, "sight": 1, "req": ["barracks"], "kit": 4},
	"flak": {"name": "Flak Nest", "w": 1, "h": 1, "hp": 450, "cost": 600, "time": 8, "pwr": -20, "sight": 8, "req": ["barracks"], "weapon": "flak", "dmg": 24, "range": 7.5, "rof": 0.55, "antiAir": true},
	"comms": {"name": "Comms Array", "w": 2, "h": 2, "hp": 700, "cost": 1000, "time": 10, "pwr": -40, "sight": 10, "req": ["refinery"]},
	"helipad": {"name": "Helipad", "w": 2, "h": 2, "hp": 650, "cost": 1100, "time": 11, "pwr": -20, "sight": 5, "req": ["comms"]},
	"tech": {"name": "Tech Lab", "w": 2, "h": 2, "hp": 800, "cost": 1500, "time": 14, "pwr": -60, "sight": 5, "req": ["factory", "comms"]},
	"bastion": {"name": "Bastion Cannon", "fac": "vanguard", "w": 2, "h": 2, "hp": 1250, "cost": 1400, "time": 14, "pwr": -50, "sight": 9, "req": ["tech"], "weapon": "shell", "dmg": 78, "range": 8.5, "rof": 2.4},
	"pylon": {"name": "Arc Pylon", "fac": "ashen", "w": 1, "h": 1, "hp": 700, "cost": 1200, "time": 12, "pwr": -75, "sight": 7, "req": ["tech"], "weapon": "arc", "dmg": 62, "range": 5.5, "rof": 1.9, "needPower": true},
	"skyfall": {"name": "Skyfall Battery", "fac": "vanguard", "w": 3, "h": 3, "hp": 1500, "cost": 3000, "time": 25, "pwr": -100, "sight": 5, "req": ["tech"], "sw": true, "charge": 240.0},
	"rift": {"name": "Rift Engine", "fac": "ashen", "w": 3, "h": 3, "hp": 1500, "cost": 3000, "time": 25, "pwr": -100, "sight": 5, "req": ["tech"], "sw": true, "charge": 240.0},
}

var UN := {
	"rifle": {"name": "Rifleman", "cat": "inf", "cost": 100, "time": 4, "hp": 60, "spd": 1.15, "range": 3.8, "sight": 5, "dmg": 9, "rof": 0.75, "weapon": "bullet", "armor": "inf", "r": 6, "req": ["barracks"]},
	"lancer": {"name": "Lancer", "cat": "inf", "cost": 250, "time": 6, "hp": 55, "spd": 1.0, "range": 5, "sight": 6, "dmg": 34, "rof": 2.2, "weapon": "rocket", "armor": "inf", "r": 6, "req": ["barracks"]},
	"ranger": {"name": "Ranger", "fac": "vanguard", "cat": "inf", "cost": 400, "time": 7, "hp": 55, "spd": 1.1, "range": 7, "sight": 8, "dmg": 48, "rof": 2.3, "weapon": "snipe", "armor": "inf", "r": 6, "req": ["barracks", "comms"]},
	"pyro": {"name": "Pyro", "fac": "ashen", "cat": "inf", "cost": 300, "time": 6, "hp": 85, "spd": 1.05, "range": 2.3, "sight": 5, "dmg": 13, "rof": 0.3, "weapon": "flame", "armor": "inf", "r": 6, "req": ["barracks", "comms"]},
	"raider": {"name": "Raider Bike", "fac": "ashen", "cat": "veh", "cost": 350, "time": 6, "hp": 120, "spd": 4.0, "range": 3.8, "sight": 7, "dmg": 9, "rof": 0.35, "weapon": "bullet", "armor": "light", "r": 9, "req": ["factory"]},
	"scorpion": {"name": "Scorpion Tank", "fac": "ashen", "cat": "veh", "cost": 750, "time": 11, "hp": 350, "spd": 2.2, "range": 4.6, "sight": 6, "dmg": 36, "rof": 1.45, "weapon": "shell", "armor": "heavy", "r": 12, "turret": true, "req": ["factory"]},
	"bulwark": {"name": "Bulwark Tank", "fac": "vanguard", "cat": "veh", "cost": 1600, "time": 18, "hp": 850, "spd": 1.15, "range": 5.2, "sight": 6, "dmg": 58, "rof": 1.5, "weapon": "shell", "armor": "heavy", "r": 15, "turret": true, "req": ["factory", "tech"]},
	"arcc": {"name": "Arc Crawler", "fac": "ashen", "cat": "veh", "cost": 1500, "time": 17, "hp": 520, "spd": 1.5, "range": 4.5, "sight": 6, "dmg": 55, "rof": 1.7, "weapon": "arc", "armor": "heavy", "r": 14, "req": ["factory", "tech"]},
	"skyhawk": {"name": "Skyhawk Gunship", "fac": "vanguard", "cat": "air", "cost": 1300, "time": 14, "hp": 300, "spd": 3.0, "range": 5, "sight": 8, "dmg": 34, "rof": 1.3, "weapon": "rocket", "armor": "light", "r": 14, "air": true, "req": ["helipad"]},
	"wasp": {"name": "Wasp Drone", "fac": "ashen", "cat": "air", "cost": 800, "time": 9, "hp": 160, "spd": 4.4, "range": 3.8, "sight": 7, "dmg": 11, "rof": 0.32, "weapon": "bullet", "armor": "light", "r": 11, "air": true, "req": ["helipad"]},
	"buggy": {"name": "Scout Buggy", "fac": "vanguard", "cat": "veh", "cost": 400, "time": 7, "hp": 150, "spd": 3.2, "range": 4.2, "sight": 7, "dmg": 11, "rof": 0.45, "weapon": "bullet", "armor": "light", "r": 10, "req": ["factory"]},
	"tank": {"name": "Warden Tank", "fac": "vanguard", "cat": "veh", "cost": 800, "time": 12, "hp": 420, "spd": 1.7, "range": 4.8, "sight": 6, "dmg": 42, "rof": 1.7, "weapon": "shell", "armor": "heavy", "r": 12, "turret": true, "req": ["factory"]},
	"medic": {"name": "Field Medic", "cat": "inf", "cost": 150, "time": 5, "hp": 50, "spd": 1.1, "range": 2.2, "sight": 5, "heal": 9, "rof": 0.7, "armor": "inf", "r": 6, "req": ["barracks"]},
	"engineer": {"name": "Engineer", "cat": "inf", "cost": 500, "time": 8, "hp": 45, "spd": 1.05, "sight": 4, "armor": "inf", "r": 6, "eng": true, "req": ["barracks", "factory"]},
	"arty": {"name": "Howler Mortar", "cat": "veh", "cost": 950, "time": 13, "hp": 170, "spd": 1.4, "range": 9, "minr": 2.2, "sight": 6, "dmg": 65, "rof": 3.6, "weapon": "arty", "splash": 46, "armor": "light", "r": 12, "turret": true, "req": ["factory", "repair"]},
	# heroes and mission-only units: never trained, a mission brings them
	"vey": {"name": "Kestrel Vey", "fac": "ashen", "cat": "inf", "cost": 0, "time": 1, "hp": 460, "spd": 1.35, "range": 5.2, "sight": 8, "dmg": 30, "rof": 0.7, "weapon": "arc", "armor": "inf", "r": 7, "hero": true, "req": ["never"]},
	"furnace": {"name": "The Furnace", "fac": "ashen", "cat": "veh", "cost": 0, "time": 1, "hp": 1500, "spd": 1.3, "range": 4.8, "sight": 7, "dmg": 72, "rof": 1.6, "weapon": "arc", "armor": "heavy", "r": 16, "hero": true, "req": ["never"]},
	"harrow": {"name": "Ilse Harrow", "fac": "vanguard", "cat": "inf", "cost": 0, "time": 1, "hp": 420, "spd": 1.3, "range": 7.5, "sight": 9, "dmg": 58, "rof": 1.4, "weapon": "rail", "armor": "inf", "r": 7, "hero": true, "req": ["never"]},
	"saint": {"name": "Iron Saint", "fac": "vanguard", "cat": "veh", "cost": 0, "time": 1, "hp": 1900, "spd": 1.15, "range": 5.6, "sight": 7, "dmg": 72, "rof": 1.3, "weapon": "shell", "armor": "heavy", "r": 17, "turret": true, "hero": true, "req": ["never"]},
	"truck": {"name": "Convoy Truck", "cat": "veh", "cost": 0, "time": 1, "hp": 520, "spd": 1.6, "sight": 5, "armor": "heavy", "r": 13, "req": ["never"]},
	"harv": {"name": "Harvester", "cat": "veh", "cost": 1200, "time": 14, "hp": 650, "spd": 1.35, "sight": 4, "armor": "heavy", "r": 14, "harv": true, "req": ["factory", "refinery"]},
}

const MOD := {
	"snipe": {"inf": 1.6, "light": 0.3, "heavy": 0.1, "bld": 0.05}, "flame": {"inf": 1.4, "light": 0.7, "heavy": 0.35, "bld": 0.9},
	"arc": {"inf": 1.1, "light": 1.05, "heavy": 0.85, "bld": 0.7}, "flak": {"inf": 0.25, "light": 1.2, "heavy": 0.8, "bld": 0.1},
	"sw": {"inf": 1, "light": 1, "heavy": 1, "bld": 1}, "arty": {"inf": 0.9, "light": 0.8, "heavy": 0.6, "bld": 1.1},
	"bullet": {"inf": 1, "light": 0.6, "heavy": 0.22, "bld": 0.25}, "rocket": {"inf": 0.35, "light": 1.1, "heavy": 1.15, "bld": 0.75},
	"shell": {"inf": 0.45, "light": 0.9, "heavy": 1, "bld": 1}, "rail": {"inf": 1.4, "light": 0.9, "heavy": 0.5, "bld": 0.55},
}
const CATS := {
	"bld": ["power", "refinery", "barracks", "factory", "turret", "flak", "wall", "repair", "comms", "helipad", "tech", "bastion", "pylon", "skyfall", "rift"],
	"inf": ["rifle", "lancer", "medic", "engineer", "ranger", "pyro"],
	"veh": ["buggy", "raider", "tank", "scorpion", "arty", "bulwark", "arcc", "harv"],
	"air": ["skyhawk", "wasp"],
}
const CAT_ORDER := ["bld", "inf", "veh", "air"]
const PRODUCER := {"inf": "barracks", "veh": "factory", "air": "helipad"}
const AIRW := ["bullet", "rocket", "flak"]
## Weapons that lob over hills; everything else needs a clear line of fire.
const INDIRECT := ["arty"]
const FACS := {
	"vanguard": {"name": "Vanguard", "lv": "buggy", "mt": "tank", "ht": "bulwark", "air": "skyhawk", "inf": "ranger", "def": "bastion", "sw": "skyfall"},
	"ashen": {"name": "Ashen Pact", "lv": "raider", "mt": "scorpion", "ht": "arcc", "air": "wasp", "inf": "pyro", "def": "pylon", "sw": "rift"},
}
const DIFF := {
	"easy": {"prod": 0.7, "inc": 0.8, "first": 330, "start": 3000},
	"normal": {"prod": 1.0, "inc": 1.0, "first": 210, "start": 3000},
	"hard": {"prod": 1.3, "inc": 1.35, "first": 140, "start": 4000},
}
## Colours follow the faction: the Vanguard is blue, the Ashen Pact red. TEAMC and MINI_COL are
## indexed by team and set for each match by set_team_colors().
const FCOL := {
	"vanguard": {"col": Color("#3fb4e8"), "dk": Color("#174a63"), "lt": Color("#a6e3ff"), "mini": Color("#5cc8ff")},
	"ashen": {"col": Color("#e0423a"), "dk": Color("#5e1512"), "lt": Color("#ffb0a8"), "mini": Color("#ff5a4f")},
}
var TEAMC: Array = [FCOL.vanguard, FCOL.ashen]
var MINI_COL: Array = [FCOL.vanguard.mini, FCOL.ashen.mini]

## Returns true when the colours changed (cached models must be rebuilt).
func set_team_colors(f0: String, f1: String) -> bool:
	if TEAMC[0] == FCOL[f0] and TEAMC[1] == FCOL[f1]: return false
	TEAMC = [FCOL[f0], FCOL[f1]]; MINI_COL = [FCOL[f0].mini, FCOL[f1].mini]
	return true
const TCOL := [Color8(74, 98, 50), Color8(112, 94, 64), Color8(158, 140, 98), Color8(98, 92, 86), Color8(34, 76, 98)]
## Landscapes. Colours are sRGB 0..1. grass = base + noise * var. trees: "pine" (two cones), "snowpine" (pine with a white cap),
## "broad" (round crowns), "dead" (bare trunks), "palm"-less on purpose: the valley has none.
const THEMES := {
	"temperate": {"name": "Green river country", "grass": [0.30, 0.42, 0.20], "gvar": [0.12, 0.10, 0.04], "dirt": [0.50, 0.40, 0.27], "sand": [0.68, 0.60, 0.42], "rock": [0.40, 0.37, 0.33],
		"cliff": [0.44, 0.41, 0.37], "bed": [0.22, 0.30, 0.30], "trees": "pine", "tcol": ["3f6b2c", "4f7d33", "355e2a", "6b8a3a"], "trunk": "5a4130", "bush": "4f7a34", "stone": "8a8174",
		"tden": 0.075, "bden": 0.085, "water": [0.227, 0.525, 0.659, 0.84], "sun": "fff0d8", "sunE": 1.05, "amb": "aeb6be", "ambE": 0.75},
	"autumn": {"name": "Autumn foundry country", "grass": [0.42, 0.38, 0.18], "gvar": [0.14, 0.08, 0.03], "dirt": [0.50, 0.38, 0.25], "sand": [0.66, 0.57, 0.40], "rock": [0.42, 0.38, 0.34],
		"cliff": [0.45, 0.40, 0.35], "bed": [0.22, 0.27, 0.26], "trees": "broad", "tcol": ["b4562a", "d08a2e", "8f3e22", "c7a03a"], "trunk": "4a3428", "bush": "8a6a2c", "stone": "857a6c",
		"tden": 0.09, "bden": 0.08, "water": [0.25, 0.45, 0.50, 0.86], "sun": "ffe2b8", "sunE": 1.0, "amb": "b8aa9c", "ambE": 0.75},
	"arid": {"name": "Dust flats", "grass": [0.62, 0.52, 0.32], "gvar": [0.10, 0.08, 0.05], "dirt": [0.58, 0.42, 0.26], "sand": [0.76, 0.66, 0.45], "rock": [0.56, 0.42, 0.30],
		"cliff": [0.60, 0.44, 0.30], "bed": [0.36, 0.32, 0.24], "trees": "dead", "tcol": ["7a6a3a", "8a7a44", "6a5a32", "9a8a52"], "trunk": "5e4a36", "bush": "8c8550", "stone": "a08060",
		"tden": 0.018, "bden": 0.05, "water": [0.36, 0.48, 0.44, 0.86], "sun": "fff2d0", "sunE": 1.12, "amb": "c4b8a4", "ambE": 0.78},
	"snow": {"name": "Ironpine snowfields", "grass": [0.80, 0.83, 0.86], "gvar": [0.08, 0.07, 0.05], "dirt": [0.58, 0.56, 0.54], "sand": [0.70, 0.72, 0.74], "rock": [0.42, 0.43, 0.46],
		"cliff": [0.48, 0.49, 0.52], "bed": [0.24, 0.32, 0.38], "trees": "snowpine", "tcol": ["24452f", "2c5236", "1f3d2a", "35603e"], "trunk": "4a3a30", "bush": "c6ccd0", "stone": "7c8088",
		"tden": 0.085, "bden": 0.05, "water": [0.42, 0.60, 0.70, 0.90], "sun": "e8f0ff", "sunE": 0.95, "amb": "b0bccc", "ambE": 0.72},
	"ash": {"name": "Cinder hills", "grass": [0.26, 0.24, 0.22], "gvar": [0.08, 0.06, 0.05], "dirt": [0.36, 0.29, 0.24], "sand": [0.46, 0.40, 0.34], "rock": [0.24, 0.22, 0.21],
		"cliff": [0.30, 0.27, 0.25], "bed": [0.30, 0.12, 0.06], "trees": "dead", "tcol": ["2a2420", "322a24", "241e1a", "3a3028"], "trunk": "2a2420", "bush": "4a3e30", "stone": "4a4440",
		"tden": 0.05, "bden": 0.04, "water": [0.85, 0.32, 0.10, 0.92], "lava": true, "sun": "ffc8a0", "sunE": 0.95, "amb": "a89c98", "ambE": 0.72},
	"marsh": {"name": "Reedmarsh", "grass": [0.24, 0.34, 0.20], "gvar": [0.08, 0.10, 0.05], "dirt": [0.36, 0.33, 0.22], "sand": [0.48, 0.46, 0.32], "rock": [0.34, 0.34, 0.30],
		"cliff": [0.38, 0.38, 0.33], "bed": [0.16, 0.22, 0.18], "trees": "broad", "tcol": ["2f4a26", "3a5a2c", "28401f", "4a5e30"], "trunk": "3e3226", "bush": "6a7a3a", "stone": "6e6c60",
		"tden": 0.05, "bden": 0.16, "water": [0.20, 0.36, 0.34, 0.86], "sun": "f2ecd0", "sunE": 0.95, "amb": "a8b0a4", "ambE": 0.74},
}
## Dusk light for some missions: low warm sun, cooler shadows.
const DUSK := {"sun": "ffa868", "sunE": 0.85, "amb": "8890a8", "ambE": 0.62}

## Minimap colours for a landscape: grass, dirt, sand, rock, water.
var _tcol := {}
func tcol(theme: String) -> Array:
	if not _tcol.has(theme):
		var TH: Dictionary = THEMES[theme]
		var c := func(a: Array) -> Color: return Color(a[0], a[1], a[2])
		_tcol[theme] = [c.call(TH.grass), c.call(TH.dirt), c.call(TH.sand), c.call(TH.rock), c.call(TH.water)]
	return _tcol[theme]

const BH := {"hq": 1.55, "power": 1.25, "refinery": 1.3, "barracks": 0.95, "factory": 1.2, "turret": 0.7, "repair": 1.0, "wall": 0.6, "flak": 0.8, "comms": 2.2, "helipad": 0.5, "tech": 1.3, "bastion": 1.2, "pylon": 1.9, "skyfall": 1.0, "rift": 2.2}
const UH := {"rifle": 0.5, "lancer": 0.55, "medic": 0.5, "engineer": 0.5, "ranger": 0.5, "pyro": 0.55, "buggy": 0.42, "raider": 0.45, "tank": 0.48, "scorpion": 0.4, "bulwark": 0.6, "arcc": 0.85, "arty": 0.55, "harv": 0.58, "skyhawk": 0.4, "wasp": 0.25, "vey": 0.62, "harrow": 0.62, "furnace": 0.95, "saint": 0.8, "truck": 0.6}

const ALLB := ["power", "refinery", "barracks", "factory", "turret", "flak", "wall", "repair", "comms", "helipad", "tech", "bastion", "pylon", "skyfall", "rift"]
const AI_ORDER := ["power", "refinery", "barracks", "power", "factory", "turret", "power", "refinery", "flak", "comms", "repair", "power", "DEF", "turret", "helipad", "power", "tech", "DEF", "power", "flak", "SW", "power", "DEF", "turret", "power"]

var CAMPAIGNS: Array = []

func _init() -> void:
	for k in BLD:
		var d: Dictionary = BLD[k]
		d.type = k
		for kv in [["fac", ""], ["weapon", ""], ["dmg", 0], ["range", 0.0], ["rof", 1.0], ["antiAir", false], ["needPower", false], ["sw", false], ["charge", 0.0], ["kit", 0], ["splash", 0.0], ["minr", 0.0], ["air", false], ["heal", 0], ["eng", false], ["harv", false], ["turret", false], ["armor", "bld"]]:
			if not d.has(kv[0]): d[kv[0]] = kv[1]
	for k in UN:
		var d: Dictionary = UN[k]
		d.type = k
		for kv in [["fac", ""], ["weapon", ""], ["dmg", 0], ["range", 0.0], ["rof", 1.0], ["air", false], ["turret", false], ["heal", 0], ["eng", false], ["harv", false], ["minr", 0.0], ["splash", 0.0], ["antiAir", false], ["hero", false]]:
			if not d.has(kv[0]): d[kv[0]] = kv[1]
	CAMPAIGNS = Campaign.all()
	for c in CAMPAIGNS:
		for i in c.missions.size():
			var m: Dictionary = c.missions[i]
			m.idx = i; m.camp = c.id; m.fac = c.fac
			for kv in [["aiBuild", true], ["aiProd", true], ["aiFirst", -1], ["waves", null], ["swCh", 0.0], ["tech", null], ["aiTech", null], ["phq", true],
					["pbase", []], ["punits", []], ["pheroes", []], ["ehq", "hq"], ["ebase", []], ["eunits", []], ["eheroes", []], ["posts", []], ["captives", []],
					["events", []], ["keep", []], ["limit", 0.0], ["credits", [3000, 3000]], ["diff", "normal"], ["heroes", []], ["theatre", ""], ["pvip", []]]:
				if not m.has(kv[0]): m[kv[0]] = kv[1]
			for g in m.goals:
				for kv in [["waves", null], ["done", null], ["label", ""], ["r", 2.5], ["who", "any"], ["need", 1], ["t", 0.0], ["types", []], ["tag", ""], ["protect", []], ["zone", null], ["zones", []], ["at", null], ["n", 0]]:
					if not g.has(kv[0]): g[kv[0]] = kv[1]

func camp(id: String) -> Dictionary:
	for c in CAMPAIGNS:
		if c.id == id: return c
	return CAMPAIGNS[0]

func def_of(t: String) -> Dictionary:
	return BLD[t] if BLD.has(t) else UN[t]

static func fmt(t: float) -> String:
	var s := int(ceil(max(0.0, t)))
	return "%d:%02d" % [s / 60, s % 60]
