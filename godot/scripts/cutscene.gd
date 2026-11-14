extends Control
const Cutscenes := preload("res://scripts/cutscenes.gd")  # no class_name: an installed shell would not know a new global class
## Plays a scene from Cutscenes over the live 3D view: letterbox bars, a subtitle line in the bottom bar,
## title cards, a place stamp, a Skip button and fades to black. It drives View3D's camera and runs the
## scene's actions on the sim; main.gd builds the world first and steps the sim while `active`.

var main  # main.gd
var U: UI
var V: View3D
var active := false     # a scene is playing (input blocked, HUD hidden)
var sc: Dictionary
var shots: Array = []
var si := -1            # current shot
var st := 0.0           # seconds into the current shot
var fired := {}         # actions already run in this shot
var cast := {}
var on_done: Callable
var cam := [32.0, 32.0, 19.0, 0.0, 40.0]   # x, y (tiles), dist, yaw°, pitch°
var shot_from: Array = []
var follow_at = null    # smoothed centre of a followed group (tiles)

var black := 1.0        # fade to black over everything
var leaving := false    # fading out at the end (or after Skip)
var bars := 0.0         # letterbox, 0 = gone, 1 = in

var bar_top: ColorRect
var bar_bot: ColorRect
var veil: ColorRect
var who_l: Label
var line_l: Label
var sub_box: VBoxContainer
var title_box: VBoxContainer
var title_eye: Label
var title_l: Label
var title_sub: Label
var place_l: Label
var skip_btn: Button
var sub_a := 0.0; var sub_to := 0.0
var title_a := 0.0; var title_to := 0.0
var place_a := 0.0; var place_to := 0.0

const BAR := 0.13       # letterbox height, share of the screen
const FADE := 0.6

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func build(ui: UI, view: View3D) -> void:
	U = ui; V = view
	bar_top = _rect(); bar_bot = _rect()
	title_box = VBoxContainer.new(); title_box.alignment = BoxContainer.ALIGNMENT_CENTER; title_box.add_theme_constant_override("separation", 2)
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(title_box)
	title_eye = _lab(U.f_wide, 15, UI.W_BRASS); title_l = _lab(U.f_title, 46, UI.W_KHAKI); title_sub = _lab(U.f_wide, 16, UI.W_SAND)
	for l in [title_eye, title_l, title_sub]:
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75)); l.add_theme_constant_override("shadow_offset_y", 2)
		title_box.add_child(l)
	sub_box = VBoxContainer.new(); sub_box.alignment = BoxContainer.ALIGNMENT_CENTER; sub_box.add_theme_constant_override("separation", 0)
	sub_box.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(sub_box)
	who_l = _lab(U.f_wide, 13, UI.W_BRASS); line_l = _lab(U.f_body6, 21, UI.W_KHAKI)
	line_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_box.add_child(who_l); sub_box.add_child(line_l)
	place_l = _lab(U.f_wide, 13, UI.W_SAND); place_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT; add_child(place_l)
	skip_btn = U.mkbtn("Skip  ››", skip, 96, 36, 13)
	add_child(skip_btn)
	veil = _rect(); veil.set_anchors_preset(Control.PRESET_FULL_RECT); veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)

func _rect() -> ColorRect:
	var r := ColorRect.new(); r.color = Color.BLACK; r.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(r)
	return r

func _lab(f: Font, size: int, col: Color) -> Label:
	var l := U.lbl("", f, size, col); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _bar_h() -> float:
	return clampf(size.y * BAR, 46.0, 90.0)

func _layout() -> void:
	var bh := _bar_h(); var w := size.x; var h := size.y
	var slide := (1.0 - bars) * bh
	bar_top.position = Vector2(0, -slide); bar_top.size = Vector2(w, bh)
	bar_bot.position = Vector2(0, h - bh + slide); bar_bot.size = Vector2(w, bh)
	var l := U.ins_l + 16; var r := U.ins_r + 16
	sub_box.position = Vector2(l, h - bh - 2 + slide); sub_box.size = Vector2(w - l - r, bh)
	sub_box.custom_minimum_size = Vector2(w - l - r, 0)
	title_box.position = Vector2(l, bh); title_box.size = Vector2(w - l - r, h - bh * 2)
	skip_btn.position = Vector2(w - r - skip_btn.size.x, (bh - skip_btn.size.y) / 2 - slide)
	place_l.position = Vector2(l, (bh - 18) / 2 - slide); place_l.size = Vector2(w * 0.6, 18)

## Starts a scene; main has already built its world. done runs under the black once it ends or is skipped.
func start(scene: Dictionary, cast_: Dictionary, done: Callable) -> void:
	sc = scene; shots = scene.shots; cast = cast_; on_done = done
	active = true; leaving = false; visible = true; mouse_filter = Control.MOUSE_FILTER_STOP
	si = -1; black = 1.0; bars = 1.0; follow_at = null
	sub_a = 0; sub_to = 0; title_a = 0; title_to = 0; place_a = 0; place_to = 0
	who_l.text = ""; line_l.text = ""; place_l.text = ""
	skip_btn.visible = true; skip_btn.modulate.a = 0.0
	V.set_cine_look(true)
	if shots.size() and shots[0].has("cam"): cam = shots[0].cam.duplicate()
	_next()
	_apply_cam()
	_layout()

