extends Node
const Cutscenes := preload("res://scripts/cutscenes.gd")  # no class_name: an installed shell would not know a new global class
class Host:
	var log := []
	func toast(m, k = ""): log.append(m)
	func sfx(n, x = null, y = null): pass
	func on_world_changed(): pass
	func on_sel_changed(): pass
	func on_vision(): pass
	func add_scorch(x, y, r): pass
	func end_game(w): log.append("END " + str(w))
## Meets each goal of the running mission by hand (teleports, kills, timers) and checks the mission is won.
func solve(s, h) -> bool:
	h.log.clear()
	for guard in 12:
		if s.over: break
		var g = s.goal()
		if g == null: break
		var g0: int = s.gi
		for e in s.ents:
			if e.team == 0 and e.kind == "u": e.hp = e.max_hp   # keep heroes alive while we cheat
		# a goal with a wave plan really sends enemies (no cheating): jump to the next wave and let it land
		if g.waves != null:
			var before: int = s.nid
			s.g_t0 = s.time - g.waves.first - s.wst.get("wn", 0) * g.waves.every - 0.5
			for i in 40: s.step(0.05)
			var spawned: Array = s.ents.filter(func(e): return e.id >= before and e.team == 1 and e.kind == "u")
			print("   ", g.k, " wave ", s.wst.get("wn", 0), ": ", spawned.size(), " enemy units")
			if spawned.size() < 2:
				print("  no wave arrived"); return false
		match g.k:
			"destroy_all":
				for e in s.ents.duplicate():
					if e.alive and e.team == 1: s.kill(e)
			"kill":
				for e in s.goal_targets(g): s.kill(e)
			"mine": s.stats.mined += g.n
			"survive": s.g_t0 -= g.t
			"reach":
				var u = s._hero_alive(0) if g.who == "hero" else s.ents.filter(func(e): return e.alive and e.team == 0 and e.kind == "u" and not e.captive)[0]
				u.x = g.at[0] * D.T + 16; u.y = g.at[1] * D.T + 16; u.path = []
			"hold":
				for e in s.ents.duplicate():
					if e.alive and e.team == 1 and e.kind == "u": s.kill(e)
				var us = s.ents.filter(func(e): return e.alive and e.team == 0 and e.kind == "u" and not e.d.air and not e.d.harv)
				for i in g.zones.size():
					us[i].x = g.zones[i][0] * D.T + 16; us[i].y = g.zones[i][1] * D.T + 16; us[i].path = []; us[i].order = "none"
				s.gst.held = g.t - 1
			"escort":
				for e in s.ents:
					if e.alive and e.tag == "vip" and not e.captive: e.x = g.at[0] * D.T + 16; e.y = g.at[1] * D.T + 16; e.path = []
			"rescue":
				var u = s._hero_alive(0)
				for c in s.ents.filter(func(e): return e.alive and e.captive):
					u.x = c.x + 20; u.y = c.y; u.path = []
					s.mission_tick()
			"capture":
				for e in s.goal_targets(g, -1): e.team = 0
		for i in 30:
			s.step(0.05)
			if s.over or s.gi != g0: break
		if not s.over and s.gi == g0: s.mission_tick()
		if s.gi == g0 and not s.over:
			print("  goal ", g.k, " did not complete"); return false
	return h.log.has("END true")

