class_name UI
extends Control
## All screen UI, built in code: HUD, side panel, overlays. Game logic lives in main.gd.

const C_BG := Color("0b0f12")
const C_PANEL := Color("141a1e")
const C_PANEL2 := Color("1b2328")
const C_LINE := Color("2a353c")
const C_FG := Color("e4ebee")
const C_DIM := Color("8b9aa3")
const C_AUR := Color("f0b93f")
const C_ACC := Color("e5483f")
const C_OK := Color("7fd68e")
const C_BAD := Color("ff5a52")
const PANEL_W := 188.0

var main  # main.gd
var f_disp: FontFile
var f_disp6: FontFile
var f_disp7: FontFile
var f_body: FontFile
var f_body6: FontFile

var hud: Control
var credits_l: Label
var power_l: Label
var power_bar: PowerMeter
var power_box: PanelContainer
var sw_box: Plate
var sw_name: Label
var sw_time: Label
var obj_l: RichTextLabel
var obj_box: Plate
var toast_box: Plate
var toast_l: Label
var toast_t := 0.0
var cmd_row: VBoxContainer
var cmd_top: HBoxContainer
var cmd_bot: HBoxContainer
var btn := {}
var selinfo: Label
var mode_btn: ModeDial
var place_bar: HBoxContainer
var place_hint: Label
var panel: PanelContainer
var mini: Control
var big_map: Control      # enlarged minimap floating over the view (MAP button)
var prod_chips := {}      # cat -> ProdChip: what is being built, shown in the top bar while the panel is hidden
var obj_btn: Button       # brings the objective back after it hides itself
var groups_box: VBoxContainer
var tabs := {}
var grid: GridContainer
var grid_scroll: ScrollContainer
var items := {}
var overlays := {}
var camp_pane: VBoxContainer
var camp_scroll: ScrollContainer
var press_scroll := 0
var sk_pane: VBoxContainer
var seg_btns := {}

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func font(path: String) -> FontFile:
	var f: FontFile = load(path)
	return f

func build() -> void:
	f_disp = font("res://fonts/chakra-petch-latin-600-normal.woff2")
	f_disp7 = font("res://fonts/chakra-petch-latin-700-normal.woff2")
	f_disp6 = font("res://fonts/chakra-petch-latin-500-normal.woff2")
	f_body = font("res://fonts/barlow-latin-500-normal.woff2")
	f_body6 = font("res://fonts/barlow-latin-600-normal.woff2")
	var th := Theme.new()
	th.default_font = f_body; th.default_font_size = 14
	th.set_color("font_color", "Label", C_FG)
	th.set_color("font_color", "Button", C_FG)
	th.set_color("font_hover_color", "Button", C_FG)
	th.set_color("font_pressed_color", "Button", C_FG)
	th.set_color("font_focus_color", "Button", C_FG)
	th.set_color("font_disabled_color", "Button", C_DIM)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		th.set_stylebox(st, "Button", sb(Color(0.08, 0.1, 0.12, 0.92), C_LINE))
	th.set_stylebox("hover", "Button", sb(Color(0.11, 0.14, 0.16, 0.95), Color("3b4a54")))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_stylebox("panel", "PanelContainer", sb(Color(0.047, 0.063, 0.075, 0.84), C_LINE))
	theme = th
	_wide_fonts()
	_build_hud()
	_build_panel()
	_build_overlays()

static func sb(bg: Color, border := Color(0, 0, 0, 0), bw := 1, rad := 3, pad := 6.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new(); s.bg_color = bg; s.border_color = border
	s.set_border_width_all(bw); s.set_corner_radius_all(rad)
	s.content_margin_left = pad + 2; s.content_margin_right = pad + 2; s.content_margin_top = pad; s.content_margin_bottom = pad
	return s

func lbl(text: String, f: Font, size: int, col := C_FG) -> Label:
	var l := Label.new(); l.text = text
	l.add_theme_font_override("font", f); l.add_theme_font_size_override("font_size", size); l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## A HUD button: a chamfered olive plate with a brass glyph (see `glyph`) left of its text, or centred when it has no text.
func mkbtn(text: String, cb: Callable, w := 0.0, h := 42.0, size := 12, g := "") -> Button:
	var b := HudBtn.new(); b.text = text.to_upper(); b.glyph = g
	b.add_theme_font_override("font", f_disp); b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(max(w, 48.0), h)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	restyle(b)
	return b

# HUD plate colours: olive-black field plates with brass trim, like the menus
const H_BG := Color(0.055, 0.062, 0.045, 0.9)
const H_BG2 := Color(0.09, 0.1, 0.07, 0.94)
const H_ON := Color("3a1512")

var _sb_cache := {}
## Plate stylebox for a HUD button state, cached (update_cmd restyles buttons several times a second).
func hsb(state: String, on: bool, ml: float, mr: float) -> StyleBoxFlat:
	var key := "%s%s%d_%d" % [state, on, ml, mr]
	if _sb_cache.has(key): return _sb_cache[key]
	var bg := H_ON if on else H_BG
	var bd := C_ACC if on else W_LINE
	match state:
		"hover": bd = C_ACC.lightened(0.15) if on else W_SAND
		"pressed": bg = bg.darkened(0.35); bd = W_BRASS
		"disabled": bg = Color(bg, 0.6); bd = Color(W_LINE, 0.5)
	var s := cut(bg, bd, 2 if on else 1, 7, 6.0)
	s.content_margin_left = ml; s.content_margin_right = mr
	s.shadow_color = Color(0, 0, 0, 0.35); s.shadow_size = 3; s.shadow_offset = Vector2(0, 2)
	s.anti_aliasing = true
	_sb_cache[key] = s
	return s

## Applies the plate styles to a HUD button for its current glyph, text and on state.
func restyle(b: Button) -> void:
	var on: bool = b.get_meta("on", false)
	var g: String = b.glyph if b is HudBtn else ""
	var ml := 10.0; var mr := 10.0
	if g != "" and b.text != "" and not (b is HudBtn and b.cap != ""): ml = 36.0; mr = 12.0
	for st in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(st, hsb(st, on, ml, mr))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, Color("ffd8d2") if on else W_KHAKI)
	b.queue_redraw()

func set_on(b: Button, on: bool) -> void:
	if b.get_meta("on", false) == on and b.has_theme_stylebox_override("normal"): return
	b.set_meta("on", on); restyle(b)

# ---------------- HUD ----------------
func _build_hud() -> void:
	hud = Control.new(); hud.name = "HUD"; hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.anchor_right = 1; hud.anchor_bottom = 1; hud.offset_right = -PANEL_W
	add_child(hud)
	var draw := HudDraw.new(); draw.ui = self; draw.set_anchors_preset(Control.PRESET_FULL_RECT); draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(draw); hud.set_meta("draw", draw)
	var top := HBoxContainer.new(); top.position = Vector2(8, 8); top.add_theme_constant_override("separation", 6); top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.anchor_right = 1; top.offset_right = -8
	hud.add_child(top)
	# resource strip: one brass-trimmed plate, aurite then power with a segmented meter
	var res := Plate.new(); res.mouse_filter = Control.MOUSE_FILTER_IGNORE
	res.add_theme_stylebox_override("panel", plate_sb(8.0)); top.add_child(res)
	var rh := HBoxContainer.new(); rh.add_theme_constant_override("separation", 10); rh.mouse_filter = Control.MOUSE_FILTER_IGNORE; res.add_child(rh)
	rh.add_child(_glyph_box("aur", 24, C_AUR))
	var cv := _stat(rh, "AURITE"); credits_l = lbl("0", f_disp7, 18, C_AUR); credits_l.custom_minimum_size.x = 62; cv.add_child(credits_l)
	var sep := Rule.new(); sep.vertical = true; sep.custom_minimum_size = Vector2(2, 0); rh.add_child(sep)
	rh.add_child(_glyph_box("pwr", 22, C_OK))
	power_box = res
	var pv := _stat(rh, "POWER"); power_l = lbl("0 / 0", f_disp7, 18); pv.add_child(power_l)
	power_bar = PowerMeter.new(); power_bar.custom_minimum_size = Vector2(92, 6); power_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE; pv.add_child(power_bar)
	sw_box = Plate.new(); sw_box.mouse_filter = Control.MOUSE_FILTER_IGNORE; sw_box.accent = C_ACC
	sw_box.add_theme_stylebox_override("panel", plate_sb(8.0, Color(0.13, 0.05, 0.04, 0.9), Color("6a2a22"))); top.add_child(sw_box)
	var sh := HBoxContainer.new(); sh.add_theme_constant_override("separation", 8); sh.mouse_filter = Control.MOUSE_FILTER_IGNORE; sw_box.add_child(sh)
	sh.add_child(_glyph_box("launch", 22, Color("ff9a8c")))
	var sv := _stat(sh, "SKYFALL"); sw_name = sv.get_child(0); sw_time = lbl("0:00", f_disp7, 18, Color("ffd0cc")); sv.add_child(sw_time); sw_box.visible = false
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sp.mouse_filter = Control.MOUSE_FILTER_IGNORE; top.add_child(sp)
	# hides the side panel (build menu + minimap) for a wider view; stays in the top bar either way
	for cat in ["bld", "inf", "veh", "air"]:
		var pc := ProdChip.new(); pc.ui = self; pc.cat = cat; pc.custom_minimum_size = Vector2(58, 48); pc.visible = false
		top.add_child(pc); prod_chips[cat] = pc
	var mp := mkbtn("Map", func(): main.toggle_big_map(), 56, 48, 12, "map"); top.add_child(mp); btn["map"] = mp
	var pb := mkbtn("", func(): main.toggle_panel(), 48, 48, 13, "hide"); top.add_child(pb); btn["panel"] = pb
	var mb := mkbtn("", func(): main.open_menu(), 48, 48, 16, "pause"); top.add_child(mb); btn["pause"] = mb
	big_map = MiniMap.new(); big_map.ui = self; big_map.src = true
	big_map.anchor_left = 1; big_map.anchor_right = 1; big_map.offset_left = -8 - 280; big_map.offset_right = -8; big_map.offset_top = 64; big_map.offset_bottom = 64 + 280
	big_map.visible = false; hud.add_child(big_map)
	# the objective shows for a few seconds, then folds into this button (tap the box to fold it sooner)
	obj_btn = mkbtn("Objective", func(): main.show_objective(), 0, 40, 11, "obj"); obj_btn.position = Vector2(8, 70); obj_btn.visible = false
	hud.add_child(obj_btn)
	obj_box = Plate.new(); obj_box.position = Vector2(8, 70); obj_box.custom_minimum_size = Vector2(310, 0); obj_box.mouse_filter = Control.MOUSE_FILTER_STOP
	obj_box.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: main.hide_objective())
	obj_box.add_theme_stylebox_override("panel", plate_sb(10.0, H_BG, W_LINE, W_BRASS))
	var ov := VBoxContainer.new(); ov.add_theme_constant_override("separation", 4); ov.mouse_filter = Control.MOUSE_FILTER_IGNORE; obj_box.add_child(ov)
	var oh := HBoxContainer.new(); oh.add_theme_constant_override("separation", 6); oh.mouse_filter = Control.MOUSE_FILTER_IGNORE; ov.add_child(oh)
	oh.add_child(_glyph_box("obj", 14, W_BRASS)); oh.add_child(lbl("OBJECTIVE", f_wide, 11, W_BRASS))
	var orule := Rule.new(); orule.custom_minimum_size = Vector2(0, 2); ov.add_child(orule)
	obj_l = RichTextLabel.new(); obj_l.fit_content = true; obj_l.custom_minimum_size = Vector2(286, 0); obj_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	obj_l.add_theme_font_override("normal_font", f_body); obj_l.add_theme_font_size_override("normal_font_size", 13)
	obj_l.add_theme_color_override("default_color", Color("e2dac2")); ov.add_child(obj_l)
	obj_box.visible = false; hud.add_child(obj_box)
	toast_box = Plate.new(); toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := HBoxContainer.new(); th.add_theme_constant_override("separation", 8); th.mouse_filter = Control.MOUSE_FILTER_IGNORE; toast_box.add_child(th)
	toast_g = _glyph_box("info", 14, C_ACC); th.add_child(toast_g)
	toast_l = lbl("", f_disp, 13); th.add_child(toast_l); toast_box.visible = false
	toast_box.anchor_left = 0.5; toast_box.anchor_right = 0.5; toast_box.offset_top = 70; toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud.add_child(toast_box)
	# army groups on the left edge: tap selects the group, tap again centres the camera, hold stores the selection
	groups_box = VBoxContainer.new(); groups_box.add_theme_constant_override("separation", 5); groups_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	groups_box.anchor_top = 0.5; groups_box.anchor_bottom = 0.5; groups_box.offset_left = 8; groups_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	groups_box.offset_top = -78; groups_box.offset_bottom = 105  # clear of the objective box and the command rows on a phone
	hud.add_child(groups_box)
	for i in 4:
		var g := GroupChip.new(); g.ui = self; g.idx = i; g.focus_mode = Control.FOCUS_NONE; g.custom_minimum_size = Vector2(56, 42)
		for st in ["normal", "hover", "pressed", "disabled"]: g.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		g.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		g.button_down.connect(func(): g.set_meta("t0", Time.get_ticks_msec()))
		g.button_up.connect(func(): main.group_btn(i, Time.get_ticks_msec() - int(g.get_meta("t0", 0)) > 500))
		groups_box.add_child(g); btn["grp%d" % i] = g
	# two rows in the bottom-left corner, close to the thumb: unit groups at the bottom, orders above
	cmd_row = VBoxContainer.new(); cmd_row.add_theme_constant_override("separation", 6); cmd_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cmd_row.anchor_top = 1; cmd_row.anchor_bottom = 1; cmd_row.offset_left = 8; cmd_row.offset_bottom = -8
	cmd_row.grow_vertical = Control.GROW_DIRECTION_BEGIN; cmd_row.alignment = BoxContainer.ALIGNMENT_END
	hud.add_child(cmd_row)
	cmd_top = HBoxContainer.new(); cmd_top.add_theme_constant_override("separation", 6); cmd_top.mouse_filter = Control.MOUSE_FILTER_IGNORE; cmd_row.add_child(cmd_top)
	cmd_bot = HBoxContainer.new(); cmd_bot.add_theme_constant_override("separation", 6); cmd_bot.mouse_filter = Control.MOUSE_FILTER_IGNORE; cmd_row.add_child(cmd_bot)
	var fb := mkbtn("Formation", func(): main.toggle_formation(), 150.0, 48.0, 12, "form"); cmd_bot.add_child(fb); btn["form"] = fb
	var gap := Rule.new(); gap.vertical = true; gap.custom_minimum_size = Vector2(6, 0); cmd_bot.add_child(gap)
	for k in ["all", "inf", "veh", "air", "idle"]:
		var b := mkbtn(k, func(): main.squad_btn(k), 76.0, 48.0, 12, k)
		cmd_bot.add_child(b); btn[k] = b
	for pair in [["sw", "Launch", "launch"], ["amove", "Attack", "atk"], ["stop", "Stop", "stop"], ["upgrade", "Upgrade", "up"], ["repair", "Repair", "repair"], ["sell", "Sell", "sell"], ["desel", "", "x"]]:
		var k: String = pair[0]
		var b := mkbtn(pair[1], func(): main.cmd_btn(k), 0, 44, 12, pair[2]); cmd_top.add_child(b); btn[k] = b; b.visible = false
	set_on(btn.sw, true)
	selinfo = lbl("", f_body6, 12, W_SAND); selinfo.size_flags_vertical = Control.SIZE_SHRINK_CENTER; cmd_top.add_child(selinfo)
	selinfo.add_theme_constant_override("outline_size", 4); selinfo.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	mode_btn = ModeDial.new(); mode_btn.ui = self; mode_btn.focus_mode = Control.FOCUS_NONE; mode_btn.custom_minimum_size = Vector2(88, 88)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]: mode_btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	mode_btn.anchor_left = 1; mode_btn.anchor_right = 1; mode_btn.anchor_top = 1; mode_btn.anchor_bottom = 1
	mode_btn.offset_left = -98; mode_btn.offset_right = -10; mode_btn.offset_top = -98; mode_btn.offset_bottom = -10
	mode_btn.pressed.connect(func(): main.toggle_mode())
	hud.add_child(mode_btn)
	place_bar = HBoxContainer.new(); place_bar.add_theme_constant_override("separation", 8)
	place_bar.anchor_left = 0.5; place_bar.anchor_right = 0.5; place_bar.anchor_top = 1; place_bar.anchor_bottom = 1
	place_bar.offset_top = -56; place_bar.offset_bottom = -8; place_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var hb := Plate.new(); hb.add_theme_stylebox_override("panel", plate_sb(10.0)); place_hint = lbl("Drag to position · tap it to build", f_body6, 13, W_KHAKI)
	place_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER; hb.add_child(place_hint); place_bar.add_child(hb)
	var bp := mkbtn("Build here", func(): main.confirm_place(), 0, 48, 13, "build"); set_on(bp, true); place_bar.add_child(bp)
	place_bar.add_child(mkbtn("Cancel", func(): main.end_placing(), 0, 48, 13, "x"))
	place_bar.visible = false; hud.add_child(place_bar)
	update_mode(false)

