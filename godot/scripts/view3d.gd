class_name View3D
extends Node3D
## Draws the battle: terrain, water, decor, ore, units, buildings, effects, fog of war.

const T := 32
const MW := 64
const MH := 64
const HN := MW * 2 + 1
const PITCH := 0.95

var S: Sim
var cam_x := 1024.0
var cam_y := 1024.0
var cam_z := 1.0
var panel_px := 0.0  # width of the side panel covering the right of the screen

var camera := Camera3D.new()
var sun := DirectionalLight3D.new()
var env := Environment.new()
var fog_img: Image
var fog_tex: ImageTexture
var world := Node3D.new()
var ents_root := Node3D.new()
var recs := {}
var decor := {}
var ore_mm: MultiMeshInstance3D
var ore_list: Array = []
var ore_t := 0.0
var scorches: Array = []
var scorch_mesh: Mesh
var scorch_mat: ShaderMaterial
var batches := {}
var tracers := MeshInstance3D.new()
var tracer_mesh := ImmediateMesh.new()
var ghost: Node3D = null
var ghost_type := ""
var ghost_tiles: Dictionary
var rally := Node3D.new()
var rally_line := MeshInstance3D.new()
var rally_mesh := ImmediateMesh.new()
var preview: Dictionary
var water_mat: ShaderMaterial
var frame_no := 0

const PART_SHADER := """
shader_type spatial;
render_mode %s;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float use_fog = 1.0;
void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float f = mix(1.0, texture(fog_tex, wp.xz / 64.0).r, use_fog);
	ALBEDO = COLOR.rgb * tint.rgb * f;
	%s
}
"""

