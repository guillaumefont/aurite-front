class_name Models
extends RefCounted
## Low-poly models built from primitives, baked into one vertex-coloured mesh per moving part.
## Vertex colour alpha: 1 = lit, 0 = unlit (glow), in between = lit plus some glow.

static var material: ShaderMaterial
static var ghost_ok: StandardMaterial3D
static var ghost_bad: StandardMaterial3D
static var cache := {}

const LIT_SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform float fog_on = 1.0;
void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float f = mix(1.0, texture(fog_tex, wp.xz / 64.0).r, fog_on);
	ALBEDO = COLOR.rgb * COLOR.a * f;
	EMISSION = COLOR.rgb * (1.0 - COLOR.a) * f;
}
"""

## Same look as LIT_SHADER, but everything above cut_y (world height) is cut away and a hot seam glows at the cut.
## Used only while a building is being assembled or dismantled.
const CUT_SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform float fog_on = 1.0;
uniform float cut_y = 100.0;
void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (wp.y > cut_y) discard;
	float f = mix(1.0, texture(fog_tex, wp.xz / 64.0).r, fog_on);
	float seam = 1.0 - smoothstep(0.0, 0.045, cut_y - wp.y);
	ALBEDO = mix(COLOR.rgb * COLOR.a, vec3(0.0), seam * 0.6) * f;
	EMISSION = (COLOR.rgb * (1.0 - COLOR.a) + vec3(1.0, 0.5, 0.12) * seam * 0.85) * f;
}
"""
static var cut_shader: Shader
static var fog_texture: Texture2D

static func cut_material() -> ShaderMaterial:
	if cut_shader == null:
		cut_shader = Shader.new(); cut_shader.code = CUT_SHADER
	var m := ShaderMaterial.new(); m.shader = cut_shader
	m.set_shader_parameter("fog_tex", fog_texture)
	m.set_shader_parameter("fog_on", material.get_shader_parameter("fog_on") if material.get_shader_parameter("fog_on") != null else 1.0)
	return m

static func init_materials(fog_tex: Texture2D) -> void:
	var sh := Shader.new(); sh.code = LIT_SHADER
	fog_texture = fog_tex
	material = ShaderMaterial.new(); material.shader = sh
	material.set_shader_parameter("fog_tex", fog_tex)
	ghost_ok = _ghost_mat(Color(0.5, 0.84, 0.56, 0.45))
	ghost_bad = _ghost_mat(Color(1, 0.35, 0.32, 0.5))

static func _ghost_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.no_depth_test = false
	return m

# ---------------- colours ----------------
static func lit(hex: String, glow := 0.0) -> Color:
	var c := Color(hex).srgb_to_linear(); c.a = 1.0 - glow; return c
static func unlit(hex: String) -> Color:
	var c := Color(hex).srgb_to_linear(); c.a = 0.0; return c

static var MAT := {
	"conc": lit("6b7176"), "metal": lit("8d949a"), "metal2": lit("6f777d"), "dark": lit("2b2f31"), "tire": lit("1f2223"),
	"olive": lit("5f6b4a"), "olive2": lit("4c573a"), "gold": lit("d8b840"), "goldGlow": lit("f2c443", 0.25), "glass": lit("24343f"),
	"skin": lit("d6a079"), "white": lit("e6ebe8"), "green": unlit("6fe08a"), "harv": lit("c9a227"), "cyan": unlit("78ebff"),
	"redLight": unlit("ff4a42"), "wall": lit("7d8378"), "wall2": lit("656b61"), "rock": lit("8a8174"),
	"ashM": lit("4a4644"), "ashM2": lit("353231"), "ashC": lit("55524f"), "arc": unlit("b88cff"), "orange": lit("d9772b"),
	"rotor": lit("1c1e1f"), "hmark": lit("e6e2d0"), "glowC": unlit("9ff3ff"),
	"heal": unlit("8af5a4"), "fire": unlit("ffa040"), "arcF": unlit("d9c2ff"), "flash": unlit("fff0a0"),
	"stone": lit("6a675a"), "stone2": lit("4b493f"), "earthC": lit("5c5547"), "moss": lit("46603a"), "earth": lit("6e5a42"), "robe": lit("343a31"),
	"cryst": lit("7dffa0", 0.55), "crystD": lit("3fbf68", 0.3), "glowG": unlit("8dffad"), "bone": lit("c9c2aa"),
	"winLit": lit("ffd890", 0.55), "sandbag": lit("a8946a"), "pipe": lit("7b868c"), "scaf": lit("d9a92e"), "stripe": lit("26292a"), "tank": lit("b8bdb8"),
}

# ---------------- geometry primitives (unit sized, centred) ----------------
static var _ico_v: Array = []
static var _ico_f: Array = []

static func _ico() -> void:
	if _ico_v.size(): return
	var t := (1.0 + sqrt(5.0)) / 2.0
	for v in [[-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0], [0, -1, t], [0, 1, t], [0, -1, -t], [0, 1, -t], [t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1]]:
		_ico_v.append(Vector3(v[0], v[1], v[2]).normalized())
	_ico_f = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]

## Returns an array of triangles [a, b, c] in unit space plus an inside point for orientation.
static func prim_tris(kind: String, p: Dictionary = {}) -> Array:
	var tris: Array = []
	match kind:
		"box":
			var c := [Vector3(-.5, -.5, -.5), Vector3(.5, -.5, -.5), Vector3(.5, .5, -.5), Vector3(-.5, .5, -.5), Vector3(-.5, -.5, .5), Vector3(.5, -.5, .5), Vector3(.5, .5, .5), Vector3(-.5, .5, .5)]
			for f in [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [3, 2, 6, 7], [0, 3, 7, 4], [1, 2, 6, 5]]:
				tris.append([c[f[0]], c[f[1]], c[f[2]]]); tris.append([c[f[0]], c[f[2]], c[f[3]]])
		"cyl":
			var rt: float = p.rt; var seg: int = p.seg
			for i in seg:
				var a0 := TAU * i / seg; var a1 := TAU * (i + 1) / seg
				var b0 := Vector3(sin(a0), -.5, cos(a0)); var b1 := Vector3(sin(a1), -.5, cos(a1))
				var t0 := Vector3(sin(a0) * rt, .5, cos(a0) * rt); var t1 := Vector3(sin(a1) * rt, .5, cos(a1) * rt)
				tris.append([b0, b1, t1]); tris.append([b0, t1, t0])
				if rt > 0.0001: tris.append([Vector3(0, .5, 0), t0, t1])
				tris.append([Vector3(0, -.5, 0), b0, b1])
		"cone":
			var seg: int = p.seg
			for i in seg:
				var a0 := TAU * i / seg; var a1 := TAU * (i + 1) / seg
				var b0 := Vector3(sin(a0), -.5, cos(a0)); var b1 := Vector3(sin(a1), -.5, cos(a1))
				tris.append([b0, b1, Vector3(0, .5, 0)]); tris.append([Vector3(0, -.5, 0), b0, b1])
		"ico":
			_ico()
			for f in _ico_f: tris.append([_ico_v[f[0]], _ico_v[f[1]], _ico_v[f[2]]])
		"oct":
			var v := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
			for a in [0, 1]:
				for b in [2, 3]:
					for c in [4, 5]: tris.append([v[a], v[b], v[c]])
		"prism":
			var v := [Vector3(-.5, 0, -.5), Vector3(-.5, 0, .5), Vector3(-.5, 1, 0), Vector3(.5, 0, -.5), Vector3(.5, 0, .5), Vector3(.5, 1, 0)]
			var ix := [0, 1, 2, 3, 5, 4, 1, 4, 5, 1, 5, 2, 0, 2, 5, 0, 5, 3, 0, 3, 4, 0, 4, 1]
			for i in range(0, ix.size(), 3): tris.append([v[ix[i]], v[ix[i + 1]], v[ix[i + 2]]])
	return tris

static func prim_center(kind: String) -> Vector3:
	return Vector3(0, 0.45, 0) if kind == "prism" else Vector3.ZERO