## A titled stat inside a plate: small sand caption, then whatever the caller adds.
func _stat(par: Control, title: String) -> VBoxContainer:
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", -1); v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(lbl(title, f_wide, 9, W_SAND))
	par.add_child(v)
	return v

func _glyph_box(g: String, sz: float, col: Color) -> Glyph:
	var gl := Glyph.new(); gl.kind = g; gl.col = col; gl.custom_minimum_size = Vector2(sz, sz)
	gl.size_flags_vertical = Control.SIZE_SHRINK_CENTER; gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gl

## Chamfered olive plate for HUD readouts; `bar` draws a coloured strip down the left edge.
func plate_sb(pad := 8.0, bg := H_BG, border := W_LINE, bar := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := cut(bg, border, 1, 8, pad)
	s.content_margin_left = pad + 4; s.content_margin_right = pad + 4
	s.shadow_color = Color(0, 0, 0, 0.35); s.shadow_size = 4; s.shadow_offset = Vector2(0, 2); s.anti_aliasing = true
	if bar.a > 0:
		s.border_width_left = 3; s.border_color = border
		s.set_meta("bar", bar)
		s.content_margin_left = pad + 6
	return s

func _left_bar(c: Color) -> StyleBoxFlat:
	var s := sb(Color(0.047, 0.063, 0.075, 0.86), C_LINE)
	s.border_width_left = 3; s.border_color = C_LINE
	var s2 := s.duplicate(); s2.border_color = c; s2.border_width_top = 0; s2.border_width_right = 0; s2.border_width_bottom = 0
	return s2

func update_mode(box: bool) -> void:
	mode_btn.tooltip_text = "drag to box units" if box else "tap for Select"
	mode_btn.box = box; mode_btn.queue_redraw()

var toast_g: Glyph
func toast(msg: String, kind := "") -> void:
	toast_l.text = msg.to_upper()
	var c := C_ACC
	if kind == "warn": c = C_BAD
	elif kind == "gold": c = C_AUR
	toast_box.add_theme_stylebox_override("panel", plate_sb(8.0, H_BG, W_LINE, c))
	toast_g.kind = "warn" if kind == "warn" else ("aur" if kind == "gold" else "info"); toast_g.col = c; toast_g.queue_redraw()
	toast_box.accent = c
	toast_l.add_theme_color_override("font_color", Color("ffd2cf") if kind == "warn" else W_KHAKI)
	toast_box.visible = true; toast_t = 2.4
	toast_box.reset_size()
	toast_box.offset_left = -toast_box.size.x / 2; toast_box.offset_right = toast_box.size.x / 2

# ---------------- side panel ----------------
func _build_panel() -> void:
	panel = PanelContainer.new(); panel.add_theme_stylebox_override("panel", sb(C_PANEL, C_LINE, 0, 0, 8))
	panel.anchor_left = 1; panel.anchor_right = 1; panel.anchor_bottom = 1; panel.offset_left = -PANEL_W
	panel.draw.connect(_draw_panel_bg)
	add_child(panel)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 8); panel.add_child(v)
	mini = MiniMap.new(); mini.ui = self; mini.custom_minimum_size = Vector2(PANEL_W - 16, PANEL_W - 16); v.add_child(mini)
	var tb := HBoxContainer.new(); tb.add_theme_constant_override("separation", 4); v.add_child(tb)
	for c in ["bld", "inf", "veh", "air"]:
		var b := HudBtn.new(); b.cap = {"bld": "BASE", "inf": "INF", "veh": "VEH", "air": "AIR"}[c]; b.glyph = c; b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", f_disp); b.add_theme_font_size_override("font_size", 10)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL; b.custom_minimum_size.y = 46
		b.pressed.connect(func(): main.select_tab(c))
		var dot := ColorRect.new(); dot.color = C_ACC; dot.size = Vector2(6, 6); dot.position = Vector2(5, 5); dot.visible = false; dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(dot); b.set_meta("dot", dot)
		restyle(b)
		tb.add_child(b); tabs[c] = b
	grid_scroll = ScrollContainer.new(); grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vsb := grid_scroll.get_v_scroll_bar(); vsb.custom_minimum_size.x = 4
	vsb.add_theme_stylebox_override("scroll", cut(Color(W_OLIVE2, 0.6), Color(0, 0, 0, 0), 0, 0, 0))
	for g in ["grabber", "grabber_highlight", "grabber_pressed"]: vsb.add_theme_stylebox_override(g, cut(Color(W_BRASS, 0.75), Color(0, 0, 0, 0), 0, 0, 0))
	v.add_child(grid_scroll)
	grid = GridContainer.new(); grid.columns = 2; grid.add_theme_constant_override("h_separation", 6); grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_scroll.add_child(grid)
	for cat in D.CAT_ORDER:
		for type in D.CATS[cat]:
			var it := BuildItem.new(); it.ui = self; it.cat = cat; it.type = type
			it.custom_minimum_size = Vector2((PANEL_W - 16 - 6) / 2.0, 82)
			grid.add_child(it); items[cat + ":" + type] = it

## Side panel backdrop: dark olive steel with a faint map grid and a brass seam along its inner edge.
func _draw_panel_bg() -> void:
	var s := panel.size
	panel.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]),
		PackedColorArray([Color("171b13"), Color("171b13"), Color("0c0e0a"), Color("0c0e0a")]))
	var g := 23.0; var y := 0.0
	while y < s.y:
		panel.draw_line(Vector2(0, y), Vector2(s.x, y), Color(0.85, 0.8, 0.64, 0.03), 1.0); y += g
	var x := 0.0
	while x < s.x:
		panel.draw_line(Vector2(x, 0), Vector2(x, s.y), Color(0.85, 0.8, 0.64, 0.03), 1.0); x += g
	panel.draw_rect(Rect2(0, 0, 2, s.y), Color(W_BRASS, 0.55))
	panel.draw_rect(Rect2(2, 0, 1, s.y), Color(0, 0, 0, 0.6))
	for yy in [10.0, s.y - 10.0]:
		panel.draw_circle(Vector2(9, yy), 2.0, Color(W_BRASS, 0.5))

func set_tab(cat: String) -> void:
	for c in tabs:
		set_on(tabs[c], c == cat)

# ---------------- overlays (war-room look) ----------------
const W_KHAKI := Color("d8cba3")
const W_SAND := Color("a99c78")
const W_OLIVE := Color(0.075, 0.086, 0.059, 0.9)
const W_OLIVE2 := Color("21271a")
const W_LINE := Color("4a5238")
const W_BRASS := Color("d9a441")
const W_SEL := Color("33140f")
const W_GREEN := Color("8fcf7a")

var f_title: FontVariation
var f_wide: FontVariation

## Chamfered box: two cut corners, like stencilled military plates.
static func cut(bg: Color, border := Color(0, 0, 0, 0), bw := 1, c := 9, pad := 8.0) -> StyleBoxFlat:
	var s := sb(bg, border, bw, 0, pad)
	s.corner_radius_top_left = c; s.corner_radius_bottom_right = c; s.corner_detail = 1
	return s

func _wide_fonts() -> void:
	f_title = FontVariation.new(); f_title.base_font = f_disp7; f_title.spacing_glyph = 4
	f_wide = FontVariation.new(); f_wide.base_font = f_disp; f_wide.spacing_glyph = 2

