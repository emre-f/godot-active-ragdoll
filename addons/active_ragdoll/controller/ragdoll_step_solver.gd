class_name RagdollStepSolver
extends Node

@export var actor_path: NodePath
@export_range(0.01, 2.0, 0.01) var step_distance: float = 0.25
@export_range(0.02, 2.0, 0.01) var step_time: float = 0.2
@export_range(0.0, 1.0, 0.01) var step_height: float = 0.1
@export_range(0.0, 1.0, 0.01) var velocity_lead: float = 0.15
@export_range(0.0, 3.0, 0.01) var ground_probe_depth: float = 0.6
@export_flags_3d_physics var ground_mask: int = 1
@export_range(1, 8) var groups: int = 2

var actor: RagdollActor
var legs: Array[Leg] = []
var steps_taken: int = 0

var _body: Node3D
var _exclude: Array[RID] = []


class Leg:
	var chain: RagdollChain
	var target: Node3D
	var home_local: Vector3
	var planted: Vector3
	var step_from: Vector3
	var step_to: Vector3
	var progress: float = 1.0
	var group: int = 0


func _ready() -> void:
	actor = RagdollIKSupport.find_actor(self, actor_path)
	if actor == null:
		push_warning("RagdollStepSolver %s found no RagdollActor" % name)
		return
	_body = get_parent() as Node3D
	RagdollIKSupport.when_ready(actor, _setup)


func _setup() -> void:
	var skeleton := actor.get_skeleton()
	_exclude = RagdollIKSupport.exclusions(actor)
	var chains := RagdollIKSupport.chains_of_type(actor, RagdollChain.ChainType.LEG)
	for i in chains.size():
		var chain := chains[i]
		var names := RagdollIKSupport.bone_names(actor, chain)
		var tip := skeleton.find_bone(names[names.size() - 1])
		if tip < 0 or names.size() < 2:
			continue
		var length := RagdollIKSupport.tip_length(skeleton, tip)
		var leg := Leg.new()
		leg.chain = chain
		leg.group = (i + i / 2) % groups
		leg.target = RagdollIKSupport.make_target(actor, "StepTarget_" + chain.chain_name)
		var tip_world := (skeleton.global_transform * skeleton.get_bone_global_rest(tip) * Vector3(0.0, length, 0.0))
		leg.home_local = _body.to_local(tip_world)
		leg.planted = _ground(tip_world)
		leg.target.global_position = leg.planted
		var ik := FABRIK3D.new()
		ik.setting_count = 1
		ik.set_root_bone_name(0, names[0])
		ik.set_end_bone_name(0, names[names.size() - 1])
		ik.set_extend_end_bone(0, true)
		ik.set_end_bone_direction(0, SkeletonModifier3D.BONE_DIRECTION_PLUS_Y)
		ik.set_end_bone_length(0, length)
		RagdollIKSupport.insert_modifier(actor, ik, "StepIK_" + chain.chain_name)
		ik.set_target_node(0, ik.get_path_to(leg.target))
		legs.append(leg)


func _ground(from: Vector3) -> Vector3:
	return RagdollIKSupport.ground_below(_body, from, ground_probe_depth, ground_mask, _exclude)


func _physics_process(delta: float) -> void:
	if legs.is_empty():
		return
	var body_velocity := Vector3.ZERO
	if _body is CharacterBody3D:
		body_velocity = _body.velocity
	body_velocity.y = 0.0
	var swinging := -1
	for leg in legs:
		if leg.progress < 1.0:
			swinging = leg.group
	for leg in legs:
		if leg.progress < 1.0:
			_advance(leg, delta)
			continue
		var desired := _ground(_body.to_global(leg.home_local) + body_velocity * velocity_lead)
		if desired.distance_to(leg.planted) > step_distance and (swinging < 0 or swinging == leg.group):
			swinging = leg.group
			leg.step_from = leg.planted
			leg.step_to = desired + body_velocity * step_time * 0.5
			leg.planted = leg.step_to
			leg.progress = 0.0
			steps_taken += 1
			_advance(leg, delta)
		else:
			leg.target.global_position = leg.planted


func _advance(leg: Leg, delta: float) -> void:
	leg.progress = minf(leg.progress + delta / step_time, 1.0)
	var lift := sin(leg.progress * PI) * step_height
	leg.target.global_position = leg.step_from.lerp(leg.step_to, leg.progress) + Vector3.UP * lift


func swinging_count() -> int:
	var count := 0
	for leg in legs:
		if leg.progress < 1.0:
			count += 1
	return count
