class_name RagdollAim
extends Node

@export var actor_path: NodePath
@export var arm_chains: PackedStringArray = PackedStringArray(["arm_r"])
@export_range(0.1, 3.0, 0.01) var reach: float = 0.55
@export_range(0.0, 3.0, 0.05) var aim_strength: float = 1.6
@export_range(0.0, 2.0, 0.01) var blend_time: float = 0.25
@export var pole_offset: Vector3 = Vector3(0.0, -0.5, -0.5)
@export var look_with_head: bool = true
@export var head_slot: String = "head"
@export_enum("+X", "-X", "+Y", "-Y", "+Z", "-Z") var head_forward_axis: int = 4
@export_range(0.0, 180.0, 1.0) var head_limit_degrees: float = 70.0

var actor: RagdollActor
var aim_active: bool = false
var aim_origin: Vector3 = Vector3.ZERO
var aim_direction: Vector3 = Vector3.FORWARD
var weight: float = 0.0

var _iks: Array[TwoBoneIK3D] = []
var _targets: Array[Node3D] = []
var _poles: Array[Node3D] = []
var _shoulders: PackedInt32Array = PackedInt32Array()
var _chains: Array[RagdollChain] = []
var _look: LookAtModifier3D
var _look_target: Node3D


func _ready() -> void:
	actor = RagdollIKSupport.find_actor(self, actor_path)
	if actor == null:
		push_warning("RagdollAim %s found no RagdollActor" % name)
		return
	RagdollIKSupport.when_ready(actor, _setup)


func _setup() -> void:
	var skeleton := actor.get_skeleton()
	for chain_name in arm_chains:
		var chain := RagdollIKSupport.chain_named(actor, chain_name)
		if chain == null or chain.slots.size() < 3:
			push_warning("RagdollAim: chain %s needs three slots" % chain_name)
			continue
		var names := RagdollIKSupport.bone_names(actor, chain)
		var target := RagdollIKSupport.make_target(actor, "AimTarget_" + chain_name)
		var pole := RagdollIKSupport.make_target(actor, "AimPole_" + chain_name)
		var ik := TwoBoneIK3D.new()
		ik.setting_count = 1
		ik.set_root_bone_name(0, names[0])
		ik.set_middle_bone_name(0, names[1])
		ik.set_end_bone_name(0, names[2])
		ik.influence = 0.0
		RagdollIKSupport.insert_modifier(actor, ik, "AimIK_" + chain_name)
		ik.set_target_node(0, ik.get_path_to(target))
		ik.set_pole_node(0, ik.get_path_to(pole))
		_iks.append(ik)
		_targets.append(target)
		_poles.append(pole)
		_shoulders.append(skeleton.find_bone(names[0]))
		_chains.append(chain)
	if look_with_head:
		_setup_look(skeleton)


func _setup_look(skeleton: Skeleton3D) -> void:
	var head_bone := actor.profile.bone_map.bone_for(head_slot)
	if skeleton.find_bone(head_bone) < 0:
		return
	_look_target = RagdollIKSupport.make_target(actor, "LookTarget")
	_look = LookAtModifier3D.new()
	_look.bone_name = head_bone
	_look.forward_axis = head_forward_axis
	_look.use_angle_limitation = true
	_look.symmetry_limitation = true
	_look.primary_limit_angle = deg_to_rad(head_limit_degrees)
	_look.secondary_limit_angle = deg_to_rad(head_limit_degrees)
	_look.influence = 0.0
	RagdollIKSupport.insert_modifier(actor, _look, "AimLook")
	_look.target_node = _look.get_path_to(_look_target)


func _pole_world_offset() -> Vector3:
	var flat := Vector3(aim_direction.x, 0.0, aim_direction.z).normalized()
	if flat.is_zero_approx():
		flat = Vector3.FORWARD
	var right := flat.cross(Vector3.UP)
	return right * pole_offset.x + Vector3.UP * pole_offset.y + flat * pole_offset.z


func set_aim(origin: Vector3, direction: Vector3) -> void:
	aim_origin = origin
	aim_direction = direction.normalized()


func _process(delta: float) -> void:
	if actor == null or (_iks.is_empty() and _look == null):
		return
	var goal := 1.0 if aim_active and not actor.is_limp else 0.0
	var step := delta / maxf(blend_time, 0.001)
	var previous := weight
	weight = move_toward(weight, goal, step)
	var skeleton := actor.get_skeleton()
	for i in _iks.size():
		var shoulder := RagdollIKSupport.bone_world_position(skeleton, _shoulders[i])
		_targets[i].global_position = shoulder + aim_direction * reach
		_poles[i].global_position = shoulder + _pole_world_offset()
		_iks[i].influence = weight
		if weight != previous:
			actor.set_strength_multiplier(lerpf(1.0, aim_strength, weight), _chains[i].chain_name)
	if _look != null:
		_look_target.global_position = aim_origin + aim_direction * 20.0
		_look.influence = weight