# ---------------- builder ----------------
class Builder:
	var root := Node3D.new()
	var bufs := {}  # Node3D -> [PackedVector3Array verts, PackedVector3Array normals, PackedColorArray cols]
	var team := 0
	var tm: Dictionary
	var P: Dictionary
	var nshadow := {}  # nodes that should not cast shadows

	func _init(t: int, fac: String) -> void:
		team = t
		var tc: Dictionary = D.TEAMC[t]
		tm = {"col": Color(tc.col).srgb_to_linear(), "dk": Color(tc.dk).srgb_to_linear()}
		var M: Dictionary = Models.MAT
		if fac == "ashen": P = {"metal": M.ashM, "metal2": M.ashM2, "conc": M.ashC, "gear": M.ashM2}
		elif fac == "choir": P = {"metal": M.stone, "metal2": M.stone2, "conc": M.earthC, "gear": M.moss}
		else: P = {"metal": M.metal, "metal2": M.metal2, "conc": M.conc, "gear": M.olive2}

	func grp(par: Node3D, nm: String, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> Node3D:
		var g := Node3D.new(); g.name = nm
		g.transform = Transform3D(Basis.from_euler(rot) * Basis.from_scale(scl), pos)
		par.add_child(g)
		return g

	func add(kind: String, prm: Dictionary, col: Color, par: Node3D, xf: Transform3D) -> void:
		if not bufs.has(par): bufs[par] = [PackedVector3Array(), PackedVector3Array(), PackedColorArray()]
		var b: Array = bufs[par]
		var ctr: Vector3 = xf * Models.prim_center(kind)
		for tri in Models.prim_tris(kind, prm):
			var a: Vector3 = xf * tri[0]; var bb: Vector3 = xf * tri[1]; var c: Vector3 = xf * tri[2]
			var n := (bb - a).cross(c - a)
			if n.length_squared() < 1e-12: continue
			n = n.normalized()
			if n.dot((a + bb + c) / 3.0 - ctr) < 0:
				n = -n; var tmp := bb; bb = c; c = tmp
			# Godot front faces are clockwise
			b[0].append(a); b[0].append(c); b[0].append(bb)
			for k in 3: b[1].append(n); b[2].append(col)

	static func xf(sx: float, sy: float, sz: float, x: float, y: float, z: float, rot := Vector3.ZERO) -> Transform3D:
		return Transform3D(Basis.from_euler(rot) * Basis.from_scale(Vector3(sx, sy, sz)), Vector3(x, y, z))

	func box(c: Color, sx: float, sy: float, sz: float, x: float, y: float, z: float, par: Node3D, rot := Vector3.ZERO) -> void:
		add("box", {}, c, par, xf(sx, sy, sz, x, y, z, rot))
	func cyl(c: Color, rt: float, rb: float, h: float, seg: int, x: float, y: float, z: float, par: Node3D, rot := Vector3.ZERO) -> void:
		add("cyl", {"rt": rt / rb, "seg": seg}, c, par, xf(rb, h, rb, x, y, z, rot))
	func ico(c: Color, r: float, x: float, y: float, z: float, par: Node3D, sc := Vector3.ONE) -> void:
		add("ico", {}, c, par, xf(r * sc.x, r * sc.y, r * sc.z, x, y, z))
	func prism(c: Color, sx: float, sy: float, sz: float, x: float, y: float, z: float, par: Node3D) -> void:
		add("prism", {}, c, par, xf(sx, sy, sz, x, y, z))
	## A crystal: an octahedron with half-extents sx, sy, sz.
	func gem(c: Color, sx: float, sy: float, sz: float, x: float, y: float, z: float, par: Node3D, rot := Vector3.ZERO) -> void:
		add("oct", {}, c, par, xf(sx, sy, sz, x, y, z, rot))
	## A cluster of n crystals leaning out from (x, y, z), the tallest h high.
	func cluster(par: Node3D, x: float, y: float, z: float, n: int, h: float, sd: int, c := Color()) -> void:
		var col: Color = c if c != Color() else Models.MAT.cryst
		for k in n:
			var a := TAU * (k + sd * .37) / n + sd; var lean := .18 + .22 * fmod(k * .61 + sd * .3, 1.0)
			var hh := h * (1.0 - .45 * fmod(k * .37 + sd * .19, 1.0))
			var r := .045 * h / .4 + .01
			gem(col if k % 3 else Models.MAT.crystD, r, hh / 2, r, x + cos(a) * r * 1.2 + sin(lean) * cos(a) * hh * .25, y + hh * .42, z + sin(a) * r * 1.2 + sin(lean) * sin(a) * hh * .25, par, Vector3(sin(a) * lean, 0, -cos(a) * lean))
	func cone(c: Color, seg: int, sx: float, sy: float, sz: float, x: float, y: float, z: float, par: Node3D, rot := Vector3.ZERO) -> void:
		add("cone", {"seg": seg}, c, par, xf(sx, sy, sz, x, y, z, rot))
	func torus(c: Color, R: float, r: float, rs: int, ts: int, par: Node3D) -> void:
		if not bufs.has(par): bufs[par] = [PackedVector3Array(), PackedVector3Array(), PackedColorArray()]
		var b: Array = bufs[par]
		for j in ts:
			for i in rs:
				var pts: Array = []
				for q in [[j, i], [j + 1, i], [j + 1, i + 1], [j, i + 1]]:
					var u: float = TAU * q[0] / ts; var v: float = TAU * q[1] / rs
					pts.append(Vector3((R + r * cos(v)) * cos(u), (R + r * cos(v)) * sin(u), r * sin(v)))
				var um := TAU * (j + 0.5) / ts; var ctr := Vector3(R * cos(um), R * sin(um), 0)
				for tri in [[pts[0], pts[1], pts[2]], [pts[0], pts[2], pts[3]]]:
					var a: Vector3 = tri[0]; var bb: Vector3 = tri[1]; var cc: Vector3 = tri[2]
					var n := (bb - a).cross(cc - a).normalized()
					if n.dot((a + bb + cc) / 3.0 - ctr) < 0: n = -n; var tmp := bb; bb = cc; cc = tmp
					b[0].append(a); b[0].append(cc); b[0].append(bb)
					for k in 3: b[1].append(n); b[2].append(c)

	## A single primitive that animates on its own: a named group at (x,y,z).
	func solo(nm: String, par: Node3D, x: float, y: float, z: float, rot := Vector3.ZERO) -> Node3D:
		return grp(par, nm, Vector3(x, y, z), rot)

	func flash_mesh(par: Node3D, x: float, y: float, z: float, s := 0.07, c := Color()) -> Node3D:
		var g := solo("flash", par, x, y, z)
		ico(c if c != Color() else Models.MAT.flash, s, 0, 0, 0, g)
		g.visible = false; nshadow[g] = true
		return g

	func rotor(par: Node3D, nm: String, x: float, y: float, z: float, ln: float, c = null, rot := Vector3.ZERO) -> Node3D:
		var g := grp(par, nm, Vector3(x, y, z), rot)
		var col: Color = c if c != null else Models.MAT.rotor
		box(col, ln, .012, .05, 0, 0, 0, g); box(col, .05, .012, ln, 0, 0, 0, g)
		nshadow[g] = true
		return g

	# ---- detail kit for buildings ----
	var nfan := 0
	var nlt := 0
	func pipe(c: Color, a: Vector3, b: Vector3, rad: float, par: Node3D) -> void:
		var dv := b - a; var L := dv.length()
		if L < 1e-4: return
		var dn := dv / L
		var rb := Basis.from_euler(Vector3(PI, 0, 0)) if dn.dot(Vector3.UP) < -0.999 else Basis(Quaternion(Vector3.UP, dn))
		var bs := rb * Basis.from_scale(Vector3(rad, L, rad))
		add("cyl", {"rt": 1.0, "seg": 6}, c, par, Transform3D(bs, (a + b) / 2))
	func rail(par: Node3D, pts: Array, y: float, hg: float) -> void:
		var c: Color = Models.MAT.pipe
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]; var b: Vector2 = pts[i + 1]
			pipe(c, Vector3(a.x, y + hg, a.y), Vector3(b.x, y + hg, b.y), .012, par)
			var n: int = max(1, roundi(a.distance_to(b) / .35))
			for k in n + 1:
				if k == n and i < pts.size() - 2: continue
				var q := a.lerp(b, float(k) / n)
				box(c, .025, hg, .025, q.x, y + hg / 2, q.y, par)
	func windows(par: Node3D, x0: float, x1: float, y: float, z: float, n: int, ws: float, hs: float, along_z := false) -> void:
		for k in n:
			var f := float(k) / (n - 1) if n > 1 else .5
			var p := lerpf(x0, x1, f)
			if along_z: box(Models.MAT.winLit, .02, hs, ws, z, y, p, par)
			else: box(Models.MAT.winLit, ws, hs, .02, p, y, z, par)
	func fan(par: Node3D, x: float, y: float, z: float, sz: float) -> void:
		box(Models.MAT.dark, sz, sz * .5, sz, x, y, z, par)
		var f := grp(par, "fan%d" % nfan, Vector3(x, y + sz * .26, z)); nfan += 1
		box(Models.MAT.metal2, sz * .85, .012, sz * .14, 0, 0, 0, f); box(Models.MAT.metal2, sz * .14, .012, sz * .85, 0, 0, 0, f)
	func lamp(par: Node3D, x: float, y: float, z: float, c: Color) -> void:
		var l := solo("lt%d" % nlt, par, x, y, z); nlt += 1
		ico(c, .035, 0, 0, 0, l); nshadow[l] = true
	func crate(par: Node3D, x: float, z: float, sz: float) -> void:
		box(Models.MAT.olive2, sz, sz, sz, x, .12 + sz / 2, z, par); box(Models.MAT.dark, sz * 1.02, sz * .12, sz * 1.02, x, .12 + sz * .55, z, par)
	func bags(par: Node3D, cx: float, cz: float, rad: float, a0: float, a1: float, n: int) -> void:
		for k in n:
			var a := lerpf(a0, a1, float(k) / (n - 1) if n > 1 else .5)
			box(Models.MAT.sandbag, .16, .08, .09, cx + cos(a) * rad, .16, cz + sin(a) * rad, par, Vector3(0, -a + PI / 2, 0))
			if k % 2 == 0: box(Models.MAT.sandbag, .15, .07, .085, cx + cos(a + .12) * rad, .235, cz + sin(a + .12) * rad, par, Vector3(0, -a + PI / 2, 0))
	func stripes(par: Node3D, x: float, z: float, ln: float, y: float, along_z := false) -> void:
		var n: int = max(2, roundi(ln / .14))
		for k in n:
			var f := (k + .5) / n - .5
			var c: Color = Models.MAT.stripe if k % 2 else Models.MAT.gold
			if along_z: box(c, .06, .012, ln / n, x, y, z + f * ln, par)
			else: box(c, ln / n, .012, .06, x + f * ln, y, z, par)

	func finish() -> Node3D:
		for n in bufs:
			var b: Array = bufs[n]
			var arr := []; arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = b[0]; arr[Mesh.ARRAY_NORMAL] = b[1]; arr[Mesh.ARRAY_COLOR] = b[2]
			var am := ArrayMesh.new(); am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			am.surface_set_material(0, Models.material)
			var mi := MeshInstance3D.new(); mi.mesh = am; mi.name = "m"
			if nshadow.has(n): mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			(n as Node3D).add_child(mi)
		return root

