class_name RagdollCharacter
extends CharacterBody3D

signal state_changed(old_state: State, new_state: State)

enum State { DRIVEN, KNOCKED, SETTLING, RECOVERING, DEAD }

@export var actor_path: NodePath
@export var model_forward: Vector3 = Vector3.BACK
@export_group("Movement")
@export_range(0.0, 20.0, 0.1) var walk_speed: float = 3.0
@export_range(0.0, 30.0, 0.1) var run_speed: float = 6.0
@export_range(0.0, 200.0, 1.0) var acceleration: float = 25.0
@export_range(0.0, 50.0, 0.1) var turn_speed: float = 12.0
@export_range(0.5, 50.0, 0.1) var max_turn_rate: float = 6.0
@export_range(0.0, 20.0, 0.1) var jump_speed: float = 4.5
@export_group("Capsule")
@export var auto_capsule: bool = true
@export_range(0.05, 2.0, 0.01) var capsule_radius: float = 0.3
@export_range(0.1, 5.0, 0.01) var capsule_height: float = 1.8
@export_group("Knock")
@export_range(0.0, 50.0, 0.1) var knock_impulse_threshold: float = 4.0
@export_range(0.0, 30.0, 0.1) var settle_timeout: float = 4.0
@export_range(0.0, 5.0, 0.05) var rest_time: float = 0.4
@export_range(0.05, 5.0, 0.05) var get_up_time: float = 1.2
@export var get_up_animation: String = ""

var actor: RagdollActor
var state: State = State.DRIVEN
var move_input: Vector3 = Vector3.ZERO
var face_direction: Vector3 = Vector3.ZERO
var running: bool = false
var jump_requested: bool = false

var _gravity: float = 9.8
var _state_time: float = 0.0
var _saved_layer: int = 0
var _saved_mask: int = 0
var _animation_player: AnimationPlayer


func _ready() -> void:
	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	actor = _find_actor()
	if actor == null:
		push_warning("RagdollCharacter %s has no RagdollActor below it" % name)
		return
	if auto_capsule and not _has_shape():
		_add_capsule()
	for bone in actor.bones:
		add_collision_exception_with(bone)
		bone.add_collision_exception_with(self)
	var players := find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_animation_player = players[0]


func _find_actor() -> RagdollActor:
	if not actor_path.is_empty():
		return get_node_or_null(actor_path) as RagdollActor
	var found := find_children("*", "RagdollActor", true, false)
	return found[0] if not found.is_empty() else null


func _has_shape() -> bool:
	for child in get_children():
		if child is CollisionShape3D:
			return true
	return false


func _add_capsule() -> void:
	var shape := CollisionShape3D.new()
	shape.name = "Capsule"
	shape.shape = CapsuleShape3D.new()
	shape.shape.radius = capsule_radius
	shape.shape.height = capsule_height
	shape.position = Vector3(0.0, capsule_height * 0.5, 0.0)
	add_child(shape)


func _physics_process(delta: float) -> void:
	if actor == null:
		return
	_state_time += delta
	match state:
		State.DRIVEN:
			_move(delta)
		State.KNOCKED:
			_follow_root()
			if actor.is_settled() or _state_time >= settle_timeout:
				_enter(State.SETTLING)
		State.SETTLING:
			_follow_root()
			if _state_time >= rest_time:
				_enter(State.RECOVERING)
		State.DEAD:
			if not actor.is_baked:
				_follow_root()
		State.RECOVERING:
			_stand(delta)
			var progress := clampf(_state_time / get_up_time, 0.0, 1.0)
			actor.strength_scale = progress * progress
			if progress >= 1.0:
				_enter(State.DRIVEN)


func _move(delta: float) -> void:
	var wish := Vector3(move_input.x, 0.0, move_input.z).limit_length(1.0)
	var target_speed := run_speed if running else walk_speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(wish * target_speed, acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		if jump_requested:
			velocity.y = jump_speed
	else:
		velocity.y -= _gravity * delta
	jump_requested = false
	move_and_slide()
	_turn_toward(face_direction if face_direction.length_squared() > 0.0001 else wish, delta)


func _stand(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= _gravity * delta
	move_and_slide()


func _turn_toward(direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.0001:
		return
	var target_yaw := atan2(direction.x, direction.z) - atan2(model_forward.x, model_forward.z)
	var step := wrapf(lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta)) - rotation.y, -PI, PI)
	rotation.y += clampf(step, -max_turn_rate * delta, max_turn_rate * delta)


func _follow_root() -> void:
	var root := actor.root_bone()
	global_position = Vector3(root.global_position.x, actor.lowest_point(), root.global_position.z)


func _enter(new_state: State) -> void:
	var old_state := state
	state = new_state
	_state_time = 0.0
	match new_state:
		State.KNOCKED, State.DEAD:
			velocity = Vector3.ZERO
			_set_capsule_enabled(false)
		State.RECOVERING:
			_follow_root()
			_set_capsule_enabled(true)
			actor.root_snap_enabled = false
			actor.strength_scale = 0.0
			actor.resume_drive()
			if not get_up_animation.is_empty() and _animation_player != null:
				_animation_player.play(get_up_animation)
		State.DRIVEN:
			actor.strength_scale = 1.0
			actor.root_snap_enabled = true
			if actor.is_limp:
				actor.resume_drive()
	state_changed.emit(old_state, new_state)


func _set_capsule_enabled(enabled: bool) -> void:
	if enabled:
		collision_layer = _saved_layer
		collision_mask = _saved_mask
		return
	if collision_layer == 0 and collision_mask == 0:
		return
	_saved_layer = collision_layer
	_saved_mask = collision_mask
	collision_layer = 0
	collision_mask = 0


func knock(impulse: Vector3, source: Node = null) -> void:
	if state != State.DRIVEN:
		if not actor.is_baked:
			actor.root_bone().apply_central_impulse(impulse)
		return
	actor.knock(impulse, source)
	_enter(State.KNOCKED)


func kill(impulse: Vector3 = Vector3.ZERO, source: Node = null) -> void:
	if state == State.DEAD:
		return
	actor.bake_when_settled = true
	if state == State.DRIVEN or not actor.is_limp:
		actor.knock(impulse, source)
	elif not actor.is_baked:
		actor.root_bone().apply_central_impulse(impulse)
	_enter(State.DEAD)


func is_dead() -> bool:
	return state == State.DEAD


func hit(impulse: Vector3, source: Node = null, slot: String = "") -> void:
	if actor.is_baked:
		return
	if impulse.length() >= knock_impulse_threshold * actor.total_mass():
		knock(impulse, source)
		return
	var bone := actor.bone_for_slot(slot) if not slot.is_empty() else null
	if bone == null:
		bone = actor.root_bone()
	bone.apply_central_impulse(impulse)


func is_controllable() -> bool:
	return state == State.DRIVEN


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func state_name() -> String:
	return State.keys()[state]
