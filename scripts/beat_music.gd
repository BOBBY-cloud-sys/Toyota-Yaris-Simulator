class_name BeatMusic
extends AudioStreamPlayer
## Procedural techno track synthesized in real time. Emits `beat` on every
## audible quarter note so the cars can dance in sync.

signal beat(index: int)

@export var bpm := 128.0

const RATE := 22050.0
const BUFFER := 0.15
const BASS := [0, 0, 12, 0, 3, 0, 12, 3, 5, 5, 17, 5, 7, 7, 10, 12]
const LEAD := [12, 15, 19, 24, 19, 15, 12, 7, 10, 14, 17, 22, 17, 14, 10, 7]

var _pb: AudioStreamGeneratorPlayback
var _n := 0
var _last_beat := -1
var _kick_phase := 0.0
var _bass_phase := 0.0
var _lead_phase := 0.0


func _ready() -> void:
	add_to_group("beat_music")
	if AudioServer.get_bus_index("Music") != -1:
		bus = &"Music"
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = BUFFER
	stream = gen
	play()
	_pb = get_stream_playback() as AudioStreamGeneratorPlayback
	_fill()


func beat_len() -> float:
	return 60.0 / bpm


func song_time() -> float:
	var buffered := 0.0
	if _pb:
		buffered = maxf(BUFFER * RATE - _pb.get_frames_available(), 0.0) / RATE
	return maxf(_n / RATE - buffered - AudioServer.get_output_latency(), 0.0)


func beat_float() -> float:
	return song_time() / beat_len()


func beat_phase() -> float:
	return fposmod(beat_float(), 1.0)


func _process(_delta: float) -> void:
	_fill()
	var b := int(floor(beat_float()))
	if b != _last_beat:
		_last_beat = b
		beat.emit(b)


func _fill() -> void:
	if _pb == null:
		return
	var frames := _pb.get_frames_available()
	var bl := beat_len()
	for i in frames:
		var t := _n / RATE
		var bt := fposmod(t, bl)
		var beat_i := int(t / bl)
		var s := 0.0
		# Kick on every beat
		var kf := 48.0 + 130.0 * exp(-bt * 30.0)
		_kick_phase = fposmod(_kick_phase + kf / RATE, 1.0)
		s += sin(_kick_phase * TAU) * exp(-bt * 9.0) * 0.9
		# Off-beat hi-hat
		var ht := bt - bl * 0.5
		if ht > 0.0:
			s += (randf() * 2.0 - 1.0) * exp(-ht * 70.0) * 0.22
		# Clap on 2 and 4
		if beat_i % 2 == 1:
			s += (randf() * 2.0 - 1.0) * exp(-bt * 22.0) * 0.28
		# Saw bass on 8th notes
		var eighth := int(t / (bl * 0.5))
		var et := fposmod(t, bl * 0.5)
		var semi: int = BASS[eighth % BASS.size()]
		var bf := 55.0 * pow(2.0, semi / 12.0)
		_bass_phase = fposmod(_bass_phase + bf / RATE, 1.0)
		s += (_bass_phase * 2.0 - 1.0) * 0.32 * exp(-et * 5.0)
		# Square-wave arpeggio every other 8-beat phrase
		if int(beat_i / 8.0) % 2 == 1:
			var six := int(t / (bl * 0.25))
			var lt := fposmod(t, bl * 0.25)
			var ln: int = LEAD[six % LEAD.size()]
			var lf := 440.0 * pow(2.0, ln / 12.0 - 1.0)
			_lead_phase = fposmod(_lead_phase + lf / RATE, 1.0)
			s += (1.0 if _lead_phase < 0.5 else -1.0) * 0.1 * exp(-lt * 12.0)
		s = clampf(s * 0.6, -1.0, 1.0)
		_pb.push_frame(Vector2(s, s))
		_n += 1
