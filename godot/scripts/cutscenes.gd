extends RefCounted
## In-engine cutscenes, as data. CutscenePlayer (cutscene.gd) plays them; main.gd sets the world up.
##
## A scene borrows a mission's map ("camp", "map": mission index). With "bare" it brings its own cast instead of
## the mission's units; without it the mission is set up as in play (posts, heroes, goal marks), which suits a
## mission intro. Map positions are tiles, like campaign.gd.
##
##   cast:  [{"id", "team", "u": [[type, n]], "at": [x, y]}  or  {"id", "team", "b": [types], "at"}]  ("go": [x, y] sets off at once)
##   shots: {"d": seconds, "cam": [x, y, dist, yaw°, pitch°], "to": [... end of the move], "follow": cast id,
##           "say": [who, line], "title": [eyebrow, title, line], "place": "where · when", "do": [action, ...]}
##   yaw 0 looks north from the south; 90 looks west from the east. A shot without "cam" starts where the last one ended.
##   actions (each may have "t", seconds into the shot): {"move": id, "to": [x, y]}, {"spawn": cast entry},
##           {"boom": [x, y], "s": size}, {"sfx": name}
## Keep lines short (one line on a phone, about 60 characters) and few: the player reads them in the letterbox.

const WHO := {"vey": "Kestrel Vey", "dace": "Marshal Dace", "harrow": "Ilse Harrow"}

static var _all := {}

static func all() -> Dictionary:
	if _all.is_empty(): _all = _scenes()
	return _all

static func has(id: String) -> bool:
	return all().has(id)

static func scene(id: String) -> Dictionary:
	return all()[id]

## The opening of a campaign plays before its first mission; "<camp>_<n>" is the intro of mission n.
static func opening_of(camp: String) -> String:
	return camp + "_open"

static func intro_of(camp: String, idx: int) -> String:
	return "%s_%d" % [camp, idx + 1]

