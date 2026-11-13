extends Node
class Host:
	var log := []
	func toast(m, k = ""): log.append(m)
	func sfx(n, x = null, y = null): pass
	func on_world_changed(): pass
	func on_sel_changed(): pass
	func on_vision(): pass
	func add_scorch(x, y, r): pass
	func end_game(w): log.append("END " + str(w))
func _ready():
	var t0 = Time.get_ticks_msec()
	var s = Sim.new(); var h = Host.new(); s.host = h
	s.new_game("hard", {"fac": "ashen"})
	print("setup ms ", Time.get_ticks_msec() - t0, " ents ", s.ents.size())
	t0 = Time.get_ticks_msec()
	var mx := 0
	for i in 20 * 60 * 15:
		var a = Time.get_ticks_usec()
		s.step(0.05)
		if i % 20 == 0: s.ai_think(s.teams[0])
		mx = max(mx, Time.get_ticks_usec() - a)
		if i % 2400 == 0: print("t=", int(s.time), " ents=", s.ents.size(), " proj=", s.proj.size(), " parts=", s.parts.size(), " worst step us=", mx)
		if s.over: break
	print("8 min sim ms ", Time.get_ticks_msec() - t0, " t=", s.time, " ents ", s.ents.size(), " credits ", int(s.teams[0].credits), "/", int(s.teams[1].credits))
	var c = {}
	for e in s.ents: c[str(e.team)+e.type] = c.get(str(e.team)+e.type, 0) + 1
	print(c)
	print(h.log.slice(-10))
	for m in D.MISSIONS:
		s.new_game("normal", {"mission": m}); for i in 200: s.step(0.05)
		print(m.title, " ", s.ents.size(), " ", s.obj_text())
	# formation move: a unit far behind must not slow the main body down
	s.new_game("normal", {"fac": "vanguard"})
	var bx: float = (D.P0.x + 4) * D.T; var by: float = (D.P0.y - 4) * D.T
	var near := []
	for i in 3: near.append(s.spawn_unit(0, "rifle", bx + i * D.T, by))
	var far = s.spawn_unit(0, "rifle", bx + 30 * D.T, by - 25 * D.T)
	s.group_move(near + [far], bx + 2 * D.T, by - 6 * D.T, "move")
	var slow := near.filter(func(u): return u.fspd > 0 and u.fspd < u.d.spd * 0.6)
	print("formation near fspd=", near.map(func(u): return snappedf(u.fspd, 0.01)), " far fspd=", far.fspd, " spd=", far.d.spd)
	if slow.size() or far.path.is_empty():
		print("FORMATION TEST FAILED"); get_tree().quit(1); return
	print("SIM TEST DONE")
	get_tree().quit()
