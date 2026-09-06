class_name RagdollGrab
extends Node

signal grabbed(body: RigidBody3D)
signal released(body: RigidBody3D)

@export var actor_path: NodePath
@export var arm_chains: PackedStringArray = PackedStringArray(["arm_l", "arm_r"])
@export var chest_slot: String = "chest"
@export var hands_at_chain_tip: bool = false
@export_group("Reach")
@export_range(0.1, 3.0, 0.01) var reach: float = 0.6
@export_range(0.0, 1.5, 0.01) var hand_spacing: float = 0.3
@export_range(-1.0, 1.0, 0.01) var hand_height: float = 0.0
@export_range(0.05, 1.5, 0.01) var grab_radius: float = 0.7
@export_range(0.0, 0.5, 0.01) var grab_lead_time: float = 0.1
@export_range(-89.0, 0.0, 1.0) var pitch_min_degrees: float = -80.0
@export_range(0.0, 89.0, 1.0) var pitch_max_degrees: float = 70.0
@export_flags_3d_physics var grab_mask: int = 1
@export_range(0.0, 3.0, 0.05) var arm_strength: float = 1.6
@export_range(0.0, 2.0, 0.01) var blend_time: float = 0.2
@export var pole_offset: Vector3 = Vector3(0.0, -0.5, -0.5)
@export_group("Hold")
@export_range(0.0, 200.0, 0.5) var lift_mass_limit: float = 10.0
@export_range(0.01, 1.0, 0.01) var lift_response_time: float = 0.08
@export_range(0.5, 30.0, 0.5) var lift_speed_max: float = 5.0
@export_range(0.0, 2000.0, 10.0) var lift_force_max: float = 150.0
@export_range(0.0, 5000.0, 10.0) var pull_force_max: float = 1200.0
@export_range(0.0, 10.0, 0.1) var drag_speed_max: float = 1.5
@export_range(0.01, 1.0, 0.01) var pull_response_time: float = 0.15
@export_range(0.0, 3.0, 0.05) var leash_slack: float = 0.4
@export_range(0.1, 3.0, 0.05) var break_slack: float = 1.0
@export_range(0.0, 2.0, 0.01) var break_time: float = 0.15
@export_range(0.0, 1.0, 0.05) var held_speed_scale: float = 0.6
@export_group("Trip")
@export_range(0.0, 2.0, 0.05) var trip_time: float = 0.2
@export_range(0.0, 2.0, 0.05) var trip_slack: float = 0.25
@export_range(0.0, 20.0, 0.5) var trip_impulse: float = 5.0

var hold: bool = false
var aim_pitch: float = 0.0
var actor: RagdollActor
var character: RagdollCharacter
var held: RagdollGrabHold
var shown_body: RigidBody3D
var shown_kind: RagdollGrabHold.Kind = RagdollGrabHold.Kind.PULL

var _arms := RagdollArmIK.new()
var _sphere := SphereShape3D.new()
var _sync := RagdollGrabSync.new()
var _chest_index: int = -1


func _ready() -> void:
	actor = RagdollIKSupport.find_actor(self, actor_path)
	if actor == null:
		push_warning("RagdollGrab %s found no RagdollActor" % name)
		return
	character = RagdollGrabHold.character_of(self)
	_sphere.radius = grab_radius
	_sync.name = "Sync"
	_sync.grab = self
	add_child(_sync)
	RagdollIKSupport.when_ready(actor, _setup)


func _setup() -> void:
	_arms.setup(actor, arm_chains, "Grab", hands_at_chain_tip)
	_chest_index = actor.get_skeleton().find_bone(actor.profile.bone_map.bone_for(chest_slot))


func simulates() -> bool:
	return multiplayer.is_server()


func is_holding() -> bool:
	return shown_body != null


func held_body() -> RigidBody3D:
	return shown_body


func pull_direction() -> Vector3:
	if shown_body == null or shown_kind != RagdollGrabHold.Kind.PULL or character == null:
		return Vector3.ZERO
	var point := held.point() if held != null else shown_body.global_position
	var to_point := point - character.global_position
	return Vector3(to_point.x, 0.0, to_point.z).normalized()


func chest_bone() -> RagdollBone:
	return actor.bone_for_slot(chest_slot)


func forward() -> Vector3:
	if character != null:
		return (character.global_transform.basis * character.model_forward).normalized()
	return actor.get_skeleton().global_transform.basis.z.normalized()


