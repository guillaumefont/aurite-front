class_name Ent
extends RefCounted
## One unit ("u") or building ("b"). Positions are in world pixels (32 per tile), like the web version.

var id := 0
var kind := "u"
var type := ""
var team := 0
var d: Dictionary
var x := 0.0
var y := 0.0
var hp := 0.0
var max_hp := 0.0
var alive := true
var sel := false
var r := 6.0
var cd := 0.0
var flash := 0.0
var hit_t := 0.0
var scan := 0.0
var target: Ent = null
var tang := 0.0

# buildings
var tx := 0
var ty := 0
var w := 1
var h := 1
var rally = null  # Vector2 or null
var seen := false
var smoke_t := 0.0
var born := 0.0
var repairing := false
var rp_t := 0.0
var busy := false
var ch := 0.0
var rdy := false
var end_kind := ""  # "sell" or "die": the view plays a dismantle or collapse before dropping the model
var end_t := 0.0
var out_t := -9.0  # last time a unit rolled out (factory door)
var unload_t := -9.0  # last time a harvester unloaded here (refinery conveyor)

# units
var ang := 0.0
var path: Array = []  # Array of Vector2i
var order := "none"
var auto := false
var guard = null  # Vector2 or null
var dest = null  # Vector2i or null
var rp := 0.0
var load := 0.0
var hs := ""
var it := 0.0
var mt := 0.0
var moving := false
var stuck_t := 0.0
var stuck := 0
var lx := 0.0
var ly := 0.0
var pref := -1
var ref: Ent = null
var retry := 0
var ot := -1
var fspd := 0.0
var esc: Array = []
var ecx = null
var ecy = null
var ht: Ent = null
var path_len := 0.0
var los_t := 0.0
var los_ok := true
var los_of: Ent = null
var dump := 0.0  # aurite delivered in the current unload
var tag := ""          # mission tag: "vip", "hero", a post tag such as "guns"
var captive := false   # a prisoner: does nothing, cannot be hurt or selected until a friendly unit reaches it
var post := false      # holds its position: the AI never pulls it into an attack wave
var face = null  # Vector2 facing to adopt when the move ends (formation drag)
# Hollow Choir
var under := false     # burrowed (a moving sapper, or a unit in a tunnel): cannot be seen by the enemy, targeted or hurt
var intun := 0.0       # seconds left travelling through a tunnel (hidden, frozen at the entrance)
var tun = null         # tunnel plan {a, b, dest, order}: walk to burrow a, come out of burrow b, go on to dest
var aura_t := 0.0      # inside a Cantor's aura for this long: fires faster, mends slowly
var gt := 0.0          # crystal garden: time since the last harvest pulse