static func _scenes() -> Dictionary:
	return {
		# ---------------- Campaign I opening: the Vanguard lands, Vey sets off to light the fire
		"ashen_open": {"camp": "ashen", "map": 0, "bare": true,
			"cast": [
				{"id": "van", "team": 1, "u": [["tank", 2], ["rifle", 4], ["buggy", 2]], "at": [58, 40], "go": [39, 40]},
				{"id": "van2", "team": 1, "u": [["rifle", 3], ["lancer", 2], ["buggy", 1]], "at": [58, 21], "go": [40, 22]},
				{"id": "town", "team": 0, "b": ["refinery", "power", "barracks", "power"], "at": [15, 43]},
				{"id": "vey", "team": 0, "u": [["vey", 1]], "at": [10, 53]},
				{"id": "cell", "team": 0, "u": [["rifle", 4], ["pyro", 2], ["medic", 1]], "at": [9, 55]}],
			"shots": [
				{"d": 7.0, "cam": [36, 30, 36, -20, 38], "to": [42, 34, 32, 5, 34],
				 "title": ["Campaign I  ·  The Ashen Pact", "Embers of the Pact", ""], "place": "The Sable valley · dawn"},
				{"d": 7.0, "follow": "van", "cam": [0, 0, 13, 115, 22], "to": [0, 0, 11, 85, 18],
				 "say": ["vey", "They came at first light. Barges on the Sable."]},
				{"d": 6.5, "cam": [17, 46, 15, 35, 30], "to": [14, 45, 13, -5, 26],
				 "say": ["vey", "The foundry towns still sleep. No one has lit the fire."]},
				{"d": 6.5, "cam": [10, 54, 8, 25, 20], "to": [10, 53, 7, -10, 17],
				 "say": ["vey", "So we will. Cell, on me. Up Hollin's Rise."],
				 "do": [{"t": 3.0, "move": "vey", "to": [24, 31]}, {"t": 3.2, "move": "cell", "to": [23, 33]}]},
				{"d": 6.0, "follow": "cell", "cam": [0, 0, 12, -150, 26], "to": [0, 0, 13, -170, 30],
				 "say": ["vey", "One fire on the Rise, and the whole valley wakes."]},
				{"d": 6.5, "cam": [30, 28, 20, -40, 30], "to": [32, 26, 34, -20, 44],
				 "title": ["Embers of the Pact", "The Pact rises", ""]},
			]},

		# ---------------- Campaign I, mission 1 intro: Smoke on the River
		"ashen_1": {"camp": "ashen", "map": 0,
			"shots": [
				{"d": 5.0, "cam": [9, 53, 9, 20, 22], "to": [9, 53, 8, -10, 20], "place": "Hollin's Rise · dawn",
				 "say": ["vey", "The old signal tower is up on the Rise."]},
				{"d": 6.0, "cam": [17, 44, 15, -15, 32], "to": [24, 34, 15, -25, 32],
				 "say": ["vey", "Vanguard pickets on the slope. Clear them as we go."]},
				{"d": 5.5, "cam": [33, 19, 12, -40, 26], "to": [33, 18, 15, -10, 32],
				 "say": ["vey", "Light the fire, then hold until the militia comes."]},
				{"d": 2.5, "cam": [33, 18, 15, -10, 32], "to": [9, 53, 19, 0, 54]},
			]},

		# ---------------- Campaign II opening: a year later, the Directorate lands again
		"vanguard_open": {"camp": "vanguard", "map": 0, "bare": true,
			"cast": [
				{"id": "guns1", "team": 1, "b": ["turret", "turret", "power"], "at": [32, 50]},
				{"id": "guns2", "team": 1, "b": ["turret", "turret", "power"], "at": [52, 44]},
				{"id": "pact", "team": 1, "u": [["rifle", 3], ["pyro", 2]], "at": [33, 46]},
				{"id": "base", "team": 1, "b": ["hq", "rift", "power", "power", "refinery"], "at": [48, 13]},
				{"id": "harrow", "team": 0, "u": [["harrow", 1]], "at": [11, 57]},
				{"id": "wave", "team": 0, "u": [["rifle", 4], ["lancer", 2], ["buggy", 2]], "at": [12, 58]},
				{"id": "saint", "team": 0, "u": [["saint", 1]], "at": [6, 58]}],
			"shots": [
				{"d": 7.0, "cam": [30, 56, 32, 10, 30], "to": [24, 54, 28, -15, 28],
				 "title": ["Campaign II  ·  The Vanguard", "Iron Tide", "One year later"], "place": "Gull Strand · morning"},
				{"d": 6.0, "cam": [32, 50, 12, 150, 22], "to": [32, 50, 11, 175, 20],
				 "say": ["dace", "A year ago the Pact threw us into this sea."]},
				{"d": 6.0, "cam": [49, 15, 14, 30, 24], "to": [49, 15, 12, -5, 22],
				 "say": ["dace", "Now they build Rift Engines. Not one more."]},
				{"d": 6.0, "cam": [11, 56, 8, 25, 18], "to": [11, 55, 8, -10, 18],
				 "say": ["harrow", "Harrow. First wave is ashore, Marshal."],
				 "do": [{"t": 2.0, "move": "harrow", "to": [19, 47]}, {"t": 2.2, "move": "wave", "to": [20, 48]}]},
				{"d": 6.0, "cam": [7, 57, 7, -40, 15], "to": [8, 56, 8, -15, 18],
				 "say": ["dace", "Silence those guns, Captain. The Saint is behind you."],
				 "do": [{"t": 3.0, "move": "saint", "to": [16, 50]}]},
				{"d": 6.5, "follow": "wave", "cam": [0, 0, 16, -30, 30], "to": [0, 0, 30, -10, 42],
				 "title": ["Iron Tide", "The Directorate returns", ""]},
			]},
	}

## Puts the scene's cast on the map; returns {cast id: [Ent]}.
static func setup(S: Sim, sc: Dictionary) -> Dictionary:
	var cast := {}
	for c in sc.get("cast", []): spawn(S, cast, c)
	return cast

static func spawn(S: Sim, cast: Dictionary, c: Dictionary) -> void:
	var got: Array = cast.get(c.id, [])
	for t in c.get("b", []):
		var b := S.place_near(c.team, t, c.at[0], c.at[1])
		if b != null:
			b.born = -9.0; got.append(b)
	if c.has("u"): got.append_array(S.squad(c.team, c.u, c.at[0], c.at[1]))
	cast[c.id] = got
	if c.has("go"): act(S, cast, {"move": c.id, "to": c.go})

## Runs one timeline action on the sim. Sounds go through the host.
static func act(S: Sim, cast: Dictionary, a: Dictionary) -> void:
	if a.has("move"):
		var us: Array = cast.get(a.move, []).filter(func(e): return e.alive and e.kind == "u")
		S.group_move(us, a.to[0] * S.T + 16, a.to[1] * S.T + 16, "move")
	if a.has("spawn"): spawn(S, cast, a.spawn)
	if a.has("boom"): S.explode(a.boom[0] * S.T + 16, a.boom[1] * S.T + 16, a.get("s", 1.0))
	if a.has("sfx"): S.host.sfx(a.sfx)

## Middle of a cast group's living members, in world units, or null.
static func centre(cast: Dictionary, id: String):
	var n := 0; var p := Vector2()
	for e in cast.get(id, []):
		if e.alive: p += Vector2(e.x, e.y); n += 1
	return p / n if n else null
