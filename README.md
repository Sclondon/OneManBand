# One Man Band

A grinning bandsman with a whole band on his back. Five buttons play five notes on
whichever instrument he has in his hands, and a loop station keeps what you played going while you put the next
thing on top. Godot 4.7, GL Compatibility, made to run in a browser and on a phone.

## Playing

- **Notes**: five round buttons with their note names on them, lowest on the left. Slide a finger
  from one to the next. Keys `A S D F G`.
- **The stick**: up and down bends what is sounding by up to a whole tone, sideways makes it wobble. Arrow keys.
  Under it are four keys that stay on until tapped again: flat and sharp move the five buttons a half step
  (`C`, `V`), so every note can be had, and two drop or raise an octave (`Q`, `E`).
- **Instruments**: piccolo, trumpet, viola, accordion, guitar, organ, theremin, tuba, bells, drums, and the choir (the
  satyrs and imps line up and sing, and he conducts). Keys `1` to `0` and `-`. On the drums the five buttons are kick,
  snare, hat, tom and crash; the low octave key changes them to the big drums (boom, rim, open hat, floor tom, ride) and
  the high one to the toys (clap, block, shake, bell, splash).
- **Loop station**: record (`R`; counts a bar in from a standstill), play/stop (`Space`), undo (`Z`), clear this
  track, mute this track, metronome (`M`), tempo, loop length (1, 2, 4 or 8 bars; doubling repeats what is there),
  and four sections A to D that swap at the end of the loop.
- **Menu**: tuning (which five notes), key, snap, song mode (plays the sections in turn), the house band, new song,
  send to the station radio, save as a MIDI file, MIDI keyboard in, sound.
- **The radio**: in the Wayside arcade, "Send to the station radio" posts the playing loop to the page
  (`ONE_MAN_BAND_SONG`), which keeps it on the player's account; the radio on the station's bench plays it
  on 94.7 for them and on 101.3 for everyone else. The page answers `ONE_MAN_BAND_SAVED`.
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
| `scripts/hud.gd` | Every control, drawn by hand, multi-touch, scaled down to fit any screen |
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