func up() -> Vector3:
	if character != null:
		return character.global_basis.y
	return Vector3.UP


func chest_position() -> Vector3:
	return RagdollIKSupport.bone_world_position(actor.get_skeleton(), _chest_index)


func aim_direction() -> Vector3:
	var pitch := clampf(aim_pitch, deg_to_rad(pitch_min_degrees), deg_to_rad(pitch_max_degrees))
	return forward() * cos(pitch) + up() * sin(pitch)


func anchor() -> Vector3:
	return chest_position() + aim_direction() * reach + up() * hand_height


func _active() -> bool:
	return hold and not actor.is_limp and (character == null or character.is_controllable())


func _physics_process(delta: float) -> void:
	if actor == null or _chest_index < 0 or not simulates():
		return
	if not _active():
		release()
		return
	var hands := anchor()
	if held == null:
		_search(hands)
	elif not held.update(hands, delta):
		release()


func _process(delta: float) -> void:
	if actor == null or _chest_index < 0 or _arms.count() == 0:
		return
	_arms.blend_weight(1.0 if _active() else 0.0, delta, blend_time, arm_strength)
	if _arms.weight <= 0.0:
		return
	var center := anchor()
	if shown_body != null and shown_kind == RagdollGrabHold.Kind.LIFT:
		center = shown_body.global_position
	elif shown_body != null:
		center = held.point() if held != null else _sync.shown_point()
	var facing := forward()
	var right := facing.cross(up()).normalized()
	var chest := chest_position()
	for i in _arms.count():
		var shoulder := _arms.shoulder_position(i)
		var side := 1.0 if (shoulder - chest).dot(right) >= 0.0 else -1.0
		var target := center + right * side * hand_spacing * 0.5
		var pole := shoulder + right * pole_offset.x * side + up() * pole_offset.y + facing * pole_offset.z
		_arms.set_hand(i, target, pole)


func _search(hands: Vector3) -> void:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _sphere
	var lead := character.velocity * grab_lead_time if character != null else Vector3.ZERO
	query.transform = Transform3D(Basis(), hands + lead)
	query.collision_mask = grab_mask
	query.exclude = RagdollIKSupport.exclusions(actor)
	var best: RigidBody3D = null
	var best_distance := INF
	for hit in get_viewport().world_3d.direct_space_state.intersect_shape(query, 8):
		var body := hit.collider as RigidBody3D
		if body == null:
			continue
		var distance := body.global_position.distance_to(hands)
		if distance < best_distance:
			best = body
			best_distance = distance
	if best != null:
		grab(best, hands)


func grab(body: RigidBody3D, hands: Vector3) -> void:
	release()
	var liftable := body.mass <= lift_mass_limit and not (body is RagdollBone) and not body.freeze
	held = RagdollGrabHold.new()
	held.begin(self, body, RagdollGrabHold.Kind.LIFT if liftable else RagdollGrabHold.Kind.PULL, hands)
	_sync.announce(body, held.kind, held.local_point)
	grabbed.emit(body)


func release() -> void:
	if held == null:
		return
	var body := held.body
	held.end()
	held = null
	_sync.announce(null, RagdollGrabHold.Kind.PULL, Vector3.ZERO)
	released.emit(body)


func show_held(body: RigidBody3D, kind: RagdollGrabHold.Kind) -> void:
	shown_body = body
	shown_kind = kind
	if character != null and character.is_multiplayer_authority():
		character.speed_scale = held_speed_scale if body != null and kind == RagdollGrabHold.Kind.PULL else 1.0


func drag_character(target: RagdollCharacter, velocity: Vector3, scale: float) -> void:
	if target.is_multiplayer_authority():
		target.drag_velocity = velocity
		target.speed_scale = scale
		return
	for child in target.get_children():
		if child is RagdollNetSync:
			child.send_drag(velocity, scale)


func trip_character(target: RagdollCharacter, impulse: Vector3, slot: String) -> void:
	if target.is_multiplayer_authority():
		target.hit(impulse, character, slot)
		return
	for child in target.get_children():
		if child is RagdollNetSync:
			child.apply_hit(impulse, slot)


func stop_drag(target: RagdollCharacter) -> void:
	if target.is_multiplayer_authority():
		target.drag_velocity = Vector3.ZERO
		target.speed_scale = 1.0
		return
	for child in target.get_children():
		if child is RagdollNetSync:
			child.send_drag_end()
