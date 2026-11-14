extends Node
## Game shell: owns the simulation, the 3D view, the UI and audio; handles input and game flow.

const T := 32

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
var last_opt := {"fac": "vanguard"}
var cur_tab := "bld"
var brief_i := 0
var icons_for := ""
var headless := false

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

func _ready() -> void:
	headless = DisplayServer.get_name() == "headless"
	randomize()
	S = Sim.new(); S.host = self
	V = View3D.new(); V.S = S; add_child(V)
	V.panel_px = UI.PANEL_W
	var layer := CanvasLayer.new(); add_child(layer)
	U = UI.new(); U.main = self; layer.add_child(U); U.build()
	A = GameAudio.new(); add_child(A)
	U.set_tab("bld")
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
	if n == "ack" and S.teams.size() and S.teams[0].fac == "ashen": n = "ack_ashen"
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
	if M and win: camp_save(M.idx)
	U.btn.next.visible = M != null and win and M.idx < D.MISSIONS.size() - 1
	U.btn.again.text = ("REPLAY" if win else "RETRY") if M else "PLAY AGAIN"
	A.music_stop()
	U.set_end_stats([["Time", D.fmt(S.time)], ["Aurite mined", Sim._thousands(S.stats.mined)], ["Units trained", S.stats.built], ["Enemies destroyed", S.stats.killed], ["Losses", S.stats.lost]])
	get_tree().create_timer(1.2).timeout.connect(func(): U.show_overlay("end"))
	A.play("ready" if win else "alert")

