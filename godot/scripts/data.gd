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
	"harv": {"name": "Harvester", "cat": "veh", "cost": 1200, "time": 14, "hp": 650, "spd": 1.35, "sight": 4, "armor": "heavy", "r": 14, "harv": true, "req": ["factory", "refinery"]},
}

const MOD := {
	"snipe": {"inf": 1.6, "light": 0.3, "heavy": 0.1, "bld": 0.05}, "flame": {"inf": 1.4, "light": 0.7, "heavy": 0.35, "bld": 0.9},
	"arc": {"inf": 1.1, "light": 1.05, "heavy": 0.85, "bld": 0.7}, "flak": {"inf": 0.25, "light": 1.2, "heavy": 0.8, "bld": 0.1},
	"sw": {"inf": 1, "light": 1, "heavy": 1, "bld": 1}, "arty": {"inf": 0.9, "light": 0.8, "heavy": 0.6, "bld": 1.1},
	"bullet": {"inf": 1, "light": 0.6, "heavy": 0.22, "bld": 0.25}, "rocket": {"inf": 0.35, "light": 1.1, "heavy": 1.15, "bld": 0.75},
	"shell": {"inf": 0.45, "light": 0.9, "heavy": 1, "bld": 1},
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
## Team 0 (the player) is blue, team 1 (the AI) is red.
var TEAMC := [
	{"col": Color("#3fb4e8"), "dk": Color("#174a63"), "lt": Color("#a6e3ff")},
	{"col": Color("#e0423a"), "dk": Color("#5e1512"), "lt": Color("#ffb0a8")},
]
const MINI_COL := [Color("#5cc8ff"), Color("#ff5a4f")]
const TCOL := [Color8(74, 98, 50), Color8(112, 94, 64), Color8(158, 140, 98), Color8(98, 92, 86), Color8(34, 76, 98)]
const BH := {"hq": 1.55, "power": 1.25, "refinery": 1.3, "barracks": 0.95, "factory": 1.2, "turret": 0.7, "repair": 1.0, "wall": 0.6, "flak": 0.8, "comms": 2.2, "helipad": 0.5, "tech": 1.3, "bastion": 1.2, "pylon": 1.9, "skyfall": 1.0, "rift": 2.2}
const UH := {"rifle": 0.5, "lancer": 0.55, "medic": 0.5, "engineer": 0.5, "ranger": 0.5, "pyro": 0.55, "buggy": 0.42, "raider": 0.45, "tank": 0.48, "scorpion": 0.4, "bulwark": 0.6, "arcc": 0.85, "arty": 0.55, "harv": 0.58, "skyhawk": 0.4, "wasp": 0.25}

const ALLB := ["power", "refinery", "barracks", "factory", "turret", "flak", "wall", "repair", "comms", "helipad", "tech", "bastion", "pylon", "skyfall", "rift"]
const AI_ORDER := ["power", "refinery", "barracks", "power", "factory", "turret", "power", "refinery", "flak", "comms", "repair", "power", "DEF", "turret", "helipad", "power", "tech", "DEF", "power", "flak", "SW", "power", "DEF", "turret", "power"]

var MISSIONS: Array = []

func _init() -> void:
	for k in BLD:
		var d: Dictionary = BLD[k]
		d.type = k
		for kv in [["fac", ""], ["weapon", ""], ["dmg", 0], ["range", 0.0], ["rof", 1.0], ["antiAir", false], ["needPower", false], ["sw", false], ["charge", 0.0], ["kit", 0], ["splash", 0.0], ["minr", 0.0], ["air", false], ["heal", 0], ["eng", false], ["harv", false], ["turret", false], ["armor", "bld"]]:
			if not d.has(kv[0]): d[kv[0]] = kv[1]
	for k in UN:
		var d: Dictionary = UN[k]
		d.type = k
		for kv in [["fac", ""], ["weapon", ""], ["dmg", 0], ["range", 0.0], ["rof", 1.0], ["air", false], ["turret", false], ["heal", 0], ["eng", false], ["harv", false], ["minr", 0.0], ["splash", 0.0], ["antiAir", false]]:
			if not d.has(kv[0]): d[kv[0]] = kv[1]
	var m4tech: Array = []
	for t in ALLB:
		if t != "skyfall" and t != "rift": m4tech.append(t)
	m4tech.append_array(["rifle", "lancer", "medic", "engineer", "ranger", "buggy", "tank", "arty", "bulwark", "harv", "skyhawk"])
	MISSIONS = [
		{"title": "Landfall", "tag": "Take the river crossing", "seed": 4242, "diff": "easy", "credits": [1800, 600],
		 "brief": "Our landing barges made it across the Sable river at dawn. An Ashen Pact outpost watches the crossing from the north-east. Set up a foothold, train a strike team and wipe the outpost out before their main army notices.",
		 "obj": ["Destroy every Ashen Pact unit and structure", "New: Field Medics keep your infantry alive"],
		 "tech": ["power", "refinery", "barracks", "turret", "wall", "rifle", "lancer", "medic", "harv"], "aiTech": ["rifle", "lancer", "power"], "aiBuild": false, "aiFirst": 260,
		 "pbase": [], "punits": [["rifle", 5], ["lancer", 2], ["medic", 1]],
		 "ehq": "barracks", "ebase": ["power", "turret", "turret", "turret"], "eunits": [["rifle", 6], ["lancer", 3]], "goal": "destroy_all"},
		{"title": "Gold Rush", "tag": "Fund the war effort", "seed": 777, "diff": "normal", "credits": [2500, 1500],
		 "brief": "Command needs aurite, and fast. The valley floor is thick with it, but Ashen raiders on bikes will hit any harvester they can find. Build refineries, protect your harvesters and deliver 5,000 aurite before the window closes.",
		 "obj": ["Deliver 5,000 aurite within 12 minutes", "Keep your Command Yard standing", "New: War Factory, Scout Buggies, Sentry Guns"],
		 "tech": ["power", "refinery", "barracks", "factory", "turret", "wall", "rifle", "lancer", "medic", "buggy", "harv"], "aiTech": ["power", "turret", "rifle", "lancer", "raider", "harv"], "aiFirst": 150,
		 "pbase": ["power"], "punits": [["rifle", 4], ["buggy", 1]],
		 "ehq": "hq", "ebase": ["power", "power", "refinery", "barracks", "factory", "turret", "turret"], "eunits": [["rifle", 3], ["raider", 2]], "goal": "mine"},
		{"title": "Hold the Ford", "tag": "Survive the counterattack", "seed": 1337, "diff": "normal", "credits": [5000, 0],
		 "brief": "The Ashen Pact wants the ford back. Our engineers say reinforcements are nine minutes out. Dig in with Warden Tanks, Howler mortars and Flak Nests, because scouts report drones in their later waves.",
		 "obj": ["Survive for 9 minutes", "New: Warden Tanks, Howler Mortars, Repair Bay, Flak Nest, Engineers"],
		 "tech": ["power", "refinery", "barracks", "factory", "turret", "flak", "wall", "repair", "rifle", "lancer", "medic", "engineer", "buggy", "tank", "arty", "harv"], "aiBuild": false, "aiProd": false,
		 "waves": {"first": 50, "every": 55},
		 "pbase": ["power", "power", "refinery", "barracks", "factory"], "punits": [["tank", 2], ["rifle", 4], ["lancer", 2]],
		 "ehq": "hq", "ebase": ["power", "power", "refinery", "barracks", "factory", "helipad", "turret", "turret", "pylon"], "eunits": [], "goal": "survive"},
		{"title": "Broken Wing", "tag": "Ground their air wing", "seed": 9001, "diff": "normal", "credits": [6000, 5000],
		 "brief": "Wasp drones are tearing up our supply lines. They fly from a helipad deep in the Ashen base, guided by a Comms Array. Knock out both. Our own Skyhawk gunships are cleared for this one, and Rangers can pick off their infantry from long range.",
		 "obj": ["Destroy every enemy Helipad", "Destroy every enemy Comms Array", "New: Comms Array, Helipad, Skyhawk gunships, Rangers, Tech Lab, Bulwark Tanks"],
		 "tech": m4tech,
		 "aiTech": ["power", "refinery", "barracks", "factory", "turret", "flak", "repair", "pylon", "rifle", "lancer", "medic", "pyro", "raider", "scorpion", "arty", "harv", "wasp"], "aiFirst": 200,
		 "pbase": ["power", "power", "refinery", "barracks", "factory", "comms"], "punits": [["tank", 2], ["lancer", 3], ["rifle", 3]],
		 "ehq": "hq", "ebase": ["power", "power", "power", "refinery", "barracks", "factory", "comms", "helipad", "flak", "flak", "flak", "turret", "turret"], "eunits": [["wasp", 3], ["scorpion", 2], ["rifle", 4]], "goal": "air"},
		{"title": "Ashfall", "tag": "End the war", "seed": 31337, "diff": "hard", "credits": [9000, 9000],
		 "brief": "This is it. The Ashen Pact has finished a Rift Engine at their capital and it is already charging. Every system we have is unlocked, including our own Skyfall Battery. Break their base before the Rift Engine flattens yours.",
		 "obj": ["Destroy all Ashen Pact forces", "Watch the Rift Engine timer: it hits your biggest cluster of buildings", "New: Bastion Cannon, Skyfall Battery"],
		 "tech": null, "aiTech": null, "aiFirst": 160,
		 "pbase": ["power", "power", "power", "refinery", "barracks", "factory", "comms", "repair"], "punits": [["tank", 3], ["bulwark", 1], ["lancer", 4], ["ranger", 2], ["medic", 2]],
		 "ehq": "hq", "ebase": ["power", "power", "power", "power", "refinery", "refinery", "barracks", "factory", "comms", "helipad", "tech", "flak", "flak", "pylon", "pylon", "turret", "rift"], "eunits": [["scorpion", 3], ["arcc", 1], ["pyro", 3], ["wasp", 2], ["rifle", 4]], "goal": "rift", "riftCh": 60.0},
	]
	for i in MISSIONS.size():
		MISSIONS[i].idx = i
		for kv in [["aiBuild", true], ["aiProd", true], ["aiFirst", -1], ["waves", null], ["riftCh", 0.0]]:
			if not MISSIONS[i].has(kv[0]): MISSIONS[i][kv[0]] = kv[1]

func def_of(t: String) -> Dictionary:
	return BLD[t] if BLD.has(t) else UN[t]

## Wave composition for "Hold the Ford", wave number n.
func wave_list(n: int) -> Array:
	return [["rifle", 3 + n], ["lancer", 1 + (n >> 1)], ["raider", 2 if n > 1 else 0], ["scorpion", n - 2 if n > 2 else 0], ["arty", 1 if n > 4 else 0], ["wasp", 2 if n > 5 else 0], ["pyro", 2 if n > 3 else 0]]

static func fmt(t: float) -> String:
	var s := int(ceil(max(0.0, t)))
	return "%d:%02d" % [s / 60, s % 60]
