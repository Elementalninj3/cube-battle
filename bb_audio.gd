extends Node
## Procedural SFX (ported from block-brawl-quality.html): all sounds are
## synthesized into AudioStreamWAV at runtime — no audio files needed.

const RATE := 22050

var vol: float = 0.6
var streams := {}
var players: Array = []
var _idx := 0


func _ready() -> void:
	for i in 8:
		var pl := AudioStreamPlayer.new()
		pl.bus = "Master"
		add_child(pl)
		players.append(pl)
	streams["light"] = _noise(0.12, 0.25, 2500.0, 800.0)
	streams["heavy"] = _noise(0.28, 0.4, 1200.0, 250.0)
	streams["hitL"] = _mix(_tone(220.0, 90.0, 0.1, 1, 0.2), _noise(0.06, 0.2, 2500.0, 800.0))
	streams["hitH"] = _mix(_tone(140.0, 40.0, 0.25, 2, 0.3), _noise(0.18, 0.4, 900.0, 150.0))
	streams["dash"] = _noise(0.15, 0.2, 4000.0, 1200.0)
	streams["beep_lo"] = _tone(560.0, 560.0, 0.15, 1, 0.15)
	streams["beep_hi"] = _tone(900.0, 900.0, 0.15, 1, 0.15)
	streams["ko"] = _mix(_tone(300.0, 50.0, 0.5, 2, 0.3), _noise(0.4, 0.4, 1200.0, 200.0))
	streams["win"] = _melody([523.0, 659.0, 784.0, 1046.0], 0.11, 0.25)


func play(sname: String) -> void:
	if not streams.has(sname):
		return
	var pl: AudioStreamPlayer = players[_idx]
	_idx = (_idx + 1) % players.size()
	pl.stream = streams[sname]
	pl.volume_db = linear_to_db(maxf(vol, 0.001))
	pl.play()


# wave: 0 sine, 1 square, 2 saw, 3 triangle
func _tone(f0: float, f1: float, dur: float, wave: int, v: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(f0, f1, float(i) / maxf(1.0, float(n - 1)))
		phase += TAU * f / RATE
		var s := 0.0
		match wave:
			0:
				s = sin(phase)
			1:
				s = 1.0 if sin(phase) >= 0.0 else -1.0
			2:
				s = fmod(phase, TAU) / PI - 1.0
			_:
				s = 2.0 * absf(2.0 * (phase / TAU - floor(phase / TAU + 0.5))) - 1.0
		var env := exp(-3.0 * t / dur)
		_encode(data, i, s * v * env)
	return _wav(data)


func _noise(dur: float, v: float, f0: float, f1: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		var cutoff := lerpf(f0, f1, float(i) / maxf(1.0, float(n - 1)))
		var a := clampf(TAU * cutoff / RATE, 0.01, 1.0)
		y += a * ((randf() * 2.0 - 1.0) - y)
		var env := exp(-3.0 * t / dur)
		_encode(data, i, y * v * env * 2.0)
	return _wav(data)


func _mix(a: AudioStreamWAV, b: AudioStreamWAV) -> AudioStreamWAV:
	var da := a.data
	var db := b.data
	var n := maxi(da.size(), db.size())
	# 16-bit mix
	var out := PackedByteArray()
	out.resize(n)
	var frames := n / 2
	for f in frames:
		var sa := 0
		var sb := 0
		if f * 2 + 1 < da.size():
			sa = da[f * 2] | (da[f * 2 + 1] << 8)
			if sa >= 32768:
				sa -= 65536
		if f * 2 + 1 < db.size():
			sb = db[f * 2] | (db[f * 2 + 1] << 8)
			if sb >= 32768:
				sb -= 65536
		var m := clampi(sa + sb, -32768, 32767)
		if m < 0:
			m += 65536
		out[f * 2] = m & 0xFF
		out[f * 2 + 1] = (m >> 8) & 0xFF
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = out
	return w


func _melody(freqs: Array, gap: float, note_dur: float) -> AudioStreamWAV:
	var total := int(RATE * (gap * float(freqs.size() - 1) + note_dur))
	var data := PackedByteArray()
	data.resize(total * 2)
	# triangle notes, like html win jingle (resize() already zero-fills = silence)
	for ni in freqs.size():
		var f: float = freqs[ni]
		var start := int(RATE * gap * ni)
		var nn := int(RATE * note_dur)
		var phase := 0.0
		for i in nn:
			var idx := start + i
			if idx >= total:
				break
			phase += TAU * f / RATE
			var s := 2.0 * absf(2.0 * (phase / TAU - floor(phase / TAU + 0.5))) - 1.0
			var env := exp(-3.0 * float(i) / float(nn))
			var cur: int = data[idx * 2] | (data[idx * 2 + 1] << 8)
			if cur >= 32768:
				cur -= 65536
			var m := clampi(cur + int(s * 0.25 * env * 32767.0), -32768, 32767)
			if m < 0:
				m += 65536
			data[idx * 2] = m & 0xFF
			data[idx * 2 + 1] = (m >> 8) & 0xFF
	return _wav(data)


func _encode(data: PackedByteArray, i: int, s: float) -> void:
	var v := clampi(int(s * 32767.0), -32768, 32767)
	if v < 0:
		v += 65536
	data[i * 2] = v & 0xFF
	data[i * 2 + 1] = (v >> 8) & 0xFF


func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