# ---------------- models ----------------
static func get_model(kind: String, type: String, team: int, fac: String) -> Node3D:
	var key := kind + type + str(team) + fac
	if not cache.has(key):
		cache[key] = unit_model(type, team, fac) if kind == "u" else bld_model(type, team, fac)
	return cache[key].duplicate()

static func infantry(B: Builder, b: Node3D, type: String) -> void:
	var M := MAT; var tm := B.tm; var P := B.P
	b.scale = Vector3.ONE * 1.6
	var lg := B.solo("legL", b, 0, .065, -.045); B.box(M.dark, .07, .13, .06, 0, 0, 0, lg)
	var rg := B.solo("legR", b, 0, .065, .045); B.box(M.dark, .07, .13, .06, 0, 0, 0, rg)
	var torso: Color = M.white if type == "medic" else tm.col
	B.box(torso, .12, .15, .17, 0, .2, 0, b); B.box(tm.dk, .125, .03, .175, 0, .135, 0, b)
	B.box(tm.col, .05, .1, .04, .01, .2, -.105, b); B.box(tm.col, .05, .1, .04, .01, .2, .105, b)
	var hollow := ["thrall", "sapper", "cantor"].has(type)
	B.ico(M.dark if type == "pyro" else (M.bone if hollow else M.skin), .055, .01, .32, 0, b)
	if hollow:
		# deep hood with two green eyes
		B.ico(M.robe, .068, -.012, .335, 0, b, Vector3(1, 1.05, 1)); B.box(M.glowG, .01, .014, .016, .058, .325, -.02, b); B.box(M.glowG, .01, .014, .016, .058, .325, .02, b)
	match type:
		"rifle":
			B.box(P.gear, .12, .045, .12, 0, .37, 0, b); B.box(P.gear, .07, .12, .13, -.09, .22, 0, b); B.box(M.dark, .24, .03, .03, .1, .22, .08, b); B.flash_mesh(b, .24, .22, .08, .06)
		"lancer":
			B.box(P.gear, .12, .045, .12, 0, .37, 0, b); B.cyl(P.gear, .045, .045, .4, 6, 0, .33, -.1, b, Vector3(0, 0, PI / 2)); B.box(M.dark, .05, .07, .06, .2, .33, -.1, b); B.box(M.dark, .04, .08, .03, .05, .27, -.1, b); B.flash_mesh(b, -.22, .33, -.1, .09)
		"medic":
			B.box(M.white, .12, .045, .12, 0, .37, 0, b); B.box(M.white, .09, .14, .13, -.1, .22, 0, b); B.box(M.green, .004, .09, .03, -.147, .23, 0, b); B.box(M.green, .004, .03, .09, -.147, .23, 0, b); B.box(M.green, .004, .02, .06, .07, .375, 0, b); B.flash_mesh(b, .08, .2, .1, .06, M.heal)
		"engineer":
			B.box(M.gold, .14, .045, .14, 0, .37, 0, b); B.box(M.gold, .1, .02, .16, .02, .355, 0, b); B.box(M.orange, .08, .07, .11, .02, .13, .14, b); B.box(M.metal, .03, .03, .16, .1, .2, -.1, b); B.flash_mesh(b, .12, .2, .12, .05)
		"ranger":
			B.box(M.olive2, .13, .06, .14, -.01, .37, 0, b); B.box(M.olive2, .1, .16, .18, -.03, .22, 0, b); B.box(M.dark, .36, .025, .025, .14, .23, .07, b); B.cyl(M.dark, .018, .018, .08, 5, .1, .26, .07, b, Vector3(0, 0, PI / 2)); B.flash_mesh(b, .33, .23, .07, .06)
		"vey":
			# hooded commando: long dark coat, orange scarf, arc carbine with a violet coil, glowing visor
			b.scale = Vector3.ONE * 1.95
			B.box(M.ashM2, .15, .12, .19, -.01, .13, 0, b); B.box(M.ashM2, .05, .2, .2, -.08, .16, 0, b)
			B.box(M.dark, .13, .07, .13, -.01, .36, 0, b); B.box(M.dark, .06, .05, .13, -.06, .4, 0, b); B.box(M.arcF, .015, .02, .1, .055, .325, 0, b)
			B.box(M.orange, .1, .04, .19, .0, .27, 0, b); B.box(M.orange, .08, .1, .03, -.07, .22, .09, b, Vector3(0, 0, .4))
			B.box(M.dark, .3, .04, .04, .12, .22, .08, b); B.cyl(M.arc, .025, .025, .07, 6, .2, .22, .08, b, Vector3(0, 0, PI / 2)); B.box(M.ashM, .06, .07, .05, .03, .2, .08, b)
			B.flash_mesh(b, .3, .22, .08, .08, M.arcF)
		"harrow":
			# marksman officer: olive cape, brass-trimmed beret, long rail rifle with a scope
			b.scale = Vector3.ONE * 1.95
			B.box(M.olive2, .05, .22, .22, -.085, .19, 0, b); B.box(M.olive, .14, .05, .2, -.01, .29, 0, b)
			B.box(tm.dk, .14, .035, .14, -.01, .38, 0, b); B.box(M.gold, .02, .03, .02, .05, .385, -.04, b); B.box(M.gold, .03, .025, .17, -.01, .265, 0, b)
			B.box(M.dark, .44, .03, .03, .15, .23, .08, b); B.box(M.metal2, .1, .035, .035, .04, .27, .08, b); B.cyl(M.cyan, .012, .012, .38, 5, .2, .245, .08, b, Vector3(0, 0, PI / 2))
			B.flash_mesh(b, .4, .23, .08, .07, M.glowC)
		"thrall":
			B.box(M.robe, .13, .06, .18, -.01, .1, 0, b)
			B.box(M.stone2, .24, .03, .03, .1, .22, .08, b); B.gem(M.cryst, .05, .018, .018, .25, .22, .08, b, Vector3(0, 0, PI / 2))
			B.flash_mesh(b, .3, .22, .08, .06, M.glowG)
		"sapper":
			b.scale = Vector3.ONE * 1.5
			B.box(M.earth, .1, .16, .15, -.11, .23, 0, b); B.cluster(b, -.12, .3, 0, 4, .14, 2)
			B.box(M.metal2, .03, .03, .2, .07, .14, .1, b, Vector3(0, 0, -.5)); B.box(M.metal, .08, .02, .07, .14, .06, .1, b)
			B.flash_mesh(b, .16, .12, 0, .08, M.glowG)
		"cantor":
			# the Cantor: long robe, a hood with a halo of crystal, a tall singing staff
			b.scale = Vector3.ONE * 1.95
			B.box(M.robe, .17, .2, .21, -.01, .12, 0, b); B.box(tm.col, .14, .05, .22, -.01, .27, 0, b); B.box(tm.dk, .05, .2, .2, -.09, .18, 0, b)
			B.box(M.bone, .02, .62, .02, .09, .3, .12, b); B.cluster(b, .09, .58, .12, 3, .08, 1)
			var orb := B.solo("orb", b, .09, .66, .12); B.ico(M.glowG, .35, 0, 0, 0, orb); orb.scale = Vector3.ONE * .08; B.nshadow[orb] = true
			var hl := B.grp(b, "halo", Vector3(-.05, .36, 0), Vector3(0, PI / 2, 0)); B.torus(M.cryst, .085, .01, 4, 10, hl); B.nshadow[hl] = true
			B.flash_mesh(b, .09, .66, .12, .09, M.glowG)
		"pyro":
			B.box(M.dark, .12, .05, .12, 0, .37, 0, b); B.box(M.dark, .03, .03, .05, .065, .32, 0, b); B.cyl(M.orange, .04, .04, .18, 6, -.11, .23, -.04, b); B.cyl(M.orange, .04, .04, .18, 6, -.11, .23, .04, b); B.box(M.dark, .2, .035, .035, .1, .2, .08, b); B.flash_mesh(b, .22, .2, .08, .08, M.fire)

