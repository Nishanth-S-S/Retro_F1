extends Node
## Procedurally synthesised placeholder audio. Every sound is generated once at startup
## into an AudioStreamWAV, so there are no asset dependencies and no per-frame synthesis cost.

const MIX_RATE := 22050

var streams: Dictionary = {}
var _sfx_players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _music: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus_name: String in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
	_build_streams()
	for i in 6:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_sfx_players.append(player)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.stream = streams["music"]
	_music.volume_db = -14.0
	add_child(_music)
	EventBus.settings_changed.connect(apply_volumes)
	apply_volumes()


func apply_volumes() -> void:
	_set_bus("Master", float(GameManager.setting("master_volume")))
	_set_bus("Music", float(GameManager.setting("music_volume")))
	_set_bus("SFX", float(GameManager.setting("effects_volume")))


func _set_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)


func play(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not streams.has(sound):
		return
	var player := _sfx_players[_next_player]
	_next_player = (_next_player + 1) % _sfx_players.size()
	player.stream = streams[sound]
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


func play_music(on: bool) -> void:
	if on and not _music.playing:
		_music.play()
	elif not on:
		_music.stop()


func make_loop_player(sound: String, positional: bool) -> Node:
	var player: Node
	if positional:
		var p2 := AudioStreamPlayer2D.new()
		p2.max_distance = 900.0
		p2.attenuation = 1.6
		player = p2
	else:
		player = AudioStreamPlayer.new()
	player.set("stream", streams[sound])
	player.set("bus", "SFX")
	player.set("volume_db", -60.0)
	return player


# ---------------------------------------------------------------- synthesis

func _build_streams() -> void:
	streams["engine"] = _make_engine()
	streams["squeal"] = _make_squeal()
	streams["collision"] = _make_noise_burst(0.22, 180.0, 0.9)
	streams["shift"] = _make_noise_burst(0.06, 900.0, 0.5)
	streams["click"] = _make_tone([1250.0], 0.045, 0.35)
	streams["snap"] = _make_tone([520.0, 780.0, 1040.0], 0.13, 0.5)
	streams["deny"] = _make_tone([180.0, 140.0], 0.16, 0.5)
	streams["beep"] = _make_tone([440.0], 0.18, 0.5)
	streams["go"] = _make_tone([880.0], 0.5, 0.55)
	streams["finish"] = _make_arpeggio([523.0, 659.0, 784.0, 1046.0], 0.13, 0.5)
	streams["cash"] = _make_arpeggio([784.0, 1046.0], 0.09, 0.4)
	streams["music"] = _make_music()
	streams["crowd"] = _make_crowd()


func _wav(samples: PackedFloat32Array, loop: bool, rate: int = MIX_RATE) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


## Crowd loop: a wash of voices (band-passed noise) that swells and cheers. The ends are
## faded into each other so the loop never clicks.
func _make_crowd() -> AudioStreamWAV:
	var count := MIX_RATE * 4
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var low := 0.0
	var band := 0.0
	for i in count:
		var t := float(i) / MIX_RATE
		low += (rng.randf_range(-1.0, 1.0) - low) * 0.18
		band += (low - band) * 0.05
		var swell := 0.55 + 0.25 * sin(TAU * 0.5 * t) + 0.2 * sin(TAU * 1.3 * t + 1.0)
		var cheer := 0.35 * maxf(0.0, sin(TAU * 0.25 * t + 0.6)) * (0.5 + 0.5 * sin(TAU * 7.0 * t))
		samples[i] = (low - band) * 2.2 * (swell + cheer)
	var fade := MIX_RATE / 2
	for i in fade:
		var k := float(i) / fade
		samples[i] = samples[i] * k + samples[count - fade + i] * (1.0 - k)
	return _wav(samples.slice(0, count - fade), true)


## Engine loop: a 50 Hz buzz rich in harmonics. Pitch-shifted with RPM at playback time.
func _make_engine() -> AudioStreamWAV:
	var period := 441
	var count := period * 8
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / float(period) * TAU
		var v := sin(t) * 0.5 + sin(t * 2.0 + 0.4) * 0.3 + sin(t * 3.0 + 1.1) * 0.2 + sin(t * 4.0) * 0.12 + sin(t * 0.5) * 0.25 + sin(t * 6.0 + 0.7) * 0.06
		samples[i] = tanh(v * 1.6) * 0.55
	return _wav(samples, true)


func _make_squeal() -> AudioStreamWAV:
	var count := 8820
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var band := 0.0
	var low := 0.0
	for i in count:
		var t := float(i) / MIX_RATE
		# Resonant band-passed noise plus a wavering tone reads as tire scrub.
		var noise := rng.randf_range(-1.0, 1.0)
		low += (noise - low) * 0.35
		band += (low - band) * 0.12
		var tone := sin(TAU * (1150.0 + 60.0 * sin(TAU * 5.0 * t)) * t)
		var edge := minf(1.0, minf(float(i), float(count - i)) / 400.0)
		samples[i] = ((low - band) * 0.9 + tone * 0.22) * edge * 0.6
	return _wav(samples, true)


func _make_noise_burst(length: float, cutoff_hz: float, gain: float) -> AudioStreamWAV:
	var count := int(length * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var low := 0.0
	var alpha := clampf(cutoff_hz / MIX_RATE * TAU, 0.01, 1.0)
	for i in count:
		low += (rng.randf_range(-1.0, 1.0) - low) * alpha
		var env := pow(1.0 - float(i) / count, 2.2)
		samples[i] = low * env * gain * 2.0
	return _wav(samples, false)


func _make_tone(freqs: Array, length: float, gain: float) -> AudioStreamWAV:
	var count := int(length * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / MIX_RATE
		var env := minf(1.0, float(i) / 60.0) * pow(1.0 - float(i) / count, 1.5)
		var v := 0.0
		for f: float in freqs:
			v += sin(TAU * f * t)
		samples[i] = v / freqs.size() * env * gain
	return _wav(samples, false)


func _make_arpeggio(freqs: Array, note_length: float, gain: float) -> AudioStreamWAV:
	var note := int(note_length * MIX_RATE)
	var count := note * freqs.size() + int(0.25 * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var idx := mini(i / note, freqs.size() - 1)
		var local := i - idx * note
		var f: float = freqs[idx]
		var t := float(i) / MIX_RATE
		var env := minf(1.0, float(local) / 40.0) * exp(-float(local) / MIX_RATE * 7.0)
		samples[i] = (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)) * env * gain
	return _wav(samples, false)


## Quiet ambient pad for the menus. Low sample rate keeps generation instant.
func _make_music() -> AudioStreamWAV:
	var rate := 11025
	var bar := 2.0
	var chords := [[110.0, 164.81, 220.0, 261.63], [87.31, 130.81, 174.61, 261.63], [130.81, 196.0, 261.63, 329.63], [98.0, 146.83, 196.0, 293.66]]
	var count := int(bar * chords.size() * rate)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var per_bar := int(bar * rate)
	for i in count:
		var chord: Array = chords[i / per_bar]
		var local := float(i % per_bar) / per_bar
		var t := float(i) / rate
		var env := sin(local * PI)
		var v := 0.0
		for f: float in chord:
			v += sin(TAU * f * t) + 0.25 * sin(TAU * f * 2.003 * t)
		# Soft plucked arpeggio on top of the pad.
		var step := int(local * 8.0)
		var pluck_t := local * 8.0 - step
		var pf: float = chord[step % 4] * 2.0
		v += sin(TAU * pf * t) * exp(-pluck_t * 5.0) * 1.2
		samples[i] = v * 0.085 * (0.35 + 0.65 * env)
	return _wav(samples, true, rate)
