class_name RagdollFootSolver
extends Node

@export var actor_path: NodePath
@export_range(0.0, 3.0, 0.01) var ground_probe_depth: float = 0.6
@export_range(0.0, 0.5, 0.005) var foot_height: float = 0.0
@export_flags_3d_physics var ground_mask: int = 1
@export_range(0.0, 1.0, 0.01) var influence: float = 1.0
@export var pole_offset: Vector3 = Vector3(0.0, 0.0, 1.0)

var actor: RagdollActor
var _iks: Array[TwoBoneIK3D] = []
var _targets: Array[Node3D] = []
var _poles: Array[Node3D] = []
var _knees: PackedInt32Array = PackedInt32Array()
var _feet: PackedInt32Array = PackedInt32Array()
var _body: Node3D
var _exclude: Array[RID] = []
var last_offsets: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	actor = RagdollIKSupport.find_actor(self, actor_path)
	if actor == null:
		push_warning("RagdollFootSolver %s found no RagdollActor" % name)
		return
	_body = get_parent() as Node3D
	RagdollIKSupport.when_ready(actor, _setup)


func _setup() -> void:
	var skeleton := actor.get_skeleton()
	_exclude = RagdollIKSupport.exclusions(actor)
	for chain in RagdollIKSupport.chains_of_type(actor, RagdollChain.ChainType.LEG):
		if chain.slots.size() != 3:
			continue
		var names := RagdollIKSupport.bone_names(actor, chain)
		var target := RagdollIKSupport.make_target(actor, "FootTarget_" + chain.chain_name)
		var pole := RagdollIKSupport.make_target(actor, "FootPole_" + chain.chain_name)
		var ik := TwoBoneIK3D.new()
		ik.setting_count = 1
		ik.set_root_bone_name(0, names[0])
		ik.set_middle_bone_name(0, names[1])
		var shin := skeleton.find_bone(names[1])
		var foot := skeleton.find_bone(names[2])
		if skeleton.get_bone_parent(foot) == shin:
			ik.set_end_bone_name(0, names[2])
		else:
			ik.set_use_virtual_end(0, true)
			ik.set_extend_end_bone(0, true)
			ik.set_end_bone_direction(0, SkeletonModifier3D.BONE_DIRECTION_PLUS_Y)
			ik.set_end_bone_length(0, skeleton.get_bone_global_rest(shin).origin.distance_to(skeleton.get_bone_global_rest(foot).origin))
		ik.influence = influence
		RagdollIKSupport.insert_modifier(actor, ik, "FootIK_" + chain.chain_name)
		ik.set_target_node(0, ik.get_path_to(target))
		ik.set_pole_node(0, ik.get_path_to(pole))
		_iks.append(ik)
		_targets.append(target)
		_poles.append(pole)
		_knees.append(shin)
		_feet.append(foot)
		last_offsets.append(0.0)


func _process(_delta: float) -> void:
	if _iks.is_empty():
		return
	var skeleton := actor.get_skeleton()
	var floor_y := _body.global_position.y
	for i in _iks.size():
		var foot := RagdollIKSupport.bone_world_position(skeleton, _feet[i])
		var ground := RagdollIKSupport.ground_below(_body, foot, ground_probe_depth, ground_mask, _exclude)
		var offset := ground.y + foot_height - floor_y
		last_offsets[i] = offset
		_targets[i].global_position = foot + Vector3.UP * offset
		_poles[i].global_position = RagdollIKSupport.bone_world_position(skeleton, _knees[i]) + _body.global_transform.basis * pole_offset
		_iks[i].influence = influence
