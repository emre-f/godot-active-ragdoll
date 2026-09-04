class_name RagdollActor
extends SkeletonModifier3D

signal knocked(impulse: Vector3, source: Node)
signal settled

@export var profile: RagdollProfile
@export var build_at_runtime: bool = false
@export var start_limp: bool = false

var bones: Array[RagdollBone] = []
var targets: Array[Transform3D] = []
var drive_enabled: bool = true
var is_limp: bool = false

var _settled_ticks: int = 0
var _has_settled: bool = false
var _total_mass: float = 0.0


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
	snap_to_skeleton()


func _has_generated_bones() -> bool:
	for child in get_children():
		if child is RagdollBone:
			return true
	return false


func _collect_bones() -> void:
	bones.clear()
	_total_mass = 0.0
	for child in get_children():
		if child is RagdollBone:
			bones.append(child)
			_total_mass += child.mass
	targets.resize(bones.size())
	for i in bones.size():
		targets[i] = bones[i].global_transform


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
		skeleton.set_bone_global_pose(bone.bone_index, to_skeleton * bone.global_transform)


func _physics_process(delta: float) -> void:
	if bones.is_empty():
		return
	if drive_enabled and not is_limp and profile.driver != null:
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


func knock(impulse: Vector3, source: Node = null) -> void:
	go_limp()
	var root := root_bone()
	if root != null:
		root.apply_central_impulse(impulse)
	knocked.emit(impulse, source)


func go_limp() -> void:
	is_limp = true
	drive_enabled = false
	_settled_ticks = 0
	_has_settled = false
	for bone in bones:
		bone.sleeping = false


func resume_drive() -> void:
	is_limp = false
	drive_enabled = true
	_has_settled = false


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
