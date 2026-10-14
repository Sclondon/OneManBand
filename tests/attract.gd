extends SceneTree
## Plays the game for the arcade's preview film: the house band going, a phrase on the trumpet, the
## choir called up to sing, the organ, the toy drums, and the controls put away for the dance.
## godot --path . --fixed-fps 30 --write-movie <out.avi> -s tests/attract.gd

const FPS := 30.0

var save := "user://attract.json"
var main: Band


func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	main = load("res://main.tscn").instantiate()
	main.save_path = save
	main.show_help_first = false
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await _beats(0.5)
	main.press("play")
	await _beats(2.0)
	main.press("i%d" % Kit.TRUMPET)
	await _phrase([0, 2, 4, 2, 3, 2, 1, 0])
	# The choir: the little folk run to their places and sing three long notes
	main.press("i%d" % Kit.CHOIR)
	await _beats(1.5)
	for b: int in [0, 2, 4]:
		main.hud._down("n%d" % b)
		await _beats(1.4)
		main.hud._up("n%d" % b)
		await _beats(0.1)
	main.press("i%d" % Kit.ORGAN)
	await _beats(1.0)
	await _phrase([0, 2, 4, 2, 4, 3, 2, 4])
	# The toy drums, then the controls put away for the dance
	main.press("i%d" % Kit.DRUMS)
	main.press("up")
	await _beats(0.5)
	await _phrase([0, 2, 1, 3, 0, 4])
	main.press("up")
	main.press("hide")
	await _beats(5.0)
	quit()


# One button every half beat
func _phrase(pads: Array) -> void:
	for b: int in pads:
		main.hud._down("n%d" % b)
		await _beats(0.4)
		main.hud._up("n%d" % b)
		await _beats(0.1)


func _beats(n: float) -> void:
	for i in roundi(n * 60.0 / main.looper.bpm * FPS):
		await process_frame
