extends Node
## Self-update ("Updater" autoload, listed FIRST in project.godot).
##
## The APK holds the game as installed. CI also publishes the game as a resource pack
## (aurite-front.pck) and a version.json next to the APK on GitHub Pages. This node checks
## version.json on launch and when the app comes back to the front, downloads a newer pack
## into user://update/ in the background, and at the next launch mounts it over the APK's
## files, before any other game script is loaded (see _init). Saves in user:// are untouched.
##
## A pack only fits the "shell" it was built for: the engine version, project.godot (autoloads,
## settings), the export preset (permissions), this script, the icons and the splash. CI hashes
## those into "shell"; when it changes, the game asks for the new APK instead.
##
## This script is part of the shell, so it must not use any other game script or class:
## it is loaded from the APK before the pack is mounted.

signal changed

const DIR := "user://update/"
const STATE := DIR + "state.json"
const CHECK_EVERY := 300.0  # seconds between checks when the app comes back to the front

var info := {}        # build.json of the APK: build, shell, url, name
var build := 0        # build that is running (the APK's, or the mounted pack's)
var name_ := ""       # version name that is running, like "1.1-b142"
var applied := false  # a downloaded pack is mounted
var status := "idle"  # idle, checking, current, downloading, ready, apk, offline, off
var remote := {}      # version.json of the newer build, when there is one
var progress := 0.0
var enabled := false
var base := ""         # site folder the last check used (the build's own, or the main build's)
var _last_check := -1e9
var _http: HTTPRequest

func _init() -> void:
	info = _read_json("res://build.json")
	build = int(info.get("build", 0)); name_ = str(info.get("name", "dev"))
	var st := _read_json(STATE)
	var pck := DIR + str(st.get("file", ""))
	if st.is_empty():
		return
	# a newer pack for this same shell: mount it over the APK's files
	if int(st.get("build", 0)) > build and st.get("shell", "") == info.get("shell", "-") and FileAccess.file_exists(pck):
		# a pack that crashed the game twice in a row is dropped (back to the APK's version)
		var tries := int(st.get("tries", 0))
		if tries >= 2:
			push_warning("Updater: pack b%d failed to start twice, back to b%d" % [st.build, build])
			_wipe(); return
		st.tries = tries + 1; _write_json(STATE, st)
		if ProjectSettings.load_resource_pack(pck, true):
			applied = true
			build = int(st.build); name_ = str(st.get("name", "b%d" % build))
		else:
			push_warning("Updater: could not mount " + pck); _wipe()
	else:
		_wipe()  # older than (or made for another version of) the installed APK

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_clean_old_packs()
	enabled = info.get("url", "") != "" and int(info.get("build", 0)) > 0 and DisplayServer.get_name() != "headless"
	# AF_UPDATE=1 forces checks (tests, headless), AF_UPDATE=0 turns them off
	if OS.get_environment("AF_UPDATE") != "": enabled = OS.get_environment("AF_UPDATE") == "1" and info.get("url", "") != ""
	if not enabled:
		status = "off"; return
	if applied:
		# the game got this far: the pack is good
		get_tree().create_timer(8.0).timeout.connect(func():
			var st := _read_json(STATE)
			if st.has("tries"): st.erase("tries"); _write_json(STATE, st))
	get_tree().create_timer(1.5).timeout.connect(check)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and enabled and Time.get_ticks_msec() / 1000.0 - _last_check > CHECK_EVERY:
		check()

## What the start screen shows.
func label() -> String:
	var v := "Build %d" % build if build > 0 else "Dev build"
	match status:
		"checking": return v + "  ·  checking for updates"
		"current": return v + ("  ·  updated" if applied else "  ·  up to date")
		"downloading": return "Downloading build %d  ·  %d%%" % [int(remote.get("build", 0)), int(progress * 100)]
		"ready": return "Build %d ready  ·  tap to restart" % int(remote.get("build", 0))
		"apk": return "Build %d needs the new app  ·  tap to get it" % int(remote.get("build", 0))
		"offline": return v + "  ·  offline"
	return v

## Tapping the status: restart into a downloaded update, fetch a needed APK, or check again.
func act() -> void:
	match status:
		"ready": restart()
		"apk": OS.shell_open(base + str(remote.get("apk", "aurite-front.apk")))
		"checking", "downloading", "off": pass
		_: check()

