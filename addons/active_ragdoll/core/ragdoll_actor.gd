class_name RagdollActor
extends SkeletonModifier3D

signal knocked(impulse: Vector3, source: Node)
signal settled

@export var profile: RagdollProfile
@export var build_at_runtime: bool = false
@export var start_limp: bool = false

var bones: Array[RagdollBone] = []
var targets: Array[Transform3D] = []
var target_velocities: PackedVector3Array = PackedVector3Array()
var target_angular_velocities: PackedVector3Array = PackedVector3Array()
var _previous_targets: Array[Transform3D] = []
var drive_enabled: bool = true
var is_limp: bool = false
var strength_scale: float = 1.0
var root_snap_enabled: bool = true

var _free_bones: PackedInt32Array = PackedInt32Array()
var _kinematic_bones: PackedByteArray = PackedByteArray()
var _write_order: PackedInt32Array = PackedInt32Array()
var _settled_ticks: int = 0
var _has_settled: bool = false
var _total_mass: float = 0.0
var _reset_target_velocity: bool = true


func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		push_warning("RagdollActor %s must be a child of a Skeleton3D" % name)
		return
	if profile == null:
		push_warning("RagdollActor %s has no profile" % name)
		return
	if build_at_runtime or not _has_generated_bones():
		RagdollGenerator.build(self, skeleton, profile)
	refresh()
	if start_limp:
		go_limp()


func detach_bones() -> void:
	bones.clear()
	targets.clear()


func refresh() -> void:
	_collect_bones()
	_apply_collision_rules()
	if profile.driver != null:
		profile.driver.on_attached(self)
	_set_sleep_allowed(is_limp or profile.driver == null)
	snap_to_skeleton()


func _has_generated_bones() -> bool:
	for child in get_children():
		if child is RagdollBone:
			return true
	return false


func _collect_bones() -> void:
	bones.clear()
	_total_mass = 0.0
	var skeleton := get_skeleton()
	for child in get_children():
		if child is RagdollBone:
			bones.append(child)
			_total_mass += child.mass
	targets.resize(bones.size())
	target_velocities.resize(bones.size())
	target_angular_velocities.resize(bones.size())
	_previous_targets.resize(bones.size())
	for i in bones.size():
		targets[i] = bones[i].global_transform
		target_velocities[i] = Vector3.ZERO
		target_angular_velocities[i] = Vector3.ZERO
	_free_bones = RagdollFreeBones.collect(skeleton, bones)
	_kinematic_bones = RagdollKinematicBones.collect(bones, profile)
	_write_order = RagdollFreeBones.hierarchy_order(skeleton, bones)


func _apply_collision_rules() -> void:
	if profile.self_collision:
		return
	for i in bones.size():
		for j in range(i + 1, bones.size()):
			bones[i].add_collision_exception_with(bones[j])


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or bones.is_empty():
		return
	var to_skeleton := skeleton.global_transform.affine_inverse()
	var capture_targets := not is_limp
	for i in bones.size():
		var bone := bones[i]
		if capture_targets:
			targets[i] = skeleton.global_transform * skeleton.get_bone_global_pose(bone.bone_index)
	RagdollFreeBones.follow_root(skeleton, to_skeleton, bones[0], _free_bones)
	for i in _write_order:
		var bone := bones[i]
		var pose := to_skeleton * (targets[i] if bone.freeze else bone.global_transform)
		pose.basis = pose.basis.orthonormalized()
		skeleton.set_bone_global_pose(bone.bone_index, pose)


func _physics_process(delta: float) -> void:
	if bones.is_empty():
		return
	var driven := drive_enabled and not is_limp and profile.driver != null
	RagdollKinematicBones.update(self, _kinematic_bones, driven and strength_scale >= 1.0)
	if driven:
		_reset_target_velocity = RagdollTargetVelocity.measure(self, _previous_targets, delta, _reset_target_velocity)
		profile.driver.drive(self, delta)
	if is_limp:
		_update_settle()


func _update_settle() -> void:
	if _has_settled:
		return
	if kinetic_energy() < profile.settle_energy_threshold * _total_mass:
		_settled_ticks += 1
	else:
		_settled_ticks = 0
	if _settled_ticks >= profile.settle_ticks:
		_has_settled = true
		settled.emit()


func snap_to_skeleton() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	for i in bones.size():
		var bone := bones[i]
		var pose := skeleton.global_transform * skeleton.get_bone_global_pose(bone.bone_index)
		pose.basis = pose.basis.orthonormalized()
		bone.global_transform = pose
		bone.linear_velocity = Vector3.ZERO
		bone.angular_velocity = Vector3.ZERO
		targets[i] = pose
	_reset_target_velocity = true


func knock(impulse: Vector3, source: Node = null) -> void:
	go_limp()
	var root := root_bone()
	if root != null:
		root.apply_central_impulse(impulse)
	knocked.emit(impulse, source)


func go_limp() -> void:
	is_limp = true
	drive_enabled = false
	RagdollKinematicBones.update(self, _kinematic_bones, false)
	_settled_ticks = 0
	_has_settled = false
	_set_sleep_allowed(true)
	for bone in bones:
		bone.sleeping = false


func resume_drive() -> void:
	is_limp = false
	_reset_target_velocity = true
	drive_enabled = true
	_has_settled = false
	_set_sleep_allowed(profile.driver == null)


func _set_sleep_allowed(allowed: bool) -> void:
	for bone in bones:
		bone.can_sleep = allowed
		if not allowed:
			bone.sleeping = false


func set_strength_multiplier(multiplier: float, chain_name: String = "") -> void:
	for bone in bones:
		var chain := profile.archetype.chain_for_slot(bone.slot)
		if chain_name.is_empty() or (chain != null and chain.chain_name == chain_name):
			bone.strength = profile.stiffness_for(bone.slot) * multiplier


func shift_bones(offset: Vector3) -> void:
	for i in bones.size():
		bones[i].global_position += offset


func set_drive_enabled(enabled: bool) -> void:
	drive_enabled = enabled


func root_bone() -> RagdollBone:
	if bones.is_empty():
		return null
	return bones[0]


func bone_for_slot(slot: String) -> RagdollBone:
	for bone in bones:
		if bone.slot == slot:
			return bone
	return null


func kinetic_energy() -> float:
	var energy := 0.0
	for bone in bones:
		energy += bone.kinetic_energy()
	return energy


func total_mass() -> float:
	return _total_mass


func is_settled() -> bool:
	return _has_settled


func max_joint_separation() -> float:
	var worst := 0.0
	for bone in bones:
		worst = maxf(worst, bone.joint_separation())
	return worst


func lowest_point() -> float:
	var lowest := INF
	for bone in bones:
		lowest = minf(lowest, bone.global_position.y)
	return lowest
