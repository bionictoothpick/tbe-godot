extends Node
## Sound effects. The original game had no sound, so every sound here is
## synthesized in code when the game starts: there are no audio files to
## license, and it works the same in exported and web builds.
##
##   Sfx.play("pop")                  play a named sound
##   Sfx.impact(body, speed_change)   collision sound for an object
##
## Objects pick their collision sound by type (see MATERIAL). A level or object
## can override it with a "Sound" property: wood, metal, ball, soft or none.

const RATE := 22050
const VOICES := 16

## Collision sound per object type; anything not listed sounds like wood.
const MATERIAL := {
	"PegMetal": "metal", "IBeam": "metal", "Weight": "metal", "Hammer": "metal",
	"CircularSaw": "metal", "Skyhook": "metal", "PetanqueBoule": "metal",
	"BedOfNails": "metal", "Spring": "metal",
	"SoccerBall": "ball", "VolleyBall": "ball", "TennisBall": "ball", "CustomBall": "ball",
	"Balloon": "soft", "Styrofoam": "soft", "LeftStyrofoamWedge": "soft",
	"RightStyrofoamWedge": "soft", "CardboardBox": "soft", "Daffodil": "soft",
	"Cactus": "soft", "ColaMintBottle": "soft",
	"PostItHint": "none", "PostItMisc": "none", "PostItTutorial": "none",
	"Butterfly": "none", "Scenery": "none", "Goal": "none",
}

var muted := false
## How many times each sound has played (used by tools/sound_test.gd).
var counts := {}
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _rng := RandomNumberGenerator.new()
## real-time throttling, so a pile of dominoes doesn't make a wall of noise
var _recent: Array[int] = []
var _last_by_body := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 7
	muted = bool(Progress.get_setting("muted", false))
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_players.append(p)
	_build_sounds()
	# a soft click for every button in the game, editor and menus
	get_tree().node_added.connect(_on_node_added)


func set_muted(m: bool) -> void:
	muted = m
	Progress.set_setting("muted", m)
	if m:
		for p in _players:
			p.stop()


## Play a sound. `volume` is linear (0..1), `pitch` 1 = normal.
func play(sound: String, volume: float = 1.0, pitch: float = 1.0) -> void:
	if muted or not _streams.has(sound) or volume <= 0.0:
		return
	counts[sound] = int(counts.get(sound, 0)) + 1
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _streams[sound]
	p.volume_db = linear_to_db(clampf(volume, 0.0, 1.0)) - 4.0
	p.pitch_scale = clampf(pitch, 0.3, 3.0)
	p.play()


## Collision sound for `body` hitting the object with instance id `other_id`.
## `dv` is how much the body's speed changed, in m/s. When both objects of a
## collision report it, only the first one that is loud enough plays.
func impact(body: TbeObject, dv: float, other_id: int = 0) -> void:
	if muted or dv < 0.6:
		return
	var mat := material_of(body)
	if mat == "none":
		return
	var now := Time.get_ticks_msec()
	var id := body.get_instance_id()
	var pair := Vector2i(mini(id, other_id), maxi(id, other_id))
	if now - int(_last_by_body.get(id, -1000)) < 70 or now - int(_last_by_body.get(pair, -1000)) < 100:
		return
	while not _recent.is_empty() and now - _recent[0] > 80:
		_recent.pop_front()
	if _recent.size() >= 5:
		return
	_recent.append(now)
	_last_by_body[id] = now
	_last_by_body[pair] = now
	if _last_by_body.size() > 2000:
		_last_by_body.clear()
	# louder for harder hits; heavier things sound lower
	var vol := clampf(dv / 5.0, 0.12, 1.0)
	var pitch := clampf(1.25 - 0.12 * log(maxf(body.mass, 0.01)), 0.6, 1.7)
	play("hit_" + mat, vol, pitch * _rng.randf_range(0.93, 1.07))


func material_of(body: TbeObject) -> String:
	var v = TBE.prop(body.props, "Sound")
	if v != null:
		return str(v).strip_edges().to_lower()
	return MATERIAL.get(body.def.type_name, "wood")


func _on_node_added(n: Node) -> void:
	if n is BaseButton:
		n.pressed.connect(func(): play("click", 0.35))


# ============================================================== synthesis

