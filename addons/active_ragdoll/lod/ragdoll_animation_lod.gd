class_name RagdollAnimationLOD
extends RefCounted

var mixers: Array[AnimationMixer] = []
var saved_modes: Dictionary = {}
var reduced: bool = false


func apply(actor: RagdollActor, tier: RagdollLOD.Tier) -> void:
	var wants_reduced := tier >= RagdollLOD.Tier.T2_KINEMATIC
	if wants_reduced == reduced:
		return
	reduced = wants_reduced
	if mixers.is_empty():
		mixers = collect(actor)
	for mixer in mixers:
		if reduced:
			saved_modes[mixer] = mixer.callback_mode_process
			mixer.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		elif saved_modes.has(mixer):
			mixer.callback_mode_process = saved_modes[mixer]
	if not reduced:
		saved_modes.clear()


func advance(delta: float) -> void:
	for mixer in mixers:
		if mixer.active:
			mixer.advance(delta)


static func collect(actor: RagdollActor) -> Array[AnimationMixer]:
	var skeleton := actor.get_skeleton()
	var found: Array[AnimationMixer] = []
	if skeleton == null:
		return found
	var rig: Node = skeleton
	var scene_root := skeleton.get_tree().current_scene
	while rig.get_parent() != null and rig.get_parent() != scene_root and not rig.get_parent() is RagdollCharacter:
		rig = rig.get_parent()
	if rig.get_parent() is RagdollCharacter:
		rig = rig.get_parent()
	for mixer in rig.find_children("*", "AnimationMixer", true, false):
		found.append(mixer)
	return found
