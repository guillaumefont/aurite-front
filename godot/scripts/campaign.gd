class_name Campaign
extends RefCounted
## The three campaigns. Campaign I is played as the Ashen Pact (red), campaign II, a year later, as the Vanguard (blue).
## Campaign III is the Hollow Choir (green) during the Iron Tide war. It is a side story, open from the start ("free"),
## and its missions name their enemy army ("efac": the Vanguard or the Pact).
##
## Map coordinates are tiles on the 64×64 grid: x grows east, y grows south. A mission's map is drawn by MapGen
## from the primitives in "map" (rivers, lakes, ridges, mesas, gaps, roads, ore fields, sea) on top of noise.
## Goals run one after the other; see Sim.goal_tick() for every kind:
##   destroy_all · kill (types or tag) · mine (n, t limit) · survive (t) · reach (at, who) · hold (zones, t)
##   escort (at, need: units tagged "vip" walk off there) · rescue (free every captive) · capture (tag, with engineers)
## A goal's "done" can give a base, credits, tech, units, and say something. "keep": lose if the player has none of
## these types left (heroes, the Command Yard). Posts are enemy positions that hold their ground.

const ASH_EARLY := ["power", "refinery", "barracks", "turret", "wall", "rifle", "lancer", "medic", "pyro", "harv"]
const VAN_EARLY := ["power", "refinery", "barracks", "turret", "wall", "rifle", "lancer", "medic", "ranger", "harv"]
const CHO_EARLY := ["power", "garden", "barracks", "burrow", "turret", "wall", "thrall", "lancer", "medic"]

static func all() -> Array:
	return [
		{"id": "ashen", "fac": "ashen", "num": "I", "name": "Embers of the Pact",
		 "tag": "Play the Ashen Pact. The Vanguard lands in the Sable valley and the foundry towns rise.", "missions": ashen()},
		{"id": "vanguard", "fac": "vanguard", "num": "II", "name": "Iron Tide",
		 "tag": "The sequel. A year after Embers, the Directorate returns to break the Pact and its new Rift Engines. Play the Vanguard.", "missions": vanguard()},
		{"id": "choir", "fac": "choir", "num": "III", "name": "The Hollow Song", "free": true,
		 "tag": "Play the Hollow Choir. While the Iron Tide breaks over the valley, the miners who stayed below wake up and sing.", "missions": choir()},
	]

static func _plus(a: Array, b: Array) -> Array:
	var r := a.duplicate()
	for x in b:
		if not r.has(x): r.append(x)
	return r

