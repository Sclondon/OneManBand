class_name Kit
## What the bandsman carries, and how the five note buttons are tuned.

const PICCOLO := 0
const TRUMPET := 1
const ACCORDION := 2
const GUITAR := 3
const TUBA := 4
const BELLS := 5
const DRUMS := 6
const ORGAN := 7
const CHOIR := 10
const BASSOON := 11
const THEREMIN := 8
const VIOLA := 9
const UKULELE := 12
const ELECTRIC := 13
const PIANO := 14

# `base` is the note the buttons count up from in the key of C, `bases` the notes there are
# samples of, `held` whether a note lasts as long as the button (and `release` how long it takes
# to die away once let go), `gm` the General MIDI program. New ones go on the end: saved songs
# and the station's radio know the instruments by their place here.
const INSTRUMENTS: Array[Dictionary] = [
	{"id": "piccolo", "name": "Piccolo", "base": 72, "bases": [72, 84, 96], "held": true, "release": 0.07, "gm": 72, "db": -5.0, "color": Color("4fd6c8")},
	{"id": "trumpet", "name": "Trumpet", "base": 60, "bases": [48, 60, 72], "held": true, "release": 0.06, "gm": 56, "db": -7.0, "color": Color("ffd24a")},
	{"id": "accordion", "name": "Accordion", "base": 60, "bases": [48, 60, 72, 84], "held": true, "release": 0.09, "gm": 21, "db": -9.0, "color": Color("ff6a5c")},
	{"id": "guitar", "name": "Guitar", "base": 48, "bases": [48, 60, 72], "held": false, "gm": 24, "db": -4.0, "color": Color("f0a25a")},
	{"id": "tuba", "name": "Tuba", "base": 36, "bases": [36, 48, 60], "held": true, "release": 0.1, "gm": 58, "db": -3.0, "color": Color("b98cff")},
	{"id": "bells", "name": "Bells", "base": 72, "bases": [72, 84, 96], "held": false, "gm": 9, "db": -8.0, "color": Color("ffa6d0")},
	{"id": "drums", "name": "Drums", "base": 0, "bases": [], "held": false, "gm": 0, "db": -3.0, "color": Color("9be06a")},
	{"id": "organ", "name": "Organ", "base": 60, "bases": [48, 60, 72], "held": true, "release": 0.08, "gm": 19, "db": -9.0, "color": Color("e06a8c")},
	{"id": "theremin", "name": "Theremin", "base": 60, "bases": [60, 72, 84], "held": true, "release": 0.3, "gm": 78, "db": -5.0, "color": Color("f5f1e6")},
	{"id": "viola", "name": "Viola", "base": 48, "bases": [48, 60, 72], "held": true, "release": 0.16, "gm": 41, "db": -6.0, "color": Color("8fb4ff")},
	# (the little folk on the green, singing: he conducts)
	{"id": "choir", "name": "Choir", "base": 60, "bases": [48, 52, 56, 60, 64, 68, 72, 76, 80, 84], "held": true, "release": 0.35, "gm": 52, "db": -6.0, "color": Color("a8e6c9")},
	{"id": "bassoon", "name": "Bassoon", "base": 48, "bases": [36, 48, 60], "held": true, "release": 0.09, "gm": 70, "db": -5.0, "color": Color("c9643e")},
	{"id": "ukulele", "name": "Ukulele", "base": 60, "bases": [48, 60, 72, 84], "held": false, "gm": 24, "db": -5.0, "color": Color("ffd98a")},
	# (turned up too loud, so that a note sings on for as long as it is held; samples from low E
	# to the top of the neck and past, because between them the keys reach all of it)
	{"id": "electric", "name": "Electric", "base": 48, "bases": [28, 40, 52, 64, 76, 88], "held": true, "release": 0.12, "gm": 29, "db": -9.0, "color": Color("e8364f")},
	# (struck, so a note dies away by itself, but is stopped short when the key is let go)
	{"id": "piano", "name": "Piano", "base": 60, "bases": [24, 36, 48, 60, 72, 84, 96], "held": true, "release": 0.15, "gm": 0, "db": -6.0, "color": Color("f2efe6")},
]

# The order they are laid out in for picking, and that the number keys go in
const SHELF: Array[int] = [PICCOLO, TRUMPET, VIOLA, ACCORDION, GUITAR, UKULELE, ELECTRIC, PIANO, ORGAN, THEREMIN, TUBA, BELLS, DRUMS, CHOIR, BASSOON]

# Three kits of five drums: the trap set, the big low ones (with the low octave key on) and the
# toys (with the high one). A drum's note says which kit it is from and how far it is bent:
# DRUM_KIT down or up for the kit, and whatever is left over in semitones.
const DRUM_NAMES := ["Kick", "Snare", "Hat", "Tom", "Crash", "Boom", "Rim", "Open", "Floor", "Ride", "Clap", "Block", "Shake", "Bell", "Splash"]
const DRUM_KIT := 40


static func drum_kit(n: int) -> int:
	return clampi(roundi(n / float(DRUM_KIT)), -1, 1)


# Which of DRUM_NAMES button `b` is, for a note `n`
static func drum(b: int, n: int) -> int:
	var kit := drum_kit(n)
	return posmod(b, 5) + (0 if kit == 0 else (5 if kit < 0 else 10))


static func drum_bend(n: int) -> int:
	return n - DRUM_KIT * drum_kit(n)

# The five buttons from the lowest to the highest, as semitones above the key note.
# The first is the old ocarina tuning: in C it gives D F A B D.
const TUNINGS: Array[Dictionary] = [
	{"name": "Classic", "steps": [2, 5, 9, 11, 14]},
	{"name": "Sunny", "steps": [0, 2, 4, 7, 9]},
	{"name": "Moody", "steps": [0, 3, 5, 7, 10]},
	{"name": "Blues", "steps": [0, 3, 5, 6, 7]},
	{"name": "Desert", "steps": [0, 1, 4, 5, 7]},
	{"name": "Lantern", "steps": [0, 2, 3, 7, 8]},
]

const NOTE_NAMES := ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]

# Little melodies that do something, as buttons (0 is the lowest)
const TUNES: Array[Dictionary] = [
	{"name": "Sun Tune", "pads": [2, 1, 4, 2, 1, 4], "does": "sun", "hint": "turns day to night and back"},
	{"name": "Storm Tune", "pads": [0, 1, 4, 0, 1, 4], "does": "storm", "hint": "calls the rain, or sends it off"},
	{"name": "Firefly Tune", "pads": [1, 2, 3, 1, 2, 3], "does": "fireflies", "hint": "brings the fireflies out"},
	{"name": "Dance Tune", "pads": [0, 2, 4, 0, 2, 4], "does": "dance", "hint": "gets the little folk dancing"},
	{"name": "Tag Tune", "pads": [4, 3, 4, 3, 2, 0], "does": "tag", "hint": "starts a game of tag"},
	{"name": "Balloon Tune", "pads": [0, 1, 2, 3, 4, 4], "does": "balloons", "hint": "lets the balloons go"},
	{"name": "Snow Tune", "pads": [4, 2, 1, 4, 2, 1], "does": "snow", "hint": "brings the snow, or stops it"},
	{"name": "Carnival Tune", "pads": [3, 3, 1, 1, 4, 0], "does": "carnival", "hint": "lights the lamps every colour"},
]


static func note_name(n: int) -> String:
	return NOTE_NAMES[posmod(n, 12)]


static func is_drums(inst: int) -> bool:
	return inst == DRUMS
