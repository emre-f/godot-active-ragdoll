class_name RagdollNetSync
extends Node

signal event_received(kind: int, impulse: Vector3)

enum Event { KNOCK, KILL, RECOVER, HIT }

@export_range(1.0, 120.0, 1.0) var send_rate: float = 20.0
@export_range(0.0, 1.0, 0.01) var interpolation_delay: float = 0.1
@export_range(0.0, 2.0, 0.01) var interpolation_delay_max: float = 0.5
@export var adaptive_delay: bool = true
@export_range(0.5, 10.0, 0.5) var jitter_scale: float = 3.0
@export_range(0.01, 1.0, 0.01) var clock_smoothing: float = 0.1
@export_range(0.5, 10.0, 0.5) var bake_timeout: float = 3.0
@export_range(0.1, 20.0, 0.1) var snap_distance: float = 2.0
@export_range(0.0, 30.0, 0.5) var correction_rate: float = 6.0
@export_range(0.05, 2.0, 0.05) var drag_timeout: float = 0.25

var grab: RagdollGrab
var crouch: RagdollCrouch
var _drag_time_left: float = 0.0

var character: RagdollCharacter
var buffer := RagdollNetBuffer.new()
var clock := RagdollNetClock.new()
var root_pinned: bool = false
var arrived: bool = false
var bake_wait: float = 0.0
var states_received: int = 0
var events_received: int = 0
var _send_timer: float = 0.0
var _last_impulse: Vector3 = Vector3.ZERO


func _ready() -> void:
	character = get_parent() as RagdollCharacter
	if character == null:
		push_warning("RagdollNetSync %s must be a child of a RagdollCharacter" % name)
		return
	if character.is_node_ready():
		_on_character_ready()
	else:
		character.ready.connect(_on_character_ready, CONNECT_ONE_SHOT)


func _on_character_ready() -> void:
	for child in character.get_children():
		if child is RagdollGrab:
			grab = child
		if child is RagdollCrouch:
			crouch = child
	if character.actor == null or not is_multiplayer_authority():
		return
	character.actor.knocked.connect(_on_knocked)
	character.state_changed.connect(_on_state_changed)
	character.hit_applied.connect(_on_hit_applied)


func _physics_process(delta: float) -> void:
	if character == null or character.actor == null:
		return
	if is_multiplayer_authority():
		_send(delta)
		_expire_drag(delta)
	else:
		RagdollNetRemote.follow(self, delta)


func _send(delta: float) -> void:
	_send_timer += delta
	if _send_timer < 1.0 / send_rate:
		return
	_send_timer = 0.0
	_receive_state.rpc(local_time(), character.global_position, character.rotation.y, character.velocity, character.state, character.running, root_transform(), grab != null and grab.hold, grab.aim_pitch if grab != null else 0.0, crouch != null and crouch.crouching, character.actor.is_baked)


static func local_time() -> float:
	return Time.get_ticks_msec() / 1000.0


func sample_time(delta: float) -> float:
	var latest := buffer.latest()
	var max_delay := interpolation_delay_max if adaptive_delay else interpolation_delay
	return clock.sample_time(local_time(), latest.time, 1.0 / send_rate, interpolation_delay, maxf(max_delay, interpolation_delay), jitter_scale, 0.05, delta)


func root_transform() -> Transform3D:
	var actor := character.actor
	if not actor.bones.is_empty():
		return actor.bones[0].global_transform
	var skeleton := actor.get_skeleton()
	var root_index := skeleton.find_bone(actor.profile.bone_map.bone_for(actor.profile.archetype.root_slot))
	return skeleton.global_transform * skeleton.get_bone_global_pose(root_index)


func apply_hit(impulse: Vector3, slot: String = "") -> void:
	if not is_multiplayer_authority():
		_request_hit.rpc_id(get_multiplayer_authority(), impulse, slot)
		return
	character.hit(impulse, null, slot)


func _on_knocked(impulse: Vector3, _source: Node) -> void:
	_last_impulse = impulse


func _on_hit_applied(impulse: Vector3, slot: String) -> void:
	_receive_event.rpc(Event.HIT, impulse, slot)


func _on_state_changed(_old_state: RagdollCharacter.State, new_state: RagdollCharacter.State) -> void:
	match new_state:
		RagdollCharacter.State.KNOCKED:
			_receive_event.rpc(Event.KNOCK, _last_impulse, "")
		RagdollCharacter.State.DEAD:
			_receive_event.rpc(Event.KILL, _last_impulse, "")
		RagdollCharacter.State.RECOVERING:
			_receive_event.rpc(Event.RECOVER, Vector3.ZERO, "")
	_last_impulse = Vector3.ZERO


@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_state(sent_time: float, position: Vector3, yaw: float, velocity: Vector3, state: int, running: bool, root: Transform3D, hold: bool, aim_pitch: float, crouching: bool, baked: bool) -> void:
	clock.observe(sent_time, local_time(), clock_smoothing)
	var snapshot := RagdollNetState.new()
	snapshot.time = sent_time
	snapshot.position = position
	snapshot.yaw = yaw
	snapshot.velocity = velocity
	snapshot.state = state
	snapshot.running = running
	snapshot.root = root
	snapshot.hold = hold
	snapshot.aim_pitch = aim_pitch
	snapshot.crouching = crouching
	snapshot.baked = baked
	buffer.push(snapshot)
	states_received += 1


@rpc("authority", "call_remote", "reliable")
func _receive_event(kind: int, impulse: Vector3, slot: String) -> void:
	events_received += 1
	RagdollNetRemote.apply_event(self, kind, impulse, slot)
	event_received.emit(kind, impulse)


@rpc("any_peer", "call_remote", "reliable")
func _request_hit(impulse: Vector3, slot: String) -> void:
	if is_multiplayer_authority():
		apply_hit(impulse, slot)


func send_drag(velocity: Vector3, scale: float) -> void:
	_receive_drag.rpc_id(get_multiplayer_authority(), velocity, scale)


func send_drag_end() -> void:
	_receive_drag_end.rpc_id(get_multiplayer_authority())


func _expire_drag(delta: float) -> void:
	if _drag_time_left <= 0.0:
		return
	_drag_time_left -= delta
	if _drag_time_left <= 0.0:
		character.drag_velocity = Vector3.ZERO


func _stop_drag() -> void:
	_drag_time_left = 0.0
	character.drag_velocity = Vector3.ZERO
	character.speed_scale = 1.0


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _receive_drag(velocity: Vector3, scale: float) -> void:
	if multiplayer.get_remote_sender_id() != 1 or not is_multiplayer_authority():
		return
	character.drag_velocity = velocity
	character.speed_scale = scale
	_drag_time_left = drag_timeout


@rpc("any_peer", "call_remote", "reliable")
func _receive_drag_end() -> void:
	if multiplayer.get_remote_sender_id() == 1 and is_multiplayer_authority():
		_stop_drag()
