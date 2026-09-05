class_name RagdollActorUpdate
extends RefCounted


static func physics(actor: RagdollActor, delta: float) -> void:
	var driven := actor.drive_enabled and not actor.is_limp and actor.profile.driver != null
	if driven and actor.lod_tier == RagdollLOD.Tier.T2_KINEMATIC:
		kinematic_lod_tick(actor, delta)
		return
	if actor.bones.is_empty():
		return
	RagdollKinematicBones.update(actor, actor._kinematic_bones, driven and actor.strength_scale >= 1.0)
	if driven:
		actor._drive_tick += 1
		if actor._drive_tick >= actor.drive_interval:
			actor._drive_tick = 0
			var step := delta * actor.drive_interval
			actor._reset_target_velocity = RagdollTargetVelocity.measure(actor, actor._previous_targets, step, actor._reset_target_velocity)
			actor.profile.driver.drive(actor, step)
	if actor.is_limp and actor._settle.update(actor, delta):
		actor.settled.emit()


static func kinematic_lod_tick(actor: RagdollActor, delta: float) -> void:
	actor._drive_tick += 1
	if actor._drive_tick >= actor.kinematic_interval:
		actor._drive_tick = 0
		if not actor.bones.is_empty():
			RagdollKinematicBones.update(actor, actor._all_kinematic, true)
		actor._animation_lod.advance(delta * actor.kinematic_interval)
	actor._reset_target_velocity = true


static func write_pose(actor: RagdollActor, skeleton: Skeleton3D) -> void:
	var to_skeleton := skeleton.global_transform.affine_inverse()
	var capture_targets := not actor.is_limp
	var bones := actor.bones
	for i in bones.size():
		if capture_targets:
			actor.targets[i] = skeleton.global_transform * skeleton.get_bone_global_pose(bones[i].bone_index)
	if capture_targets and actor.lod_tier == RagdollLOD.Tier.T2_KINEMATIC:
		return
	RagdollFreeBones.follow_root(skeleton, to_skeleton, bones[0], actor._free_bones)
	for i in actor._write_order:
		var bone := bones[i]
		var pose := to_skeleton * (actor.targets[i] if bone.freeze else bone.global_transform)
		pose.basis = pose.basis.orthonormalized()
		skeleton.set_bone_global_pose(bone.bone_index, pose)


static func snap_to_skeleton(actor: RagdollActor) -> void:
	var skeleton := actor.get_skeleton()
	if skeleton == null:
		return
	for i in actor.bones.size():
		var bone := actor.bones[i]
		var pose := skeleton.global_transform * skeleton.get_bone_global_pose(bone.bone_index)
		pose.basis = pose.basis.orthonormalized()
		bone.global_transform = pose
		bone.linear_velocity = Vector3.ZERO
		bone.angular_velocity = Vector3.ZERO
		actor.targets[i] = pose
	actor._reset_target_velocity = true