# =====================================================================================
# Campaign I: Embers of the Pact (Ashen Pact)
# =====================================================================================
static func ashen() -> Array:
	var t2 := _plus(ASH_EARLY, ["factory", "raider", "engineer"])
	var t3 := _plus(t2, ["scorpion", "flak", "repair", "arty", "comms"])
	var t4 := _plus(t3, ["helipad", "wasp", "tech", "pylon", "arcc"])
	var van_ai := ["power", "refinery", "barracks", "factory", "turret", "rifle", "lancer", "medic", "buggy", "tank", "harv"]
	var van_ai2 := _plus(van_ai, ["flak", "repair", "arty", "comms", "ranger", "helipad", "skyhawk"])
	return [
		# ---- 1: no base, the hero reaches a hilltop and holds it
		{"title": "Smoke on the River", "tag": "Light the warning fire", "seed": 1101, "diff": "easy", "credits": [0, 0],
		 "theatre": "Hollin's Rise, above the Sable river · dawn",
		 "brief": "Vanguard landing barges are on the Sable at first light, and the foundry towns are still asleep. Kestrel Vey, take your cell up Hollin's Rise and light the old signal fire. Then hold the hill until the town militia reaches you.",
		 "obj": ["Bring Kestrel Vey to the signal tower on Hollin's Rise", "Hold the rise for 2:30", "Kestrel Vey must survive", "New: heroes heal themselves when out of the fight"],
		 "heroes": ["vey"],
		 "map": {"theme": "temperate", "p0": [8, 55], "e0": null, "rock": 0.72,
			"rivers": [{"pts": [[48, 0], [45, 14], [50, 30], [46, 46], [51, 63]], "w": 1.8}], "gaps": [[47, 22, 2], [48, 40, 2]],
			"mesas": [[24, 32, 3], [38, 40, 3], [16, 18, 3], [30, 10, 2.5]], "roads": [[[8, 55], [16, 44], [25, 28], [33, 19]]],
			"ore": [[14, 44, 2.6], [40, 26, 2.4]]},
		 "phq": false, "tech": [], "aiTech": [], "aiBuild": false, "aiProd": false, "ehq": "",
		 "pheroes": ["vey"], "punits": [["rifle", 4], ["pyro", 2], ["medic", 1]], "keep": ["vey"],
		 "posts": [{"at": [22, 38], "u": [["rifle", 3]]}, {"at": [35, 21], "u": [["rifle", 2], ["lancer", 1]]}, {"at": [42, 30], "u": [["buggy", 1], ["rifle", 2]]}],
		 "goals": [
			{"k": "reach", "at": [33, 18], "r": 2.5, "who": "hero", "label": "signal tower",
			 "done": {"say": "The warning fire is lit. Every town in the valley can see it. Hold the rise!"}},
			{"k": "survive", "t": 150, "label": "Hold Hollin's Rise", "zone": [33, 18],
			 "waves": {"first": 8, "every": 32, "n": 5, "from": [[60, 14], [60, 34]], "to": [33, 18],
				"list": [["rifle", 2, 1, 1], ["buggy", 1, 0.5, 2], ["lancer", 0, 1, 3]]},
			 "done": {"say": "Militia on the road! The Pact is awake."}},
		 ]},
		# ---- 2: first base, wipe out the bridgehead
		{"title": "Kettleford", "tag": "Throw back the bridgehead", "seed": 1202, "diff": "easy", "credits": [4000, 1500],
		 "theatre": "Kettleford foundry town · autumn",
		 "brief": "The Vanguard has a bridgehead on our side of the river, right above Kettleford's foundries. The town council has handed you its yards. Build up, train a strike force and drive them back into the water.",
		 "obj": ["Destroy every Vanguard unit and structure", "Keep your Command Yard standing", "New: base building, Raider Bikes, War Factory"],
		 "map": {"theme": "autumn", "p0": [10, 52], "e0": [52, 12], "rock": 0.73,
			"rivers": [{"pts": [[0, 24], [16, 28], [30, 31], [44, 30], [63, 40]], "w": 1.7}], "gaps": [[14, 28, 2], [38, 31, 2], [56, 36, 2]],
			"ore": [[18, 46, 3.2], [7, 38, 3], [28, 42, 3], [44, 20, 3], [33, 12, 3], [55, 26, 2.6]], "roads": [[[10, 52], [14, 28], [30, 18], [52, 12]]]},
		 "tech": _plus(t2, []), "aiTech": ["power", "refinery", "barracks", "factory", "turret", "rifle", "lancer", "medic", "buggy", "harv"], "aiBuild": false, "aiFirst": 420,
		 "pbase": ["power", "power", "barracks", "refinery"], "punits": [["rifle", 7], ["lancer", 3], ["raider", 3]], "keep": ["hq"],
		 "ehq": "barracks", "ebase": ["power", "power", "refinery", "factory", "turret", "turret"], "eunits": [["rifle", 4], ["lancer", 1], ["buggy", 1]],
		 "posts": [{"at": [40, 26], "b": ["turret"], "u": [["rifle", 2]]}, {"at": [18, 24], "u": [["rifle", 3]]}],
		 "goals": [{"k": "destroy_all", "label": "Vanguard bridgehead"}]},
		# ---- 3: economy race against raiders
		{"title": "Dust and Ore", "tag": "Fill the foundries", "seed": 1303, "diff": "normal", "credits": [3000, 1500],
		 "theatre": "The Dust Flats, south of the valley · dry season",
		 "brief": "Every foundry in the Pact is cold for lack of aurite. The Dust Flats are thick with it, but Vanguard buggies hunt anything that moves out there. Build refineries, guard your harvesters and ship 10,000 aurite before the supply trains leave.",
		 "obj": ["Deliver 10,000 aurite within 13 minutes", "Keep your Command Yard standing", "New: Scorpion Tanks, Flak Nests, Repair Bay, Howler Mortars"],
		 "map": {"theme": "arid", "p0": [9, 54], "e0": [54, 9], "rock": 0.8, "dirt": 0.55,
			"mesas": [[20, 20, 4], [32, 32, 4.5], [44, 44, 4], [14, 34, 3], [40, 15, 3], [27, 50, 3], [50, 28, 3]],
			"ore": [[18, 48, 3.4], [7, 41, 3], [26, 40, 3.2], [38, 53, 3], [22, 27, 3], [42, 36, 3.4], [31, 13, 3], [51, 20, 3]]},
		 "tech": t3, "aiTech": van_ai, "aiFirst": 230,
		 "pbase": ["power", "refinery"], "punits": [["rifle", 4], ["raider", 2], ["scorpion", 1]], "keep": ["hq"],
		 "ehq": "hq", "ebase": ["power", "power", "refinery", "barracks", "factory", "turret", "turret"], "eunits": [["rifle", 3], ["buggy", 2]],
		 "events": [
			{"t": 120, "say": "Buggies on the flats, heading for your harvesters", "spawn": [{"at": [62, 34], "u": [["buggy", 3]], "go": "harv"}]},
			{"t": 330, "say": "Another raid on the harvesters", "spawn": [{"at": [36, 2], "u": [["buggy", 3], ["tank", 1]], "go": "harv"}]},
			{"t": 540, "say": "Vanguard armor rolling for the refineries", "spawn": [{"at": [62, 50], "u": [["tank", 2], ["buggy", 2]], "go": "harv"}]}],
		 "goals": [{"k": "mine", "n": 10000, "t": 780, "label": "aurite shipped"}]},
		# ---- 4: escort a refugee convoy through an ambush
		{"title": "Refugee Road", "tag": "Get the convoy through", "seed": 1404, "diff": "normal", "credits": [0, 0],
		 "theatre": "The Ironpine road · first snow",
		 "brief": "Kettleford is burning behind us and its families are on the road east, packed into three foundry trucks. The road runs between two ridges and the Vanguard knows it. Clear the ambushes and get at least two trucks to the Ironpine gate.",
		 "obj": ["Get 2 of the 3 Convoy Trucks to the Ironpine gate (east)", "Kestrel Vey must survive", "Trucks move only when you order them"],
		 "heroes": ["vey"],
		 "map": {"theme": "snow", "p0": [5, 32], "e0": null, "rock": 0.74,
			"ridges": [{"pts": [[0, 22], [14, 20], [28, 25], [42, 20], [63, 23]], "w": 2.4}, {"pts": [[0, 43], [16, 45], [30, 39], [46, 45], [63, 41]], "w": 2.4}],
			"gaps": [[28, 25, 2], [34, 40, 1.6]], "lakes": [[20, 10, 4], [44, 54, 4], [54, 10, 3]],
			"roads": [[[5, 32], [18, 33], [30, 30], [42, 33], [52, 29], [61, 31]]], "ore": [[12, 12, 2.4], [50, 54, 2.4]]},
		 "phq": false, "tech": [], "aiTech": [], "aiBuild": false, "aiProd": false, "ehq": "",
		 "pheroes": ["vey"], "punits": [["raider", 3], ["rifle", 4], ["lancer", 3], ["medic", 1]], "pvip": [["truck", 3]], "keep": ["vey"],
		 "posts": [{"at": [22, 29], "u": [["rifle", 3], ["lancer", 1]]}, {"at": [36, 35], "b": ["turret"], "u": [["rifle", 2], ["tank", 1]]},
			{"at": [48, 29], "b": ["turret", "turret"], "u": [["lancer", 2], ["rifle", 3]]}, {"at": [56, 34], "u": [["tank", 1], ["rifle", 2]]}],
		 "events": [
			{"t": 100, "say": "Buggies coming through the north pass, going for the trucks", "spawn": [{"at": [28, 8], "u": [["buggy", 2], ["rifle", 3]], "go": "vip"}]},
			{"t": 240, "say": "Vanguard tanks from the south", "spawn": [{"at": [36, 58], "u": [["tank", 2], ["rifle", 2]], "go": "vip"}]}],
		 "goals": [{"k": "escort", "at": [61, 31], "r": 3, "need": 2, "label": "Ironpine gate"}]},
		# ---- 5: hold a mountain pass
		{"title": "Ironpine Pass", "tag": "Hold the pass", "seed": 1505, "diff": "normal", "credits": [6000, 0],
		 "theatre": "Ironpine Pass · deep winter",
		 "brief": "The refugees are behind the Ironpine wall, and the Vanguard wants through before the snow closes the pass. Our sappers will bring the cliffs down in ten minutes. Until then, nothing gets past. Watch the sky: the Directorate flies gunships now.",
		 "obj": ["Hold out for 10 minutes", "Keep your Command Yard standing", "New: Engineers, Comms Array, Pyros from the barracks"],
		 "map": {"theme": "snow", "p0": [32, 54], "e0": [32, 7], "rock": 0.75,
			"ridges": [{"pts": [[0, 27], [18, 29], [27, 31]], "w": 2.6}, {"pts": [[37, 31], [46, 29], [63, 27]], "w": 2.6}],
			"gaps": [[9, 28, 1.6]], "lakes": [[52, 46, 3.5], [12, 46, 3]],
			"ore": [[22, 48, 3.4], [42, 48, 3.4], [32, 40, 3], [24, 14, 3], [40, 14, 3]]},
		 "tech": t3, "aiTech": [], "aiBuild": false, "aiProd": false,
		 "pbase": ["power", "power", "refinery", "barracks", "factory"], "punits": [["scorpion", 2], ["rifle", 4], ["lancer", 3], ["pyro", 2]], "keep": ["hq"],
		 "ehq": "hq", "ebase": ["power", "power", "refinery", "barracks", "factory", "helipad", "turret", "turret", "bastion"],
		 "goals": [{"k": "survive", "t": 600, "label": "Hold the pass",
			"waves": {"first": 45, "every": 55, "n": 11, "from": [[20, 4], [44, 4], [32, 3]],
				"list": [["rifle", 3, 1, 1], ["lancer", 1, 0.5, 1], ["buggy", 2, 0, 2], ["tank", 0, 1, 3], ["ranger", 2, 0, 4], ["arty", 1, 0, 5], ["skyhawk", 2, 0, 6], ["bulwark", 1, 0, 8]]}}]},
		# ---- 6: capture with engineers, then keep it
		{"title": "Silent Wires", "tag": "Steal their codes", "seed": 1606, "diff": "normal", "credits": [6000, 4000],
		 "theatre": "The Reedmarsh · fog season",
		 "brief": "The Vanguard talks to its whole army through one Comms Array out in the Reedmarsh. Take it intact with Engineers and we hear every order they give. Old Brann has rolled The Furnace out of the foundry to help: point it at anything that guards the array, but do not burn the array itself.",
		 "obj": ["Capture the Vanguard Comms Array with an Engineer (do not destroy it)", "Then hold it for 2 minutes", "Kestrel Vey must survive", "New hero: The Furnace, Old Brann's arc tank"],
		 "heroes": ["vey", "furnace"],
		 "map": {"theme": "marsh", "p0": [8, 54], "e0": [55, 9], "rock": 0.78,
			"lakes": [[20, 20, 4], [30, 41, 4.5], [44, 32, 3.6], [13, 32, 3], [50, 49, 4], [36, 12, 3], [23, 55, 2.6], [58, 30, 2.6]],
			"rivers": [{"pts": [[0, 45], [18, 43], [26, 36]], "w": 1.1}], "gaps": [[10, 44, 1.5]],
			"ore": [[16, 48, 3.2], [6, 40, 2.8], [28, 28, 3], [40, 22, 3], [48, 12, 2.8], [52, 40, 2.8]]},
		 "tech": t3, "aiTech": van_ai2, "aiBuild": false, "aiFirst": 320,
		 "pbase": ["power", "power", "refinery", "barracks", "factory"], "pheroes": ["vey", "furnace"], "punits": [["engineer", 3], ["scorpion", 2], ["raider", 2], ["rifle", 4]], "keep": ["vey"],
		 "ehq": "hq", "ebase": ["power", "power", "power", "refinery", "barracks", "factory", "turret", "flak", "helipad"], "eunits": [["tank", 2], ["rifle", 3]],
		 "posts": [{"at": [42, 24], "b": ["comms", "turret", "power"], "u": [["rifle", 3], ["ranger", 2]], "tag": "cap"}],
		 "goals": [
			{"k": "capture", "tag": "cap", "types": ["comms"], "label": "Vanguard Comms Array",
			 "done": {"say": "The array is ours and their orders are pouring in. They will want it back.", "credits": 2000}},
			{"k": "survive", "t": 120, "label": "Hold the Comms Array", "protect": ["comms"],
			 "waves": {"first": 6, "every": 40, "n": 3, "from": [[60, 6], [62, 20]], "to": "comms",
				"list": [["tank", 2, 1, 1], ["rifle", 4, 1, 1], ["skyhawk", 1, 1, 2]]}}]},
		# ---- 7: hunt the enemy hero
		{"title": "The Iron Saint", "tag": "Stop Marshal Dace", "seed": 1707, "diff": "normal", "credits": [7500, 5000],
		 "theatre": "The Cinder Hills, the Pact's heartland · dusk",
		 "brief": "From the codes we know the name of their spearhead: the Iron Saint, Marshal Corwin Dace's own command tank. Where it goes, the Vanguard follows. It is parked in the Cinder Hills, and it will come for our forges soon. Destroy the Iron Saint, then their forward Command Yard.",
		 "obj": ["Destroy the Iron Saint", "Then destroy the Vanguard Command Yard", "Keep your Command Yard standing", "New: Tech Lab, Arc Crawlers, Arc Pylons, Helipad and Wasp drones"],
		 "heroes": ["furnace"],
		 "map": {"theme": "ash", "dusk": true, "p0": [10, 52], "e0": [52, 12], "rock": 0.7,
			"rivers": [{"pts": [[20, 0], [24, 16], [17, 30]], "w": 1.3}, {"pts": [[63, 30], [47, 36], [40, 50], [44, 63]], "w": 1.3}],
			"gaps": [[24, 10, 1.6], [43, 42, 1.6]], "ridges": [{"pts": [[28, 20], [36, 28], [30, 40]], "w": 2}],
			"ore": [[18, 46, 3.2], [8, 38, 3], [30, 48, 3], [36, 14, 3], [46, 24, 3], [54, 34, 2.6]]},
		 "tech": t4, "aiTech": van_ai2, "aiFirst": 260,
		 "pbase": ["power", "power", "refinery", "barracks", "factory", "comms"], "pheroes": ["furnace"], "punits": [["scorpion", 3], ["pyro", 3], ["lancer", 3], ["medic", 1]], "keep": ["hq"],
		 "ehq": "hq", "ebase": ["power", "power", "power", "refinery", "barracks", "factory", "repair", "turret", "turret", "flak", "bastion"],
		 "eheroes": ["saint"], "eunits": [["tank", 3], ["bulwark", 1], ["rifle", 4], ["ranger", 2]],
		 "events": [{"t": 240, "say": "The Iron Saint is rolling. Marshal Dace leads from the front!", "attack": "hero"}],
		 "goals": [
			{"k": "kill", "types": ["saint"], "label": "Iron Saint",
			 "done": {"say": "The Iron Saint burns! Dace's crew drag him out and run. Now break their Command Yard."}},
			{"k": "kill", "types": ["hq"], "label": "Vanguard Command Yard"}]},
		# ---- 8: finale, superweapon race
		{"title": "Embers", "tag": "Break the Skyfall", "seed": 1808, "diff": "hard", "credits": [10000, 6000], "swCh": 80.0,
		 "theatre": "Sable Mouth, the Vanguard's sea camp · dusk",
		 "brief": "The Vanguard has fallen back to its sea camp at Sable Mouth and finished a Skyfall Battery there. Its missiles can reach every town we have. Captain Ilse Harrow, their best marksman, guards the cliffs. Every system the Pact owns is yours. Destroy the Skyfall Battery and their Command Yard, and the Directorate goes home.",
		 "obj": ["Destroy the Skyfall Battery and the Vanguard Command Yard", "The Skyfall strikes your biggest cluster of buildings each time it charges", "Kestrel Vey must survive", "New: Rift Engine"],
		 "heroes": ["vey", "furnace"],
		 "map": {"theme": "temperate", "dusk": true, "p0": [12, 54], "e0": [50, 15], "rock": 0.74, "sea": {"edge": "n", "d": 5},
			"ridges": [{"pts": [[36, 4], [36, 20], [44, 30], [63, 30]], "w": 2}], "gaps": [[36, 13, 2], [42, 27, 2], [56, 30, 2]],
			"rivers": [{"pts": [[0, 30], [20, 34], [30, 44], [32, 63]], "w": 1.5}], "gaps2": [[18, 34, 2], [30, 53, 2]],
			"ore": [[18, 48, 3.4], [6, 42, 3], [24, 24, 3.2], [8, 18, 3], [46, 40, 3.2], [56, 40, 3], [44, 12, 2.8], [28, 56, 2.8]]},
		 "tech": null, "aiTech": null, "aiFirst": 230,
		 "pbase": ["power", "power", "power", "refinery", "barracks", "factory", "comms"], "pheroes": ["vey", "furnace"],
		 "punits": [["scorpion", 3], ["arcc", 1], ["pyro", 3], ["lancer", 3], ["medic", 2]], "keep": ["vey"],
		 "ehq": "hq", "ebase": ["power", "power", "power", "power", "refinery", "refinery", "barracks", "factory", "comms", "helipad", "tech", "flak", "flak", "bastion", "bastion", "turret", "skyfall"],
		 "eheroes": ["harrow"], "eunits": [["tank", 3], ["bulwark", 1], ["ranger", 2], ["skyhawk", 2], ["rifle", 4]],
		 "goals": [{"k": "kill", "types": ["skyfall", "hq"], "label": "Skyfall Battery and Command Yard"}]},
	]

