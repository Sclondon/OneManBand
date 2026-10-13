class_name Kit
## What the bandsman carries, and how the five note buttons are tuned.

const OCARINA := 0
const TRUMPET := 1
const ACCORDION := 2
const GUITAR := 3
const TUBA := 4
const BELLS := 5
const DRUMS := 6

# `base` is the note the buttons count up from in the key of C, `bases` the notes there are
# samples of, `held` whether a note lasts as long as the button, `gm` the General MIDI program.
const INSTRUMENTS: Array[Dictionary] = [
	{"id": "ocarina", "name": "Ocarina", "base": 60, "bases": [60, 72, 84], "held": true, "gm": 79, "db": -5.0, "color": Color("4fd6c8")},
	{"id": "trumpet", "name": "Trumpet", "base": 60, "bases": [48, 60, 72], "held": true, "gm": 56, "db": -7.0, "color": Color("ffd24a")},
	{"id": "accordion", "name": "Accordion", "base": 48, "bases": [48, 60, 72], "held": true, "gm": 21, "db": -9.0, "color": Color("ff6a5c")},
	{"id": "guitar", "name": "Guitar", "base": 48, "bases": [48, 60, 72], "held": false, "gm": 24, "db": -4.0, "color": Color("f0a25a")},
	{"id": "tuba", "name": "Tuba", "base": 36, "bases": [36, 48, 60], "held": true, "gm": 58, "db": -3.0, "color": Color("b98cff")},
	{"id": "bells", "name": "Bells", "base": 72, "bases": [72, 84, 96], "held": false, "gm": 9, "db": -8.0, "color": Color("ffa6d0")},
	{"id": "drums", "name": "Drums", "base": 0, "bases": [], "held": false, "gm": 0, "db": -3.0, "color": Color("9be06a")},
]

const DRUM_NAMES := ["Kick", "Snare", "Hat", "Tom", "Crash"]

# The five buttons from the lowest (A) to the highest (C up), as semitones above the key note.
# The first is the tuning of the ocarina itself: in C it gives D F A B D.
const TUNINGS: Array[Dictionary] = [
	{"name": "Ocarina", "steps": [2, 5, 9, 11, 14]},
	{"name": "Sunny", "steps": [0, 2, 4, 7, 9]},
	{"name": "Moody", "steps": [0, 3, 5, 7, 10]},
	{"name": "Blues", "steps": [0, 3, 5, 6, 7]},
	{"name": "Desert", "steps": [0, 1, 4, 5, 7]},
	{"name": "Lantern", "steps": [0, 2, 3, 7, 8]},
]

const NOTE_NAMES := ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]

# Little melodies that do something, as buttons (0 is A, then C down, right, left, up)
const TUNES: Array[Dictionary] = [
	{"name": "Sun Tune", "pads": [2, 1, 4, 2, 1, 4], "does": "sun", "hint": "turns day to night and back"},
	{"name": "Storm Tune", "pads": [0, 1, 4, 0, 1, 4], "does": "storm", "hint": "calls the rain, or sends it off"},
	{"name": "Firefly Tune", "pads": [1, 2, 3, 1, 2, 3], "does": "fireflies", "hint": "brings the fireflies out"},
]


static func note_name(n: int) -> String:
	return NOTE_NAMES[posmod(n, 12)]


static func is_drums(inst: int) -> bool:
	return inst == DRUMS