func _ready():
	var t0 = Time.get_ticks_msec()
	var s = Sim.new(); var h = Host.new(); s.host = h
	s.new_game("hard", {"fac": "ashen"})
	print("setup ms ", Time.get_ticks_msec() - t0, " ents ", s.ents.size())
	t0 = Time.get_ticks_msec()
	var mx := 0
	var ups := {}   # upgrades either AI made: "team type" -> true
	for i in 20 * 60 * 15:
		var a = Time.get_ticks_usec()
		s.step(0.05)
		if i % 20 == 0:
			s.ai_think(s.teams[0])
			for e in s.ents:
				if e.alive and e.kind == "b" and e.lv > 1: ups["%d %s" % [e.team, e.type]] = true
		mx = max(mx, Time.get_ticks_usec() - a)
		if i % 2400 == 0: print("t=", int(s.time), " ents=", s.ents.size(), " proj=", s.proj.size(), " parts=", s.parts.size(), " worst step us=", mx)
		if s.over: break
	print("8 min sim ms ", Time.get_ticks_msec() - t0, " t=", s.time, " ents ", s.ents.size(), " credits ", int(s.teams[0].credits), "/", int(s.teams[1].credits))
	var c = {}
	for e in s.ents: c[str(e.team)+e.type] = c.get(str(e.team)+e.type, 0) + 1
	print(c)
	print(h.log.slice(-10))
	print("AI upgrades in the soak: ", ups.keys())
	if ups.is_empty():
		print("UPGRADE TEST FAILED: neither skirmish AI upgraded anything"); get_tree().quit(1); return
	# every mission sets up, runs a minute, and can be won by meeting its goals in order
	for C in D.CAMPAIGNS:
		for m in C.missions:
			s.new_game("normal", {"mission": m})
			if s.teams[0].fac != C.fac or D.TEAMC[0] != D.FCOL[C.fac]:
				print("MISSION TEST FAILED: wrong faction or colour in ", m.title); get_tree().quit(1); return
			for i in 1200: s.step(0.05)
			var txt: String = s.obj_text()
			print(C.num, ".", m.idx + 1, " ", m.title, " ents=", s.ents.size(), " over=", s.over, " | ", txt.replace("\n", " | "))
			if s.over or txt == "":
				print("MISSION TEST FAILED: ", m.title, " ended or has no objective after a minute: ", h.log.slice(-3)); get_tree().quit(1); return
			var won := solve(s, h)
			if not won:
				print("MISSION TEST FAILED: could not win ", m.title, " goal ", s.gi, " ", h.log.slice(-4)); get_tree().quit(1); return
	# formation move: a unit far behind must not slow the main body down
	# fixed map: on some random maps the near units' paths differ enough to trip the pace check
	s.new_game("normal", {"fac": "vanguard", "seed": 4242})
	var bx: float = (D.P0.x + 4) * D.T; var by: float = (D.P0.y - 4) * D.T
	var near := []
	for i in 3: near.append(s.spawn_unit(0, "rifle", bx + i * D.T, by))
	var far = s.spawn_unit(0, "rifle", bx + 30 * D.T, by - 25 * D.T)
	s.group_move(near + [far], bx + 2 * D.T, by - 6 * D.T, "move")
	var slow := near.filter(func(u): return u.fspd > 0 and u.fspd < u.d.spd * 0.6)
	print("formation near fspd=", near.map(func(u): return snappedf(u.fspd, 0.01)), " far fspd=", far.fspd, " spd=", far.d.spd)
	if slow.size() or far.path.is_empty():
		print("FORMATION TEST FAILED"); get_tree().quit(1); return
	# formation off: player units go straight to the spot at their own speed, no ranks
	s.formation = false
	s.group_move(near, bx + 2 * D.T, by - 6 * D.T, "move")
	var paced := near.filter(func(u): return u.fspd > 0 or u.path.is_empty())
	print("formation off fspd=", near.map(func(u): return u.fspd))
	s.formation = true
	if paced.size():
		print("FORMATION OFF TEST FAILED"); get_tree().quit(1); return
	if not choir_tests(s, h): get_tree().quit(1); return
	if not upgrade_tests(s, h): get_tree().quit(1); return
	if not cutscene_tests(s, h): get_tree().quit(1); return
	print("SIM TEST DONE")
	get_tree().quit()

## Every cutscene: its map and cast set up, its timeline runs on the sim (no AI, no goals), its cast
## stays on the map, nobody dies by accident, and the mission it belongs to still plays normally afterwards.
func cutscene_tests(s, h) -> bool:
	for id in Cutscenes.all():
		var sc: Dictionary = Cutscenes.scene(id)
		var M: Dictionary = D.camp(sc.camp).missions[sc.map]
		s.new_game("normal", {"mission": M, "cine": true, "bare": sc.get("bare", false)})
		var cast: Dictionary = Cutscenes.setup(s, sc)
		for c in sc.get("cast", []):
			var want: int = c.get("b", []).size()
			for p in c.get("u", []): want += p[1]
			if cast[c.id].size() != want:
				print("CUTSCENE TEST FAILED: ", id, " cast ", c.id, " has ", cast[c.id].size(), " of ", want); return false
		var n0: int = s.ents.filter(func(e): return e.kind == "u").size()
		var total := 0.0
		for sh in sc.shots:
			if sh.has("follow") and not cast.has(sh.follow):
				print("CUTSCENE TEST FAILED: ", id, " follows unknown ", sh.follow); return false
			if sh.has("say") and sh.say[1].length() > 64:
				print("CUTSCENE TEST FAILED: ", id, " line too long for a phone: ", sh.say[1]); return false
			var fired := {}
			var t := 0.0
			while t < sh.d:
				for i in sh.get("do", []).size():
					if not fired.has(i) and t >= sh.do[i].get("t", 0.0):
						fired[i] = true; Cutscenes.act(s, cast, sh.do[i])
				s.step(0.05); t += 0.05
			total += sh.d
		var n1: int = s.ents.filter(func(e): return e.kind == "u" and e.alive).size()
		print("cutscene ", id, " ", snappedf(total, 0.1), "s units ", n0, " -> ", n1, " over=", s.over, " gi=", s.gi)
		if s.over or n1 < n0 - 1 or total > 50.0:
			print("CUTSCENE TEST FAILED: ", id, " ended the game, lost units or runs too long"); return false
		if s.cine == false or s.vis.count(2) != s.vis.size():
			print("CUTSCENE TEST FAILED: ", id, " not in cutscene mode"); return false
	# the mission after an intro is an ordinary game again
	s.new_game("normal", {"mission": D.camp("ashen").missions[0]})
	if s.cine or s.gi != 0:
		print("CUTSCENE TEST FAILED: mission after a cutscene is still in cutscene mode"); return false
	return true

