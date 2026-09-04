class_name RagdollGenerator
extends RefCounted

const BODY_PREFIX := "RB_"
const JOINT_PREFIX := "J_"


static func build(actor: Node3D, skeleton: Skeleton3D, profile: RagdollProfile, scene_owner: Node = null) -> Array[RagdollBone]:
	clear(actor)
	var bones: Array[RagdollBone] = []
	var problems := profile.validate(skeleton)
	for problem in problems:
		push_warning("RagdollGenerator: %s" % problem)
	if not profile.bone_map.is_complete():
		return bones
	var archetype := profile.archetype
	var by_slot: Dictionary = {}
	var fitter := RagdollMeshFitter.for_skeleton(skeleton) if profile.fit_to_mesh else null
	var slot_bone_indices := PackedInt32Array()
	for slot in archetype.all_slots():
		slot_bone_indices.append(skeleton.find_bone(profile.bone_map.bone_for(slot)))
	for slot in archetype.all_slots():
		var bone := _build_body(actor, skeleton, profile, slot, by_slot, scene_owner, fitter, slot_bone_indices)
		by_slot[slot] = bone
		bones.append(bone)
	_assign_auto_masses(bones, profile)
	for bone in bones:
		if bone.parent_bone != null:
			_build_joint(actor, skeleton, profile, bone, scene_owner)
	_warn_mass_ratios(bones)
	if not Engine.is_editor_hint() and actor.has_method("refresh"):
		actor.refresh()
	return bones


static func clear(actor: Node3D) -> void:
	if not Engine.is_editor_hint() and actor.has_method("detach_bones"):
		actor.detach_bones()
	for child in actor.get_children():
		if child is RagdollBone or child is Generic6DOFJoint3D:
			actor.remove_child(child)
			child.queue_free()


static func _build_body(actor: Node3D, skeleton: Skeleton3D, profile: RagdollProfile, slot: String, by_slot: Dictionary, scene_owner: Node, fitter: RagdollMeshFitter, slot_bone_indices: PackedInt32Array) -> RagdollBone:
	var archetype := profile.archetype
	var settings := profile.settings_for(slot)
	var bone_index := skeleton.find_bone(profile.bone_map.bone_for(slot))
	var rest := skeleton.get_bone_global_rest(bone_index)
	var world := skeleton.global_transform * rest
	world.basis = world.basis.orthonormalized()
	var parent_slot := archetype.parent_slot(slot)
	var parent_bone: RagdollBone = by_slot.get(parent_slot)
	var direction_and_length := _bone_direction(skeleton, profile, slot, bone_index, parent_bone)
	var world_direction: Vector3 = direction_and_length[0]
	var length: float = direction_and_length[1]
	var axis_is_guess: bool = direction_and_length[2]
	if settings.length > 0.0:
		length = settings.length
	var bone := RagdollBone.new()
	bone.name = BODY_PREFIX + slot
	bone.slot = slot
	bone.bone_index = bone_index
	bone.parent_slot = parent_slot
	bone.parent_bone = parent_bone
	bone.strength = profile.stiffness_for(slot)
	bone.mass = settings.mass if settings.mass > 0.0 else 1.0
	bone.bone_length = length
	bone.bone_axis = (world.basis.inverse() * world_direction).normalized()
	var fitted := fitter.measure(bone_index, slot_bone_indices, bone.bone_axis, axis_is_guess) if fitter != null and fitter.has_data() else {}
	var center := bone.bone_axis * length * 0.5
	if not fitted.is_empty():
		bone.bone_axis = fitted.axis
		if settings.length <= 0.0:
			length = fitted.length
			bone.bone_length = length
		center = fitted.center
	bone.linear_damp = profile.linear_damp
	bone.angular_damp = profile.angular_damp
	bone.continuous_cd = profile.continuous_collision
	bone.physics_material_override = PhysicsMaterial.new()
	bone.physics_material_override.friction = profile.friction
	bone.physics_material_override.bounce = profile.bounce
	bone.collision_layer = profile.collision_layer
	bone.collision_mask = profile.collision_mask
	bone.top_level = true
	actor.add_child(bone)
	bone.global_transform = world
	RagdollShapeBuilder.build(bone, settings, profile, length, center, fitted.get("radius", 0.0))
	_own(bone, scene_owner)
	return bone


