extends SceneTree
## Screenshots of the band at work.
## godot --audio-driver Dummy --path . -s tests/shots.gd -- --shots=<dir> [--portrait | --size=WxH] [--only=name,name] [--turn=DEGREES] [--close]
## With --turn the camera goes round him by that much; with --close it comes in on his top half.

var save := "user://shots_test.json"
var main: Band
var out := "user://shots"
var portrait := false
var only: PackedStringArray = []
var turned := 0.0
var close := false
var window := Vector2i.ZERO


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			out = arg.trim_prefix("--shots=")
		if arg == "--portrait":
			portrait = true
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",")
		if arg.begins_with("--turn="):
			turned = deg_to_rad(float(arg.trim_prefix("--turn=")))
		if arg == "--close":
			close = true
		if arg.begins_with("--size="):
			var parts := arg.trim_prefix("--size=").split("x")
			window = Vector2i(int(parts[0]), int(parts[1]))
	DirAccess.make_dir_recursive_absolute(out)
	if window == Vector2i.ZERO:
		window = Vector2i(540, 1100) if portrait else Vector2i(1280, 720)
	DisplayServer.window_set_size(window)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	main = load("res://main.tscn").instantiate()
	main.save_path = save
	main.show_help_first = false
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await _frames(20)
	for i in Kit.INSTRUMENTS.size():
		if not _wanted("inst_%d" % i):
			continue
		main.press("i%d" % i)
		await _frames(30)
		main.press("n2")
		await _frames(5)
		await _shot("inst_%d" % i)
		main.release("n2")
	main.press("i0")
	if _wanted("playing"):
		main.press("play")
		await _frames(100)
		await _shot("playing")
		main.press("rec")
		await _frames(20)
		main.press("n1")
		await _frames(20)
		main.release("n1")
		main.press("n4")
		await _frames(30)
		main.release("n4")
		await _shot("recording")
		main.press("play")
	if _wanted("night"):
		main.stage.set_night(true, true)
		main.stage.set_fireflies(true)
		await _frames(40)
		await _shot("night")
		main.stage.set_rain(true)
		await _frames(80)
		await _shot("rain")
		main.stage.set_night(false, true)
		main.stage.set_rain(false)
	if _wanted("stare"):
		main.man.startle()
		await _frames(5)
		await _shot("stare")
	if _wanted("menu"):
		main.press("menu")
		await _frames(3)
		await _shot("menu")
		main.press("close")
	if _wanted("book"):
		main.hud.book_open = true
		await _frames(3)
		await _shot("book")
		main.hud.book_open = false
	if _wanted("party"):
		main.press("play")
		main.crowd.dance(20.0)
		main.stage.release_balloons()
		main.stage.set_snow(true)
		main.stage.carnival = true
		await _frames(200)
		await _shot("party")
		main.crowd.play_tag(10.0)
		await _frames(120)
		await _shot("tag")
		main.press("play")
	# (only when asked for by name: each sample song played with the controls put away, a
	# picture in each of the four figures the little folk dance)
	if only.has("dance"):
		for k in Band.SAMPLES.size():
			main.load_demo(k)
			main.press("hide")
			for f in 4:
				var wait := 16.0 * 60.0 / main.looper.bpm
				await create_timer(wait * (0.6 if f == 0 else 1.0)).timeout
				await _shot("dance_%d_%d" % [k, f])
			main.press("play")
			await _frames(40)
	# (by name only: him with only what he is playing on him, and the menu that says so)
	if only.has("bare"):
		main.press("carry")
		await _frames(20)
		await _shot("bare")
		main.hud.menu_open = true
		await _frames(3)
		await _shot("bare_menu")
		main.hud.menu_open = false
		main.press("carry")
	if _wanted("help"):
		main.hud.help_open = true
		await _frames(3)
		await _shot("help")
	quit()


func _wanted(name: String) -> bool:
	return only.is_empty() or only.has(name)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	if turned != 0.0 or close:
		# After the game has set the camera for this frame, and before it is drawn
		var cam := main.camera
		var away := 2.6 if close else cam.position.distance_to(Band.SUBJECT)
		var basis := Basis(Vector3.UP, turned) * Basis(Vector3.RIGHT, -0.05)
		cam.basis = basis
		cam.position = Band.SUBJECT + (Vector3(0, 0.15, 0) if close else Vector3.ZERO) + basis.z * away
		main.hud.visible = false
		main.set_process(false)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ("_portrait" if portrait else "") + ("_%dx%d" % [window.x, window.y] if not portrait and window != Vector2i(1280, 720) else "") + ".png"))
	main.set_process(true)