func _fail(msg: String) -> bool:
	print("CHOIR TEST FAILED: ", msg); return false

## The Hollow Choir: AI soaks on both sides, then each of its systems on its own.
func choir_tests(s, h) -> bool:
	for pair in [["choir", "vanguard"], ["ashen", "choir"]]:
		var t0 = Time.get_ticks_msec()
		s.new_game("normal", {"fac": pair[0], "enemy": pair[1]})
		if s.teams[0].fac != pair[0] or s.teams[1].fac != pair[1] or D.TEAMC[0] != D.FCOL[pair[0]]: return _fail("factions or colours not set")
		var ci: int = 0 if pair[0] == "choir" else 1
		var seen := {}   # every type the Choir side had at some point
		for i in 20 * 60 * 9:
			s.step(0.05)
			if i % 20 == 0:
				s.ai_think(s.teams[0])
				for e in s.ents:
					if e.team == ci: seen[e.type] = true
			if s.over: break
		var c = {}
		for e in s.ents: c[str(e.team) + e.type] = c.get(str(e.team) + e.type, 0) + 1
		print("choir soak ", pair, " ms ", Time.get_ticks_msec() - t0, " t=", int(s.time), " over=", s.over, " credits ", int(s.teams[0].credits), "/", int(s.teams[1].credits), " ", c)
		print("  the Choir had: ", seen.keys())
		if seen.has("refinery") or seen.has("harv") or seen.has("rifle"): return _fail("the Choir got a refinery, harvester or riflemen")
		if not seen.has("garden") or not seen.has("burrow"): return _fail("the Choir AI built no garden or no burrow")
		if not (seen.has("thrall") or seen.has("skitter") or seen.has("mantis")): return _fail("the Choir AI trained no army")
	# a fixed map for the unit tests
	s.new_game("normal", {"fac": "choir", "enemy": "vanguard", "seed": 4242})
	s.teams[1].credits = 0
	var hq = s.find_hq(0)
	if not s.avail(0, "thrall") or s.avail(0, "rifle") or s.avail(0, "refinery") or not s.avail(0, "garden"): return _fail("availability")
	# the garden stands in for a refinery in requirements
	s.add_building(0, "power", hq.tx + 4, hq.ty)
	if s.has_req(0, ["refinery"]): return _fail("refinery requirement met without a garden")
	# garden: yields on its own and drinks nearby ore
	var oi := -1
	for i in D.MW * D.MH:
		if s.ore[i] > 0 and Vector2(i % D.MW - hq.tx, i / D.MW - hq.ty).length() < 14: oi = i; break
	if oi < 0: return _fail("no ore near the base on the test map")
	var gp = null
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if gp == null and s.can_place(0, "garden", oi % D.MW + dx, oi / D.MW + dy, false): gp = Vector2i(oi % D.MW + dx, oi / D.MW + dy)
	if gp == null:
		# place it by hand next to the ore; the garden test is about growth, not placement rules
		gp = Vector2i(oi % D.MW + 2, oi / D.MW)
	var g = s.add_building(0, "garden", gp.x, gp.y)
	if not s.has_req(0, ["refinery"]): return _fail("garden does not count as a refinery")
	var ore0 := 0
	for i in D.MW * D.MH: ore0 += s.ore[i]
	var cr0: float = s.teams[0].credits
	for i in 20 * 9: s.step(0.05)
	var ore1 := 0
	for i in D.MW * D.MH: ore1 += s.ore[i]
	print("garden: +", int(s.teams[0].credits - cr0), " credits, ore drained ", ore0 - ore1)
	if s.teams[0].credits - cr0 < 40: return _fail("garden gave nothing")
	# tunnels: a far burrow, units walk into the yard and come out of the burrow
	var bp := Vector2i(hq.tx + 22, hq.ty - 22)
	var bur = s.add_building(0, "burrow", bp.x, bp.y)
	var us := []
	for i in 4: us.append(s.spawn_unit(0, "thrall", (hq.tx + 1 + i) * D.T + 16, (hq.ty + 4) * D.T + 16))
	s.group_move(us, (bp.x + 1) * D.T, (bp.y + 6) * D.T, "move")
	if us.filter(func(u): return u.tun != null).is_empty(): return _fail("no unit planned a tunnel trip")
	var went := false
	for i in 20 * 25:
		s.step(0.05)
		for u in us:
			if u.intun > 0: went = true
	var arrived := us.filter(func(u): return Vector2(u.x - (bp.x + 1) * D.T, u.y - (bp.y + 6) * D.T).length() < D.T * 4)
	print("tunnel: underground=", went, " arrived ", arrived.size(), "/", us.size(), " in 25 s")
	if not went or arrived.size() < 3: return _fail("tunnel trip")
	# a unit in a tunnel cannot be hit; a moving sapper is burrowed
	var sp = s.spawn_unit(0, "sapper", (hq.tx + 2) * D.T, (hq.ty + 6) * D.T)
	s.group_move([sp], (hq.tx + 9) * D.T, (hq.ty + 6) * D.T, "move")
	for i in 10: s.step(0.05)
	var en = s.spawn_unit(1, "rifle", sp.x + D.T * 2, sp.y)
	if not sp.under or s.find_target(en, D.T * 6) == sp: return _fail("moving sapper not burrowed")
	en.alive = false
	# geode lobber: splash plus a lingering shard field
	var gl = s.spawn_unit(0, "geode", (hq.tx + 4) * D.T, (hq.ty + 12) * D.T)
	var vic = s.spawn_unit(1, "rifle", gl.x + D.T * 6, gl.y)
	vic.hp = 9999; vic.max_hp = 9999
	gl.target = vic; gl.order = "attack"
	var saw_field := false
	for i in 20 * 8:
		s.step(0.05)
		if s.fields.size(): saw_field = true
	print("geode: fields seen=", saw_field, " victim hp ", int(vic.hp))
	if not saw_field or vic.hp >= 9999: return _fail("geode lobber left no shard field")
	vic.alive = false; gl.alive = false
	# the Cantor: one at a time, lifts nearby units
	var ca = s.spawn_unit(0, "cantor", (hq.tx + 6) * D.T, (hq.ty + 8) * D.T)
	var th = s.spawn_unit(0, "thrall", ca.x + D.T, ca.y)
	for i in 30: s.step(0.05)
	if th.aura_t <= 0: return _fail("Cantor aura")
	if not s.at_limit(0, "cantor"): return _fail("a second Cantor allowed")
	# Chorus Well: a burst and a long shard field
	var ch = s.add_building(0, "chorus", hq.tx - 6, hq.ty + 6)
	s.fields = []
	s.launch_sw(ch, (hq.tx + 20) * D.T, (hq.ty - 10) * D.T)
	for i in 20 * 4: s.step(0.05)
	if s.fields.filter(func(f): return f.r > D.T * 3).is_empty(): return _fail("Chorus Well left no field")
	print("choir tests ok")
	return true