func restart() -> void:
	# Android relaunches the app (Godot kills the process and starts it again)
	OS.set_restart_on_exit(true, PackedStringArray() if OS.has_feature("android") else OS.get_cmdline_args())
	get_tree().quit()

func check() -> void:
	if not enabled or status in ["checking", "downloading", "ready"]:
		return
	_last_check = Time.get_ticks_msec() / 1000.0
	_status("checking")
	# a PR build follows its PR's preview, then the main build once the preview is gone (PR closed)
	base = str(info.url)
	var body = await _fetch(base + "version.json?t=%d" % Time.get_unix_time_from_system())
	if body == null and str(info.get("main_url", "")) not in ["", base]:
		base = str(info.main_url)
		body = await _fetch(base + "version.json?t=%d" % Time.get_unix_time_from_system())
	if body == null:
		_status("offline"); return
	var v = JSON.parse_string(body)
	if not v is Dictionary or not v.has("build"):
		_status("offline"); return
	if int(v.build) <= build:
		_status("current"); return
	remote = v
	if v.get("shell", "") != info.get("shell", "-"):
		_status("apk"); return
	var st := _read_json(STATE)
	if int(st.get("build", 0)) == int(v.build) and FileAccess.file_exists(DIR + str(st.get("file", ""))):
		_status("ready"); return  # downloaded earlier, waiting for a restart
	_download(v)

func _download(v: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var file := "b%d.pck" % int(v.build)
	var part := DIR + file + ".part"
	progress = 0.0; _status("downloading")
	_http = _req()
	_http.download_file = part
	var size := float(v.get("size", 0))
	var ok := _http.request(base + str(v.get("pck", "aurite-front.pck")) + "?b=%d" % int(v.build)) == OK
	while ok and not _http.get_meta("done", false):
		if size > 0: progress = clampf(_http.get_downloaded_bytes() / size, 0, 1)
		changed.emit()
		await get_tree().create_timer(0.25).timeout
	var res: Array = _http.get_meta("res", [HTTPRequest.RESULT_CANT_CONNECT, 0]) if ok else [HTTPRequest.RESULT_CANT_CONNECT, 0]
	_http.queue_free(); _http = null
	var good: bool = res[0] == HTTPRequest.RESULT_SUCCESS and res[1] == 200 and FileAccess.file_exists(part)
	if good and v.has("sha256"): good = FileAccess.get_sha256(part) == str(v.sha256)
	if not good:
		DirAccess.remove_absolute(part)
		_status("offline"); return
	DirAccess.rename_absolute(part, DIR + file)
	# never overwrite a pack that is mounted: Godot reads it while the game runs
	_write_json(STATE, {"build": int(v.build), "shell": v.shell, "name": str(v.get("name", "")), "file": file})
	progress = 1.0; _status("ready")

func _req() -> HTTPRequest:
	var h := HTTPRequest.new()
	h.use_threads = true; h.timeout = 0.0; h.body_size_limit = -1
	h.request_completed.connect(func(r, code, _h, _b): h.set_meta("res", [r, code]); h.set_meta("done", true))
	add_child(h)
	return h

## GET a small text file; null when offline or not found.
func _fetch(url: String):
	var h := _req(); h.timeout = 15.0
	if h.request(url) != OK:
		h.queue_free(); return null
	var r = await h.request_completed
	h.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200: return null
	return (r[3] as PackedByteArray).get_string_from_utf8()

func _status(s: String) -> void:
	status = s; changed.emit()
	print("Updater: build %d, %s" % [build, s])

func _clean_old_packs() -> void:
	if not DirAccess.dir_exists_absolute(DIR): return
	# at launch the pack named in the state is the mounted one; older packs and partial downloads go
	var keep := str(_read_json(STATE).get("file", ""))
	for f in DirAccess.get_files_at(DIR):
		if f != keep and f != "state.json": DirAccess.remove_absolute(DIR + f)

func _wipe() -> void:
	if not DirAccess.dir_exists_absolute(DIR): return
	for f in DirAccess.get_files_at(DIR): DirAccess.remove_absolute(DIR + f)

static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return {}
	var v = JSON.parse_string(f.get_as_text())
	return v if v is Dictionary else {}

static func _write_json(path: String, v: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(v))
