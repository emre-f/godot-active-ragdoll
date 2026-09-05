class_name RagdollKinematicBones
extends RefCounted


static func collect(bones: Array[RagdollBone], profile: RagdollProfile) -> PackedByteArray:
	var flags := PackedByteArray()
	flags.resize(bones.size())
	var archetype := profile.archetype
	if archetype == null:
		return flags
	for i in bones.size():
		if i == 0:
			flags[i] = 1 if archetype.root_kinematic_when_driven else 0
			continue
		var chain := archetype.chain_for_slot(bones[i].slot)
		flags[i] = 1 if chain != null and chain.kinematic_when_driven else 0
	return flags


static func update(actor: RagdollActor, flags: PackedByteArray, kinematic: bool) -> void:
	for i in flags.size():
		if flags[i] == 0:
			continue
		var bone := actor.bones[i]
		if bone.freeze != kinematic:
			bone.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			bone.freeze = kinematic
			if not kinematic:
				bone.sleeping = false
		if kinematic:
			var pose := actor.targets[i]
			pose.basis = pose.basis.orthonormalized()
			bone.global_transform = pose
