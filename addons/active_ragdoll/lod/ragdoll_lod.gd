class_name RagdollLOD
extends RefCounted

enum Tier { T0_FULL, T1_REDUCED, T2_KINEMATIC, T3_DORMANT }

const TIER_NAMES := ["T0", "T1", "T2", "T3"]


static func apply(actor: RagdollActor, tier: Tier) -> void:
	if actor.is_baked or actor.lod_tier == tier:
		return
	var old_tier := actor.lod_tier
	actor.lod_tier = tier
	actor.drive_interval = 2 if tier == Tier.T1_REDUCED else 1
	match tier:
		Tier.T3_DORMANT:
			_park_bodies(actor, false)
		Tier.T2_KINEMATIC:
			_park_bodies(actor, actor.profile.lod_kinematic_collision)
		_:
			if actor.is_released:
				actor.build_bodies()
			elif old_tier >= Tier.T2_KINEMATIC:
				_set_bodies_dynamic(actor, true, true)
				actor.snap_to_skeleton()
	actor.apply_animation_lod(tier)
	actor.lod_tier_changed.emit(old_tier, tier)


static func _park_bodies(actor: RagdollActor, collides: bool) -> void:
	if actor.profile.lod_kinematic_collision:
		_set_bodies_dynamic(actor, false, collides)
	else:
		actor.release_bodies()


static func _set_bodies_dynamic(actor: RagdollActor, dynamic: bool, collides: bool) -> void:
	for bone in actor.bones:
		bone.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		bone.freeze = not dynamic
		if dynamic:
			bone.sleeping = false
		bone.collision_layer = actor.profile.collision_layer if collides else 0
		bone.collision_mask = actor.profile.collision_mask if collides else 0


static func tier_name(tier: int) -> String:
	if tier < 0 or tier >= TIER_NAMES.size():
		return "?"
	return TIER_NAMES[tier]