## full: animated battlefield backdrop; otherwise a dim veil over the paused game.
## fit: the card fills the screen height instead of scrolling as a whole (its own lists scroll).
func _overlay(nm: String, maxw: float, full := true, fit := false) -> VBoxContainer:
	var o := Control.new(); o.name = nm; o.set_anchors_preset(Control.PRESET_FULL_RECT); o.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := WarBG.new(); bg.full = full; bg.set_anchors_preset(Control.PRESET_FULL_RECT); bg.mouse_filter = Control.MOUSE_FILTER_IGNORE; o.add_child(bg)
	var mc := MarginContainer.new(); for s in ["left", "right", "top", "bottom"]: mc.add_theme_constant_override("margin_" + s, 16)
	var card := VBoxContainer.new(); card.add_theme_constant_override("separation", 12)
	if fit:
		mc.set_anchors_preset(Control.PRESET_FULL_RECT); o.add_child(mc)
		o.resized.connect(func(): _fit_margins(o))
	else:
		var sc := ScrollContainer.new(); sc.set_anchors_preset(Control.PRESET_FULL_RECT); sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; o.add_child(sc)
		var cc := CenterContainer.new(); cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL; cc.size_flags_vertical = Control.SIZE_EXPAND_FILL; sc.add_child(cc)
		cc.add_child(mc)
		card.custom_minimum_size.x = maxw
		o.resized.connect(func(): card.custom_minimum_size.x = minf(maxw, o.size.x - 32 - ins_l - ins_r))
	mc.add_child(card)
	o.set_meta("card", card); o.set_meta("mc", mc); o.set_meta("fit", fit); o.set_meta("maxw", maxw)
	add_child(o); overlays[nm] = o; o.visible = false
	return card

var ins_l := 0.0
var ins_t := 0.0
var ins_r := 0.0
var ins_b := 0.0

## Safe-area insets in UI units: HUD, side panel content and menu cards move in; backgrounds still bleed.
func set_insets(l: float, t: float, r: float, b: float) -> void:
	ins_l = l; ins_t = t; ins_r = r; ins_b = b
	_place_hud()
	panel.offset_left = -PANEL_W - r
	var ps := sb(C_PANEL, C_LINE, 0, 0, 8)
	ps.content_margin_right = 8 + r; ps.content_margin_top = 8 + t; ps.content_margin_bottom = 8 + b
	panel.add_theme_stylebox_override("panel", ps)
	for k in overlays:
		var o: Control = overlays[k]; var mc: MarginContainer = o.get_meta("mc")
		mc.add_theme_constant_override("margin_top", int(16 + t)); mc.add_theme_constant_override("margin_bottom", int(16 + b))
		if o.get_meta("fit"): _fit_margins(o)
		else:
			mc.add_theme_constant_override("margin_left", int(16 + l)); mc.add_theme_constant_override("margin_right", int(16 + r))
			var card: Control = o.get_meta("card"); card.custom_minimum_size.x = minf(o.get_meta("maxw"), o.size.x - 32 - l - r)

var panel_open := true

## Width the side panel takes on screen (0 when hidden), safe-area margin included.
func panel_px() -> float:
	return (PANEL_W if panel_open else 0.0) + ins_r

## Show or hide the side panel; the HUD and the 3D view's centre follow.
func set_panel(open: bool) -> void:
	panel_open = open; panel.visible = open
	btn.panel.text = "" if open else "BUILD"
	btn.panel.glyph = "hide" if open else "build"
	btn.panel.custom_minimum_size.x = 48 if open else 104
	restyle(btn.panel)
	_place_hud()

func _place_hud() -> void:
	var pw := (PANEL_W if panel_open else 0.0)
	hud.offset_left = ins_l; hud.offset_top = ins_t; hud.offset_right = -pw - ins_r; hud.offset_bottom = -ins_b
	var dr: Control = hud.get_meta("draw")
	dr.offset_left = -ins_l; dr.offset_top = -ins_t; dr.offset_right = pw + ins_r; dr.offset_bottom = ins_b

func _fit_margins(o: Control) -> void:
	var mc: MarginContainer = o.get_meta("mc")
	var side := maxf(0.0, (o.size.x - 32 - ins_l - ins_r - float(o.get_meta("maxw"))) / 2)
	mc.add_theme_constant_override("margin_left", int(16 + ins_l + side)); mc.add_theme_constant_override("margin_right", int(16 + ins_r + side))

## Olive panel with brass corner brackets.
func frame(par: Control, sep := 10, accent := W_BRASS) -> VBoxContainer:
	var p := Frame.new(); p.accent = accent
	p.add_theme_stylebox_override("panel", cut(W_OLIVE, W_LINE, 1, 14, 16.0))
	par.add_child(p)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", sep); p.add_child(v)
	return v

func eyebrow(t: String, col := W_BRASS) -> Label:
	return lbl(t.to_upper(), f_wide, 11, col)

func title(t: String, size := 64) -> Label:
	return lbl(t.to_upper(), f_title, size, W_KHAKI)

func cta(t: String, cb: Callable) -> Button:
	var b := mkbtn(t, cb, 0, 52, 17)
	b.add_theme_stylebox_override("normal", cut(C_ACC, Color("ff8a7a"), 0))
	b.add_theme_stylebox_override("hover", cut(C_ACC.lightened(0.08), C_ACC, 0))
	b.add_theme_stylebox_override("pressed", cut(C_ACC.darkened(0.15), C_ACC, 0))
	b.add_theme_color_override("font_color", Color.WHITE); b.add_theme_font_override("font", f_title)
	var hz := Hazard.new(); hz.set_anchors_preset(Control.PRESET_FULL_RECT); hz.mouse_filter = Control.MOUSE_FILTER_IGNORE; b.add_child(hz)
	return b

func ghost(t: String, cb: Callable, h := 44.0) -> Button:
	var b := mkbtn(t, cb, 0, h, 13)
	b.add_theme_font_override("font", f_wide)
	b.add_theme_stylebox_override("normal", cut(W_OLIVE2, W_LINE))
	b.add_theme_stylebox_override("hover", cut(W_OLIVE2.lightened(0.06), W_SAND))
	b.add_theme_stylebox_override("pressed", cut(W_OLIVE2.darkened(0.2), W_SAND))
	b.add_theme_color_override("font_color", W_KHAKI); b.add_theme_color_override("font_hover_color", W_KHAKI); b.add_theme_color_override("font_pressed_color", W_KHAKI)
	return b

func seg(par: Control, group: String, opts: Array, cur: String, cb: Callable) -> HBoxContainer:
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 6); par.add_child(h)
	seg_btns[group] = {}
	for o in opts:
		var b := Button.new(); b.focus_mode = Control.FOCUS_NONE; b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(80, 42)
		var v := VBoxContainer.new(); v.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.set_anchors_preset(Control.PRESET_FULL_RECT); v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.offset_left = 6; v.offset_right = -6; v.add_theme_constant_override("separation", 1)
		var l := lbl(o[1].to_upper(), f_wide, 13, W_KHAKI); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(l)
		if o.size() > 2:
			var s := lbl(o[2], f_body, 11, W_SAND); s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(s)
			b.custom_minimum_size.y = 74
		b.add_child(v)
		b.pressed.connect(func(): _seg_pick(group, o[0]); cb.call(o[0]))
		h.add_child(b); seg_btns[group][o[0]] = b
	_seg_pick(group, cur)
	return h

func _seg_pick(group: String, val: String) -> void:
	for k in seg_btns[group]:
		var on: bool = k == val
		var b: Button = seg_btns[group][k]
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, cut(W_SEL if on else W_OLIVE2, C_ACC if on else (W_SAND if st == "hover" else W_LINE), 2 if on else 1, 7))

