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
var power_bar: ColorRect
var power_box: PanelContainer
var sw_box: PanelContainer
var sw_name: Label
var sw_time: Label
var obj_l: RichTextLabel
var obj_box: PanelContainer
var toast_box: PanelContainer
var toast_l: Label
var toast_t := 0.0
var cmd_row: HBoxContainer
var btn := {}
var selinfo: Label
var mode_btn: Button
var place_bar: HBoxContainer
var place_hint: Label
var panel: PanelContainer
var mini: Control
var tabs := {}
var grid: GridContainer
var grid_scroll: ScrollContainer
var items := {}
var overlays := {}
var start_mode := "campaign"
var camp_pane: VBoxContainer
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

func mkbtn(text: String, cb: Callable, w := 0.0, h := 42.0, size := 12) -> Button:
	var b := Button.new(); b.text = text.to_upper()
	b.add_theme_font_override("font", f_disp); b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(max(w, 48.0), h)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b

func set_on(b: Button, on: bool) -> void:
	if on:
		b.add_theme_stylebox_override("normal", sb(Color("3a1512"), C_ACC)); b.add_theme_stylebox_override("hover", sb(Color("3a1512"), C_ACC))
		b.add_theme_color_override("font_color", Color("ffd0cc"))
	else:
		b.remove_theme_stylebox_override("normal"); b.remove_theme_stylebox_override("hover"); b.remove_theme_color_override("font_color")

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
	var cbox := _pill(top, "AURITE"); credits_l = lbl("0", f_disp, 16, C_AUR); cbox.get_child(0).add_child(credits_l); cbox.custom_minimum_size.x = 104
	power_box = _pill(top, "POWER"); power_l = lbl("0 / 0", f_disp, 16); power_box.get_child(0).add_child(power_l)
	var bar := ColorRect.new(); bar.color = Color("26313a"); bar.custom_minimum_size = Vector2(84, 5); bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	power_bar = ColorRect.new(); power_bar.color = C_OK; power_bar.size = Vector2(0, 5); power_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(power_bar); power_box.get_child(0).add_child(bar)
	sw_box = _pill(top, "SKYFALL"); sw_name = sw_box.get_child(0).get_child(0); sw_time = lbl("0:00", f_disp, 16, Color("ffd0cc")); sw_box.get_child(0).add_child(sw_time); sw_box.visible = false
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sp.mouse_filter = Control.MOUSE_FILTER_IGNORE; top.add_child(sp)
	var mb := mkbtn("II", func(): main.open_menu(), 44, 44, 16); top.add_child(mb)
	obj_box = PanelContainer.new(); obj_box.position = Vector2(8, 66); obj_box.custom_minimum_size = Vector2(300, 0); obj_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	obj_box.add_theme_stylebox_override("panel", _left_bar(C_AUR))
	var ov := VBoxContainer.new(); ov.add_theme_constant_override("separation", 3); obj_box.add_child(ov)
	ov.add_child(lbl("OBJECTIVE", f_disp, 11, C_AUR))
	obj_l = RichTextLabel.new(); obj_l.fit_content = true; obj_l.custom_minimum_size = Vector2(280, 0); obj_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	obj_l.add_theme_font_override("normal_font", f_body); obj_l.add_theme_font_size_override("normal_font_size", 12); ov.add_child(obj_l)
	obj_box.visible = false; hud.add_child(obj_box)
	toast_box = PanelContainer.new(); toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_l = lbl("", f_disp, 13); toast_box.add_child(toast_l); toast_box.visible = false
	toast_box.anchor_left = 0.5; toast_box.anchor_right = 0.5; toast_box.offset_top = 64; toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud.add_child(toast_box)
	cmd_row = HBoxContainer.new(); cmd_row.add_theme_constant_override("separation", 6); cmd_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cmd_row.anchor_top = 1; cmd_row.anchor_bottom = 1; cmd_row.offset_left = 8; cmd_row.offset_top = -50; cmd_row.offset_bottom = -8
	hud.add_child(cmd_row)
	for k in ["all", "inf", "veh", "air", "idle"]:
		var b := mkbtn(k, func(): main.squad_btn(k)); b.add_theme_stylebox_override("normal", sb(Color(0.08, 0.1, 0.12, 0.92), Color("3b4a54")))
		cmd_row.add_child(b); btn[k] = b
	for pair in [["sw", "Launch"], ["amove", "Attack"], ["stop", "Stop"], ["repair", "Repair"], ["sell", "Sell"], ["desel", "✕"]]:
		var k: String = pair[0]
		var b := mkbtn(pair[1], func(): main.cmd_btn(k)); cmd_row.add_child(b); btn[k] = b; b.visible = false
	set_on(btn.sw, true)
	selinfo = lbl("", f_body, 12, C_DIM); cmd_row.add_child(selinfo)
	mode_btn = Button.new(); mode_btn.focus_mode = Control.FOCUS_NONE; mode_btn.custom_minimum_size = Vector2(84, 84)
	mode_btn.anchor_left = 1; mode_btn.anchor_right = 1; mode_btn.anchor_top = 1; mode_btn.anchor_bottom = 1
	mode_btn.offset_left = -94; mode_btn.offset_right = -10; mode_btn.offset_top = -94; mode_btn.offset_bottom = -10
	var mv := VBoxContainer.new(); mv.set_anchors_preset(Control.PRESET_FULL_RECT); mv.alignment = BoxContainer.ALIGNMENT_CENTER; mv.mouse_filter = Control.MOUSE_FILTER_IGNORE; mv.add_theme_constant_override("separation", 2)
	var m1 := lbl("MOVE", f_disp7, 15); m1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; mv.add_child(m1)
	var m2 := lbl("tap for Select", f_body, 9, C_DIM); m2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; mv.add_child(m2)
	mode_btn.add_child(mv); mode_btn.set_meta("l1", m1); mode_btn.set_meta("l2", m2)
	mode_btn.pressed.connect(func(): main.toggle_mode())
	hud.add_child(mode_btn)
	cmd_row.offset_right = -100
	place_bar = HBoxContainer.new(); place_bar.add_theme_constant_override("separation", 8)
	place_bar.anchor_left = 0.5; place_bar.anchor_right = 0.5; place_bar.anchor_top = 1; place_bar.anchor_bottom = 1
	place_bar.offset_top = -52; place_bar.offset_bottom = -8; place_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var hb := PanelContainer.new(); place_hint = lbl("Drag to position · tap it to build", f_body, 12); hb.add_child(place_hint); place_bar.add_child(hb)
	var bp := mkbtn("Build here", func(): main.confirm_place()); set_on(bp, true); place_bar.add_child(bp)
	place_bar.add_child(mkbtn("Cancel", func(): main.end_placing()))
	place_bar.visible = false; hud.add_child(place_bar)
	update_mode(false)

