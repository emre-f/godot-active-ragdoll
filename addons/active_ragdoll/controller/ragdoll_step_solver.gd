class_name RagdollStepSolver
extends Node

@export var actor_path: NodePath
@export_range(0.01, 2.0, 0.01) var step_distance: float = 0.25
@export_range(0.02, 2.0, 0.01) var step_time: float = 0.2
@export_range(0.02, 1.0, 0.01) var min_step_time: float = 0.08
@export_range(0.0, 1.0, 0.01) var step_height: float = 0.1
@export_range(0.0, 1.0, 0.01) var velocity_lead: float = 0.15
@export_range(0.0, 0.5, 0.005) var foot_height: float = 0.0
@export_range(0.0, 3.0, 0.01) var ground_probe_depth: float = 0.6
@export_flags_3d_physics var ground_mask: int = 1
@export_range(1, 8) var groups: int = 2
@export_range(0.05, 5.0, 0.05) var pole_lift: float = 0.5
@export_range(0.0, 5.0, 0.05) var pole_out: float = 0.5
@export_range(1.0, 4.0, 0.1) var overreach_ratio: float = 2.0

var actor: RagdollActor
var legs: Array[Leg] = []
var steps_taken: int = 0

var _body: Node3D
var _exclude: Array[RID] = []
var _leg_radius: float = 0.0
var _last_forward: Vector3 = Vector3.BACK
var _swing_time: float = 0.2


class Leg:
	var chain: RagdollChain
	var target: Node3D
	var pole: Node3D
	var tibia_body: int
	var foot_shift_body: Vector3
	var pole_local: Vector3
	var home_local: Vector3
	var planted: Vector3
	var step_from: Vector3
	var step_to: Vector3
	var progress: float = 1.0
	var swing_time: float = 0.2
	var group: int = 0


func _ready() -> void:
	actor = RagdollIKSupport.find_actor(self, actor_path)
	if actor == null:
		push_warning("RagdollStepSolver %s found no RagdollActor" % name)
		return
	_body = get_parent() as Node3D
	RagdollIKSupport.when_ready(actor, _setup)


func _setup() -> void:
	_exclude = RagdollIKSupport.exclusions(actor)
	var chains := RagdollIKSupport.chains_of_type(actor, RagdollChain.ChainType.LEG)
	for i in chains.size():
		var leg := _make_leg(chains[i])
		if leg == null:
			continue
		leg.group = (i + i / 2) % groups
		legs.append(leg)
		_leg_radius = maxf(_leg_radius, Vector2(leg.home_local.x, leg.home_local.z).length())
	_last_forward = _body.global_basis.z


func _make_leg(chain: RagdollChain) -> Leg:
	var skeleton := actor.get_skeleton()
	var names := RagdollIKSupport.bone_names(actor, chain)
	if names.size() < 2:
		return null
	var knee := skeleton.find_bone(names[names.size() - 2])
	var tibia := skeleton.find_bone(names[names.size() - 1])
	if knee < 0 or tibia < 0:
		return null
	var leg := Leg.new()
	leg.chain = chain
	leg.tibia_body = _body_index(tibia)
	var tibia_rest := skeleton.get_bone_global_rest(tibia)
	var children := skeleton.get_bone_children(tibia)
	var ik := TwoBoneIK3D.new()
	ik.setting_count = 1
	ik.set_root_bone_name(0, names[names.size() - 2])
	ik.set_middle_bone_name(0, names[names.size() - 1])
	var ankle_local := Vector3.ZERO
	if children.is_empty():
		ankle_local = Vector3(0.0, RagdollIKSupport.tip_length(skeleton, tibia), 0.0)
		ik.set_use_virtual_end(0, true)
		ik.set_extend_end_bone(0, true)
		ik.set_end_bone_direction(0, SkeletonModifier3D.BONE_DIRECTION_PLUS_Y)
		ik.set_end_bone_length(0, ankle_local.y)
	else:
		ik.set_end_bone(0, children[0])
		ankle_local = skeleton.get_bone_rest(children[0]).origin
	var leaf_local := tibia_rest.affine_inverse() * skeleton.get_bone_global_rest(_leaf_below(skeleton, tibia)).origin
	var to_world := skeleton.global_transform
	leg.foot_shift_body = _body.global_transform.basis.inverse() * (to_world.basis * tibia_rest.basis * (leaf_local - ankle_local))
	var foot_world := to_world * tibia_rest * leaf_local
	var knee_world := to_world * skeleton.get_bone_global_rest(tibia).origin
	leg.home_local = _body.to_local(foot_world)
	var outward := knee_world - _body.global_position
	outward.y = 0.0
	leg.pole_local = _body.to_local(knee_world + outward.normalized() * pole_out + Vector3.UP * pole_lift)
	leg.planted = _ground(foot_world)
	leg.target = RagdollIKSupport.make_target(actor, "StepTarget_" + chain.chain_name)
	leg.pole = RagdollIKSupport.make_target(actor, "StepPole_" + chain.chain_name)
	RagdollIKSupport.insert_modifier(actor, ik, "StepIK_" + chain.chain_name)
	ik.set_target_node(0, ik.get_path_to(leg.target))
	ik.set_pole_node(0, ik.get_path_to(leg.pole))
	_place(leg, leg.planted)
	return leg