# =====================================================================================
# Campaign II: Iron Tide (Vanguard)
# =====================================================================================
static func vanguard() -> Array:
	var t1 := _plus(VAN_EARLY, ["factory", "buggy", "tank"])
	var t2 := _plus(t1, ["flak", "repair", "arty", "engineer", "comms"])
	var t3 := _plus(t2, ["helipad", "skyhawk", "tech", "bulwark", "bastion"])
	var ash_ai := ["power", "refinery", "barracks", "factory", "turret", "rifle", "lancer", "medic", "pyro", "raider", "scorpion", "harv", "comms"]
	var ash_ai2 := _plus(ash_ai, ["flak", "repair", "arty", "helipad", "wasp", "tech", "arcc", "pylon"])
	return [
		# ---- 1: land, set up, silence the shore guns
		{"title": "Second Landfall", "tag": "Silence the shore guns", "seed": 2101, "diff": "easy", "credits": [0, 2000],
		 "theatre": "Gull Strand, south coast of the valley · morning",
		 "brief": "A year ago the Pact burned our Skyfall at Sable Mouth and threw us into the sea. Since then they have built Rift Engines, and the Directorate is back, with Captain Ilse Harrow leading the first wave. Get ashore, secure the landing zone so the barges can drop a Command Yard, then knock out the Pact shore guns before they sink the rest of the fleet.",
		 "obj": ["Reach the landing zone", "Destroy the four Pact shore guns", "Ilse Harrow must survive", "Hero: Ilse Harrow's rail rifle cuts through infantry and cracks walls"],
		 "heroes": ["harrow"],
		 "map": {"theme": "temperate", "p0": [10, 55], "e0": [50, 12], "rock": 0.74, "sea": {"edge": "s", "d": 4},
			"rivers": [{"pts": [[26, 0], [30, 20], [24, 36]], "w": 1.4}], "gaps": [[29, 14, 2], [26, 30, 2]],
			"ore": [[22, 44, 3], [12, 36, 3], [36, 36, 3], [44, 22, 3], [56, 30, 2.8]]},
		 "phq": false, "tech": t1, "aiTech": ash_ai, "aiBuild": false, "aiFirst": 380,
		 "pheroes": ["harrow"], "punits": [["rifle", 4], ["lancer", 2], ["buggy", 2]], "keep": ["harrow"],
		 "ehq": "hq", "ebase": ["power", "power", "refinery", "barracks", "factory", "turret"], "eunits": [["rifle", 3], ["raider", 2]],
		 "posts": [{"at": [32, 50], "b": ["turret", "turret", "power"], "u": [["rifle", 3], ["pyro", 1]], "tag": "guns"},
			{"at": [52, 44], "b": ["turret", "turret", "power"], "u": [["rifle", 2], ["lancer", 2]], "tag": "guns"}],
		 "goals": [
			{"k": "reach", "at": [20, 46], "r": 3, "who": "any", "label": "landing zone",
			 "done": {"say": "Landing zone secure. The barges are dropping a Command Yard.", "base": [20, 46], "pbase": ["power", "barracks"], "credits": 3000,
				"spawn": [{"team": 0, "at": [16, 56], "u": [["tank", 2], ["rifle", 3]]}]}},
			{"k": "kill", "tag": "guns", "types": ["turret"], "label": "shore guns"}]},
		# ---- 2: commando raid at night
		{"title": "Night Wires", "tag": "Cut the relay masts", "seed": 2202, "diff": "normal", "credits": [0, 0],
		 "theatre": "The Reedmarsh · night",
		 "brief": "The Pact learned its lesson at Silent Wires. Now it runs three relay masts through the Reedmarsh to warn its forges. Harrow, take a Ranger team and two Engineers in under the fog and take all three masts down. Destroy them or capture them, but no base and no backup.",
		 "obj": ["Destroy or capture all three Pact relay masts (Comms Arrays)", "Ilse Harrow must survive", "Engineers can capture a mast, which also counts"],
		 "heroes": ["harrow"],
		 "map": {"theme": "marsh", "dusk": true, "p0": [6, 56], "e0": null, "rock": 0.78,
			"lakes": [[16, 30, 4], [30, 22, 4], [28, 44, 4], [44, 36, 4], [52, 24, 3], [40, 54, 3.5], [10, 12, 3]],
			"ore": [[22, 54, 2.4], [56, 10, 2.4]]},
		 "phq": false, "tech": [], "aiTech": [], "aiBuild": false, "aiProd": false, "ehq": "",
		 "pheroes": ["harrow"], "punits": [["ranger", 3], ["engineer", 2], ["medic", 1]], "keep": ["harrow"],
		 "posts": [{"at": [18, 16], "b": ["comms", "power"], "u": [["pyro", 2], ["rifle", 2]], "tag": "relay"},
			{"at": [44, 22], "b": ["comms", "power", "turret"], "u": [["rifle", 3]], "tag": "relay"},
			{"at": [52, 46], "b": ["comms", "power"], "u": [["pyro", 2], ["lancer", 1], ["raider", 1]], "tag": "relay"},
			{"at": [32, 34], "u": [["rifle", 3]]}],
		 "events": [{"t": 220, "say": "Wasp drones sweeping the marsh", "spawn": [{"at": [60, 4], "u": [["wasp", 2]], "go": "hero"}]},
			{"t": 420, "say": "Pact riders are hunting you", "spawn": [{"at": [62, 60], "u": [["raider", 3]], "go": "hero"}]}],
		 "goals": [{"k": "kill", "tag": "relay", "types": ["comms"], "label": "relay masts"}]},
		# ---- 3: free prisoners, then walk them out
		{"title": "Chainbreak", "tag": "Free the miners", "seed": 2303, "diff": "normal", "credits": [0, 0],
		 "theatre": "Redrock labour camp, the Dust Flats · noon",
		 "brief": "The Pact holds Directorate miners and engineers at the Redrock camp and works them in its pits. A tank column can reach the camp across the flats. Break the guard, free every prisoner, then bring them home to the extraction point.",
		 "obj": ["Free the prisoners at Redrock camp (move a unit next to them)", "Bring 5 of them to the extraction point (south-west)", "Don't lose your whole column"],
		 "map": {"theme": "arid", "p0": [7, 56], "e0": null, "rock": 0.8,
			"mesas": [[22, 22, 4], [36, 40, 4], [14, 38, 3], [46, 28, 3], [30, 8, 3], [52, 52, 3.5]],
			"ore": [[44, 10, 3], [50, 18, 3], [20, 50, 2.6]], "roads": [[[7, 56], [20, 46], [32, 30], [46, 15]]]},
		 "phq": false, "tech": [], "aiTech": [], "aiBuild": false, "aiProd": false, "ehq": "",
		 "punits": [["tank", 3], ["buggy", 3], ["rifle", 4], ["medic", 1]], "keep": [],
		 "posts": [{"at": [47, 14], "b": ["turret", "turret", "barracks", "power"], "u": [["pyro", 3], ["rifle", 4], ["raider", 2]]},
			{"at": [30, 32], "u": [["rifle", 3], ["lancer", 2]]}, {"at": [20, 44], "u": [["raider", 2]]}],
		 "captives": [{"at": [50, 10], "u": [["engineer", 3], ["rifle", 5]]}],
		 "goals": [
			{"k": "rescue", "label": "prisoners", "done": {"say": "Chains are off. Get them to the extraction point!",
				"spawn": [{"at": [62, 2], "u": [["raider", 4], ["scorpion", 1]], "go": "vip"}]}},
			{"k": "escort", "at": [7, 56], "r": 3, "need": 5, "label": "extraction point"}]},
		# ---- 4: economy race
		{"title": "Glass Flats", "tag": "Strip the aurite", "seed": 2404, "diff": "normal", "credits": [4000, 2000],
		 "theatre": "The Glass Flats · high summer",
		 "brief": "The war will be won by whoever has the most aurite. The Glass Flats shine with it, and the Pact's raider bikes know every gully there. Mine 12,000 aurite before the Pact can move its own harvesters in.",
		 "obj": ["Deliver 12,000 aurite within 14 minutes", "Keep your Command Yard standing", "New: War Factory, Warden Tanks, Repair Bay, Howler Mortars, Flak Nests"],
		 "map": {"theme": "arid", "p0": [10, 12], "e0": [53, 52], "rock": 0.8,
			"mesas": [[24, 26, 4], [38, 20, 3.5], [20, 44, 3.5], [40, 40, 4], [52, 30, 3], [32, 54, 3]],
			"rivers": [{"pts": [[0, 34], [22, 34], [34, 30], [63, 22]], "w": 0.9}], "gaps": [[14, 34, 1.5], [30, 31, 1.5], [48, 26, 1.5]],
			"ore": [[18, 16, 3.4], [8, 24, 3], [28, 12, 3], [14, 30, 3], [30, 38, 3.4], [46, 12, 3], [8, 48, 3], [44, 48, 3]]},
		 "tech": t2, "aiTech": ash_ai, "aiFirst": 240,
		 "pbase": ["power", "refinery"], "punits": [["tank", 2], ["buggy", 2], ["rifle", 4]], "keep": ["hq"],
		 "ehq": "hq", "ebase": ["power", "power", "refinery", "barracks", "factory", "turret", "turret", "comms"], "eunits": [["raider", 3], ["rifle", 3]],
		 "events": [
			{"t": 150, "say": "Raider bikes going for your harvesters", "spawn": [{"at": [62, 8], "u": [["raider", 3]], "go": "harv"}]},
			{"t": 330, "say": "More raiders on the flats", "spawn": [{"at": [2, 62], "u": [["raider", 3], ["pyro", 2]], "go": "harv"}]},
			{"t": 480, "say": "Wasp drones inbound", "spawn": [{"at": [62, 30], "u": [["wasp", 2], ["raider", 2]], "go": "harv"}]},
			{"t": 650, "say": "Scorpion tanks hunting harvesters", "spawn": [{"at": [62, 8], "u": [["scorpion", 2], ["raider", 2]], "go": "harv"}]}],
		 "goals": [{"k": "mine", "n": 12000, "t": 840, "label": "aurite delivered"}]},
		# ---- 5: hold a bridgehead over a lava river
		{"title": "Breakwater", "tag": "Hold the bridgehead", "seed": 2505, "diff": "normal", "credits": [7500, 0],
		 "theatre": "The Cinder River fords · ashfall",
		 "brief": "We hold the only fords over the Cinder River, where the hills run with molten slag. The Pact will throw everything at us to get them back: Pyros, Arc Crawlers, drones. The main army needs ten minutes to come up. Make them count.",
		 "obj": ["Hold out for 10 minutes", "Keep your Command Yard standing", "New: Skyhawk gunships, Tech Lab, Bulwark Tanks, Bastion Cannons"],
		 "map": {"theme": "ash", "p0": [32, 54], "e0": [32, 6], "rock": 0.74,
			"rivers": [{"pts": [[0, 32], [20, 30], [44, 34], [63, 30]], "w": 2}], "gaps": [[12, 31, 2], [32, 32, 2], [52, 32, 2]],
			"ore": [[20, 46, 3.4], [44, 46, 3.4], [32, 42, 2.8], [10, 52, 3], [54, 52, 3], [20, 16, 3], [44, 16, 3]]},
		 "tech": t3, "aiTech": [], "aiBuild": false, "aiProd": false,
		 "pbase": ["power", "power", "refinery", "barracks", "factory", "repair"], "punits": [["tank", 3], ["rifle", 4], ["lancer", 3], ["ranger", 2]], "keep": ["hq"],
		 "ehq": "hq", "ebase": ["power", "power", "refinery", "barracks", "factory", "helipad", "turret", "pylon"],
		 "goals": [{"k": "survive", "t": 600, "label": "Hold the fords",
			"waves": {"first": 45, "every": 55, "n": 11, "from": [[14, 4], [50, 4], [32, 2]],
				"list": [["rifle", 3, 1, 1], ["raider", 2, 0.5, 1], ["pyro", 1, 0.5, 2], ["scorpion", 0, 1, 3], ["wasp", 2, 0, 5], ["arcc", 1, 0, 6], ["arty", 1, 0, 7], ["arcc", 0, 1, 9]]}}]},
		# ---- 6: hold three hills at once
		{"title": "Three Spires", "tag": "Seize the high ground", "seed": 2606, "diff": "normal", "credits": [7500, 4500],
		 "theatre": "The Spires, autumn hill country · afternoon",
		 "brief": "Three old signal spires look over the whole middle valley. Hold all three at once and our gunners can see every Pact convoy for a day's march. Marshal Dace is back in the hatch of the rebuilt Iron Saint and he wants this one personally.",
		 "obj": ["Hold all three spires at the same time for 2:30 in total (no enemy units inside)", "Keep your Command Yard standing", "Hero: the Iron Saint, Marshal Dace's command tank"],
		 "heroes": ["saint"],
		 "map": {"theme": "autumn", "p0": [10, 54], "e0": [54, 9], "rock": 0.72,
			"mesas": [[28, 22, 2.4], [40, 36, 2.4], [16, 34, 2.2], [48, 22, 2]],
			"rivers": [{"pts": [[63, 44], [44, 48], [30, 56], [24, 63]], "w": 1.4}], "gaps": [[38, 50, 2]],
			"ore": [[18, 48, 3.2], [8, 40, 3], [26, 42, 3], [36, 14, 3], [46, 28, 3], [56, 34, 2.8]]},
		 "tech": t3, "aiTech": ash_ai2, "aiFirst": 220,
		 "pbase": ["power", "power", "refinery", "barracks", "factory"], "pheroes": ["saint"], "punits": [["tank", 3], ["rifle", 4], ["lancer", 2], ["medic", 1]], "keep": ["hq"],
		 "ehq": "hq", "ebase": ["power", "power", "power", "refinery", "barracks", "factory", "turret", "turret", "flak", "comms"], "eunits": [["scorpion", 2], ["pyro", 2], ["rifle", 4]],
		 "posts": [{"at": [33, 28], "u": [["rifle", 3], ["lancer", 1]]}],
		 "events": [{"t": 240, "say": "Pact infantry moving on the east spire", "spawn": [{"at": [62, 30], "u": [["rifle", 4], ["pyro", 2], ["scorpion", 1]], "go": [44, 18]}]},
			{"t": 420, "say": "A Pact column is heading for the west spire", "spawn": [{"at": [30, 2], "u": [["rifle", 4], ["raider", 2], ["scorpion", 2]], "go": [22, 26]}]},
			{"t": 600, "say": "Arc Crawlers rolling on the spires", "spawn": [{"at": [62, 30], "u": [["arcc", 2], ["pyro", 3]], "go": [33, 30]}]}],
		 "goals": [{"k": "hold", "zones": [[22, 26], [33, 30], [44, 18]], "r": 2.6, "t": 150, "label": "spires"}]},
		# ---- 7: hunt the enemy heroes
		{"title": "The Cinder", "tag": "Hunt Kestrel Vey", "seed": 2707, "diff": "normal", "credits": [9000, 5000],
		 "theatre": "Ironpine, the Pact's mountain fortress · snow",
		 "brief": "Kestrel Vey is the Pact's heart. Every town rose when she lit that fire on Hollin's Rise. She and The Furnace now ride out of the Ironpine fortress to hit our columns. Take them both off the field and the Pact loses its nerve.",
		 "obj": ["Defeat Kestrel Vey and The Furnace", "Ilse Harrow must survive"],
		 "heroes": ["harrow", "saint"],
		 "map": {"theme": "snow", "p0": [10, 54], "e0": [52, 12], "rock": 0.72,
			"ridges": [{"pts": [[0, 30], [16, 32], [24, 26]], "w": 2.2}, {"pts": [[34, 40], [46, 34], [63, 38]], "w": 2.2}],
			"gaps": [[8, 31, 1.6], [56, 37, 1.6]], "lakes": [[30, 30, 3.5], [52, 54, 3]],
			"ore": [[18, 46, 3.2], [8, 40, 3], [28, 48, 3], [40, 14, 3], [48, 26, 3], [20, 18, 3]]},
		 "tech": t3, "aiTech": ash_ai2, "aiFirst": 240,
		 "pbase": ["power", "power", "power", "refinery", "barracks", "factory", "repair"], "pheroes": ["harrow", "saint"],
		 "punits": [["tank", 3], ["bulwark", 1], ["ranger", 2], ["lancer", 3], ["medic", 1]], "keep": ["harrow"],
		 "ehq": "hq", "ebase": ["power", "power", "power", "refinery", "barracks", "factory", "repair", "comms", "turret", "turret", "flak", "pylon"],
		 "eheroes": ["vey", "furnace"], "eunits": [["scorpion", 2], ["raider", 3], ["pyro", 3]],
		 "events": [{"t": 150, "say": "Kestrel Vey is leading a raid on your base!", "attack": "hero"},
			{"t": 420, "say": "Vey and The Furnace are coming again", "attack": "hero"}],
		 "goals": [{"k": "kill", "types": ["vey", "furnace"], "verb": "Defeat", "label": "Kestrel Vey and The Furnace",
			"done": {"say": "Vey is down and taken alive. The Furnace is scrap."}}]},
		# ---- 8: finale
		{"title": "Rift Breaker", "tag": "End the Rift Engines", "seed": 2808, "diff": "hard", "credits": [11000, 6500], "swCh": 90.0,
		 "theatre": "Emberhold, the Pact capital · ashfall at dusk",
		 "brief": "Emberhold has two Rift Engines, and both are charging. Each one can tear a hole through a whole base. Everything the Directorate has is here: Skyfall, Bulwarks, the Iron Saint. Destroy both Rift Engines and the Pact's Command Yard, and this war is over.",
		 "obj": ["Destroy both Rift Engines and the Pact Command Yard", "Each Rift Engine strikes your biggest cluster of buildings when it charges", "The Iron Saint must survive", "New: Skyfall Battery"],
		 "heroes": ["harrow", "saint"],
		 "map": {"theme": "ash", "dusk": true, "p0": [10, 54], "e0": [52, 12], "rock": 0.72,
			"rivers": [{"pts": [[0, 26], [18, 30], [30, 24], [40, 36], [63, 40]], "w": 1.6}], "gaps": [[10, 28, 2], [30, 25, 2], [52, 38, 2]],
			"ridges": [{"pts": [[38, 4], [40, 18], [48, 26]], "w": 1.8}], "gaps2": [[40, 12, 1.8]],
			"ore": [[18, 46, 3.4], [8, 38, 3], [28, 48, 3], [26, 14, 3], [46, 32, 3], [56, 26, 2.8], [20, 56, 2.8]]},
		 "tech": null, "aiTech": null, "aiFirst": 220,
		 "pbase": ["power", "power", "power", "refinery", "barracks", "factory", "comms", "repair"], "pheroes": ["harrow", "saint"],
		 "punits": [["tank", 3], ["bulwark", 2], ["lancer", 4], ["ranger", 2], ["medic", 2]], "keep": ["saint"],
		 "ehq": "hq", "ebase": ["power", "power", "power", "power", "power", "refinery", "refinery", "barracks", "factory", "comms", "helipad", "tech", "flak", "flak", "pylon", "pylon", "turret", "rift", "rift"],
		 "eunits": [["scorpion", 3], ["arcc", 2], ["pyro", 3], ["wasp", 2], ["rifle", 4]],
		 "goals": [{"k": "kill", "types": ["rift", "hq"], "label": "Rift Engines and Command Yard"}]},
	]

