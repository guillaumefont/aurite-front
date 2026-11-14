extends Node
## Game shell: owns the simulation, the 3D view, the UI and audio; handles input and game flow.

const T := 32
const Cutscenes := preload("res://scripts/cutscenes.gd")  # no class_name: an installed shell would not know a new global class
const CutscenePlayer := preload("res://scripts/cutscene.gd")

var S: Sim
var V: View3D
var U: UI
var A: GameAudio
var paused := true
var placing = null  # {type, tx, ty, ldx, ldy}
var amove := false
var box_mode := false
var sw_aim := false
var diff := "normal"
var sk_fac := "vanguard"
var sk_enemy := "random"
var last_opt := {"fac": "vanguard"}
var cur_tab := "bld"
var brief_i := 0
var camp_id := "ashen"
var icons_for := ""
var headless := false
var cut: CutscenePlayer
## Fingers that drag the map. 1 (Guillaume's pick after trying both, 2026-11-14): one-finger drag pans,
## hold then drag draws a selection box (or faces a formation). 2: two-finger drag pans and a plain
## one-finger drag draws the box.
const PAN_FINGERS := 1

# input state
var ptrs := {}
var gest = null
var keys := {}
var last_tap := {"id": 0, "t": 0}
var shown_cr := 0.0
var panel_t := 0.0
var mini_t := 0.0
var preview_slots: Array = []
var pv_from = null
var pv_to = null
var squad_key := ""   # squad button that made the current selection (lit until the selection changes)
var squad_set: Array = []
var groups := [[], [], [], []]   # army groups: unit ids per chip on the left edge
var obj_t := 0.0                 # seconds the objective box stays open
var obj_gi := -1
const OBJ_SHOW := 8.0
const GHOST_LIFT := 70.0         # a building dragged from the menu shows this far above the finger

func _ready() -> void:
	headless = DisplayServer.get_name() == "headless"
	randomize()
	S = Sim.new(); S.host = self
	V = View3D.new(); V.S = S; add_child(V)
	var layer := CanvasLayer.new(); add_child(layer)
	U = UI.new(); U.main = self; layer.add_child(U); U.build()
	A = GameAudio.new(); add_child(A)
	cut = CutscenePlayer.new(); cut.main = self; layer.add_child(cut); cut.build(U, V)
	U.set_tab("bld")
	U.set_panel(_load_prefs().get("panel", true))
	V.panel_px = U.panel_px()
	U.mode_btn.visible = false  # box selection is a hold-and-drag (or a plain drag with PAN_FINGERS 2)
	show_start()
	if not headless: render_icons("vanguard")
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()
	if OS.get_environment("AF_SHOT") != "": _autotest(OS.get_environment("AF_SHOT"))

## Phone screens are dense: the 600-unit-tall UI would be only ~3 inches high and its text tiny.
## Scale the canvas so the UI keeps a readable physical size (about 180 UI units per inch), never
## smaller than the desktop layout. AF_DPI overrides the screen DPI for tests.
func _on_resize() -> void:
	var win := get_window()
	var dpi := float(OS.get_environment("AF_DPI")) if OS.get_environment("AF_DPI") != "" else float(DisplayServer.screen_get_dpi())
	var f := 1.0
	if dpi > 0 and (OS.has_feature("mobile") or OS.get_environment("AF_DPI") != ""):
		var h_in := float(min(win.size.x, win.size.y)) / dpi
		f = clampf(600.0 / (h_in * 180.0), 1.0, 1.5)
	if abs(win.content_scale_factor - f) > 0.01:
		win.content_scale_factor = f
	_apply_safe()

## Keep buttons and text clear of rounded screen corners and of a camera hole or notch.
## Uses the display's safe area (it flips sides when the phone turns round), never less than a
## corner margin on phones. AF_SAFE="left,top,right,bottom" (window pixels) simulates a cutout.
var safe_last := Rect2()
var safe_t := 0.0
func _apply_safe() -> void:
	var win := get_window()
	var k := V.ui_scale()
	if k <= 0: return
	var l := 0.0; var t := 0.0; var r := 0.0; var b := 0.0
	var phone := OS.has_feature("mobile") or OS.get_environment("AF_DPI") != ""
	if OS.get_environment("AF_SAFE") != "":
		var a := OS.get_environment("AF_SAFE").split(",")
		l = float(a[0]); t = float(a[1]); r = float(a[2]); b = float(a[3])
	elif OS.has_feature("mobile"):
		var sa := DisplayServer.get_display_safe_area()
		var wr := Rect2i(win.position, win.size)
		l = sa.position.x - wr.position.x; t = sa.position.y - wr.position.y
		r = wr.end.x - sa.end.x; b = wr.end.y - sa.end.y
	var ins := Rect2(maxf(l, 0) / k, maxf(t, 0) / k, maxf(r, 0) / k, maxf(b, 0) / k)
	if phone:  # rounded corners: a little room on every side, more on the short sides
		ins = Rect2(maxf(ins.position.x, 24), maxf(ins.position.y, 8), maxf(ins.size.x, 24), maxf(ins.size.y, 8))
	if ins == safe_last: return
	safe_last = ins
	U.set_insets(ins.position.x, ins.position.y, ins.size.x, ins.size.y)
	V.panel_px = U.panel_px()

## Hide or show the side panel (build menu and minimap) to free the screen; remembered between games.
func toggle_panel() -> void:
	var anchor := Vector2(100, V.view_rect().size.y / 2); var w := V.s2w(anchor.x, anchor.y)
	U.set_panel(not U.panel_open); V.panel_px = U.panel_px(); sfx("click")
	var w2 := V.s2w(anchor.x, anchor.y)  # keep the map still on screen while the view widens
	V.cam_x += w.x - w2.x; V.cam_y += w.y - w2.y; V.clamp_cam()
	var p := _load_prefs(); p.panel = U.panel_open; _save_prefs(p)
	if U.panel_open: refresh_panel(true)
	else: _panel_alert()