static func unit_model(type: String, team: int, fac: String) -> Node3D:
	var B := Builder.new(team, fac); var M := MAT; var tm := B.tm; var P := B.P
	var g := B.root
	var body := B.grp(g, "body", Vector3.ZERO, Vector3.ZERO, Vector3.ONE * 1.25)
	var tracks := func(L: float, z: float, h: float) -> void:
		B.box(M.tire, L, h, .14, 0, .07, z, body); B.box(M.tire, L, h, .14, 0, .07, -z, body)
		for x in [-L / 2 + .08, L / 2 - .08]:
			for zz in [z, -z]: B.cyl(M.dark, .06, .06, .15, 6, x, .07, zz, body, Vector3(PI / 2, 0, 0))
	match type:
		"rifle", "lancer", "medic", "engineer", "ranger", "pyro", "vey", "harrow", "thrall", "sapper", "cantor":
			infantry(B, body, type)
		"skitter":
			# six-legged crystal crawler with a shard gun under its chin
			B.ico(tm.col, 1, 0, .2, 0, body, Vector3(.2, .075, .12)); B.ico(M.stone2, 1, .17, .2, 0, body, Vector3(.07, .055, .07))
			B.box(M.glowG, .01, .015, .05, .235, .22, 0, body)
			for k in 3: B.gem(M.cryst if k % 2 else M.crystD, .025, .07, .025, -.1 + k * .08, .3, 0, body, Vector3(0, 0, .35))
			for side in [["legL", .07], ["legR", -.07]]:
				var lg := B.solo(side[0], body, 0, .17, side[1])
				for x in [-.11, 0.0, .11]:
					B.box(M.stone2, .025, .025, .14, x, 0, sign(side[1]) * .07, lg, Vector3(-sign(side[1]) * .5, 0, 0))
					B.box(M.stone2, .022, .14, .022, x, -.07, sign(side[1]) * .14, lg)
			B.box(M.dark, .12, .025, .025, .26, .15, 0, body); B.flash_mesh(body, .33, .15, 0, .06, M.glowG)
		"mantis":
			# tall glass mantis: long abdomen, raised thorax, a spine launcher held in its forelimbs
			B.ico(tm.dk, 1, -.2, .3, 0, body, Vector3(.2, .08, .11)); B.box(tm.col, .3, .1, .16, .02, .34, 0, body)
			B.ico(M.stone2, 1, .2, .42, 0, body, Vector3(.07, .06, .07)); B.box(M.glowG, .012, .02, .07, .27, .44, 0, body)
			for z in [-.06, .06]: B.gem(M.cryst, .02, .1, .02, -.06, .46, z, body, Vector3(z * 3, 0, .4))
			for side in [["legL", .08], ["legR", -.08]]:
				var lg := B.solo(side[0], body, 0, .28, side[1])
				for x in [-.14, .08]:
					B.box(M.stone2, .025, .025, .16, x, 0, sign(side[1]) * .08, lg, Vector3(-sign(side[1]) * .6, 0, 0))
					B.box(M.stone2, .022, .26, .022, x, -.13, sign(side[1]) * .16, lg)
			for z in [-.07, .07]:
				B.box(M.stone2, .2, .03, .03, .26, .36, z, body, Vector3(0, 0, -.3)); B.cyl(M.crystD, .03, .035, .18, 5, .36, .32, z, body, Vector3(0, 0, PI / 2))
			B.flash_mesh(body, .46, .32, 0, .08, M.glowG)
		"geode":
			# shelled beetle with a sling arm that hurls a geode
			B.ico(tm.col, 1, 0, .26, 0, body, Vector3(.3, .14, .22)); B.ico(tm.dk, 1, .24, .22, 0, body, Vector3(.09, .07, .1))
			B.box(M.glowG, .01, .02, .08, .325, .24, 0, body)
			for side in [["legL", .14], ["legR", -.14]]:
				var lg := B.solo(side[0], body, 0, .18, side[1])
				for x in [-.16, 0.0, .16]:
					B.box(M.stone2, .03, .03, .12, x, 0, sign(side[1]) * .05, lg, Vector3(-sign(side[1]) * .5, 0, 0))
					B.box(M.stone2, .026, .16, .026, x, -.08, sign(side[1]) * .1, lg)
			var t := B.grp(body, "tur", Vector3(-.06, .38, 0))
			B.cyl(M.stone2, .07, .09, .06, 6, 0, .02, 0, t)
			var tube := B.solo("tube", t, .02, .05, 0, Vector3(0, 0, -.9)); B.box(M.bone, .04, .4, .04, 0, .2, 0, tube); B.box(M.stone2, .1, .04, .1, 0, .4, 0, tube); B.gem(M.cryst, .06, .08, .06, 0, .47, 0, tube)
			B.cluster(body, -.12, .34, 0, 4, .12, 3)
			B.flash_mesh(t, .32, .37, 0, .1, M.glowG)
		"moth":
			# glass-winged moth drone
			B.ico(tm.dk, 1, 0, 0, 0, body, Vector3(.14, .05, .055)); B.ico(tm.col, 1, .1, .01, 0, body, Vector3(.05, .045, .045)); B.box(M.glowG, .01, .015, .04, .15, .01, 0, body)
			for side in [["wingL", .04], ["wingR", -.04]]:
				var wg := B.grp(body, side[0], Vector3(0, .02, side[1]))
				B.gem(M.cryst, .09, .006, .14, 0, 0, sign(side[1]) * .14, wg); B.gem(M.crystD, .06, .005, .08, -.1, 0, sign(side[1]) * .1, wg)
			B.box(M.dark, .1, .02, .02, .1, -.05, 0, body); B.flash_mesh(body, .17, -.05, 0, .06, M.glowG)
		"furnace":
			# Old Brann's arc tank: a smelter on tracks, twin chimneys, a furnace mouth and an arc horn on top
			tracks.call(.86, .28, .15)
			B.box(M.ashM2, .76, .18, .46, 0, .25, 0, body); B.box(tm.col, .78, .05, .48, 0, .35, 0, body); B.box(tm.dk, .16, .14, .48, .39, .24, 0, body)
			B.box(M.ashM, .4, .2, .34, -.08, .46, 0, body); B.box(M.fire, .02, .08, .18, .125, .44, 0, body); B.box(M.dark, .02, .02, .22, .126, .49, 0, body)
			for z in [-.11, .11]:
				B.cyl(M.ashM2, .05, .06, .34, 6, -.24, .62, z, body); B.cyl(M.fire, .04, .04, .02, 6, -.24, .8, z, body)
			B.cyl(M.metal2, .05, .07, .14, 6, .06, .62, 0, body)
			for k in 3: B.cyl(tm.col if k % 2 else M.metal, .1 - k * .02, .1 - k * .02, .03, 8, .06, .7 + k * .05, 0, body)
			var orb := B.solo("orb", body, .06, .86, 0); B.ico(M.arc, 1, 0, 0, 0, orb); orb.scale = Vector3.ONE * .08; B.nshadow[orb] = true
			B.box(M.gold, .05, .05, .5, .42, .15, 0, body)
			B.flash_mesh(body, .06, .86, 0, .16, M.arcF)
		"saint":
			# Marshal Dace's command tank: long hull, twin long guns, brass trim, a banner pole and command antennas
			tracks.call(.92, .3, .17)
			B.box(tm.col, .82, .17, .48, 0, .26, 0, body); B.box(tm.dk, .16, .12, .48, .44, .22, 0, body); B.box(P.metal2, .84, .12, .07, 0, .24, .32, body); B.box(P.metal2, .84, .12, .07, 0, .24, -.32, body)
			B.box(M.gold, .84, .025, .02, 0, .33, .29, body); B.box(M.gold, .84, .025, .02, 0, .33, -.29, body)
			var t := B.grp(body, "tur", Vector3(-.08, .35, 0))
			B.box(tm.col, .42, .16, .38, 0, .08, 0, t); B.prism(tm.dk, .2, .1, .38, -.26, .06, 0, t); B.box(M.gold, .1, .03, .1, -.05, .18, 0, t)
			for z in [-.08, .08]:
				B.box(P.metal2, .56, .06, .06, .46, .09, z, t); B.box(M.dark, .08, .09, .09, .74, .09, z, t)
			B.box(M.dark, .012, .4, .012, -.18, .32, .14, t); B.box(M.dark, .012, .3, .012, -.2, .26, -.14, t)
			B.box(M.gold, .1, .07, .005, -.13, .46, .14, t); B.box(tm.col, .09, .06, .006, -.13, .45, .14, t)
			B.flash_mesh(t, .8, .09, 0, .13)
		"truck":
			# foundry truck: cab up front, canvas-covered cargo bed
			for w in [[.26, .17], [-.06, .17], [-.24, .17], [.26, -.17], [-.06, -.17], [-.24, -.17]]: B.cyl(M.tire, .09, .09, .08, 7, w[0], .09, w[1], body, Vector3(PI / 2, 0, 0))
			B.box(M.dark, .7, .06, .3, 0, .15, 0, body)
			B.box(tm.col, .2, .2, .3, .25, .27, 0, body); B.box(M.glass, .03, .09, .26, .355, .32, 0, body)
			B.box(M.sandbag, .44, .24, .32, -.12, .32, 0, body); B.box(tm.dk, .45, .03, .33, -.12, .45, 0, body)
		"buggy":
			B.box(tm.col, .5, .1, .3, 0, .17, 0, body); B.box(tm.dk, .52, .04, .32, 0, .11, 0, body); B.box(M.glass, .03, .09, .24, .13, .26, 0, body)
			for z in [-.13, .13]:
				B.box(M.dark, .03, .16, .03, .12, .29, z, body); B.box(M.dark, .03, .16, .03, -.12, .29, z, body); B.box(M.dark, .27, .03, .03, 0, .37, z, body)
			for w in [[.17, .18], [-.17, .18], [.17, -.18], [-.17, -.18]]: B.cyl(M.tire, .095, .095, .08, 7, w[0], .095, w[1], body, Vector3(PI / 2, 0, 0))
			var t := B.grp(body, "tur", Vector3(-.12, .24, 0))
			B.cyl(M.dark, .05, .06, .08, 6, 0, .04, 0, t); B.box(M.dark, .24, .035, .035, .12, .07, 0, t); B.flash_mesh(t, .26, .07, 0, .07)
		"raider":
			B.box(tm.col, .42, .07, .09, 0, .18, 0, body); B.box(M.ashM2, .18, .06, .1, -.05, .24, 0, body)
			B.cyl(M.tire, .1, .1, .05, 8, .2, .1, 0, body, Vector3(PI / 2, 0, 0)); B.cyl(M.tire, .11, .11, .06, 8, -.19, .11, 0, body, Vector3(PI / 2, 0, 0))
			B.box(M.dark, .03, .16, .03, .16, .24, 0, body); B.box(M.dark, .03, .03, .2, .14, .32, 0, body)
			B.box(tm.col, .08, .12, .1, -.03, .35, 0, body); B.ico(M.dark, .045, -.01, .45, 0, body); B.box(M.dark, .16, .025, .025, .2, .22, .06, body); B.flash_mesh(body, .3, .22, .06, .06)
		"tank":
			tracks.call(.68, .21, .13); B.box(tm.col, .58, .13, .34, 0, .2, 0, body); B.box(tm.dk, .12, .08, .34, .31, .17, 0, body); B.box(P.metal2, .6, .05, .08, 0, .2, .22, body); B.box(P.metal2, .6, .05, .08, 0, .2, -.22, body)
			var t := B.grp(body, "tur", Vector3(-.04, .27, 0))
			B.cyl(tm.col, .15, .19, .12, 6, 0, .06, 0, t); B.box(tm.dk, .1, .06, .2, -.15, .07, 0, t)
			B.box(P.metal2, .4, .055, .055, .26, .07, 0, t); B.box(M.dark, .07, .08, .08, .46, .07, 0, t); B.box(M.dark, .01, .25, .01, -.1, .22, .08, t); B.flash_mesh(t, .52, .07, 0, .1)
		"scorpion":
			tracks.call(.64, .19, .11); B.prism(tm.col, .6, .14, .36, 0, .13, 0, body); B.box(tm.dk, .6, .03, .37, 0, .13, 0, body); B.box(M.ashM2, .18, .06, .2, -.22, .25, 0, body)
			var t := B.grp(body, "tur", Vector3(0, .24, 0))
			B.cone(tm.col, 6, .13, .1, .13, 0, .05, 0, t); B.box(M.dark, .46, .035, .035, .26, .06, 0, t); B.box(M.arc, .04, .04, .04, .5, .06, 0, t); B.flash_mesh(t, .52, .06, 0, .08)
			B.box(M.ashM2, .03, .24, .03, -.27, .36, 0, body, Vector3(0, 0, .5))
		"bulwark":
			tracks.call(.82, .27, .16); B.box(tm.col, .72, .16, .44, 0, .24, 0, body); B.box(tm.dk, .14, .1, .44, .38, .2, 0, body); B.box(P.metal2, .74, .12, .06, 0, .22, .3, body); B.box(P.metal2, .74, .12, .06, 0, .22, -.3, body)
			var t := B.grp(body, "tur", Vector3(-.06, .32, 0))
			B.box(tm.col, .38, .15, .34, 0, .08, 0, t); B.box(tm.dk, .12, .12, .36, -.22, .08, 0, t)
			for z in [-.07, .07]:
				B.box(P.metal2, .46, .055, .055, .4, .09, z, t); B.box(M.dark, .07, .08, .08, .62, .09, z, t)
			B.flash_mesh(t, .68, .09, 0, .12)
		"arcc":
			tracks.call(.66, .22, .13); B.box(M.ashM2, .56, .14, .36, 0, .21, 0, body); B.box(tm.col, .58, .04, .38, 0, .29, 0, body)
			B.cyl(M.ashM, .09, .14, .16, 6, -.02, .37, 0, body)
			for k in 3: B.cyl(tm.col if k % 2 else M.metal, .16 - k * .03, .16 - k * .03, .04, 8, -.02, .47 + k * .08, 0, body)
			B.cyl(M.ashM, .03, .03, .22, 5, -.02, .62, 0, body)
			var orb := B.solo("orb", body, -.02, .76, 0); B.ico(M.arc, 1, 0, 0, 0, orb); orb.scale = Vector3.ONE * .08; B.nshadow[orb] = true
			B.flash_mesh(body, -.02, .76, 0, .14, M.arcF)
		"arty":
			tracks.call(.62, .2, .12); B.box(tm.col, .6, .12, .36, 0, .18, 0, body); B.box(P.gear, .18, .1, .3, .22, .28, 0, body)
			var t := B.grp(body, "tur", Vector3(-.12, .26, 0))
			B.box(tm.dk, .24, .08, .26, 0, .04, 0, t)
			var tube := B.solo("tube", t, .12, .2, 0, Vector3(0, 0, -.9)); B.cyl(P.metal2, .06, .075, .5, 6, 0, 0, 0, tube)
			B.box(M.dark, .06, .1, .3, -.05, .08, 0, t); B.flash_mesh(t, .32, .37, 0, .1)
		"harv":
			tracks.call(.74, .26, .13)
			B.box(M.harv, .52, .22, .48, -.06, .24, 0, body); B.box(tm.col, .17, .24, .32, .28, .32, 0, body); B.box(M.glass, .02, .08, .26, .37, .37, 0, body)
			B.box(M.dark, .38, .03, .38, -.1, .36, 0, body)
			var cargo := B.solo("cargo", body, -.1, .37, 0); B.box(M.goldGlow, .34, 1, .34, 0, 0, 0, cargo)
			var scoop := B.solo("scoop", body, .42, .1, 0); B.box(M.metal, .08, .12, .52, 0, 0, 0, scoop)
		"skyhawk":
			B.box(tm.col, .5, .14, .17, 0, 0, 0, body); B.box(M.glass, .14, .1, .15, .25, -.01, 0, body); B.box(tm.dk, .5, .04, .18, 0, -.07, 0, body)
			B.box(tm.col, .42, .05, .05, -.42, .03, 0, body); B.box(tm.dk, .03, .14, .1, -.62, .07, 0, body); B.rotor(body, "tr", -.62, .07, .06, .16, null, Vector3(PI / 2, 0, 0))
			B.box(M.dark, .06, .03, .5, 0, -.02, 0, body)
			for z in [-.24, .24]: B.cyl(M.dark, .03, .03, .16, 6, 0, -.05, z, body, Vector3(0, 0, PI / 2))
			for z in [-.09, .09]: B.box(M.dark, .42, .02, .02, 0, -.16, z, body)
			B.box(M.dark, .06, .12, .06, 0, .12, 0, body)
			B.rotor(body, "rot", 0, .19, 0, .95); B.flash_mesh(body, .12, -.05, .24, .08)
		"wasp":
			B.ico(tm.col, 1, 0, 0, 0, body, Vector3(.15, .07, .12)); B.box(M.ashM2, .12, .04, .08, .06, -.06, 0, body); B.box(M.arc, .03, .03, .06, .13, 0, 0, body)
			var i := 0
			for xz in [[.17, .17], [.17, -.17], [-.17, .17], [-.17, -.17]]:
				B.box(M.ashM2, .03, .025, .26, xz[0] / 2, 0, xz[1] / 2, body, Vector3(0, atan2(xz[0], xz[1]), 0))
				B.cyl(M.ashM2, .03, .03, .05, 6, xz[0], .02, xz[1], body)
				B.rotor(body, "rot%d" % i, xz[0], .05, xz[1], .18, tm.dk); i += 1
			B.box(M.dark, .14, .025, .025, .1, -.08, 0, body); B.flash_mesh(body, .2, -.08, 0, .06)
	# selection ring
	var r: float = D.UN[type].r / 32.0 * 1.45
	var ring := B.grp(g, "sel", Vector3(0, .035, 0)); ring.visible = false
	_ring(B, ring, r * 0.82, r, Color(0.5, 0.84, 0.56, 0))
	B.nshadow[ring] = true
	return B.finish()

