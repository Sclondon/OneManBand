# One Man Band

A grinning bandsman with a whole band on his back. Five buttons play five notes on
whichever instrument he has in his hands, and a loop station keeps what you played going while you put the next
thing on top. Godot 4.7, GL Compatibility, made to run in a browser and on a phone.

## Playing

- **Notes**: five round buttons with their note names on them, lowest on the left. Slide a finger
  from one to the next. Keys `A S D F G`.
- **The stick**: up and down bends what is sounding by up to a whole tone, sideways makes it wobble. Arrow keys.
  Under it are four keys that stay on until tapped again: flat and sharp move the five buttons a half step
  (`C`, `V`), and two drop or raise an octave (`Q`, `E`). Tapped a second time, flat and sharp go a whole step and
  the octave keys two octaves; a third tap puts them out. The whole steps are what make every note reachable in
  every tuning (Classic in C is D F A B D: without them there is no G).
- **Instruments**, on the shelf kind with kind (`Kit.SHELF_GROUPS`, each on a tray of its own): piccolo, bassoon,
  trumpet, tuba; viola, guitar, ukulele, electric guitar; piano, organ, accordion, theremin; the choir (the satyrs
  and imps line up and sing, and he conducts); bells, drums, hand percussion. Keys `1` to `0`, `-`, `=`, `[`, `]`,
  `\` and `'`, in that order. The
  electric holds a note for as long as it is held; the piano dies away by itself and stops when let go. On the drums the five buttons are kick,
  snare, hat, tom and crash; the low octave key changes them to the big drums (boom, rim, open hat, floor tom, ride) and
  the high one to the toys (clap, block, shake, bell, splash). The hand percussion goes the same way: guiro, cuica,
  tambourine, maracas and agogo; the skins (conga, bongo, surdo, timbale, cajon); and the bright things (claves,
  triangle, vibraslap, samba whistle, chimes). He shakes a tambourine and a maraca for it.
- **Loop station**: record (`R`; counts a bar in from a standstill), play/stop (`Space`), undo (`Z`), clear this
  track, mute this track, metronome (`M`), tempo (`,` and `.`; a tap is 1 bpm, holding runs it, then in fives), loop length (1, 2, 4 or 8 bars; doubling repeats what is there),
  and four sections A to D that swap at the end of the loop.
- **The pencil** (`P`): step entry, for putting notes exactly where they go, the way a sequencer takes them from
  a MIDI keyboard. Each note played goes in at a gold cursor, as long as the length key says (1/16 to a bar, `L`),
  and the cursor moves on by that much; buttons (or MIDI keys) held together go in as one chord, and are taken back
  by one undo. The sheet shows the bar the cursor is in; a tap on it moves the cursor there. Under the loop station
  are back and on (`←` `→`), the length, a rest (`Enter`) and erase (`Backspace`). The loop can play while you write.
  Notes already there can be changed: drag one along (a sixteenth at a time, within its bar), up or down (to the
  next button), or by its end (longer or shorter). Tapped, it stays picked out with a red ring, and then the arrows
  move it (`↑` `↓` too), the length key sets its length, and erase takes it out. Each change is one undo.
- **More room**: the tab over the instruments (`X`) tucks them away while you play, to see more of him.
- **Watching**: the eye (`H`) puts the controls away while the loop plays; a tap anywhere, or the loop stopping,
  brings them back. With the loop going the little folk dance it, a new figure every four bars.
- **Menu**: tuning (which five notes), key, snap, song mode (plays the sections in turn), the sample songs (three, in
  turn: the house band, a march and a hymn), new song, send to the station radio, MIDI keyboard in, save as a
  MIDI file, save as sound (a WAV, written a slice each frame by `SongRender` so the band plays on meanwhile; the
  loop that is up, or with song mode on every part in turn, ringing out at the end), sound. In a browser the two
  saves are downloads.
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
| `scripts/looper.gd` | The loop station: sections, tracks, recording, step entry, undo |
| `scripts/midi.gd` | Writes a song as a standard MIDI file |
| `scripts/render.gd` | `SongRender`: plays a song into a WAV, a slice at a time (the menu's save, and `tools/render_song.gd`) |
| `scripts/bandsman.gd` | The man: arms that reach for what he holds, the rest bobbing to the beat, painted faces |
| `scripts/stage.gd` | The green, sky, day and night, rain, fireflies, floating notes |
| `scripts/hud.gd` | Every control, drawn by hand, multi-touch, scaled down to fit any screen |
| `scripts/n64.gd`, `shaders/` | The one vertex-lit material and the sky |
| `art/make_models.py` | Builds `models/*.glb` (and `art/*.blend`) in Blender |
| `tools/render_samples.gd` | Synthesises `sounds/*.res` |
| `tools/render_song.gd` | Plays a saved song into a WAV that loops without a seam, headless |

## Rebuilding things

```
blender --background --python art/make_models.py -- <this folder>
godot --headless --path . -s tools/render_samples.gd
godot --headless --path . --import
godot --headless --audio-driver Dummy --fixed-fps 60 --path . -s tests/smoke.gd
godot --audio-driver Dummy --path . -s tests/shots.gd -- --shots=<dir> [--portrait] [--close] [--turn=75]
godot --headless --path . --export-release "Web" build/index.html
```
