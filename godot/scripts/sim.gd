class_name Sim
extends RefCounted
## The whole battle simulation, ported from the web version (world pixels, 32 per tile).
## Rendering, UI and audio are reached through `host`.

const T := 32
const MW := 64
const MH := 64
const TAU := PI * 2.0
const HN := MW * 2 + 1

var host  # main.gd
var time := 0.0
var ents: Array = []
var nid := 1
var terr := PackedByteArray()
var ore := PackedInt32Array()
var bmap := PackedInt32Array()
var vis := PackedByteArray()
var H := PackedFloat32Array()  # height grid, 2 samples per tile
var proj: Array = []
var parts: Array = []
var sel: Array = []
var over := false
var vis_t := 0.0
var ai_t := 2.0
var last_alert := -99.0
var ping = null  # {x,y,t}
var seed := 0
var stats := {"built": 0, "lost": 0, "killed": 0, "mined": 0}
var mission = null
var strikes: Array = []
var fields: Array = []        # crystal shard fields on the ground: {x, y, r, life, max, team, dps, tick, seed}
var aura_tick := 0.0
var combat := 0.0
var teams: Array = []
var diff := "normal"
var delayed: Array = []
var astar := AStarGrid2D.new()
var by_id := {}
# mission state
var p0 := Vector2i(9, 53)     # player start (tile)
var e0 = null                 # enemy base (Vector2i) or null
var theme := "temperate"
var dusk := false
var gi := 0                   # current goal
var g_t0 := 0.0               # when the current goal started
var gst := {}                 # current goal's progress (held seconds, trucks through, aurite at start)
var wst := {}                 # wave state of the current wave plan
var ev_done := {}
var m_t := 1.0
var end_why := ""

# ---------------- util ----------------
static func _u32(v: int) -> int:
	return v & 0xFFFFFFFF

static func _imul(a: int, b: int) -> int:
	a = a & 0xFFFFFFFF
	b = b & 0xFFFFFFFF
	var lo := (a & 0xFFFF) * b
	var hi := (((a >> 16) * b) & 0xFFFF) << 16
	return (lo + hi) & 0xFFFFFFFF

static func hash2(x: int, y: int, s: int) -> float:
	var h := _u32(_imul(x, 374761393) + _imul(y, 668265263) + _imul(s, 1442695041))
	h = _imul(h ^ (h >> 13), 1274126177)
	h = h ^ (h >> 16)
	return float(h) / 4294967296.0

static func vnoise(x: float, y: float, s: int) -> float:
	var xi := int(floor(x)); var yi := int(floor(y))
	var xf := x - xi; var yf := y - yi
	var u := xf * xf * (3 - 2 * xf); var v := yf * yf * (3 - 2 * yf)
	var a := hash2(xi, yi, s); var b := hash2(xi + 1, yi, s); var c := hash2(xi, yi + 1, s); var d := hash2(xi + 1, yi + 1, s)
	return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v

static func fbm(x: float, y: float, s: int) -> float:
	return vnoise(x, y, s) * 0.6 + vnoise(x * 2, y * 2, s + 7) * 0.28 + vnoise(x * 4, y * 4, s + 13) * 0.12

static func turn_to(a: float, b: float, m: float) -> float:
	var d := fposmod(b - a + PI, TAU) - PI
	if abs(d) <= m: return b
	return a + sign(d) * m

static func ang_diff(a: float, b: float) -> float:
	return abs(fposmod(b - a + PI, TAU) - PI)

