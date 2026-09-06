class_name RagdollClimb
extends Node

@export var enabled: bool = false
@export_flags_3d_physics var surface_mask: int = 1
@export_range(0.0, 2.0, 0.01) var probe_ahead: float = 0.5
@export_range(0.0, 0.5, 0.01) var contact_gap: float = 0.05
@export_range(0.1, 3.0, 0.05) var probe_depth: float = 0.6
@export_range(0.5, 40.0, 0.5) var align_speed: float = 10.0
@export_range(0.0, 3.0, 0.05) var fall_reset_time: float = 0.5

var character: RagdollCharacter
var grab: RagdollGrab
var surface_up: Vector3 = Vector3.UP
var on_surface: bool = false

var _exclude: Array[RID] = []
var _lost_time: float = 0.0


func _ready() -> void:
	character = get_parent() as RagdollCharacter
	if character == null:
		push_warning("RagdollClimb %s must be a child of a RagdollCharacter" % name)
		return
	if character.is_node_ready():
		_setup()
	else:
		character.ready.connect(_setup, CONNECT_ONE_SHOT)


func _setup() -> void:
	if character.actor != null:
		_exclude = RagdollIKSupport.exclusions(character.actor)
	for child in character.get_children():
		if child is RagdollGrab:
			grab = child


func _physics_process(delta: float) -> void:
	if character == null or character.actor == null:
		return
	if not character.is_controllable():
		_reset()
		return
	if not enabled:
		on_surface = false
		_align(Vector3.UP, delta)
		return
	var target := _probe()
	if target == Vector3.ZERO:
		_lost_time += delta
		on_surface = false
		_align(Vector3.UP if _lost_time > fall_reset_time else surface_up, delta)
		return
	_lost_time = 0.0
	on_surface = true
	_align(target, delta)


func _reset() -> void:
	surface_up = Vector3.UP
	on_surface = false
	_lost_time = 0.0
	character.up_direction = Vector3.UP
	_set_basis(Vector3.UP)


func heading() -> Vector3:
	var up := character.up_direction
	var along := character.move_input - up * character.move_input.dot(up)
	if along.length() < 0.1:
		along = character.velocity - up * character.velocity.dot(up)
	return along.normalized() if along.length_squared() > 0.0001 else Vector3.ZERO


func _probe() -> Vector3:
	var up := character.up_direction
	var radius := character.capsule_radius
	var center := character.global_position + up * character.capsule_height * 0.5
	var forward := heading()
	var below := _ray(center, center - up * probe_depth)
	var resting: Vector3 = below.normal if not below.is_empty() else Vector3.ZERO
	if forward != Vector3.ZERO:
		var ahead := _ray(center, center + forward * (radius + probe_ahead))
		if not ahead.is_empty():
			return _approach(resting, ahead, center, radius)
	if resting != Vector3.ZERO:
		return resting
	if forward != Vector3.ZERO:
		var beyond_edge := center + forward * (radius + probe_ahead) - up * probe_depth
		var around := _ray(beyond_edge, beyond_edge - forward * (radius + probe_ahead) * 2.0)
		if not around.is_empty():
			return around.normal
	return Vector3.ZERO


func _approach(resting: Vector3, ahead: Dictionary, center: Vector3, radius: float) -> Vector3:
	var normal: Vector3 = ahead.normal
	if resting == Vector3.ZERO:
		return normal
	var gap: float = (center - ahead.position).dot(normal) - radius
	var blend := clampf(1.0 - (gap - contact_gap) / probe_ahead, 0.0, 1.0)
	return resting.slerp(normal, blend).normalized()


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var exclude := _exclude
	if grab != null and grab.shown_body != null:
		exclude = _exclude.duplicate()
		exclude.append(grab.shown_body.get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, to, surface_mask, exclude)
	return character.get_world_3d().direct_space_state.intersect_ray(query)


func _align(target_up: Vector3, delta: float) -> void:
	if surface_up.dot(target_up) < -0.99:
		target_up = (target_up + character.global_basis.z * 0.1).normalized()
	surface_up = surface_up.slerp(target_up, 1.0 - exp(-align_speed * delta)).normalized()
	character.up_direction = surface_up
	_set_basis(surface_up)


func _set_basis(up: Vector3) -> void:
	var basis := character.global_basis
	var half_height := character.capsule_height * 0.5
	var center := character.global_position + basis.y * half_height
	var forward := basis.z - up * basis.z.dot(up)
	if forward.length_squared() < 0.0001:
		forward = basis.x.cross(up)
	forward = forward.normalized()
	character.global_basis = Basis(up.cross(forward), up, forward)
	character.global_position = center - up * half_height
