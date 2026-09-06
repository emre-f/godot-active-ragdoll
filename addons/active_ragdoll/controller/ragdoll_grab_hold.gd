class_name RagdollGrabHold
extends RefCounted

enum Kind { LIFT, PULL }

var body: RigidBody3D
var kind: Kind = Kind.PULL
var local_point: Vector3 = Vector3.ZERO

var _grab: RagdollGrab
var _carry_basis: Basis = Basis()
var _victim: RagdollCharacter
var _leg_hold: bool = false
var _trip_time: float = 0.0
var _stretched_time: float = 0.0
var _excluded: Array[PhysicsBody3D] = []


func begin(grab: RagdollGrab, target: RigidBody3D, hold_kind: Kind, anchor: Vector3) -> void:
	_grab = grab
	body = target
	kind = hold_kind
	if kind == Kind.LIFT:
		_begin_lift(anchor)
	else:
		_begin_pull(anchor)


func _begin_lift(anchor: Vector3) -> void:
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	for bone in _grab.actor.bones:
		_exclude(bone)
	if _grab.character != null:
		_exclude(_grab.character)
	_carry_basis = _holder_basis().inverse() * body.global_basis


func _holder_basis() -> Basis:
	var facing := _grab.forward()
	var up := _grab.up()
	if facing.cross(up).length_squared() < 0.0001:
		return Basis()
	return Basis.looking_at(facing, up)


func _carry(anchor: Vector3, delta: float) -> void:
	body.sleeping = false
	var to_anchor := anchor - body.global_position
	body.linear_velocity = (to_anchor / _grab.lift_response_time).limit_length(_grab.lift_speed_max)
	var target_basis := _holder_basis() * _carry_basis
	var rotation := (target_basis * body.global_basis.inverse()).get_rotation_quaternion()
	var angle := rotation.get_angle()
	if angle > PI:
		angle -= TAU
	body.angular_velocity = rotation.get_axis() * angle / maxf(delta * 4.0, _grab.lift_response_time) if absf(angle) > 0.001 else Vector3.ZERO


func _begin_pull(anchor: Vector3) -> void:
	local_point = body.to_local(_surface_point(anchor))
	_victim = character_of(body)
	for bone in _grab.actor.bones:
		_exclude(bone)
	_leg_hold = _victim != null and body is RagdollBone and _is_leg(body)


func _is_leg(bone: RagdollBone) -> bool:
	var chain := _victim.actor.profile.archetype.chain_for_slot(bone.slot)
	return chain != null and chain.chain_type == RagdollChain.ChainType.LEG


func _surface_point(anchor: Vector3) -> Vector3:
	var center := body.global_position
	var fallback := Vector3(anchor.x, center.y, anchor.z)
	var space := body.get_world_3d().direct_space_state
	var exclude := RagdollIKSupport.exclusions(_grab.actor)
	for pair in [[anchor, Vector3(center.x, anchor.y, center.z)], [fallback, center]]:
		var query := PhysicsRayQueryParameters3D.create(pair[0], pair[1], _grab.grab_mask, exclude)
		var hit := space.intersect_ray(query)
		if not hit.is_empty() and hit.collider == body:
			return hit.position
	return fallback


func point() -> Vector3:
	return body.to_global(local_point)


func update(anchor: Vector3, delta: float) -> bool:
	if not is_instance_valid(body) or not body.is_inside_tree():
		return false
	if kind == Kind.LIFT:
		_carry(anchor, delta)
		return true
	if _victim != null and _victim.is_dead():
		return false
	var grab_point := point()
	var rope := _grab.chest_position() - grab_point
	rope.y = 0.0
	var stretch := rope.length() - _grab.reach
	if stretch > _grab.break_slack:
		_stretched_time += delta
		if _stretched_time >= _grab.break_time:
			return false
	else:
		_stretched_time = 0.0
	var toward_holder := rope.normalized()
	_leash_holder(toward_holder, stretch)
	var pull_speed := maxf(stretch, 0.0) / _grab.pull_response_time
	if _victim != null and _victim.is_controllable():
		if _trips(stretch, delta):
			_grab.trip_character(_victim, (toward_holder + Vector3.UP * 0.5).normalized() * _grab.trip_impulse * _victim.actor.total_mass(), body.slot)
		else:
			_grab.drag_character(_victim, toward_holder * minf(pull_speed, _grab.drag_speed_max), _grab.held_speed_scale)
		return true
	body.sleeping = false
	var mass := _victim.actor.total_mass() if _victim != null else body.mass
	var point_velocity := body.linear_velocity + body.angular_velocity.cross(grab_point - body.global_position)
	var force := (toward_holder * pull_speed - point_velocity) * mass / _grab.pull_response_time
	var lift_speed := (anchor.y - grab_point.y) / _grab.pull_response_time
	var lift := (lift_speed - point_velocity.y) * mass / _grab.pull_response_time
	force.y = clampf(lift, -_grab.lift_force_max, _grab.lift_force_max)
	body.apply_force(force.limit_length(_grab.pull_force_max + _grab.lift_force_max), grab_point - body.global_position)
	return true


func _trips(stretch: float, delta: float) -> bool:
	if not _leg_hold or stretch < _grab.trip_slack:
		_trip_time = 0.0
		return false
	_trip_time += delta
	return _trip_time >= _grab.trip_time


func _leash_holder(toward_holder: Vector3, stretch: float) -> void:
	if _grab.character == null:
		return
	var excess := stretch - _grab.leash_slack
	var velocity := Vector3.ZERO
	if excess > 0.0:
		velocity = -toward_holder * minf(excess / _grab.pull_response_time, _grab.drag_speed_max)
	_grab.drag_character(_grab.character, velocity, _grab.held_speed_scale)


func end() -> void:
	if is_instance_valid(body):
		if kind == Kind.LIFT:
			body.linear_velocity = body.linear_velocity.limit_length(_grab.lift_speed_max)
		for other in _excluded:
			if is_instance_valid(other):
				body.remove_collision_exception_with(other)
				other.remove_collision_exception_with(body)
	_excluded.clear()
	if is_instance_valid(_victim):
		_grab.stop_drag(_victim)
	if kind == Kind.PULL and _grab.character != null:
		_grab.stop_drag(_grab.character)


func _exclude(other: PhysicsBody3D) -> void:
	body.add_collision_exception_with(other)
	other.add_collision_exception_with(body)
	_excluded.append(other)


static func character_of(node: Node) -> RagdollCharacter:
	var current := node
	while current != null and not current is RagdollCharacter:
		current = current.get_parent()
	return current as RagdollCharacter