static func inb(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < MW and y < MH

func walk(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < MW and y < MH and terr[y * MW + x] < D.ROCK and bmap[y * MW + x] == 0

func t_idx(e) -> int:
	return clampi(int(e.y / T), 0, MH - 1) * MW + clampi(int(e.x / T), 0, MW - 1)

func h_at(x: float, y: float) -> float:
	if H.is_empty(): return 0.0
	var gx: float = clamp(x / T * 2.0, 0.0, HN - 1.001)
	var gy: float = clamp(y / T * 2.0, 0.0, HN - 1.001)
	var i := int(gx); var j := int(gy)
	var fx := gx - i; var fy := gy - j
	return (H[j * HN + i] * (1 - fx) + H[j * HN + i + 1] * fx) * (1 - fy) + (H[(j + 1) * HN + i] * (1 - fx) + H[(j + 1) * HN + i + 1] * fx) * fy

func ud(e: Ent) -> Dictionary:
	return e.d

func is_air(e: Ent) -> bool:
	return e.kind == "u" and e.d.air

func avail(team: int, type: String) -> bool:
	var d: Dictionary = D.def_of(type)
	if d.fac != "" and teams.size() > team and d.fac != teams[team].fac: return false
	if teams.size() > team and d.no.has(teams[team].fac): return false
	if mission:
		var ts = mission.tech if team == 0 else mission.aiTech
		if ts != null and not (ts as Array).has(type): return false
	return true

func can_hit(sd: Dictionary, t: Ent) -> bool:
	var w: String = sd.weapon
	if w == "": return false
	if t.kind == "u" and t.d.air: return D.AIRW.has(w)
	return not sd.antiAir

# ---------------- map ----------------
func gen_map(sd: int) -> void:
	var s := sd % 9973
	var off := func(v: float) -> float: return 3 * sin((v - 63) * 0.09) + 1.5 * sin((v - 63) * 0.23)
	for y in MH:
		for x in MW:
			if y < x: continue
			var n1 := fbm(x / 8.0, y / 8.0, s + 1); var n2 := fbm(x / 5.0, y / 5.0, s + 2)
			var t := D.GRASS
			if n2 > 0.6: t = D.DIRT
			if n1 > 0.68: t = D.ROCK
			var sv := x + y
			var dv: float = abs((y - x) - off.call(float(sv))) / sqrt(2.0)
			if dv < 1.6: t = D.WATER
			elif dv < 2.6 and t != D.ROCK: t = D.SAND
			for f in [31, 63, 95]:
				if abs(sv - f) <= 3 and (t == D.WATER or t == D.ROCK): t = D.SAND
			terr[y * MW + x] = t
	var clear := func(cx: int, cy: int, r: int) -> void:
		for y in range(cy - r, cy + r + 1):
			for x in range(cx - r, cx + r + 1):
				if not inb(x, y) or y < x: continue
				if Vector2(x - cx, y - cy).length() <= r:
					var i := y * MW + x
					if terr[i] >= D.ROCK: terr[i] = D.GRASS
	clear.call(D.P0.x, D.P0.y, 7)
	var fields := [[18, 52, 3.4], [9, 42, 3.0], [22, 38, 3.2], [8, 20, 3.6], [31, 57, 2.8]]
	for f in fields:
		var fx: int = f[0]; var fy: int = f[1]; var r: float = f[2]
		clear.call(fx, fy, int(ceil(r)))
		for y in range(fy - 4, fy + 5):
			for x in range(fx - 4, fx + 5):
				if not inb(x, y) or y < x: continue
				var dd := Vector2(x - fx, y - fy).length() + (hash2(x, y, s + 5) - 0.5) * 1.3
				var i := y * MW + x
				if dd < r and terr[i] < D.ROCK:
					ore[i] = int(round((160 + (1 - dd / r) * 340) / 20.0)) * 20
					terr[i] = D.DIRT
	for y in MH:
		for x in MW:
			if y < x:
				var i := y * MW + x; var j := (MH - 1 - y) * MW + (MW - 1 - x)
				terr[i] = terr[j]; ore[i] = ore[j]
	# connectivity check base to base
	var seen := PackedByteArray(); seen.resize(MW * MH)
	var q := [D.P0.y * MW + D.P0.x]; seen[q[0]] = 1
	while q.size() > 0:
		var c: int = q.pop_back()
		var cx := c % MW; var cy := c / MW
		for dxy in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nx: int = cx + dxy[0]; var ny: int = cy + dxy[1]
			if not inb(nx, ny): continue
			var n := ny * MW + nx
			if seen[n] or terr[n] >= D.ROCK: continue
			seen[n] = 1; q.append(n)
	if not seen[(MH - 1 - D.P0.y) * MW + (MW - 1 - D.P0.x)]:
		var ax := MW - 1 - D.P0.x; var ay := MH - 1 - D.P0.y
		for k in 201:
			var f := k / 200.0
			var x := int(round(D.P0.x + (ax - D.P0.x) * f)); var y := int(round(D.P0.y + (ay - D.P0.y) * f))
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if not inb(x + dx, y + dy): continue
					var i := (y + dy) * MW + x + dx
					if terr[i] == D.ROCK: terr[i] = D.GRASS
					elif terr[i] == D.WATER: terr[i] = D.SAND

func gen_heights(sd: int) -> void:
	H = PackedFloat32Array(); H.resize(HN * HN)
	for j in HN:
		for i in HN:
			var xs := [(i - 1) / 2] if i % 2 else [i / 2 - 1, i / 2]
			var ys := [(j - 1) / 2] if j % 2 else [j / 2 - 1, j / 2]
			var all_r := true; var all_w := true; var any_r := false; var any_w := false
			for yy in ys:
				for xx in xs:
					var t: int = terr[clampi(yy, 0, MH - 1) * MW + clampi(xx, 0, MW - 1)]
					if t == D.ROCK: any_r = true
					else: all_r = false
					if t == D.WATER: any_w = true
					else: all_w = false
			var n := fbm(i / 7.0, j / 7.0, sd + 21)
			var h: float
			if all_r: h = 0.6 + n * 1.3 + (0.3 if (i % 2 and j % 2) else 0.0) + hash2(i, j, sd + 3) * 0.25
			elif all_w: h = -0.62 + hash2(i, j, sd + 4) * 0.1
			elif any_w: h = -0.1
			else: h = (n - 0.5) * 0.12 + (0.07 if any_r else 0.0)
			H[j * HN + i] = h

func init_astar() -> void:
	astar.region = Rect2i(0, 0, MW, MH)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for y in MH:
		for x in MW:
			var t: int = terr[y * MW + x]
			astar.set_point_solid(Vector2i(x, y), t >= D.ROCK)
			if t == D.SAND: astar.set_point_weight_scale(Vector2i(x, y), 1.15)

func _sync_solid(tx: int, ty: int, w: int, h: int) -> void:
	for y in range(ty, ty + h):
		for x in range(tx, tx + w):
			if inb(x, y): astar.set_point_solid(Vector2i(x, y), not walk(x, y))

# ---------------- setup ----------------
func new_game(d: String, opt: Dictionary) -> void:
	var M = opt.get("mission", null)
	mission = M
	diff = M.diff if M else d
	seed = M.seed if M else opt.get("seed", int(Time.get_ticks_msec() % 100000) + randi() % 1000)
	var pf: String = M.fac if M else opt.get("fac", "vanguard")
	var ef: String = opt.get("enemy", "") if not M else ""
	if ef == "random":
		var others: Array = D.FAC_ORDER.filter(func(f): return f != pf)
		ef = others[randi() % others.size()]
	if ef == "" or ef == pf or not D.FACS.has(ef): ef = "ashen" if pf == "vanguard" else "vanguard"
	time = 0.0; ents = []; nid = 1; proj = []; parts = []; sel = []; over = false; vis_t = 0.0; ai_t = 2.0; fields = []; aura_tick = 0.0
	last_alert = -99.0; ping = null; stats = {"built": 0, "lost": 0, "killed": 0, "mined": 0}; strikes = []; combat = 0.0; delayed = []; by_id = {}
	terr = PackedByteArray(); terr.resize(MW * MH)
	ore = PackedInt32Array(); ore.resize(MW * MH)
	bmap = PackedInt32Array(); bmap.resize(MW * MH)
	vis = PackedByteArray(); vis.resize(MW * MH)
	teams = []
	for id in [0, 1]:
		var prod := {}
		for c in D.CAT_ORDER: prod[c] = {"cur": "", "prog": 0.0, "paid": 0.0, "ready": false, "queue": [], "left": 0}
		teams.append({"id": id, "credits": float(M.credits[id] if M else D.DIFF[diff].start), "ai": id == 1,
			"fac": pf if id == 0 else ef, "pmade": 0, "pused": 0, "rally": null,
			"wave": 5, "waveT": 0, "wn": 0, "prod": prod, "noFundsT": 0.0, "earned": 0.0})
	if D.set_team_colors(teams[0].fac, teams[1].fac): Models.cache.clear()
	gi = 0; g_t0 = 0.0; gst = {}; wst = {}; ev_done = {}; m_t = 1.0; end_why = ""
	var A := Vector2i(MW - 1 - D.P0.x, MH - 1 - D.P0.y)
	if M:
		p0 = Vector2i(M.map.p0[0], M.map.p0[1])
		e0 = Vector2i(M.map.e0[0], M.map.e0[1]) if M.map.get("e0", null) != null else null
		theme = M.map.get("theme", "temperate"); dusk = M.map.get("dusk", false)
		MapGen.generate(self, M.map, seed, mission_keys(M))
	else:
		p0 = D.P0; e0 = A; theme = "temperate"; dusk = false
		gen_map(seed)
	gen_heights(seed)
	init_astar()
	if M: mission_setup(M)
	else:
		for pair in [[0, D.P0], [1, A]]:
			var tm: int = pair[0]; var p: Vector2i = pair[1]
			add_building(tm, "hq", p.x - 1, p.y - 1)
			var dir := 1 if tm == 0 else -1
			for k in 3: spawn_unit(tm, D.sub(teams[tm].fac, "rifle"), (p.x + dir * (2 + k)) * T + 16, (p.y - dir * 3) * T + 16)
			spawn_unit(tm, D.FACS[teams[tm].fac].lv, (p.x + dir * 3) * T + 16, (p.y - dir * 2) * T + 16)
	var er: Vector2i = e0 if e0 != null else Vector2i(MW - 1 - p0.x, MH - 1 - p0.y)
	teams[1].rally = Vector2((er.x - 6) * T, (er.y + 6) * T)
	update_vision()
	for e in ents:
		if e.kind == "b" and e.team == 0: e.born = -9.0

## Tiles that must be open ground and reachable: objectives, posts, captives, spawn points.
func mission_keys(M: Dictionary) -> Array:
	var k: Array = []
	for g in M.goals:
		if g.at != null: k.append([g.at[0], g.at[1], g.r + 0.5])
		if g.zone != null: k.append([g.zone[0], g.zone[1], 2.5])
		for z in g.zones: k.append([z[0], z[1], g.r + 0.5])
		if g.waves != null:
			for f in g.waves.from: k.append([f[0], f[1], 2.0])
		if g.done != null:
			if g.done.has("base"): k.append([g.done.base[0], g.done.base[1], 5.0])
			for sp in g.done.get("spawn", []): k.append([sp.at[0], sp.at[1], 2.0])
	for p in M.posts: k.append([p.at[0], p.at[1], 3.5])
	for c in M.captives: k.append([c.at[0], c.at[1], 2.5])
	for ev in M.events:
		for sp in ev.get("spawn", []): k.append([sp.at[0], sp.at[1], 2.0])
	return k

func mission_setup(M: Dictionary) -> void:
	if M.phq:
		add_building(0, "hq", p0.x - 1, p0.y - 1)
		if M.pbase.size(): prebuild(0, M.pbase)
	var c := p0 + (Vector2i(3, -3) if M.phq else Vector2i.ZERO)
	for h in M.pheroes:
		for u in squad(0, [[h, 1]], c.x, c.y): u.tag = "hero"
	if M.punits.size(): squad(0, M.punits, c.x, c.y)
	for u in squad(0, M.pvip, c.x, c.y): u.tag = "vip"
	if e0 != null and M.ehq != "":
		add_building(1, M.ehq, e0.x - 1, e0.y - 1)
		if M.ebase.size(): prebuild(1, M.ebase)
	if e0 != null:
		var ec: Vector2i = e0 + Vector2i(-3, 3)
		for h in M.eheroes:
			for u in squad(1, [[h, 1]], ec.x, ec.y): u.tag = "hero"
		if M.eunits.size(): squad(1, M.eunits, ec.x, ec.y)
	for pst in M.posts:
		var tm: int = pst.get("team", 1)
		for t in pst.get("b", []):
			var b := place_near(tm, t, pst.at[0], pst.at[1])
			if b != null:
				b.tag = pst.get("tag", ""); b.born = -9.0
		for u in squad(tm, pst.get("u", []), pst.at[0], pst.at[1]):
			u.post = true
			u.guard = Vector2(u.x, u.y)
	for cp in M.captives:
		for u in squad(0, cp.u, cp.at[0], cp.at[1]):
			u.captive = true; u.tag = "captive"; u.ang = randf() * TAU
	if M.swCh > 0:
		for e in ents:
			if e.team == 1 and e.kind == "b" and e.d.sw: e.ch = M.swCh
	calc_power()

## Puts a building on free open ground as close as possible to a tile (enemy posts, mission bases).
func place_near(team: int, type: String, cx: int, cy: int) -> Ent:
	var d: Dictionary = D.BLD[type]; var best = null; var bs := 1e9
	for ty in range(cy - 7, cy + 8):
		for tx in range(cx - 7, cx + 8):
			var ok := true
			for y in range(ty - 1, ty + d.h + 1):
				for x in range(tx - 1, tx + d.w + 1):
					var inside: bool = x >= tx and x < tx + d.w and y >= ty and y < ty + d.h
					if not inb(x, y):
						if inside: ok = false
						continue
					var i := y * MW + x
					if bmap[i]: ok = false
					elif inside and (terr[i] >= D.ROCK or ore[i] > 0): ok = false
				if not ok: break
			if not ok: continue
			var sc := Vector2(tx + d.w / 2.0 - cx, ty + d.h / 2.0 - cy).length() + randf() * 0.5
			if sc < bs: bs = sc; best = Vector2i(tx, ty)
	if best == null: return null
	return add_building(team, type, best.x, best.y)

func find_hq(team: int) -> Ent:
	for e in ents:
		if e.alive and e.team == team and e.kind == "b" and e.type == "hq": return e
	for e in ents:
		if e.alive and e.team == team and e.kind == "b": return e
	return null

func prebuild(team: int, list: Array) -> void:
	var hq := find_hq(team)
	if not hq: return
	if team == 0: update_vision()
	for t in list:
		var sp = ai_spot(team, t, hq)
		if sp != null:
			var b := add_building(team, t, sp.x, sp.y)
			b.born = -9.0
		if team == 0: update_vision()

func squad(team: int, list: Array, cx: int, cy: int) -> Array:
	var out: Array = []
	for pair in list:
		for k in pair[1]:
			var sl := slots_around(cx, cy, 12 + k)
			var p: Vector2i = sl[randi() % sl.size()] if sl.size() else Vector2i(cx, cy)
			out.append(spawn_unit(team, pair[0], p.x * T + 16, p.y * T + 16))
	return out

# ---------------- entities ----------------
func add_building(team: int, type: String, tx: int, ty: int) -> Ent:
	var d: Dictionary = D.BLD[type]
	var b := Ent.new()
	b.id = nid; nid += 1
	b.kind = "b"; b.type = type; b.d = d; b.team = team; b.tx = tx; b.ty = ty; b.w = d.w; b.h = d.h
	b.x = (tx + d.w / 2.0) * T; b.y = (ty + d.h / 2.0) * T; b.hp = d.hp; b.max_hp = d.hp
	b.tang = -PI / 4 if team == 0 else PI * 0.75
	b.seen = team == 0; b.r = max(d.w, d.h) * T / 2.0; b.born = time
	for y in range(ty, ty + d.h):
		for x in range(tx, tx + d.w): bmap[y * MW + x] = b.id
	_sync_solid(tx, ty, d.w, d.h)
	ents.append(b); by_id[b.id] = b
	for u in ents:
		if u.kind != "u" or not u.alive or u.d.air: continue
		var ux := int(u.x / T); var uy := int(u.y / T)
		if ux >= tx and ux < tx + d.w and uy >= ty and uy < ty + d.h:
			var n = nearest_walk(ux, uy, ux, uy + d.h)
			if n != null: u.x = n.x * T + 16; u.y = n.y * T + 16
			u.path = []
	if type == "refinery":
		var u := spawn_unit(team, "harv", (tx + 1) * T + 16, (ty + 3) * T + 16)
		u.hs = "find"
	if d.sw:
		b.ch = 0.0
		if team == 1 and time > 1:
			host.toast("Warning: enemy " + d.name + " detected", "warn"); host.sfx("alert")
	calc_power()
	host.on_world_changed()
	return b

func spawn_unit(team: int, type: String, x: float, y: float) -> Ent:
	var tx := int(x / T); var ty := int(y / T)
	var d: Dictionary = D.UN[type]
	if d.air:
		tx = clampi(tx, 0, MW - 1); ty = clampi(ty, 0, MH - 1)
	elif not walk(tx, ty):
		var n = nearest_walk(tx, ty, tx, ty)
		if n != null: tx = n.x; ty = n.y
	var u := Ent.new()
	u.id = nid; nid += 1
	u.kind = "u"; u.type = type; u.d = d; u.team = team; u.x = tx * T + 16; u.y = ty * T + 16
	u.hp = d.hp; u.max_hp = d.hp; u.ang = -PI / 2 if team == 0 else PI / 2; u.tang = u.ang
	u.scan = randf() * 0.4; u.hs = "find" if d.harv else ""; u.r = d.r
	ents.append(u); by_id[u.id] = u
	return u

func calc_power() -> void:
	for t in teams: t.pmade = 0; t.pused = 0
	for b in ents:
		if b.kind != "b" or not b.alive: continue
		var p: int = b.d.pwr
		if p > 0: teams[b.team].pmade += p
		else: teams[b.team].pused -= p

func low_power(t: int) -> bool:
	return teams[t].pused > teams[t].pmade

func count(team: int, type: String) -> int:
	var n := 0
	for e in ents:
		if e.alive and e.team == team and e.type == type: n += 1
	return n

func has_req(team: int, req: Array) -> bool:
	for r in req_of(team, req):
		if count(team, r) == 0: return false
	return true

## Requirements in the team's own buildings (the Choir's garden stands in for a refinery).
func req_of(team: int, req: Array) -> Array:
	if teams.size() <= team: return req
	var f: String = teams[team].fac
	return req.map(func(r): return D.sub(f, r) if D.sub(f, r) != "" else r)

## One-of-a-kind units (the Cantor): true when one is alive or already ordered.
func at_limit(team: int, type: String) -> bool:
	var d: Dictionary = D.def_of(type)
	if d.lim <= 0 or teams.size() <= team: return false
	var n := count(team, type)
	if d.has("cat") and teams[team].prod.has(d.cat):
		var q: Dictionary = teams[team].prod[d.cat]
		n += q.queue.count(type) + (1 if q.cur == type else 0)
	return n >= d.lim

func dist_to_ent(ax: float, ay: float, b) -> float:
	if b.kind == "b":
		var x0: float = b.tx * T; var y0: float = b.ty * T
		var cx: float = clamp(ax, x0, x0 + b.w * T); var cy: float = clamp(ay, y0, y0 + b.h * T)
		return Vector2(ax - cx, ay - cy).length()
	return max(0.0, Vector2(ax - b.x, ay - b.y).length() - b.r)

func visible_to_player(e: Ent) -> bool:
	if e.team == 0: return true
	if e.kind == "u" and e.under: return false
	return vis[t_idx(e)] == 2 if e.kind == "u" else e.seen

# ---------------- terrain-aware fire ----------------
## Height of the muzzle above the ground, and of the point a shooter aims at.
func muzzle_h(s: Ent) -> float:
	if s.kind == "b": return D.BH[s.type] * 0.75
	return D.ALT if s.d.air else D.UH[s.type] * 0.6

func aim_h(t: Ent) -> float:
	if t.kind == "b": return D.BH[t.type] * 0.5
	return D.ALT + 0.05 if t.d.air else D.UH[t.type] * 0.5

## True when no hill sits between the shooter and the target.
func line_clear(ax: float, ay: float, ha: float, bx: float, by: float, hb: float) -> bool:
	var L := Vector2(bx - ax, by - ay).length() / T
	var n := int(L * 3) + 1
	for i in range(1, n):
		var f := float(i) / n
		var px := ax + (bx - ax) * f; var py := ay + (by - ay) * f
		if h_at(px, py) > ha + (hb - ha) * f + 0.03: return false
	return true

func fire_clear(s: Ent, t: Ent) -> bool:
	var w: String = s.d.weapon
	if D.INDIRECT.has(w): return true
	return line_clear(s.x, s.y, h_at(s.x, s.y) + muzzle_h(s), t.x, t.y, h_at(t.x, t.y) + aim_h(t))

## Cached version for units (re-checked a few times a second).
func has_shot(s: Ent, t: Ent, dt: float) -> bool:
	s.los_t -= dt
	if s.los_of != t or s.los_t <= 0:
		s.los_of = t; s.los_t = 0.25; s.los_ok = fire_clear(s, t)
	return s.los_ok

# ---------------- pathfinding ----------------
func nearest_walk(gx: int, gy: int, sx: int, sy: int):
	for r in 14:
		var best = null; var bd := 1e9
		for y in range(gy - r, gy + r + 1):
			for x in range(gx - r, gx + r + 1):
				if max(abs(x - gx), abs(y - gy)) != r: continue
				if not walk(x, y): continue
				var dd := (x - sx) * (x - sx) + (y - sy) * (y - sy)
				if dd < bd: bd = dd; best = Vector2i(x, y)
		if best != null: return best
	return null

func find_path(sx: int, sy: int, gx: int, gy: int) -> Array:
	sx = clampi(sx, 0, MW - 1); sy = clampi(sy, 0, MH - 1)
	if not walk(gx, gy):
		var n = nearest_walk(gx, gy, sx, sy)
		if n == null: return []
		gx = n.x; gy = n.y
	if sx == gx and sy == gy: return []
	var sp := Vector2i(sx, sy)
	var was_solid := astar.is_point_solid(sp)
	if was_solid: astar.set_point_solid(sp, false)
	var ids := astar.get_id_path(sp, Vector2i(gx, gy), true)
	if was_solid: astar.set_point_solid(sp, true)
	var out: Array = []
	for k in range(1, ids.size()): out.append(ids[k])
	return smooth(sx, sy, out)

func los(ax: int, ay: int, bx: int, by: int) -> bool:
	var dx := bx - ax; var dy := by - ay
	var L := sqrt(dx * dx + dy * dy); var n := int(ceil(L * 3))
	if n == 0: return true
	var px := -dy / L * 0.38; var py := dx / L * 0.38
	for i in range(1, n + 1):
		var f := float(i) / n
		var x := ax + 0.5 + dx * f; var y := ay + 0.5 + dy * f
		if not walk(int(floor(x)), int(floor(y))) or not walk(int(floor(x + px)), int(floor(y + py))) or not walk(int(floor(x - px)), int(floor(y - py))): return false
	return true

func smooth(sx: int, sy: int, p: Array) -> Array:
	if p.size() < 3: return p
	var out: Array = []; var cx := sx; var cy := sy; var i := 0
	while i < p.size():
		var j := mini(p.size() - 1, i + 14)
		while j > i and not los(cx, cy, p[j].x, p[j].y): j -= 1
		out.append(p[j]); cx = p[j].x; cy = p[j].y; i = j + 1
	return out

func route(u: Ent, tx: int, ty: int) -> Array:
	if u.d.air:
		tx = clampi(tx, 0, MW - 1); ty = clampi(ty, 0, MH - 1)
		return [] if (int(u.x / T) == tx and int(u.y / T) == ty) else [Vector2i(tx, ty)]
	return find_path(int(u.x / T), int(u.y / T), tx, ty)

func set_path(u: Ent, tx: int, ty: int) -> void:
	u.path = route(u, tx, ty); u.dest = Vector2i(tx, ty); u.stuck = 0; u.fspd = 0.0

# ---------------- orders ----------------
func slots_around(tx: int, ty: int, n: int) -> Array:
	if not walk(tx, ty):
		var w = nearest_walk(tx, ty, tx, ty)
		if w == null: return []
		tx = w.x; ty = w.y
	var out: Array = []; var seen := {ty * MW + tx: true}; var q := [Vector2i(tx, ty)]; var qi := 0
	while qi < q.size() and out.size() < n:
		var c: Vector2i = q[qi]; qi += 1
		out.append(c)
		for dxy in [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, -1], [1, -1], [-1, 1]]:
			var nx: int = c.x + dxy[0]; var ny: int = c.y + dxy[1]; var k := ny * MW + nx
			if not seen.has(k) and walk(nx, ny):
				seen[k] = true; q.append(Vector2i(nx, ny))
	return out

## formation rank: 0 armor up front, 1 infantry, 2 support and artillery at the back, 3 air
func rank_of(u: Ent) -> int:
	var d := u.d
	if d.air: return 3
	if d.heal or d.eng or d.harv or d.minr > 0: return 2
	return 1 if d.armor == "inf" else 0

func free_tile(x: float, y: float, used: Dictionary, air: bool):
	var xi := int(round(x)); var yi := int(round(y))
	for r in 8:
		for yy in range(yi - r, yi + r + 1):
			for xx in range(xi - r, xi + r + 1):
				if max(abs(xx - xi), abs(yy - yi)) != r: continue
				if not inb(xx, yy): continue
				var k := yy * MW + xx
				if used.has(k): continue
				if not air and not walk(xx, yy): continue
				used[k] = true
				return Vector2i(xx, yy)
	return null

## Plan formation slots without issuing orders (used for the drag preview too).
## face: optional facing angle; width: optional front width in tiles.
func plan_formation(movers: Array, wx: float, wy: float, face = null, width := 0.0) -> Array:
	var tx := clampi(int(wx / T), 0, MW - 1); var ty := clampi(int(wy / T), 0, MH - 1)
	if movers.size() <= 1:
		return [[movers[0], Vector2i(tx, ty)]] if movers.size() else []
	var cx := 0.0; var cy := 0.0
	for u in movers: cx += u.x; cy += u.y
	cx /= movers.size(); cy /= movers.size()
	var dir: float
	if face != null: dir = face
	else:
		dir = atan2(wy - cy, wx - cx)
		if Vector2(wx - cx, wy - cy).length() < T * 1.5: dir = movers[0].ang
	var fx := cos(dir); var fy := sin(dir); var rx := -fy; var ry := fx
	var ranks := [[], [], [], []]
	for u in movers: ranks[rank_of(u)].append(u)
	var used := {}
	var wide := maxi(3, int(ceil(sqrt(movers.size()) * 1.4)))
	if width > 1.5: wide = clampi(int(round(width / 1.3)) + 1, 2, movers.size())
	var row := 0; var plan: Array = []
	for rk in [0, 1, 2, 3]:
		var list: Array = ranks[rk]
		if list.is_empty(): continue
		var sp := 1.5 if rk == 0 else (1.6 if rk == 3 else 1.1)
		list.sort_custom(func(a, b): return ((a.x - cx) * rx + (a.y - cy) * ry) < ((b.x - cx) * rx + (b.y - cy) * ry))
		var i := 0
		while i < list.size():
			var chunk := list.slice(i, i + wide); var n := chunk.size()
			for j in n:
				var lat := (j - (n - 1) / 2.0) * sp; var back := row * (1.5 if rk == 0 else 1.15)
				var px := wx / T - 0.5 + rx * lat - fx * back; var py := wy / T - 0.5 + ry * lat - fy * back
				var sl = free_tile(px, py, used, rk == 3)
				plan.append([chunk[j], sl if sl != null else Vector2i(tx, ty)])
			row += 1; i += wide
	return plan

const STRAGGLE := 8.0
var formation := true   # off: every unit heads straight for the nearest free tile, no ranks, own speed

func group_move(units: Array, wx: float, wy: float, order: String, face = null, width := 0.0) -> void:
	if units.is_empty(): return
	var fighters := units.filter(func(u): return u.d.dmg > 0 and not u.d.air)
	var escorts: Array = []
	if order == "amove" and fighters.size():
		escorts = units.filter(func(u): return u.d.heal > 0 or u.d.eng)
	var movers := units.filter(func(u): return not escorts.has(u))
	var plan: Array
	var form: bool = formation or units[0].team != 0   # the toggle is the player's; the AI always forms up
	if form: plan = plan_formation(movers, wx, wy, face, width)
	else:
		plan = []; var used := {}
		movers.sort_custom(func(a, b): return Vector2(a.x - wx, a.y - wy).length() < Vector2(b.x - wx, b.y - wy).length())
		for u in movers:
			var sl = free_tile(wx / T - 0.5, wy / T - 0.5, used, u.d.air)
			plan.append([u, sl if sl != null else Vector2i(clampi(int(wx / T), 0, MW - 1), clampi(int(wy / T), 0, MH - 1))])
	for p in plan:
		var u: Ent = p[0]; var sl: Vector2i = p[1]
		if u.intun > 0:
			u.tun.dest = sl; u.tun.order = order; u.face = face; continue
		u.order = order; u.target = null; u.auto = false; u.guard = null; u.face = face
		if u.d.harv: u.hs = "manual"
		set_path(u, sl.x, sl.y)
		plan_tunnel(u, sl)
	if plan.size() > 1 and form:
		# shared pace: the main body arrives together (aircraft fly ahead). Units far behind the main
		# body (STRAGGLE tiles more to travel than the median) don't hold it back: they go at full speed.
		var ground: Array = []
		for p in plan:
			if not p[0].d.air and p[0].path.size() and p[0].tun == null: ground.append(p[0])
		var lens: Array = []
		for u in ground:
			var L := 0.0; var x: float = u.x; var y: float = u.y
			for c in u.path:
				var px: float = c.x * T + 16; var py: float = c.y * T + 16
				L += Vector2(px - x, py - y).length(); x = px; y = py
			u.path_len = L; lens.append(L)
		lens.sort()
		var med: float = lens[lens.size() / 2] if lens.size() else 0.0
		var body := ground.filter(func(u): return u.path_len <= med + STRAGGLE * T)
		var eta := 0.0
		for u in body: eta = max(eta, u.path_len / (u.d.spd * T))
		if eta > 0 and body.size() > 1:
			for u in body: u.fspd = max(u.d.spd * 0.35, min(u.d.spd, u.path_len / eta / T))
	for u in escorts:
		u.order = "escort"; u.esc = fighters.duplicate(); u.ecx = wx; u.ecy = wy; u.target = null; u.path = []; u.rp = 0.0; u.fspd = 0.0

func follow_esc(u: Ent, dt: float) -> bool:
	var es := u.esc.filter(func(e): return e.alive)
	if es.is_empty():
		u.order = "none"; u.esc = []
		if u.ecx != null:
			set_path(u, int(u.ecx / T), int(u.ecy / T)); u.order = "move"
		return move_unit(u, dt)
	var best: Ent = null; var bd := 1e9
	for e in es:
		var dd: float = Vector2(e.x - u.x, e.y - u.y).length() * (1.0 if e.d.armor == "inf" else 1.6)
		if dd < bd: bd = dd; best = e
	var tx := best.x - cos(best.ang) * T * 1.1; var ty := best.y - sin(best.ang) * T * 1.1
	if Vector2(tx - u.x, ty - u.y).length() > T * 1.3:
		u.rp -= dt
		if u.rp <= 0 or u.path.is_empty():
			u.rp = 0.6; u.path = route(u, int(tx / T), int(ty / T))
		return move_unit(u, dt)
	u.path = []
	return false

func attack_order(units: Array, t: Ent) -> void:
	for u in units:
		if u.d.dmg == 0 or not can_hit(u.d, t) or u.intun > 0: continue
		u.order = "attack"; u.target = t; u.auto = false; u.path = []; u.rp = 0.0; u.face = null; u.tun = null

func eng_order(us: Array, b: Ent) -> void:
	for u in us:
		if u.intun > 0: continue
		u.tun = null
		u.order = "capture"; u.target = b; u.path = []; u.rp = 0.0

# ---------------- Hollow Choir tunnels ----------------
## Burrows and the Choir's Command Yard are linked underground: a unit walks into the one nearest to it
## and comes out of the one nearest its destination, when that is clearly shorter than walking.
func is_tun(b: Ent) -> bool:
	return b.alive and b.kind == "b" and (b.d.tun or (b.type == "hq" and teams[b.team].fac == "choir"))

func tun_exit(b: Ent) -> Vector2i:
	var gx: int = b.tx + (b.w >> 1); var gy: int = b.ty + b.h
	var n = nearest_walk(gx, gy, gx, gy + 1)
	return n if n != null else Vector2i(gx, gy)

func plan_tunnel(u: Ent, dest: Vector2i) -> void:
	u.tun = null
	if u.d.air or u.d.harv or teams[u.team].fac != "choir" or u.captive: return
	var A: Ent = null; var B: Ent = null; var da := 1e9; var db := 1e9
	var dx := dest.x * T + 16.0; var dy := dest.y * T + 16.0
	for b in ents:
		if b.team != u.team or not is_tun(b): continue
		var a := Vector2(b.x - u.x, b.y - u.y).length()
		if a < da: da = a; A = b
		var c := Vector2(b.x - dx, b.y - dy).length()
		if c < db: db = c; B = b
	if A == null or A == B: return
	var direct := Vector2(dx - u.x, dy - u.y).length()
	if da + db + T * 4 >= direct * 0.75: return
	u.tun = {"a": A, "b": B, "dest": dest, "order": u.order}
	var ex := tun_exit(A)
	u.path = route(u, ex.x, ex.y); u.stuck = 0; u.fspd = 0.0

## Runs the tunnel trip. True while the unit is underground (nothing else to update).
func tunnel_tick(u: Ent, dt: float) -> bool:
	var tn: Dictionary = u.tun
	var A: Ent = tn.a; var B: Ent = tn.b
	if u.intun > 0:
		u.intun -= dt
		if u.intun <= 0 or (not A.alive and not B.alive): _emerge(u)
		return true
	if not A.alive or not B.alive:
		u.tun = null
		if u.target == null: set_path(u, tn.dest.x, tn.dest.y)
		return false
	if u.target != null or not u.path.is_empty(): return false
	if dist_to_ent(u.x, u.y, A) < T * 2.5:
		u.intun = 0.8 + Vector2(B.x - A.x, B.y - A.y).length() / (T * 14.0)
		u.under = true; u.moving = false; u.sel = false; _drop_sel(u)
		_dig(u.x, u.y, 6); host.sfx("burrow", u.x, u.y)
		return true
	u.tun = null
	return false

func _emerge(u: Ent) -> void:
	var tn: Dictionary = u.tun
	var out: Ent = tn.b if tn.b.alive else (tn.a if tn.a.alive else null)
	if out != null:
		var ex := tun_exit(out)
		var sl := slots_around(ex.x, ex.y, 1 + randi() % 4)
		var p: Vector2i = sl[-1] if sl.size() else ex
		u.x = p.x * T + 16; u.y = p.y * T + 16
	u.intun = 0.0; u.under = false; u.tun = null; u.lx = u.x; u.ly = u.y
	u.order = tn.order if tn.order != "none" else "move"
	set_path(u, tn.dest.x, tn.dest.y)
	_dig(u.x, u.y, 6); host.sfx("burrow", u.x, u.y)

func _dig(x: float, y: float, n: int) -> void:
	for k in n:
		var a := randf() * TAU
		parts.append({"k": "smoke", "x": x + cos(a) * 6, "y": y + sin(a) * 6, "vx": cos(a) * 26, "vy": sin(a) * 26, "life": 0.6, "max": 0.6, "s": 3.0, "c": Color8(122, 104, 78)})

# ---------------- Hollow Choir shard fields ----------------
func add_field(x: float, y: float, r: float, life: float, team: int, dps: float) -> void:
	fields.append({"x": x, "y": y, "r": r, "life": life, "max": life, "team": team, "dps": dps, "tick": 0.0, "seed": randi() % 1000})

func upd_fields(dt: float) -> void:
	if fields.is_empty(): return
	for f in fields:
		f.life -= dt; f.tick -= dt
		if f.tick > 0: continue
		f.tick = 0.25
		for o in ents:
			if not o.alive or o.kind != "u" or o.team == f.team or o.d.air or o.under or o.captive: continue
			if Vector2(o.x - f.x, o.y - f.y).length() < f.r: damage(o, f.dps * 0.25, "shard", null)
	fields = fields.filter(func(f): return f.life > 0)

## Cantors lift every friendly unit around them; a faint ring shows the reach.
func upd_auras(dt: float) -> void:
	aura_tick -= dt
	if aura_tick > 0: return
	aura_tick = 0.5
	for c in ents:
		if not c.alive or c.kind != "u" or c.d.aura <= 0 or c.intun > 0 or c.captive: continue
		var R: float = c.d.aura * T
		for o in ents:
			if o.alive and o.kind == "u" and o.team == c.team and o != c and Vector2(o.x - c.x, o.y - c.y).length() < R: o.aura_t = 0.7
		if int(time * 2) % 3 == 0: parts.append({"k": "aura", "x": c.x, "y": c.y, "life": 1.3, "max": 1.3, "R": R})

## Crystal garden: every 4 s it yields 40 aurite on its own and drinks up to 80 more from the ore within 5 tiles.
func upd_garden(b: Ent, tm: Dictionary, dt: float) -> void:
	b.gt += dt
	if b.gt < 4.0: return
	b.gt -= 4.0
	var want := 80; var got := 0; var shown := 0
	var cx: float = b.tx + b.w / 2.0; var cy: float = b.ty + b.h / 2.0
	for ty in range(int(cy) - 6, int(cy) + 6):
		for tx in range(int(cx) - 6, int(cx) + 6):
			if got >= want or not inb(tx, ty): continue
			var i := ty * MW + tx
			if ore[i] <= 0 or Vector2(tx + 0.5 - cx, ty + 0.5 - cy).length() > 5.5: continue
			var take := mini(ore[i], want - got); ore[i] -= take; got += take
			if shown < 4 and (b.team == 0 or visible_to_player(b)):
				shown += 1
				parts.append({"k": "gem", "x": tx * T + 16.0, "y": ty * T + 16.0, "bx": b.x, "by": b.y, "ah": h_at(tx * T + 16.0, ty * T + 16.0) + .05, "bh": h_at(b.x, b.y) + 1.0, "life": .9, "max": .9, "s": .07 + randf() * .04})
	var amt: float = (40.0 + got) * (0.5 if low_power(b.team) else 1.0)
	tm.credits += amt * (D.DIFF[diff].inc if tm.ai else 1.0); tm.earned += amt
	b.unload_t = time
	if b.team == 0:
		stats.mined += int(amt)
		parts.append({"k": "txt", "x": b.x, "y": b.y, "txt": "+%d" % int(amt), "c": Color("f0b93f"), "life": 1.6, "max": 1.6, "h": 1.5})

# ---------------- simulation ----------------
func find_target(src: Ent, rng: float) -> Ent:
	var best: Ent = null; var bs := 1e9
	var sd: Dictionary = src.d
	var bld_src := src.kind == "b"
	for o in ents:
		if not o.alive or o.team == src.team or o.captive or o.under: continue
		if src.team == 0 and not visible_to_player(o): continue
		if not can_hit(sd, o): continue
		var dd := dist_to_ent(src.x, src.y, o)
		if dd > rng: continue
		var s := dd + ((T * 7 if o.type == "wall" else T * 3) if o.kind == "b" else 0) + (T if (o.kind == "u" and o.d.harv) else 0)
		if s >= bs: continue
		if not D.INDIRECT.has(sd.weapon):
			var clear := fire_clear(src, o)
			if bld_src and not clear: continue
			if not clear:
				s += T * 4
				if s >= bs: continue
		bs = s; best = o
	return best

func fire(s: Ent, t: Ent, d: Dictionary) -> void:
	var ang := atan2(t.y - s.y, t.x - s.x)
	var mr := (s.r if s.kind == "u" else 12.0) + 2
	var mx := s.x + cos(ang) * mr; var my := s.y + sin(ang) * mr
	var ox := 0.0; var oy := 0.0
	if t.kind == "b":
		ox = (randf() - 0.5) * t.w * T * 0.6; oy = (randf() - 0.5) * t.h * T * 0.6
	s.flash = 0.08
	var hs := muzzle_h(s); var htg := aim_h(t)
	if t.team == 0 or s.team == 0: combat = min(1.0, combat + 0.04)
	var w: String = d.weapon
	if w == "bullet" or w == "snipe" or w == "rail" or w == "shard":
		var sn := w == "snipe" or w == "rail"; var sh := w == "shard"
		var lf := 0.18 if sn else (0.1 if sh else 0.07)
		parts.append({"k": "tracer", "x": mx, "y": my, "x2": t.x + ox + (randf() - 0.5) * 6, "y2": t.y + oy + (randf() - 0.5) * 6, "life": lf, "max": lf, "ha": h_at(mx, my) + hs, "hb": h_at(t.x, t.y) + htg, "c": 2 if sh else (1 if sn else 0)})
		parts.append({"k": "spark", "x": t.x + ox, "y": t.y + oy, "vx": (randf() - 0.5) * 60, "vy": (randf() - 0.5) * 60, "life": 0.15, "max": 0.15, "c": Color("#9dffb4") if sh else Color("#ffe7a0"), "s": 1.5, "h0": h_at(t.x, t.y) + htg})
		host.sfx("shard" if sh else ("snipe" if sn else "gun"), s.x, s.y)
		damage(t, d.dmg, w, s)
	elif w == "charge":
		# the sapper sets a crystal charge against the target and steps back
		explode(t.x + ox * 0.5, t.y + oy * 0.5, 14)
		for k in 6: parts.append({"k": "spark", "x": t.x, "y": t.y, "vx": (randf() - 0.5) * 90, "vy": (randf() - 0.5) * 90, "life": 0.4, "max": 0.4, "c": Color("#9dffb4"), "s": 2.2})
		host.sfx("boom", s.x, s.y)
		damage(t, d.dmg, w, s)
	elif w == "flame":
		for i in 5:
			var f := 0.3 + i * 0.17
			parts.append({"k": "flame", "x": mx + (t.x - mx) * f * 0.4, "y": my + (t.y - my) * f * 0.4, "vx": (t.x - mx) * 1.6 + (randf() - 0.5) * 30, "vy": (t.y - my) * 1.6 + (randf() - 0.5) * 30, "life": 0.35 + randf() * 0.15, "max": 0.5, "s": 3.0 + i})
		host.sfx("flame", s.x, s.y)
		damage(t, d.dmg, "flame", s)
	elif w == "arc":
		var hit: Array = [t]; var cur := t
		for j in 2:
			var nb: Ent = null; var bd := T * 2.6
			for o in ents:
				if not o.alive or o.team == s.team or hit.has(o) or o.kind != "u" or o.d.air: continue
				var dd := Vector2(o.x - cur.x, o.y - cur.y).length()
				if dd < bd: bd = dd; nb = o
			if nb == null: break
			hit.append(nb); cur = nb
		var px := mx; var py := my; var ph = h_at(mx, my) + hs
		for j in hit.size():
			var o: Ent = hit[j]
			parts.append({"k": "arc", "x": px, "y": py, "x2": o.x, "y2": o.y, "ha": ph, "life": 0.22, "max": 0.22, "seed": randf() * 99})
			px = o.x; py = o.y; ph = null
			damage(o, d.dmg * (0.6 if j else 1.0), "arc", s)
		host.sfx("arc", s.x, s.y)
	else:
		var arty := D.INDIRECT.has(w)   # lobbed: Howler mortar shells, Geode Lobber crystals
		if arty: ox += (randf() - 0.5) * 30; oy += (randf() - 0.5) * 30
		var p := {"x": mx, "y": my, "t": t, "ox": ox, "oy": oy, "tx": t.x + ox, "ty": t.y + oy, "w": w, "dmg": d.dmg, "src": s, "src_team": s.team,
			"spd": 440.0 if w == "shell" else (230.0 if arty else (560.0 if w == "flak" else (330.0 if w == "spine" else 290.0))), "ang": ang, "fixed": arty, "lob": arty, "splash": d.splash,
			"y0": h_at(mx, my) + hs, "y1": h_at(t.x + ox, t.y + oy) + (0.05 if arty else htg), "aim": 0.05 if arty else htg, "dead": false}
		p.d0 = max(1.0, Vector2(p.tx - mx, p.ty - my).length())
		p.apex = ballistic_apex(p) if arty else 0.0
		p.h = p.y0
		proj.append(p)
		var snd: String = w
		if w == "arty": snd = "mortar"
		elif w == "spine": snd = "shard"
		elif s.type == "bulwark" or s.type == "bastion" or s.type == "saint": snd = "heavy"
		host.sfx(snd, s.x, s.y)

## A real lob: the apex is high enough for the shell to clear every hill on the way.
func ballistic_apex(p: Dictionary) -> float:
	var base: float = min(3.5, p.d0 / T * 0.45)
	var apex := base
	var n := int(p.d0 / T * 3) + 2
	for i in range(1, n):
		var f := float(i) / n
		var gx: float = p.x + (p.tx - p.x) * f; var gy: float = p.y + (p.ty - p.y) * f
		var need: float = h_at(gx, gy) + 0.35 - lerp(float(p.y0), float(p.y1), f)
		var k := 4.0 * f * (1.0 - f)
		if k > 0.05: apex = max(apex, need / k)
	return apex

func damage(t: Ent, dmg: float, w: String, src) -> void:
	if not t.alive or t.captive or t.under: return
	var arm: String = "bld" if t.kind == "b" else t.d.armor
	t.hp -= dmg * D.MOD[w][arm]; t.hit_t = 3.0
	if t.team == 0: combat = min(1.0, combat + 0.05)
	if src != null and src.alive and t.kind == "u" and t.target == null and t.order == "none" and t.d.dmg > 0 and can_hit(t.d, src):
		t.target = src; t.auto = true
		if t.guard == null: t.guard = Vector2(t.x, t.y)
	if t.team == 0 and time - last_alert > 20:
		last_alert = time; ping = {"x": t.x, "y": t.y, "t": time}
		host.toast("Base under attack" if t.kind == "b" else ("Harvester under attack" if t.d.harv else "Units under attack"), "warn"); host.sfx("alert")
	if t.hp <= 0: kill(t)

func kill(e: Ent) -> void:
	e.alive = false; e.sel = false
	if e.kind == "u" and e.d.hero:
		host.toast(e.d.name + (" is down!" if e.team == 0 else " destroyed"), "warn" if e.team == 0 else "gold"); host.sfx("alert" if e.team == 0 else "ready")
	elif e.tag == "vip" and e.team == 0:
		host.toast(e.d.name + " lost", "warn")
	if e.team == 0: stats.lost += 1
	else: stats.killed += 1
	if e.kind == "b":
		for y in range(e.ty, e.ty + e.h):
			for x in range(e.tx, e.tx + e.w):
				if bmap[y * MW + x] == e.id: bmap[y * MW + x] = 0
		_sync_solid(e.tx, e.ty, e.w, e.h)
		e.end_kind = "die"; e.end_t = time
		if e.type == "wall":
			explode(e.x, e.y, 10); calc_power(); _drop_sel(e); host.on_world_changed(); return
		for k in e.w * e.h:
			delayed.append([time + k * 0.09, e.tx * T + randf() * e.w * T, e.ty * T + randf() * e.h * T, 18 + randf() * 10])
		host.add_scorch(e.x, e.y, e.w * T * 0.6); calc_power(); host.sfx("boom", e.x, e.y); host.on_world_changed()
	else:
		if e.d.armor == "inf":
			for k in 6: parts.append({"k": "smoke", "x": e.x, "y": e.y, "vx": (randf() - 0.5) * 20, "vy": (randf() - 0.5) * 20, "life": 0.6, "max": 0.6, "s": 3.0, "c": Color8(120, 110, 100)})
			parts.append({"k": "body", "x": e.x, "y": e.y, "life": 6.0, "max": 6.0, "c": D.TEAMC[e.team].dk, "rot": randf() * TAU})
		else:
			explode(e.x, e.y, e.r * 1.6)
			if not e.d.air: host.add_scorch(e.x, e.y, e.r * 1.2)
			else:
				for p in parts.slice(-8):
					if p.k == "debris": p.h = 1.5
			host.sfx("boom", e.x, e.y)
	_drop_sel(e)

func _drop_sel(e: Ent) -> void:
	if sel.has(e):
		sel.erase(e); host.on_sel_changed()

func explode(x: float, y: float, s: float) -> void:
	parts.append({"k": "flash", "x": x, "y": y, "life": 0.25, "max": 0.25, "s": s})
	for i in 10:
		var a := randf() * TAU; var v := 40 + randf() * 120
		parts.append({"k": "spark", "x": x, "y": y, "vx": cos(a) * v, "vy": sin(a) * v, "life": 0.3 + randf() * 0.3, "max": 0.6, "c": Color("#ffcf6a") if randf() < 0.5 else Color("#ff8a3a"), "s": 2.0})
	for i in 6:
		parts.append({"k": "smoke", "x": x + (randf() - 0.5) * s, "y": y + (randf() - 0.5) * s, "vx": (randf() - 0.5) * 20, "vy": -10 - randf() * 20, "life": 1 + randf(), "max": 2.0, "s": s * 0.4, "c": Color8(50, 46, 42)})
	var nd := mini(8, 2 + int(s / 6))
	for i in nd:
		var a := randf() * TAU; var v := 30 + randf() * 70
		parts.append({"k": "debris", "x": x, "y": y, "vx": cos(a) * v, "vy": sin(a) * v, "h": 0.3, "vh": 2 + randf() * 3, "life": 1.6 + randf(), "max": 2.6, "s": 0.05 + randf() * 0.07, "r0": randf() * 6})

func move_unit(u: Ent, dt: float) -> bool:
	if u.path.is_empty():
		u.fspd = 0.0; return false
	var d := u.d
	var c: Vector2i = u.path[0]
	var px := c.x * T + 16.0; var py := c.y * T + 16.0
	var dx := px - u.x; var dy := py - u.y; var dist := sqrt(dx * dx + dy * dy)
	var inf: bool = d.armor == "inf"; var want := atan2(dy, dx)
	var sp: float = (u.fspd if u.fspd > 0 else d.spd) * T * dt * (0.85 if (not d.air and terr[t_idx(u)] == D.SAND) else 1.0)
	if dist > 1:
		u.ang = turn_to(u.ang, want, (18.0 if inf else (7.0 if d.spd > 2 else 3.6)) * dt)
		if not inf and ang_diff(u.ang, want) > 0.7: sp *= 0.15
	if d.turret and u.target == null: u.tang = turn_to(u.tang, u.ang, 3 * dt)
	if dist <= sp:
		u.x = px; u.y = py; u.path.pop_front()
		if not d.air and u.path.size() and not walk(u.path[0].x, u.path[0].y):
			var l: Vector2i = u.path[-1]; set_path(u, l.x, l.y)
	else:
		u.x += dx / dist * sp; u.y += dy / dist * sp
	u.stuck_t += dt
	if not d.air and u.stuck_t > 1:
		if Vector2(u.x - u.lx, u.y - u.ly).length() < 6 and u.path.size():
			u.stuck += 1
			if u.stuck >= 3: u.path = []; u.stuck = 0
			else:
				var l: Vector2i = u.path[-1]; u.path = route(u, l.x, l.y)
		else: u.stuck = 0
		u.lx = u.x; u.ly = u.y; u.stuck_t = 0.0
	return true

func upd_unit(u: Ent, dt: float) -> void:
	var d := u.d
	u.cd -= dt
	if u.flash > 0: u.flash -= dt
	if u.hit_t > 0: u.hit_t -= dt
	if u.captive:
		u.moving = false; return
	if u.tun != null and tunnel_tick(u, dt): return
	if u.aura_t > 0:
		u.aura_t -= dt; u.cd -= dt * 0.3
		if u.hp < u.max_hp: u.hp = min(u.max_hp, u.hp + u.max_hp * 0.01 * dt)
	if d.hero and u.hp < u.max_hp and u.hit_t <= 0: u.hp = min(u.max_hp, u.hp + u.max_hp * 0.02 * dt)
	if d.harv:
		upd_harv(u, dt); u.moving = move_unit(u, dt); return
	if d.heal: upd_medic(u, dt); return
	if d.eng: upd_eng(u, dt); return
	if u.target != null and (not u.target.alive or u.target.under or not can_hit(d, u.target) or (u.team == 0 and not visible_to_player(u.target) and u.order != "attack")):
		u.target = null
		if u.order == "attack": u.order = "none"; u.path = []
		if u.order == "amove" and u.dest != null: set_path(u, u.dest.x, u.dest.y)
	u.scan -= dt
	if u.target == null and (u.order == "none" or u.order == "amove") and u.scan <= 0:
		u.scan = 0.35 + randf() * 0.2
		var t := find_target(u, d.sight * T)
		if t != null:
			u.target = t; u.auto = true; u.fspd = 0.0
			if u.order == "none" and u.guard == null: u.guard = Vector2(u.x, u.y)
	var moving := false
	if u.target != null:
		var t: Ent = u.target
		var dist := dist_to_ent(u.x, u.y, t)
		var in_range: bool = dist <= d.range * T and has_shot(u, t, dt)
		if in_range:
			u.path = []
			var want := atan2(t.y - u.y, t.x - u.x); var aimed: bool
			if d.turret:
				u.tang = turn_to(u.tang, want, 5 * dt); aimed = ang_diff(u.tang, want) < 0.12
			else:
				u.ang = turn_to(u.ang, want, (16.0 if d.armor == "inf" else 6.0) * dt); aimed = ang_diff(u.ang, want) < 0.15
			if u.cd <= 0 and aimed and not (d.minr > 0 and dist < d.minr * T):
				fire(u, t, d); u.cd = d.rof * (0.9 + randf() * 0.2)
		else:
			var leash: bool = u.order == "none" and u.auto and u.guard != null and Vector2(u.x - u.guard.x, u.y - u.guard.y).length() > 7 * T
			var lost: bool = u.auto and dist > d.sight * T * 1.6
			if leash or lost:
				u.target = null; u.auto = false
				if u.order == "amove" and u.dest != null: set_path(u, u.dest.x, u.dest.y)
				elif u.guard != null:
					set_path(u, int(u.guard.x / T), int(u.guard.y / T)); u.order = "move"; u.guard = null
			else:
				u.rp -= dt
				if u.rp <= 0 or u.path.is_empty():
					u.rp = 0.9; u.path = route(u, int(t.x / T), int(t.y / T))
				moving = move_unit(u, dt)
	else:
		moving = move_unit(u, dt)
		if u.path.is_empty() and u.order != "none":
			u.order = "none"; u.guard = Vector2(u.x, u.y)
		if not moving and u.face != null:
			u.ang = turn_to(u.ang, u.face, (18.0 if d.armor == "inf" else 3.0) * dt)
			if d.turret: u.tang = turn_to(u.tang, u.ang, 3 * dt)
			if ang_diff(u.ang, u.face) < 0.01: u.face = null
	u.moving = moving
	if d.burrow:
		# sappers dig through the ground while they move and surface to set their charges
		if moving != u.under:
			u.under = moving; _dig(u.x, u.y, 4)
		elif moving and randf() < dt * 6: _dig(u.x, u.y, 1)

func upd_medic(u: Ent, dt: float) -> void:
	var d := u.d
	u.scan -= dt
	if u.scan <= 0:
		u.scan = 0.4
		if u.ht == null or not u.ht.alive or u.ht.hp >= u.ht.max_hp:
			u.ht = null
			var bd: float = (d.sight if u.order == "none" else (4.0 if u.order == "escort" else 2.5)) * T
			for o in ents:
				if not o.alive or o == u or o.kind != "u" or o.team != u.team or o.d.armor != "inf" or o.hp >= o.max_hp: continue
				var dd := Vector2(o.x - u.x, o.y - u.y).length()
				if dd < bd: bd = dd; u.ht = o
	var moving := false
	if u.ht != null and u.order != "move":
		var t: Ent = u.ht; var dist := Vector2(t.x - u.x, t.y - u.y).length()
		if dist <= d.range * T:
			u.ang = turn_to(u.ang, atan2(t.y - u.y, t.x - u.x), 16 * dt)
			if u.cd <= 0:
				t.hp = min(t.max_hp, t.hp + d.heal); u.cd = d.rof; u.flash = 0.25
				parts.append({"k": "heal", "x": t.x, "y": t.y, "life": 0.8, "max": 0.8})
		else:
			u.rp -= dt
			if u.rp <= 0 or u.path.is_empty():
				u.rp = 0.8; u.path = route(u, int(t.x / T), int(t.y / T))
			moving = move_unit(u, dt)
	elif u.order == "escort": moving = follow_esc(u, dt)
	else:
		moving = move_unit(u, dt)
		if u.path.is_empty() and u.order != "none": u.order = "none"
	u.moving = moving

func upd_eng(u: Ent, dt: float) -> void:
	var moving := false; var t: Ent = u.target
	if u.order == "capture" and t != null:
		if not t.alive or (t.team == u.team and t.hp >= t.max_hp):
			u.target = null; u.order = "none"; u.path = []
		elif dist_to_ent(u.x, u.y, t) < T * 0.85:
			if t.team != u.team:
				var was := t.team
				t.team = u.team; t.seen = true; t.target = null; t.rally = null; t.hp = max(t.hp, t.max_hp * 0.5); calc_power()
				if u.team == 0:
					host.toast(t.d.name + " captured", "gold"); host.sfx("ready"); stats.killed += 1
				elif was == 0:
					host.toast(t.d.name + " lost to engineers", "warn"); host.sfx("alert")
				if sel.has(t): set_sel(sel.filter(func(x): return x != t))
				host.on_world_changed()
			else:
				t.hp = t.max_hp
				if u.team == 0: host.toast(t.d.name + " repaired", "gold"); host.sfx("ready")
			for k in 6: parts.append({"k": "spark", "x": t.x + (randf() - 0.5) * 20, "y": t.y + (randf() - 0.5) * 20, "vx": (randf() - 0.5) * 50, "vy": (randf() - 0.5) * 50, "life": 0.4, "max": 0.4, "c": Color("#9df5b0"), "s": 2.0})
			u.alive = false; u.sel = false; _drop_sel(u)
			return
		else:
			u.rp -= dt
			if u.rp <= 0 or u.path.is_empty():
				u.rp = 0.9
				var n = nearest_walk(t.tx + (t.w >> 1), t.ty + t.h, int(u.x / T), int(u.y / T))
				if n == null: n = Vector2i(t.tx, t.ty)
				u.path = route(u, n.x, n.y)
			moving = move_unit(u, dt)
	elif u.order == "escort": moving = follow_esc(u, dt)
	else:
		moving = move_unit(u, dt)
		if u.path.is_empty() and u.order != "none": u.order = "none"
	u.moving = moving

func find_ore(u: Ent) -> int:
	var start := u.pref if (u.pref >= 0 and ore[u.pref] > 0) else t_idx(u)
	var taken := {}
	for o in ents:
		if o != u and o.alive and o.kind == "u" and (o.hs == "go" or o.hs == "mine"): taken[o.ot] = true
	var seen := PackedByteArray(); seen.resize(MW * MH)
	var q := [start]; seen[start] = 1; var qi := 0; var fallback := -1
	while qi < q.size() and qi < 2600:
		var c: int = q[qi]; qi += 1
		if ore[c] > 0:
			if not taken.has(c): return c
			if fallback < 0: fallback = c
		var cx := c % MW; var cy := c / MW
		for dxy in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nx: int = cx + dxy[0]; var ny: int = cy + dxy[1]
			if not inb(nx, ny): continue
			var n := ny * MW + nx
			if seen[n]: continue
			seen[n] = 1
			if terr[n] < D.ROCK and bmap[n] == 0: q.append(n)
	return fallback

func upd_harv(u: Ent, dt: float) -> void:
	u.cd -= dt
	match u.hs:
		"manual":
			if u.path.is_empty(): u.hs = "idle"
		"idle":
			if u.team != 0:
				u.it -= dt
				if u.it <= 0: u.it = 3.0; u.hs = "find"
		"find":
			if u.load >= D.HARV_CAP: u.hs = "ret"; return
			var t := find_ore(u)
			if t < 0:
				u.hs = "ret" if u.load > 0 else "idle"; u.it = 4.0; return
			u.ot = t; set_path(u, t % MW, t / MW); u.hs = "go"
		"go":
			if ore[u.ot] == 0: u.hs = "find"; return
			if u.path.is_empty():
				var i := t_idx(u)
				if ore[i] > 0: u.hs = "mine"; u.mt = 0.3; u.ot = i
				elif Vector2(u.x - (u.ot % MW * T + 16), u.y - ((u.ot / MW) * T + 16)).length() < T * 1.2: u.hs = "mine"; u.mt = 0.3
				else: u.hs = "find"
		"mine":
			u.mt -= dt; u.ang += sin(time * 3) * dt * 0.3
			if u.mt <= 0:
				u.mt = 0.3
				var i := t_idx(u)
				if ore[i] == 0: i = u.ot
				if ore[i] == 0: u.hs = "find"; return
				var take := mini(20, ore[i]); ore[i] -= take; u.load += take
				if randf() < 0.5: parts.append({"k": "smoke", "x": u.x + cos(u.ang) * 14, "y": u.y + sin(u.ang) * 14, "vx": (randf() - 0.5) * 14, "vy": -8.0, "life": 0.7, "max": 0.7, "s": 4.0, "c": Color8(170, 140, 70)})
				if u.load >= D.HARV_CAP: u.hs = "ret"
				elif ore[i] == 0: u.hs = "find"
		"ret":
			var best: Ent = null; var bd := 1e9
			for b in ents:
				if b.alive and b.kind == "b" and b.team == u.team and b.type == "refinery":
					var dd := Vector2(b.x - u.x, b.y - u.y).length()
					if dd < bd: bd = dd; best = b
			if best == null: u.hs = "idle"; u.it = 4.0; return
			u.ref = best; set_path(u, best.tx + 1, best.ty + 3); u.hs = "toref"
		"toref":
			if u.ref == null or not u.ref.alive: u.hs = "ret"; return
			if u.path.is_empty():
				if dist_to_ent(u.x, u.y, u.ref) < T * 1.1: u.hs = "unload"; u.mt = 0.4; u.retry = 0
				else:
					u.retry += 1
					if u.retry > 3: u.hs = "idle"; u.it = 3.0; u.retry = 0
					else: u.hs = "ret"
		"unload":
			u.ang = turn_to(u.ang, -PI / 2, 3 * dt)
			if not u.ref.alive: u.hs = "ret"; return
			u.mt -= dt; u.ref.unload_t = time
			if u.mt <= 0:
				u.mt = 0.1
				var a: float = min(50.0, u.load); u.load -= a; u.dump += a
				var tm: Dictionary = teams[u.team]
				tm.credits += a * (D.DIFF[diff].inc if tm.ai else 1.0); tm.earned += a
				if u.team == 0: stats.mined += int(a)
				if u.load <= 0:
					u.load = 0.0; u.hs = "find"
					if u.team == 0: parts.append({"k": "txt", "x": u.ref.x, "y": u.ref.y, "txt": "+%d" % int(u.dump), "c": Color("f0b93f"), "life": 1.6, "max": 1.6, "h": 1.2})
					u.dump = 0.0

func upd_bld(b: Ent, dt: float) -> void:
	if b.hit_t > 0: b.hit_t -= dt
	if b.flash > 0: b.flash -= dt
	var d := b.d
	var tm: Dictionary = teams[b.team]
	if tm.ai and not b.repairing and b.hp < b.max_hp * 0.7 and tm.credits > 700 and b.type != "wall": b.repairing = true
	if b.repairing:
		if b.hp >= b.max_hp: b.repairing = false
		else:
			var add: float = min(b.max_hp * 0.07 * dt, b.max_hp - b.hp)
			var cost: float = d.cost * 0.5 * add / b.max_hp if d.cost else add * 0.3
			if tm.credits >= cost:
				tm.credits -= cost; b.hp += add; b.rp_t -= dt
				if b.rp_t <= 0:
					b.rp_t = 0.3
					parts.append({"k": "spark", "x": b.tx * T + randf() * b.w * T, "y": b.ty * T + randf() * b.h * T, "vx": 0.0, "vy": 0.0, "life": 0.35, "max": 0.35, "c": Color("#9df5b0"), "s": 2.5, "h0": 0.9})
			else:
				b.repairing = false
				if b.team == 0: host.toast("Insufficient aurite", "warn")
	if b.type == "repair":
		b.cd -= dt
		if b.cd <= 0:
			b.cd = 0.25; b.busy = false
			for u in ents:
				if not u.alive or u.kind != "u" or u.team != b.team or u.d.armor == "inf" or u.hp >= u.max_hp: continue
				if dist_to_ent(u.x, u.y, b) > T * 1.3: continue
				var add: float = min(14.0, u.max_hp - u.hp); var cost := add * 0.5
				if tm.credits < cost: continue
				tm.credits -= cost; u.hp += add; b.busy = true
				parts.append({"k": "spark", "x": u.x + (randf() - 0.5) * 12, "y": u.y + (randf() - 0.5) * 12, "vx": (randf() - 0.5) * 40, "vy": (randf() - 0.5) * 40, "life": 0.3, "max": 0.3, "c": Color("#9df5b0"), "s": 2.0})
	if b.hp < b.max_hp * 0.5:
		b.smoke_t -= dt
		if b.smoke_t <= 0:
			b.smoke_t = 0.22
			parts.append({"k": "smoke", "x": b.tx * T + randf() * b.w * T, "y": b.ty * T + randf() * b.h * T, "vx": (randf() - 0.5) * 8, "vy": -14.0, "life": 1.5, "max": 1.5, "s": 5.0, "c": Color8(40, 36, 32) if b.hp < b.max_hp * 0.25 else Color8(90, 86, 80)})
	if d.grow: upd_garden(b, tm, dt)
	if d.sw:
		b.ch = min(d.charge, b.ch + dt * (0.4 if low_power(b.team) else 1.0))
		if b.ch >= d.charge and not b.rdy:
			b.rdy = true
			if b.team == 0:
				host.toast(d.name + " ready", "gold"); host.sfx("ready"); host.on_sel_changed()
			else:
				host.toast("Enemy " + d.name + " is armed", "warn"); host.sfx("alert")
	if d.weapon == "": return
	if d.needPower and low_power(b.team):
		b.target = null; return
	b.cd -= dt * (0.4 if low_power(b.team) else 1.0)
	if b.target != null and (not b.target.alive or b.target.under or dist_to_ent(b.x, b.y, b.target) > d.range * T or (b.team == 0 and not visible_to_player(b.target)) or not has_shot(b, b.target, dt)):
		b.target = null
	b.scan -= dt
	if b.target == null and b.scan <= 0:
		b.scan = 0.4; b.target = find_target(b, d.range * T)
	if b.target != null:
		var want := atan2(b.target.y - b.y, b.target.x - b.x)
		b.tang = turn_to(b.tang, want, 4 * dt)
		if b.cd <= 0 and ang_diff(b.tang, want) < 0.12:
			fire(b, b.target, d); b.cd = d.rof

func launch_sw(b: Ent, x: float, y: float) -> void:
	var d := b.d
	b.ch = 0.0; b.rdy = false
	strikes.append({"x": x, "y": y, "t": 0.0, "kind": b.type, "team": b.team, "hit": 0, "done": false})
	if b.team == 1:
		host.toast("Enemy " + d.name + " launched!", "warn"); ping = {"x": x, "y": y, "t": time}
	else: host.toast(d.name + " launched", "gold")
	host.sfx("siren"); host.on_sel_changed()

func upd_strikes(dt: float) -> void:
	for s in strikes:
		s.t += dt
		if s.kind == "skyfall":
			if s.t > 2.2 and s.hit < 7 and s.t > 2.2 + s.hit * 0.16:
				var a := randf() * TAU; var r := randf() * T * 2.2
				var x: float = s.x + cos(a) * r; var y: float = s.y + sin(a) * r
				s.hit += 1; explode(x, y, 26); host.add_scorch(x, y, T * 1.2); sw_damage(x, y, T * 1.8, 260); host.sfx("bigboom", x, y)
			if s.t < 2.4 and randf() < 0.5:
				parts.append({"k": "missile", "x": s.x + (randf() - 0.5) * T * 4, "y": s.y + (randf() - 0.5) * T * 4, "h": 14.0, "vh": -6.0, "vx": 0.0, "vy": 0.0, "life": 2.2 - s.t, "max": 2.2})
		elif s.kind == "chorus":
			# the ground hums, then crystals burst up and stay as a field of shards
			if s.t < 2.6:
				parts.append({"k": "rift", "x": s.x, "y": s.y, "life": 0.4, "max": 0.4, "f": s.t / 2.6, "g": true})
				if randf() < 0.5: _dig(s.x + (randf() - 0.5) * T * 5, s.y + (randf() - 0.5) * T * 5, 1)
			if s.t >= 2.6 and not s.hit:
				s.hit = 1
				for k in 10:
					var a := k / 10.0 * TAU + randf() * 0.3; var r := T * (1.0 + randf() * 2.0)
					explode(s.x + cos(a) * r, s.y + sin(a) * r, 18)
				explode(s.x, s.y, 34); host.add_scorch(s.x, s.y, T * 2.6); sw_damage(s.x, s.y, T * 3.2, 750)
				add_field(s.x, s.y, T * 3.2, 18.0, s.team, 30.0); host.sfx("bigboom", s.x, s.y)
		else:
			if s.t < 3: parts.append({"k": "rift", "x": s.x, "y": s.y, "life": 0.4, "max": 0.4, "f": s.t / 3.0})
			if s.t >= 3 and not s.hit:
				s.hit = 1
				for k in 9:
					var a := k / 9.0 * TAU
					explode(s.x + cos(a) * T * 1.6, s.y + sin(a) * T * 1.6, 22)
				explode(s.x, s.y, 40); host.add_scorch(s.x, s.y, T * 3); sw_damage(s.x, s.y, T * 3.4, 900); host.sfx("bigboom", s.x, s.y)
		if s.t > 4: s.done = true
	strikes = strikes.filter(func(s): return not s.done)

func sw_damage(x: float, y: float, R: float, dmg: float) -> void:
	for o in ents:
		if not o.alive: continue
		var dd := dist_to_ent(x, y, o) if o.kind == "b" else Vector2(o.x - x, o.y - y).length()
		if dd < R: damage(o, dmg * (1 - dd / R * 0.6), "sw", null)

func separate() -> void:
	# bucket units by tile so we only compare neighbours
	var grid := {}
	var us: Array = []
	for e in ents:
		if e.kind == "u" and e.alive:
			us.append(e)
			var k := int(e.y / T) * MW + int(e.x / T)
			if grid.has(k): grid[k].append(e)
			else: grid[k] = [e]
	for a in us:
		if a.intun > 0: continue
		var ax := int(a.x / T); var ay := int(a.y / T)
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				var k := (ay + oy) * MW + ax + ox
				if not grid.has(k): continue
				for b in grid[k]:
					if b.id <= a.id or b.intun > 0: continue
					if a.d.air != b.d.air: continue
					var dx: float = b.x - a.x; var dy: float = b.y - a.y; var mn: float = (a.r + b.r) * 0.8
					if abs(dx) > mn or abs(dy) > mn: continue
					var d2 := dx * dx + dy * dy
					if d2 >= mn * mn: continue
					var nx: float; var ny: float; var dd: float
					if d2 < 0.01:
						var an := randf() * TAU; nx = cos(an); ny = sin(an); dd = 0.0
					else:
						dd = sqrt(d2); nx = dx / dd; ny = dy / dd
					var push := (mn - dd) * 0.5
					var wa := (0.3 if a.moving else 1.0) * (0.1 if (a.hs == "mine" or a.hs == "unload") else 1.0)
					var wb := (0.3 if b.moving else 1.0) * (0.1 if (b.hs == "mine" or b.hs == "unload") else 1.0)
					nudge(a, -nx * push * wa, -ny * push * wa); nudge(b, nx * push * wb, ny * push * wb)

func nudge(u: Ent, dx: float, dy: float) -> void:
	var nx := u.x + dx; var ny := u.y + dy
	var ok: bool = (nx > 4 and ny > 4 and nx < D.WW - 4 and ny < D.WH - 4) if u.d.air else walk(int(nx / T), int(ny / T))
	if ok: u.x = nx; u.y = ny

func upd_proj(dt: float) -> void:
	for p in proj:
		var tg: Ent = p.t
		if tg.alive and not p.fixed:
			p.tx = tg.x + p.ox; p.ty = tg.y + p.oy; p.y1 = h_at(tg.x, tg.y) + p.aim
		var dx: float = p.tx - p.x; var dy: float = p.ty - p.y; var dd := sqrt(dx * dx + dy * dy); var st: float = p.spd * dt
		p.ang = atan2(dy, dx)
		if p.w == "rocket" and randf() < 0.8: parts.append({"k": "smoke", "x": p.x, "y": p.y, "vx": 0.0, "vy": 0.0, "life": 0.45, "max": 0.45, "s": 2.5, "c": Color8(200, 200, 200), "h0": p.h})
		var impact := dd <= st
		if not impact:
			p.x += dx / dd * st; p.y += dy / dd * st
			var prog: float = clamp(1.0 - Vector2(p.tx - p.x, p.ty - p.y).length() / p.d0, 0.0, 1.0)
			var arc: float = p.apex * 4.0 * prog * (1.0 - prog) if p.lob else sin(prog * PI) * 0.12
			p.h = lerp(float(p.y0), float(p.y1), prog) + arc
			# shells that meet a hill burst on it
			if p.h < h_at(p.x, p.y):
				p.h = h_at(p.x, p.y); p.tx = p.x; p.ty = p.y; p.ground = true; impact = true
		else:
			p.h = p.y1
		if impact:
			p.dead = true
			if p.splash > 0:
				for o in ents:
					if not o.alive or o.team == p.src_team: continue
					var od := dist_to_ent(p.tx, p.ty, o) if o.kind == "b" else Vector2(o.x - p.tx, o.y - p.ty).length()
					if od < p.splash: damage(o, p.dmg * (1 - od / p.splash * 0.6), p.w, p.src)
				explode(p.tx, p.ty, 10)
				if p.w == "geode": add_field(p.tx, p.ty, T * 1.3, 7.0, p.src_team, 12.0)
			elif tg.alive and not p.get("ground", false): damage(tg, p.dmg, p.w, p.src)
			var hh: float = p.h
			parts.append({"k": "flash", "x": p.tx, "y": p.ty, "life": 0.15, "max": 0.15, "s": 12.0 if p.w == "shell" else (10.0 if p.w == "flak" else 9.0), "h0": hh})
			for i in 4:
				var a := randf() * TAU
				parts.append({"k": "spark", "x": p.tx, "y": p.ty, "vx": cos(a) * 80, "vy": sin(a) * 80, "life": 0.2, "max": 0.2, "c": Color("#ffcf6a"), "s": 1.5, "h0": hh})
			parts.append({"k": "smoke", "x": p.tx, "y": p.ty, "vx": 0.0, "vy": -10.0, "life": 0.6, "max": 0.6, "s": 5.0, "c": Color8(40, 38, 36) if p.w == "flak" else Color8(70, 64, 58), "h0": hh})
			host.sfx("small", p.tx, p.ty)
	proj = proj.filter(func(p): return not p.dead)

func upd_parts(dt: float) -> void:
	for p in parts:
		p.life -= dt
		if p.has("vx"): p.x += p.vx * dt; p.y += p.vy * dt
		if p.has("vh"):
			p.h += p.vh * dt; p.vh -= 9 * dt
			if p.h < 0.03:
				p.h = 0.03; p.vh = -p.vh * 0.3 if abs(p.vh) > 0.8 else 0.0; p.vx *= 0.5; p.vy *= 0.5
	parts = parts.filter(func(p): return p.life > 0)
	if parts.size() > 900: parts = parts.slice(parts.size() - 900)

func update_vision() -> void:
	for i in vis.size():
		if vis[i] == 2: vis[i] = 1
	for e in ents:
		if not e.alive or e.team != 0: continue
		var r: float = e.d.sight if e.kind == "u" else e.d.sight + e.w / 2.0
		var cx: float = e.x / T; var cy: float = e.y / T; var r2 := r * r
		for y in range(maxi(0, int(floor(cy - r))), mini(MH - 1, int(ceil(cy + r))) + 1):
			for x in range(maxi(0, int(floor(cx - r))), mini(MW - 1, int(ceil(cx + r))) + 1):
				var dx := x + 0.5 - cx; var dy := y + 0.5 - cy
				if dx * dx + dy * dy <= r2: vis[y * MW + x] = 2
	for b in ents:
		if b.kind != "b" or b.team == 0 or b.seen or not b.alive: continue
		for y in range(b.ty, b.ty + b.h):
			for x in range(b.tx, b.tx + b.w):
				if vis[y * MW + x] == 2: b.seen = true
	host.on_vision()

# ---------------- production ----------------
func upd_prod(tm: Dictionary, dt: float) -> void:
	var mult: float = (0.5 if low_power(tm.id) else 1.0) * (D.DIFF[diff].prod if tm.ai else 1.0)
	for cat in D.CAT_ORDER:
		var q: Dictionary = tm.prod[cat]
		if q.cur == "" and q.queue.size():
			q.cur = q.queue.pop_front(); q.prog = 0.0; q.paid = 0.0
		if q.cur == "" or q.ready: continue
		var d: Dictionary = D.def_of(q.cur)
		if cat != "bld" and count(tm.id, D.PRODUCER[cat]) == 0: continue
		if cat == "bld" and not has_req(tm.id, d.req):
			tm.credits += q.paid; q.cur = ""; continue
		var rate: float = min(dt * mult / d.time, 1.0 - q.prog); var cost: float = d.cost * rate
		if tm.credits >= cost:
			tm.credits -= cost; q.paid += cost; q.prog += rate
			if q.prog >= 1 - 1e-6:
				if cat == "bld":
					q.ready = true
					if tm.id == 0: host.toast("Construction complete", "gold"); host.sfx("ready")
				else:
					produce_done(tm, q.cur); q.cur = ""
		elif tm.id == 0:
			tm.noFundsT -= dt
			if tm.noFundsT <= 0: tm.noFundsT = 8.0; host.toast("Insufficient aurite", "warn")

func produce_done(tm: Dictionary, type: String) -> void:
	var d: Dictionary = D.UN[type]
	var bs: Array = ents.filter(func(e): return e.alive and e.kind == "b" and e.team == tm.id and e.type == D.PRODUCER[d.cat])
	if bs.is_empty(): return
	var b: Ent = bs[-1]
	for x in bs:
		if x.sel: b = x; break
	var ex := b.tx + b.w / 2; var ey := b.ty + b.h
	var u := spawn_unit(tm.id, type, ex * T + 16, ey * T + 16)
	b.out_t = time
	if tm.id == 0: stats.built += 1
	if d.harv: u.hs = "find"
	else:
		var rp = b.rally if b.rally != null else tm.rally
		u.order = "move"
		if rp != null:
			var s := slots_around(int(rp.x / T), int(rp.y / T), 1 + randi() % 6)
			var t: Vector2i = s[-1] if s.size() else Vector2i(int(rp.x / T), int(rp.y / T))
			set_path(u, t.x, t.y)
		else:
			var s := slots_around(ex, ey + 1, 1 + randi() % 5)
			var t: Vector2i = s[-1] if s.size() else Vector2i(ex, ey + 1)
			set_path(u, t.x, t.y)
	if tm.id == 0: host.toast(d.name + " ready"); host.sfx("ready")

func can_place(team: int, type: String, tx: int, ty: int, gap: bool) -> bool:
	var d: Dictionary = D.BLD[type]
	for y in range(ty, ty + d.h):
		for x in range(tx, tx + d.w):
			if not inb(x, y): return false
			var i := y * MW + x
			if terr[i] >= D.ROCK or ore[i] > 0 or bmap[i]: return false
			if team == 0 and vis[i] == 0: return false
	if gap:
		for y in range(ty - 1, ty + d.h + 1):
			for x in range(tx - 1, tx + d.w + 1):
				if inb(x, y) and bmap[y * MW + x]: return false
		if type == "refinery" or type == "factory" or type == "barracks" or d.tun:
			var ex: int = tx + d.w / 2; var ey: int = ty + d.h
			if not walk(ex, ey) or not walk(ex, ey + 1): return false
	if team == 0:
		for u in ents:
			if u.kind != "u" or not u.alive or u.d.air: continue
			var ux := int(u.x / T); var uy := int(u.y / T)
			if ux >= tx and ux < tx + d.w and uy >= ty and uy < ty + d.h: return false
	if d.tun:
		# a burrow can be dug anywhere the team has seen, but not right under an enemy base
		for b in ents:
			if b.kind == "b" and b.alive and b.team != team and Vector2(b.x - (tx + d.w / 2.0) * T, b.y - (ty + d.h / 2.0) * T).length() < T * 7: return false
		return true
	for b in ents:
		if b.kind != "b" or not b.alive or b.team != team: continue
		var gx := maxi(maxi(b.tx - (tx + d.w), tx - (b.tx + b.w)), 0); var gy := maxi(maxi(b.ty - (ty + d.h), ty - (b.ty + b.h)), 0)
		if maxi(gx, gy) <= 2: return true
	return false

func tile_ok(tx: int, ty: int) -> bool:
	if not inb(tx, ty): return false
	var i := ty * MW + tx
	return terr[i] < D.ROCK and ore[i] == 0 and bmap[i] == 0 and vis[i] != 0

func sell(b: Ent) -> int:
	var ref := int(floor(b.d.cost * 0.5 * b.hp / b.max_hp))
	teams[0].credits += ref
	b.alive = false; b.sel = false; b.end_kind = "sell"; b.end_t = time
	if ref > 0: parts.append({"k": "txt", "x": b.x, "y": b.y, "txt": "+%d" % ref, "c": Color("f0b93f"), "life": 1.8, "max": 1.8, "h": D.BH[b.type] + .3})
	for y in range(b.ty, b.ty + b.h):
		for x in range(b.tx, b.tx + b.w):
			if bmap[y * MW + x] == b.id: bmap[y * MW + x] = 0
	_sync_solid(b.tx, b.ty, b.w, b.h)
	for k in 8: parts.append({"k": "smoke", "x": b.tx * T + randf() * b.w * T, "y": b.ty * T + randf() * b.h * T, "vx": (randf() - 0.5) * 30, "vy": -randf() * 10, "life": 0.7, "max": 0.7, "s": 3.5, "c": Color8(196, 184, 156)})
	calc_power(); host.on_world_changed()
	return ref

func set_sel(list: Array) -> void:
	for e in sel: e.sel = false
	sel = list
	for e in list: e.sel = true
	host.on_sel_changed()

# ---------------- AI ----------------
func ai_think(tm: Dictionary) -> void:
	var id: int = tm.id; var q: Dictionary = tm.prod.bld; var F: Dictionary = D.FACS[tm.fac]; var M = mission
	var hq := find_hq(id)
	if hq == null: return
	var ok := func(t: String) -> bool: return t != "" and avail(id, t) and has_req(id, D.def_of(t).req) and not at_limit(id, t)
	if not M or M.aiBuild:
		if q.ready:
			var spot = ai_spot(id, q.cur, hq)
			if spot != null:
				add_building(id, q.cur, spot.x, spot.y); q.cur = ""; q.ready = false; q.prog = 0.0; q.paid = 0.0
		elif q.cur == "":
			var nxt := ""
			if tm.pused + 20 > tm.pmade and count(id, "power") < 10 and avail(id, "power"): nxt = "power"
			else:
				var need := {}
				for t0 in D.AI_ORDER:
					var t: String = t0
					if t == "DEF": t = F.def
					if t == "SW": t = F.sw
					if t == "TUN": t = F.get("tun", "")
					t = D.sub(tm.fac, t)
					if t == "" or not avail(id, t): continue
					need[t] = need.get(t, 0) + 1
					if count(id, t) < need[t]: nxt = t; break
			if nxt != "" and ok.call(nxt): q.cur = nxt
	if not M or M.aiProd:
		var harvs := count(id, "harv"); var refs := count(id, "refinery")
		var vq: Dictionary = tm.prod.veh; var iq: Dictionary = tm.prod.inf; var aq: Dictionary = tm.prod.air
		var pick := func(l: Array) -> String:
			var f := l.filter(func(t): return ok.call(t))
			return f[randi() % f.size()] if f.size() else ""
		if count(id, "factory") and vq.cur == "" and vq.queue.is_empty():
			if refs and harvs < mini(refs * 2, 3) and ok.call("harv"): vq.queue.append("harv")
			elif tm.credits > 500 or q.cur == "":
				var u: String = pick.call([F.lv, F.mt, F.mt, F.mt, D.sub(tm.fac, "arty"), F.ht, F.ht])
				if u != "": vq.queue.append(u)
		if count(id, "barracks") and iq.cur == "" and iq.queue.is_empty() and (tm.credits > 300 or q.cur == ""):
			var rf := D.sub(tm.fac, "rifle")
			var u: String = pick.call([rf, rf, "lancer", "lancer", "medic", F.inf, F.inf] + ([rf, rf, rf] if tm.fac == "choir" else []))
			if F.get("hero", "") != "" and tm.credits > 2200 and ok.call(F.hero): u = F.hero
			if u != "":
				iq.queue.append(u)
				# the Choir trains in swarms: cheap thralls come in threes
				if u == rf and tm.fac == "choir": iq.queue.append(u); iq.queue.append(u)
		if count(id, "helipad") and aq.cur == "" and aq.queue.is_empty() and tm.credits > 900 and count(id, F.air) < 4 + (2 if diff == "hard" else 0) and ok.call(F.air):
			aq.queue.append(F.air)
	# superweapon
	for b in ents:
		if b.alive and b.team == id and b.kind == "b" and b.rdy:
			var best: Ent = null; var bs := -1
			for o in ents:
				if not o.alive or o.team == id or o.kind != "b" or o.type == "wall": continue
				var sc := 0
				for p in ents:
					if p.alive and p.team != id and Vector2(p.x - o.x, p.y - o.y).length() < T * 3: sc += 3 if p.kind == "b" else 1
				if sc > bs: bs = sc; best = o
			if best != null: launch_sw(b, best.x, best.y)
	var army := ents.filter(func(e): return e.alive and e.team == id and e.kind == "u" and not e.d.harv and not e.d.eng and not e.post and not (M and e.d.hero))
	var idle := army.filter(func(u): return u.order == "none" and u.target == null)
	var intr: Ent = null
	for e in ents:
		if not e.alive or e.team == id or e.kind != "u" or e.captive: continue
		if Vector2(e.x - hq.x, e.y - hq.y).length() < 13 * T: intr = e; break
	if intr != null:
		for u in idle:
			if (Vector2(u.x - intr.x, u.y - intr.y).length() < 20 * T and can_hit(u.d, intr)) or u.d.heal:
				u.order = "amove"; set_path(u, int(intr.x / T), int(intr.y / T))
		return
	var first: float = M.aiFirst if (M and M.aiFirst >= 0) else D.DIFF[diff].first
	if time > first and idle.size() >= tm.wave:
		var tgt: Ent = null; var bd := 1e9
		for e in ents:
			if not e.alive or e.team == id or e.captive: continue
			var dd := Vector2(e.x - hq.x, e.y - hq.y).length() + (T * 8 if e.kind == "u" else 0)
			if dd < bd: bd = dd; tgt = e
		if tgt != null:
			group_move(idle, tgt.x, tgt.y, "amove"); tm.wave = mini(tm.wave + 2, 16)

func ai_spot(id: int, type: String, hq: Ent, home := false):
	var d: Dictionary = D.BLD[type]; var best = null; var bs := 1e9
	var ores: Array = []
	var eco: bool = type == "refinery" or d.grow
	if eco:
		for i in MW * MH:
			if ore[i]: ores.append(i)
	var cx := hq.tx + 1; var cy := hq.ty + 1
	var fwd = null
	if d.tun and not home:
		# burrows go forward, part way to the nearest enemy building, a little further for each one dug
		var en: Ent = null; var ed := 1e9
		for e in ents:
			if e.alive and e.kind == "b" and e.team != id:
				var dd := Vector2(e.x - hq.x, e.y - hq.y).length()
				if dd < ed: ed = dd; en = e
		if en == null: return null
		var f: float = clamp(0.3 + 0.12 * count(id, type), 0.3, 0.6)
		fwd = Vector2(lerp(hq.x, en.x, f) / T, lerp(hq.y, en.y, f) / T)
		cx = int(fwd.x); cy = int(fwd.y)
	for ty in range(cy - 12, cy + 13):
		for tx in range(cx - 12, cx + 13):
			if not can_place(id, type, tx, ty, true): continue
			var mx: float = tx + d.w / 2.0; var my: float = ty + d.h / 2.0; var s: float
			if fwd != null: s = Vector2(mx - fwd.x, my - fwd.y).length() + randf() * 3
			elif eco:
				s = 1e9
				for o in ores:
					var dd := Vector2(o % MW - mx, o / MW - my).length()
					if dd < s: s = dd
				s += randf() * 2
			elif d.weapon != "": s = Vector2(mx - MW / 2.0, my - MH / 2.0).length() + randf() * 4
			else: s = Vector2(mx - cx, my - cy).length() + randf() * 3
			if s < bs: bs = s; best = Vector2i(tx, ty)
	if best == null and fwd != null: return ai_spot(id, type, hq, true)
	return best

# ---------------- campaign goals, events, waves ----------------
func goal():
	return mission.goals[gi] if mission and gi < mission.goals.size() else null

func _hero_alive(team: int) -> Ent:
	for e in ents:
		if e.alive and e.team == team and e.kind == "u" and e.d.hero and not e.captive: return e
	return null

## Where enemy reinforcements head when nothing else is named: the Command Yard, else a hero, else any unit.
func _player_focus(from: Vector2) -> Vector2:
	var hq := find_hq(0)
	if hq != null and hq.kind == "b": return Vector2(hq.x, hq.y)
	var h := _hero_alive(0)
	if h != null: return Vector2(h.x, h.y)
	var best = null; var bd := 1e9
	for e in ents:
		if e.alive and e.team == 0 and not e.captive:
			var dd := Vector2(e.x, e.y).distance_to(from)
			if dd < bd: bd = dd; best = Vector2(e.x, e.y)
	return best if best != null else Vector2(p0.x * T, p0.y * T)

func _nearest(team: int, from: Vector2, f: Callable) -> Ent:
	var best: Ent = null; var bd := 1e9
	for e in ents:
		if e.alive and e.team == team and not e.captive and f.call(e):
			var dd := Vector2(e.x, e.y).distance_to(from)
			if dd < bd: bd = dd; best = e
	return best

## Sends a fresh group somewhere: a unit to hunt ("harv", "vip", "hero", "comms"), a tile, or the player's base.
func send_group(us: Array, go) -> void:
	if us.is_empty(): return
	var from := Vector2(us[0].x, us[0].y)
	var tgt: Ent = null
	if go is String:
		match go:
			"harv": tgt = _nearest(0, from, func(e): return e.kind == "u" and e.d.harv)
			"vip": tgt = _nearest(0, from, func(e): return e.tag == "vip")
			"hero": tgt = _nearest(0, from, func(e): return e.kind == "u" and e.d.hero)
			"comms": tgt = _nearest(0, from, func(e): return e.type == "comms")
			"none": return
	var dest: Vector2
	if go is Array: dest = Vector2(go[0] * T + 16, go[1] * T + 16)
	elif tgt != null: dest = Vector2(tgt.x, tgt.y)
	else: dest = _player_focus(from)
	group_move(us, dest.x, dest.y, "amove")
	if tgt != null and tgt.kind == "u":
		attack_order(us.filter(func(u): return u.d.dmg > 0 and can_hit(u.d, tgt)), tgt)

func spawn_group(sp: Dictionary) -> Array:
	var tm: int = sp.get("team", 1)
	var us := squad(tm, sp.u, sp.at[0], sp.at[1])
	if tm == 1: send_group(us, sp.get("go", "base"))
	return us

func run_event(ev: Dictionary, warn := true) -> void:
	if ev.has("say"):
		host.toast(ev.say, "warn" if warn else "gold"); host.sfx("alert" if warn else "ready")
	for sp in ev.get("spawn", []): spawn_group(sp)
	if ev.get("attack", "") == "hero":
		var hs := ents.filter(func(e): return e.alive and e.team == 1 and e.kind == "u" and e.d.hero)
		if hs.size():
			var c := Vector2(hs[0].x, hs[0].y)
			var esc := ents.filter(func(e): return e.alive and e.team == 1 and e.kind == "u" and not e.d.harv and not e.d.eng and not e.post and not e.d.hero and Vector2(e.x, e.y).distance_to(c) < 10 * T)
			send_group(hs + esc.slice(0, 8), "base")
	if ev.has("credits") and ev.get("team", 0) == 0: teams[0].credits += ev.credits

func goal_done(g: Dictionary) -> void:
	var dn = g.done
	if dn != null:
		if dn.has("base"):
			var bp: Vector2i = Vector2i(dn.base[0], dn.base[1])
			var hq := place_near(0, "hq", bp.x - 1, bp.y - 1)
			if hq != null:
				update_vision()
				prebuild(0, dn.get("pbase", []))
		if dn.has("credits"): teams[0].credits += dn.credits
		if dn.has("tech") and mission.tech != null:
			for t in dn.tech:
				if not mission.tech.has(t): mission.tech.append(t)
		for sp in dn.get("spawn", []): spawn_group(sp)
		if dn.has("say"): host.toast(dn.say, "gold"); host.sfx("ready")
	gi += 1; g_t0 = time; gst = {}; wst = {}
	var nx = goal()
	if nx == null:
		over = true; host.end_game(true)
	elif dn == null or not dn.has("say"):
		host.toast("Objective complete. Next: " + _goal_name(nx), "gold"); host.sfx("ready")

func lose(why: String) -> void:
	if over: return
	end_why = why; over = true
	host.toast(why, "warn"); host.end_game(false)

func _goal_name(g: Dictionary) -> String:
	match g.k:
		"reach": return "reach the " + g.label
		"survive": return g.label
		"hold": return "hold the " + g.label
		"escort": return "get them to the " + g.label
		"rescue": return "free the " + g.label
		"capture": return "capture the " + g.label
		"mine": return "deliver aurite"
	return g.get("verb", "Destroy the").to_lower() + " " + g.label

## The goal's targets: entities with its tag (if any) and of its types (buildings when it names none). team -1: any side.
func goal_targets(g: Dictionary, team := 1) -> Array:
	return ents.filter(func(e): return e.alive and (team < 0 or e.team == team) and not e.captive and (g.tag == "" or e.tag == g.tag) and (g.types.has(e.type) if g.types.size() else e.kind == "b"))

## Who stands in a zone: 0 the player, 1 the enemy, -1 nobody, 2 contested.
func zone_owner(z: Array, r: float) -> int:
	var p := false; var en := false
	var c := Vector2(z[0] * T + 16, z[1] * T + 16)
	for e in ents:
		if not e.alive or e.kind != "u" or e.captive or e.d.harv: continue
		if Vector2(e.x, e.y).distance_to(c) <= r * T:
			if e.team == 0: p = true
			else: en = true
	if p and en: return 2
	return 0 if p else (1 if en else -1)

func _in_zone(e: Ent, at: Array, r: float) -> bool:
	return Vector2(e.x, e.y).distance_to(Vector2(at[0] * T + 16, at[1] * T + 16)) <= r * T

func mission_tick() -> void:
	var M = mission
	if not M or over: return
	for i in M.events.size():
		var ev: Dictionary = M.events[i]
		if not ev_done.has(i) and time >= ev.t:
			ev_done[i] = true; run_event(ev)
	var g = goal()
	if g == null: return
	if g.waves != null: do_waves(g.waves, time - g_t0)
	elif M.waves != null: do_waves(M.waves, time)
	# prisoners walk free when a friendly unit reaches them
	for c in ents:
		if not c.alive or not c.captive: continue
		for e in ents:
			if e.alive and e.team == 0 and e.kind == "u" and not e.captive and Vector2(e.x - c.x, e.y - c.y).length() < T * 2.6:
				c.captive = false; c.tag = "vip"; c.guard = null
				if not gst.get("freed_msg", false):
					gst.freed_msg = true; host.toast("Prisoners freed", "gold"); host.sfx("ready")
				break
	for t in M.keep:
		if count(0, t) == 0:
			lose(("%s has fallen" % D.def_of(t).name) if D.UN.has(t) else ("Your %s was destroyed" % D.def_of(t).name)); return
	for t in g.protect:
		if count(0, t) == 0:
			lose("Your %s was lost" % D.def_of(t).name); return
	match g.k:
		"destroy_all":
			if ents.filter(func(e): return e.alive and e.team == 1 and (e.type != "wall" if e.kind == "b" else not e.d.harv)).is_empty(): goal_done(g)
		"kill":
			if goal_targets(g).is_empty(): goal_done(g)
		"mine":
			if not gst.has("m0"): gst.m0 = stats.mined
			if stats.mined - gst.m0 >= g.n: goal_done(g)
			elif g.t > 0 and time - g_t0 > g.t: lose("Time is up")
		"survive":
			if time - g_t0 >= g.t: goal_done(g)
		"reach":
			for e in ents:
				if e.alive and e.team == 0 and e.kind == "u" and not e.captive and (g.who != "hero" or e.d.hero) and _in_zone(e, g.at, g.r):
					goal_done(g); return
		"hold":
			var all_ok := true
			for z in g.zones:
				if zone_owner(z, g.r) != 0: all_ok = false
			if all_ok: gst.held = gst.get("held", 0.0) + 1.0
			if gst.get("held", 0.0) >= g.t: goal_done(g)
		"escort":
			for e in ents:
				if e.alive and e.team == 0 and e.tag == "vip" and not e.captive and _in_zone(e, g.at, g.r):
					e.alive = false; e.sel = false; _drop_sel(e)
					gst.arrived = gst.get("arrived", 0) + 1
					host.toast("%s is through (%d of %d)" % [e.d.name, gst.arrived, g.need], "gold"); host.sfx("ready")
			var left := ents.filter(func(e): return e.alive and e.team == 0 and e.tag == "vip").size()
			if gst.get("arrived", 0) >= g.need: goal_done(g)
			elif gst.get("arrived", 0) + left < g.need: lose("Too many of them were lost")
		"rescue":
			if ents.filter(func(e): return e.alive and e.captive).is_empty(): goal_done(g)
		"capture":
			var tg := goal_targets(g, -1)
			if tg.any(func(e): return e.team == 0): goal_done(g)
			elif tg.is_empty(): lose("The %s was destroyed" % g.label)

## Wave plan {first, every, n, from, to, list: [[type, base, per wave, from wave]]}; t is seconds since the plan started.
func do_waves(W: Dictionary, t: float) -> void:
	var wn: int = wst.get("wn", 0)
	if wn >= W.get("n", 99) or t < W.first + wn * W.every: return
	wn += 1; wst.wn = wn
	var fr: Array = W.from[randi() % W.from.size()]
	var list: Array = []
	for row in W.list:
		if wn < row[3]: continue
		var n := int(row[1] + row[2] * (wn - row[3]))
		if n > 0 and avail(1, row[0]): list.append([row[0], n])
	if list.is_empty(): return
	var us := squad(1, list, fr[0], fr[1])
	send_group(us, W.get("to", "base"))
	host.toast("Enemy wave %d of %d incoming" % [wn, W.get("n", 99)] if W.has("n") else "Enemy wave %d incoming" % wn, "warn"); host.sfx("alert")

func check_end() -> void:
	if over: return
	var alive := [0, 0]
	for e in ents:
		if e.alive and not e.captive and (e.type != "wall" if e.kind == "b" else not e.d.harv): alive[e.team] += 1
	if mission:
		if alive[0] == 0: lose("All your forces are gone")
		return
	if alive[0] == 0 or alive[1] == 0:
		over = true; host.end_game(alive[0] > 0)

func _sw_line() -> String:
	for e in ents:
		if e.alive and e.team == 1 and e.kind == "b" and e.d.sw:
			return "\n%s: %s" % [e.d.name, "ARMED" if e.rdy else D.fmt(e.d.charge - e.ch)]
	return ""

## Mission HUD text: the current goal with its progress, plus what must not be lost.
func obj_text() -> String:
	var M = mission
	if not M: return ""
	var g = goal()
	if g == null: return "Mission complete"
	var s := ""
	var step := "" if M.goals.size() < 2 else "(%d/%d) " % [gi + 1, M.goals.size()]
	match g.k:
		"destroy_all":
			var n := ents.filter(func(e): return e.alive and e.team == 1 and (e.type != "wall" if e.kind == "b" else not e.d.harv)).size()
			s = "Destroy the %s. Enemy forces left: %d" % [g.label if g.label != "" else "enemy", n]
		"kill": s = "%s %s · %d left" % [g.get("verb", "Destroy the"), g.label, goal_targets(g).size()]
		"mine":
			var m: int = stats.mined - int(gst.get("m0", stats.mined))
			s = "Aurite delivered: %s / %s" % [_thousands(m), _thousands(g.n)] + (" · %s left" % D.fmt(g.t - (time - g_t0)) if g.t > 0 else "")
		"survive": s = "%s: %s to go" % [g.label, D.fmt(g.t - (time - g_t0))]
		"reach": s = "Bring %s to the %s (gold marker)" % ["your hero" if g.who == "hero" else "a unit", g.label]
		"hold":
			var own := 0
			for z in g.zones:
				if zone_owner(z, g.r) == 0: own += 1
			s = "Hold all %d %s at once: %d held · %s to go" % [g.zones.size(), g.label, own, D.fmt(g.t - gst.get("held", 0.0))]
		"escort":
			var left := ents.filter(func(e): return e.alive and e.team == 0 and e.tag == "vip").size()
			s = "Get %d to the %s (gold marker): %d through, %d on the way" % [g.need, g.label, gst.get("arrived", 0), left]
		"rescue":
			s = "Free the %s: %d still held (marked on the map)" % [g.label, ents.filter(func(e): return e.alive and e.captive).size()]
		"capture": s = "Capture the %s with an Engineer. Do not destroy it" % g.label
	s = step + s + _sw_line()
	var keep: Array = []
	for t in M.keep:
		if D.UN.has(t): keep.append(D.UN[t].name)
	if keep.size(): s += "\nKeep alive: " + ", ".join(keep)
	return s

## Gold rings the 3D view and the minimap draw: [x, y, radius (tiles), owner (-1 none, 0 you, 1 enemy, 2 contested)].
func marks() -> Array:
	var g = goal()
	if g == null or over: return []
	var out: Array = []
	match g.k:
		"reach", "escort": out.append([g.at[0], g.at[1], g.r, -1])
		"hold":
			for z in g.zones: out.append([z[0], z[1], g.r, zone_owner(z, g.r)])
		"survive":
			if g.zone != null: out.append([g.zone[0], g.zone[1], 3.0, -1])
	return out

static func _thousands(n: int) -> String:
	var s := str(n); var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out; s = s.substr(0, s.length() - 3)
	return s + out

# ---------------- loop ----------------
func step(dt: float) -> void:
	time += dt
	for tm in teams: upd_prod(tm, dt)
	for e in ents:
		if not e.alive: continue
		if e.kind == "u": upd_unit(e, dt)
		else: upd_bld(e, dt)
	separate(); upd_proj(dt); upd_parts(dt); upd_fields(dt); upd_auras(dt)
	if delayed.size():
		var keep: Array = []
		for dl in delayed:
			if dl[0] <= time: explode(dl[1], dl[2], dl[3])
			else: keep.append(dl)
		delayed = keep
	vis_t -= dt
	if vis_t <= 0: vis_t = 0.2; update_vision()
	ai_t -= dt
	if ai_t <= 0:
		ai_t = 1.0; ai_think(teams[1]); mission_tick(); check_end()
	upd_strikes(dt); combat = max(0.0, combat - dt * 0.05)
	var any_dead := false
	for e in ents:
		if not e.alive: any_dead = true; break
	if any_dead:
		for e in ents:
			if not e.alive: by_id.erase(e.id)
		ents = ents.filter(func(e): return e.alive)