func _load_prefs() -> Dictionary:
	if not FileAccess.file_exists("user://prefs.json"): return {}
	var f := FileAccess.open("user://prefs.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f else null
	return d if d is Dictionary else {}

func _save_prefs(p: Dictionary) -> void:
	var f := FileAccess.open("user://prefs.json", FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(p))

## While the panel is hidden, the top bar shows each production line that is busy.
func _prod_chips(tm: Dictionary) -> void:
	for cat in U.prod_chips:
		var pc = U.prod_chips[cat]; var q: Dictionary = tm.prod[cat]
		var busy: bool = q.cur != "" or q.queue.size() > 0
		pc.visible = not U.panel_open and busy
		if not pc.visible: continue
		pc.type = q.cur if q.cur != "" else q.queue[0]
		pc.prog = q.prog; pc.is_ready = cat == "bld" and q.ready
		pc.n = q.queue.size() + (1 if q.cur != "" else 0) if cat != "bld" else 1
		pc.queue_redraw()

func prod_chip_tap(cat: String) -> void:
	var q: Dictionary = S.teams[0].prod[cat]
	if cat == "bld" and q.ready: start_placing(q.cur); sfx("click"); return
	if not U.panel_open: toggle_panel()
	select_tab(cat)

## Hold a unit button: queue five of it.
func queue_many(cat: String, type: String, k: int) -> void:
	var q: Dictionary = S.teams[0].prod[cat]
	for i in k:
		var before: int = q.queue.size()
		click_item(cat, type)
		if q.queue.size() == before: break
	buzz(20)

# ---------------- objective ----------------
func _obj_vis() -> void:
	var m: bool = S.mission != null and not S.teams.is_empty()
	U.obj_box.visible = m and obj_t > 0
	U.obj_btn.visible = m and obj_t <= 0

func show_objective() -> void:
	obj_t = OBJ_SHOW; _obj_vis(); sfx("click")

func hide_objective() -> void:
	obj_t = 0; _obj_vis()

# ---------------- army groups ----------------
func _group_units(i: int) -> Array:
	return S.ents.filter(func(e): return e.alive and e.kind == "u" and e.team == 0 and not e.captive and groups[i].has(e.id))

## Tap: select the group; tap again (already selected): centre the camera on it.
## Hold (or tap an empty group with units selected): store the selected units in it.
func group_btn(i: int, hold: bool) -> void:
	if S.teams.is_empty(): return
	var units := _group_units(i)
	var sel_u: Array = S.sel.filter(func(e): return e.kind == "u")
	if hold or units.is_empty():
		if sel_u.size():
			groups[i] = sel_u.map(func(e): return e.id)
			toast("Group %d · %d units" % [i + 1, sel_u.size()]); buzz(25); sfx("click")
		elif hold:
			groups[i] = []; toast("Group %d cleared" % (i + 1))
		else: toast("Select units, then hold %d to store them" % (i + 1))
		_group_chips(); return
	var ids := units.map(func(e): return e.id); ids.sort()
	var cur := sel_u.map(func(e): return e.id); cur.sort()
	if ids == cur:
		var c := Vector2()
		for e in units: c += Vector2(e.x, e.y)
		c /= units.size(); V.center_on(c.x, c.y)
	else:
		S.set_sel(units); sfx("click"); buzz(10)

func _group_chips() -> void:
	for i in 4:
		var n := _group_units(i).size(); var b = U.btn["grp%d" % i]
		if b.n != n: b.n = n; b.queue_redraw()

## A short vibration on phones to confirm an order or a selection.
func buzz(ms: int) -> void:
	if OS.has_feature("mobile"): Input.vibrate_handheld(ms)

# ---------------- enlarged minimap ----------------
func toggle_big_map() -> void:
	U.big_map.visible = not U.big_map.visible
	U.set_on(U.btn.map, U.big_map.visible); sfx("click")

## While the panel is hidden its button lights up when a building is ready to place.
func _panel_alert() -> void:
	var ready: bool = not U.panel_open and S.teams.size() > 0 and S.teams[0].prod.bld.ready
	U.set_on(U.btn.panel, ready)
	if not U.panel_open:
		var t := "READY" if ready else "BUILD"
		if U.btn.panel.text != t: U.btn.panel.text = t; U.restyle(U.btn.panel)

# ---------------- host interface for the simulation ----------------
func toast(msg: String, kind := "") -> void:
	U.toast(msg, kind)

func sfx(n: String, x = null, y = null) -> void:
	if S == null or paused and n != "click": return
	var big := n == "bigboom" or n == "siren" or n == "alert" or n == "ready"
	var pan := 0.0; var vol := 1.0
	if x != null:
		var p := V.w2s(x, y, S.h_at(x, y))
		var r := V.view_rect()
		var on := p.z > 0 and r.grow(40).has_point(Vector2(p.x, p.y))
		if not on and not big: return
		pan = (p.x / r.size.x * 2 - 1) * .8
		vol = max(.35, 1 - Vector2(p.x / r.size.x - .5, p.y / r.size.y - .5).length() * .9)
		if not on: vol = .4
	if n == "ack" and S.teams.size() and S.teams[0].fac != "vanguard": n = "ack_" + S.teams[0].fac
	A.play(n, pan, vol)

func on_world_changed() -> void:
	V.refresh_decor()

func on_sel_changed() -> void:
	if squad_key != "" and S.sel != squad_set: squad_key = ""
	update_cmd()

func on_vision() -> void:
	V.upd_fog()

func add_scorch(x: float, y: float, r: float) -> void:
	V.add_scorch(x, y, r)

func end_game(win: bool) -> void:
	var M = S.mission
	var en: String = D.FACS[S.teams[1].fac].name; var me: String = D.FACS[S.teams[0].fac].name
	U.btn.end_eye.text = (("Mission %d · %s %s" % [M.idx + 1, M.title, "complete" if win else "failed"]) if M else (en + " eliminated" if win else me + " base lost")).to_upper()
	U.btn.end_title.text = "VICTORY" if win else "DEFEAT"
	U.set_end_result(win)
	U.btn.end_why.text = S.end_why if (M and not win) else ""
	U.btn.end_why.visible = U.btn.end_why.text != ""
	if M and win: camp_save(M.camp, M.idx)
	var last: bool = M != null and M.idx == D.camp(M.camp).missions.size() - 1
	var sequel := _sequel(M.camp) if M else ""
	U.btn.next.visible = M != null and win and (not last or sequel != "")
	U.btn.next.text = ("BEGIN " + D.camp(sequel).name.to_upper()) if (last and sequel != "") else "NEXT MISSION"
	if last and win and sequel != "": toast("Campaign complete. %s is unlocked" % D.camp(sequel).name, "gold")
	U.btn.again.text = ("REPLAY" if win else "RETRY") if M else "PLAY AGAIN"
	A.music_stop()
	U.set_end_stats([["Time", D.fmt(S.time)], ["Aurite mined", Sim._thousands(S.stats.mined)], ["Units trained", S.stats.built], ["Enemies destroyed", S.stats.killed], ["Losses", S.stats.lost]])
	get_tree().create_timer(1.2).timeout.connect(func(): U.show_overlay("end"))
	A.play("ready" if win else "alert")

# ---------------- game flow ----------------
## Progress per campaign: {"ashen": missions won, "vanguard": ...}. The old single-campaign save is ignored.
func _camp_file() -> Dictionary:
	if not FileAccess.file_exists("user://campaigns.json"): return {}
	var f := FileAccess.open("user://campaigns.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

func camp_prog(id: String) -> int:
	return int(_camp_file().get(id, 0))

func camp_save(id: String, i: int) -> void:
	var d := _camp_file()
	d[id] = max(int(d.get(id, 0)), i + 1)
	var f := FileAccess.open("user://campaigns.json", FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(d))

## The campaign that follows this one in the story, or "".
func _sequel(id: String) -> String:
	for i in D.CAMPAIGNS.size() - 1:
		if D.CAMPAIGNS[i].id == id: return D.CAMPAIGNS[i + 1].id
	return ""

## A campaign opens once the one before it is finished.
func camp_open(id: String) -> bool:
	for i in range(1, D.CAMPAIGNS.size()):
		if D.CAMPAIGNS[i].id == id:
			var prev: Dictionary = D.CAMPAIGNS[i - 1]
			return camp_open(prev.id) and camp_prog(prev.id) >= prev.missions.size()
	return true

## Opens the campaign screen scrolled to this campaign.
func pick_campaign(id: String) -> void:
	camp_id = id
	show_campaigns()

func _camp_rows() -> Array:
	return D.CAMPAIGNS.map(func(C): return {"C": C, "open": camp_open(C.id), "done": camp_prog(C.id)})

func show_start() -> void:
	if not camp_open(camp_id): camp_id = D.CAMPAIGNS[0].id
	# continue where the player is: the furthest open campaign that is not finished
	var cur: Dictionary = D.CAMPAIGNS[0]
	for C in D.CAMPAIGNS:
		if camp_open(C.id): cur = C
		if camp_open(C.id) and camp_prog(C.id) < C.missions.size(): cur = C; break
	var dn := mini(camp_prog(cur.id), cur.missions.size())
	var nxt: String = ("Next: " + cur.missions[dn].title) if dn < cur.missions.size() else "All won: replay any mission"
	U.set_camp_tile(nxt, "%s · %s  ·  %d of %d secured" % [cur.num, cur.name, dn, cur.missions.size()])
	U.show_overlay("start")
	paused = true
	A.music_stop()

func show_campaigns() -> void:
	if not camp_open(camp_id): camp_id = D.CAMPAIGNS[0].id
	U.render_campaigns(_camp_rows(), camp_id)
	U.show_overlay("campaign")

func open_brief(i: int) -> void:
	brief_i = i
	var C := D.camp(camp_id)
	var m: Dictionary = C.missions[i]
	U.btn.br_eye.text = ("%s  //  Mission %d of %d" % [C.name, i + 1, C.missions.size()]).to_upper()
	U.btn.br_title.text = m.title.to_upper()
	U.btn.br_theatre.text = (m.theatre + "  ·  " + D.THEMES[m.map.theme].name).to_upper()
	U.btn.br_text.text = m.brief
	U.set_brief_heroes(m.heroes, C.fac)
	U.btn.br_obj.text = "\n".join(m.obj.map(func(o): return "•  " + o))
	U._seg_pick("level", camp_level())
	U.show_overlay("brief")

## Begin on the briefing: the campaign's opening the first time its first mission starts, then the mission's own intro.
func begin_mission() -> void:
	var opt := {"mission": D.camp(camp_id).missions[brief_i], "level": camp_level()}
	var reel: Array = []
	var op := Cutscenes.opening_of(camp_id)
	if brief_i == 0 and Cutscenes.has(op) and not cine_seen(op): reel.append(op)
	if Cutscenes.has(Cutscenes.intro_of(camp_id, brief_i)): reel.append(Cutscenes.intro_of(camp_id, brief_i))
	play_reel(reel, func(): play(opt))

# ---------------- cutscenes ----------------
func cine_seen(id: String) -> bool:
	return (_camp_file().get("_seen", []) as Array).has(id)

func _cine_mark(id: String) -> void:
	var d := _camp_file(); var seen: Array = d.get("_seen", [])
	if seen.has(id): return
	seen.append(id); d["_seen"] = seen
	var f := FileAccess.open("user://campaigns.json", FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(d))

## Plays scenes one after the other (Skip ends only the current one), then calls done.
func play_reel(ids: Array, done: Callable) -> void:
	if ids.is_empty() or headless: done.call(); return
	start_cutscene(ids[0], func(): play_reel(ids.slice(1), done))

## Builds the scene's map and cast on the sim and hands the timeline to the cutscene player.
func start_cutscene(id: String, done: Callable) -> void:
	_cine_mark(id)
	var sc := Cutscenes.scene(id)
	var M: Dictionary = D.camp(sc.camp).missions[sc.map]
	placing = null; amove = false; box_mode = false; sw_aim = false; gest = null; ptrs.clear()
	U.show_overlay(""); U.hud.visible = false; U.panel.visible = false
	S.new_game("normal", {"mission": M, "level": camp_level(), "cine": true, "bare": sc.get("bare", false)})
	V.build_world(); V.panel_px = 0.0
	S.update_vision()
	paused = false; A.set_paused(false)
	cut.start(sc, Cutscenes.setup(S, sc), func():
		U.hud.visible = true; U.panel.visible = U.panel_open; V.panel_px = U.panel_px()
		paused = true
		done.call())
	A.music_start()

## Replays a scene from the campaign screen, then comes back to it.
func watch_cutscene(id: String) -> void:
	start_cutscene(id, func(): A.music_stop(); show_campaigns())

## Campaign difficulty, kept with the campaign progress.
func camp_level() -> String:
	var l: String = str(_camp_file().get("_level", "normal"))
	return l if D.LEVELS.has(l) else "normal"

func set_camp_level(l: String) -> void:
	var d := _camp_file(); d["_level"] = l
	var f := FileAccess.open("user://campaigns.json", FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(d))

func next_mission() -> void:
	if brief_i >= D.camp(camp_id).missions.size() - 1 and _sequel(camp_id) != "":
		camp_id = _sequel(camp_id); open_brief(0); return
	open_brief(min(D.camp(camp_id).missions.size() - 1, brief_i + 1))

func play(opt: Dictionary) -> void:
	last_opt = opt
	U.show_overlay("")
	new_game(opt.get("diff", diff), opt)
	paused = false
	A.set_paused(false)

func new_game(d: String, opt: Dictionary) -> void:
	placing = null; amove = false; box_mode = false; sw_aim = false; gest = null; ptrs.clear()
	groups = [[], [], [], []]; obj_t = OBJ_SHOW; obj_gi = -1
	S.new_game(d, opt)
	diff = S.diff
	V.build_world()
	S.update_vision()
	V.cam_z = 1.0
	V.center_on(S.p0.x * T + 16, (S.p0.y - 1) * T)
	if icons_for != S.teams[0].fac and not headless: render_icons(S.teams[0].fac)
	select_tab("bld"); refresh_panel(true); update_cmd(); end_placing()
	_obj_vis()
	if S.mission: toast(S.mission.title, "gold")
	else:
		toast("Two fingers move the map · drag one finger to box-select" if PAN_FINGERS == 2 else "Drag to move the map · hold, then drag to box-select", "gold")
		get_tree().create_timer(3.5).timeout.connect(func(): if S.time < 20 and not S.over: toast("Build a Reactor, then a " + D.BLD[D.sub(S.teams[0].fac, "refinery")].name, "gold"))
	A.music_start()

func open_menu() -> void:
	if S.over: return
	paused = true; U.show_overlay("menu"); A.set_paused(true)

func resume() -> void:
	paused = false; U.show_overlay(""); A.set_paused(false)

func restart() -> void:
	play(last_opt)

func quit_to_menu() -> void:
	show_start()

func toggle_sound() -> void:
	A.muted = not A.muted; U.btn.sound.text = "SOUND: " + ("OFF" if A.muted else "ON")

func toggle_music() -> void:
	A.music_on = not A.music_on; U.btn.music.text = "MUSIC: " + ("ON" if A.music_on else "OFF")
	if A.music_on: A.music_start()
	else: A.music_stop()

func _notification(what: int) -> void:
	if cut and cut.active:
		if what == NOTIFICATION_WM_GO_BACK_REQUEST: cut.skip()
		return
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if U.overlays.menu.visible: resume()
		elif U.overlays.brief.visible: show_campaigns()
		elif U.overlays.manual.visible or U.overlays.campaign.visible or U.overlays.skirmish.visible: show_start()
		elif S.teams.size() and not S.over and not U.overlays.start.visible: open_menu()
		return
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if S and S.teams.size() and not S.over and not paused and U.overlays.menu and not U.overlays.start.visible: open_menu()

# ---------------- panel ----------------
func select_tab(cat: String) -> void:
	cur_tab = cat; U.set_tab(cat)
	for k in U.items:
		var it = U.items[k]
		it.visible = it.cat == cat and (S.teams.is_empty() or S.avail(0, it.type))
	U.grid_scroll.scroll_vertical = 0

func click_item(cat: String, type: String) -> void:
	if S.teams.is_empty() or S.over: return
	var tm: Dictionary = S.teams[0]; var q: Dictionary = tm.prod[cat]; var d: Dictionary = D.def_of(type)
	if not S.has_req(0, d.req):
		toast("Requires " + " + ".join(S.req_of(0, d.req).map(func(r): return D.BLD[r].name)), "warn"); return
	if S.at_limit(0, type):
		toast(d.name + " is already in the field", "warn"); return
	if cat == "bld":
		if q.ready and q.cur == type: start_placing(type); return
		if q.cur != "":
			toast("Already building" if q.cur == type else "Busy building " + D.BLD[q.cur].name); return
		q.cur = type; q.prog = 0.0; q.paid = 0.0; q.ready = false; sfx("click")
	else:
		if S.count(0, D.PRODUCER[cat]) == 0:
			toast("Requires " + D.BLD[D.PRODUCER[cat]].name, "warn"); return
		if q.queue.size() + (1 if q.cur != "" else 0) >= 9: return
		q.queue.append(type); sfx("click")
	refresh_panel(true)

func cancel_item(cat: String, type: String) -> void:
	if S.teams.is_empty(): return
	var tm: Dictionary = S.teams[0]; var q: Dictionary = tm.prod[cat]
	if cat == "bld":
		if q.cur == type:
			tm.credits += q.paid; q.cur = ""; q.prog = 0.0; q.paid = 0.0; q.ready = false
			if placing != null: end_placing()
			toast("Cancelled")
	else:
		var i: int = q.queue.rfind(type)
		if i >= 0: q.queue.remove_at(i)
		elif q.cur == type:
			tm.credits += q.paid; q.cur = ""; q.prog = 0.0; q.paid = 0.0
		toast("Cancelled")
	sfx("click"); refresh_panel(true)

func refresh_panel(_force := false) -> void:
	if S.teams.is_empty(): return
	var tm: Dictionary = S.teams[0]
	for k in U.items:
		var it = U.items[k]; var q: Dictionary = tm.prod[it.cat]; var d: Dictionary = D.def_of(it.type)
		var locked: bool = not S.has_req(0, d.req) or (it.cat != "bld" and S.count(0, D.PRODUCER[it.cat]) == 0) or (d.lim > 0 and S.count(0, it.type) >= d.lim)
		var n := 0; var prog := 0.0; var ready := false
		if it.cat == "bld":
			if q.cur == it.type: prog = q.prog; ready = q.ready
		else:
			n = q.queue.count(it.type) + (1 if q.cur == it.type else 0)
			if q.cur == it.type: prog = q.prog
		# active from the moment it is ordered, even before any aurite is paid (prog still 0)
		var active: bool = q.cur == it.type or (it.cat != "bld" and q.cur == "" and q.queue.size() > 0 and q.queue[0] == it.type)
		it.locked = locked; it.n = n; it.prog = prog; it.is_ready = ready; it.active = active
		if it.visible: it.queue_redraw()
	for c in U.tabs:
		var q: Dictionary = tm.prod[c]
		U.tabs[c].get_meta("dot").visible = q.cur != "" or q.queue.size() > 0
	var sw: Ent = null
	for e in S.ents:
		if e.alive and e.team == 0 and e.kind == "b" and e.d.sw: sw = e; break
	U.sw_box.visible = sw != null
	if sw:
		U.sw_name.text = sw.d.name.split(" ")[0].to_upper()
		U.sw_time.text = "READY" if sw.rdy else D.fmt(sw.d.charge - sw.ch)
	if S.mission: U.obj_l.text = S.obj_text()
	_obj_vis()
	_panel_alert()
	_prod_chips(tm)
	_group_chips()

func hud_tick(dt: float) -> void:
	var tm: Dictionary = S.teams[0]
	shown_cr += (tm.credits - shown_cr) * min(1.0, dt * 8)
	if abs(tm.credits - shown_cr) < 1: shown_cr = tm.credits
	U.credits_l.text = Sim._thousands(int(shown_cr))
	U.power_l.text = "%d / %d" % [tm.pmade, tm.pused]
	var lp := S.low_power(0)
	U.power_bar.set_val(min(1.0, float(tm.pused) / tm.pmade if tm.pmade else 1.0), lp)
	U.power_l.add_theme_color_override("font_color", UI.C_BAD if lp else UI.C_FG)
	if S.mission:
		if S.gi != obj_gi: obj_gi = S.gi; obj_t = OBJ_SHOW  # a new goal shows itself again
		if obj_t > 0:
			obj_t -= dt
			if obj_t <= 0: _obj_vis()
	panel_t -= dt
	if panel_t <= 0: panel_t = .12; refresh_panel(); _upg_btn()
	mini_t -= dt
	if mini_t <= 0: mini_t = .15; render_mini()

# ---------------- placement ----------------
func start_placing(type: String) -> void:
	var d: Dictionary = D.BLD[type]; var c := V.s2w(V.view_rect().size.x / 2, V.view_rect().size.y / 2)
	var q: Dictionary = S.teams[0].prod.bld
	if d.kit and not q.left: q.left = d.kit
	placing = {"type": type, "tx": int(round(c.x / T - d.w / 2.0)), "ty": int(round(c.y / T - d.h / 2.0)), "ldx": 0, "ldy": 0}
	var best = null; var bd := 1e9
	for y in range(placing.ty - 8, placing.ty + 9):
		for x in range(placing.tx - 8, placing.tx + 9):
			if S.can_place(0, type, x, y, false):
				var dd: float = (x - placing.tx) * (x - placing.tx) + (y - placing.ty) * (y - placing.ty)
				if dd < bd: bd = dd; best = Vector2i(x, y)
	if best != null: placing.tx = best.x; placing.ty = best.y
	U.place_bar.visible = true; U.cmd_row.visible = false; place_hint()

## Drag a ready building out of the menu: it follows the finger, drawn GHOST_LIFT above it so the
## finger does not hide it, and is built where it is let go (if the spot is allowed).
func drag_build_start(type: String, p: Vector2) -> void:
	if placing == null or placing.type != type: start_placing(type)
	drag_build_move(p)

func _ghost_at(p: Vector2, lift: float) -> void:
	var w := V.s2w(p.x, p.y - lift); var d: Dictionary = D.BLD[placing.type]
	placing.tx = int(round(w.x / T - d.w / 2.0)); placing.ty = int(round(w.y / T - d.h / 2.0))

func drag_build_move(p: Vector2) -> void:
	if placing == null or not _in_view(p): return
	_ghost_at(p, GHOST_LIFT)

func drag_build_end(p: Vector2) -> void:
	if placing == null: return
	if not _in_view(p): return  # let go over the menu: stay in placing mode
	_ghost_at(p, GHOST_LIFT)
	if S.can_place(0, placing.type, placing.tx, placing.ty, false): confirm_place()
	else: toast("Can't build there · drag it or tap Build here", "warn")

func place_hint() -> void:
	var q: Dictionary = S.teams[0].prod.bld
	U.place_hint.text = ("Barrier: %d left · tap it to build" % q.left) if (placing != null and D.BLD[placing.type].kit) else "Drag to position · tap it to build"
	U.place_bar.reset_size()
	U.place_bar.offset_left = -U.place_bar.size.x / 2; U.place_bar.offset_right = U.place_bar.size.x / 2

func end_placing() -> void:
	placing = null; U.place_bar.visible = false; U.cmd_row.visible = true

func confirm_place() -> void:
	if placing == null: return
	var q: Dictionary = S.teams[0].prod.bld
	if not S.can_place(0, placing.type, placing.tx, placing.ty, false):
		toast("Can't build there. Stay close to your base, off rock, water and aurite.", "warn"); return
	var b := S.add_building(0, placing.type, placing.tx, placing.ty)
	for k in 8: S.parts.append({"k": "smoke", "x": b.tx * T + randf() * b.w * T, "y": (b.ty + b.h) * T - 4, "vx": (randf() - .5) * 30, "vy": -randf() * 10, "life": .8, "max": .8, "s": 5.0, "c": Color8(150, 140, 120)})
	sfx("place")
	if D.BLD[placing.type].kit:
		q.left -= 1
		if q.left > 0:
			var px: int = placing.tx; var py: int = placing.ty; var best = null; var bd := 1e9
			for dxy in [[1, 0], [0, 1], [-1, 0], [0, -1], [1, 1], [-1, 1], [1, -1], [-1, -1], [2, 0], [0, 2]]:
				if S.can_place(0, "wall", px + dxy[0], py + dxy[1], false):
					var dd: float = dxy[0] * dxy[0] + dxy[1] * dxy[1] + (-1 if (placing.ldx == dxy[0] and placing.ldy == dxy[1]) else 0)
					if dd < bd: bd = dd; best = dxy
			if best != null:
				placing.tx = px + best[0]; placing.ty = py + best[1]; placing.ldx = best[0]; placing.ldy = best[1]
			place_hint(); refresh_panel(true); return
	q.cur = ""; q.ready = false; q.prog = 0.0; q.paid = 0.0; q.left = 0
	end_placing(); refresh_panel(true)

# ---------------- commands ----------------
func squad_btn(k: String) -> void:
	if S.teams.is_empty(): return
	var a := S.ents.filter(func(e): return e.alive and e.kind == "u" and e.team == 0 and not e.captive and e.intun <= 0 and not e.d.harv and not e.d.eng and (k == "all" or ((e.order == "none" and e.target == null) if k == "idle" else e.d.cat == k)))
	squad_key = k if a.size() else ""; squad_set = a
	S.set_sel(a)
	update_cmd()
	if a.size():
		sfx("click")
		var x := 0.0; var y := 0.0; var any_on := false
		for u in a:
			x += u.x; y += u.y
			if V.on_screen(u.x, u.y): any_on = true
		if k == "idle" or not any_on: V.center_on(x / a.size(), y / a.size())
	else: toast("No idle units" if k == "idle" else "No units of that kind")

func toggle_formation() -> void:
	S.formation = not S.formation; sfx("click"); update_cmd()
	toast("Formation moves on" if S.formation else "Formation off: units go straight to the spot")

func cmd_btn(k: String) -> void:
	match k:
		"sw":
			sw_aim = not sw_aim; sfx("click"); update_cmd()
		"amove":
			amove = not amove; update_cmd()
		"stop":
			for u in S.sel:
				if u.kind == "u":
					u.path = []; u.order = "none"; u.target = null; u.guard = Vector2(u.x, u.y); u.face = null
					if u.d.harv: u.hs = "idle"
		"desel": S.set_sel([])
		"upgrade":
			var b: Ent = S.sel[0] if S.sel.size() else null
			if b == null or b.kind != "b" or b.team != 0: return
			if b.upg >= 0:
				S.cancel_upgrade(b); toast("Upgrade cancelled, aurite refunded"); sfx("click")
			else:
				var why := S.upg_block(b)
				if why != "": toast(why, "warn"); return
				S.start_upgrade(b); sfx("place")
				toast("Upgrading to " + D.UPG[b.type].name + ": " + D.UPG[b.type].say)
			update_cmd()
		"repair":
			var b: Ent = S.sel[0] if S.sel.size() else null
			if b == null or b.kind != "b": return
			if b.hp >= b.max_hp and not b.repairing: toast("Already at full strength"); return
			b.repairing = not b.repairing; sfx("click"); update_cmd()
		"sell":
			var b: Ent = S.sel[0] if S.sel.size() else null
			if b == null or b.kind != "b" or b.team != 0 or b.type == "hq": return
			var ref := S.sell(b)
			S.set_sel([]); toast("Sold for %d" % ref, "gold"); sfx("place"); refresh_panel(true)

func toggle_mode() -> void:
	box_mode = not box_mode; update_cmd(); sfx("click")

func update_cmd() -> void:
	if U == null: return
	var units: Array = S.sel.filter(func(e): return e.kind == "u")
	var combat := units.filter(func(u): return u.d.dmg > 0)
	U.btn.amove.visible = combat.size() > 0; U.btn.stop.visible = units.size() > 0; U.btn.desel.visible = S.sel.size() > 0
	var swb: Ent = null
	for e in S.ents:
		if e.alive and e.team == 0 and e.kind == "b" and e.rdy: swb = e; break
	U.btn.sw.visible = swb != null
	if swb: U.btn.sw.text = "PICK TARGET" if sw_aim else "LAUNCH " + swb.d.name.split(" ")[0].to_upper()
	var sb: Ent = S.sel[0] if (S.sel.size() == 1 and S.sel[0].kind == "b" and S.sel[0].team == 0) else null
	U.btn.repair.visible = sb != null; U.btn.sell.visible = sb != null and sb.type != "hq"
	if sb: U.set_on(U.btn.repair, sb.repairing)
	_upg_btn()
	U.set_on(U.btn.amove, amove)
	U.set_on(U.btn.form, S.formation); U.btn.form.text = "FORMATION " + ("ON" if S.formation else "OFF")
	for k in ["all", "inf", "veh", "air", "idle"]:
		var lit: bool = squad_key == k
		U.set_on(U.btn[k], lit)
		U.btn[k].text = k.to_upper() + (" · %d" % S.sel.size() if lit else "")
	U.update_mode(box_mode)
	if S.sel.size():
		U.selinfo.visible = true
		if S.sel.size() == 1:
			var e: Ent = S.sel[0]; var d := e.d
			if e.kind == "b" and e.team == 0 and not S.upg_def(e).is_empty(): U.selinfo.text = d.name + " · upgrade: " + D.UPG[e.type].say
			elif e.kind == "b": U.selinfo.text = d.name.replace(" ×4", "") + (" · tap map to set rally" if (e.type == "barracks" or e.type == "factory") else (" · park vehicles beside it" if e.type == "repair" else ""))
			else: U.selinfo.text = d.name + (" · tap aurite to mine" if d.harv else (" · tap a building to capture or fix" if d.eng else (" · heals nearby infantry" if d.heal else (" · long range, blind up close" if d.minr > 0 else ""))))
		else: U.selinfo.text = "%d units" % S.sel.size()
	else: U.selinfo.visible = false

## The UPGRADE button of a selected building: its cost, its progress while it runs (tap again to cancel), dimmed while
## the requirement is missing (a tap says what is needed).
func _upg_btn() -> void:
	var b: Ent = S.sel[0] if (S.sel.size() == 1 and S.sel[0].kind == "b" and S.sel[0].team == 0) else null
	var u: Dictionary = S.upg_def(b) if b != null else {}
	U.btn.upgrade.visible = not u.is_empty()
	if u.is_empty(): return
	if b.upg >= 0: U.btn.upgrade.text = "UPGRADING %d%% ✕" % int(b.upg * 100)
	else: U.btn.upgrade.text = "UPGRADE · %d" % u.cost
	U.set_on(U.btn.upgrade, b.upg >= 0)
	U.btn.upgrade.modulate.a = 0.55 if (b.upg < 0 and S.upg_block(b) != "") else 1.0

func ring(x: float, y: float, c: Color) -> void:
	S.parts.append({"k": "ring", "x": x, "y": y, "life": .5, "max": .5, "c": c})

# ---------------- picking ----------------
func pick(sx: float, sy: float, wx: float, wy: float) -> Ent:
	V.update_cam()
	var best: Ent = null; var bd := 1e9
	for e in S.ents:
		if not e.alive or e.kind != "u" or e.captive or e.intun > 0: continue
		if e.team != 0 and not S.visible_to_player(e): continue
		var h: float = S.h_at(e.x, e.y) + (D.ALT if e.d.air else 0.0)
		var p := V.w2s(e.x, e.y, h + D.UH[e.type] * .45)
		if p.z < 0: continue
		var q := V.w2s(e.x + T, e.y, h); var o := V.w2s(e.x, e.y, h); var ppt: float = abs(q.x - o.x)
		# generous: a fingertip is about 30 UI units wide, small infantry far less
		var rad: float = max(32.0, e.r / T * ppt * 1.8); var dd := Vector2(p.x - sx, p.y - sy).length()
		if dd < rad and dd < bd: bd = dd; best = e
	if best: return best
	var rr := V.ray(sx, sy); var ro: Vector3 = rr[0]; var rn: Vector3 = rr[1]
	var bdist := 1e9; var bb: Ent = null
	for e in S.ents:
		if not e.alive or e.kind != "b" or not S.visible_to_player(e): continue
		var box := AABB(Vector3(e.tx, 0, e.ty), Vector3(e.w, D.BH[e.type], e.h))
		var hit = box.intersects_ray(ro, rn)
		if hit != null:
			var dd: float = (hit as Vector3).distance_to(ro)
			if dd < bdist: bdist = dd; bb = e
	if bb: return bb
	var tx := int(wx / T); var ty := int(wy / T)
	if not Sim.inb(tx, ty): return null
	var id: int = S.bmap[ty * 64 + tx]
	if id and S.by_id.has(id):
		var b: Ent = S.by_id[id]
		if b.alive and S.visible_to_player(b): return b
	return null

func tap(sx: float, sy: float, right: bool) -> void:
	if S.teams.is_empty() or S.over: return
	var w := V.s2w(sx, sy); var wx := w.x; var wy := w.y
	if placing != null:
		var tx := int(floor(wx / T)); var ty := int(floor(wy / T)); var d: Dictionary = D.BLD[placing.type]
		if tx >= placing.tx and tx < placing.tx + d.w and ty >= placing.ty and ty < placing.ty + d.h: confirm_place()
		else:
			placing.tx = int(round(wx / T - d.w / 2.0)); placing.ty = int(round(wy / T - d.h / 2.0))
		return
	var hit := pick(sx, sy, wx, wy)
	var sel_u: Array = S.sel.filter(func(e): return e.kind == "u")
	if sw_aim and not right:
		var b: Ent = null
		for e in S.ents:
			if e.alive and e.team == 0 and e.kind == "b" and e.rdy: b = e; break
		sw_aim = false
		if b: S.launch_sw(b, wx, wy)
		update_cmd(); return
	if right:
		if sel_u.size(): command(hit, wx, wy, sel_u)
		else: S.set_sel([])
		return
	if hit != null and hit.team == 0:
		if hit.kind == "b" and hit.type == "refinery" and sel_u.any(func(u): return u.d.harv):
			for u in sel_u:
				if u.d.harv: u.hs = "ret"
			ring(hit.x, hit.y, Color("f0b93f")); return
		if hit.kind == "b" and hit.type == "repair" and sel_u.any(func(u): return u.d.armor != "inf"):
			S.group_move(sel_u.filter(func(u): return u.d.armor != "inf"), hit.x, hit.y, "move"); ring(hit.x, hit.y, Color("7fd68e")); sfx("click"); return
		if hit.kind == "b" and hit.hp < hit.max_hp and sel_u.any(func(u): return u.d.eng):
			S.eng_order(sel_u.filter(func(u): return u.d.eng), hit); ring(hit.x, hit.y, Color("7fd68e")); sfx("click"); return
		if hit.kind == "u":
			var now := Time.get_ticks_msec()
			if last_tap.id == hit.id and now - last_tap.t < 380:
				# double-tap / double-click: every unit of that type on screen
				var same := S.ents.filter(func(e): return e.alive and e.kind == "u" and e.team == 0 and e.type == hit.type and V.on_screen(e.x, e.y))
				S.set_sel(same); last_tap.id = 0
				if same.size() > 1: toast("%d × %s" % [same.size(), hit.d.name])
			else:
				S.set_sel([hit]); last_tap = {"id": hit.id, "t": now}
			buzz(8)
		else: S.set_sel([hit])
		sfx("click"); return
	if sel_u.size():
		command(hit, wx, wy, sel_u); return
	var sb: Ent = S.sel[0] if S.sel.size() else null
	if sb and sb.kind == "b" and (sb.type == "barracks" or sb.type == "factory"):
		sb.rally = Vector2(wx, wy); ring(wx, wy, Color("7fd68e")); sfx("click"); return
	S.set_sel([])

func command(hit: Ent, wx: float, wy: float, units: Array, face = null, width := 0.0) -> void:
	var combat := units.filter(func(u): return u.d.dmg > 0)
	var harvs := units.filter(func(u): return u.d.harv)
	var engs := units.filter(func(u): return u.d.eng)
	var others := units.filter(func(u): return u.d.dmg == 0 and not u.d.harv and not (u.d.eng and hit != null and hit.kind == "b" and hit.team != 0))
	if hit != null and hit.team != 0:
		if combat.size(): S.attack_order(combat, hit); ring(hit.x, hit.y, Color("ff5a52")); sfx("click")
		if hit.kind == "b" and engs.size(): S.eng_order(engs, hit); ring(hit.x, hit.y, Color("7fd68e")); sfx("click")
		if others.size(): S.group_move(others, hit.x, hit.y, "move")
		buzz(12); amove = false; update_cmd(); return
	var ti := clampi(int(wy / T), 0, 63) * 64 + clampi(int(wx / T), 0, 63)
	if harvs.size() and S.ore[ti] > 0:
		for h in harvs: h.pref = ti; h.hs = "find"
		ring(wx, wy, Color("f0b93f"))
	elif harvs.size(): S.group_move(harvs, wx, wy, "move")
	if combat.size() or others.size():
		S.group_move(combat + others, wx, wy, "amove" if (amove and combat.size()) else "move", face, width)
		ring(wx, wy, Color("ff5a52") if amove else Color("7fd68e"))
	sfx("ack"); buzz(12); amove = false; update_cmd()

func box_select(x0: float, y0: float, x1: float, y1: float) -> void:
	var us := _box_units(Vector2(x0, y0), Vector2(x1, y1))
	var cb := us.filter(func(u): return not u.d.harv)
	if cb.size(): us = cb
	S.set_sel(us)
	if us.size(): sfx("click"); buzz(8)

func _box_units(a: Vector2, b: Vector2) -> Array:
	V.update_cam()
	var x0 := a.x; var y0 := a.y; var x1 := b.x; var y1 := b.y
	var r := Rect2(Vector2(min(x0, x1), min(y0, y1)), Vector2(abs(x1 - x0), abs(y1 - y0))).grow(6)
	return S.ents.filter(func(e):
		if not e.alive or e.kind != "u" or e.team != 0 or e.captive or e.intun > 0: return false
		var p := V.w2s(e.x, e.y, S.h_at(e.x, e.y) + .2 + (D.ALT if e.d.air else 0.0))
		return p.z > 0 and r.has_point(Vector2(p.x, p.y)))

# ---------------- input ----------------
func _in_view(p: Vector2) -> bool:
	return V.view_rect().has_point(p)

func _unhandled_input(ev: InputEvent) -> void:
	if S.teams.is_empty() or paused or cut.active: return
	if ev is InputEventScreenTouch:
		if ev.pressed: _down(ev.index, ev.position, false, 0)
		else: _up(ev.index, ev.position, ev.canceled)
	elif ev is InputEventScreenDrag:
		_move(ev.index, ev.position)
	elif ev is InputEventMouseButton and ev.device != InputEvent.DEVICE_ID_EMULATION:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP or ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if ev.pressed: _zoom_at(ev.position, 1.12 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 1 / 1.12)
			return
		if ev.pressed: _down(-1, ev.position, true, ev.button_index)
		else: _up(-1, ev.position, false)
	elif ev is InputEventMouseMotion and ev.device != InputEvent.DEVICE_ID_EMULATION:
		if ptrs.has(-1): _move(-1, ev.position)
		elif placing != null and _in_view(ev.position):
			var w := V.s2w(ev.position.x, ev.position.y); var d: Dictionary = D.BLD[placing.type]
			placing.tx = int(round(w.x / T - d.w / 2.0)); placing.ty = int(round(w.y / T - d.h / 2.0))
	elif ev is InputEventKey:
		var k: String = OS.get_keycode_string(ev.keycode).to_lower()
		keys[k] = ev.pressed
		if ev.pressed and ev.keycode == KEY_ESCAPE:
			if placing != null: end_placing()
			elif amove: amove = false; update_cmd()
			else: S.set_sel([])

func _zoom_at(p: Vector2, f: float) -> void:
	var w := V.s2w(p.x, p.y)
	V.cam_z *= f; V.clamp_cam()
	var w2 := V.s2w(p.x, p.y)
	V.cam_x += w.x - w2.x; V.cam_y += w.y - w2.y; V.clamp_cam()

func _down(id: int, p: Vector2, mouse: bool, button: int) -> void:
	if not _in_view(p): return
	ptrs[id] = p
	if ptrs.size() == 2:
		var v := ptrs.values(); var a: Vector2 = v[0]; var b: Vector2 = v[1]
		var m := (a + b) / 2
		# the world point under the fingers' midpoint stays under it: moving both fingers pans the map;
		# spreading them zooms, but only past a dead zone so a two-finger pan does not drift the zoom
		gest = {"mode": "pinch", "d0": max(1.0, a.distance_to(b)), "z0": V.cam_z, "w": V.s2w(m.x, m.y), "zoom": false, "upd": {}}
		_clear_preview(); return
	if ptrs.size() > 2: return
	gest = {"mode": "pending", "s": p, "e": p, "l": p, "mouse": mouse, "btn": button, "t0": Time.get_ticks_msec()}
	if mouse and (button == MOUSE_BUTTON_MIDDLE or button == MOUSE_BUTTON_RIGHT): gest.mode = "rpending"

func _sel_movers() -> Array:
	return S.sel.filter(func(e): return e.kind == "u" and not e.d.harv)

func _move(id: int, p: Vector2) -> void:
	if not ptrs.has(id): return
	ptrs[id] = p
	if gest == null: return
	if gest.mode == "pinch":
		if ptrs.size() < 2: return
		var v := ptrs.values(); var a: Vector2 = v[0]; var b: Vector2 = v[1]
		var m := (a + b) / 2
		var dd: float = max(1.0, a.distance_to(b))
		# fingers report one at a time: judge the spread only once both have moved, or a fast pan
		# (one finger ahead of the other) looks like a pinch
		gest.upd[id] = true
		if not gest.zoom and gest.upd.size() >= 2:
			gest.upd = {}
			if abs(dd / gest.d0 - 1) > .12: gest.zoom = true; gest.d0 = dd; gest.z0 = V.cam_z
		if gest.zoom: V.cam_z = gest.z0 * dd / gest.d0; V.clamp_cam()
		var w2 := V.s2w(m.x, m.y); V.cam_x += gest.w.x - w2.x; V.cam_y += gest.w.y - w2.y; V.clamp_cam()
		return
	# a finger wobbles more than a mouse: a touch must travel further before a tap turns into a drag
	var moved: bool = p.distance_to(gest.s) > (9.0 if gest.mouse else 14.0)
	if gest.mode == "pending" and moved:
		if gest.mouse: gest.mode = "box"
		elif placing != null:
			gest.mode = "ghost"; gest.g0 = Vector2(placing.tx, placing.ty); gest.w0 = V.s2w(gest.s.x, gest.s.y)
		elif box_mode or PAN_FINGERS == 2: gest.mode = "box"
		else: gest.mode = "pan"
	elif gest.mode == "rpending" and moved:
		gest.mode = "face" if (gest.btn == MOUSE_BUTTON_RIGHT and _sel_movers().size() and placing == null) else "pan"
		if gest.mode == "face": gest.from = V.s2w(gest.s.x, gest.s.y)
	elif gest.mode == "lp" and moved:
		# hold then drag: a box, unless units are selected and the hold began on open ground, which
		# sets a formation's facing; starting on one of your units always boxes
		if _sel_movers().size() and placing == null and not gest.get("own", false):
			gest.mode = "face"; gest.from = V.s2w(gest.s.x, gest.s.y)
		else: gest.mode = "box"
	match gest.mode:
		"pan":
			var a := V.s2w(gest.l.x, gest.l.y); var b := V.s2w(p.x, p.y)
			V.cam_x += a.x - b.x; V.cam_y += a.y - b.y; V.clamp_cam()
		"box": gest.e = p
		"ghost":
			# the building moves with the finger from where it was, so it can be dragged from below without hiding it
			var dw: Vector2 = (V.s2w(p.x, p.y) - gest.w0) / T
			placing.tx = int(gest.g0.x + round(dw.x)); placing.ty = int(gest.g0.y + round(dw.y))
		"face":
			gest.e = p
			_face_preview()
	if gest.mouse and placing != null and gest.mode != "pan":
		var w := V.s2w(p.x, p.y); var d: Dictionary = D.BLD[placing.type]
		placing.tx = int(round(w.x / T - d.w / 2.0)); placing.ty = int(round(w.y / T - d.h / 2.0))
	gest.l = p

func _face_params():
	var from: Vector2 = gest.from; var to := V.s2w(gest.e.x, gest.e.y)
	if from.distance_to(to) < T * 0.6: return null
	return {"from": from, "to": to, "ang": atan2(to.y - from.y, to.x - from.x) - PI / 2, "width": from.distance_to(to) / T}

## The drag line is the front of the formation; the troops face across it (left of the drag direction, so a left-to-right drag faces up the screen).
func _face_preview() -> void:
	var fp = _face_params()
	if fp == null: _clear_preview(); return
	var movers := _sel_movers()
	var mid: Vector2 = (fp.from + fp.to) / 2
	var plan := S.plan_formation(movers, mid.x, mid.y, fp.ang, fp.width)
	preview_slots = plan.map(func(p): return p[1])
	pv_from = fp.from; pv_to = fp.to

func _clear_preview() -> void:
	preview_slots = []; pv_from = null; pv_to = null

func _up(id: int, p: Vector2, cancel: bool) -> void:
	if not ptrs.has(id): return
	ptrs.erase(id)
	if gest == null: return
	if gest.mode == "pinch":
		if ptrs.is_empty(): gest = null
		else: gest.mode = "dead"
		return
	if gest.mode == "dead":
		if ptrs.is_empty(): gest = null
		return
	if cancel: gest = null; _clear_preview(); return
	match gest.mode:
		"pending": tap(p.x, p.y, false)
		"rpending":
			if placing != null: end_placing()
			elif gest.btn == MOUSE_BUTTON_RIGHT: tap(p.x, p.y, true)
		"lp": S.set_sel([])
		"box":
			var sz: Vector2 = (gest.e - gest.s).abs()
			if not gest.mouse and _box_units(gest.s, gest.e).is_empty():
				# an empty box from a finger keeps the selection; a short one was a shaky tap
				if sz.x < 48 and sz.y < 48: tap(gest.s.x, gest.s.y, false)
			else: box_select(gest.s.x, gest.s.y, gest.e.x, gest.e.y)
			if box_mode and not gest.mouse: box_mode = false; update_cmd()
		"face":
			var fp = _face_params()
			var units := S.sel.filter(func(e): return e.kind == "u")
			if fp == null: tap(gest.s.x, gest.s.y, gest.mouse)
			elif units.size():
				var mid: Vector2 = (fp.from + fp.to) / 2
				command(null, mid.x, mid.y, units, fp.ang, fp.width)
	gest = null; _clear_preview()

func _check_long_press() -> void:
	if gest != null and gest.mode == "pending" and not gest.mouse and placing == null and Time.get_ticks_msec() - gest.t0 > 450:
		gest.mode = "lp"
		var w := V.s2w(gest.s.x, gest.s.y); var h := pick(gest.s.x, gest.s.y, w.x, w.y)
		gest.own = h != null and h.team == 0 and h.kind == "u"
		Input.vibrate_handheld(15)

func key_pan(dt: float) -> void:
	var s := 700.0 / V.cam_z * dt; var mv := false
	if keys.get("a", false) or keys.get("left", false): V.cam_x -= s; mv = true
	if keys.get("d", false) or keys.get("right", false): V.cam_x += s; mv = true
	if keys.get("w", false) or keys.get("up", false): V.cam_y -= s; mv = true
	if keys.get("s", false) or keys.get("down", false): V.cam_y += s; mv = true
	if mv: V.clamp_cam()

# ---------------- HUD drawing ----------------
func draw_hud(c: Control) -> void:
	if S.teams.is_empty() or U.overlays.start.visible: return
	var f: Font = U.f_disp
	for e in S.ents:
		if not e.alive or not (e.sel or e.hit_t > 0 or (e.kind == "b" and (e.repairing or (e.upg >= 0 and e.team == 0)))): continue
		if e.team != 0 and not S.visible_to_player(e): continue
		var is_b: bool = e.kind == "b"
		var top: float = D.BH[e.type] + .25 if is_b else D.UH[e.type] + .15 + (D.ALT if e.d.air else 0.0)
		var p := V.w2s(e.x, e.y, S.h_at(e.x, e.y) + top)
		if p.z < 0: continue
		var q := V.w2s(e.x + T, e.y, S.h_at(e.x, e.y) + top); var ppt: float = abs(q.x - p.x)
		var w: float = max(24.0, e.w * ppt * .85) if is_b else max(18.0, e.r / T * 2 * ppt + 8)
		var x := p.x - w / 2; var y := p.y - 4; var fr: float = max(0.0, e.hp / e.max_hp)
		_hp_bar(c, Rect2(x, y, w, 4 if is_b else 3), fr, D.MINI_COL[e.team] if e.team < D.MINI_COL.size() else Color.WHITE, is_b)
		if e.kind == "u" and e.d.harv and e.sel:
			c.draw_rect(Rect2(x - 1, y + 4, w + 2, 4), Color(0, 0, 0, .75)); c.draw_rect(Rect2(x, y + 5, w * e.load / D.HARV_CAP, 2), Color("f0b93f"))
		if is_b and e.upg >= 0 and (e.team == 0 or e.sel):
			c.draw_rect(Rect2(x - 1, y + 5, w + 2, 4), Color(0, 0, 0, .75)); c.draw_rect(Rect2(x, y + 6, w * e.upg, 2), Color("f0b93f"))
		if is_b and e.repairing:
			c.draw_string(U.f_disp7, Vector2(p.x - 5, y - 5 + sin(S.time * 6) * 2), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("7fd68e"))
	_draw_mission_marks(c)
	# floating "+N" aurite numbers (refinery deliveries, sales)
	for p in S.parts:
		if p.k != "txt": continue
		var fr: float = p.life / p.max
		var q: Vector3 = V.w2s(p.x, p.y, S.h_at(p.x, p.y) + p.h + (1 - fr) * .8)
		if q.z < 0: continue
		var col: Color = p.c; col.a = min(1.0, fr * 2.2)
		var tw: float = f.get_string_size(p.txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		c.draw_string_outline(f, Vector2(q.x - tw / 2, q.y), p.txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(0, 0, 0, .7 * col.a))
		c.draw_string(f, Vector2(q.x - tw / 2, q.y), p.txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
	if gest != null and gest.mode == "box":
		var r := Rect2(Vector2(min(gest.s.x, gest.e.x), min(gest.s.y, gest.e.y)), Vector2(abs(gest.e.x - gest.s.x), abs(gest.e.y - gest.s.y)))
		c.draw_rect(r, Color(.5, .84, .56, .12)); c.draw_rect(r, Color("7fd68e"), false, 1.5)
	if gest != null and gest.mode == "lp":
		c.draw_arc(gest.s, 22, 0, TAU, 32, Color("7fd68e"), 2)
	if sw_aim: _order_banner(c, "launch", "SUPERWEAPON: TAP A TARGET", Color(.94, .73, .25))
	elif amove: _order_banner(c, "atk", "ATTACK-MOVE: TAP A DESTINATION", Color(.95, .32, .28))
	elif gest != null and gest.mode == "face" and pv_from != null: _order_banner(c, "form", "RELEASE TO FORM UP FACING THIS WAY", Color(.56, .84, .48))

## Health bar over a unit or building: dark frame, team-coloured cap, fill from green to red, quarter ticks.
func _hp_bar(c: Control, r: Rect2, fr: float, team: Color, big: bool) -> void:
	c.draw_rect(r.grow(1.5), Color(0, 0, 0, .78))
	c.draw_rect(r, Color(0.12, 0.13, 0.1, 0.9))
	var col := Color("8fcf7a") if fr > .6 else (Color("f0c23f") if fr > .3 else Color("ff5a52"))
	c.draw_rect(Rect2(r.position, Vector2(r.size.x * fr, r.size.y)), col)
	c.draw_rect(Rect2(r.position, Vector2(r.size.x * fr, 1)), col.lightened(0.35))
	if r.size.x >= 30:
		var n := 8 if big and r.size.x > 70 else 4
		for i in range(1, n): c.draw_rect(Rect2(r.position.x + r.size.x * i / n, r.position.y, 1, r.size.y), Color(0, 0, 0, .55))
	c.draw_rect(Rect2(r.position.x - 1.5, r.position.y - 1.5, 3, r.size.y + 3), team)

## A plate centred above the command buttons naming the order the next tap gives.
func _order_banner(c: Control, g: String, txt: String, col: Color) -> void:
	var vr := V.view_rect(); var f: Font = U.f_disp
	var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var w := tw + 52; var r := Rect2(maxf(8.0, vr.size.x / 2 - w / 2), U.cmd_row.get_global_rect().position.y - 42, w, 32)
	c.draw_style_box(UI.cut(Color(0.055, 0.062, 0.045, 0.9), Color(col, 0.8), 1, 8, 0), r)
	c.draw_rect(Rect2(r.position.x, r.position.y + 8, 3, r.size.y - 8), col)
	UI.glyph(c, g, Rect2(r.position.x + 14, r.position.y + 8, 16, 16), col)
	c.draw_string(f, Vector2(r.position.x + 38, r.position.y + 21), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col.lightened(0.3))

## Campaign markers over the 3D view: hero chevrons, prisoners, convoy trucks, targets, objective labels.
func _draw_mission_marks(c: Control) -> void:
	if S.mission == null: return
	var f: Font = U.f_disp7
	var g = S.goal()
	var tg: Array = S.goal_targets(g) if g != null and (g.k == "kill" or g.k == "capture") else []
	for e in S.ents:
		if not e.alive: continue
		var hero: bool = e.kind == "u" and e.d.hero
		if not (hero or e.captive or e.tag == "vip" or tg.has(e)): continue
		if e.team != 0 and not S.visible_to_player(e): continue
		if e.captive and S.vis[int(e.y / T) * 64 + int(e.x / T)] == 0: continue
		var top: float = (D.BH[e.type] + .55) if e.kind == "b" else (D.UH[e.type] + .5 + (D.ALT if e.d.air else 0.0))
		var p := V.w2s(e.x, e.y, S.h_at(e.x, e.y) + top)
		if p.z < 0: continue
		var bob := sin(S.time * 4 + e.id) * 2
		if e.captive:
			c.draw_string_outline(f, Vector2(p.x - 4, p.y + bob), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 4, Color(0, 0, 0, .8))
			c.draw_string(f, Vector2(p.x - 4, p.y + bob), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("f0b93f"))
		elif tg.has(e):
			var col := Color("ff5a52") if g.k == "kill" else Color("f0b93f")
			var q := Vector2(p.x, p.y - 4 + bob)
			c.draw_colored_polygon(PackedVector2Array([q + Vector2(0, -9), q + Vector2(7, 0), q + Vector2(0, 9), q + Vector2(-7, 0)]), Color(0, 0, 0, .6))
			c.draw_colored_polygon(PackedVector2Array([q + Vector2(0, -7), q + Vector2(5, 0), q + Vector2(0, 7), q + Vector2(-5, 0)]), col)
		elif hero:
			var col: Color = Color("f0b93f") if e.team == 0 else Color("ff5a52")
			var q := Vector2(p.x, p.y + bob * .5)
			for k in 2:
				var o := Vector2(0, k * 5)
				c.draw_polyline(PackedVector2Array([q + o + Vector2(-7, -3), q + o + Vector2(0, 3), q + o + Vector2(7, -3)]), Color(0, 0, 0, .7), 4)
				c.draw_polyline(PackedVector2Array([q + o + Vector2(-7, -3), q + o + Vector2(0, 3), q + o + Vector2(7, -3)]), col, 2)
		else:
			c.draw_rect(Rect2(p.x - 4, p.y - 4 + bob * .5, 8, 8), Color(0, 0, 0, .7))
			c.draw_rect(Rect2(p.x - 3, p.y - 3 + bob * .5, 6, 6), Color("e4ebee"))
	for m in S.marks():
		var q := V.w2s(m[0] * T + 16, m[1] * T + 16, S.h_at(m[0] * T + 16, m[1] * T + 16) + 1.6)
		if q.z < 0 or g == null or g.label == "": continue
		var txt: String = g.label.to_upper()
		var tw: float = U.f_disp.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		c.draw_string_outline(U.f_disp, Vector2(q.x - tw / 2, q.y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 4, Color(0, 0, 0, .75))
		c.draw_string(U.f_disp, Vector2(q.x - tw / 2, q.y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("f0b93f"))

# ---------------- minimap ----------------
func render_mini() -> void:
	var m = U.mini; var img: Image = m.img
	var data := PackedByteArray(); data.resize(64 * 64 * 4)
	for i in 64 * 64:
		var v: int = S.vis[i]; var k := i * 4
		if v == 0:
			data[k] = 4; data[k + 1] = 6; data[k + 2] = 8; data[k + 3] = 255; continue
		var col: Color = D.tcol(S.theme)[S.terr[i]] * 0.9
		if S.ore[i]: col = Color8(220, 170, 60)
		if v == 1: col = col * 0.55
		data[k] = int(col.r * 255); data[k + 1] = int(col.g * 255); data[k + 2] = int(col.b * 255); data[k + 3] = 255
	for e in S.ents:
		if not e.alive or (e.team != 0 and not S.visible_to_player(e)): continue
		var c: Color = D.MINI_COL[e.team]
		var r := Rect2i(e.tx, e.ty, e.w, e.h) if e.kind == "b" else Rect2i(int(e.x / T), int(e.y / T), 1, 1)
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				if x < 0 or y < 0 or x > 63 or y > 63: continue
				var k := (y * 64 + x) * 4
				data[k] = int(c.r * 255); data[k + 1] = int(c.g * 255); data[k + 2] = int(c.b * 255)
	img.set_data(64, 64, false, Image.FORMAT_RGBA8, data)
	m.tex.update(img)
	m.queue_redraw()
	if U.big_map.visible: U.big_map.queue_redraw()

func draw_mini_overlay(c: Control) -> void:
	if S.teams.is_empty(): return
	var s := c.size / 64.0
	var vr := V.view_rect()
	var cs := [Vector2(0, 0), Vector2(vr.size.x, 0), Vector2(vr.size.x, vr.size.y), Vector2(0, vr.size.y)].map(func(p): return (V.s2w(p.x, p.y) / T * s).clamp(Vector2.ZERO, c.size))
	cs.append(cs[0])
	c.draw_polyline(PackedVector2Array(cs), Color.WHITE, 1.0)
	var pulse := 0.6 + 0.4 * sin(S.time * 4)
	for m in S.marks():
		var col: Color = [Color("f0b93f"), Color("7fd68e"), Color("ff5a52"), Color("f0b93f")][m[3] + 1]
		c.draw_arc(Vector2(m[0] + .5, m[1] + .5) * s, max(3.0, m[2] * s.x), 0, TAU, 20, Color(col, pulse), 1.5)
	var g = S.goal()
	if g != null and (g.k == "kill" or g.k == "capture"):
		for e in S.goal_targets(g):
			if e.kind == "b" or S.visible_to_player(e):
				var q := Vector2(e.x / T, e.y / T) * s
				c.draw_colored_polygon(PackedVector2Array([q + Vector2(0, -4), q + Vector2(4, 0), q + Vector2(0, 4), q + Vector2(-4, 0)]), Color(Color("ff5a52") if g.k == "kill" else Color("f0b93f"), pulse))
	for e in S.ents:
		if e.alive and e.captive:
			c.draw_circle(Vector2(e.x / T, e.y / T) * s, 2.5, Color(Color("f0b93f"), pulse))
	if S.ping != null and S.time - S.ping.t < 4:
		var f := fmod(S.time - S.ping.t, 1.0)
		c.draw_arc(Vector2(S.ping.x, S.ping.y) / T * s, 4 + f * 14, 0, TAU, 24, Color(1, .35, .32, 1 - f), 2)

func mini_go(f: Vector2) -> void:
	if S.teams.is_empty(): return
	V.center_on(f.x * D.WW, f.y * D.WH)

# ---------------- build icons ----------------
func render_icons(fac: String) -> void:
	icons_for = fac
	var vp := SubViewport.new(); vp.size = Vector2i(112, 88); vp.own_world_3d = true; vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera3D.new(); cam.fov = 30; vp.add_child(cam)
	var l := DirectionalLight3D.new(); l.light_energy = 1.0; vp.add_child(l); l.position = Vector3(-3, 6, 4); l.look_at(Vector3.ZERO)
	var env := Environment.new(); env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color("c8cfd6"); env.ambient_light_energy = .9
	env.background_mode = Environment.BG_CLEAR_COLOR
	var we := WorldEnvironment.new(); we.environment = env; vp.add_child(we)
	Models.material.set_shader_parameter("fog_on", 0.0)
	var dir := Vector3(.75, .75, 1).normalized()
	for k in U.items:
		var it = U.items[k]
		var m := Models.get_model("b" if it.cat == "bld" else "u", it.type, 0, fac)
		if it.cat != "bld": m.rotation.y = .5
		vp.add_child(m)
		var bb := AABB(); var first := true
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			if not (mi as Node3D).is_visible_in_tree(): continue
			var a: AABB = (m.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb() if m.is_inside_tree() else mi.get_aabb()
			a = m.transform * a
			bb = a if first else bb.merge(a); first = false
		var ctr := bb.get_center(); var sz := bb.size
		var L: float = max(sz.x, max(sz.y * 1.2, sz.z))
		cam.position = ctr + dir * L * 2.2; cam.look_at(ctr)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		it.icon = ImageTexture.create_from_image(img); it.queue_redraw()
		m.queue_free()
	Models.material.set_shader_parameter("fog_on", 1.0)
	vp.queue_free()

# ---------------- loop ----------------
func _process(delta: float) -> void:
	var dt: float = min(.05, delta)
	if cut.active:
		S.step(dt)
		A.intensity = A.intensity + (S.combat - A.intensity) * min(1.0, dt * 0.5)
		V.render(dt, null, [], null, null)
		cut.tick(dt)
		U.tick(dt)
		return
	if S.teams.size():
		if not paused and not S.over:
			S.step(dt)
			if placing != null and not S.teams[0].prod.bld.ready: end_placing()
		elif S.over: S.upd_parts(dt)
		_check_long_press()
		key_pan(dt)
		A.intensity = A.intensity + (S.combat - A.intensity) * min(1.0, dt * 0.5)
		V.render(dt, placing, preview_slots, pv_from, pv_to)
		hud_tick(dt)
	else:
		V.update_cam()
	U.tick(dt)
	safe_t += dt
	if safe_t > 0.5:
		safe_t = 0.0; _apply_safe()

# ---------------- automated screenshot test (AF_SHOT=dir) ----------------
func _autotest(dir: String) -> void:
	await get_tree().create_timer(2.0).timeout
	await _shot(dir + "/00_start.png")
	var mode := OS.get_environment("AF_MODE")
	if mode == "splash":
		U.build_splash(); U.show_overlay("splash")
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://splash.png")
		await _shot(dir + "/splash.png"); get_tree().quit(); return
	if mode == "menus":
		await _menu_shots(dir); get_tree().quit(); return
	if mode == "camp":
		await _camp_shots(dir); get_tree().quit(); return
	if mode == "cine":
		await _cine_shots(dir); get_tree().quit(); return
	if OS.get_environment("AF_CAMP") != "": camp_id = OS.get_environment("AF_CAMP")
	if mode.begins_with("m"):
		open_brief(int(mode.substr(1)))
		await get_tree().create_timer(0.5).timeout
		await _shot(dir + "/01_brief.png")
		begin_mission()
	elif mode == "b":
		await _bld_test(dir); get_tree().quit(); return
	elif mode == "choir":
		await _choir_shots(dir); get_tree().quit(); return
	elif mode == "up":
		await _upgrade_shots(dir); get_tree().quit(); return
	else:
		play({"fac": OS.get_environment("AF_FAC") if OS.get_environment("AF_FAC") != "" else "vanguard", "enemy": OS.get_environment("AF_ENEMY"), "diff": "normal"})
	await get_tree().create_timer(1.0).timeout
	await _shot(dir + "/02_game.png")
	if OS.get_environment("AF_INPUT") != "":
		await _input_test()
		get_tree().quit(); return
	# fast-forward with both sides on AI
	for i in 20 * 150:
		S.step(0.05)
		if i % 20 == 0: S.ai_think(S.teams[0])
		if S.over: break
	S.update_vision()
	var army := S.ents.filter(func(e): return e.alive and e.team == 0 and e.kind == "u" and not e.d.harv)
	S.set_sel(army)
	if army.size(): V.center_on(army[0].x, army[0].y)
	await get_tree().create_timer(1.0).timeout
	await _shot(dir + "/03_later.png")
	# formation preview
	gest = {"mode": "face", "s": Vector2(300, 300), "e": Vector2(520, 300), "l": Vector2(520, 300), "mouse": true, "btn": 2, "t0": 0, "from": V.s2w(300, 300)}
	_face_preview()
	await get_tree().create_timer(0.5).timeout
	await _shot(dir + "/04_face.png")
	_clear_preview(); gest = null
	V.cam_z = 2.2; V.clamp_cam()
	await get_tree().create_timer(0.5).timeout
	await _shot(dir + "/05_zoom.png")
	for i in 20 * 240:
		S.step(0.05)
		if i % 20 == 0: S.ai_think(S.teams[0])
		if S.over: break
	var fight = null
	for p in S.proj: fight = p
	if fight: V.center_on(fight.x, fight.y)
	V.cam_z = 1.4; V.clamp_cam()
	await get_tree().create_timer(0.3).timeout
	await _shot(dir + "/06_fight.png")
	print("AUTOTEST time=", S.time, " over=", S.over, " ents=", S.ents.size())
	get_tree().quit()

## AF_MODE=menus: one screenshot per menu screen.
func _menu_shots(dir: String) -> void:
	U.show_overlay("skirmish")
	await get_tree().create_timer(0.3).timeout
	await _shot(dir + "/01_skirmish.png")
	U.btn.camp_tile.pressed.emit()
	await get_tree().create_timer(0.3).timeout
	await _shot(dir + "/01a_campaigns.png")
	U.camp_scroll.scroll_vertical = 0
	await get_tree().create_timer(0.1).timeout
	# drag the mission list: only the list moves, a drag that scrolled does not open a briefing
	var lr := U.camp_scroll.get_global_rect(); var p0 := lr.get_center() + Vector2(0, lr.size.y * 0.3)
	var sv0 := U.camp_scroll.scroll_vertical
	Input.set_emulate_touch_from_mouse(true)  # ScrollContainer only drag-scrolls on touch screens
	_mouse(p0, true); await get_tree().process_frame
	for k in 8:
		_mouse(p0 - Vector2(0, 25 * (k + 1)), true, true); await get_tree().process_frame
	_mouse(p0 - Vector2(0, 200), false); await get_tree().create_timer(0.4).timeout
	Input.set_emulate_touch_from_mouse(false)
	print("MENU list drag scroll ", sv0, " -> ", U.camp_scroll.scroll_vertical, " brief=", U.overlays.brief.visible)
	await get_tree().create_timer(0.2).timeout
	await _shot(dir + "/01b_scrolled.png")
	U.show_overlay("manual")
	await get_tree().create_timer(0.3).timeout
	await _shot(dir + "/02_manual.png")
	open_brief(0)
	await get_tree().create_timer(0.3).timeout
	await _shot(dir + "/03_brief.png")
	begin_mission()
	await get_tree().create_timer(1.0).timeout
	open_menu()
	await get_tree().create_timer(0.3).timeout
	await _shot(dir + "/04_pause.png")
	resume()
	S.over = true; end_game(true)
	await get_tree().create_timer(1.6).timeout
	await _shot(dir + "/05_end.png")

## AF_MODE=cine: plays every cutscene (or AF_CINE=id,id) and shoots each shot halfway through, then the game it leads to.
## Run with --fixed-fps 20 so the scene keeps its pace on a slow renderer.
func _cine_shots(dir: String) -> void:
	var ids: Array = Array(OS.get_environment("AF_CINE").split(",", false)) if OS.get_environment("AF_CINE") != "" else Cutscenes.all().keys()
	for id in ids:
		var sc := Cutscenes.scene(id)
		var back := [false]
		start_cutscene(id, func(): back[0] = true)
		var last := -1
		while cut.active:
			await get_tree().process_frame
			if cut.si < sc.shots.size() and cut.si >= 0 and cut.si != last and cut.st >= sc.shots[cut.si].d * 0.6:
				last = cut.si
				await _shot(dir + "/%s_%d.png" % [id, cut.si + 1])
		print("CINE ", id, " done=", back[0])
	# Begin on mission 1 of campaign I: opening (already seen now, so skipped) and intro, then the game
	camp_id = "ashen"; open_brief(0); begin_mission()
	await get_tree().create_timer(1.0).timeout
	cut.skip()
	while cut.active: await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	await _shot(dir + "/after_skip.png")
	print("CINE game running=", not paused, " mission=", S.mission.title if S.mission else "")

## AF_MODE=camp: the campaign menu, then every mission's briefing and its opening view, zoomed out.
func _camp_shots(dir: String) -> void:
	for C in D.CAMPAIGNS:
		show_start(); pick_campaign(C.id)
		await get_tree().create_timer(0.4).timeout
		await _shot(dir + "/%s_menu.png" % C.id)
		for i in C.missions.size():
			open_brief(i)
			await get_tree().create_timer(0.3).timeout
			await _shot(dir + "/%s_%d_brief.png" % [C.id, i + 1])
			begin_mission()
			for k in 60:
				S.step(0.05)
			await get_tree().create_timer(1.0).timeout
			await _shot(dir + "/%s_%d_start.png" % [C.id, i + 1])
			paused = true
			V.cam_z = 0.5; V.clamp_cam(); V.fog_clear(true)
			var m = S.marks()
			if m.size(): V.center_on(m[0][0] * T, m[0][1] * T)
			await get_tree().create_timer(0.5).timeout
			await _shot(dir + "/%s_%d_wide.png" % [C.id, i + 1])
			paused = true

## AF_MODE=b: every building model, then the build, sell and collapse animations and a harvester at work.
func _bld_test(dir: String) -> void:
	play({"fac": OS.get_environment("AF_FAC") if OS.get_environment("AF_FAC") != "" else "vanguard", "diff": "normal"})
	paused = true
	var hq: Ent = S.ents.filter(func(e): return e.team == 0 and e.type == "hq")[0]
	var bs: Array = []
	for t in D.ALLB:
		if t == "wall" or not S.avail(0, t): continue
		var sp = S.ai_spot(0, t, hq)
		if sp == null: continue
		var b := S.add_building(0, t, sp.x, sp.y); b.born = -9.0; bs.append(b)
		S.update_vision()
	S.update_vision(); V.fog_clear(true)
	await get_tree().create_timer(.5).timeout
	for b in [hq] + bs:
		V.cam_z = 2.4; V.center_on(b.x, b.y)
		await get_tree().create_timer(.25).timeout
		await _shot(dir + "/b_%s.png" % b.type)
	var f: Ent = bs.filter(func(e): return e.type == "factory")[0]
	V.cam_z = 1.9; V.center_on(f.x, f.y)
	for k in [.15, .4, .7, .95]:
		f.born = S.time - k * 2.2
		await get_tree().create_timer(.15).timeout
		await _shot(dir + "/build_%d.png" % int(k * 100))
	f.born = -9.0
	S.produce_done(S.teams[0], "tank"); S.time += .5
	await get_tree().create_timer(.3).timeout
	await _shot(dir + "/door.png")
	var ref := S.sell(f)
	print("BLDTEST sold for ", ref)
	for k in 3:
		S.time += .5
		await get_tree().create_timer(.3).timeout
		await _shot(dir + "/sell_%d.png" % k)
	var p: Ent = bs.filter(func(e): return e.type == "power")[0]
	V.center_on(p.x, p.y)
	S.kill(p)
	for k in 3:
		S.time += .45
		await get_tree().create_timer(.3).timeout
		await _shot(dir + "/die_%d.png" % k)
	if not S.avail(0, "harv"): return
	paused = false
	var hv = null
	for e in S.ents:
		if e.alive and e.type == "harv": hv = e
	for i in 20 * 40:
		S.step(.05)
		if hv.hs == "mine": break
	V.cam_z = 2.2; V.center_on(hv.x, hv.y)
	await get_tree().create_timer(.6).timeout
	await _shot(dir + "/mine.png")
	hv.load = D.HARV_CAP
	for i in 20 * 60:
		S.step(.05)
		if hv.hs == "unload": break
	V.center_on(hv.x, hv.y - 20)
	await get_tree().create_timer(.7).timeout
	await _shot(dir + "/unload.png")
	print("BLDTEST done hs=", hv.hs, " parts=", S.parts.size())

## AF_MODE=up: for each faction, every upgradable building next to its upgraded twin, then the scaffold while an
## upgrade runs, the reveal and the selected building's UPGRADE button.
func _upgrade_shots(dir: String) -> void:
	for fac in D.FAC_ORDER:
		play({"fac": fac, "enemy": "ashen" if fac != "ashen" else "vanguard", "diff": "normal", "seed": 4242})
		paused = true
		var hq: Ent = S.find_hq(0)
		var pairs: Array = []
		for t in D.UPG:
			if not S.avail(0, t): continue
			var two: Array = []
			var d: Dictionary = D.BLD[t]; var spot = null
			# side by side on open ground near the yard
			for r in range(4, 22):
				for a in 24:
					var x := hq.tx + int(round(cos(TAU * a / 24.0) * r)); var y := hq.ty + int(round(sin(TAU * a / 24.0) * r))
					var ok := true
					for yy in range(y - 1, y + d.h + 1):
						for xx in range(x - 1, x + d.w * 2 + 2):
							if not S.inb(xx, yy) or S.terr[yy * D.MW + xx] >= D.ROCK or S.ore[yy * D.MW + xx] > 0 or S.bmap[yy * D.MW + xx]: ok = false
					if ok: spot = Vector2i(x, y); break
				if spot != null: break
			if spot == null: continue
			for k in 2:
				var b := S.add_building(0, t, spot.x + k * (d.w + 1), spot.y); b.born = -9.0; two.append(b)
			S.update_vision()
			if two.size() == 2:
				S.finish_upgrade(two[1]); two[1].up_t = -99.0; pairs.append(two)
		S.update_vision(); V.fog_clear(true)
		await get_tree().create_timer(.5).timeout
		for two in pairs:
			V.cam_z = 2.4 - 0.3 * two[0].w; V.center_on((two[0].x + two[1].x) / 2, (two[0].y + two[1].y) / 2)
			await get_tree().create_timer(.25).timeout
			await _shot(dir + "/%s_%s.png" % [fac, two[0].type])
		if fac != "vanguard": continue
		# a reactor mid-upgrade, selected, with the button showing progress; then the reveal
		var p: Ent = pairs[0][0]
		S.teams[0].credits = 5000.0; S.add_building(0, "refinery", hq.tx - 6, hq.ty + 4)
		S.set_sel([p]); S.start_upgrade(p); p.upg = .42
		V.cam_z = 1.6; V.center_on(p.x, p.y)
		await get_tree().create_timer(.4).timeout
		await _shot(dir + "/upgrading.png")
		S.set_sel([]); S.finish_upgrade(p)
		for k in 3:
			S.time += .35
			await get_tree().create_timer(.2).timeout
			await _shot(dir + "/reveal_%d.png" % k)
		S.time += 2.0
		var fr: Ent = pairs.filter(func(two): return two[0].type == "factory")[0][0]
		S.set_sel([fr]); update_cmd()
		await get_tree().create_timer(.3).timeout
		await _shot(dir + "/button.png")

## AF_MODE=choir: the Hollow Choir's skirmish pick, buildings, units, a burrowing sapper, shard fields, the Cantor's aura and the Chorus Well.
func _choir_shots(dir: String) -> void:
	U.show_overlay("skirmish"); U.seg_btns.fac.choir.pressed.emit()
	await get_tree().create_timer(0.3).timeout
	await _shot(dir + "/c0_skirmish.png")
	play({"fac": "choir", "enemy": "vanguard", "diff": "normal", "seed": 4242})
	paused = true
	var hq: Ent = S.find_hq(0)
	var bs: Array = []
	for t in ["power", "garden", "barracks", "factory", "comms", "tech", "helipad", "spire", "chorus", "garden"]:
		var sp = S.ai_spot(0, t, hq)
		if sp == null: continue
		var b := S.add_building(0, t, sp.x, sp.y); b.born = -9.0; bs.append(b)
		S.update_vision()
	var bur := S.add_building(0, "burrow", hq.tx + 3, hq.ty - 7); bur.born = -9.0
	S.update_vision(); V.fog_clear(true)
	V.cam_z = 1.1; V.center_on(hq.x + T * 2, hq.y - T * 2)
	await get_tree().create_timer(.6).timeout
	await _shot(dir + "/c1_base.png")
	for b in [hq, bur] + bs.filter(func(e): return ["garden", "spire", "chorus", "factory"].has(e.type)):
		V.cam_z = 2.4; V.center_on(b.x, b.y)
		await get_tree().create_timer(.25).timeout
		await _shot(dir + "/c_b_%s_%d.png" % [b.type, b.id])
	# the army in a row
	var row := ["thrall", "thrall", "sapper", "cantor", "lancer", "medic", "skitter", "mantis", "geode", "moth"]
	var x0: float = (hq.tx + 6) * T; var y0: float = (hq.ty - 14) * T
	var us: Array = []
	for i in row.size():
		var u := S.spawn_unit(0, row[i], x0 + i * T * 1.1, y0); u.ang = PI * .75; us.append(u)
	V.cam_z = 2.6; V.center_on(x0 + T * 5, y0)
	await get_tree().create_timer(.4).timeout
	await _shot(dir + "/c2_units.png")
	V.cam_z = 3.4; V.center_on(x0 + T * 2.5, y0)
	await get_tree().create_timer(.3).timeout
	await _shot(dir + "/c3_units_close.png")
	V.center_on(x0 + T * 7.5, y0)
	await get_tree().create_timer(.3).timeout
	await _shot(dir + "/c3_units_close2.png")
	# fighting: geode fields and the Cantor's aura against a Vanguard squad
	var ex: float = x0 + T * 9; var ey: float = y0 - T * 5
	var foes: Array = []
	for i in 5:
		var f := S.spawn_unit(1, "rifle" if i < 3 else "tank", ex + (i % 3) * T, ey + (i / 3) * T)
		f.hp *= 6; f.max_hp *= 6; foes.append(f)
	S.update_vision(); paused = false
	for i in 20 * 6: S.step(.05)
	V.cam_z = 1.8; V.center_on((x0 + T * 5 + ex) / 2, (y0 + ey) / 2)
	await get_tree().create_timer(.5).timeout
	await _shot(dir + "/c4_fight.png")
	# a sapper burrowing towards the tank
	var sp: Ent = us[2]
	S.group_move([sp], ex + T * 6, ey - T * 4, "move")
	for i in 12: S.step(.05)
	V.cam_z = 2.6; V.center_on(sp.x, sp.y)
	await get_tree().create_timer(.3).timeout
	await _shot(dir + "/c5_sapper.png")
	# the Chorus Well
	var ch: Ent = bs.filter(func(e): return e.type == "chorus")[0]
	S.launch_sw(ch, ex, ey)
	for i in 20 * 2: S.step(.05)
	V.cam_z = 1.4; V.center_on(ex, ey)
	await get_tree().create_timer(.2).timeout
	await _shot(dir + "/c6_chorus_charge.png")
	for i in 20 * 1: S.step(.05)
	await get_tree().create_timer(.3).timeout
	await _shot(dir + "/c7_chorus_burst.png")
	for i in 20 * 2: S.step(.05)
	await get_tree().create_timer(.3).timeout
	await _shot(dir + "/c8_chorus_field.png")
	paused = true

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path)

var mouse_last := Vector2()
func _mouse(p: Vector2, down: bool, motion := false) -> void:
	var e: InputEventMouse
	if motion:
		e = InputEventMouseMotion.new(); e.button_mask = MOUSE_BUTTON_MASK_LEFT
		e.relative = (p - mouse_last) * V.ui_scale()
	else:
		e = InputEventMouseButton.new(); e.button_index = MOUSE_BUTTON_LEFT; e.pressed = down
	e.position = p * V.ui_scale(); e.global_position = e.position; mouse_last = p
	Input.parse_input_event(e)

func _touch(i: int, p: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new(); e.index = i; e.position = p * V.ui_scale(); e.pressed = down
	Input.parse_input_event(e)

func _drag(i: int, p: Vector2) -> void:
	var e := InputEventScreenDrag.new(); e.index = i; e.position = p * V.ui_scale()
	Input.parse_input_event(e)

func _input_test() -> void:
	var r: Ent = null
	for e in S.ents:
		if e.team == 0 and e.type == "rifle": r = e; break
	var p3 := V.w2s(r.x, r.y, S.h_at(r.x, r.y) + .2); var p := Vector2(p3.x, p3.y)
	print("INPUT rifle at ", p, " paused=", paused)
	_touch(0, p, true); await get_tree().process_frame; _touch(0, p, false); await get_tree().process_frame
	print("INPUT single tap sel=", S.sel.size())
	await get_tree().create_timer(0.1).timeout
	_touch(0, p, true); await get_tree().process_frame; _touch(0, p, false); await get_tree().process_frame
	print("INPUT double tap sel=", S.sel.size(), " types=", S.sel.map(func(e): return e.type))
	var g := p + Vector2(150, -60)
	_touch(0, g, true); await get_tree().process_frame; _touch(0, g, false); await get_tree().process_frame
	print("INPUT move order: ", S.sel.map(func(e): return e.order))
	# hold then drag = formation facing
	var a := p + Vector2(-40, -120)
	_touch(0, a, true)
	await get_tree().create_timer(1.0).timeout
	for k in 6:
		_drag(0, a + Vector2(30 * (k + 1), 0)); await get_tree().process_frame
	print("INPUT face gesture mode=", gest.mode if gest else "none", " preview=", preview_slots.size())
	_touch(0, a + Vector2(180, 0), false); await get_tree().process_frame
	print("INPUT face order: ", S.sel.map(func(e): return [e.order, snappedf(e.face if e.face != null else -9.0, 0.01)]))
	# one-finger drag over the map pans (PAN_FINGERS 1)
	var cx := V.cam_x; var nsel := S.sel.size()
	_touch(0, Vector2(400, 300), true); await get_tree().process_frame
	for k in 5:
		_drag(0, Vector2(400 - 40 * (k + 1), 300 + 4 * k)); await get_tree().process_frame
	print("INPUT one-finger drag mode=", gest.mode if gest else "none")
	_touch(0, Vector2(200, 316), false); await get_tree().process_frame
	print("INPUT one-finger drag pan dx=", V.cam_x - cx, " sel ", nsel, " -> ", S.sel.size())
	# hold on a rifle, then drag: box (even with units selected)
	var rp3 := V.w2s(r.x, r.y, S.h_at(r.x, r.y) + .2)
	S.set_sel([r])
	_touch(0, Vector2(rp3.x, rp3.y), true); await get_tree().create_timer(0.7).timeout
	for k in 4:
		_drag(0, Vector2(rp3.x + 30 * (k + 1), rp3.y + 30 * (k + 1))); await get_tree().process_frame
	print("INPUT hold-drag from own unit mode=", gest.mode if gest else "none")
	_touch(0, Vector2(rp3.x + 120, rp3.y + 120), false); await get_tree().process_frame
	print("INPUT hold-box sel=", S.sel.map(func(e): return e.type))
	S.set_sel([])
	_touch(0, Vector2(rp3.x - 60, rp3.y - 60), true); await get_tree().create_timer(0.7).timeout
	for k in 4:
		_drag(0, Vector2(rp3.x - 60 + 30 * (k + 1), rp3.y - 60 + 30 * (k + 1))); await get_tree().process_frame
	_touch(0, Vector2(rp3.x + 60, rp3.y + 60), false); await get_tree().process_frame
	print("INPUT box sel=", S.sel.map(func(e): return e.type))
	# two-finger drag pans, without zooming
	var z0 := V.cam_z
	_touch(0, Vector2(380, 280), true); _touch(1, Vector2(420, 320), true); await get_tree().process_frame
	for k in 5:
		var o := Vector2(-40 * (k + 1), 0)
		_drag(0, Vector2(380, 280) + o); _drag(1, Vector2(420, 320) + o + Vector2(k, 0)); await get_tree().process_frame
	_touch(0, Vector2(180, 280), false); _touch(1, Vector2(224, 320), false); await get_tree().process_frame
	print("INPUT two-finger pan dx=", V.cam_x - cx, " zoom ", z0, " -> ", V.cam_z)
	# hide and show the side panel
	var vw := V.view_rect().size.x
	toggle_panel(); await get_tree().process_frame
	print("INPUT panel hidden: view ", vw, " -> ", V.view_rect().size.x, " panel=", U.panel.visible, " btn=", U.btn.panel.text)
	await _shot(OS.get_environment("AF_SHOT") + "/03_panel_hidden.png")
	toggle_panel(); await get_tree().process_frame
	print("INPUT panel shown: view ", V.view_rect().size.x, " panel=", U.panel.visible)
	# pinch
	var z := V.cam_z
	_touch(0, Vector2(300, 300), true); _touch(1, Vector2(500, 300), true); await get_tree().process_frame
	for k in 10:
		_drag(0, Vector2(300 - 10 * (k + 1), 300)); _drag(1, Vector2(500 + 10 * (k + 1), 300)); await get_tree().process_frame
	_touch(0, Vector2(200, 300), false); _touch(1, Vector2(600, 300), false); await get_tree().process_frame
	print("INPUT pinch zoom ", z, " -> ", V.cam_z)
	# build a reactor through the panel
	click_item("bld", "power")
	for i in 20 * 9: S.step(0.05)
	click_item("bld", "power")
	print("INPUT placing=", placing)
	confirm_place()
	print("INPUT reactors=", S.count(0, "power"))
	# drag a ready reactor out of the menu onto the map (touch on the panel item, emulated mouse)
	V.cam_z = 1.0; V.center_on(S.p0.x * T + 16, (S.p0.y - 1) * T)
	click_item("bld", "power")
	for i in 20 * 9: S.step(0.05)
	refresh_panel(true); await get_tree().process_frame
	var it = U.items["bld:power"]; var ic: Vector2 = it.get_global_rect().get_center()
	var dst := V.s2w(300, 330 - GHOST_LIFT)
	_touch(0, ic, true); await get_tree().process_frame
	for k in 8:
		_drag(0, ic.lerp(Vector2(300, 330), (k + 1) / 8.0)); await get_tree().process_frame
	print("INPUT drag-build placing=", placing)
	_touch(0, Vector2(300, 330), false); await get_tree().process_frame
	var rs := S.ents.filter(func(e): return e.alive and e.team == 0 and e.type == "power")
	print("INPUT drag-build reactors=", rs.size(), " last at ", rs.back().x if rs.size() else 0, ",", rs.back().y if rs.size() else 0, " aimed ", dst)
	end_placing()
	# hold-to-queue five, groups, hidden panel with production chips and the big map
	S.teams[0].credits = 9000
	var inf_t: String = D.sub(S.teams[0].fac, "rifle")
	if S.count(0, "barracks") == 0: S.add_building(0, D.sub(S.teams[0].fac, "barracks") if D.BLD.has(D.sub(S.teams[0].fac, "barracks")) else "barracks", 12, 44)
	queue_many("inf", inf_t, 5)
	print("INPUT queue five: ", S.teams[0].prod.inf.queue.size() + (1 if S.teams[0].prod.inf.cur != "" else 0))
	var rifles := S.ents.filter(func(e): return e.alive and e.team == 0 and e.type == "rifle")
	S.set_sel(rifles); group_btn(1, true); S.set_sel([])
	group_btn(1, false); print("INPUT group 2 select: ", S.sel.size(), " of ", rifles.size())
	V.center_on(D.WW / 2.0, D.WH / 2.0); group_btn(1, false)
	print("INPUT group 2 recentre: cam ", Vector2(V.cam_x, V.cam_y), " group at ", Vector2(rifles[0].x, rifles[0].y))
	click_item("bld", "power"); S.step(0.5)
	if U.panel_open: toggle_panel()
	toggle_big_map(); refresh_panel(true); render_mini()
	await get_tree().create_timer(0.3).timeout
	print("INPUT chips: ", U.prod_chips.keys().filter(func(c): return U.prod_chips[c].visible))
	await _shot(OS.get_environment("AF_SHOT") + "/04_chips_map_groups.png")
	toggle_big_map(); toggle_panel()