func _build_sounds() -> void:
	_streams["hit_wood"] = _make(0.18, func(t, n):
		return (sin(TAU * 520 * t) * 0.6 + sin(TAU * 830 * t) * 0.3) * exp(-t * 38) \
				+ n * exp(-t * 220) * 0.5)
	_streams["hit_metal"] = _make(0.6, func(t, n):
		return (sin(TAU * 1180 * t) * exp(-t * 7) * 0.4 + sin(TAU * 2710 * t) * exp(-t * 11) * 0.3
				+ sin(TAU * 4130 * t) * exp(-t * 16) * 0.2) + n * exp(-t * 300) * 0.4)
	_streams["hit_ball"] = _make(0.22, func(t, _n):
		var f := 170.0 + 90.0 * exp(-t * 30)
		return sin(TAU * f * t) * exp(-t * 16) * 0.9)
	_streams["hit_soft"] = _make(0.16, func(t, n):
		return sin(TAU * (90 + 60 * exp(-t * 40)) * t) * exp(-t * 30) * 0.8 + n * exp(-t * 60) * 0.25,
			0.15)
	_streams["pop"] = _make(0.14, func(t, n):
		return n * exp(-t * 60) * 0.9 + sin(TAU * 300 * t) * exp(-t * 90) * 0.5)
	_streams["boom"] = _make(1.4, func(t, n):
		var env := minf(t * 200.0, 1.0) * exp(-t * 3.5)
		return (n * 0.9 + sin(TAU * (45 + 30 * exp(-t * 5)) * t) * 0.6) * env, 0.05)
	_streams["ring"] = _make(0.55, func(t, _n):
		# an old telephone bell: the hammer flips between two bells 25 times a second
		var f := 1300.0 if int(t * 50) % 2 == 0 else 1650.0
		return sin(TAU * f * t) * 0.45 * minf(t * 80.0, 1.0) * minf((0.55 - t) * 30.0, 1.0))
	_streams["fizz"] = _make(1.6, func(t, n):
		var env := minf(t * 6.0, 1.0) * minf((1.6 - t) * 2.0, 1.0)
		return n * env * 0.35 * (0.7 + 0.3 * sin(TAU * 9 * t)), 0.9)
	_streams["squish"] = _make(0.3, func(t, _n):
		return sin(TAU * (300 + 600 * exp(-t * 9)) * t) * exp(-t * 9) * 0.6)
	_streams["pick"] = _make(0.05, func(t, _n):
		return sin(TAU * 1500 * t) * exp(-t * 90) * 0.5)
	_streams["drop"] = _make(0.08, func(t, n):
		return sin(TAU * 700 * t) * exp(-t * 60) * 0.6 + n * exp(-t * 300) * 0.2)
	_streams["click"] = _make(0.03, func(t, _n):
		return sin(TAU * 2200 * t) * exp(-t * 160) * 0.5)
	# C E G C, then a held chord
	_streams["win"] = _notes([[523.3, 0.0, 0.25], [659.3, 0.12, 0.25], [784.0, 0.24, 0.25],
			[1046.5, 0.36, 0.9], [784.0, 0.36, 0.9], [659.3, 0.36, 0.9]], 1.3)
	_streams["fail"] = _notes([[392.0, 0.0, 0.3], [349.2, 0.25, 0.3], [261.6, 0.5, 0.7]], 1.25)


## Render `dur` seconds. `fn(t, noise)` returns a sample in -1..1. `noise` is
## white noise, smoothed when `lowpass` (0..1) is above 0.
func _make(dur: float, fn: Callable, lowpass: float = 0.0) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var white := _rng.randf_range(-1.0, 1.0)
		lp += (1.0 - lowpass) * (white - lp)
		var s: float = fn.call(t, lp if lowpass > 0.0 else white)
		# fade the last few milliseconds so nothing clicks
		s *= minf(1.0, float(n - i) / (RATE * 0.004))
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 30000))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


## A little tune: each note is [frequency, start, length], soft triangle waves.
func _notes(notes: Array, dur: float) -> AudioStreamWAV:
	return _make(dur, func(t, _n):
		var s := 0.0
		for nt in notes:
			var u: float = t - nt[1]
			if u < 0.0 or u > nt[2]:
				continue
			var ph: float = fmod(u * nt[0], 1.0)
			var tri := 4.0 * absf(ph - 0.5) - 1.0
			s += tri * minf(u * 60.0, 1.0) * minf((nt[2] - u) * 12.0, 1.0) * exp(-u * 2.5) * 0.3
		return s)
