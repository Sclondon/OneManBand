# One Man Band

A grinning bandsman with a whole band on his back. Five buttons play five notes on
whichever instrument he has in his hands, and a loop station keeps what you played going while you put the next
thing on top. Godot 4.7, GL Compatibility, made to run in a browser and on a phone.

## Playing

- **Notes**: five round buttons with their note names on them, lowest on the left. Slide a finger
  from one to the next. Keys `A S D F G`.
- **Benders** (hold): flat, sharp, octave down, octave up. Arrow keys.
- **Instruments**: piccolo, trumpet, accordion, guitar, tuba, bells, drums. Keys `1` to `7`. On the drums the five
  buttons are kick, snare, hat, tom and crash.
- **Loop station**: record (`R`; counts a bar in from a standstill), play/stop (`Space`), undo (`Z`), clear this
  track, mute this track, metronome (`M`), tempo, loop length (1, 2, 4 or 8 bars; doubling repeats what is there),
  and four sections A to D that swap at the end of the loop.
- **Menu**: tuning (which five notes), key, snap, song mode (plays the sections in turn), the house band, new song,
  save as a MIDI file, MIDI keyboard in, sound.
- **Tune book**: three short melodies that change the weather and the time of day. They are in "How to play".

## Layout

| | |
| --- | --- |
| `scripts/main.gd` | `Band`: owns everything, turns a pressed button into what it does, saves |
| `scripts/kit.gd` | The instruments, tunings and tune book |
| `scripts/synth.gd` | Plays the samples in `sounds/`, one voice a note |
| `scripts/looper.gd` | The loop station: sections, tracks, recording, undo |
| `scripts/midi.gd` | Writes a song as a standard MIDI file |
| `scripts/bandsman.gd` | The man: arms that reach for what he holds, the rest bobbing to the beat, painted faces |
| `scripts/stage.gd` | The green, sky, day and night, rain, fireflies, floating notes |
| `scripts/hud.gd` | Every control, drawn by hand and multi-touch |
| `scripts/n64.gd`, `shaders/` | The one vertex-lit material and the sky |
| `art/make_models.py` | Builds `models/*.glb` (and `art/*.blend`) in Blender |
| `tools/render_samples.gd` | Synthesises `sounds/*.res` |

## Rebuilding things

```
blender --background --python art/make_models.py -- <this folder>
godot --headless --path . -s tools/render_samples.gd
godot --headless --path . --import
godot --headless --audio-driver Dummy --fixed-fps 60 --path . -s tests/smoke.gd
godot --audio-driver Dummy --path . -s tests/shots.gd -- --shots=<dir> [--portrait] [--close] [--turn=75]
godot --headless --path . --export-release "Web" build/index.html
```