static func _bone_direction(skeleton: Skeleton3D, profile: RagdollProfile, slot: String, bone_index: int, parent_bone: RagdollBone) -> Array:
	var archetype := profile.archetype
	var origin := (skeleton.global_transform * skeleton.get_bone_global_rest(bone_index)).origin
	var next_slot := archetype.child_slot_in_chain(slot)
	if next_slot.is_empty() and slot == archetype.root_slot:
		next_slot = _first_attached_slot(archetype, slot)
	if not next_slot.is_empty():
		var next_index := skeleton.find_bone(profile.bone_map.bone_for(next_slot))
		if next_index >= 0:
			return _direction_to(origin, (skeleton.global_transform * skeleton.get_bone_global_rest(next_index)).origin, false)
	var farthest := _farthest_child(skeleton, bone_index, origin)
	if farthest >= 0:
		return _direction_to(origin, (skeleton.global_transform * skeleton.get_bone_global_rest(farthest)).origin, true)
	if parent_bone != null:
		var parent_direction := parent_bone.global_transform.basis * parent_bone.bone_axis
		return [parent_direction.normalized(), parent_bone.bone_length * profile.tip_length_ratio, true]
	var rest_up := (skeleton.global_transform * skeleton.get_bone_global_rest(bone_index)).basis.y
	return [rest_up.normalized(), 0.1, true]


static func _farthest_child(skeleton: Skeleton3D, bone_index: int, origin: Vector3) -> int:
	var best := -1
	var best_distance := 0.0
	for child in skeleton.get_bone_children(bone_index):
		var distance := origin.distance_to((skeleton.global_transform * skeleton.get_bone_global_rest(child)).origin)
		if distance > best_distance:
			best_distance = distance
			best = child
	return best


static func _direction_to(from: Vector3, to: Vector3, is_guess: bool) -> Array:
	var delta := to - from
	var length := delta.length()
	if length < 0.001:
		return [Vector3.UP, 0.05, true]
	return [delta / length, length, is_guess]


static func _first_attached_slot(archetype: RagdollArchetype, slot: String) -> String:
	var fallback := ""
	for chain in archetype.chains:
		if chain.parent_slot != slot or chain.slots.is_empty():
			continue
		if chain.chain_type == RagdollChain.ChainType.SPINE or chain.chain_type == RagdollChain.ChainType.TAIL:
			return chain.slots[0]
		if fallback.is_empty():
			fallback = chain.slots[0]
	return fallback


static func _build_joint(actor: Node3D, skeleton: Skeleton3D, profile: RagdollProfile, bone: RagdollBone, scene_owner: Node) -> void:
	var joint := Generic6DOFJoint3D.new()
	joint.name = JOINT_PREFIX + bone.slot
	var world_axis := bone.global_transform.basis * bone.bone_axis
	actor.add_child(joint)
	joint.global_transform = Transform3D(RagdollShapeBuilder.basis_with_x(world_axis), bone.global_transform.origin)
	joint.exclude_nodes_from_collision = true
	joint.node_a = joint.get_path_to(bone.parent_bone)
	joint.node_b = joint.get_path_to(bone)
	var twist := deg_to_rad(profile.twist_limit_for(bone.slot))
	var swing := deg_to_rad(profile.swing_limit_for(bone.slot))
	_set_axis_limits(joint, "x", twist)
	_set_axis_limits(joint, "y", swing)
	_set_axis_limits(joint, "z", swing)
	bone.joint = joint
	bone.joint_anchor_in_parent = bone.parent_bone.global_transform.affine_inverse() * bone.global_transform.origin
	_own(joint, scene_owner)


static func _set_axis_limits(joint: Generic6DOFJoint3D, axis: String, angular_limit: float) -> void:
	joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
	joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -angular_limit)
	joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, angular_limit)


static func _assign_auto_masses(bones: Array[RagdollBone], profile: RagdollProfile) -> void:
	var volumes := PackedFloat32Array()
	var total_volume := 0.0
	var fixed_mass := 0.0
	for bone in bones:
		var volume := 0.0
		if profile.settings_for(bone.slot).mass <= 0.0:
			volume = RagdollShapeBuilder.volume(bone)
			total_volume += volume
		else:
			fixed_mass += bone.mass
		volumes.append(volume)
	var free_mass := maxf(profile.total_mass - fixed_mass, 0.0)
	var floor_mass := profile.total_mass * profile.min_mass_share
	for i in bones.size():
		if volumes[i] <= 0.0:
			continue
		bones[i].mass = maxf(free_mass * volumes[i] / maxf(total_volume, 0.000001), floor_mass)


static func _warn_mass_ratios(bones: Array[RagdollBone]) -> void:
	for bone in bones:
		if bone.parent_bone == null:
			continue
		var ratio := bone.mass / bone.parent_bone.mass
		if ratio > 5.0 or ratio < 0.02:
			push_warning("RagdollGenerator: mass ratio %.2f between %s and %s is outside 0.02 to 5; joints may explode" % [ratio, bone.slot, bone.parent_bone.slot])


static func _own(node: Node, scene_owner: Node) -> void:
	if scene_owner == null:
		return
	node.owner = scene_owner
	for child in node.get_children():
		_own(child, scene_owner)
