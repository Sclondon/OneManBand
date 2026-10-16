extends SceneTree
## Plays a One Man Band song into a WAV file, without the game running (SongRender does the
## playing). What rings on past the end is laid over the start, so the file loops without a seam.
## Other games use it to take their music from here.
##   godot --headless --path . -s tools/render_song.gd -- <song.json> <out.wav> [rate]
## A song is what Looper.to_dict() saves: {bpm, bars, sections: [[a track per instrument]]}, a
## note being [beat, beats long, button, note].


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("render_song: <song.json> <out.wav> [rate]")
		quit(1)
		return
	var song: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var rate := int(args[2]) if args.size() > 2 else SongRender.RATE
	var render := SongRender.new(song, rate, true)
	while not render.work(1000):
		pass
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	file.store_buffer(render.bytes)
	file.close()
	print("rendered %s: %.1f s" % [args[1], render.frames / float(rate)])
	quit()
