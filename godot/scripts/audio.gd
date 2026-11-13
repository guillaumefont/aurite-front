class_name GameAudio
extends Node
## Pre-rendered synth effects (with reverb baked in) and a two-layer march that follows the fighting.

const MINGAP := {"gun": .06, "snipe": .1, "small": .07, "shell": .08, "heavy": .1, "mortar": .12, "rocket": .09, "flak": .1, "flame": .12, "arc": .1, "boom": .1, "bigboom": .15, "click": .03, "ack": .12, "ready": .3, "alert": 1.0, "place": .2, "siren": 2.0}
const NAMES := ["gun", "snipe", "shell", "heavy", "mortar", "rocket", "flak", "flame", "arc", "small", "boom", "bigboom", "click", "ack", "ack_ashen", "ready", "alert", "place", "siren"]

var streams := {}
var pool: Array = []
var pi := 0
var last := {}
var muted := false
var music_on := true
var calm: AudioStreamPlayer
var combat: AudioStreamPlayer
var music_level := 0.0
var music_target := 0.0
var intensity := 0.0
var pan_bus := ["SfxL", "SfxC", "SfxR"]

func _ready() -> void:
	for i in 3:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx); AudioServer.set_bus_name(idx, pan_bus[i]); AudioServer.set_bus_send(idx, "Master")
		var p := AudioEffectPanner.new(); p.pan = [-0.55, 0.0, 0.55][i]
		AudioServer.add_bus_effect(idx, p)
	var mi := AudioServer.bus_count
	AudioServer.add_bus(mi); AudioServer.set_bus_name(mi, "Music"); AudioServer.set_bus_send(mi, "Master")
	var lim := AudioEffectLimiter.new(); AudioServer.add_bus_effect(0, lim)
	for n in NAMES:
		var path := "res://sfx/%s.wav" % n
		if ResourceLoader.exists(path): streams[n] = load(path)
	for i in 18:
		var p := AudioStreamPlayer.new(); add_child(p); pool.append(p)
	calm = AudioStreamPlayer.new(); calm.bus = "Music"; add_child(calm)
	combat = AudioStreamPlayer.new(); combat.bus = "Music"; add_child(combat)
	if ResourceLoader.exists("res://music/march_calm.ogg"):
		calm.stream = load("res://music/march_calm.ogg"); combat.stream = load("res://music/march_combat.ogg")
		calm.stream.loop = true; combat.stream.loop = true
	calm.volume_db = -80; combat.volume_db = -80

func play(n: String, pan := 0.0, vol := 1.0) -> void:
	if muted: return
	var now := Time.get_ticks_msec() / 1000.0
	if last.has(n) and now - last[n] < MINGAP.get(n, .05): return
	last[n] = now
	if not streams.has(n): return
	var p: AudioStreamPlayer = pool[pi]; pi = (pi + 1) % pool.size()
	p.stream = streams[n]
	p.bus = pan_bus[0] if pan < -0.33 else (pan_bus[2] if pan > 0.33 else pan_bus[1])
	p.volume_db = linear_to_db(max(0.001, vol * 0.75))
	p.play()

func music_start() -> void:
	if not music_on or calm.stream == null: return
	if not calm.playing:
		calm.play(); combat.play()
	music_target = 1.0

func music_stop() -> void:
	music_target = 0.0

func _process(dt: float) -> void:
	music_level = move_toward(music_level, music_target, dt * (0.6 if music_target > music_level else 1.5))
	if calm.playing:
		var w := clampf(intensity * 1.6 - 0.15, 0.0, 1.0)
		calm.volume_db = linear_to_db(max(0.0001, music_level * 0.8 * (1.0 - w * 0.6)))
		combat.volume_db = linear_to_db(max(0.0001, music_level * 0.85 * w))
		# keep the two layers locked together
		if abs(combat.get_playback_position() - calm.get_playback_position()) > 0.08 and calm.get_playback_position() > 0.2:
			combat.seek(calm.get_playback_position())
		if music_level <= 0.0 and music_target <= 0.0:
			calm.stop(); combat.stop()

func set_paused(p: bool) -> void:
	calm.stream_paused = p; combat.stream_paused = p