const WATER_SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, cull_disabled, depth_draw_opaque;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform vec4 water_col : source_color = vec4(0.227, 0.525, 0.659, 0.84);
varying vec3 wpos;
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(w.x * 1.3 + TIME * 1.4) * 0.035 + cos(w.z * 1.1 - TIME * 1.1) * 0.035;
	wpos = w;
}
void fragment() {
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	float f = texture(fog_tex, wpos.xz / 64.0).r;
	ALBEDO = water_col.rgb * f;
	ALPHA = water_col.a;
	ROUGHNESS = 0.25;
	SPECULAR = 0.6 * f;
}
"""

func _ready() -> void:
	fog_img = Image.create(MW, MH, false, Image.FORMAT_L8)
	fog_img.fill(Color(1, 1, 1))
	fog_tex = ImageTexture.create_from_image(fog_img)
	Models.init_materials(fog_tex)
	add_child(camera)
	camera.fov = 38; camera.near = 0.5; camera.far = 400
	camera.current = true
	sun.light_color = Color("fff0d8"); sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.shadow_bias = 0.04; sun.shadow_normal_bias = 1.0
	sun.shadow_blur = 1.0
	add_child(sun)
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0b0f12")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("aeb6be")
	env.ambient_light_energy = 0.75
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color("0b0f12")
	env.fog_density = 1.0
	env.fog_depth_curve = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)
	add_child(world); add_child(ents_root)
	var under := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(600, 600); under.mesh = pm
	var um := StandardMaterial3D.new(); um.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; um.albedo_color = Color("10161a"); under.material_override = um
	under.position = Vector3(MW / 2.0, -0.9, MH / 2.0); add_child(under)
	_init_batches()
	tracers.mesh = tracer_mesh
	var tm := StandardMaterial3D.new(); tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; tm.vertex_color_use_as_albedo = true
	tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD; tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; tm.no_depth_test = false
	tracers.material_override = tm; tracers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tracers)
	# rally flag
	add_child(rally); rally.visible = false
	rally_line.mesh = rally_mesh; var rm := StandardMaterial3D.new(); rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; rm.albedo_color = Color("7fd68e"); rally_line.material_override = rm
	add_child(rally_line)
	var flag := Models.Builder.new(0, "vanguard")
	var fg := flag.grp(flag.root, "f")
	flag.cyl(Models.MAT.dark, .025, .025, .6, 4, 0, .3, 0, fg); flag.box(Models.unlit("7fd68e"), .25, .14, .02, .13, .52, 0, fg)
	rally.add_child(flag.finish())
	# ghost tiles / formation preview markers
	ghost_tiles = _batch(_flat_quad(0.92), _pmat("unshaded, cull_disabled, depth_draw_never", "ALPHA = 0.55;", false), 12)
	preview = _batch(_disc_mesh(7), _pmat("unshaded, cull_disabled, depth_draw_never", "ALPHA = 0.7;", false), 64)
	# scorch decals
	scorch_mesh = _disc_mesh(7)
	scorch_mat = _pmat("unshaded, cull_disabled, depth_draw_never", "ALPHA = 0.6;", true)
	scorch_mat.set_shader_parameter("tint", Color("17120e"))

# ---------------- materials / batches ----------------
func _pmat(mode: String, extra: String, fog := true) -> ShaderMaterial:
	var sh := Shader.new(); sh.code = PART_SHADER % [mode, extra]
	var m := ShaderMaterial.new(); m.shader = sh
	m.set_shader_parameter("fog_tex", fog_tex); m.set_shader_parameter("use_fog", 1.0 if fog else 0.0)
	return m

func _mesh_from(kind: String, prm := {}) -> ArrayMesh:
	var B := Models.Builder.new(0, "vanguard")
	B.add(kind, prm, Color(1, 1, 1, 1), B.root, Transform3D.IDENTITY)
	var b: Array = B.bufs[B.root]
	var arr := []; arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = b[0]; arr[Mesh.ARRAY_NORMAL] = b[1]; arr[Mesh.ARRAY_COLOR] = b[2]
	var am := ArrayMesh.new(); am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	B.root.free()
	return am

func _flat_quad(s: float) -> ArrayMesh:
	var h := s / 2
	var v := PackedVector3Array([Vector3(-h, 0, -h), Vector3(h, 0, -h), Vector3(h, 0, h), Vector3(-h, 0, -h), Vector3(h, 0, h), Vector3(-h, 0, h)])
	return _flat_mesh(v)

func _disc_mesh(n: int) -> ArrayMesh:
	var v := PackedVector3Array()
	for i in n:
		var a0 := TAU * i / n; var a1 := TAU * (i + 1) / n
		v.append_array([Vector3.ZERO, Vector3(cos(a0), 0, sin(a0)), Vector3(cos(a1), 0, sin(a1))])
	return _flat_mesh(v)

func _ring_mesh(r0: float, n: int) -> ArrayMesh:
	var v := PackedVector3Array()
	for i in n:
		var a0 := TAU * i / n; var a1 := TAU * (i + 1) / n
		var p0 := Vector3(cos(a0) * r0, 0, sin(a0) * r0); var p1 := Vector3(cos(a0), 0, sin(a0)); var p2 := Vector3(cos(a1), 0, sin(a1)); var p3 := Vector3(cos(a1) * r0, 0, sin(a1) * r0)
		v.append_array([p0, p1, p2, p0, p2, p3])
	return _flat_mesh(v)

func _flat_mesh(v: PackedVector3Array) -> ArrayMesh:
	var n := PackedVector3Array(); var c := PackedColorArray()
	for i in v.size(): n.append(Vector3.UP); c.append(Color(1, 1, 1, 1))
	var arr := []; arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v; arr[Mesh.ARRAY_NORMAL] = n; arr[Mesh.ARRAY_COLOR] = c
	var am := ArrayMesh.new(); am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am

func _batch(mesh: Mesh, mat: Material, cap: int, shadow := false) -> Dictionary:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true; mm.mesh = mesh; mm.instance_count = cap; mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new(); mi.multimesh = mm; mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-10, -10, -10), Vector3(100, 60, 100))
	add_child(mi)
	var buf := PackedFloat32Array(); buf.resize(cap * 16)
	# Upload zeros once so the GPU buffer never holds uninitialised memory (some mobile GL drivers
	# otherwise draw garbage, huge stretched triangles), and hide the batch while it is empty.
	mm.buffer = buf; mi.visible = false
	return {"mm": mm, "mi": mi, "buf": buf, "n": 0, "cap": cap}

func _init_batches() -> void:
	var ico := _mesh_from("ico"); var box := _mesh_from("box"); var disc := _disc_mesh(7); var ring := _ring_mesh(0.82, 20)
	batches = {
		"smoke": _batch(ico, _pmat("diffuse_lambert, specular_disabled, depth_draw_never", "ALPHA = 0.55;"), 900),
		"spark": _batch(box, _pmat("unshaded", "", false), 600),
		"flash": _batch(ico, _pmat("unshaded, blend_add, depth_draw_never", "ALPHA = 0.85;", false), 120),
		"ring": _batch(ring, _pmat("unshaded, cull_disabled, depth_draw_never", "ALPHA = 0.9;", false), 40),
		"body": _batch(disc, _pmat("unshaded, cull_disabled", ""), 120),
		"debris": _batch(box, _pmat("diffuse_lambert, specular_disabled", "", true), 240, true),
		"shell": _batch(ico, _pmat("unshaded", "", false), 120),
		"rocket": _batch(box, _pmat("unshaded", "", false), 120),
		"heal": _batch(box, _pmat("unshaded, depth_draw_never", "ALPHA = 0.9;", false), 80),
		"flame": _batch(ico, _pmat("unshaded, blend_add, depth_draw_never", "ALPHA = 0.8;", false), 300),
		"missile": _batch(box, _pmat("unshaded", "", false), 60),
		"rift": _batch(ring, _pmat("unshaded, blend_add, cull_disabled, depth_draw_never", "ALPHA = 0.8;", false), 60),
		"shadow": _batch(disc, _pmat("unshaded, cull_disabled, depth_draw_never", "ALPHA = 0.28;", false), 80),
	}
	batches.shadow.mi.material_override.set_shader_parameter("tint", Color(0, 0, 0))
	batches.shell.mi.material_override.set_shader_parameter("tint", Color("ffe9a8"))
	batches.rocket.mi.material_override.set_shader_parameter("tint", Color("dadcd8"))
	batches.heal.mi.material_override.set_shader_parameter("tint", Color("8af5a4"))
	batches.missile.mi.material_override.set_shader_parameter("tint", Color("f2f2ee"))
	batches.flash.mi.material_override.set_shader_parameter("tint", Color("ffc070"))

func _put(b: Dictionary, x: float, y: float, z: float, sx: float, sy: float, sz: float, rx := 0.0, ry := 0.0, rz := 0.0, col := Color(1, 1, 1, 1)) -> void:
	var n: int = b.n
	if n >= b.cap: return
	var buf: PackedFloat32Array = b.buf
	var o := n * 16
	if rx == 0.0 and ry == 0.0 and rz == 0.0:
		buf[o] = sx; buf[o + 1] = 0; buf[o + 2] = 0; buf[o + 3] = x
		buf[o + 4] = 0; buf[o + 5] = sy; buf[o + 6] = 0; buf[o + 7] = y
		buf[o + 8] = 0; buf[o + 9] = 0; buf[o + 10] = sz; buf[o + 11] = z
	else:
		var bs := Basis.from_euler(Vector3(rx, ry, rz)) * Basis.from_scale(Vector3(sx, sy, sz))
		buf[o] = bs.x.x; buf[o + 1] = bs.y.x; buf[o + 2] = bs.z.x; buf[o + 3] = x
		buf[o + 4] = bs.x.y; buf[o + 5] = bs.y.y; buf[o + 6] = bs.z.y; buf[o + 7] = y
		buf[o + 8] = bs.x.z; buf[o + 9] = bs.y.z; buf[o + 10] = bs.z.z; buf[o + 11] = z
	buf[o + 12] = col.r; buf[o + 13] = col.g; buf[o + 14] = col.b; buf[o + 15] = col.a
	b.n = n + 1

func _flush(b: Dictionary) -> void:
	var mm: MultiMesh = b.mm; var mi: MultiMeshInstance3D = b.mi
	if b.n == 0:
		mi.visible = false; return
	mm.buffer = b.buf
	mm.visible_instance_count = b.n
	mi.visible = true
	b.n = 0

# ---------------- world ----------------
func build_world() -> void:
	for c in world.get_children(): c.queue_free()
	for id in recs: recs[id].n.queue_free()
	recs.clear(); scorches.clear()
	var sd: int = S.seed
	var JX := PackedFloat32Array(); JX.resize(HN * HN); var JZ := PackedFloat32Array(); JZ.resize(HN * HN)
	for j in range(1, HN - 1):
		for i in range(1, HN - 1):
			JX[j * HN + i] = (Sim.hash2(i, j, sd + 31) - .5) * .26; JZ[j * HN + i] = (Sim.hash2(i, j, sd + 32) - .5) * .26
	var verts := PackedVector3Array(); var cols := PackedColorArray(); var norms := PackedVector3Array()
	var BASEC := [Vector3(.36, .5, .22), Vector3(.5, .4, .27), Vector3(.68, .6, .42), Vector3(.47, .44, .4), Vector3(.2, .3, .33)]
	var H := S.H
	for j in HN - 1:
		for i in HN - 1:
			var a := Vector3(i / 2.0 + JX[j * HN + i], H[j * HN + i], j / 2.0 + JZ[j * HN + i])
			var b := Vector3((i + 1) / 2.0 + JX[j * HN + i + 1], H[j * HN + i + 1], j / 2.0 + JZ[j * HN + i + 1])
			var cc := Vector3(i / 2.0 + JX[(j + 1) * HN + i], H[(j + 1) * HN + i], (j + 1) / 2.0 + JZ[(j + 1) * HN + i])
			var dd := Vector3((i + 1) / 2.0 + JX[(j + 1) * HN + i + 1], H[(j + 1) * HN + i + 1], (j + 1) / 2.0 + JZ[(j + 1) * HN + i + 1])
			var tris := [[a, cc, b], [b, cc, dd]] if Sim.hash2(i, j, sd + 40) < .5 else [[a, cc, dd], [a, dd, b]]
			var tx := i >> 1; var ty := j >> 1; var t: int = S.terr[ty * MW + tx]; var ore_t := S.ore[ty * MW + tx] > 0
			for k in 2:
				var tr: Array = tris[k]
				var h0: float = tr[0].y; var h1: float = tr[1].y; var h2: float = tr[2].y
				var hmin: float = min(h0, min(h1, h2)); var hmax: float = max(h0, max(h1, h2)); var hav := (h0 + h1 + h2) / 3.0
				var base: Vector3 = BASEC[t]; var v := (Sim.hash2(i * 3 + k, j, sd + 41) - .5) * .07
				if t == D.GRASS:
					var p := Sim.fbm(i / 9.0, j / 9.0, sd + 50); base = Vector3(.3 + p * .12, .42 + p * .1, .2 + p * .04)
				if hmax - hmin > .28 and t != D.WATER: base = Vector3(.44, .41, .37)
				if t == D.ROCK: base = Vector3(.4 + hav * .12, .37 + hav * .11, .33 + hav * .1)
				if ore_t: base = Vector3(.5, .4, .24)
				if t == D.WATER: base = Vector3(.22, .3, .3) if hav < -.4 else Vector3(.62, .56, .4)
				var col := Color(base.x + v, base.y + v, base.z + v * .8).srgb_to_linear()
				var p0: Vector3 = tr[0]; var p1: Vector3 = tr[1]; var p2: Vector3 = tr[2]
				var n := (p1 - p0).cross(p2 - p0).normalized()
				if n.y < 0: n = -n
				# clockwise for Godot: tris above are counter-clockwise seen from above
				verts.append_array([p0, p2, p1])
				for q in 3: cols.append(col); norms.append(n)
	var arr := []; arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts; arr[Mesh.ARRAY_NORMAL] = norms; arr[Mesh.ARRAY_COLOR] = cols
	var am := ArrayMesh.new(); am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr); am.surface_set_material(0, Models.material)
	var terr := MeshInstance3D.new(); terr.mesh = am; world.add_child(terr)
	# water
	var wm := PlaneMesh.new(); wm.size = Vector2(MW, MH); wm.subdivide_width = 40; wm.subdivide_depth = 40
	var water := MeshInstance3D.new(); water.mesh = wm; water.position = Vector3(MW / 2.0, -0.24, MH / 2.0)
	var wsh := Shader.new(); wsh.code = WATER_SHADER; water_mat = ShaderMaterial.new(); water_mat.shader = wsh; water_mat.set_shader_parameter("fog_tex", fog_tex)
	water.material_override = water_mat; water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(water)
	# decor
	var R := RandomNumberGenerator.new(); R.seed = sd + 77
	var trees: Array = []; var rocks: Array = []; var bushes: Array = []
	var A := Vector2(MW - 1 - D.P0.x, MH - 1 - D.P0.y)
	for ty in MH:
		for tx in MW:
			var i := ty * MW + tx; var t: int = S.terr[i]
			if S.ore[i]: continue
			var near := Vector2(tx, ty).distance_to(Vector2(D.P0)) < 6 or Vector2(tx, ty).distance_to(A) < 6
			if t == D.GRASS and not near:
				var r := R.randf()
				if r < .075: trees.append({"tx": tx, "ty": ty, "x": tx + .2 + R.randf() * .6, "z": ty + .2 + R.randf() * .6, "s": .75 + R.randf() * .6, "c": R.randf()})
				elif r < .16: bushes.append({"tx": tx, "ty": ty, "x": tx + R.randf(), "z": ty + R.randf(), "s": .12 + R.randf() * .1})
			elif t == D.ROCK and R.randf() < .18: rocks.append({"tx": tx, "ty": ty, "x": tx + R.randf(), "z": ty + R.randf(), "s": .18 + R.randf() * .25, "ry": R.randf() * 6})
			elif (t == D.DIRT or t == D.SAND) and R.randf() < .05: rocks.append({"tx": tx, "ty": ty, "x": tx + R.randf(), "z": ty + R.randf(), "s": .06 + R.randf() * .07, "ry": R.randf() * 6})
	var lit := Models.material
	decor = {"trees": trees, "rocks": rocks, "bushes": bushes,
		"trunk": _wbatch(_mesh_from("cyl", {"rt": .7, "seg": 5}), lit, trees.size()),
		"crown": _wbatch(_mesh_from("cone", {"seg": 5}), lit, trees.size() * 2),
		"rk": _wbatch(_mesh_from("ico"), lit, rocks.size()),
		"bu": _wbatch(_mesh_from("ico"), lit, bushes.size())}
	# ore
	ore_list = []
	for i in MW * MH:
		if S.ore[i]: ore_list.append(i)
	var om := _mesh_from("oct")
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true; mm.mesh = om; mm.instance_count = max(1, ore_list.size() * 5)
	var zb := PackedFloat32Array(); zb.resize(mm.instance_count * 16); mm.buffer = zb; mm.visible_instance_count = 0
	ore_mm = MultiMeshInstance3D.new(); ore_mm.multimesh = mm; ore_mm.material_override = lit; world.add_child(ore_mm)
	refresh_decor(); upd_ore()

func _wbatch(mesh: Mesh, mat: Material, n: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true; mm.mesh = mesh; mm.instance_count = max(1, n)
	var zb := PackedFloat32Array(); zb.resize(mm.instance_count * 16); mm.buffer = zb
	mm.visible_instance_count = n
	var mi := MultiMeshInstance3D.new(); mi.multimesh = mm; mi.material_override = mat
	world.add_child(mi)
	return mi

func _xf(x: float, y: float, z: float, sx: float, sy: float, sz: float, rx := 0.0, ry := 0.0, rz := 0.0) -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(rx, ry, rz)) * Basis.from_scale(Vector3(sx, sy, sz)), Vector3(x, y, z))

func refresh_decor() -> void:
	if decor.is_empty(): return
	var tc := [Color("3f6b2c"), Color("4f7d33"), Color("355e2a"), Color("6b8a3a")]
	var trunk_c := Color("5a4130").srgb_to_linear(); var rock_c := Color("8a8174").srgb_to_linear(); var bush_c := Color("4f7a34").srgb_to_linear()
	var tr: MultiMesh = decor.trunk.multimesh; var cr: MultiMesh = decor.crown.multimesh; var rk: MultiMesh = decor.rk.multimesh; var bu: MultiMesh = decor.bu.multimesh
	var k := 0
	for t in decor.trees:
		var s: float = 0.001 if S.bmap[t.ty * MW + t.tx] else t.s
		var y := S.h_at(t.x * T, t.z * T)
		tr.set_instance_transform(k, _xf(t.x, y + .12 * s, t.z, .06 * s, .25 * s, .06 * s)); tr.set_instance_color(k, trunk_c)
		var c: Color = tc[int(t.c * 4)].srgb_to_linear()
		cr.set_instance_transform(k * 2, _xf(t.x, y + .42 * s, t.z, .3 * s, .45 * s, .3 * s, 0, t.c * 3)); cr.set_instance_color(k * 2, c)
		cr.set_instance_transform(k * 2 + 1, _xf(t.x, y + .68 * s, t.z, .22 * s, .35 * s, .22 * s, 0, t.c * 5)); cr.set_instance_color(k * 2 + 1, c)
		k += 1
	k = 0
	for t in decor.rocks:
		var s: float = 0.001 if S.bmap[t.ty * MW + t.tx] else t.s
		rk.set_instance_transform(k, _xf(t.x, S.h_at(t.x * T, t.z * T) + s * .3, t.z, s, s * .7, s, t.ry, t.ry * 2)); rk.set_instance_color(k, rock_c); k += 1
	k = 0
	for t in decor.bushes:
		var s: float = 0.001 if S.bmap[t.ty * MW + t.tx] else t.s
		bu.set_instance_transform(k, _xf(t.x, S.h_at(t.x * T, t.z * T) + s * .4, t.z, s * 1.2, s * .8, s * 1.2, 0, k)); bu.set_instance_color(k, bush_c); k += 1

func upd_ore() -> void:
	if ore_mm == null: return
	var mm := ore_mm.multimesh; var n := 0; var gc := Color("f2c443").srgb_to_linear(); gc.a = 0.75
	for i in ore_list:
		var a: int = S.ore[i]
		if a == 0 or S.vis[i] == 0: continue
		var tx: int = i % MW; var ty: int = i / MW; var cnt := mini(5, 1 + a / 110)
		for k in cnt:
			var h1 := Sim.hash2(tx, ty, k * 3 + 1); var h2 := Sim.hash2(tx, ty, k * 3 + 2); var h3 := Sim.hash2(tx, ty, k * 3 + 3)
			var x := tx + .15 + h1 * .7; var z := ty + .15 + h2 * .7; var s: float = .05 + h3 * .045 + min(1.0, a / 400.0) * .04
			mm.set_instance_transform(n, _xf(x, S.h_at(x * T, z * T) + s * .9, z, s, s * 2.1, s, (h1 - .5) * .6, h3 * 6, (h2 - .5) * .6))
			mm.set_instance_color(n, gc); n += 1
	mm.visible_instance_count = n

func add_scorch(x: float, y: float, r: float) -> void:
	var m := MeshInstance3D.new(); m.mesh = scorch_mesh; m.material_override = scorch_mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.scale = Vector3(r / T * 1.1, 1, r / T); m.rotation.y = randf() * 6; m.position = Vector3(x / T, S.h_at(x, y) + .035, y / T)
	m.sorting_offset = -1
	world.add_child(m); scorches.append(m)
	if scorches.size() > 60: scorches.pop_front().queue_free()

func upd_fog() -> void:
	var data := PackedByteArray(); data.resize(MW * MH)
	var V := S.vis
	for i in MW * MH: data[i] = 255 if V[i] == 2 else (118 if V[i] == 1 else 14)
	fog_img.set_data(MW, MH, false, Image.FORMAT_L8, data)
	fog_tex.update(fog_img)

func fog_clear(on: bool) -> void:
	if on:
		fog_img.fill(Color(1, 1, 1)); fog_tex.update(fog_img)
	else: upd_fog()

# ---------------- camera ----------------
func cam_dist() -> float:
	return 19.0 / cam_z

func clamp_cam() -> void:
	cam_z = clamp(cam_z, 0.5, 2.4)
	cam_x = clamp(cam_x, T, D.WW - T); cam_y = clamp(cam_y, T * 2, D.WH - T)

func update_cam() -> void:
	var d := cam_dist(); var fx := cam_x / T; var fz := cam_y / T
	camera.position = Vector3(fx, sin(PITCH) * d, fz + cos(PITCH) * d)
	camera.look_at(Vector3(fx, 0, fz), Vector3.UP)
	var vh := get_viewport().get_visible_rect().size.y
	camera.h_offset = panel_px / 2.0 * (2.0 * d * tan(deg_to_rad(camera.fov) / 2.0)) / max(1.0, vh)
	var cz := fz - d * .25
	sun.position = Vector3(fx - 12, 24, cz + 9)
	sun.look_at(Vector3(fx, 0, cz), Vector3.UP)
	sun.directional_shadow_max_distance = d * 2.6 + 6
	env.fog_depth_begin = d * 1.15; env.fog_depth_end = d * 2.8 + 12

## Window pixels per UI unit (stretch mode). Camera3D project/unproject already work in UI units.
func ui_scale() -> float:
	return get_viewport().get_stretch_transform().get_scale().x

func ray(sx: float, sy: float) -> Array:
	var p := Vector2(sx, sy)
	return [camera.project_ray_origin(p), camera.project_ray_normal(p)]

func s2w(sx: float, sy: float) -> Vector2:
	update_cam()
	var rr := ray(sx, sy); var o: Vector3 = rr[0]; var n: Vector3 = rr[1]
	if abs(n.y) < 1e-5: return Vector2(cam_x, cam_y)
	var t := -o.y / n.y
	if t < 0: return Vector2(cam_x, cam_y)
	var p := o + n * t
	return Vector2(p.x * T, p.z * T)

## Screen position of a world point, z < 0 when behind the camera.
func w2s(x: float, y: float, h: float) -> Vector3:
	var p := Vector3(x / T, h, y / T)
	if camera.is_position_behind(p): return Vector3(0, 0, -1)
	var s := camera.unproject_position(p)
	return Vector3(s.x, s.y, 1)

func view_rect() -> Rect2:
	var r := get_viewport().get_visible_rect()
	r.size.x -= panel_px
	return r

func on_screen(x: float, y: float, pad := 40.0) -> bool:
	var p := w2s(x, y, S.h_at(x, y))
	var r := view_rect().grow(pad)
	return p.z > 0 and r.has_point(Vector2(p.x, p.y))

func center_on(x: float, y: float) -> void:
	cam_x = x; cam_y = y; clamp_cam()

# ---------------- entities ----------------
func _mk_rec(e: Ent) -> Dictionary:
	var fac: String = S.teams[e.team].fac
	var n := Models.get_model(e.kind, e.type, e.team, fac)
	ents_root.add_child(n)
	var r := {"n": n, "team": e.team, "f": 0}
	for k in ["body", "tur", "flash", "legL", "legR", "orb", "cargo", "scoop", "tube", "spin", "blink", "arm", "tool", "lamp", "lamp2", "rot", "tr", "sel"]:
		var c := n.find_child(k, true, false)
		if c: r[k] = c
	var rots: Array = []
	for i in 4:
		var c := n.find_child("rot%d" % i, true, false)
		if c: rots.append(c)
	if rots.size(): r.rots = rots
	if e.type == "skyfall":
		r.doors = []; r.tips = []
		for i in 3:
			r.doors.append([n.find_child("doorL%d" % i, true, false), n.find_child("doorR%d" % i, true, false), [-.8, 0.0, .8][i]])
			r.tips.append(n.find_child("tip%d" % i, true, false))
	if e.kind == "b":
		n.position = Vector3(e.tx + e.w / 2.0, S.h_at(e.x, e.y), e.ty + e.h / 2.0)
	return r

func sync_ents(t: float) -> void:
	frame_no += 1
	for e in S.ents:
		if not e.alive: continue
		var r = recs.get(e.id)
		if r != null and r.team != e.team:
			r.n.queue_free(); r = null
		if r == null:
			r = _mk_rec(e); recs[e.id] = r
		r.f = frame_no
		var vis: bool = e.team == 0 or S.visible_to_player(e)
		r.n.visible = vis
		if not vis: continue
		r.sel.visible = e.sel
		var n: Node3D = r.n
		if e.kind == "u":
			var air: bool = e.d.air
			n.position = Vector3(e.x / T, (max(S.h_at(e.x, e.y), 0.0) + D.ALT + sin(t * 2 + e.id) * .06) if air else S.h_at(e.x, e.y), e.y / T)
			n.rotation.y = -e.ang
			if air:
				r.body.rotation.z = -.18 if e.moving else 0.0
				if r.has("rot"): r.rot.rotation.y = t * 25
				if r.has("tr"): r.tr.rotation.y = t * 30
				if r.has("rots"):
					for i in r.rots.size(): r.rots[i].rotation.y = t * (-30 if i % 2 else 30)
				r.sel.position.y = -D.ALT + .04
			if r.has("orb"): r.orb.scale = Vector3.ONE * .08 * (1 + .15 * sin(t * 8 + e.id))
			if r.has("tur"): r.tur.rotation.y = -(e.tang - e.ang)
			if r.has("flash"): r.flash.visible = e.flash > 0
			if r.has("legL") and not air:
				var sw: float = sin(t * 14 + e.id) * .05 if e.moving else 0.0
				r.legL.position.x = sw; r.legR.position.x = -sw
				r.body.position.y = abs(sin(t * 14 + e.id)) * .025 if e.moving else 0.0
			elif not air: r.body.position.y = sin(t * 30 + e.id) * .006 if e.moving else 0.0
			if r.has("cargo"):
				var f: float = max(.01, e.load / D.HARV_CAP)
				r.cargo.scale.y = .2 * f; r.cargo.position.y = .35 + .1 * f
			if r.has("scoop"): r.scoop.position.y = .1 + sin(t * 20) * .03 if e.hs == "mine" else .1
			if r.has("tube"): r.tube.rotation.z = -.9 + (.15 if e.flash > 0 else 0.0)
		else:
			var age: float = t - e.born; var k: float = clamp(age / .6, .05, 1.0)
			r.body.scale.y = 1 - (1 - k) * (1 - k) if k < 1 else 1.0
			if r.has("tur"): r.tur.rotation.y = -e.tang
			if r.has("flash"): r.flash.visible = e.flash > 0
			if r.has("spin"): r.spin.rotation.y = t * ((.6 + e.ch / D.BLD.rift.charge * 2.5) if e.type == "rift" else .9)
			if r.has("orb"):
				var c: float = e.ch / D.BLD.rift.charge if e.type == "rift" else 1.0
				r.orb.scale = Vector3.ONE * ((.2 + .2 * c) if e.type == "rift" else .15) * (1 + .12 * sin(t * 7))
			if r.has("doors"):
				var o: float = 1.0 if e.rdy else max(0.0, (e.ch / D.BLD.skyfall.charge - .85) / .15)
				for dr in r.doors:
					dr[0].position.x = dr[2] - .15 - o * .3; dr[1].position.x = dr[2] + .15 + o * .3
				for tp in r.tips: tp.position.y = .3 + o * .25
			if r.has("blink"): r.blink.visible = sin(t * 4) > 0
			if r.has("arm"):
				r.arm.position.x = sin(t * 2.2) * .8 if e.busy else r.arm.position.x * .95
				r.tool.position.y = -.25 + sin(t * 9) * .05 if e.busy else -.2
				r.lamp.visible = not e.busy; r.lamp2.visible = e.busy
	var gone: Array = []
	for id in recs:
		if recs[id].f != frame_no: gone.append(id)
	for id in gone:
		recs[id].n.queue_free(); recs.erase(id)

# ---------------- particles & projectiles ----------------
func _top_at(x: float, y: float) -> float:
	var tx := int(x / T); var ty := int(y / T)
	if not Sim.inb(tx, ty): return .15
	var id: int = S.bmap[ty * MW + tx]
	if id and S.by_id.has(id): return D.BH[S.by_id[id].type] * .8
	return S.h_at(x, y) + .15

func draw_parts() -> void:
	var tm := tracer_mesh
	tm.clear_surfaces()
	var lines := 0
	var vr := view_rect().grow(120)
	tm.surface_begin(Mesh.PRIMITIVE_LINES)
	for p in S.parts:
		var f: float = p.life / p.max; var X: float = p.x / T; var Z: float = p.y / T
		var k: String = p.k
		if k != "tracer" and k != "ring" and k != "body" and k != "heal":
			var sp := w2s(p.x, p.y, .2)
			if sp.z < 0 or not vr.has_point(Vector2(sp.x, sp.y)): continue
		if not p.has("h0"): p.h0 = _top_at(p.x, p.y) if (k == "smoke" or k == "spark") else S.h_at(p.x, p.y)
		var h0: float = p.h0
		match k:
			"smoke":
				var s: float = p.s / T * (1.8 - f) * 1.3; var c: Color = p.c * (.7 + f * .5)
				_put(batches.smoke, X, h0 + (1 - f) * (.5 + p.s * .08), Z, s, s * .8, s, p.life, p.life * 2, 0, c.srgb_to_linear())
			"spark":
				var s: float = p.s / T * 1.6
				_put(batches.spark, X, h0 + sin((1 - f) * PI) * .35, Z, s, s, s, 0, 0, 0, p.c)
			"flash":
				var s: float = p.s / T * (1.4 - f * .5) * 1.3 * sqrt(f)
				_put(batches.flash, X, h0 + .3, Z, s, s, s)
			"ring":
				var s := (4 + 14 * (1 - f)) / T * 1.3; var c: Color = p.c; c = Color(c.r * f, c.g * f, c.b * f)
				_put(batches.ring, X, S.h_at(p.x, p.y) + .05, Z, s, 1, s, 0, 0, 0, c)
			"body":
				var s: float = min(1.0, f * 3)
				_put(batches.body, X, h0 + .03, Z, .15 * s, 1, .09 * s, 0, p.rot, 0, p.c)
			"debris":
				_put(batches.debris, X, p.h + S.h_at(p.x, p.y), Z, p.s, p.s * .7, p.s, p.life * p.r0, p.life * 3, 0, Color(.2, .19, .18).srgb_to_linear())
			"heal":
				var y := h0 + .55 + (1 - f) * .4
				_put(batches.heal, X, y, Z, .03 * f, .12 * f, .03 * f); _put(batches.heal, X, y, Z, .12 * f, .03 * f, .03 * f)
			"tracer":
				if lines >= 400: continue
				var ha: float = p.ha; var hb: float = p.hb
				var c := Color(f, f * .92, f * (.9 if p.c else .6))
				tm.surface_set_color(c); tm.surface_add_vertex(Vector3(X, ha, Z))
				tm.surface_set_color(c); tm.surface_add_vertex(Vector3(p.x2 / T, hb, p.y2 / T)); lines += 1
			"arc":
				var ax := X; var ay: float = p.ha if p.ha != null else h0 + .5; var az := Z
				var bx: float = p.x2 / T; var by := S.h_at(p.x2, p.y2) + .3; var bz: float = p.y2 / T
				var R := RandomNumberGenerator.new(); R.seed = int(p.seed * 1000) + int(S.time * 20)
				var N := 6
				for q in range(1, N + 1):
					if lines >= 400: break
					var j := .18 if q < N else 0.0; var dv := float(N - q + 1)
					var nx := ax + (bx - ax) / dv + (R.randf() - .5) * j; var ny := ay + (by - ay) / dv + (R.randf() - .5) * j; var nz := az + (bz - az) / dv + (R.randf() - .5) * j
					var c := Color(f * .8, f * .6, f)
					tm.surface_set_color(c); tm.surface_add_vertex(Vector3(ax, ay, az)); tm.surface_set_color(c); tm.surface_add_vertex(Vector3(nx, ny, nz))
					lines += 1; ax = nx; ay = ny; az = nz
				_put(batches.flash, bx, by, bz, .12 * f, .12 * f, .12 * f)
			"flame":
				var s: float = p.s / T * (1.6 - f) * 1.2
				_put(batches.flame, X, h0 + .2 + (1 - f) * .25, Z, s, s, s, 0, 0, 0, Color(1, .35 + f * .45, .08 * f))
			"missile":
				var y: float = p.h + S.h_at(p.x, p.y)
				_put(batches.missile, X, y, Z, .06, .35, .06); _put(batches.flame, X, y + .3, Z, .08, .12, .08, 0, 0, 0, Color(1, .6, .2))
			"rift":
				var kk: float = p.f; var s := 3.4 * (1 - kk * .85) + .1; var gh := S.h_at(p.x, p.y)
				_put(batches.rift, X, gh + .1 + kk * .5, Z, s, 1, s, 0, S.time * 3, 0, Color(.6 * f, .4 * f, f))
				_put(batches.rift, X, gh + .3 + kk * 1.2, Z, s * .6, 1, s * .6, 0, -S.time * 4, 0, Color(.8 * f, .5 * f, f))
	if lines == 0:
		tm.surface_set_color(Color(0, 0, 0)); tm.surface_add_vertex(Vector3.ZERO); tm.surface_add_vertex(Vector3.ZERO)
	tm.surface_end()
	for e in S.ents:
		if not e.alive or e.kind != "u" or not e.d.air or (e.team != 0 and not S.visible_to_player(e)): continue
		var s: float = e.r / T * 1.3
		_put(batches.shadow, e.x / T, S.h_at(e.x, e.y) + .03, e.y / T, s, 1, s)
	for p in S.proj:
		var X: float = p.x / T; var Z: float = p.y / T
		if p.w == "shell" or p.w == "arty" or p.w == "flak":
			var s := .07 if p.w == "arty" else .045
			_put(batches.shell, X, p.h, Z, s, s, s)
		else:
			_put(batches.rocket, X, p.h, Z, .16, .035, .035, 0, -p.ang, 0)
	for k in batches: _flush(batches[k])

# ---------------- ghost, rally, formation preview ----------------
func upd_ghost(placing) -> void:
	if placing == null:
		if ghost: ghost.visible = false
		_flush(ghost_tiles); return
	if ghost == null or ghost_type != placing.type:
		if ghost: ghost.queue_free()
		ghost = Models.get_model("b", placing.type, 0, S.teams[0].fac); ghost_type = placing.type
		for c in ghost.find_children("*", "MeshInstance3D", true, false):
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var s := ghost.find_child("sel", true, false)
		if s: s.queue_free()
		add_child(ghost)
	var d: Dictionary = D.BLD[placing.type]
	var ok := S.can_place(0, placing.type, placing.tx, placing.ty, false)
	ghost.visible = true; ghost.position = Vector3(placing.tx + d.w / 2.0, .02, placing.ty + d.h / 2.0)
	for c in ghost.find_children("*", "MeshInstance3D", true, false): c.material_override = Models.ghost_ok if ok else Models.ghost_bad
	var okc := Color("7fd68e"); var bad := Color("ff5a52")
	for y in range(placing.ty, placing.ty + d.h):
		for x in range(placing.tx, placing.tx + d.w):
			_put(ghost_tiles, x + .5, S.h_at(x * T + 16, y * T + 16) + .06, y + .5, 1, 1, 1, 0, 0, 0, okc if (S.tile_ok(x, y) and ok) else bad)
	_flush(ghost_tiles)

func upd_rally() -> void:
	var b: Ent = S.sel[0] if (S.sel.size() == 1 and S.sel[0].kind == "b") else null
	rally_mesh.clear_surfaces()
	if b == null or b.rally == null:
		rally.visible = false; return
	rally.visible = true
	var a := Vector3(b.x / T, D.BH[b.type] * .6, b.y / T); var e := Vector3(b.rally.x / T, S.h_at(b.rally.x, b.rally.y) + .1, b.rally.y / T)
	rally_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var L := a.distance_to(e); var n := int(L / .55)
	for i in n:
		rally_mesh.surface_add_vertex(a.lerp(e, i / float(n))); rally_mesh.surface_add_vertex(a.lerp(e, (i + .55) / float(n)))
	if n == 0: rally_mesh.surface_add_vertex(a); rally_mesh.surface_add_vertex(e)
	rally_mesh.surface_end()
	rally.position = Vector3(b.rally.x / T, S.h_at(b.rally.x, b.rally.y), b.rally.y / T)

## Formation drag preview: one marker per planned slot plus an arrow of markers along the facing.
func upd_preview(slots: Array, from, to) -> void:
	var c := Color("7fd68e")
	for sl in slots:
		_put(preview, sl.x + .5, S.h_at(sl.x * T + 16, sl.y * T + 16) + .05, sl.y + .5, .18, 1, .18, 0, 0, 0, c)
	if from != null and to != null:
		var a: Vector2 = from; var b: Vector2 = to; var L := a.distance_to(b) / T
		var n := int(L / .35)
		for i in n + 1:
			var p := a.lerp(b, i / float(max(1, n)))
			_put(preview, p.x / T, S.h_at(p.x, p.y) + .07, p.y / T, .07, 1, .07, 0, 0, 0, Color("f0b93f"))
	_flush(preview)

func render(dt: float, placing, preview_slots: Array, pv_from, pv_to) -> void:
	update_cam()
	if S == null: return
	sync_ents(S.time); draw_parts(); upd_ghost(placing); upd_rally(); upd_preview(preview_slots, pv_from, pv_to)
	ore_t -= dt
	if ore_t <= 0: ore_t = .3; upd_ore()
