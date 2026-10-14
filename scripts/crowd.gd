class_name Crowd
extends Node3D
## The little folk out of the woods (models/kids.glb: satyr kids and straw-hatted wood imps):
## they run round and round the bandstand, stop to watch, and jump about when there is music. Some of the tunes in the song
## book set them all dancing, or off on a game of tag.
##
## Each keeps to a ring round the stand: where it is is an angle (0 is out in front) and how
## far out, and it runs round the ring to where it is going, so nobody cuts across the stage.

const MODEL: PackedScene = preload("res://models/kids.glb")
const COUNT := 6
# Half of them have climbed up onto the stand itself and run round him there, where they are
# always in the picture; the rest keep to the grass: [nearest, furthest, the same round the
# back (wider there, to clear the curtain's posts and stay inside the fence), how high]
const RINGS := [[1.45, 1.78, 1.45, 1.78, Stage.FLOOR], [2.55, 3.5, 3.4, 4.2, 0.0]]

var phase := -1.0        # how far through the beat the loop is, or -1 when it is stopped
var lively := false      # there is music
var dancing := 0.0       # seconds of dancing left
var tag := 0.0           # seconds of tag left
var choir := false       # he is conducting: everyone lines up in front of him
var singing := 0.0       # seconds of a sung note left
var time := 0.0
var kids: Array[Dictionary] = []


func _ready() -> void:
	var model := MODEL.instantiate()
	add_child(model)
	N64.dress(model, N64.mat())
	for i in COUNT:
		# (even ones are satyrs and odd ones wood imps: both rings get some of each, so the imps
		# are not all out on the grass at the edge of the picture)
		var ring: Array = RINGS[(i / 2 + i) % 2]
		var node: Node3D = model.find_child("kid%d" % i, true, false)
		var kid := {
			"node": node,
			"legs": [node.find_child("kid%d_leg_L" % i, true, false), node.find_child("kid%d_leg_R" % i, true, false)],
			"arms": [node.find_child("kid%d_arm_L" % i, true, false), node.find_child("kid%d_arm_R" % i, true, false)],
			"place": i / float(COUNT - 1), "ring": ring, "a": randf() * TAU, "r": ring[0] + 0.2, "to_a": 0.0, "to_r": ring[0],
			"wait": randf_range(0.0, 2.0), "pace": randf_range(1.9, 2.9), "step": randf() * TAU, "hop": randf(),
		}
		_choose(kid)
		kids.append(kid)


# Everyone to the front, to dance for so long
func dance(seconds: float) -> void:
	dancing = seconds
	tag = 0.0
	for kid in kids:
		kid.wait = 0.0
		_choose(kid)


# Everyone into a row across the front, facing him, for as long as he conducts
func gather(on: bool) -> void:
	if choir == on:
		return
	choir = on
	for kid in kids:
		kid.wait = 0.0
		_choose(kid)


# A note of theirs is sounding
func sing(seconds: float) -> void:
	singing = maxf(singing, seconds)


# Everyone off round the stand as fast as they can go
func play_tag(seconds: float) -> void:
	tag = seconds
	dancing = 0.0
	for kid in kids:
		kid.wait = 0.0
		_choose(kid)


func _process(delta: float) -> void:
	time += delta
	dancing = maxf(0.0, dancing - delta)
	tag = maxf(0.0, tag - delta)
	singing = maxf(0.0, singing - delta)
	for kid in kids:
		var node: Node3D = kid.node
		var moving := false
		var way := 1.0
		if kid.wait > 0.0:
			kid.wait -= delta
			if kid.wait <= 0.0:
				_choose(kid)
		else:
			var gap: float = kid.to_a - kid.a
			# (off round the stand at a run for tag, and quicker still to their places in the choir)
			var pace: float = kid.pace * (1.8 if tag > 0.0 else (3.2 if choir else 1.0))
			var turn: float = pace / kid.r * delta
			if absf(gap) <= turn:
				kid.a = kid.to_a
				kid.wait = 0.02 if tag > 0.0 else (0.4 if choir else (dancing if dancing > 0.0 else randf_range(0.4, 4.0 if lively else 1.5)))
			else:
				kid.a += signf(gap) * turn
				kid.r = move_toward(kid.r, kid.to_r, pace * (1.0 if choir else 0.5) * delta)
				way = signf(gap)
				moving = true
		var at := Vector3(sin(kid.a) * kid.r, kid.ring[4], cos(kid.a) * kid.r)
		# Running, it looks where it is going; stood, at the band
		var yaw := atan2(cos(kid.a) * way, -sin(kid.a) * way) if moving else atan2(-at.x, -at.z)
		node.rotation.y = lerp_angle(node.rotation.y, yaw, 1.0 - exp(-10.0 * delta))
		var swing := 0.0
		var arms_up := 0.0
		node.rotation.z = 0.0
		node.rotation.x = 0.0
		if moving:
			kid.step += delta * kid.pace * 5.0
			swing = sin(kid.step)
			at.y += absf(swing) * 0.05
		else:
			var beat: float = phase if phase >= 0.0 else fposmod(time * 1.3 + kid.hop, 1.0)
			var jump := 0.2 if dancing > 0.0 else (0.08 if lively else 0.0)
			at.y += absf(sin(PI * fposmod(beat + kid.hop * (0.0 if dancing > 0.0 else 0.5), 1.0))) * jump
			if jump > 0.0:
				arms_up = 1.0 if dancing > 0.0 else 0.5 + 0.5 * sin(time * 0.7 + kid.hop * TAU)
			if dancing > 0.0:
				node.rotation.z = 0.18 * sin(time * 6.0 + kid.hop * TAU)
			if singing > 0.0:
				# Heads back and arms out, swaying, for as long as the note lasts
				var loud := clampf(singing * 5.0, 0.0, 1.0)
				at.y += 0.04 * loud * absf(sin(time * 4.0 + kid.hop * TAU))
				arms_up = maxf(arms_up, 0.4 * loud)
				node.rotation.x = -0.28 * loud
				node.rotation.z = 0.1 * loud * sin(time * 2.2 + kid.hop * TAU)
		node.position = at
		for side in 2:
			var flip := 1.0 if side == 0 else -1.0
			kid.legs[side].rotation.x = swing * 0.9 * flip
			kid.arms[side].rotation.x = lerpf(-swing * 0.7 * flip, -2.7 + 0.3 * sin(time * 8.0 + kid.hop * TAU + side), arms_up)


# Where next: somewhere on its ring, the short way round
func _choose(kid: Dictionary) -> void:
	var to: float
	if choir and tag <= 0.0:
		# (its own place in the row)
		kid.to_a = lerpf(-1.15, 1.15, kid.place)
		kid.to_r = kid.ring[0] + 0.12
		return
	if tag > 0.0:
		# (round and round, all the same way)
		kid.to_a = kid.a + 2.4
		kid.to_r = kid.ring[1]
		return
	if dancing > 0.0:
		to = randf_range(-1.6, 1.6)
	elif lively and randf() < 0.6:
		# (to one side or the other, to watch)
		to = randf_range(0.5, 1.7) * (1.0 if randf() < 0.5 else -1.0)
	else:
		to = randf_range(-PI, PI)
	kid.to_a = kid.a + wrapf(to - kid.a, -PI, PI)
	kid.to_r = randf_range(kid.ring[0], kid.ring[1]) if absf(to) < 1.9 else randf_range(kid.ring[2], kid.ring[3])
