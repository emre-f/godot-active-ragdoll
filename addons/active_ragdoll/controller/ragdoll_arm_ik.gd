class_name RagdollArmIK
extends RefCounted

var actor: RagdollActor
var chains: Array[RagdollChain] = []
var shoulders: PackedInt32Array = PackedInt32Array()
var weight: float = 0.0

var _iks: Array[TwoBoneIK3D] = []
var _targets: Array[Node3D] = []
var _poles: Array[Node3D] = []


func setup(owner: RagdollActor, chain_names: PackedStringArray, prefix: String, hands_at_tip: bool = false) -> void:
	actor = owner
	var skeleton := actor.get_skeleton()
	var needed := 2 if hands_at_tip else 3
	for chain_name in chain_names:
		var chain := RagdollIKSupport.chain_named(actor, chain_name)
		if chain == null or chain.slots.size() < needed:
			push_warning("%s: chain %s needs %d slots" % [prefix, chain_name, needed])
			continue
		var names := RagdollIKSupport.bone_names(actor, chain)
		names = names.slice(names.size() - needed)
		var target := RagdollIKSupport.make_target(actor, prefix + "Target_" + chain_name)
		var pole := RagdollIKSupport.make_target(actor, prefix + "Pole_" + chain_name)
		var ik := TwoBoneIK3D.new()
		ik.setting_count = 1
		ik.set_root_bone_name(0, names[0])
		ik.set_middle_bone_name(0, names[1])
		if hands_at_tip:
			_end_at_tip(ik, skeleton, skeleton.find_bone(names[1]))
		else:
			ik.set_end_bone_name(0, names[2])
		ik.influence = 0.0
		RagdollIKSupport.insert_modifier(actor, ik, prefix + "IK_" + chain_name)
		ik.set_target_node(0, ik.get_path_to(target))
		ik.set_pole_node(0, ik.get_path_to(pole))
		_iks.append(ik)
		_targets.append(target)
		_poles.append(pole)
		shoulders.append(skeleton.find_bone(names[0]))
		chains.append(chain)


func _end_at_tip(ik: TwoBoneIK3D, skeleton: Skeleton3D, tip_bone: int) -> void:
	var children := skeleton.get_bone_children(tip_bone)
	if not children.is_empty():
		ik.set_end_bone(0, children[0])
		return
	ik.set_use_virtual_end(0, true)
	ik.set_extend_end_bone(0, true)
	ik.set_end_bone_direction(0, SkeletonModifier3D.BONE_DIRECTION_PLUS_Y)
	ik.set_end_bone_length(0, RagdollIKSupport.tip_length(skeleton, tip_bone))


func count() -> int:
	return _iks.size()


func shoulder_position(index: int) -> Vector3:
	return RagdollIKSupport.bone_world_position(actor.get_skeleton(), shoulders[index])


func set_hand(index: int, target_position: Vector3, pole_position: Vector3) -> void:
	_targets[index].global_position = target_position
	_poles[index].global_position = pole_position


func blend_weight(goal: float, delta: float, blend_time: float, strength: float) -> void:
	var previous := weight
	weight = move_toward(weight, goal, delta / maxf(blend_time, 0.001))
	for i in _iks.size():
		_iks[i].influence = weight
		if weight != previous:
			actor.set_strength_multiplier(lerpf(1.0, strength, weight), chains[i].chain_name)