func _pill(par: Control, title: String) -> PanelContainer:
	var p := PanelContainer.new(); p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 1); v.mouse_filter = Control.MOUSE_FILTER_IGNORE; p.add_child(v)
	v.add_child(lbl(title, f_disp6, 10, C_DIM))
	par.add_child(p)
	return p

func _left_bar(c: Color) -> StyleBoxFlat:
	var s := sb(Color(0.047, 0.063, 0.075, 0.86), C_LINE)
	s.border_width_left = 3; s.border_color = C_LINE
	var s2 := s.duplicate(); s2.border_color = c; s2.border_width_top = 0; s2.border_width_right = 0; s2.border_width_bottom = 0
	return s2

func update_mode(box: bool) -> void:
	mode_btn.tooltip_text = "drag to box units" if box else "tap for Select"
	var s := sb(Color("3a1512") if box else Color(0.08, 0.1, 0.12, 0.92), C_ACC if box else Color("3b4a54"), 2, 42)
	mode_btn.add_theme_stylebox_override("normal", s); mode_btn.add_theme_stylebox_override("hover", s); mode_btn.add_theme_stylebox_override("pressed", s)
	mode_btn.text = ""
	mode_btn.get_meta("l1").text = "SELECT" if box else "MOVE"
	mode_btn.get_meta("l2").text = "drag to box units" if box else "tap for Select"
	mode_btn.get_meta("l1").add_theme_color_override("font_color", Color("ffd0cc") if box else C_FG)

func toast(msg: String, kind := "") -> void:
	toast_l.text = msg.to_upper()
	var c := C_ACC
	if kind == "warn": c = C_BAD
	elif kind == "gold": c = C_AUR
	toast_box.add_theme_stylebox_override("panel", _left_bar(c))
	toast_l.add_theme_color_override("font_color", Color("ffd2cf") if kind == "warn" else C_FG)
	toast_box.visible = true; toast_t = 2.4
	toast_box.reset_size()
	toast_box.offset_left = -toast_box.size.x / 2; toast_box.offset_right = toast_box.size.x / 2