func _build_overlays() -> void:
	_wide_fonts()
	# ---- start: title on the left, orders dossier on the right
	var c := _overlay("start", 1010, true, true)
	var bar := HBoxContainer.new(); c.add_child(bar)
	bar.add_child(eyebrow("Field command  //  Sable valley theatre", W_SAND))
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; bar.add_child(sp)
	# build number and self-update status (scripts/updater.gd); tap to check, restart or get the new app
	var up := Button.new(); up.flat = true; up.focus_mode = Control.FOCUS_NONE; up.add_theme_font_override("font", f_wide); up.add_theme_font_size_override("font_size", 11)
	up.custom_minimum_size.y = 28; up.pressed.connect(func(): Updater.act()); bar.add_child(up)
	var upd := func():
		up.text = Updater.label().to_upper()
		var col: Color = {"ready": C_AUR, "apk": C_AUR, "downloading": W_SAND, "checking": W_SAND, "offline": C_DIM, "off": C_DIM}.get(Updater.status, W_GREEN)
		for k in ["font_color", "font_hover_color", "font_pressed_color"]: up.add_theme_color_override(k, col)
	Updater.changed.connect(upd); upd.call()
	var cols := HBoxContainer.new(); cols.add_theme_constant_override("separation", 28); cols.size_flags_vertical = Control.SIZE_EXPAND_FILL; c.add_child(cols)
	var lc := VBoxContainer.new(); lc.size_flags_horizontal = Control.SIZE_EXPAND_FILL; lc.size_flags_stretch_ratio = 0.9; lc.add_theme_constant_override("separation", 10); cols.add_child(lc)
	var ih := HBoxContainer.new(); ih.add_theme_constant_override("separation", 12); lc.add_child(ih)
	var ins := Insignia.new(); ins.custom_minimum_size = Vector2(54, 54); ih.add_child(ins)
	var iv := VBoxContainer.new(); iv.alignment = BoxContainer.ALIGNMENT_CENTER; iv.add_theme_constant_override("separation", 0); ih.add_child(iv)
	iv.add_child(eyebrow("Vanguard  ·  Ashen Pact  ·  Hollow Choir")); iv.add_child(lbl("THE WAR FOR AURITE", f_wide, 11, W_SAND))
	var tl := VBoxContainer.new(); tl.add_theme_constant_override("separation", -16)
	tl.add_child(title("Aurite", 70)); tl.add_child(lbl("FRONT", f_title, 70, C_ACC)); lc.add_child(tl)
	var rule := Hazard.new(); rule.stripe = true; rule.custom_minimum_size = Vector2(0, 8); lc.add_child(rule)
	var lede := lbl("Two armies fight over the aurite fields of the Sable valley. Rise with the Ashen Pact in the first campaign, return with the Vanguard in the second, or pick a side in a skirmish, including the Hollow Choir, who sing to the aurite under the valley.", f_body, 14, Color("cfc6ad"))
	lede.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; lc.add_child(lede)
	var lsp := Control.new(); lsp.size_flags_vertical = Control.SIZE_EXPAND_FILL; lc.add_child(lsp)
	var fm := ghost("Field manual", func(): show_overlay("manual"), 40); fm.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; fm.custom_minimum_size.x = 170; lc.add_child(fm)
	# right: the orders dossier, two big doors: the campaign screen and the skirmish screen
	var rc := VBoxContainer.new(); rc.size_flags_horizontal = Control.SIZE_EXPAND_FILL; cols.add_child(rc)
	var d := frame(rc, 12)
	d.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	d.add_child(eyebrow("Orders", W_SAND))
	btn.camp_tile = _tile(d, "Campaign", true, func(): main.show_campaigns())
	btn.sk_tile = _tile(d, "Skirmish", false, func(): show_overlay("skirmish"))
	btn.sk_tile.get_meta("l1").text = "Vanguard, Ashen Pact or Hollow Choir against the AI"
	btn.sk_tile.get_meta("l2").text = "Pick both armies and the enemy's strength"
	# ---- campaigns: chapters stacked in one list that scrolls on its own
	c = _overlay("campaign", 1010, true, true)
	var ch := HBoxContainer.new(); ch.add_theme_constant_override("separation", 16); c.add_child(ch)
	var cb := ghost("Back", func(): main.show_start(), 44); cb.custom_minimum_size.x = 130; ch.add_child(cb)
	var chv := VBoxContainer.new(); chv.add_theme_constant_override("separation", -4); chv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; ch.add_child(chv)
	chv.add_child(eyebrow("Field command  //  campaigns", W_SAND)); chv.add_child(title("The war for aurite", 28))
	camp_scroll = ScrollContainer.new(); camp_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	camp_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; camp_scroll.custom_minimum_size.y = 100
	var vsb := camp_scroll.get_v_scroll_bar(); vsb.custom_minimum_size.x = 6
	vsb.add_theme_stylebox_override("scroll", cut(Color(W_OLIVE2, 0.6), Color(0, 0, 0, 0), 0, 0, 0))
	for g in ["grabber", "grabber_highlight", "grabber_pressed"]: vsb.add_theme_stylebox_override(g, cut(W_BRASS if g != "grabber" else Color(W_BRASS, 0.7), Color(0, 0, 0, 0), 0, 0, 0))
	c.add_child(camp_scroll)
	camp_pane = VBoxContainer.new(); camp_pane.add_theme_constant_override("separation", 10); camp_pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL; camp_scroll.add_child(camp_pane)
	# ---- skirmish setup
	c = _overlay("skirmish", 860)
	var sh := HBoxContainer.new(); sh.add_theme_constant_override("separation", 16); c.add_child(sh)
	var sb2 := ghost("Back", func(): main.show_start(), 44); sb2.custom_minimum_size.x = 130; sh.add_child(sb2)
	var shv := VBoxContainer.new(); shv.add_theme_constant_override("separation", -4); sh.add_child(shv)
	shv.add_child(eyebrow("Field command  //  skirmish", W_SAND)); shv.add_child(title("Skirmish", 28))
	sk_pane = frame(c, 8)
	sk_pane.add_child(eyebrow("Choose your army", W_SAND))
	seg(sk_pane, "fac", [["vanguard", "Vanguard", "Heavy armor, Rangers, Skyhawk gunships, Bastion cannons, Skyfall missiles"], ["ashen", "Ashen Pact", "Fast raiders, Pyros, Wasp drones, Arc weapons, the Rift Engine"],
		["choir", "Hollow Choir", "Cheap swarms, tunnels, crystal gardens, burrowing sappers, the Cantor"]], "vanguard", func(f): main.sk_fac = f)
	sk_pane.add_child(eyebrow("Enemy army", W_SAND))
	seg(sk_pane, "enemy", [["random", "Random"], ["vanguard", "Vanguard"], ["ashen", "Ashen"], ["choir", "Choir"]], "random", func(f): main.sk_enemy = f)
	sk_pane.add_child(eyebrow("Enemy strength", W_SAND))
	seg(sk_pane, "diff", [["easy", "Easy"], ["normal", "Normal"], ["hard", "Hard"]], "normal", func(dd): main.diff = dd)
	sk_pane.add_child(cta("Deploy", func(): main.play({"fac": main.sk_fac, "enemy": main.sk_enemy, "diff": main.diff})))
	# ---- field manual (controls)
	c = _overlay("manual", 640)
	d = frame(c, 10)
	d.add_child(eyebrow("Field manual  //  standing orders"))
	d.add_child(title("Controls", 40))
	for row in [["TOUCH", "Drag to move the map, pinch to zoom · tap a unit to select it, then tap the ground to move there or an enemy to attack it · tap another of your units to switch to it · hold, then drag to box-select (with units selected, start the hold on one of your units; held on open ground it faces a formation instead) · double-tap a unit to grab every unit of that type on screen · hold and let go, or ✕, to deselect."], ["MOUSE", "Click to select or command, drag to box-select, double-click a unit for all of its type, right-drag to face a formation, middle-drag or WASD to scroll, wheel to zoom."], ["PANEL", "» in the top bar hides the build menu and minimap for a wider view; « BUILD brings them back. While it is hidden, the top bar shows what is in production (tap a ready building to place it). MAP opens a large minimap: tap or drag on it to look there."], ["BUILD", "Tap to order, hold a unit to order five, tap the corner ✕ to cancel one (or long-press a building). Drag a ready building out of the menu and let go where it should stand; it is drawn above your finger."], ["GROUPS", "Select units, then hold 1 to 4 on the left edge to store them. Tap a group to select it, tap again to jump to it. The objective folds away after a few seconds; tap OBJECTIVE to see it again."]]:
		var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 12); d.add_child(h)
		var k := lbl(row[0], f_wide, 11, W_BRASS); k.custom_minimum_size.x = 60; h.add_child(k)
		var t := lbl(row[1], f_body, 13, Color("d6cfba")); t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; t.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(t)
	d.add_child(ghost("Back", func(): show_overlay("start")))
	# ---- pause
	c = _overlay("menu", 400, false)
	d = frame(c, 10)
	var ph := HBoxContainer.new(); d.add_child(ph)
	var pv := VBoxContainer.new(); pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; pv.add_theme_constant_override("separation", -2); ph.add_child(pv)
	pv.add_child(eyebrow("Operation paused")); pv.add_child(title("Stand by", 38))
	var st := Stamp.new(); st.text = "HOLD"; st.col = C_ACC; st.custom_minimum_size = Vector2(96, 52); ph.add_child(st)
	d.add_child(cta("Resume", func(): main.resume()))
	var r1 := HBoxContainer.new(); r1.add_theme_constant_override("separation", 8); d.add_child(r1)
	btn.sound = ghost("Sound: on", func(): main.toggle_sound()); btn.sound.size_flags_horizontal = Control.SIZE_EXPAND_FILL; r1.add_child(btn.sound)
	btn.music = ghost("Music: on", func(): main.toggle_music()); btn.music.size_flags_horizontal = Control.SIZE_EXPAND_FILL; r1.add_child(btn.music)
	var r2 := HBoxContainer.new(); r2.add_theme_constant_override("separation", 8); d.add_child(r2)
	var rs := ghost("Restart", func(): main.restart()); rs.size_flags_horizontal = Control.SIZE_EXPAND_FILL; r2.add_child(rs)
	var mm := ghost("Main menu", func(): main.quit_to_menu()); mm.size_flags_horizontal = Control.SIZE_EXPAND_FILL; r2.add_child(mm)
	# ---- end
	c = _overlay("end", 700)
	d = frame(c, 12)
	var eh := HBoxContainer.new(); d.add_child(eh)
	var ev := VBoxContainer.new(); ev.size_flags_horizontal = Control.SIZE_EXPAND_FILL; ev.add_theme_constant_override("separation", -4); eh.add_child(ev)
	btn.end_eye = eyebrow("Operation complete"); ev.add_child(btn.end_eye)
	btn.end_title = title("Victory", 60); ev.add_child(btn.end_title)
	btn.end_stamp = Stamp.new(); btn.end_stamp.custom_minimum_size = Vector2(170, 70); eh.add_child(btn.end_stamp)
	btn.end_why = lbl("", f_body, 14, Color("ffb0a8")); btn.end_why.visible = false; d.add_child(btn.end_why)
	btn.end_stats = GridContainer.new(); btn.end_stats.columns = 5; btn.end_stats.add_theme_constant_override("h_separation", 8); btn.end_stats.add_theme_constant_override("v_separation", 8); d.add_child(btn.end_stats)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8); d.add_child(row)
	btn.next = cta("Next mission", func(): main.next_mission()); btn.next.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(btn.next)
	btn.again = cta("Play again", func(): main.play(main.last_opt)); btn.again.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(btn.again)
	var em := ghost("Main menu", func(): main.show_start(), 52); em.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(em)
	# ---- briefing dossier
	c = _overlay("brief", 640)
	d = frame(c, 10)
	var bh := HBoxContainer.new(); d.add_child(bh)
	var bv := VBoxContainer.new(); bv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; bv.add_theme_constant_override("separation", -4); bh.add_child(bv)
	btn.br_eye = eyebrow("Mission 1"); bv.add_child(btn.br_eye)
	btn.br_title = title("Landfall", 48); bv.add_child(btn.br_title)
	var cl := Stamp.new(); cl.text = "CLASSIFIED"; cl.col = C_ACC; cl.custom_minimum_size = Vector2(170, 60); bh.add_child(cl)
	btn.br_theatre = lbl("", f_wide, 11, W_SAND); btn.br_theatre.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; d.add_child(btn.br_theatre)
	btn.br_text = lbl("", f_body, 14, Color("d6cfba")); btn.br_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; d.add_child(btn.br_text)
	btn.br_heroes = HBoxContainer.new(); btn.br_heroes.add_theme_constant_override("separation", 8); d.add_child(btn.br_heroes)
	var ob := PanelContainer.new(); ob.add_theme_stylebox_override("panel", _left_bar(W_BRASS)); d.add_child(ob)
	var obv := VBoxContainer.new(); ob.add_child(obv); obv.add_child(eyebrow("Objectives"))
	btn.br_obj = lbl("", f_body, 14, W_KHAKI); btn.br_obj.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; obv.add_child(btn.br_obj)
	var lv := HBoxContainer.new(); lv.add_theme_constant_override("separation", 10); d.add_child(lv)
	var ll := eyebrow("Difficulty", W_SAND); ll.size_flags_vertical = Control.SIZE_SHRINK_CENTER; lv.add_child(ll)
	var lsg := seg(lv, "level", [["easy", "Easy"], ["normal", "Normal"], ["hard", "Hard"]], "normal", func(l): main.set_camp_level(l))
	lsg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row = HBoxContainer.new(); row.add_theme_constant_override("separation", 8); d.add_child(row)
	var go := cta("Begin mission", func(): main.begin_mission()); go.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(go)
	var bk := ghost("Back", func(): main.show_campaigns(), 52); bk.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(bk)

## Boot splash art (AF_MODE=splash renders it to res://splash.png).
func build_splash() -> void:
	var c := _overlay("splash", 720)
	var bg: WarBG = overlays.splash.get_child(0); bg.hero = true; bg.t = 3.0
	c.alignment = BoxContainer.ALIGNMENT_CENTER; c.add_theme_constant_override("separation", 8)
	var ins := Insignia.new(); ins.custom_minimum_size = Vector2(96, 96); ins.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; c.add_child(ins)
	var e := eyebrow("Vanguard  vs  Ashen Pact"); e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; e.add_theme_font_size_override("font_size", 14); c.add_child(e)
	var tl := VBoxContainer.new(); tl.add_theme_constant_override("separation", -26); c.add_child(tl)
	for w in [["AURITE", W_KHAKI], ["FRONT", C_ACC]]:
		var l := lbl(w[0], f_title, 110, w[1]); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; tl.add_child(l)
	var hz := Hazard.new(); hz.stripe = true; hz.custom_minimum_size = Vector2(440, 10); hz.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; c.add_child(hz)
	var sub := lbl("THE WAR FOR AURITE", f_wide, 14, W_SAND); sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; c.add_child(sub)

func show_overlay(nm: String) -> void:
	for k in overlays: overlays[k].visible = k == nm

func set_end_result(win: bool) -> void:
	btn.end_title.add_theme_color_override("font_color", W_KHAKI if win else C_ACC)
	btn.end_stamp.text = "SECURED" if win else "OVERRUN"
	btn.end_stamp.col = W_GREEN if win else C_ACC
	btn.end_stamp.queue_redraw()

const HERO_LINES := {
	"vey": "Pact commando. Arc carbine that jumps between targets.",
	"furnace": "Old Brann's arc tank, forged from a smelter.",
	"harrow": "Vanguard marksman. Rail rifle, long reach.",
	"saint": "Marshal Dace's command tank. Heavy twin cannon.",
}

func set_brief_heroes(list: Array, fac: String) -> void:
	for ch in btn.br_heroes.get_children(): ch.queue_free()
	btn.br_heroes.visible = list.size() > 0
	for h in list:
		var p := PanelContainer.new(); p.add_theme_stylebox_override("panel", cut(W_OLIVE2, W_BRASS, 1, 7, 7.0)); p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 0); p.add_child(v)
		var own: bool = D.UN[h].fac == fac
		v.add_child(lbl(("HERO  //  " if own else "ENEMY HERO  //  ") + D.UN[h].name.to_upper(), f_wide, 11, W_BRASS if own else C_ACC))
		var t := lbl(HERO_LINES.get(h, ""), f_body, 12, W_SAND); t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(t)
		btn.br_heroes.add_child(p)

## A big two-line door on the start screen (red for the main action).
func _tile(par: Control, t: String, main_action: bool, cb: Callable) -> Button:
	var b := Button.new(); b.focus_mode = Control.FOCUS_NONE; b.custom_minimum_size = Vector2(0, 104); b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bg := C_ACC.darkened(0.55) if main_action else W_OLIVE2
	var bd := C_ACC if main_action else W_LINE
	b.add_theme_stylebox_override("normal", cut(bg, bd, 2 if main_action else 1, 12))
	b.add_theme_stylebox_override("hover", cut(bg.lightened(0.06), bd if main_action else W_SAND, 2 if main_action else 1, 12))
	b.add_theme_stylebox_override("pressed", cut(bg.darkened(0.2), W_SAND, 2, 12))
	b.pressed.connect(cb)
	var h := HBoxContainer.new(); h.set_anchors_preset(Control.PRESET_FULL_RECT); h.offset_left = 20; h.offset_right = -16; h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new(); v.alignment = BoxContainer.ALIGNMENT_CENTER; v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; v.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.add_theme_constant_override("separation", 2); h.add_child(v)
	v.add_child(lbl(t.to_upper(), f_title, 30, Color.WHITE if main_action else W_KHAKI))
	var l1 := lbl("", f_wide, 12, W_BRASS if main_action else W_SAND); v.add_child(l1)
	var l2 := lbl("", f_body, 12, W_SAND); v.add_child(l2)
	var ar := lbl(">>", f_title, 26, Color.WHITE if main_action else W_SAND); ar.size_flags_vertical = Control.SIZE_SHRINK_CENTER; h.add_child(ar)
	b.add_child(h); b.set_meta("l1", l1); b.set_meta("l2", l2)
	par.add_child(b)
	return b

