class_name MidiFile
## Writes a song out as a standard MIDI file: a tempo track, then a track for each instrument that
## has anything on it. With song mode on, every section with notes in it follows the last.

const PPQ := 480
const DRUM_NOTES := [36, 38, 42, 45, 49, 35, 37, 46, 41, 51, 39, 76, 54, 56, 55]
# (General MIDI has no surdo, cajon or chimes: a floor tom, a bass drum and the bell tree stand in)
const PERCUSSION_NOTES := [74, 79, 54, 70, 67, 64, 60, 41, 65, 35, 75, 81, 58, 72, 84]


static func write(looper: Looper) -> PackedByteArray:
	var order: Array[int] = []
	if looper.chain:
		for s in Looper.SECTIONS:
			if not looper.section_empty(s):
				order.append(s)
	if order.is_empty():
		order.append(looper.section)
	var span := int(looper.length() * PPQ)
	var total := span * order.size()

	var tracks: Array[PackedByteArray] = []
	var tempo := PackedByteArray()
	var micros := int(60000000.0 / looper.bpm)
	tempo.append_array([0x00, 0xFF, 0x51, 0x03, (micros >> 16) & 0xFF, (micros >> 8) & 0xFF, micros & 0xFF])
	tempo.append_array([0x00, 0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08])
	tempo.append_array(_length(total))
	tempo.append_array([0xFF, 0x2F, 0x00])
	tracks.append(tempo)

	for inst in Kit.INSTRUMENTS.size():
		var kit := Kit.INSTRUMENTS[inst]
		var drums := Kit.is_drums(inst)
		# (channel 9 is the drums' own, so the instruments after it move up one)
		var channel := 9 if drums else (inst if inst < 9 else inst + 1)
		var events := []   # [tick, 0 for off or 1 for on, key]
		for k in order.size():
			for note: Dictionary in looper.sections[order[k]][inst]:
				if note.t >= looper.length():
					continue
				var key: int = (PERCUSSION_NOTES if inst == Kit.PERCUSSION else DRUM_NOTES)[Kit.drum(note.b, note.n)] if drums else clampi(note.n, 0, 127)
				var on := k * span + int(note.t * PPQ)
				var off := on + (60 if drums else maxi(30, int(note.d * PPQ)))
				events.append([on, 1, key])
				events.append([mini(off, total), 0, key])
		if events.is_empty():
			continue
		events.sort_custom(func(a: Array, b: Array) -> bool:
			return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
		var data := PackedByteArray()
		var title: PackedByteArray = kit.name.to_utf8_buffer()
		data.append_array([0x00, 0xFF, 0x03, title.size()])
		data.append_array(title)
		if not drums:
			data.append_array([0x00, 0xC0 | channel, kit.gm])
		var at := 0
		for e: Array in events:
			data.append_array(_length(e[0] - at))
			at = e[0]
			data.append_array([(0x90 if e[1] == 1 else 0x80) | channel, e[2], 100 if e[1] == 1 else 0])
		data.append_array(_length(maxi(0, total - at)))
		data.append_array([0xFF, 0x2F, 0x00])
		tracks.append(data)

	var out := PackedByteArray()
	out.append_array("MThd".to_ascii_buffer())
	out.append_array([0, 0, 0, 6, 0, 1, 0, tracks.size(), (PPQ >> 8) & 0xFF, PPQ & 0xFF])
	for data in tracks:
		out.append_array("MTrk".to_ascii_buffer())
		var n := data.size()
		out.append_array([(n >> 24) & 0xFF, (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF])
		out.append_array(data)
	return out


# A length of time the way MIDI writes it: seven bits to a byte, the top bit set on all but the last
static func _length(ticks: int) -> PackedByteArray:
	var bytes := PackedByteArray([ticks & 0x7F])
	ticks >>= 7
	while ticks > 0:
		bytes.insert(0, (ticks & 0x7F) | 0x80)
		ticks >>= 7
	return bytes