# ---------------- side panel ----------------
func _build_panel() -> void:
	panel = PanelContainer.new(); panel.add_theme_stylebox_override("panel", sb(C_PANEL, C_LINE, 0, 0, 8))
	panel.anchor_left = 1; panel.anchor_right = 1; panel.anchor_bottom = 1; panel.offset_left = -PANEL_W
	add_child(panel)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 8); panel.add_child(v)
	mini = MiniMap.new(); mini.ui = self; mini.custom_minimum_size = Vector2(PANEL_W - 16, PANEL_W - 16); v.add_child(mini)
	var tb := HBoxContainer.new(); tb.add_theme_constant_override("separation", 4); v.add_child(tb)
	for c in ["bld", "inf", "veh", "air"]:
		var b := Button.new(); b.text = {"bld": "BASE", "inf": "INF", "veh": "VEH", "air": "AIR"}[c]; b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", f_disp); b.add_theme_font_size_override("font_size", 11)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL; b.custom_minimum_size.y = 34
		b.pressed.connect(func(): main.select_tab(c))
		var dot := ColorRect.new(); dot.color = C_ACC; dot.size = Vector2(6, 6); dot.position = Vector2(3, 3); dot.visible = false; dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(dot); b.set_meta("dot", dot)
		tb.add_child(b); tabs[c] = b
	grid_scroll = ScrollContainer.new(); grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(grid_scroll)
	grid = GridContainer.new(); grid.columns = 2; grid.add_theme_constant_override("h_separation", 6); grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_scroll.add_child(grid)
	for cat in D.CAT_ORDER:
		for type in D.CATS[cat]:
			var it := BuildItem.new(); it.ui = self; it.cat = cat; it.type = type
			it.custom_minimum_size = Vector2((PANEL_W - 16 - 6) / 2.0, 78)
			grid.add_child(it); items[cat + ":" + type] = it

func set_tab(cat: String) -> void:
	for c in tabs:
		var on: bool = c == cat
		tabs[c].add_theme_stylebox_override("normal", sb(Color("2e1513") if on else C_PANEL2, C_ACC if on else C_LINE))
		tabs[c].add_theme_color_override("font_color", C_FG if on else C_DIM)

# ---------------- overlays ----------------
func _overlay(nm: String, maxw: float) -> VBoxContainer:
	var o := Control.new(); o.name = nm; o.set_anchors_preset(Control.PRESET_FULL_RECT); o.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := OverlayBG.new(); bg.set_anchors_preset(Control.PRESET_FULL_RECT); bg.mouse_filter = Control.MOUSE_FILTER_IGNORE; o.add_child(bg)
	var sc := ScrollContainer.new(); sc.set_anchors_preset(Control.PRESET_FULL_RECT); sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; o.add_child(sc)
	var cc := CenterContainer.new(); cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL; cc.size_flags_vertical = Control.SIZE_EXPAND_FILL; sc.add_child(cc)
	var mc := MarginContainer.new(); for s in ["left", "right", "top", "bottom"]: mc.add_theme_constant_override("margin_" + s, 16)
	cc.add_child(mc)
	var card := VBoxContainer.new(); card.add_theme_constant_override("separation", 14); card.custom_minimum_size.x = maxw
	mc.add_child(card)
	add_child(o); overlays[nm] = o; o.visible = false
	o.set_meta("card", card)
	return card

func eyebrow(t: String) -> Label:
	var l := lbl(t.to_upper(), f_disp, 11, C_ACC); return l

func title(t: String, size := 64) -> Label:
	return lbl(t.to_upper(), f_disp7, size)

func cta(t: String, cb: Callable) -> Button:
	var b := mkbtn(t, cb, 0, 54, 17)
	var s := sb(C_ACC, C_ACC, 0)
	b.add_theme_stylebox_override("normal", s); b.add_theme_stylebox_override("hover", sb(C_ACC.lightened(0.08), C_ACC, 0)); b.add_theme_stylebox_override("pressed", s)
	b.add_theme_color_override("font_color", Color.WHITE); b.add_theme_font_override("font", f_disp7)
	return b

func ghost(t: String, cb: Callable) -> Button:
	var b := mkbtn(t, cb, 0, 46, 13)
	b.add_theme_stylebox_override("normal", sb(C_PANEL2, C_LINE))
	return b