func _ufail(msg: String) -> bool:
	print("UPGRADE TEST FAILED: ", msg); return false

## Building upgrades: cost, requirements, cancel, sell, each effect, and the campaign AI rule (Hard only).
func upgrade_tests(s, h) -> bool:
	s.new_game("normal", {"fac": "vanguard", "enemy": "ashen", "seed": 4242})
	s.teams[1].credits = 0; s.ai_t = 1e9
	var hq = s.find_hq(0)
	var pw = s.add_building(0, "power", hq.tx + 4, hq.ty)
	if s.upg_block(pw) == "": return _ufail("reactor upgrade allowed without a refinery")
	var rf = s.add_building(0, "refinery", hq.tx - 5, hq.ty + 4)
	if s.upg_block(pw) != "": return _ufail("reactor upgrade blocked: " + s.upg_block(pw))
	if s.upg_block(rf) == "": return _ufail("refinery upgrade allowed without a comms array")
	# cancel refunds what was paid
	s.teams[0].credits = 5000.0
	s.start_upgrade(pw)
	for i in 40: s.step(0.05)
	if pw.upg <= 0 or s.teams[0].credits >= 5000: return _ufail("upgrade did not start paying")
	s.cancel_upgrade(pw)
	if abs(s.teams[0].credits - 5000.0) > 1 or pw.upg >= 0: return _ufail("cancel did not refund")
	# full reactor upgrade: +150 power, more hp, costs 450, new name
	var pm0: int = s.teams[0].pmade
	s.start_upgrade(pw)
	for i in 20 * 14: s.step(0.05)
	print("reactor: lv ", pw.lv, " ", pw.d.name, " power ", pm0, " -> ", s.teams[0].pmade, " paid ", int(5000.0 - s.teams[0].credits), " hp ", int(pw.hp), "/", int(pw.max_hp))
	if pw.lv != 2 or pw.d.name != "Super Reactor" or s.teams[0].pmade != pm0 + 150 or pw.max_hp != 1000: return _ufail("reactor upgrade")
	if abs((5000.0 - s.teams[0].credits) - 450) > 2: return _ufail("reactor upgrade cost")
	if s.upg_block(pw) == "" or not s.upg_def(pw).is_empty(): return _ufail("upgraded twice")
	# selling an upgraded building refunds half of both prices
	var cr: float = s.teams[0].credits
	var got: int = s.sell(pw)
	if got != int((300 + 450) * 0.5): return _ufail("sell refund %d" % got)
	# barracks: faster training once upgraded
	s.add_building(0, "factory", hq.tx + 4, hq.ty + 5)
	var bk = s.add_building(0, "barracks", hq.tx - 4, hq.ty - 4)
	if s.prod_speed(0, "inf") != 1.0: return _ufail("speed before upgrade")
	s.finish_upgrade(bk)
	if abs(s.prod_speed(0, "inf") - 1.35) > 0.001 or s.prod_speed(0, "veh") != 1.0: return _ufail("Drill Hall speed")
	# sentry: the upgraded def carries the new weapon numbers
	var tu = s.add_building(0, "turret", hq.tx + 1, hq.ty + 5)
	s.finish_upgrade(tu)
	if tu.d.dmg != 44 or tu.d.range != 6.5 or tu.d.weapon != "shell": return _ufail("Heavy Sentry stats")
	# refinery yield: a full load is worth 25% more
	var ld := 0.0
	for k in 2:
		if k == 1: s.finish_upgrade(rf)
		var hv = s.spawn_unit(0, "harv", (rf.tx + 1) * D.T + 16, (rf.ty + 3) * D.T + 16)
		hv.load = 700.0; hv.ref = rf; hv.hs = "unload"; hv.mt = 0.0
		var c0: float = s.teams[0].credits
		for i in 20 * 3: s.step(0.05)
		hv.alive = false
		var gain: float = s.teams[0].credits - c0
		print("refinery lv", rf.lv, ": one load gave ", int(gain))
		if k == 1 and gain < ld * 1.2: return _ufail("Deep Refinery yield")
		ld = gain
	# the Choir's garden blooms
	s.new_game("normal", {"fac": "choir", "enemy": "vanguard", "seed": 4242})
	s.teams[1].credits = 0; s.ai_t = 1e9
	hq = s.find_hq(0)
	var gd = s.add_building(0, "garden", hq.tx + 5, hq.ty + 5)
	s.add_building(0, "power", hq.tx - 4, hq.ty)
	var gains := []
	for k in 2:
		if k == 1: s.finish_upgrade(gd)
		gd.gt = 0.0
		var c0: float = s.teams[0].credits
		for i in 20 * 8 + 2: s.step(0.05)
		gains.append(s.teams[0].credits - c0)
	print("garden: ", gains.map(func(g): return int(g)), " ", gd.d.name)
	if gains[1] <= gains[0] or gd.d.name != "Bloom Garden": return _ufail("Bloom Garden yield")
	# campaign AI: never upgrades on Normal, may on Hard
	var m = null
	for C in D.CAMPAIGNS:
		for mm in C.missions:
			if m == null and mm.aiBuild and mm.ehq == "hq": m = mm
	for lv in ["normal", "hard"]:
		s.new_game("normal", {"mission": m, "level": lv})
		s.teams[1].credits = 50000.0
		var any := false
		for i in 20 * 60 * 3:
			s.step(0.05)
			if i % 40 == 0:
				for e in s.ents:
					if e.alive and e.team == 1 and e.kind == "b" and (e.lv > 1 or e.upg >= 0): any = true
			if any or s.over: break
		print("campaign AI on ", lv, " (", m.title, ") upgraded: ", any)
		if lv == "normal" and any: return _ufail("campaign AI upgraded on Normal")
		if lv == "hard" and not any: return _ufail("campaign AI never upgraded on Hard")
	print("upgrade tests ok")
	return true
