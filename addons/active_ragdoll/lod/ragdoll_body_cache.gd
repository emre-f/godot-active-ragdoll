class_name RagdollBodyCache
extends RefCounted

var bones: Array[RagdollBone] = []


func release(actor: RagdollActor) -> void:
	for child in actor.get_children():
		if child is RagdollBone:
			bones.append(child)
			actor.remove_child(child)
		elif child is Generic6DOFJoint3D:
			actor.remove_child(child)
	actor.detach_bones()


func restore(actor: RagdollActor) -> void:
	var skeleton := actor.get_skeleton()
	for bone in bones:
		bone.freeze = false
		bone.collision_layer = actor.profile.collision_layer
		bone.collision_mask = actor.profile.collision_mask
		var pose := skeleton.global_transform * skeleton.get_bone_global_pose(bone.bone_index)
		pose.basis = pose.basis.orthonormalized()
		bone.transform = pose
		actor.add_child(bone)
	bones.clear()
	RagdollActorSetup.collect_bones(actor)
	actor.snap_to_skeleton()
	var to_actor := actor.global_transform.affine_inverse()
	for bone in actor.bones:
		if bone.joint == null:
			continue
		var world_axis := bone.global_transform.basis * bone.bone_axis
		bone.joint.transform = to_actor * Transform3D(RagdollShapeBuilder.basis_with_x(world_axis), bone.global_transform.origin)
		actor.add_child(bone.joint)


func has_bodies() -> bool:
	return not bones.is_empty()


func free_all() -> void:
	for bone in bones:
		if bone.joint != null:
			bone.joint.free()
		bone.free()
	bones.clear()
