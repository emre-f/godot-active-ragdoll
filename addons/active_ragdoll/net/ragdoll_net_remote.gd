class_name RagdollNetRemote
extends RefCounted

const State := RagdollCharacter.State


static func follow(sync: RagdollNetSync, delta: float) -> void:
	var latest := sync.buffer.latest()
	if latest == null:
		return
	var target := sync.buffer.sample(sync.sample_time(delta))
	if not sync.arrived:
		sync.arrived = true
		teleport(sync, latest)
	coerce_state(sync, latest.state)
	if sync.grab != null:
		sync.grab.hold = latest.hold
		sync.grab.aim_pitch = target.aim_pitch
	if sync.crouch != null:
		sync.crouch.crouching = latest.crouching
	var character := sync.character
	if character.state == State.DRIVEN:
		unpin_root(sync)
		follow_capsule(sync, target, delta)
	elif character.state == State.RECOVERING:
		unpin_root(sync)
	else:
		pin_root(sync, target)
		follow_bake(sync, latest, delta)


static func teleport(sync: RagdollNetSync, target: RagdollNetState) -> void:
	var character := sync.character
	var offset := target.position - character.global_position
	character.global_position = target.position
	character.velocity = target.velocity
	character.rotation.y = target.yaw
	if not character.actor.bones.is_empty():
		character.actor.shift_bones(offset)


static func follow_capsule(sync: RagdollNetSync, target: RagdollNetState, delta: float) -> void:
	var character := sync.character
	var error := target.position - character.global_position
	if error.length() > sync.snap_distance:
		teleport(sync, target)
		error = Vector3.ZERO
	character.global_position += error * clampf(sync.correction_rate * delta, 0.0, 1.0)
	var top_speed := character.run_speed if target.running else character.walk_speed
	character.running = target.running
	character.move_input = (Vector3(target.velocity.x, 0.0, target.velocity.z) / maxf(top_speed, 0.01)).limit_length(1.0)
	character.face_direction = Basis(Vector3.UP, target.yaw) * character.model_forward
	if target.velocity.y > character.jump_speed * 0.5 and character.is_on_floor():
		character.jump_requested = true


static func coerce_state(sync: RagdollNetSync, authority_state: int) -> void:
	var character := sync.character
	var state := character.state
	if state == State.DEAD:
		return
	match authority_state:
		State.DRIVEN:
			if state == State.KNOCKED or state == State.SETTLING:
				character._enter(State.RECOVERING)
		State.KNOCKED, State.SETTLING:
			if state == State.DRIVEN or state == State.RECOVERING:
				character.actor.go_limp()
				character._enter(State.KNOCKED)
		State.RECOVERING:
			if state == State.KNOCKED or state == State.SETTLING:
				character._enter(State.RECOVERING)
		State.DEAD:
			character.kill(Vector3.ZERO)


static func apply_event(sync: RagdollNetSync, kind: int, impulse: Vector3, slot: String) -> void:
	var character := sync.character
	match kind:
		RagdollNetSync.Event.KNOCK:
			if character.state == State.DRIVEN:
				character.knock(impulse)
			elif not character.actor.is_baked:
				character.actor.root_bone().apply_central_impulse(impulse)
		RagdollNetSync.Event.KILL:
			character.kill(impulse)
		RagdollNetSync.Event.RECOVER:
			if character.state == State.KNOCKED or character.state == State.SETTLING:
				character._enter(State.RECOVERING)
		RagdollNetSync.Event.HIT:
			character.hit(impulse, null, slot)


static func follow_bake(sync: RagdollNetSync, latest: RagdollNetState, delta: float) -> void:
	var actor := sync.character.actor
	if not latest.baked or actor.is_baked or not actor.has_ragdoll():
		return
	sync.bake_wait += delta
	if actor.is_settled() or sync.bake_wait >= sync.bake_timeout:
		actor.bake()


static func pin_root(sync: RagdollNetSync, target: RagdollNetState) -> void:
	var actor := sync.character.actor
	if actor.bones.is_empty() or actor.is_baked:
		return
	var root := actor.bones[0]
	if not root.freeze:
		root.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		root.freeze = true
	sync.root_pinned = true
	var pose := target.root
	pose.basis = pose.basis.orthonormalized()
	root.global_transform = pose
	actor.targets[0] = pose


static func unpin_root(sync: RagdollNetSync) -> void:
	if not sync.root_pinned:
		return
	sync.root_pinned = false
	var actor := sync.character.actor
	if actor.bones.is_empty() or actor.all_kinematic_flags()[0] == 1 and actor.profile.archetype.root_kinematic_when_driven:
		return
	actor.bones[0].freeze = false
	actor.bones[0].sleeping = false
