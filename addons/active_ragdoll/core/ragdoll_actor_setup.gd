class_name RagdollActorSetup
extends RefCounted


static func has_generated_bones(actor: RagdollActor) -> bool:
	for child in actor.get_children():
		if child is RagdollBone:
			return true
	return false


static func collect_bones(actor: RagdollActor) -> void:
	var bones := actor.bones
	bones.clear()
	actor._total_mass = 0.0
	var skeleton := actor.get_skeleton()
	for child in actor.get_children():
		if child is RagdollBone:
			bones.append(child)
			actor._total_mass += child.mass
	actor.targets.resize(bones.size())
	actor.target_velocities.resize(bones.size())
	actor.target_angular_velocities.resize(bones.size())
	actor._previous_targets.resize(bones.size())
	for i in bones.size():
		actor.targets[i] = bones[i].global_transform
		actor.target_velocities[i] = Vector3.ZERO
		actor.target_angular_velocities[i] = Vector3.ZERO
	actor._free_bones = RagdollFreeBones.collect(skeleton, bones)
	actor._kinematic_bones = RagdollKinematicBones.collect(bones, actor.profile)
	actor._all_kinematic = PackedByteArray()
	actor._all_kinematic.resize(bones.size())
	actor._all_kinematic.fill(1)
	actor._write_order = RagdollFreeBones.hierarchy_order(skeleton, bones)


static func apply_collision_rules(actor: RagdollActor) -> void:
	if actor.profile.self_collision:
		return
	var bones := actor.bones
	for i in bones.size():
		for j in range(i + 1, bones.size()):
			bones[i].add_collision_exception_with(bones[j])


static func rebind_joints(actor: RagdollActor) -> void:
	for child in actor.get_children():
		if child is Generic6DOFJoint3D:
			var path_a: NodePath = child.node_a
			child.node_a = NodePath()
			child.node_a = path_a