static func _ring(B: Builder, par: Node3D, r0: float, r1: float, c: Color) -> void:
	if not B.bufs.has(par): B.bufs[par] = [PackedVector3Array(), PackedVector3Array(), PackedColorArray()]
	var b: Array = B.bufs[par]; var n := 20
	for i in n:
		var a0 := TAU * i / n; var a1 := TAU * (i + 1) / n
		var p0 := Vector3(cos(a0) * r0, 0, sin(a0) * r0); var p1 := Vector3(cos(a0) * r1, 0, sin(a0) * r1)
		var p2 := Vector3(cos(a1) * r1, 0, sin(a1) * r1); var p3 := Vector3(cos(a1) * r0, 0, sin(a1) * r0)
		for tri in [[p0, p1, p2], [p0, p2, p3]]:
			# facing up, clockwise seen from above
			var a: Vector3 = tri[0]; var bb: Vector3 = tri[1]; var cc: Vector3 = tri[2]
			if (bb - a).cross(cc - a).y < 0: var tmp := bb; bb = cc; cc = tmp
			b[0].append(a); b[0].append(cc); b[0].append(bb)
			for k in 3: b[1].append(Vector3.UP); b[2].append(c)

static func bld_model(type: String, team: int, fac: String) -> Node3D:
	var B := Builder.new(team, fac); var M := MAT; var tm := B.tm; var P := B.P
	var g := B.root
	var body := B.grp(g, "body")
	var d: Dictionary = D.BLD[type]; var w: float = d.w; var h: float = d.h
	if type != "wall" and type != "helipad": B.box(P.conc, w - .1, .12, h - .1, 0, .06, 0, body)
	match type:
		"hq":
			B.box(P.metal, 2.3, .85, 1.5, -.15, .55, -.55, body); B.box(tm.col, 2.32, .1, 1.52, -.15, .86, -.55, body)
			B.box(P.metal2, 1.1, .5, 1.0, -.5, 1.2, -.6, body); B.box(M.glass, 1.12, .1, .7, -.5, 1.28, -.55, body)
			B.cyl(M.dark, .05, .05, .55, 5, .85, 1.2, -.8, body)
			var dish := B.grp(body, "spin", Vector3(.85, 1.5, -.8)); B.cone(P.metal, 6, .36, .14, .36, .05, 0, 0, dish, Vector3(0, 0, -1.2))
			B.box(M.dark, 1.6, .03, .8, 0, .135, .85, body)
			for x in [-.5, 0, .5]: B.box(M.gold, .36, .035, .1, x, .14, .85, body, Vector3(0, .6, 0))
			var bl := B.solo("blink", body, -1.05, 1.47, -.15); B.ico(M.redLight, .06, 0, 0, 0, bl); B.nshadow[bl] = true
		"power":
			B.cyl(P.metal, .3, .42, 1.0, 7, -.4, .62, -.35, body); B.cyl(M.cyan, .3, .3, .05, 7, -.4, 1.13, -.35, body)
			B.cyl(P.metal, .26, .36, .8, 7, .42, .52, .4, body); B.cyl(M.cyan, .26, .26, .05, 7, .42, .93, .4, body)
			B.box(P.metal2, .5, .38, .6, .45, .31, -.45, body); B.box(tm.col, .52, .07, .62, .45, .46, -.45, body); B.box(M.dark, .4, .3, .3, -.4, .27, .45, body)
		"refinery":
			B.box(P.metal, 1.5, .8, 1.4, -.6, .5, -.6, body); B.box(tm.col, 1.52, .1, 1.42, -.6, .84, -.6, body)
			B.cyl(P.metal2, .55, .55, 1.0, 8, .8, .6, -.6, body); B.ico(M.goldGlow, 1, .8, 1.1, -.6, body, Vector3(.55, .32, .55))
			B.box(M.dark, .5, .12, .12, .2, .7, -.6, body)
			B.box(M.gold, 1.1, .04, .7, 0, .14, .95, body)
			for x in [-.35, 0, .35]: B.box(M.dark, .12, .046, .7, x, .142, .95, body)
		"barracks":
			B.box(M.olive, 1.6, .5, 1.3, 0, .37, -.1, body); B.prism(P.gear, 1.7, .42, 1.42, 0, .62, -.1, body); B.box(tm.col, 1.62, .07, 1.32, 0, .6, -.1, body)
			B.box(M.dark, .42, .33, .05, 0, .29, .56, body)
		"factory":
			B.box(P.metal, 2.6, .85, 1.9, 0, .52, -.35, body); B.box(tm.col, 2.62, .09, 1.92, 0, .9, -.35, body)
			for z in [-1.0, -.35, .3]: B.prism(P.metal2, 2.6, .32, .62, 0, .94, z, body)
			B.box(M.dark, 1.4, .62, .05, 0, .41, .61, body)
			for k in 5: B.box(M.gold, .1, .62, .06, -.56 + k * .28, .41, .62, body)
			B.box(M.dark, 1.4, .03, .6, 0, .135, 1.1, body)
		"turret":
			B.cyl(P.metal, .3, .38, .32, 6, 0, .26, 0, body)
			var t := B.grp(body, "tur", Vector3(0, .42, 0))
			B.cyl(tm.col, .2, .23, .16, 6, 0, .08, 0, t); B.box(M.dark, .42, .07, .07, .26, .09, 0, t); B.flash_mesh(t, .5, .09, 0, .1)
		"flak":
			B.cyl(P.metal, .32, .4, .3, 6, 0, .25, 0, body)
			var t := B.grp(body, "tur", Vector3(0, .42, 0))
			B.box(tm.col, .3, .16, .3, 0, .08, 0, t)
			for z in [-.08, .08]: B.box(M.dark, .42, .05, .05, .18, .24, z, t, Vector3(0, 0, .75))
			B.flash_mesh(t, .34, .4, 0, .1)
		"repair":
			B.box(M.dark, 2.3, .03, 2.0, 0, .135, .15, body)
			for x in [-1.05, 1.05]:
				B.box(P.metal2, .16, 1.0, .16, x, .6, -.6, body); B.box(P.metal2, .16, 1.0, .16, x, .6, .75, body)
			B.box(P.metal, 2.3, .14, .18, 0, 1.08, -.6, body); B.box(P.metal, 2.3, .14, .18, 0, 1.08, .75, body); B.box(tm.col, 2.32, .06, .2, 0, 1.16, -.6, body)
			var arm := B.grp(body, "arm", Vector3(0, 1.0, .07)); B.box(P.metal2, .16, .1, 1.4, 0, 0, 0, arm)
			var tool := B.solo("tool", arm, 0, -.2, 0); B.box(M.dark, .1, .3, .1, 0, 0, 0, tool)
			var l1 := B.solo("lamp", body, 1.05, 1.2, -.6); B.ico(M.green, .07, 0, 0, 0, l1); B.nshadow[l1] = true
			var l2 := B.solo("lamp2", body, 1.05, 1.2, -.6); B.ico(M.goldGlow, .07, 0, 0, 0, l2); l2.visible = false; B.nshadow[l2] = true
			for x in [-.7, 0, .7]: B.box(M.gold, .4, .035, .08, x, .14, 1.05, body, Vector3(0, .5, 0))
		"wall":
			B.box(M.wall, .86, .48, .86, 0, .24, 0, body); B.box(M.wall2, .92, .07, .92, 0, .03, 0, body)
			for xz in [[-.27, -.27], [.27, -.27], [-.27, .27], [.27, .27]]: B.box(M.wall2, .22, .12, .22, xz[0], .53, xz[1], body)
		"comms":
			B.box(P.metal2, .8, .45, .6, -.4, .34, .35, body); B.box(tm.col, .82, .06, .62, -.4, .5, .35, body)
			for xz in [[.25, -.45], [.65, -.45], [.25, -.05], [.65, -.05]]:
				var x: float = xz[0]; var z: float = xz[1]
				B.box(P.metal, .05, 1.9, .05, x + (.08 if x < .45 else -.08), 1.05, z + (.08 if z < -.2 else -.08), body, Vector3(0, 0, -.06 if x < .45 else .06))
			for k in 4: B.box(P.metal, .42, .04, .42, .45, .45 + k * .42, -.25, body)
			var dish := B.grp(body, "spin", Vector3(.45, 2.0, -.25)); B.cone(P.metal, 6, .42, .16, .42, .1, 0, 0, dish, Vector3(0, 0, -1.3)); B.box(M.dark, .18, .03, .03, .2, 0, 0, dish)
			B.cone(P.metal, 6, .3, .12, .3, -.4, .75, .35, body, Vector3(0, 0, 1.1))
			var bl := B.solo("blink", body, .45, 2.2, -.25); B.ico(M.redLight, .05, 0, 0, 0, bl); B.nshadow[bl] = true
		"helipad":
			B.box(P.conc, 1.9, .08, 1.9, 0, .04, 0, body); B.box(M.dark, 1.6, .02, 1.6, 0, .09, 0, body)
			B.box(M.hmark, .12, .025, .7, -.25, .1, 0, body); B.box(M.hmark, .12, .025, .7, .25, .1, 0, body); B.box(M.hmark, .5, .025, .1, 0, .1, 0, body)
			for xz in [[-.85, -.85], [.85, -.85], [-.85, .85], [.85, .85]]: B.ico(M.green, .05, xz[0], .12, xz[1], body)
			B.box(P.metal2, .4, .35, .35, .72, .25, -.72, body); B.box(tm.col, .42, .05, .37, .72, .42, -.72, body)
		"tech":
			B.box(P.metal, 1.7, .55, 1.0, 0, .38, .3, body); B.box(tm.col, 1.72, .06, 1.02, 0, .63, .3, body)
			for k in 4: B.box(M.glowC, .22, .06, .02, -.6 + k * .4, .45, .81, body)
			B.ico(M.glass, .62, -.15, .42, -.35, body); B.box(P.metal2, .4, .7, .4, .55, .45, -.45, body)
			var bl := B.solo("blink", body, .55, .85, -.45); B.ico(M.cyan, .06, 0, 0, 0, bl)
		"bastion":
			B.cyl(P.metal, .85, .95, .45, 8, 0, .32, 0, body); B.box(tm.col, 1.72, .06, .3, 0, .56, 0, body)
			var t := B.grp(body, "tur", Vector3(0, .6, 0))
			B.box(tm.col, .62, .3, .56, 0, .15, 0, t); B.box(tm.dk, .2, .22, .58, -.36, .13, 0, t)
			B.box(P.metal2, .9, .1, .1, .72, .17, 0, t); B.box(M.dark, .14, .14, .14, 1.15, .17, 0, t); B.flash_mesh(t, 1.25, .17, 0, .16)
		"pylon":
			B.cyl(P.metal, .25, .38, .3, 6, 0, .25, 0, body); B.cyl(M.ashM2, .1, .18, 1.2, 6, 0, .95, 0, body)
			for k in 4: B.cyl(tm.col if k % 2 else M.ashM, .2 - k * .03, .2 - k * .03, .05, 8, 0, .6 + k * .28, 0, body)
			var orb := B.solo("orb", body, 0, 1.72, 0); B.ico(M.arc, 1, 0, 0, 0, orb); orb.scale = Vector3.ONE * .15; B.nshadow[orb] = true
			B.flash_mesh(body, 0, 1.72, 0, .24, M.arcF)
		"skyfall":
			B.box(P.metal, 2.6, .55, 2.4, 0, .38, -.1, body); B.box(tm.col, 2.62, .06, 2.42, 0, .62, -.1, body)
			var i := 0
			for x in [-.8, 0.0, .8]:
				B.box(M.dark, .6, .04, 1.4, x, .66, -.2, body)
				var dl := B.solo("doorL%d" % i, body, x - .15, .69, -.2); B.box(P.metal2, .3, .06, 1.4, 0, 0, 0, dl)
				var dr := B.solo("doorR%d" % i, body, x + .15, .69, -.2); B.box(P.metal2, .3, .06, 1.4, 0, 0, 0, dr)
				var tip := B.grp(body, "tip%d" % i, Vector3(x, .3, -.2)); B.cyl(M.white, .12, .12, .5, 6, 0, .25, 0, tip); B.cone(tm.col, 6, .12, .25, .12, 0, .62, 0, tip)
				i += 1
			B.box(M.dark, 1.6, .03, .5, 0, .135, 1.05, body)
		"garden":
			# a ring of standing stones round a bed of growing aurite crystal
			for k in 8:
				var a := TAU * k / 8.0 + .2
				B.box(M.stone if k % 2 else M.stone2, .16, .3 + .12 * (k % 3), .12, cos(a) * .72, .25, sin(a) * .72, body, Vector3(0, -a, 0))
			B.cyl(M.earth, .6, .66, .1, 8, 0, .16, 0, body); B.cyl(tm.col, .66, .67, .03, 8, 0, .14, 0, body)
			var gw := B.solo("grow", body, 0, .2, 0)
			B.cluster(gw, 0, 0, 0, 6, .95, 1); B.cluster(gw, .32, 0, .22, 4, .5, 4); B.cluster(gw, -.3, 0, -.2, 4, .55, 7); B.cluster(gw, -.25, 0, .3, 3, .4, 2)
			var pool := B.solo("glow", body, 0, .23, 0); B.cyl(M.glowG, .22, .22, .01, 8, 0, 0, 0, pool); B.nshadow[pool] = true
		"burrow":
			# an earth mound over a timbered tunnel mouth, crystals breaking through the top
			B.ico(M.earth, 1, 0, .1, -.08, body, Vector3(.82, .42, .7)); B.ico(M.moss, 1, -.2, .26, -.25, body, Vector3(.35, .2, .3))
			B.box(M.dark, .48, .32, .3, 0, .22, .5, body)
			for x in [-.28, .28]: B.box(M.olive2, .07, .4, .07, x, .3, .64, body)
			B.box(M.olive2, .66, .07, .09, 0, .52, .64, body); B.box(tm.col, .3, .06, .02, 0, .52, .69, body)
			B.cluster(body, .25, .38, -.25, 4, .32, 5); B.cluster(body, -.35, .3, .1, 3, .22, 2)
		"spire":
			# rough stone needle with a crown of crystal that turns to face its target
			B.cyl(M.stone2, .14, .26, .9, 6, 0, .55, 0, body); B.cyl(tm.col, .17, .17, .05, 6, 0, .72, 0, body)
			for k in 4:
				var a := TAU * k / 4.0 + .4
				B.box(M.stone, .16, .14 + .06 * (k % 2), .14, cos(a) * .3, .19, sin(a) * .3, body, Vector3(0, a, 0))
			var t := B.grp(body, "tur", Vector3(0, 1.05, 0))
			B.gem(M.cryst, .08, .2, .08, 0, .1, 0, t)
			for k in 3:
				var a := TAU * k / 3.0
				B.gem(M.crystD, .04, .12, .04, cos(a) * .1, .02, sin(a) * .1, t, Vector3(sin(a) * .7, 0, -cos(a) * .7))
			B.gem(M.cryst, .16, .035, .035, .16, .06, 0, t)
			B.flash_mesh(t, .34, .06, 0, .12, M.glowG)
		"chorus":
			# six crystal tines round a floating heart that swells as the chorus charges
			B.cyl(M.stone2, 1.25, 1.35, .22, 8, 0, .2, 0, body); B.cyl(tm.col, 1.34, 1.36, .05, 8, 0, .15, 0, body)
			for k in 6:
				var a := TAU * k / 6.0
				var x := cos(a) * 1.0; var z := sin(a) * 1.0
				B.box(M.stone, .22, .3, .22, x, .45, z, body, Vector3(0, -a, 0))
				for o in [-.05, .05]: B.gem(M.cryst if k % 2 else M.crystD, .05, .55, .05, x + -sin(a) * o, 1.1, z + cos(a) * o, body)
			var ring := B.grp(body, "spin", Vector3(0, 1.2, 0))
			for k in 8:
				var a := TAU * k / 8.0
				B.gem(M.cryst, .05, .1, .05, cos(a) * .55, 0, sin(a) * .55, ring)
			var orb := B.solo("orb", body, 0, 1.2, 0); B.ico(M.glowG, 1, 0, 0, 0, orb); orb.scale = Vector3.ONE * .32; B.nshadow[orb] = true
		"rift":
			B.box(M.ashM2, 2.4, .3, 2.4, 0, .25, 0, body)
			for x in [-1, 1]: B.box(M.ashM, .3, 1.3, .5, x * 1.05, .9, 0, body)
			var ring := B.grp(body, "spin", Vector3(0, 1.25, 0))
			B.torus(tm.col, .9, .14, 5, 12, ring); B.torus(M.ashM, .72, .06, 4, 10, ring)
			var orb := B.solo("orb", body, 0, 1.25, 0); B.ico(M.arc, 1, 0, 0, 0, orb); orb.scale = Vector3.ONE * .32; B.nshadow[orb] = true
	if not ["wall", "turret", "flak", "pylon", "helipad", "spire", "burrow", "garden"].has(type):
		B.cyl(M.dark, .025, .025, .5, 4, -w / 2 + .18, .37, -h / 2 + .18, body); B.box(tm.col, .24, .14, .02, -w / 2 + .31, .55, -h / 2 + .18, body)
	if fac == "choir" and not ["garden", "burrow", "spire", "chorus", "wall"].has(type):
		# the Choir's yards are overgrown: crystal clusters at the corners and moss on the slabs
		var k := 0
		for c in [[-1, -1], [1, 1], [1, -1]]:
			if w < 2 and k > 0: break
			B.cluster(body, c[0] * (w / 2.0 - .2), .1, c[1] * (h / 2.0 - .2), 3 + k % 2, .28 + .1 * k, k + type.length())
			k += 1
		B.box(M.moss, w * .35, .02, h * .25, -w * .2, .125, h * .25, body)
	_detail(B, type, body, g)
	# selection outline
	var sel := B.grp(g, "sel", Vector3(0, .16, 0)); sel.visible = false; B.nshadow[sel] = true
	var gc := Color(0.5, 0.84, 0.56, 0); var hw := w / 2 + .06; var hh := h / 2 + .06
	B.box(gc, hw * 2, .02, .04, 0, 0, -hh, sel); B.box(gc, hw * 2, .02, .04, 0, 0, hh, sel)
	B.box(gc, .04, .02, hh * 2, -hw, 0, 0, sel); B.box(gc, .04, .02, hh * 2, hw, 0, 0, sel)
	return B.finish()


