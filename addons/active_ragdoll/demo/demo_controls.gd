extends Node3D

@export var crate_scene: PackedScene
@export var mouse_sensitivity: float = 0.003
@export var knock_strength: float = 6.0
@export var shot_impulse: float = 40.0
@export var crate_speed: float = 18.0

var characters: Array[RagdollCharacter] = []
var active: int = 0
var scripted: bool = false
var camera_rig: Node3D
var pitch: Node3D
var camera: Camera3D


func _ready() -> void:
	for node in find_children("*", "RagdollCharacter", true, false):
		characters.append(node)
	camera_rig = $CameraRig
	pitch = $CameraRig/Pitch
	camera = $CameraRig/Pitch/Arm/Camera3D
	if not scripted:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func player() -> RagdollCharacter:
	return characters[active % characters.size()]


func _unhandled_input(event: InputEvent) -> void:
	if scripted:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_rig.rotate_y(-event.relative.x * mouse_sensitivity)
		pitch.rotation.x = clampf(pitch.rotation.x - event.relative.y * mouse_sensitivity, deg_to_rad(-70), deg_to_rad(60))
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_LEFT:
			shoot()
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		KEY_TAB:
			active = (active + 1) % characters.size()
		KEY_K:
			var direction := Vector3(randf_range(-1, 1), randf_range(0.6, 1.5), randf_range(-1, 1)).normalized()
			player().knock(direction * knock_strength * player().actor.total_mass())
		KEY_X:
			player().kill(-camera.global_transform.basis.z * knock_strength * player().actor.total_mass())
		KEY_T:
			throw_crate()
		KEY_SPACE:
			player().jump_requested = true
		KEY_O:
			$Overlay.visible = not $Overlay.visible
		KEY_B:
			_toggle_bodies()
		KEY_R:
			get_tree().reload_current_scene()


func _physics_process(delta: float) -> void:
	var current := player()
	var forward := -camera_rig.global_transform.basis.z
	var right := camera_rig.global_transform.basis.x
	if not scripted:
		var input := Vector2.ZERO
		input.y = float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
		input.x = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		current.move_input = (forward * -input.y + right * input.x).limit_length(1.0)
		current.running = Input.is_key_pressed(KEY_SHIFT)
		set_aiming(Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))
		set_holding(Input.is_physical_key_pressed(KEY_E))
		var crouch := current.get_node_or_null("Crouch") as RagdollCrouch
		if crouch != null:
			crouch.crouching = Input.is_physical_key_pressed(KEY_CTRL)
	for character in characters:
		var wander := character.get_node_or_null("Wander") as RagdollDemoWander
		if wander != null:
			wander.enabled = character != current
	var aim := current.get_node_or_null("Aim") as RagdollAim
	if aim != null:
		aim.set_aim(camera.global_position, -camera.global_transform.basis.z)
	var anchor := current.global_position + Vector3(0, 1.3 if current.capsule_height > 1.0 else 0.6, 0)
	camera_rig.global_position = camera_rig.global_position.lerp(anchor, 1.0 - exp(-12.0 * delta))
	_update_help(current)


func set_holding(holding: bool) -> void:
	for character in characters:
		var grab := character.get_node_or_null("Grab") as RagdollGrab
		if grab != null:
			grab.hold = holding and character == player()
			grab.aim_pitch = asin(clampf(-camera.global_transform.basis.z.y, -1.0, 1.0))
	if holding and player().get_node_or_null("Grab") != null:
		var forward := -camera_rig.global_transform.basis.z
		player().face_direction = Vector3(forward.x, 0, forward.z)


func set_aiming(aiming: bool) -> void:
	var aim := player().get_node_or_null("Aim") as RagdollAim
	if aim != null:
		aim.aim_active = aiming
	var forward := -camera_rig.global_transform.basis.z
	player().face_direction = Vector3(forward.x, 0, forward.z) if aiming else Vector3.ZERO


func shoot() -> void:
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * 100.0
	var query := PhysicsRayQueryParameters3D.create(from, to, 3, RagdollIKSupport.exclusions(player().actor))
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or not hit.collider is RagdollBone:
		return
	var victim: Node = hit.collider
	while victim != null and not victim is RagdollCharacter:
		victim = victim.get_parent()
	if victim != null:
		victim.hit(-camera.global_transform.basis.z * shot_impulse, self, hit.collider.slot)


func throw_crate() -> void:
	if crate_scene == null:
		return
	var crate: RigidBody3D = crate_scene.instantiate()
	var chest := player().actor.bone_for_slot("chest")
	var target: Vector3 = chest.global_position if chest != null else player().actor.root_bone().global_position
	crate.position = target + Vector3(randf_range(-1, 1), 0.4, randf_range(-1, 1)).normalized() * 4.0 + Vector3(0, 0.5, 0)
	add_child(crate)
	crate.linear_velocity = (target - crate.position).normalized() * crate_speed
	get_tree().create_timer(8.0).timeout.connect(crate.queue_free)


func _toggle_bodies() -> void:
	var actors := get_tree().get_nodes_in_group(RagdollActor.GROUP)
	if actors.is_empty():
		return
	var visible := not RagdollShapeBuilder.debug_visible(actors[0])
	for actor in actors:
		RagdollShapeBuilder.set_debug_visible(actor, visible)


func _held_name(current: RagdollCharacter) -> String:
	var grab := current.get_node_or_null("Grab") as RagdollGrab
	if grab == null or not grab.is_holding():
		return ""
	return "  holding %s" % grab.held_body().name


func _update_help(current: RagdollCharacter) -> void:
	$Help.text = "%s  %s  %.1f m/s%s\nWASD move  Shift run  Ctrl crouch  Space jump  E grab  RMB aim  LMB shoot  Tab switch  K knock  X kill  T crate  O LOD overlay  B bodies  R reload  Esc mouse" % [current.name, current.state_name(), current.horizontal_speed(), _held_name(current)]
