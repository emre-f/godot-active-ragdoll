class_name RagdollBaker
extends RefCounted


static func bake(actor: RagdollActor, skeleton: Skeleton3D) -> void:
	actor.is_baked = true
	var poses := capture_global_poses(skeleton)
	free_bodies(actor)
	pause_animation(skeleton)
	write_local_poses.call_deferred(skeleton, poses)
	actor.set_physics_process(false)
	actor.active = false
	actor.baked.emit()


static func capture_global_poses(skeleton: Skeleton3D) -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	poses.resize(skeleton.get_bone_count())
	for bone_index in skeleton.get_bone_count():
		poses[bone_index] = skeleton.get_bone_global_pose(bone_index)
	return poses


static func write_local_poses(skeleton: Skeleton3D, global_poses: Array[Transform3D]) -> void:
	for bone_index in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(bone_index)
		var local := global_poses[bone_index]
		if parent >= 0:
			local = global_poses[parent].affine_inverse() * local
		local.basis = local.basis.orthonormalized()
		skeleton.set_bone_pose(bone_index, local)


static func free_bodies(actor: RagdollActor) -> void:
	for child in actor.get_children():
		if child is RagdollBone or child is Generic6DOFJoint3D:
			actor.remove_child(child)
			child.queue_free()
	actor.detach_bones()


static func pause_animation(skeleton: Skeleton3D) -> void:
	var rig: Node = skeleton
	var scene_root := skeleton.get_tree().current_scene
	while rig.get_parent() != null and rig.get_parent() != scene_root and not rig.get_parent() is RagdollCharacter:
		rig = rig.get_parent()
	for mixer in rig.find_children("*", "AnimationMixer", true, false):
		mixer.active = false