func seg(par: Control, group: String, opts: Array, cur: String, cb: Callable) -> HBoxContainer:
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 6); par.add_child(h)
	seg_btns[group] = {}
	for o in opts:
		var b := Button.new(); b.focus_mode = Control.FOCUS_NONE; b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(90, 46)
		var v := VBoxContainer.new(); v.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.set_anchors_preset(Control.PRESET_FULL_RECT); v.alignment = BoxContainer.ALIGNMENT_CENTER
		var l := lbl(o[1].to_upper(), f_disp, 13); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(l)
		if o.size() > 2:
			var s := lbl(o[2], f_body, 11, C_DIM); s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(s)
			b.custom_minimum_size.y = 78
		b.add_child(v)
		b.pressed.connect(func(): _seg_pick(group, o[0]); cb.call(o[0]))
		h.add_child(b); seg_btns[group][o[0]] = b
	_seg_pick(group, cur)
	return h

func _seg_pick(group: String, val: String) -> void:
	for k in seg_btns[group]:
		var on: bool = k == val
		seg_btns[group][k].add_theme_stylebox_override("normal", sb(Color("2e1513") if on else C_PANEL2, C_ACC if on else C_LINE))
		seg_btns[group][k].add_theme_stylebox_override("hover", sb(Color("2e1513") if on else C_PANEL2, C_ACC if on else Color("3b4a54")))

func _build_overlays() -> void:
	# start
	var c := _overlay("start", 620)
	c.add_child(eyebrow("Vanguard vs Ashen Pact · 3D"))
	var tl := VBoxContainer.new(); tl.add_theme_constant_override("separation", -14)
	tl.add_child(title("Aurite", 72)); tl.add_child(lbl("FRONT", f_disp7, 72, C_ACC)); c.add_child(tl)
	var lede := lbl("Two factions fight over the aurite fields of the Sable valley. Lead the Vanguard through the campaign, or pick a side in a skirmish.", f_body, 16, Color("c9d3d8"))
	lede.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; c.add_child(lede)
	seg(c, "mode", [["campaign", "Campaign"], ["skirmish", "Skirmish"]], "campaign", func(m): start_mode = m; camp_pane.visible = m == "campaign"; sk_pane.visible = m == "skirmish")
	camp_pane = VBoxContainer.new(); camp_pane.add_theme_constant_override("separation", 6); c.add_child(camp_pane)
	sk_pane = VBoxContainer.new(); sk_pane.add_theme_constant_override("separation", 12); sk_pane.visible = false; c.add_child(sk_pane)
	sk_pane.add_child(lbl("FACTION", f_disp, 11, C_DIM))
	seg(sk_pane, "fac", [["vanguard", "Vanguard", "Heavy armor, Rangers, Skyhawk gunships, Bastion cannons, Skyfall missiles"], ["ashen", "Ashen Pact", "Fast raiders, Pyros, Wasp drones, Arc weapons, the Rift Engine"]], "vanguard", func(f): main.sk_fac = f)
	sk_pane.add_child(lbl("DIFFICULTY", f_disp, 11, C_DIM))
	seg(sk_pane, "diff", [["easy", "Easy"], ["normal", "Normal"], ["hard", "Hard"]], "normal", func(d): main.diff = d)
	sk_pane.add_child(cta("Deploy", func(): main.play({"fac": main.sk_fac, "diff": main.diff})))
	var ctl := lbl("Touch: drag to scroll · tap a unit to select, tap ground or an enemy to order · tap the round button, then drag a box · pinch to zoom · double-tap a unit to grab every unit of that type on screen · hold, then drag at the destination to face a formation · long-press a build button to cancel.\nMouse: click to select or command, drag to box-select, double-click a unit for all of its type, right-drag to face a formation, middle-drag or WASD to scroll, wheel to zoom.", f_body, 13, Color("cfd8dc"))
	ctl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; c.add_child(ctl)
	# menu
	c = _overlay("menu", 380)
	c.add_child(eyebrow("Paused"))
	c.add_child(cta("Resume", func(): main.resume()))
	btn.sound = ghost("Sound: on", func(): main.toggle_sound()); c.add_child(btn.sound)
	btn.music = ghost("Music: on", func(): main.toggle_music()); c.add_child(btn.music)
	c.add_child(ghost("Restart", func(): main.restart()))
	c.add_child(ghost("Main menu", func(): main.quit_to_menu()))
	# end
	c = _overlay("end", 480)
	btn.end_eye = eyebrow("Operation complete"); c.add_child(btn.end_eye)
	btn.end_title = title("Victory", 64); c.add_child(btn.end_title)
	btn.end_stats = GridContainer.new(); btn.end_stats.columns = 3; btn.end_stats.add_theme_constant_override("h_separation", 8); btn.end_stats.add_theme_constant_override("v_separation", 8); c.add_child(btn.end_stats)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8); c.add_child(row)
	btn.next = cta("Next mission", func(): main.next_mission()); btn.next.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(btn.next)
	btn.again = cta("Play again", func(): main.play(main.last_opt)); btn.again.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(btn.again)
	var em := ghost("Main menu", func(): main.show_start()); em.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(em)
	# brief
	c = _overlay("brief", 560)
	btn.br_eye = eyebrow("Mission 1"); c.add_child(btn.br_eye)
	btn.br_title = title("Landfall", 56); c.add_child(btn.br_title)
	btn.br_text = lbl("", f_body, 16, Color("c9d3d8")); btn.br_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; c.add_child(btn.br_text)
	var ob := PanelContainer.new(); ob.add_theme_stylebox_override("panel", _left_bar(C_AUR)); c.add_child(ob)
	var obv := VBoxContainer.new(); ob.add_child(obv); obv.add_child(lbl("OBJECTIVES", f_disp, 11, C_AUR))
	btn.br_obj = lbl("", f_body, 14); btn.br_obj.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; obv.add_child(btn.br_obj)
	row = HBoxContainer.new(); row.add_theme_constant_override("separation", 8); c.add_child(row)
	var go := cta("Begin mission", func(): main.begin_mission()); go.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(go)
	var bk := ghost("Back", func(): main.show_start()); bk.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(bk)