## Extra low-poly detail layered on each base building (windows, rails, pipes, fans, lamps, sandbags, crane, flag).
## Animated parts are named groups: fan<i>, lt<i>, flag, sock, holo, trolley, door, dl0/dl1, glow, bl0..bl2.
## Smoke and steam vents are stored as metadata ("steam", "stacks") in model space.
static func _detail(B: Builder, type: String, body: Node3D, root: Node3D) -> void:
	var M := MAT; var tm := B.tm; var P := B.P
	var steam := PackedVector3Array(); var stacks := PackedVector3Array()
	match type:
		"hq":
			B.windows(body, -1.1, .8, .62, .21, 6, .18, .14); B.windows(body, -1.15, 0.0, .62, -1.31, 4, .18, .14)
			B.box(M.dark, .42, .42, .04, -.15, .33, .22, body); B.box(tm.col, .6, .04, .22, -.15, .58, .32, body); B.lamp(body, -.15, .52, .24, M.goldGlow)
			B.rail(body, [Vector2(1.0, .18), Vector2(1.0, -1.28), Vector2(.1, -1.28)], .9, .12)
			B.rail(body, [Vector2(-1.28, -1.28), Vector2(-1.28, .18), Vector2(1.0, .18)], .9, .12)
			B.fan(body, .55, .98, -.95, .24); B.fan(body, .2, .98, -.95, .24)
			B.cyl(M.dark, .025, .035, .95, 5, -1.12, 1.4, -1.12, body)
			for y in [1.55, 1.7]: B.box(P.metal, .3, .02, .02, -1.12, y, -1.12, body)
			B.lamp(body, -1.12, 1.9, -1.12, M.redLight)
			B.pipe(M.pipe, Vector3(-1.3, .3, -1.0), Vector3(-1.3, .3, .1), .04, body); B.pipe(M.pipe, Vector3(-1.3, .3, .1), Vector3(-1.3, .12, .1), .04, body)
			B.crate(body, 1.15, .3, .2); B.crate(body, 1.2, .05, .16); B.crate(body, .98, .42, .14)
			for z in [.55, 1.15]: B.stripes(body, 0, z, 1.6, .15)
		"power":
			for t in [[-.4, -.35, .36, .62], [.42, .4, .31, .52]]:
				B.cyl(tm.col, t[2] + .01, t[2] + .01, .05, 7, t[0], t[3], t[1], body); B.cyl(M.pipe, t[2] + .06, t[2] + .06, .025, 7, t[0], t[3] + .28, t[1], body)
				steam.append(Vector3(t[0], t[3] + .62, t[1]))
			B.pipe(M.pipe, Vector3(-.15, .3, -.35), Vector3(.25, .3, -.45), .05, body); B.pipe(M.pipe, Vector3(.42, .2, .15), Vector3(.42, .2, -.25), .05, body)
			for x in [.3, .45, .6]:
				B.cyl(M.white, .025, .04, .14, 6, x, .57, -.45, body); B.ico(M.dark, .03, x, .66, -.45, body)
			B.fan(body, -.4, .43, .45, .28); B.lamp(body, .7, .55, -.7, M.redLight)
			B.stripes(body, 0, .9, 1.8, .125); B.stripes(body, -.9, 0, 1.8, .125, true)
		"refinery":
			B.windows(body, -1.2, -.05, .55, .11, 4, .16, .12)
			B.box(M.dark, .34, .04, .9, 0, .42, .45, body, Vector3(.42, 0, 0))
			for x in [-.2, .2]: B.box(P.metal2, .04, .06, .95, x, .46, .45, body, Vector3(.42, 0, 0))
			for k in 3:
				var bl := B.solo("bl%d" % k, body, 0, .5, .45); B.ico(M.goldGlow, .05, 0, 0, 0, bl, Vector3(1, .7, 1)); bl.visible = false; B.nshadow[bl] = true
			B.cone(M.metal2, 6, .3, .28, .3, 0, .42, .85, body, Vector3(PI, 0, 0))
			for x in [-.25, .25]: B.box(M.dark, .04, .25, .04, x, .25, .85, body)
			for k in 6: B.box(M.dark, .02, .02, .1, 1.32, .2 + k * .15, -.6, body)
			for z in [-.66, -.54]: B.box(M.dark, .02, .9, .02, 1.33, .6, z, body)
			for y in [.35, .85]: B.cyl(tm.col, .565, .565, .04, 8, .8, y, -.6, body)
			B.pipe(M.pipe, Vector3(.25, .75, -.45), Vector3(.15, .75, -.45), .05, body); B.pipe(M.pipe, Vector3(.3, .3, -.2), Vector3(.3, .3, .2), .04, body)
			B.cyl(P.metal2, .09, .11, .7, 6, -1.1, 1.15, -1.05, body); B.cyl(M.dark, .1, .1, .04, 6, -1.1, 1.5, -1.05, body); stacks.append(Vector3(-1.1, 1.55, -1.05))
			B.lamp(body, .3, .18, 1.3, M.goldGlow); B.lamp(body, -.3, .18, 1.3, M.goldGlow)
		"barracks":
			B.windows(body, -.6, .6, .42, .555, 2, .2, .13); B.windows(body, -.5, .3, .42, -.8, 2, .16, .13, true); B.windows(body, -.5, .3, .42, .8, 2, .16, .13, true)
			B.lamp(body, 0, .5, .6, M.goldGlow); B.bags(body, 0, .66, .35, .35, 2.8, 7)
			B.cyl(M.dark, .015, .015, 1.1, 4, .78, .67, .78, body)
			var fl := B.grp(body, "flag", Vector3(.78, 1.14, .78)); B.box(tm.col, .32, .16, .012, .17, 0, 0, fl); B.box(tm.dk, .32, .04, .014, .17, -.05, 0, fl)
			B.cyl(P.metal2, .05, .06, .35, 5, -.5, .95, -.4, body); stacks.append(Vector3(-.5, 1.15, -.4))
			B.crate(body, -.75, .75, .16); B.crate(body, -.55, .8, .13)
		"factory":
			var dr := B.solo("door", body, 0, .41, .635); B.box(P.metal2, 1.36, .6, .035, 0, 0, 0, dr)
			for k in 5: B.box(M.dark, 1.36, .012, .04, 0, -.24 + k * .12, .01, dr)
			var l0 := B.solo("dl0", body, -.78, .68, .64); B.ico(M.goldGlow, .035, 0, 0, 0, l0); B.nshadow[l0] = true
			var l1 := B.solo("dl1", body, .78, .68, .64); B.ico(M.goldGlow, .035, 0, 0, 0, l1); B.nshadow[l1] = true
			for x in [-.9, -.55]:
				B.cyl(P.metal2, .08, .1, .65, 6, x, 1.3, -1.1, body); stacks.append(Vector3(x, 1.65, -1.1))
			for x in [.3, .75]: B.fan(body, x, 1.1, -.75, .26)
			B.windows(body, -1.31, .3, .6, -1.2, 4, .16, .12, true)
			var gy := 1.15
			for x in [-.85, .85]: B.box(M.scaf, .07, gy, .07, x, gy / 2 + .12, 1.38, body)
			B.box(M.scaf, 1.82, .08, .08, 0, gy + .12, 1.38, body)
			var tr := B.grp(body, "trolley", Vector3(0, gy + .08, 1.38)); B.box(M.dark, .16, .08, .14, 0, 0, 0, tr); B.box(M.dark, .01, .4, .01, 0, -.22, 0, tr); B.box(M.gold, .1, .04, .1, 0, -.42, 0, tr)
			B.stripes(body, 0, 1.42, 1.6, .142)
		"turret", "flak":
			B.bags(body, 0, 0, .44, 0, TAU * .92, 10); B.crate(body, .36, .36, .12)
		"bastion":
			B.bags(body, 0, 0, 1.0, .3, TAU * .85, 16); B.crate(body, .8, .8, .14); B.crate(body, -.82, .78, .12); B.lamp(body, 0, .62, .88, M.redLight)
		"repair":
			for x in [-1.25, 1.25]:
				B.box(M.olive2, .18, .4, .5, x, .32, .15, body); B.box(M.gold, .19, .03, .51, x, .4, .15, body)
			B.pipe(M.dark, Vector3(-1.15, .2, .4), Vector3(-.6, .15, .9), .02, body); B.pipe(M.dark, Vector3(1.15, .2, .4), Vector3(.6, .15, .9), .02, body)
			B.lamp(body, -1.05, 1.2, .75, M.goldGlow); B.lamp(body, 1.05, 1.2, .75, M.goldGlow)
			B.stripes(body, -1.1, .15, 1.9, .15, true); B.stripes(body, 1.1, .15, 1.9, .15, true)
		"comms":
			B.windows(body, -.7, -.1, .36, .66, 3, .12, .1); B.fan(body, -.6, .6, .25, .2)
			for a in [-.4, .4]: B.pipe(M.dark, Vector3(.45, 1.9, -.25), Vector3(.45 + a * 1.4, .15, -.25 + (.3 if a > 0 else -.3)), .008, body)
		"helipad":
			B.cyl(M.dark, .015, .015, .6, 4, -.82, .4, .82, body)
			var ws := B.grp(body, "sock", Vector3(-.82, .66, .82)); B.cone(M.gold, 6, .06, .28, .06, .15, 0, 0, ws, Vector3(0, 0, PI / 2))
			B.cyl(M.tank, .16, .16, .28, 8, .72, .22, .72, body); B.cyl(M.redLight, .165, .165, .04, 8, .72, .26, .72, body)
			B.pipe(M.dark, Vector3(.6, .15, .6), Vector3(.3, .1, .3), .015, body)
		"tech":
			var hl := B.grp(body, "holo", Vector3(-.15, 1.15, -.35)); B.nshadow[hl] = true
			var hr := B.grp(hl, "holoring", Vector3.ZERO, Vector3(PI / 2, 0, 0)); B.torus(M.cyan, .32, .025, 4, 14, hr); B.nshadow[hr] = true
			B.ico(M.cyan, .07, 0, 0, 0, hl)
			B.cyl(M.dark, .015, .02, .6, 4, .55, 1.1, -.45, body); B.fan(body, .4, .7, .6, .22); B.fan(body, -.4, .7, .6, .22)
			B.windows(body, -.7, .7, .4, .81, 4, .2, .1)
		"skyfall":
			B.rail(body, [Vector2(-1.25, .95), Vector2(-1.25, -1.25), Vector2(1.25, -1.25), Vector2(1.25, .95)], .66, .1)
			B.box(P.metal2, .5, .4, .4, 1.05, .85, .85, body); B.windows(body, .9, 1.2, .88, 1.06, 2, .1, .1)
			B.lamp(body, -1.2, .85, -1.2, M.redLight); B.lamp(body, 1.2, .85, -1.2, M.redLight)
		"rift":
			for x in [-1, 1]: B.pipe(M.arc, Vector3(x * 1.05, 1.5, 0), Vector3(x * .35, 1.25, 0), .03, body)
			var rn := B.grp(body, "rune", Vector3(0, .41, 0)); _ring(B, rn, .78, .95, M.cyan); B.nshadow[rn] = true
		"pylon":
			for k in 3:
				var a := k * TAU / 3
				B.pipe(M.dark, Vector3(cos(a) * .3, .12, sin(a) * .3), Vector3(cos(a) * .08, .5, sin(a) * .08), .015, body)
	if steam.size(): root.set_meta("steam", steam)
	if stacks.size(): root.set_meta("stacks", stacks)

