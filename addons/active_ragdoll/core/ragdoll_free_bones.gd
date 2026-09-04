class_name RagdollFreeBones
extends RefCounted


static func collect(skeleton: Skeleton3D, bones: Array[RagdollBone]) -> PackedInt32Array:
	var free_bones := PackedInt32Array()
	var slot_bones := PackedInt32Array()
	for bone in bones:
		slot_bones.append(bone.bone_index)
	for bone_index in skeleton.get_bone_count():
		var current := bone_index
		var covered := false
		while current >= 0:
			if slot_bones.has(current):
				covered = true
				break
			current = skeleton.get_bone_parent(current)
		if not covered:
			free_bones.append(bone_index)
	return free_bones


static func follow_root(skeleton: Skeleton3D, to_skeleton: Transform3D, root: RagdollBone, free_bones: PackedInt32Array) -> void:
	if free_bones.is_empty():
		return
	var animated_root := skeleton.get_bone_global_pose(root.bone_index)
	var physics_root := to_skeleton * root.global_transform
	physics_root.basis = physics_root.basis.orthonormalized()
	var delta := physics_root * animated_root.affine_inverse()
	for bone_index in free_bones:
		skeleton.set_bone_global_pose(bone_index, delta * skeleton.get_bone_global_pose(bone_index))