func show_overlay(nm: String) -> void:
	for k in overlays: overlays[k].visible = k == nm

func render_missions(done: int) -> void:
	for ch in camp_pane.get_children(): ch.queue_free()
	for i in D.MISSIONS.size():
		var m: Dictionary = D.MISSIONS[i]
		var b := Button.new(); b.focus_mode = Control.FOCUS_NONE; b.custom_minimum_size = Vector2(0, 58); b.disabled = i > done
		b.add_theme_stylebox_override("normal", sb(C_PANEL2, C_LINE)); b.add_theme_stylebox_override("disabled", sb(Color(C_PANEL2, 0.4), Color(C_LINE, 0.4)))
		var h := HBoxContainer.new(); h.set_anchors_preset(Control.PRESET_FULL_RECT); h.offset_left = 12; h.offset_right = -12; h.add_theme_constant_override("separation", 10); h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var n := lbl(str(i + 1), f_disp7, 22, C_ACC); n.custom_minimum_size.x = 30; n.size_flags_vertical = Control.SIZE_SHRINK_CENTER; h.add_child(n)
		var v := VBoxContainer.new(); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; v.alignment = BoxContainer.ALIGNMENT_CENTER; v.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.add_theme_constant_override("separation", 0)
		v.add_child(lbl(m.title.to_upper(), f_disp, 15)); v.add_child(lbl(m.tag, f_body, 12, C_DIM)); h.add_child(v)
		var st := lbl("WON" if i < done else ("NEXT" if i == done else "LOCKED"), f_disp, 10, C_OK if i < done else (C_AUR if i == done else C_DIM)); st.size_flags_vertical = Control.SIZE_SHRINK_CENTER; h.add_child(st)
		if i > done: h.modulate.a = 0.4
		b.add_child(h)
		b.pressed.connect(func(): main.open_brief(i))
		camp_pane.add_child(b)

func set_end_stats(rows: Array) -> void:
	for ch in btn.end_stats.get_children(): ch.queue_free()
	for r in rows:
		var p := PanelContainer.new(); p.add_theme_stylebox_override("panel", sb(Color(0.08, 0.1, 0.12, 0.7), C_LINE)); p.custom_minimum_size.x = 140
		var v := VBoxContainer.new(); p.add_child(v)
		v.add_child(lbl(r[0].to_upper(), f_disp, 10, C_DIM)); v.add_child(lbl(str(r[1]), f_disp, 22))
		btn.end_stats.add_child(p)