## Yellow scaffold around a footprint, shown while a building is assembled or dismantled.
static func scaffold(w: int, h: int, top: float) -> Node3D:
	var key := "scaf%d_%d_%d" % [w, h, int(top * 10)]
	if not cache.has(key):
		var B := Builder.new(0, "vanguard"); var c: Color = MAT.scaf
		var g := B.grp(B.root, "scaf"); B.nshadow[g] = true
		var hw := w / 2.0 + .05; var hh := h / 2.0 + .05; var H := top + .12
		for p in [[-hw, -hh], [hw, -hh], [-hw, hh], [hw, hh], [0, -hh], [0, hh], [-hw, 0], [hw, 0]]: B.box(c, .035, H, .035, p[0], H / 2, p[1], g)
		var y := .35
		while y < H:
			B.box(c, hw * 2, .025, .025, 0, y, -hh, g); B.box(c, hw * 2, .025, .025, 0, y, hh, g)
			B.box(c, .025, .025, hh * 2, -hw, y, 0, g); B.box(c, .025, .025, hh * 2, hw, y, 0, g)
			y += .35
		y = .7
		while y < H:
			B.box(c, sqrt(hw * hw * 4 + .35 * .35), .02, .02, 0, y - .17, hh, g, Vector3(0, 0, atan2(.35, hw * 2)))
			y += .7
		cache[key] = B.finish()
	return cache[key].duplicate()