# ---------------- game flow ----------------
func camp_prog() -> int:
	if not FileAccess.file_exists("user://camp.json"): return 0
	var f := FileAccess.open("user://camp.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	return int(d.get("done", 0)) if d is Dictionary else 0

func camp_save(i: int) -> void:
	var f := FileAccess.open("user://camp.json", FileAccess.WRITE)
	if f: f.store_string(JSON.stringify({"done": max(camp_prog(), i + 1)}))

func show_start() -> void:
	U.render_missions(camp_prog())
	U.show_overlay("start")
	paused = true
	A.music_stop()

func open_brief(i: int) -> void:
	brief_i = i
	var m: Dictionary = D.MISSIONS[i]
	U.btn.br_eye.text = ("Mission %d of %d" % [i + 1, D.MISSIONS.size()]).to_upper()
	U.btn.br_title.text = m.title.to_upper()
	U.btn.br_text.text = m.brief
	U.btn.br_obj.text = "\n".join(m.obj.map(func(o): return "•  " + o))
	U.show_overlay("brief")

func begin_mission() -> void:
	play({"mission": D.MISSIONS[brief_i]})

func next_mission() -> void:
	open_brief(min(D.MISSIONS.size() - 1, brief_i + 1))

func play(opt: Dictionary) -> void:
	last_opt = opt
	U.show_overlay("")
	new_game(opt.get("diff", diff), opt)
	paused = false
	A.set_paused(false)

func new_game(d: String, opt: Dictionary) -> void:
	placing = null; amove = false; box_mode = false; sw_aim = false; gest = null; ptrs.clear()
	S.new_game(d, opt)
	diff = S.diff
	V.build_world()
	S.update_vision()
	V.cam_z = 1.0
	V.center_on(D.P0.x * T + 16, (D.P0.y - 1) * T)
	if icons_for != S.teams[0].fac and not headless: render_icons(S.teams[0].fac)
	select_tab("bld"); refresh_panel(true); update_cmd(); end_placing()
	U.obj_box.visible = S.mission != null
	if S.mission: toast(S.mission.title, "gold")
	else:
		toast("Tap the round button to box-select units", "gold")
		get_tree().create_timer(3.5).timeout.connect(func(): if S.time < 20 and not S.over: toast("Build a Reactor, then a Refinery", "gold"))
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
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if U.overlays.menu.visible: resume()
		elif U.overlays.brief.visible: show_start()
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
		toast("Requires " + " + ".join(d.req.map(func(r): return D.BLD[r].name)), "warn"); return
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
		var locked: bool = not S.has_req(0, d.req) or (it.cat != "bld" and S.count(0, D.PRODUCER[it.cat]) == 0)
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

func hud_tick(dt: float) -> void:
	var tm: Dictionary = S.teams[0]
	shown_cr += (tm.credits - shown_cr) * min(1.0, dt * 8)
	if abs(tm.credits - shown_cr) < 1: shown_cr = tm.credits
	U.credits_l.text = Sim._thousands(int(shown_cr))
	U.power_l.text = "%d / %d" % [tm.pmade, tm.pused]
	var lp := S.low_power(0)
	U.power_bar.size.x = 84.0 * min(1.0, float(tm.pused) / tm.pmade if tm.pmade else 1.0)
	U.power_bar.color = UI.C_BAD if lp else UI.C_OK
	U.power_l.add_theme_color_override("font_color", UI.C_BAD if lp else UI.C_FG)
	panel_t -= dt
	if panel_t <= 0: panel_t = .12; refresh_panel()
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
	var a := S.ents.filter(func(e): return e.alive and e.kind == "u" and e.team == 0 and not e.d.harv and not e.d.eng and (k == "all" or ((e.order == "none" and e.target == null) if k == "idle" else e.d.cat == k)))
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
			if e.kind == "b": U.selinfo.text = d.name.replace(" ×4", "") + (" · tap map to set rally" if (e.type == "barracks" or e.type == "factory") else (" · park vehicles beside it" if e.type == "repair" else ""))
			else: U.selinfo.text = d.name + (" · tap aurite to mine" if d.harv else (" · tap a building to capture or fix" if d.eng else (" · heals nearby infantry" if d.heal else (" · long range, blind up close" if d.minr > 0 else ""))))
		else: U.selinfo.text = "%d units" % S.sel.size()
	else: U.selinfo.visible = false

func ring(x: float, y: float, c: Color) -> void:
	S.parts.append({"k": "ring", "x": x, "y": y, "life": .5, "max": .5, "c": c})

# ---------------- picking ----------------
func pick(sx: float, sy: float, wx: float, wy: float) -> Ent:
	V.update_cam()
	var best: Ent = null; var bd := 1e9
	for e in S.ents:
		if not e.alive or e.kind != "u": continue
		if e.team != 0 and not S.visible_to_player(e): continue
		var h: float = S.h_at(e.x, e.y) + (D.ALT if e.d.air else 0.0)
		var p := V.w2s(e.x, e.y, h + D.UH[e.type] * .45)
		if p.z < 0: continue
		var q := V.w2s(e.x + T, e.y, h); var o := V.w2s(e.x, e.y, h); var ppt: float = abs(q.x - o.x)
		var rad: float = max(22.0, e.r / T * ppt * 1.4); var dd := Vector2(p.x - sx, p.y - sy).length()
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
		amove = false; update_cmd(); return
	var ti := clampi(int(wy / T), 0, 63) * 64 + clampi(int(wx / T), 0, 63)
	if harvs.size() and S.ore[ti] > 0:
		for h in harvs: h.pref = ti; h.hs = "find"
		ring(wx, wy, Color("f0b93f"))
	elif harvs.size(): S.group_move(harvs, wx, wy, "move")
	if combat.size() or others.size():
		S.group_move(combat + others, wx, wy, "amove" if (amove and combat.size()) else "move", face, width)
		ring(wx, wy, Color("ff5a52") if amove else Color("7fd68e"))
	sfx("ack"); amove = false; update_cmd()

func box_select(x0: float, y0: float, x1: float, y1: float) -> void:
	V.update_cam()
	var r := Rect2(Vector2(min(x0, x1), min(y0, y1)), Vector2(abs(x1 - x0), abs(y1 - y0))).grow(6)
	var us := S.ents.filter(func(e):
		if not e.alive or e.kind != "u" or e.team != 0: return false
		var p := V.w2s(e.x, e.y, S.h_at(e.x, e.y) + .2 + (D.ALT if e.d.air else 0.0))
		return p.z > 0 and r.has_point(Vector2(p.x, p.y)))
	var cb := us.filter(func(u): return not u.d.harv)
	if cb.size(): us = cb
	S.set_sel(us)
	if us.size(): sfx("click")

# ---------------- input ----------------
func _in_view(p: Vector2) -> bool:
	return V.view_rect().has_point(p)

func _unhandled_input(ev: InputEvent) -> void:
	if S.teams.is_empty() or paused: return
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
		gest = {"mode": "pinch", "d0": max(1.0, a.distance_to(b)), "z0": V.cam_z, "w": V.s2w(m.x, m.y)}
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
		V.cam_z = gest.z0 * a.distance_to(b) / gest.d0; V.clamp_cam()
		var w2 := V.s2w(m.x, m.y); V.cam_x += gest.w.x - w2.x; V.cam_y += gest.w.y - w2.y; V.clamp_cam()
		return
	var moved: bool = p.distance_to(gest.s) > 9
	if gest.mode == "pending" and moved:
		if gest.mouse: gest.mode = "box"
		elif placing != null: gest.mode = "ghost"
		elif box_mode: gest.mode = "box"
		else: gest.mode = "pan"
	elif gest.mode == "rpending" and moved:
		gest.mode = "face" if (gest.btn == MOUSE_BUTTON_RIGHT and _sel_movers().size() and placing == null) else "pan"
		if gest.mode == "face": gest.from = V.s2w(gest.s.x, gest.s.y)
	elif gest.mode == "lp" and moved:
		if _sel_movers().size() and placing == null:
			gest.mode = "face"; gest.from = V.s2w(gest.s.x, gest.s.y)
		else: gest.mode = "box"
	match gest.mode:
		"pan":
			var a := V.s2w(gest.l.x, gest.l.y); var b := V.s2w(p.x, p.y)
			V.cam_x += a.x - b.x; V.cam_y += a.y - b.y; V.clamp_cam()
		"box": gest.e = p
		"ghost":
			var w := V.s2w(p.x, p.y); var d: Dictionary = D.BLD[placing.type]
			placing.tx = int(round(w.x / T - d.w / 2.0)); placing.ty = int(round(w.y / T - d.h / 2.0))
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
			box_select(gest.s.x, gest.s.y, gest.e.x, gest.e.y)
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
		if not e.alive or not (e.sel or e.hit_t > 0 or (e.kind == "b" and e.repairing)): continue
		if e.team != 0 and not S.visible_to_player(e): continue
		var is_b: bool = e.kind == "b"
		var top: float = D.BH[e.type] + .25 if is_b else D.UH[e.type] + .15 + (D.ALT if e.d.air else 0.0)
		var p := V.w2s(e.x, e.y, S.h_at(e.x, e.y) + top)
		if p.z < 0: continue
		var q := V.w2s(e.x + T, e.y, S.h_at(e.x, e.y) + top); var ppt: float = abs(q.x - p.x)
		var w: float = max(24.0, e.w * ppt * .85) if is_b else max(18.0, e.r / T * 2 * ppt + 8)
		var x := p.x - w / 2; var y := p.y - 4; var fr: float = max(0.0, e.hp / e.max_hp)
		c.draw_rect(Rect2(x - 1, y - 1, w + 2, 5), Color(0, 0, 0, .75))
		c.draw_rect(Rect2(x, y, w * fr, 3), Color("7fd68e") if fr > .6 else (Color("f0c23f") if fr > .3 else Color("ff5a52")))
		if e.kind == "u" and e.d.harv and e.sel:
			c.draw_rect(Rect2(x - 1, y + 4, w + 2, 4), Color(0, 0, 0, .75)); c.draw_rect(Rect2(x, y + 5, w * e.load / D.HARV_CAP, 2), Color("f0b93f"))
		if is_b and e.repairing:
			c.draw_string(U.f_disp7, Vector2(p.x - 5, y - 5 + sin(S.time * 6) * 2), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("7fd68e"))
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
	var vr := V.view_rect()
	if sw_aim: c.draw_string(f, Vector2(max(8.0, vr.size.x / 2 - 90), vr.size.y - 64), "SUPERWEAPON: TAP A TARGET", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(.94, .73, .25, .95))
	elif amove: c.draw_string(f, Vector2(max(8.0, vr.size.x / 2 - 110), vr.size.y - 64), "ATTACK-MOVE: TAP A DESTINATION", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(.9, .28, .25, .95))
	elif gest != null and gest.mode == "face" and pv_from != null: c.draw_string(f, Vector2(max(8.0, vr.size.x / 2 - 110), vr.size.y - 64), "RELEASE TO FORM UP FACING THIS WAY", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(.5, .84, .56, .95))

# ---------------- minimap ----------------
func render_mini() -> void:
	var m = U.mini; var img: Image = m.img
	var data := PackedByteArray(); data.resize(64 * 64 * 4)
	for i in 64 * 64:
		var v: int = S.vis[i]; var k := i * 4
		if v == 0:
			data[k] = 4; data[k + 1] = 6; data[k + 2] = 8; data[k + 3] = 255; continue
		var col: Color = D.TCOL[S.terr[i]] * 0.9
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

func draw_mini_overlay(c: Control) -> void:
	if S.teams.is_empty(): return
	var s := c.size / 64.0
	var vr := V.view_rect()
	var cs := [Vector2(0, 0), Vector2(vr.size.x, 0), Vector2(vr.size.x, vr.size.y), Vector2(0, vr.size.y)].map(func(p): return (V.s2w(p.x, p.y) / T * s).clamp(Vector2.ZERO, c.size))
	cs.append(cs[0])
	c.draw_polyline(PackedVector2Array(cs), Color.WHITE, 1.0)
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

# ---------------- automated screenshot test (AF_SHOT=dir) ----------------
func _autotest(dir: String) -> void:
	await get_tree().create_timer(2.0).timeout
	await _shot(dir + "/00_start.png")
	var mode := OS.get_environment("AF_MODE")
	if mode.begins_with("m"):
		open_brief(int(mode.substr(1)))
		await get_tree().create_timer(0.5).timeout
		await _shot(dir + "/01_brief.png")
		begin_mission()
	elif mode == "b":
		await _bld_test(dir); get_tree().quit(); return
	else:
		play({"fac": "vanguard", "diff": "normal"})
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

## AF_MODE=b: every building model, then the build, sell and collapse animations and a harvester at work.
func _bld_test(dir: String) -> void:
	play({"fac": OS.get_environment("AF_FAC") if OS.get_environment("AF_FAC") != "" else "vanguard", "diff": "normal"})
	paused = true
	var hq: Ent = S.ents.filter(func(e): return e.team == 0 and e.type == "hq")[0]
	var bs: Array = []
	for t in ["power", "refinery", "barracks", "factory", "repair", "helipad", "comms", "tech", "turret", "flak", "bastion", "pylon", "skyfall", "rift"]:
		var bf: String = D.BLD[t].get("fac", "")
		if bf != "" and bf != S.teams[0].fac: continue
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

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path)

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
	# pan
	var cx := V.cam_x
	_touch(0, Vector2(400, 300), true); await get_tree().process_frame
	for k in 5:
		_drag(0, Vector2(400 - 40 * (k + 1), 300)); await get_tree().process_frame
	_touch(0, Vector2(200, 300), false); await get_tree().process_frame
	print("INPUT pan dx=", V.cam_x - cx)
	# pinch
	var z := V.cam_z
	_touch(0, Vector2(300, 300), true); _touch(1, Vector2(500, 300), true); await get_tree().process_frame
	_drag(0, Vector2(250, 300)); _drag(1, Vector2(550, 300)); await get_tree().process_frame
	_touch(0, Vector2(250, 300), false); _touch(1, Vector2(550, 300), false); await get_tree().process_frame
	print("INPUT pinch zoom ", z, " -> ", V.cam_z)
	# build a reactor through the panel
	click_item("bld", "power")
	for i in 20 * 9: S.step(0.05)
	click_item("bld", "power")
	print("INPUT placing=", placing)
	confirm_place()
	print("INPUT reactors=", S.count(0, "power"))