func _body_index(bone_index: int) -> int:
	for i in actor.bones.size():
		if actor.bones[i].bone_index == bone_index:
			return i
	return -1


static func _leaf_below(skeleton: Skeleton3D, bone_index: int) -> int:
	var origin := skeleton.get_bone_global_rest(bone_index).origin
	var best := bone_index
	var best_distance := 0.0
	var pending := Array(skeleton.get_bone_children(bone_index))
	while not pending.is_empty():
		var current: int = pending.pop_back()
		pending.append_array(skeleton.get_bone_children(current))
		var distance := origin.distance_to(skeleton.get_bone_global_rest(current).origin)
		if distance > best_distance:
			best_distance = distance
			best = current
	return best


func _ground(from: Vector3) -> Vector3:
	return RagdollIKSupport.ground_below(_body, from, ground_probe_depth, ground_mask, _exclude, up())


func up() -> Vector3:
	return _body.global_basis.y


func _place(leg: Leg, foot: Vector3) -> void:
	leg.target.global_position = foot + up() * foot_height - _body.global_transform.basis * leg.foot_shift_body
	leg.pole.global_position = _body.to_global(leg.pole_local)


func _physics_process(delta: float) -> void:
	if legs.is_empty():
		return
	var body_velocity := Vector3.ZERO
	if _body is CharacterBody3D:
		body_velocity = _body.velocity
	body_velocity -= up() * body_velocity.dot(up())
	var forward := _body.global_basis.z
	var speed := body_velocity.length() + _last_forward.angle_to(forward) / delta * _leg_radius
	_last_forward = forward
	_swing_time = clampf(step_distance / maxf(speed, 0.001), min_step_time, step_time)
	var group := _group_to_step(body_velocity, speed) if swinging_count() == 0 else -1
	for leg in legs:
		if leg.progress >= 1.0 and (leg.group == group or _overreached(leg, body_velocity)):
			_start_step(leg, body_velocity)
		if leg.progress < 1.0:
			_advance(leg, delta)
		else:
			_place(leg, leg.planted)


func _desired(leg: Leg, body_velocity: Vector3) -> Vector3:
	return _ground(_body.to_global(leg.home_local) + body_velocity * velocity_lead)


func _overreached(leg: Leg, body_velocity: Vector3) -> bool:
	return _desired(leg, body_velocity).distance_to(leg.planted) > step_distance * overreach_ratio


func _group_to_step(body_velocity: Vector3, speed: float) -> int:
	var worst_group := -1
	var stride := speed * _swing_time
	var worst_distance := minf(step_distance, maxf(stride * 0.5, step_distance * 0.2))
	for leg in legs:
		var distance := _desired(leg, body_velocity).distance_to(leg.planted)
		if distance > worst_distance:
			worst_distance = distance
			worst_group = leg.group
	return worst_group


func _start_step(leg: Leg, body_velocity: Vector3) -> void:
	leg.swing_time = _swing_time
	leg.step_from = leg.planted
	leg.step_to = _desired(leg, body_velocity) + body_velocity * leg.swing_time * 0.5
	leg.planted = leg.step_to
	leg.progress = 0.0
	steps_taken += 1


func _advance(leg: Leg, delta: float) -> void:
	leg.progress = minf(leg.progress + delta / leg.swing_time, 1.0)
	var lift := sin(leg.progress * PI) * step_height
	_place(leg, leg.step_from.lerp(leg.step_to, leg.progress) + up() * lift)


func swinging_count() -> int:
	var count := 0
	for leg in legs:
		if leg.progress < 1.0:
			count += 1
	return count