## Start screen campaign door: where the player left off.
func set_camp_tile(line1: String, line2: String) -> void:
	btn.camp_tile.get_meta("l1").text = line1.to_upper(); btn.camp_tile.get_meta("l2").text = line2

## Every campaign as a chapter: a header, then its missions two to a row. rows: [{C, open, done}].
func render_campaigns(rows: Array, focus_id: String) -> void:
	for ch in camp_pane.get_children(): ch.queue_free()
	var focus: Control = null
	for r in rows:
		var C: Dictionary = r.C; var op: bool = r.open; var done: int = r.done if op else -1
		var hp := PanelContainer.new(); hp.add_theme_stylebox_override("panel", _left_bar(C_ACC if op else W_LINE)); camp_pane.add_child(hp)
		var hh := HBoxContainer.new(); hh.add_theme_constant_override("separation", 16); hp.add_child(hh)
		var num := lbl(C.num, f_title, 36, C_ACC if op else W_SAND); num.custom_minimum_size.x = 44; num.size_flags_vertical = Control.SIZE_SHRINK_CENTER; hh.add_child(num)
		var hv := VBoxContainer.new(); hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hv.add_theme_constant_override("separation", 0); hh.add_child(hv)
		hv.add_child(lbl(C.name.to_upper(), f_wide, 18, W_KHAKI))
		var prev: Dictionary = D.CAMPAIGNS[maxi(0, D.CAMPAIGNS.find(C) - 1)]
		hv.add_child(lbl(D.FACS[C.fac].name.to_upper() + "  ·  " + ("%d OF %d SECURED" % [mini(done, C.missions.size()), C.missions.size()] if op else "FINISH " + prev.name.to_upper() + " TO OPEN"), f_wide, 11, W_BRASS if op else W_SAND))
		var tg := lbl(C.tag, f_body, 12, W_SAND); tg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; hv.add_child(tg)
		var hs := Stamp.new(); hs.small = true; hs.custom_minimum_size = Vector2(120, 44); hs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hs.text = "LOCKED" if not op else ("COMPLETE" if done >= C.missions.size() else ("IN PROGRESS" if done > 0 else "NEW"))
		hs.col = W_SAND if not op else (W_GREEN if done >= C.missions.size() else W_BRASS)
		hh.add_child(hs)
		if not op: hp.modulate.a = 0.7
		if C.id == focus_id and focus == null: focus = hp
		var grid := GridContainer.new(); grid.columns = 2; grid.add_theme_constant_override("h_separation", 8); grid.add_theme_constant_override("v_separation", 8); camp_pane.add_child(grid)
		for i in C.missions.size():
			var b := _mission_btn(C, i, done)
			grid.add_child(b)
			if C.id == focus_id and i == done: focus = b
		var gap := Control.new(); gap.custom_minimum_size.y = 6; camp_pane.add_child(gap)
	if focus: _show_next.call_deferred(focus)

func _mission_btn(C: Dictionary, i: int, done: int) -> Button:
	var m: Dictionary = C.missions[i]
	var b := Button.new(); b.focus_mode = Control.FOCUS_NONE; b.custom_minimum_size = Vector2(0, 64); b.disabled = i > done; b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nx: bool = i == done
	b.add_theme_stylebox_override("normal", cut(W_SEL if nx else W_OLIVE2, C_ACC if nx else W_LINE, 2 if nx else 1, 9))
	b.add_theme_stylebox_override("hover", cut(W_SEL if nx else W_OLIVE2, W_SAND, 1, 9))
	b.add_theme_stylebox_override("pressed", cut(W_OLIVE2.darkened(0.2), W_SAND, 1, 9))
	b.add_theme_stylebox_override("disabled", cut(Color(W_OLIVE2, 0.45), Color(W_LINE, 0.45), 1, 9))
	var h := HBoxContainer.new(); h.set_anchors_preset(Control.PRESET_FULL_RECT); h.offset_left = 12; h.offset_right = -10; h.add_theme_constant_override("separation", 10); h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := lbl("%02d" % (i + 1), f_title, 22, C_ACC if nx else W_SAND); n.custom_minimum_size.x = 38; n.size_flags_vertical = Control.SIZE_SHRINK_CENTER; h.add_child(n)
	var v := VBoxContainer.new(); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; v.alignment = BoxContainer.ALIGNMENT_CENTER; v.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.add_theme_constant_override("separation", 1)
	var t := lbl(m.title.to_upper(), f_wide, 14, W_KHAKI); t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; t.clip_text = true; v.add_child(t)
	var tg := lbl(m.tag + "  ·  " + D.THEMES[m.map.theme].name, f_body, 12, W_SAND); tg.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; tg.clip_text = true; v.add_child(tg)
	h.add_child(v)
	var st := Stamp.new(); st.small = true; st.custom_minimum_size = Vector2(98, 38); st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	st.text = "SECURED" if i < done else ("ORDERS IN" if nx else "CLASSIFIED")
	st.col = W_GREEN if i < done else (W_BRASS if nx else W_SAND)
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE; h.add_child(st)
	if i > done: h.modulate.a = 0.45
	b.add_child(h)
	# PASS lets a drag that starts on a mission scroll the list; a press that scrolled is not a tap
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.button_down.connect(func(): press_scroll = camp_scroll.scroll_vertical)
	b.pressed.connect(func(): if absi(camp_scroll.scroll_vertical - press_scroll) < 8: main.camp_id = C.id; main.open_brief(i))
	return b

func _show_next(b: Control) -> void:
	await get_tree().process_frame
	if is_instance_valid(b): camp_scroll.ensure_control_visible(b)

func set_end_stats(rows: Array) -> void:
	for ch in btn.end_stats.get_children(): ch.queue_free()
	for r in rows:
		var p := PanelContainer.new(); p.add_theme_stylebox_override("panel", cut(W_OLIVE2, W_LINE, 1, 7)); p.custom_minimum_size.x = 118; p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 0); p.add_child(v)
		v.add_child(lbl(r[0].to_upper(), f_wide, 9, W_SAND)); v.add_child(lbl(str(r[1]), f_title, 20, W_KHAKI))
		btn.end_stats.add_child(p)

func tick(dt: float) -> void:
	if toast_t > 0:
		toast_t -= dt
		if toast_t <= 0: toast_box.visible = false
	hud.get_meta("draw").queue_redraw()

# ---------------- custom controls ----------------
## Menu backdrop: a dusk battlefield (ridges, tank silhouettes, searchlights, shell flashes,
## smoke, embers, wire). Without `full` it is only a dark veil over the paused game.
class WarBG extends Control:
	var full := true
	var hero := false   # splash art: crossed searchlights, big tanks in the foreground, frozen frame
	var t := 0.0
	func _process(dt: float) -> void:
		if full and not hero and is_visible_in_tree():
			t += dt; queue_redraw()
	static func _h(i: float) -> float:
		return fposmod(sin(i * 127.1 + 311.7) * 43758.5453, 1.0)
	func _ridge(x: float, base: float, amp: float, sd: float, u: float) -> float:
		var q := x / u
		return base - amp * (sin(q * 0.006 + sd) * 0.55 + sin(q * 0.017 + sd * 2.3) * 0.3 + sin(q * 0.043 + sd * 4.1) * 0.15)
	func _band(y0: Callable, col: Color, step: float) -> void:
		var pts := PackedVector2Array(); var x := 0.0
		while x <= size.x + step:
			pts.append(Vector2(x, y0.call(x))); x += step
		pts.append(Vector2(size.x + step, size.y)); pts.append(Vector2(0, size.y))
		draw_colored_polygon(pts, col)
	func _grad(r: Rect2, top: Color, bot: Color) -> void:
		draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), PackedColorArray([top, top, bot, bot]))
	func _tank(p: Vector2, u: float, col: Color, flip := false, ang := 0.0) -> void:
		draw_set_transform(p, ang, Vector2(-u if flip else u, u))
		draw_colored_polygon(PackedVector2Array([Vector2(-26, 0), Vector2(26, 0), Vector2(31, -6), Vector2(25, -11), Vector2(-25, -11), Vector2(-31, -6)]), col)
		draw_colored_polygon(PackedVector2Array([Vector2(-13, -11), Vector2(12, -11), Vector2(9, -19), Vector2(-9, -19)]), col)
		draw_rect(Rect2(8, -16.5, 30, 3), col)
		draw_line(Vector2(-6, -19), Vector2(-9, -30), col, 1.2)
		draw_set_transform(Vector2.ZERO)
	func _draw() -> void:
		var s := size
		if not full:
			draw_rect(Rect2(Vector2.ZERO, s), Color(0.03, 0.035, 0.025, 0.72))
			return
		var u := s.y / 486.0
		var hz := s.y * 0.62
		# sky: soot black down to a burning horizon
		_grad(Rect2(0, 0, s.x, hz * 0.55), Color("0b0a08"), Color("1a100c"))
		_grad(Rect2(0, hz * 0.55, s.x, hz * 0.45 + 2), Color("1a100c"), Color("4a1a0f"))
		draw_rect(Rect2(0, hz, s.x, s.y - hz), Color("140b08"))
		# map grid
		var g := 46.0 * u; var x := 0.0
		while x < s.x:
			draw_line(Vector2(x, 0), Vector2(x, s.y), Color(0.85, 0.8, 0.64, 0.025), 1.0); x += g
		var y := 0.0
		while y < s.y:
			draw_line(Vector2(0, y), Vector2(s.x, y), Color(0.85, 0.8, 0.64, 0.025), 1.0); y += g
		# fires glowing behind the far ridge
		for i in 4:
			var fx := s.x * (0.18 + 0.23 * i + 0.05 * _h(i + 3)); var fl := 0.85 + 0.15 * sin(t * (2.0 + i) + i)
			draw_set_transform(Vector2(fx, hz), 0, Vector2(1.0, 0.35))
			for k in 6:
				draw_circle(Vector2.ZERO, (170 - k * 24) * u * fl, Color(0.95, 0.38, 0.12, 0.05))
			draw_set_transform(Vector2.ZERO)
		# searchlights sweeping the clouds
		for i in 2:
			var o := Vector2(s.x * (0.58 + 0.3 * i), hz + 26 * u)
			var a := -PI / 2 + sin(t * (0.23 + 0.07 * i) + i * 2.0) * 0.6
			var al := 0.16
			if hero:
				o = Vector2(s.x * (0.3 + 0.4 * i), hz + 30 * u); a = -PI / 2 + (0.42 if i == 0 else -0.42); al = 0.2
			var L := s.y * 1.1; var w := 0.07
			draw_polygon(PackedVector2Array([o, o + Vector2(cos(a - w), sin(a - w)) * L, o + Vector2(cos(a + w), sin(a + w)) * L]),
				PackedColorArray([Color(1, 0.93, 0.75, al), Color(1, 0.93, 0.75, 0.0), Color(1, 0.93, 0.75, 0.0)]))
		if hero:
			for fx in [0.12, 0.88]:
				for k in 8:
					draw_circle(Vector2(s.x * fx, hz - 4 * u), (90 - k * 10) * u, Color(1, 0.5 + k * 0.04, 0.18, 0.045))
		# shell bursts on the horizon
		for i in 3:
			var ph := t * 0.55 + i * 0.37; var k := floorf(ph); var f := ph - k
			if f < 0.3:
				var bx := s.x * (0.08 + 0.84 * _h(k * 3.0 + i)); var e := 1.0 - f / 0.3
				draw_circle(Vector2(bx, hz - 6 * u), 46 * u * (0.4 + f * 2), Color(1, 0.6, 0.25, 0.10 * e))
				draw_circle(Vector2(bx, hz - 6 * u), 14 * u * (0.5 + f * 2), Color(1, 0.85, 0.55, 0.35 * e))
		# far ridge with a radio mast
		var far := func(px): return _ridge(px + 300, hz + 4 * u, 22 * u, 1.3, u)
		_band(far, Color("2c1610"), 8)
		var mx := s.x * 0.7; var my: float = far.call(mx)
		draw_line(Vector2(mx, my), Vector2(mx, my - 54 * u), Color("2c1610"), 2.0 * u)
		draw_line(Vector2(mx - 10 * u, my), Vector2(mx, my - 54 * u), Color("2c1610"), 1.0 * u)
		draw_line(Vector2(mx + 10 * u, my), Vector2(mx, my - 54 * u), Color("2c1610"), 1.0 * u)
		if int(t * 1.2) % 2 == 0: draw_circle(Vector2(mx, my - 56 * u), 2.2 * u, Color(1, 0.25, 0.2, 0.9))
		# drifting smoke
		for i in 7:
			var sx := fposmod(s.x * _h(i + 10) - t * (8 + 6 * _h(i)) * u, s.x + 400 * u) - 200 * u
			var sy := hz - (10 + 70 * _h(i + 20)) * u
			for k in 3:
				draw_circle(Vector2(sx + k * 40 * u, sy - k * 6 * u), (60 + 30 * k) * u, Color(0.2, 0.15, 0.12, 0.05))
		# mid ridge with an armored column
		var mid := func(px): return _ridge(px, hz + 46 * u, 26 * u, 4.2, u)
		var mc := Color("0f0907")
		_band(mid, mc, 8)
		for i in 4:
			var tx := fposmod(s.x * [0.03, 0.13, 0.80, 0.91][i] + t * 4 * u, s.x + 80 * u) - 40 * u
			var ty: float = mid.call(tx)
			var slope := atan2(float(mid.call(tx + 10)) - ty, 10.0)
			_tank(Vector2(tx, ty + 2 * u), u * (1.0 - 0.1 * (i % 2)), mc, false, slope)
		# foreground: earth, tank traps and barbed wire
		var near := func(px): return _ridge(px + 900, s.y * 0.9, 16 * u, 7.7, u)
		var nc := Color("060403")
		_band(near, nc, 8)
		var px := 30.0 * u; var prev := Vector2(-1, -1)
		while px < s.x + 80 * u:
			var py: float = near.call(px)
			var top := Vector2(px, py - 30 * u)
			draw_line(Vector2(px, py + 4 * u), top, nc, 3.0 * u)
			if prev.x >= 0:
				var pts := PackedVector2Array()
				for k in 13:
					var f2 := k / 12.0
					pts.append(prev.lerp(top, f2) + Vector2(0, sin(f2 * PI) * 7 * u))
				draw_polyline(pts, nc, 1.4 * u)
				for k in range(1, 12, 2):
					var bp := pts[k]
					draw_line(bp + Vector2(-3, -3) * u, bp + Vector2(3, 3) * u, nc, 1.0 * u)
			prev = top
			if _h(px) > 0.55:
				var hx := px + 40 * u; var hy: float = near.call(hx)
				draw_line(Vector2(hx - 10 * u, hy), Vector2(hx + 10 * u, hy - 18 * u), nc, 2.5 * u)
				draw_line(Vector2(hx + 10 * u, hy), Vector2(hx - 10 * u, hy - 18 * u), nc, 2.5 * u)
				draw_line(Vector2(hx, hy + 2 * u), Vector2(hx + 2 * u, hy - 20 * u), nc, 2.5 * u)
			px += 120 * u
		if hero:
			for tk in [[0.84, 3.4, true, 0.06], [0.15, 2.4, false, -0.04]]:
				var tp := Vector2(s.x * tk[0], float(near.call(s.x * tk[0])) + 6 * u)
				_tank(tp + Vector2(0, -2.5 * u), tk[1] * u, Color(0.95, 0.42, 0.15, 0.55), tk[2], tk[3])
				_tank(tp, tk[1] * u, nc, tk[2], tk[3])
		# embers
		for i in 46:
			var sp := (14 + 22 * _h(i + 40)) * u
			var ey := s.y - fposmod(t * sp + _h(i + 50) * s.y, s.y * 0.85)
			var ex := s.x * _h(i + 60) + sin(t * 0.8 + i) * 14 * u
			var life := (s.y - ey) / (s.y * 0.85)
			draw_circle(Vector2(ex, ey), (1.0 + _h(i + 70) * 1.4) * u, Color(1, 0.55 + 0.3 * _h(i), 0.2, 0.75 * (1.0 - life)))
		# vignette, darker on the left behind the title
		_grad(Rect2(0, 0, s.x, s.y * 0.25), Color(0, 0, 0, 0.55), Color(0, 0, 0, 0))
		draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x * 0.5, 0), Vector2(s.x * 0.5, s.y), Vector2(0, s.y)]),
			PackedColorArray([Color(0, 0, 0, 0.45), Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.45)]))

