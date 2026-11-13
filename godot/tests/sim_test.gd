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
	get_tree().quit()
