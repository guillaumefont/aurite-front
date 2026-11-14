class_name MapGen
extends RefCounted
## Campaign maps: noise ground plus the hand-placed shapes of a mission's "map" (see campaign.gd).
## Writes Sim.terr and Sim.ore. Every key point (bases, objectives, posts, spawn points) ends up reachable
## from the player's start: where it is not, a ford or a pass is cut.

const MW := 64
const MH := 64

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-6: return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)

static func _poly_dist(p: Vector2, pts: Array) -> float:
	var best := 1e9
	for i in range(pts.size() - 1):
		best = min(best, _seg_dist(p, Vector2(pts[i][0], pts[i][1]), Vector2(pts[i + 1][0], pts[i + 1][1])))
	if pts.size() == 1: best = p.distance_to(Vector2(pts[0][0], pts[0][1]))
	return best

static func generate(S, mp: Dictionary, sd: int, keys: Array) -> void:
	var s := sd % 9973
	var terr: PackedByteArray = S.terr
	var ore: PackedInt32Array = S.ore
	var rock_th: float = mp.get("rock", 0.72)
	var dirt_th: float = mp.get("dirt", 0.6)
	var sea = mp.get("sea", null)
	for y in MH:
		for x in MW:
			var p := Vector2(x, y)
			var n1 := Sim.fbm(x / 8.0, y / 8.0, s + 1); var n2 := Sim.fbm(x / 5.0, y / 5.0, s + 2)
			var wob := (Sim.fbm(x / 6.0, y / 6.0, s + 7) - 0.5) * 1.6
			var t := D.GRASS
			if n2 > dirt_th: t = D.DIRT
			if n1 > rock_th: t = D.ROCK
			if sea != null:
				var e := 0.0
				match sea.edge:
					"n": e = y
					"s": e = MH - 1 - y
					"w": e = x
					"e": e = MW - 1 - x
				var dd: float = e - sea.d - wob * 1.5
				if dd < 0: t = D.WATER
				elif dd < 1.6: t = D.SAND
			for l in mp.get("lakes", []):
				var dd: float = p.distance_to(Vector2(l[0], l[1])) - l[2] - wob
				if dd < 0: t = D.WATER
				elif dd < 1.2 and t != D.WATER: t = D.SAND
			for rv in mp.get("rivers", []):
				var dd: float = _poly_dist(p, rv.pts) + wob * 0.5
				if dd < rv.w: t = D.WATER
				elif dd < rv.w + 1.0 and t != D.ROCK and t != D.WATER: t = D.SAND
			for rg in mp.get("ridges", []):
				if _poly_dist(p, rg.pts) + wob * 0.6 < rg.w: t = D.ROCK
			for m in mp.get("mesas", []):
				if p.distance_to(Vector2(m[0], m[1])) + wob < m[2]: t = D.ROCK
			for g in mp.get("gaps", []) + mp.get("gaps2", []):
				if p.distance_to(Vector2(g[0], g[1])) < g[2]:
					if t == D.WATER: t = D.SAND
					elif t == D.ROCK: t = D.DIRT
			for rd in mp.get("roads", []):
				if _poly_dist(p, rd) < 0.95:
					if t == D.WATER: t = D.SAND
					elif t != D.SAND: t = D.DIRT
			terr[y * MW + x] = t
	var clear := func(cx: int, cy: int, r: float) -> void:
		for y in range(cy - int(r) - 1, cy + int(r) + 2):
			for x in range(cx - int(r) - 1, cx + int(r) + 2):
				if not Sim.inb(x, y): continue
				if Vector2(x - cx, y - cy).length() <= r:
					var i := y * MW + x
					if terr[i] >= D.ROCK: terr[i] = D.GRASS
	clear.call(mp.p0[0], mp.p0[1], 7.0)
	if mp.get("e0", null) != null: clear.call(mp.e0[0], mp.e0[1], 6.5)
	for c in mp.get("clear", []): clear.call(c[0], c[1], c[2])
	for k in keys: clear.call(k[0], k[1], k[2] if k.size() > 2 else 2.0)
	for f in mp.get("ore", []):
		var fx: int = f[0]; var fy: int = f[1]; var r: float = f[2]
		for y in range(fy - 5, fy + 6):
			for x in range(fx - 5, fx + 6):
				if not Sim.inb(x, y): continue
				var dd := Vector2(x - fx, y - fy).length() + (Sim.hash2(x, y, s + 5) - 0.5) * 1.3
				var i := y * MW + x
				if dd < r:
					if terr[i] >= D.ROCK: terr[i] = D.DIRT
					ore[i] = int(round((160 + (1 - dd / r) * 340) / 20.0)) * 20
					if terr[i] == D.GRASS: terr[i] = D.DIRT
	# every key point reachable from the player start
	for k in [mp.get("e0", null)] + keys:
		if k == null: continue
		for attempt in 4:
			var seen := _flood(terr, mp.p0[0], mp.p0[1])
			var ki: int = clampi(k[1], 0, MH - 1) * MW + clampi(k[0], 0, MW - 1)
			if seen[ki]: break
			var best := -1; var bd := 1e9
			for i in MW * MH:
				if not seen[i]: continue
				var dd := Vector2(i % MW - k[0], i / MW - k[1]).length()
				if dd < bd: bd = dd; best = i
			_carve(terr, best % MW, best / MW, k[0], k[1])

static func _flood(terr: PackedByteArray, sx: int, sy: int) -> PackedByteArray:
	var seen := PackedByteArray(); seen.resize(MW * MH)
	var q := [sy * MW + sx]; seen[q[0]] = 1
	while q.size() > 0:
		var c: int = q.pop_back()
		var cx := c % MW; var cy := c / MW
		for dxy in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nx: int = cx + dxy[0]; var ny: int = cy + dxy[1]
			if not Sim.inb(nx, ny): continue
			var n := ny * MW + nx
			if seen[n] or terr[n] >= D.ROCK: continue
			seen[n] = 1; q.append(n)
	return seen

static func _carve(terr: PackedByteArray, ax: int, ay: int, bx: int, by: int) -> void:
	var n := int(Vector2(bx - ax, by - ay).length() * 2) + 2
	for k in n + 1:
		var f := float(k) / n
		var x := int(round(ax + (bx - ax) * f)); var y := int(round(ay + (by - ay) * f))
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if not Sim.inb(x + dx, y + dy): continue
				var i := (y + dy) * MW + x + dx
				if terr[i] == D.ROCK: terr[i] = D.DIRT
				elif terr[i] == D.WATER: terr[i] = D.SAND