## Panel with brass L-brackets in its corners.
class Frame extends PanelContainer:
	var accent := Color("d9a441")
	func _draw() -> void:
		var r := Rect2(Vector2(-3, -3), size + Vector2(6, 6)); var L := 16.0; var w := 2.0
		for c in [[r.position, Vector2(1, 1)], [Vector2(r.end.x, r.position.y), Vector2(-1, 1)], [r.end, Vector2(-1, -1)], [Vector2(r.position.x, r.end.y), Vector2(1, -1)]]:
			var p: Vector2 = c[0]; var d: Vector2 = c[1]
			draw_line(p, p + Vector2(d.x * L, 0), accent, w); draw_line(p, p + Vector2(0, d.y * L), accent, w)

## Rubber stamp: rotated double-ruled box with a word in it.
class Stamp extends Control:
	var text := "CLASSIFIED"
	var col := Color("e5483f")
	var small := false
	func _draw() -> void:
		var f: Font = load("res://fonts/chakra-petch-latin-700-normal.woff2")
		var fs := 11 if small else 18
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var bw := tw + (14.0 if small else 24.0); var bh := fs + (10.0 if small else 18.0)
		draw_set_transform(size / 2, -0.12 if small else -0.16)
		var r := Rect2(-bw / 2, -bh / 2, bw, bh); var c := Color(col, 0.85)
		draw_rect(r, c, false, 2.0)
		if not small: draw_rect(r.grow(-4), Color(col, 0.6), false, 1.0)
		draw_string(f, Vector2(-tw / 2, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
		draw_set_transform(Vector2.ZERO)

## Hazard stripes: along the bottom of a button, or as a full strip when `stripe`.
class Hazard extends Control:
	var stripe := false
	func _draw() -> void:
		var h := size.y if stripe else 5.0
		var y0 := 0.0 if stripe else size.y - h
		var x := -h; var i := 0
		var a := Color("d9a441", 0.9) if stripe else Color(0, 0, 0, 0.35)
		while x < size.x:
			if i % 2 == 0:
				var pts := PackedVector2Array([Vector2(x, y0 + h), Vector2(x + h, y0), Vector2(x + 2 * h, y0), Vector2(x + h, y0 + h)])
				for k in pts.size(): pts[k].x = clampf(pts[k].x, 0, size.x)
				draw_colored_polygon(pts, a)
			x += h; i += 1
		if stripe: draw_rect(Rect2(0, 0, size.x, h), Color("d9a441", 0.25), false, 1.0)

## Unit insignia: a shield with three chevrons and a star.
class Insignia extends Control:
	func _draw() -> void:
		var s := size; var c := Color("d9a441"); var k := Color("d8cba3")
		var sh := PackedVector2Array([Vector2(s.x * 0.5, 0), Vector2(s.x, s.y * 0.14), Vector2(s.x * 0.92, s.y * 0.66), Vector2(s.x * 0.5, s.y), Vector2(s.x * 0.08, s.y * 0.66), Vector2(0, s.y * 0.14)])
		draw_colored_polygon(sh, Color("21271a"))
		sh.append(sh[0]); draw_polyline(sh, c, 2.0)
		# chevrons taper to points and narrow toward the tip, clear of the border
		for i in 3:
			var y := 0.47 + 0.13 * i; var hw: float = [0.27, 0.24, 0.19][i]; var t := 0.075
			draw_colored_polygon(PackedVector2Array([Vector2(0.5 - hw, y) * s, Vector2(0.5, y + 0.11 - t / 2) * s, Vector2(0.5 + hw, y) * s, Vector2(0.5, y + 0.11 + t / 2) * s]), k)
		var st := PackedVector2Array(); var cc := Vector2(s.x * 0.5, s.y * 0.27)
		for i in 10:
			var a := -PI / 2 + i * PI / 5; var r := s.x * (0.13 if i % 2 == 0 else 0.055)
			st.append(cc + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(st, C_ACC_STAR)
	const C_ACC_STAR := Color("e5483f")

class HudDraw extends Control:
	var ui
	func _draw() -> void:
		if ui.main: ui.main.draw_hud(self)

class MiniMap extends Control:
	var ui
	var src := false   # draws the side panel minimap's texture (the enlarged copy)
	var tex: ImageTexture
	var img: Image
	var dragging := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		tex = ImageTexture.create_from_image(img)
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if src: draw_rect(r.grow(4), Color(0.055, 0.062, 0.045, 0.94))
		draw_rect(r, Color.BLACK)
		draw_texture_rect(ui.mini.tex if src else tex, r, false)
		# plotting-table grid and a light vignette
		for i in range(1, 8):
			var x := size.x * i / 8.0; var y := size.y * i / 8.0
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.85, 0.8, 0.64, 0.07), 1.0)
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.85, 0.8, 0.64, 0.07), 1.0)
		for k in 3:
			draw_rect(r.grow(-k * 2.0), Color(0, 0, 0, 0.22 - k * 0.06), false, 2.0)
		if ui.main: ui.main.draw_mini_overlay(self)
		draw_rect(r, Color("4a5238"), false, 1.0)
		# brass corner brackets and a north mark
		var L := 14.0; var b := Color("d9a441"); var o := r.grow(3)
		for q in [[o.position, 1, 1], [Vector2(o.end.x, o.position.y), -1, 1], [o.end, -1, -1], [Vector2(o.position.x, o.end.y), 1, -1]]:
			var p: Vector2 = q[0]
			draw_line(p, p + Vector2(q[1] * L, 0), b, 2.0); draw_line(p, p + Vector2(0, q[2] * L), b, 2.0)
		draw_colored_polygon(PackedVector2Array([Vector2(size.x / 2 - 5, -3), Vector2(size.x / 2 + 5, -3), Vector2(size.x / 2, 5)]), b)
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			dragging = ev.pressed
			if ev.pressed: _go(ev.position)
			accept_event()
		elif ev is InputEventMouseMotion and dragging:
			_go(ev.position); accept_event()
	func _go(p: Vector2) -> void:
		ui.main.mini_go(p / size)