func tick(dt: float) -> void:
	if toast_t > 0:
		toast_t -= dt
		if toast_t <= 0: toast_box.visible = false
	hud.get_meta("draw").queue_redraw()

# ---------------- custom controls ----------------
class OverlayBG extends Control:
	func _draw() -> void:
		var s := size
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.03, 0.04, 0.94))
		# warm glow toward the top left
		for i in 10:
			var r: float = (1.0 - i / 10.0) * max(s.x, s.y) * 0.7
			draw_circle(s * Vector2(0.3, 0.2), r, Color(0.24, 0.055, 0.047, 0.06))

class HudDraw extends Control:
	var ui
	func _draw() -> void:
		if ui.main: ui.main.draw_hud(self)

class MiniMap extends Control:
	var ui
	var tex: ImageTexture
	var img: Image
	var dragging := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		tex = ImageTexture.create_from_image(img)
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
		draw_texture_rect(tex, Rect2(Vector2.ZERO, size), false)
		draw_rect(Rect2(Vector2.ZERO, size), UI.C_LINE, false, 1.0)
		if ui.main: ui.main.draw_mini_overlay(self)
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
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
	func _process(dt: float) -> void:
		if lp_t >= 0:
			lp_t += dt
			if lp_t > 0.55 and not did:
				did = true; ui.main.cancel_item(cat, type)
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			if ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
				ui.main.cancel_item(cat, type); accept_event(); return
			if ev.button_index != MOUSE_BUTTON_LEFT: return
			if ev.pressed:
				lp_t = 0.0; did = false
			else:
				if lp_t >= 0 and not did and Rect2(Vector2.ZERO, size).has_point(ev.position): ui.main.click_item(cat, type)
				lp_t = -1.0
		elif ev is InputEventMouseMotion and lp_t >= 0 and ev.relative.length() > 6:
			lp_t = -1.0  # it's a scroll, not a press
	func _draw() -> void:
		var d: Dictionary = D.def_of(type)
		var a := 0.32 if locked else 1.0
		draw_style_box(UI.sb(UI.C_PANEL2, UI.C_LINE), Rect2(Vector2.ZERO, size))
		var iw := 56.0; var ih := 44.0; var ir := Rect2((size.x - iw) / 2, 4, iw, ih)
		draw_rect(ir, Color("10161a", a))
		if icon: draw_texture_rect(icon, ir, false, Color(1, 1, 1, a))
		var nm: String = d.name
		var f: Font = ui.f_body
		var tw := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var fs := 11 if tw <= size.x - 4 else 10
		draw_string(f, Vector2(2, 60), nm, HORIZONTAL_ALIGNMENT_CENTER, size.x - 4, fs, Color(UI.C_FG, a))
		var cost := str(d.cost) + (" · locked" if locked else "")
		draw_string(ui.f_disp, Vector2(2, 73), cost, HORIZONTAL_ALIGNMENT_CENTER, size.x - 4, 11, Color(UI.C_AUR, a) if not locked else Color(UI.C_DIM, a))
		if active and not is_ready:
			draw_style_box(UI.sb(Color(0, 0, 0, 0), UI.C_AUR), Rect2(Vector2.ZERO, size))
			# darken the part still to build, clockwise from the top
			var c := size / 2; var r := size.length() / 2
			var pts := PackedVector2Array([c])
			var steps := 32
			for i in range(int(prog * steps), steps + 1):
				var ang: float = -PI / 2 + TAU * max(prog, float(i) / steps)
				pts.append(c + Vector2(cos(ang), sin(ang)) * r)
			if pts.size() > 2:
				var clip := Rect2(Vector2.ZERO, size)
				var cp := PackedVector2Array()
				for p in pts: cp.append(Vector2(clamp(p.x, clip.position.x, clip.end.x), clamp(p.y, clip.position.y, clip.end.y)))
				draw_colored_polygon(cp, Color(0, 0, 0, 0.62))
		if n > 1: draw_string(ui.f_disp7, Vector2(size.x - 18, 15), str(n), HORIZONTAL_ALIGNMENT_RIGHT, 14, 12, Color.WHITE)
		if is_ready and int(Time.get_ticks_msec() / 500) % 2 == 0:
			draw_rect(Rect2(0, 18, size.x, 18), UI.C_ACC)
			draw_string(ui.f_disp7, Vector2(0, 32), "READY", HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, Color.WHITE)