# =====================================================================================
# Campaign III: The Hollow Song (Hollow Choir), during the Iron Tide war, against both armies
# =====================================================================================
static func choir() -> Array:
	var t2 := _plus(CHO_EARLY, ["factory", "skitter", "mantis"])
	var t3 := _plus(t2, ["flak", "repair", "comms", "sapper", "engineer", "helipad", "moth"])
	var t4 := _plus(t3, ["tech", "geode", "spire", "cantor"])
	var van_ai := ["power", "refinery", "barracks", "factory", "turret", "rifle", "lancer", "medic", "buggy", "tank", "harv"]
	var van_ai2 := _plus(van_ai, ["flak", "repair", "arty", "comms", "ranger", "helipad", "skyhawk"])
	var ash_ai := ["power", "refinery", "barracks", "factory", "turret", "rifle", "lancer", "medic", "pyro", "raider", "scorpion", "harv", "comms"]
	var ash_ai2 := _plus(ash_ai, ["flak", "repair", "arty", "helipad", "wasp", "tech", "arcc", "pylon"])
	return [
		# ---- 1: no base, sappers break the Directorate's deep drills, then the Cantor slips away
		{"title": "First Song", "tag": "Stop the deep drills", "seed": 3101, "diff": "easy", "credits": [0, 0], "efac": "vanguard",
		 "theatre": "Redrock mines, under the Dust Flats · night",
		 "brief": "The Directorate's drills are boring down into the caves where the Choir sleeps. One of the old miners woke and started to sing, and the others woke with her. Cantor, take the first of them up to the surface, blow up both deep drills, then lead them back down the old shaft.",
		 "obj": ["Destroy the two Vanguard deep drills", "Lead the Cantor to the old shaft", "The Cantor must survive", "New: Burrow Sappers dig unseen, then blow up buildings"],
		 "heroes": ["cantor"],
		 "map": {"theme": "arid", "dusk": true, "p0": [8, 54], "e0": null, "rock": 0.8,
			"mesas": [[20, 24, 3.5], [36, 40, 4], [14, 38, 3], [40, 22, 3], [52, 32, 3]],
			"ore": [[30, 30, 2.8], [50, 14, 2.6], [22, 50, 2.4]], "roads": [[[8, 54], [22, 44], [30, 30], [48, 15]]]},
		 "phq": false, "tech": [], "aiTech": [], "aiBuild": false, "aiProd": false, "ehq": "",
		 "pheroes": ["cantor"], "punits": [["thrall", 10], ["sapper", 3], ["medic", 2]], "keep": ["cantor"],
		 "posts": [{"at": [22, 42], "u": [["rifle", 2]]},
			{"at": [30, 27], "b": ["refinery", "power"], "u": [["rifle", 3]], "tag": "drills"},
			{"at": [48, 13], "b": ["refinery", "power", "turret"], "u": [["rifle", 2], ["lancer", 1]], "tag": "drills"},
			{"at": [44, 40], "u": [["rifle", 2], ["buggy", 1]]}],
		 "events": [{"t": 300, "say": "Buggies are hunting the Cantor", "spawn": [{"at": [62, 4], "u": [["buggy", 2]], "go": "hero"}]}],
		 "goals": [
			{"k": "kill", "tag": "drills", "types": ["refinery"], "label": "deep drills",
			 "done": {"say": "The drills are silent. Back to the old shaft before they come looking!"}},
			{"k": "reach", "at": [56, 54], "r": 2.5, "who": "hero", "label": "old shaft",
			 "waves": {"first": 4, "every": 30, "n": 3, "from": [[62, 30], [40, 2]], "to": "hero",
				"list": [["rifle", 3, 1, 1], ["buggy", 1, 0, 2]]}}]},
		# ---- 2: first base, gardens race the Pact's raiders
		{"title": "Gardens of Glass", "tag": "Grow the first gardens", "seed": 3202, "diff": "easy", "credits": [3000, 1500], "efac": "ashen",
		 "theatre": "The Gloam hollow, green river country · morning",
		 "brief": "The Choir needs aurite to grow, and the Gloam hollow is full of it. We have no refineries and no harvesters: our Crystal Gardens drink the ore around them. Plant them on the ore fields and grow 12,000 aurite. Pact raiders have seen the glow and will come for the gardens.",
		 "obj": ["Grow 12,000 aurite within 13 minutes", "Keep your Command Yard standing", "New: base building, Crystal Gardens on ore, Burrows to build further out"],
		 "map": {"theme": "temperate", "p0": [10, 53], "e0": [53, 11], "rock": 0.74,
			"rivers": [{"pts": [[0, 30], [20, 32], [36, 26], [63, 30]], "w": 1.3}], "gaps": [[12, 31, 2], [30, 28, 2], [50, 29, 2]],
			"ore": [[16, 47, 3.2], [6, 42, 3], [24, 40, 3], [30, 52, 3], [8, 22, 3], [36, 36, 3.2], [44, 18, 3], [54, 40, 3]]},
		 "tech": CHO_EARLY, "aiTech": ash_ai, "aiBuild": false, "aiFirst": 420,
		 "pbase": ["power", "barracks"], "punits": [["thrall", 6], ["lancer", 2]], "keep": ["hq"],
		 "ehq": "hq", "ebase": ["power", "power", "refinery", "barracks", "factory", "turret"], "eunits": [["rifle", 3], ["raider", 1]],
		 "events": [
			{"t": 150, "say": "Raider bikes are heading for your gardens", "spawn": [{"at": [62, 34], "u": [["raider", 2]], "go": "harv"}]},
			{"t": 330, "say": "Pact riflemen are coming for the gardens", "spawn": [{"at": [40, 2], "u": [["rifle", 4], ["raider", 1]], "go": "harv"}]},
			{"t": 540, "say": "Pyros and raiders in the hollow", "spawn": [{"at": [62, 50], "u": [["pyro", 2], ["raider", 2]], "go": "harv"}]}],
		 "goals": [{"k": "mine", "n": 12000, "t": 780, "label": "aurite grown"}]},
		# ---- 3: tunnels under a firebase
		{"title": "Under the Wall", "tag": "Tunnel past the firebase", "seed": 3303, "diff": "easy", "credits": [4500, 1500], "efac": "vanguard",
		 "theatre": "Kettle gorge, autumn foundry country · afternoon",
		 "brief": "A Vanguard firebase sits on the only road into our caves, behind the river and its guns. We do not need the road. Dig Burrows forward, and your army walks into one and comes out of the other. Then wipe the firebase out.",
		 "obj": ["Destroy every Vanguard unit and structure", "Keep your Command Yard standing", "New: War Factory, Skitters, Glass Mantises (they hunt tanks)"],
		 "map": {"theme": "autumn", "p0": [10, 52], "e0": [52, 12], "rock": 0.73,
			"rivers": [{"pts": [[0, 22], [18, 26], [32, 30], [46, 28], [63, 36]], "w": 1.8}], "gaps": [[40, 29, 2]],
			"ridges": [{"pts": [[30, 2], [32, 14], [38, 22]], "w": 1.8}],
			"ore": [[18, 46, 3.2], [7, 38, 3], [28, 42, 3], [44, 18, 3], [33, 10, 2.6], [56, 26, 2.6]]},
		 "tech": t2, "aiTech": ["power", "refinery", "barracks", "factory", "turret", "rifle", "lancer", "medic", "buggy", "harv"], "aiBuild": false, "aiFirst": 420,
		 "pbase": ["power", "power", "barracks", "garden"], "punits": [["thrall", 8], ["lancer", 3], ["skitter", 3]], "keep": ["hq"],
		 "ehq": "barracks", "ebase": ["power", "power", "refinery", "factory", "turret", "turret"], "eunits": [["rifle", 4], ["lancer", 1], ["buggy", 1]],
		 "posts": [{"at": [40, 32], "b": ["turret", "turret"], "u": [["rifle", 3]]}, {"at": [24, 22], "u": [["rifle", 3]]}],
		 "goals": [{"k": "destroy_all", "label": "Vanguard firebase"}]},
		# ---- 4: free the captured singers and bring them home
		{"title": "Chainsong", "tag": "Free the captured Choir", "seed": 3404, "diff": "normal", "credits": [0, 0], "efac": "ashen",
		 "theatre": "Ironpine quarries · first snow",
		 "brief": "The Pact has chained a whole hall of our singers at the Ironpine quarries and works them in the pits. They call them hollow men and want to learn how we grow aurite. Cantor, go in with a small band, free every one of them and bring at least five home to the cave mouth.",
		 "obj": ["Free the prisoners at the quarry (move a unit next to them)", "Bring 5 of them to the cave mouth (south-west)", "The Cantor must survive"],
		 "heroes": ["cantor", "vey"],
		 "map": {"theme": "snow", "p0": [7, 56], "e0": null, "rock": 0.74,
			"ridges": [{"pts": [[0, 34], [14, 36], [26, 30]], "w": 2.2}, {"pts": [[34, 46], [46, 40], [63, 44]], "w": 2.2}],
			"gaps": [[8, 35, 1.8], [56, 43, 1.8]], "lakes": [[32, 34, 3.5], [20, 12, 3], [54, 56, 3]],
			"ore": [[46, 10, 3], [52, 20, 2.6], [18, 50, 2.4]], "roads": [[[7, 56], [18, 44], [30, 26], [48, 14]]]},
		 "phq": false, "tech": [], "aiTech": [], "aiBuild": false, "aiProd": false, "ehq": "",
		 "pheroes": ["cantor"], "punits": [["thrall", 6], ["skitter", 3], ["mantis", 2], ["medic", 1]], "keep": ["cantor"],
		 "posts": [{"at": [48, 15], "b": ["turret", "turret", "barracks", "power"], "u": [["pyro", 3], ["rifle", 4], ["raider", 1]]},
			{"at": [30, 26], "u": [["rifle", 3], ["lancer", 1]]}, {"at": [18, 42], "u": [["raider", 2]]}],
		 "captives": [{"at": [50, 10], "u": [["thrall", 6], ["sapper", 2]]}],
		 "goals": [
			{"k": "rescue", "label": "prisoners", "done": {"say": "They are free and singing! Kestrel Vey is riding after you. Run for the cave mouth!",
				"spawn": [{"at": [62, 2], "u": [["vey", 1], ["raider", 3]], "go": "vip"}]}},
			{"k": "escort", "at": [7, 56], "r": 3, "need": 5, "label": "cave mouth"}]},
		# ---- 5: hold the caves while the Pact tries to collapse them
		{"title": "The Hum Below", "tag": "Hold the caves", "seed": 3505, "diff": "normal", "credits": [6000, 0], "efac": "ashen",
		 "theatre": "The Cinder vents · ashfall",
		 "brief": "The Pact has decided we are a danger and wants to blast our cave mouths shut. Their columns are coming down the Cinder vents. The halls below need ten minutes to seal the deep doors. Hold the surface until then.",
		 "obj": ["Hold out for 10 minutes", "Keep your Command Yard standing", "New: Burrow Sappers, Glassmoths, Comms Array, Flak Nests"],
		 "map": {"theme": "ash", "p0": [32, 54], "e0": [32, 6], "rock": 0.74,
			"rivers": [{"pts": [[0, 30], [20, 32], [44, 28], [63, 32]], "w": 1.6}], "gaps": [[12, 31, 2.2], [32, 30, 2.2], [52, 30, 2.2]],
			"ore": [[20, 46, 3.4], [44, 46, 3.4], [32, 42, 2.8], [10, 52, 3], [54, 52, 3], [20, 16, 3], [44, 16, 3]]},
		 "tech": t3, "aiTech": [], "aiBuild": false, "aiProd": false,
		 "pbase": ["power", "power", "garden", "barracks", "factory", "turret", "turret"], "punits": [["mantis", 3], ["thrall", 8], ["lancer", 3], ["skitter", 2]], "keep": ["hq"],
		 "ehq": "hq", "ebase": ["power", "power", "refinery", "barracks", "factory", "helipad", "turret", "pylon"],
		 "goals": [{"k": "survive", "t": 600, "label": "Hold the caves",
			"waves": {"first": 50, "every": 58, "n": 10, "from": [[14, 4], [50, 4], [32, 2]],
				"list": [["rifle", 3, 1, 1], ["raider", 2, 0.5, 1], ["pyro", 1, 0.5, 2], ["scorpion", 0, 1, 3], ["wasp", 2, 0, 5], ["arty", 1, 0, 6], ["arcc", 1, 0, 8]]}}]},
		# ---- 6: wake the Deepmaw, then break the listening post
		{"title": "The Deepmaw", "tag": "Wake the old beast", "seed": 3606, "diff": "normal", "credits": [6500, 3000], "efac": "vanguard",
		 "theatre": "The Reedmarsh sinkholes · fog",
		 "brief": "Deep under the Reedmarsh sleeps the Deepmaw, the oldest thing in the caves. The Directorate has built a listening post right over its hollow, and Captain Ilse Harrow guards it. Cantor, sing the Deepmaw awake at its sinkhole, then turn it on the post and the base behind it.",
		 "obj": ["Bring the Cantor to the Deepmaw's sinkhole", "Then destroy the listening post (Comms Array) and the Vanguard Command Yard", "The Cantor must survive", "New hero: the Deepmaw"],
		 "heroes": ["cantor", "deepmaw", "harrow"],
		 "map": {"theme": "marsh", "p0": [8, 54], "e0": [55, 9], "rock": 0.78,
			"lakes": [[20, 22, 4], [30, 42, 4], [46, 32, 3.6], [13, 32, 3], [50, 50, 4], [36, 12, 3], [58, 28, 2.6]],
			"ore": [[16, 48, 3.2], [6, 40, 2.8], [28, 30, 3], [40, 22, 3], [48, 12, 2.8], [54, 40, 2.8]]},
		 "tech": t3, "aiTech": van_ai, "aiBuild": false, "aiFirst": 420,
		 "pbase": ["power", "power", "garden", "barracks", "factory", "burrow", "turret"], "pheroes": ["cantor"], "punits": [["mantis", 3], ["thrall", 6], ["sapper", 2], ["lancer", 2]], "keep": ["cantor"],
		 "ehq": "hq", "ebase": ["power", "power", "power", "refinery", "barracks", "factory", "turret", "flak", "helipad"],
		 "eheroes": ["harrow"], "eunits": [["tank", 1], ["rifle", 3], ["ranger", 1]],
		 "posts": [{"at": [46, 22], "b": ["comms", "turret", "flak", "power"], "u": [["rifle", 3], ["ranger", 1], ["tank", 1]], "tag": "post"}, {"at": [34, 30], "u": [["rifle", 3], ["lancer", 1]]}],
		 "events": [{"t": 420, "say": "Vanguard tanks are probing your base", "spawn": [{"at": [62, 30], "u": [["tank", 2], ["rifle", 3]], "go": "base"}]}],
		 "goals": [
			{"k": "reach", "at": [28, 26], "r": 2.5, "who": "hero", "label": "Deepmaw's sinkhole",
			 "done": {"say": "The ground splits and the Deepmaw rises. It follows the song.", "spawn": [{"team": 0, "at": [28, 26], "u": [["deepmaw", 1]]}]}},
			{"k": "kill", "types": ["comms", "hq"], "label": "listening post and Command Yard"}]},
		# ---- 7: hunt the Iron Saint
		{"title": "Iron in the Garden", "tag": "Stop the Iron Saint", "seed": 3707, "diff": "normal", "credits": [7500, 5000], "efac": "vanguard",
		 "theatre": "The Glass Flats · high summer",
		 "brief": "Marshal Dace has heard of the singing caves. He has turned the Iron Saint south to burn our gardens on the Glass Flats, with a whole battle group behind it. Its armour laughs at shards, but not at the Deepmaw or the Mantises. Break the Iron Saint, then their forward Command Yard.",
		 "obj": ["Destroy the Iron Saint", "Then destroy the Vanguard Command Yard", "Keep your Command Yard standing", "New: Tech Lab, Geode Lobbers, Shard Spires, train the Cantor"],
		 "heroes": ["deepmaw", "saint"],
		 "map": {"theme": "arid", "p0": [10, 52], "e0": [52, 12], "rock": 0.8,
			"mesas": [[24, 26, 4], [38, 20, 3.5], [20, 40, 3.5], [40, 40, 4], [52, 30, 3]],
			"rivers": [{"pts": [[0, 34], [22, 34], [34, 30], [63, 22]], "w": 0.9}], "gaps": [[14, 34, 1.5], [30, 31, 1.5], [48, 26, 1.5]],
			"ore": [[18, 46, 3.2], [8, 38, 3], [30, 48, 3], [36, 14, 3], [46, 24, 3], [54, 34, 2.6]]},
		 "tech": t4, "aiTech": van_ai2, "aiFirst": 260,
		 "pbase": ["power", "power", "garden", "barracks", "factory", "comms", "burrow"], "pheroes": ["deepmaw"], "punits": [["mantis", 4], ["thrall", 6], ["lancer", 3], ["medic", 1]], "keep": ["hq"],
		 "ehq": "hq", "ebase": ["power", "power", "power", "refinery", "barracks", "factory", "repair", "turret", "turret", "flak", "bastion"],
		 "eheroes": ["saint"], "eunits": [["tank", 3], ["rifle", 4], ["ranger", 2]],
		 "events": [{"t": 240, "say": "The Iron Saint is rolling for your gardens!", "attack": "hero"}],
		 "goals": [
			{"k": "kill", "types": ["saint"], "label": "Iron Saint",
			 "done": {"say": "The Iron Saint is down in the glass! Now break their Command Yard."}},
			{"k": "kill", "types": ["hq"], "label": "Vanguard Command Yard"}]},
		# ---- 8: finale against the Pact's Rift Engine
		{"title": "The Last Chorus", "tag": "Silence the Rift Engine", "seed": 3808, "diff": "hard", "credits": [10000, 6000], "swCh": 80.0, "efac": "ashen",
		 "theatre": "The Emberhold rift · ashfall at dusk",
		 "brief": "Every shot of the Pact's Rift Engine cracks the caves below, and Kestrel Vey guards it. The Choir sings as one now. Cantor, raise a Chorus Well, break the Rift Engine and the Pact's Command Yard, and the deep will be quiet again.",
		 "obj": ["Destroy the Rift Engine and the Pact Command Yard", "The Rift Engine strikes your biggest cluster of buildings when charged", "The Cantor must survive", "New: Chorus Well"],
		 "heroes": ["cantor", "deepmaw", "vey"],
		 "map": {"theme": "ash", "dusk": true, "p0": [10, 54], "e0": [52, 12], "rock": 0.72,
			"rivers": [{"pts": [[0, 28], [18, 32], [30, 26], [40, 38], [63, 42]], "w": 1.6}], "gaps": [[10, 30, 2], [30, 27, 2], [52, 40, 2]],
			"ridges": [{"pts": [[38, 4], [40, 18], [48, 26]], "w": 1.8}], "gaps2": [[40, 12, 1.8]],
			"ore": [[18, 46, 3.4], [8, 38, 3], [28, 48, 3], [26, 14, 3], [46, 32, 3], [56, 26, 2.8], [20, 56, 2.8]]},
		 "tech": null, "aiTech": null, "aiFirst": 230,
		 "pbase": ["power", "power", "power", "garden", "barracks", "factory", "comms", "burrow"], "pheroes": ["cantor", "deepmaw"],
		 "punits": [["mantis", 4], ["geode", 1], ["thrall", 6], ["lancer", 3], ["medic", 2]], "keep": ["cantor"],
		 "ehq": "hq", "ebase": ["power", "power", "power", "power", "refinery", "refinery", "barracks", "factory", "comms", "helipad", "tech", "flak", "flak", "pylon", "pylon", "turret", "rift"],
		 "eheroes": ["vey"], "eunits": [["scorpion", 3], ["arcc", 2], ["pyro", 3], ["wasp", 2], ["rifle", 4]],
		 "goals": [{"k": "kill", "types": ["rift", "hq"], "label": "Rift Engine and Command Yard"}]},
	]
