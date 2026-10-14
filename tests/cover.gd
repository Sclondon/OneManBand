extends SceneTree
## The arcade cartridge's cover picture: him from behind, looking back over his shoulder.
## godot --audio-driver Dummy --path . -s tests/cover.gd -- --out=<file.png> [--turn=DEGREES] [--away=METRES]
## The camera goes round behind him by `turn` (the sign picks the shoulder he looks over).

var save := "user://cover_test.json"
var main: Band
var out := "user://cover.png"
var turn := -118.0
var away := 2.0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		if arg.begins_with("--turn="):
			turn = float(arg.trim_prefix("--turn="))
		if arg.begins_with("--away="):
			away = float(arg.trim_prefix("--away="))
	DisplayServer.window_set_size(Vector2i(1104, 620))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	main = load("res://main.tscn").instantiate()
	main.save_path = save
	main.show_help_first = false
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	for i in 20:
		await process_frame
	main.press("i%d" % Kit.ACCORDION)
	for i in 50:
		await process_frame
	# Hold everything still, then turn him to look back at the camera
	main.set_process(false)
	main.man.set_process(false)
	var side := signf(turn)
	var p: Dictionary = main.man.p
	p.torso.rotation.y = 0.4 * side
	p.head.rotation = Vector3(-0.08, 1.3 * side, 0.1 * side)
	main.man.skin.set_shader_parameter("face", main.man.faces.grin)
	var basis := Basis(Vector3.UP, deg_to_rad(turn)) * Basis(Vector3.RIGHT, -0.04)
	main.camera.basis = basis
	main.camera.position = Band.SUBJECT + Vector3(0, 0.3, 0) + basis.z * away
	main.hud.visible = false
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	quit()