class BuildItem extends Control:
	var ui
	var cat := ""
	var type := ""
	var icon: Texture2D
	var prog := 0.0
	var is_ready := false
	var active := false
	var n := 0
	var locked := false
	var lp_t := -1.0
	var did := false
	var press_at := Vector2()
	var dragging := false   # a ready building being dragged out onto the map
	const CANCEL := Vector2(26, 26)   # top-left corner of an item with orders: tap it to cancel one
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
	func _process(dt: float) -> void:
		if lp_t >= 0:
			lp_t += dt
			if lp_t > 0.55 and not did:
				# hold: units queue five at once; a building cancels
				did = true
				if cat == "bld": ui.main.cancel_item(cat, type)
				else: ui.main.queue_many(cat, type, 5)
	func _has_orders() -> bool:
		return active or n > 0 or is_ready
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			if ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
				ui.main.cancel_item(cat, type); accept_event(); return
			if ev.button_index != MOUSE_BUTTON_LEFT: return
			if ev.pressed:
				lp_t = 0.0; did = false; press_at = ev.position; dragging = false
			else:
				if dragging:
					dragging = false; ui.main.drag_build_end(get_global_transform() * ev.position); accept_event()
				elif lp_t >= 0 and not did and Rect2(Vector2.ZERO, size).has_point(ev.position):
					if _has_orders() and Rect2(Vector2.ZERO, CANCEL).has_point(ev.position): ui.main.cancel_item(cat, type)
					else: ui.main.click_item(cat, type)
				lp_t = -1.0
		elif ev is InputEventMouseMotion and (lp_t >= 0 or dragging):
			if dragging:
				ui.main.drag_build_move(get_global_transform() * ev.position); accept_event()
			elif cat == "bld" and is_ready and ev.position.distance_to(press_at) > 10:
				dragging = true; lp_t = -1.0; did = true
				ui.main.drag_build_start(type, get_global_transform() * ev.position); accept_event()
			elif ev.relative.length() > 6:
				lp_t = -1.0  # it's a scroll, not a press
	func _draw() -> void:
		var d: Dictionary = D.def_of(type)
		var a := 0.4 if locked else 1.0
		var hot := active or is_ready
		# chamfered card; brass trim while it is in production
		draw_style_box(UI.cut(Color("1a1f15") if not hot else Color("221f12"), Color("d9a441") if hot else Color("3a4130"), 2 if hot else 1, 8, 0), Rect2(Vector2.ZERO, size))
		# icon well: dark steel with a spotlight behind the model and a floor line
		var ir := Rect2(4, 4, size.x - 8, 46)
		draw_rect(ir, Color("0d100b"))
		var lc := ir.get_center() + Vector2(0, 4)
		for k in 4: draw_circle(lc, (26 - k * 6) * 1.0, Color(0.85, 0.78, 0.55, 0.035 * a))
		draw_line(Vector2(ir.position.x, ir.end.y - 8), Vector2(ir.end.x, ir.end.y - 8), Color(0.85, 0.8, 0.64, 0.06), 1.0)
		if icon:
			var iw := 58.0; var ih := 46.0
			draw_texture_rect(icon, Rect2(ir.get_center().x - iw / 2, ir.position.y, iw, ih), false, Color(1, 1, 1, a))
		var nm: String = d.name
		var f: Font = ui.f_body6
		var tw := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var fs := 11 if tw <= size.x - 6 else 10
		draw_string(f, Vector2(3, 63), nm, HORIZONTAL_ALIGNMENT_CENTER, size.x - 6, fs, Color(Color("e2dac2"), a))
		if locked:
			var lw: float = ui.f_disp.get_string_size("LOCKED", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			var x0: float = (size.x - lw - 14) / 2
			UI.glyph(self, "lock", Rect2(x0, 67, 10, 11), Color("8b8a78"))
			draw_string(ui.f_disp, Vector2(x0 + 14, 77), "LOCKED", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("8b8a78"))
		else:
			var cs := str(d.cost)
			var cw: float = ui.f_disp7.get_string_size(cs, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var x0: float = (size.x - cw - 12) / 2
			UI.glyph(self, "aur", Rect2(x0, 67, 8, 11), UI.C_AUR)
			draw_string(ui.f_disp7, Vector2(x0 + 12, 77), cs, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.C_AUR)
		if active and not is_ready:
			# darken the part still to build, clockwise from the top, over the icon well
			var c := ir.get_center(); var r := ir.size.length() / 2
			var pts := PackedVector2Array([c])
			var steps := 32
			for i in range(int(prog * steps), steps + 1):
				var ang: float = -PI / 2 + TAU * max(prog, float(i) / steps)
				pts.append(c + Vector2(cos(ang), sin(ang)) * r)
			if pts.size() > 2:
				var cp := PackedVector2Array()
				for p in pts: cp.append(Vector2(clamp(p.x, ir.position.x, ir.end.x), clamp(p.y, ir.position.y, ir.end.y)))
				draw_colored_polygon(cp, Color(0, 0, 0, 0.6))
			draw_rect(Rect2(ir.position.x, ir.end.y - 3, ir.size.x, 3), Color(0, 0, 0, 0.7))
			draw_rect(Rect2(ir.position.x, ir.end.y - 3, ir.size.x * clampf(prog, 0, 1), 3), UI.C_AUR)
		if n > 1:
			var bw := 24.0; var br := Rect2(size.x - bw - 3, 3, bw, 16)
			draw_style_box(UI.cut(Color("d9a441"), Color(0, 0, 0, 0), 0, 4, 0), br)
			draw_string(ui.f_disp7, Vector2(br.position.x, br.position.y + 12.5), "×%d" % n, HORIZONTAL_ALIGNMENT_CENTER, bw, 11, Color("1a1408"))
		if _has_orders():  # cancel corner
			draw_style_box(UI.cut(Color(0.1, 0.03, 0.02, 0.85), Color("e5483f", 0.7), 1, 4, 0), Rect2(Vector2(3, 3), CANCEL - Vector2(8, 8)))
			draw_line(Vector2(8, 8), Vector2(16, 16), Color("ffd0cc"), 2); draw_line(Vector2(16, 8), Vector2(8, 16), Color("ffd0cc"), 2)
		if is_ready:
			UI.ready_banner(self, ui, Rect2(0, 18, size.x, 18))

## Top-bar chip for one production line while the side panel is hidden: icon, progress, queue size.
## Tap: place a ready building, otherwise open the panel on that tab.
class ProdChip extends Control:
	var ui
	var cat := ""
	var type := ""
	var prog := 0.0
	var n := 0
	var is_ready := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
			ui.main.prod_chip_tap(cat); accept_event()
	func _draw() -> void:
		draw_style_box(ui.hsb("normal", false, 6, 6), Rect2(Vector2.ZERO, size))
		if is_ready: draw_style_box(UI.cut(Color(0, 0, 0, 0), UI.C_AUR, 2, 7, 0), Rect2(Vector2.ZERO, size))
		var it = ui.items.get(cat + ":" + type)
		var ir := Rect2(4, 3, size.x - 8, size.y - 13)
		if it and it.icon: draw_texture_rect(it.icon, ir, false)
		draw_rect(Rect2(5, size.y - 8, size.x - 10, 4), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(5, size.y - 8, (size.x - 10) * clampf(prog, 0, 1), 4), UI.C_AUR)
		UI.ticks(self, size, Color(Color("d9a441"), 0.5), 6.0)
		if n > 1:
			var br := Rect2(size.x - 22, 3, 19, 14)
			draw_style_box(UI.cut(Color("d9a441"), Color(0, 0, 0, 0), 0, 4, 0), br)
			draw_string(ui.f_disp7, Vector2(br.position.x, br.position.y + 11.5), str(n), HORIZONTAL_ALIGNMENT_CENTER, br.size.x, 11, Color("1a1408"))
		if is_ready: UI.ready_banner(self, ui, Rect2(0, size.y / 2 - 9, size.x, 16))

## READY strip across a build card or chip: hazard stripes behind white text, blinking.
static func ready_banner(c: CanvasItem, ui, r: Rect2) -> void:
	var blink := int(Time.get_ticks_msec() / 500) % 2 == 0
	c.draw_rect(r, Color("e5483f") if blink else Color("8a231d"))
	var x := r.position.x - r.size.y; var i := 0
	while x < r.end.x:
		if i % 2 == 0:
			var pts := PackedVector2Array([Vector2(x, r.end.y), Vector2(x + r.size.y, r.position.y), Vector2(x + r.size.y * 1.5, r.position.y), Vector2(x + r.size.y * 0.5, r.end.y)])
			for k in pts.size(): pts[k].x = clampf(pts[k].x, r.position.x, r.end.x)
			c.draw_colored_polygon(pts, Color(0, 0, 0, 0.18))
		x += r.size.y * 0.5; i += 1
	c.draw_line(Vector2(r.position.x, r.position.y + 0.5), Vector2(r.end.x, r.position.y + 0.5), Color("d9a441"), 1.0)
	c.draw_line(Vector2(r.position.x, r.end.y - 0.5), Vector2(r.end.x, r.end.y - 0.5), Color("d9a441"), 1.0)
	c.draw_string(ui.f_disp7, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + 4.5), "READY", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 12, Color.WHITE)

# ---------------- HUD widgets ----------------
## Maps a flat [x0, y0, x1, y1, ...] list in 0..1 into rect r.
static func _pts(r: Rect2, a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, a.size(), 2): out.append(r.position + Vector2(a[i], a[i + 1]) * r.size)
	return out

## Small vector icons for the HUD, drawn in rect r. Kept to a few flat shapes so they read at 14-24 UI units.
static func glyph(c: CanvasItem, k: String, r: Rect2, col: Color, lw := 2.0) -> void:
	var P := func(x: float, y: float) -> Vector2: return r.position + Vector2(x, y) * r.size
	var dk := col.darkened(0.4)
	match k:
		"aur":  # faceted crystal, lit on the left
			c.draw_colored_polygon(_pts(r, [0.5, 0.0, 0.86, 0.34, 0.5, 1.0, 0.14, 0.34]), col)
			c.draw_colored_polygon(_pts(r, [0.5, 0.0, 0.86, 0.34, 0.5, 1.0, 0.56, 0.34]), dk)
			c.draw_colored_polygon(_pts(r, [0.5, 0.0, 0.3, 0.34, 0.5, 0.42]), col.lightened(0.45))
		"pwr":
			c.draw_colored_polygon(_pts(r, [0.62, 0.0, 0.14, 0.58, 0.46, 0.58, 0.36, 1.0, 0.86, 0.4, 0.54, 0.4, 0.74, 0.0]), col)
		"atk":
			var ctr: Vector2 = P.call(0.5, 0.5); var rad := r.size.x * 0.32
			c.draw_arc(ctr, rad, 0, TAU, 24, col, lw, true)
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				c.draw_line(ctr + d * r.size.x * 0.16, ctr + d * r.size.x * 0.5, col, lw)
			c.draw_circle(ctr, r.size.x * 0.06, col)
		"stop":
			var oc := PackedVector2Array(); var ctr: Vector2 = P.call(0.5, 0.5)
			for i in 9: oc.append(ctr + Vector2.from_angle(PI / 8 + i * PI / 4) * r.size.x * 0.46)
			c.draw_polyline(oc, col, lw, true)
			c.draw_rect(Rect2(P.call(0.33, 0.33), r.size * 0.34), col)
		"x":
			c.draw_line(P.call(0.2, 0.2), P.call(0.8, 0.8), col, lw + 0.5, true); c.draw_line(P.call(0.8, 0.2), P.call(0.2, 0.8), col, lw + 0.5, true)
		"form":  # two ranks advancing behind a chevron
			c.draw_polyline(_pts(r, [0.24, 0.34, 0.5, 0.1, 0.76, 0.34]), col, lw, true)
			for row in 2:
				for i in 3: c.draw_rect(Rect2(P.call(0.14 + i * 0.27, 0.48 + row * 0.27), r.size * 0.18), col if row == 0 else dk)
		"all":
			var st := PackedVector2Array(); var ctr: Vector2 = P.call(0.5, 0.55)
			for i in 10: st.append(ctr + Vector2.from_angle(-PI / 2 + i * PI / 5) * r.size.x * (0.5 if i % 2 == 0 else 0.21))
			c.draw_colored_polygon(st, col)
		"inf":  # helmeted soldier, head and shoulders
			c.draw_colored_polygon(_pts(r, [0.26, 0.36, 0.3, 0.16, 0.5, 0.06, 0.7, 0.16, 0.74, 0.36, 0.86, 0.38, 0.14, 0.38]), col)
			c.draw_rect(Rect2(P.call(0.36, 0.38), r.size * Vector2(0.28, 0.16)), dk)
			c.draw_colored_polygon(_pts(r, [0.1, 1.0, 0.16, 0.66, 0.36, 0.56, 0.64, 0.56, 0.84, 0.66, 0.9, 1.0]), col)
		"veh":  # tank in profile
			c.draw_colored_polygon(_pts(r, [0.04, 0.8, 0.96, 0.8, 1.0, 0.64, 0.92, 0.52, 0.08, 0.52, 0.0, 0.64]), col)
			c.draw_colored_polygon(_pts(r, [0.24, 0.52, 0.66, 0.52, 0.6, 0.3, 0.3, 0.3]), col)
			c.draw_rect(Rect2(P.call(0.6, 0.36), r.size * Vector2(0.4, 0.08)), col)
			for i in 4: c.draw_circle(P.call(0.2 + i * 0.2, 0.68), r.size.x * 0.06, dk)
		"air":  # aircraft from above
			c.draw_colored_polygon(_pts(r, [0.45, 0.06, 0.5, 0.0, 0.55, 0.06, 0.56, 0.96, 0.44, 0.96]), col)
			c.draw_colored_polygon(_pts(r, [0.5, 0.3, 0.98, 0.56, 0.98, 0.64, 0.5, 0.52, 0.02, 0.64, 0.02, 0.56]), col)
			c.draw_colored_polygon(_pts(r, [0.5, 0.78, 0.74, 0.94, 0.26, 0.94]), col)
		"idle":  # hourglass
			c.draw_line(P.call(0.18, 0.06), P.call(0.82, 0.06), col, lw); c.draw_line(P.call(0.18, 0.94), P.call(0.82, 0.94), col, lw)
			c.draw_polyline(_pts(r, [0.26, 0.06, 0.5, 0.5, 0.26, 0.94]), col, lw, true); c.draw_polyline(_pts(r, [0.74, 0.06, 0.5, 0.5, 0.74, 0.94]), col, lw, true)
			c.draw_colored_polygon(_pts(r, [0.5, 0.62, 0.68, 0.9, 0.32, 0.9]), dk)
		"map":  # folded map
			var m := _pts(r, [0.04, 0.2, 0.36, 0.06, 0.64, 0.2, 0.96, 0.06, 0.96, 0.82, 0.64, 0.96, 0.36, 0.82, 0.04, 0.96])
			c.draw_colored_polygon(_pts(r, [0.36, 0.06, 0.64, 0.2, 0.64, 0.96, 0.36, 0.82]), Color(col, 0.35))
			m.append(m[0]); c.draw_polyline(m, col, lw, true)
			c.draw_line(P.call(0.36, 0.06), P.call(0.36, 0.82), col, lw * 0.6); c.draw_line(P.call(0.64, 0.2), P.call(0.64, 0.96), col, lw * 0.6)
		"pause":
			c.draw_rect(Rect2(P.call(0.22, 0.14), r.size * Vector2(0.2, 0.72)), col); c.draw_rect(Rect2(P.call(0.58, 0.14), r.size * Vector2(0.2, 0.72)), col)
		"hide":
			c.draw_polyline(_pts(r, [0.16, 0.18, 0.46, 0.5, 0.16, 0.82]), col, lw + 0.5, true); c.draw_polyline(_pts(r, [0.52, 0.18, 0.82, 0.5, 0.52, 0.82]), col, lw + 0.5, true)
		"build", "bld_crane":  # tower crane
			c.draw_line(P.call(0.32, 0.96), P.call(0.32, 0.08), col, lw + 0.5)
			c.draw_line(P.call(0.06, 0.12), P.call(0.96, 0.12), col, lw)
			c.draw_line(P.call(0.32, 0.0), P.call(0.86, 0.12), col, lw * 0.6); c.draw_line(P.call(0.32, 0.0), P.call(0.1, 0.12), col, lw * 0.6)
			c.draw_line(P.call(0.82, 0.12), P.call(0.82, 0.5), col, lw * 0.6)
			c.draw_rect(Rect2(P.call(0.72, 0.5), r.size * Vector2(0.2, 0.16)), col)
			c.draw_rect(Rect2(P.call(0.14, 0.88), r.size * Vector2(0.38, 0.12)), col)
			c.draw_rect(Rect2(P.call(0.04, 0.08), r.size * Vector2(0.12, 0.12)), dk)
		"bld":  # factory: saw-tooth roof and a stack
			c.draw_colored_polygon(_pts(r, [0.02, 0.96, 0.02, 0.5, 0.3, 0.32, 0.3, 0.5, 0.58, 0.32, 0.58, 0.5, 0.7, 0.5, 0.7, 0.08, 0.86, 0.08, 0.86, 0.5, 0.98, 0.5, 0.98, 0.96]), col)
			for i in 3: c.draw_rect(Rect2(P.call(0.1 + i * 0.27, 0.66), r.size * Vector2(0.14, 0.14)), dk)
		"repair":  # wrench
			var ctr: Vector2 = P.call(0.68, 0.32)
			c.draw_line(P.call(0.16, 0.84), P.call(0.56, 0.44), col, lw + 2.0)
			c.draw_arc(ctr, r.size.x * 0.2, -PI / 4 + 0.75, -PI / 4 + TAU - 0.75, 16, col, lw + 1.0)
		"sell":  # coin stamped with a crystal
			c.draw_arc(P.call(0.5, 0.5), r.size.x * 0.44, 0, TAU, 24, col, lw, true)
			glyph(c, "aur", Rect2(P.call(0.3, 0.22), r.size * Vector2(0.4, 0.56)), col)
		"up":
			c.draw_polyline(_pts(r, [0.16, 0.5, 0.5, 0.18, 0.84, 0.5]), col, lw + 1.0, true); c.draw_polyline(_pts(r, [0.16, 0.86, 0.5, 0.54, 0.84, 0.86]), col, lw + 1.0, true)
		"launch":  # missile
			c.draw_colored_polygon(_pts(r, [0.4, 0.28, 0.5, 0.0, 0.6, 0.28, 0.6, 0.74, 0.4, 0.74]), col)
			c.draw_colored_polygon(_pts(r, [0.4, 0.5, 0.2, 0.8, 0.4, 0.74]), col); c.draw_colored_polygon(_pts(r, [0.6, 0.5, 0.8, 0.8, 0.6, 0.74]), col)
			c.draw_colored_polygon(_pts(r, [0.43, 0.8, 0.57, 0.8, 0.5, 1.0]), Color(col, 0.6))
		"obj":  # pennant on a pole
			c.draw_line(P.call(0.22, 0.04), P.call(0.22, 0.98), col, lw)
			c.draw_colored_polygon(_pts(r, [0.22, 0.06, 0.9, 0.2, 0.64, 0.33, 0.9, 0.48, 0.22, 0.48]), col)
		"lock":
			c.draw_arc(P.call(0.5, 0.42), r.size.x * 0.2, PI, TAU, 12, col, lw)
			c.draw_line(P.call(0.3, 0.42), P.call(0.3, 0.5), col, lw); c.draw_line(P.call(0.7, 0.42), P.call(0.7, 0.5), col, lw)
			c.draw_rect(Rect2(P.call(0.2, 0.48), r.size * Vector2(0.6, 0.46)), col)
			c.draw_rect(Rect2(P.call(0.46, 0.6), r.size * Vector2(0.08, 0.18)), dk)
		"warn":  # hazard triangle
			c.draw_colored_polygon(_pts(r, [0.5, 0.04, 0.98, 0.94, 0.02, 0.94]), col)
			c.draw_rect(Rect2(P.call(0.45, 0.34), r.size * Vector2(0.1, 0.34)), Color(0, 0, 0, 0.85)); c.draw_rect(Rect2(P.call(0.45, 0.74), r.size * Vector2(0.1, 0.1)), Color(0, 0, 0, 0.85))
		"info":  # chevron: a field order
			c.draw_colored_polygon(_pts(r, [0.1, 0.1, 0.55, 0.5, 0.1, 0.9, 0.35, 0.9, 0.8, 0.5, 0.35, 0.1]), col)
		"move":
			c.draw_colored_polygon(_pts(r, [0.5, 0.02, 0.86, 0.42, 0.62, 0.42, 0.62, 0.96, 0.38, 0.96, 0.38, 0.42, 0.14, 0.42]), col)
		"box":
			for q in [[0.1, 0.1, 1, 1], [0.9, 0.1, -1, 1], [0.9, 0.9, -1, -1], [0.1, 0.9, 1, -1]]:
				var o: Vector2 = P.call(q[0], q[1])
				c.draw_line(o, o + Vector2(q[2] * r.size.x * 0.3, 0), col, lw); c.draw_line(o, o + Vector2(0, q[3] * r.size.y * 0.3), col, lw)
			c.draw_rect(Rect2(P.call(0.38, 0.38), r.size * 0.24), col)

class Glyph extends Control:
	var kind := ""
	var col := Color.WHITE
	func _draw() -> void:
		UI.glyph(self, kind, Rect2(Vector2.ZERO, size), col)

## Brass hairline with a dark shadow line beside it, as a divider.
class Rule extends Control:
	var vertical := false
	func _draw() -> void:
		if vertical:
			var x := size.x / 2
			draw_line(Vector2(x, 2), Vector2(x, size.y - 2), Color("d9a441", 0.45), 1.0)
			draw_line(Vector2(x + 1, 2), Vector2(x + 1, size.y - 2), Color(0, 0, 0, 0.5), 1.0)
		else:
			draw_line(Vector2(0, 0.5), Vector2(size.x, 0.5), Color("d9a441", 0.45), 1.0)
			draw_line(Vector2(0, 1.5), Vector2(size.x, 1.5), Color(0, 0, 0, 0.5), 1.0)

## HUD plate: draws its stylebox, then brass ticks on the two square corners and an optional coloured left bar.
class Plate extends PanelContainer:
	var accent := Color("d9a441")
	func _draw() -> void:
		var s := get_theme_stylebox("panel")
		if s and s.has_meta("bar"):
			draw_rect(Rect2(0, 7, 3, size.y - 7), s.get_meta("bar"))
		UI.ticks(self, size, Color(accent, 0.85))

## Brass L-ticks on the top-right and bottom-left corners (the other two are chamfered).
static func ticks(c: CanvasItem, s: Vector2, col: Color, L := 7.0) -> void:
	c.draw_line(Vector2(s.x - L, 0.75), Vector2(s.x - 0.75, 0.75), col, 1.5); c.draw_line(Vector2(s.x - 0.75, 0.75), Vector2(s.x - 0.75, L), col, 1.5)
	c.draw_line(Vector2(0.75, s.y - L), Vector2(0.75, s.y - 0.75), col, 1.5); c.draw_line(Vector2(0.75, s.y - 0.75), Vector2(L, s.y - 0.75), col, 1.5)

## HUD button with a glyph: left of the text, centred when there is no text, or above a caption (`cap`, the build tabs).
class HudBtn extends Button:
	var glyph := ""
	var cap := ""
	func _draw() -> void:
		var on: bool = get_meta("on", false)
		var col: Color = Color("ffd8d2") if on else Color("d9a441")
		if disabled: col = Color(col, 0.45)
		if is_hovered() or button_pressed: col = col.lightened(0.15)
		UI.ticks(self, size, Color(Color("e5483f") if on else Color("d9a441"), 0.7 if on else 0.4), 6.0)
		if glyph == "": return
		if cap != "":
			var gs := 18.0
			UI.glyph(self, glyph, Rect2(size.x / 2 - gs / 2, 6, gs, gs), col)
			var f := get_theme_font("font")
			draw_string(f, Vector2(0, size.y - 7), cap, HORIZONTAL_ALIGNMENT_CENTER, size.x, 10, Color("ffd8d2") if on else Color("a99c78"))
		elif text == "":
			var gs := minf(20.0, size.y * 0.42)
			UI.glyph(self, glyph, Rect2((size - Vector2(gs, gs)) / 2, Vector2(gs, gs)), col)
		else:
			var gs := 18.0
			UI.glyph(self, glyph, Rect2(12, (size.y - gs) / 2, gs, gs), col)

## Army group chip: number, then the unit count as a brass tally; dim while empty.
class GroupChip extends Button:
	var ui
	var idx := 0
	var n := 0
	func _draw() -> void:
		var st := "pressed" if button_pressed else ("hover" if is_hovered() else "normal")
		draw_style_box(ui.hsb(st, false, 6, 6), Rect2(Vector2.ZERO, size))
		var a := 1.0 if n else 0.5
		UI.ticks(self, size, Color(Color("d9a441"), 0.45 * a), 6.0)
		var f: Font = ui.f_disp7
		draw_string(f, Vector2(10, size.y / 2 + 7), str(idx + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(Color("d8cba3"), a))
		if n:
			draw_string(ui.f_disp, Vector2(28, size.y / 2 - 3), "×%d" % n, HORIZONTAL_ALIGNMENT_LEFT, size.x - 30, 11, Color("d9a441"))
			for i in mini(n, 5):
				draw_rect(Rect2(29 + i * 4.5, size.y / 2 + 3, 3, 7), Color("d9a441", 0.9))
		else:
			draw_string(ui.f_disp, Vector2(28, size.y / 2 + 4), "—", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(Color("a99c78"), 0.6))

## Round MOVE / SELECT toggle (hidden by default since select is a hold-and-drag).
class ModeDial extends Button:
	var ui
	var box := false
	func _draw() -> void:
		var c := size / 2; var r := minf(size.x, size.y) / 2 - 2
		var ring: Color = Color("e5483f") if box else Color("d9a441")
		draw_circle(c + Vector2(0, 2), r, Color(0, 0, 0, 0.35))
		draw_circle(c, r, Color(0.055, 0.062, 0.045, 0.92))
		draw_arc(c, r - 1, 0, TAU, 40, ring, 2.0, true)
		draw_arc(c, r - 6, 0, TAU, 40, Color(ring, 0.3), 1.0, true)
		UI.glyph(self, "box" if box else "move", Rect2(c.x - 10, c.y - 30, 20, 20), ring)
		draw_string(ui.f_disp7, Vector2(0, c.y + 8), "SELECT" if box else "MOVE", HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, Color("ffd0cc") if box else Color("d8cba3"))
		draw_string(ui.f_body, Vector2(0, c.y + 22), "drag to box" if box else "tap for Select", HORIZONTAL_ALIGNMENT_CENTER, size.x, 9, Color("a99c78"))

## Power use against supply as ten segments; red when the base is short of power.
class PowerMeter extends Control:
	var frac := 0.0
	var low := false
	func set_val(f: float, l: bool) -> void:
		if is_equal_approx(f, frac) and l == low: return
		frac = f; low = l; queue_redraw()
	func _draw() -> void:
		var n := 10; var gap := 2.0; var w := (size.x - gap * (n - 1)) / n
		var on := Color("ff5a52") if low else Color("8fcf7a")
		for i in n:
			var lit := (i + 0.5) / n <= frac or (i == 0 and frac > 0)
			draw_rect(Rect2(i * (w + gap), 0, w, size.y), on if lit else Color("2a2f22"))