func skip() -> void:
	if active and not leaving: leaving = true

func _input(ev: InputEvent) -> void:
	if not active or leaving: return
	if ev is InputEventKey and ev.pressed and (ev.keycode == KEY_ESCAPE or ev.keycode == KEY_SPACE):
		skip(); get_viewport().set_input_as_handled()

func _next() -> void:
	si += 1; st = 0.0; fired = {}
	if si >= shots.size():
		leaving = true; return
	var s: Dictionary = shots[si]
	shot_from = s.cam.duplicate() if s.has("cam") and not s.has("follow") else cam.duplicate()
	if s.has("follow"):
		var c = Cutscenes.centre(cast, s.follow)
		follow_at = c / Sim.T if c != null else Vector2(cam[0], cam[1])
		shot_from = [follow_at.x, follow_at.y] + (s.cam.slice(2) if s.has("cam") else cam.slice(2))
	if s.has("say"):
		var w: String = s.say[0]
		who_l.text = Cutscenes.WHO.get(w, w).to_upper(); who_l.visible = who_l.text != ""
		line_l.text = s.say[1]; sub_to = 1.0
		if main and w != "": main.sfx("ack")
	else: sub_to = 0.0
	if s.has("title"):
		title_eye.text = s.title[0].to_upper(); title_l.text = s.title[1].to_upper(); title_sub.text = s.title[2].to_upper() if s.title.size() > 2 else ""
		title_eye.visible = title_eye.text != ""; title_sub.visible = title_sub.text != ""
		title_to = 1.0
	else: title_to = 0.0
	if s.has("place"):
		place_l.text = s.place.to_upper(); place_to = 1.0
	elif si > 0: place_to = 0.0

static func _ease(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

## Advances the scene. main calls it every frame while `active`, after stepping the sim.
func tick(dt: float) -> void:
	if not active: return
	if leaving:
		black = minf(1.0, black + dt / FADE)
		sub_to = 0.0; title_to = 0.0
		if black >= 1.0: _finish(); return
	else:
		black = maxf(0.0, black - dt / FADE)
		st += dt
		var s: Dictionary = shots[si]
		for i in s.get("do", []).size():
			var a: Dictionary = s.do[i]
			if not fired.has(i) and st >= a.get("t", 0.0):
				fired[i] = true; Cutscenes.act(main.S, cast, a)
		var k := _ease(st / s.d)
		var to: Array = s.get("to", s.get("cam", shot_from))
		if s.has("follow"):
			var c = Cutscenes.centre(cast, s.follow)
			if c != null: follow_at = follow_at.lerp(c / Sim.T, minf(1.0, dt * 2.0))
			to = [follow_at.x, follow_at.y] + to.slice(2)
			shot_from = [follow_at.x, follow_at.y] + shot_from.slice(2)
		for j in 5: cam[j] = lerpf(shot_from[j], to[j], k)
		# fade the subtitle out just before a shot ends, unless the next one carries on talking
		if st > s.d - 0.35: sub_to = 0.0
		if st >= s.d: _next()
	_apply_cam()
	skip_btn.modulate.a = minf(1.0, skip_btn.modulate.a + dt * 2.0)
	sub_a = move_toward(sub_a, sub_to, dt * 4.0); title_a = move_toward(title_a, title_to, dt * 1.6); place_a = move_toward(place_a, place_to, dt * 2.0)
	sub_box.modulate.a = sub_a; title_box.modulate.a = title_a; place_l.modulate.a = place_a
	veil.color.a = black
	_layout()

func _apply_cam() -> void:
	V.cam_x = cam[0] * Sim.T + 16; V.cam_y = cam[1] * Sim.T + 16; V.cam_z = 19.0 / maxf(1.0, cam[2])
	V.cine = {"yaw": deg_to_rad(cam[3]), "pitch": deg_to_rad(cam[4])}

func _finish() -> void:
	active = false; leaving = false
	V.cine = null; V.set_cine_look(false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_a = 0; title_a = 0; place_a = 0; sub_box.modulate.a = 0; title_box.modulate.a = 0; place_l.modulate.a = 0
	skip_btn.visible = false; bars = 0.0; _layout()
	var cb := on_done
	on_done = Callable()
	if cb.is_valid(): cb.call()
	# the next view fades in from black, unless another scene has started
	if not active: set_process(true); _fade_in()

func _fade_in() -> void:
	while black > 0.0 and not active:
		await get_tree().process_frame
		black = maxf(0.0, black - get_process_delta_time() / FADE)
		veil.color.a = black
	if not active: visible = false
