class_name RagdollActor
extends SkeletonModifier3D

signal knocked(impulse: Vector3, source: Node)
signal settled
signal lod_tier_changed(old_tier: int, new_tier: int)
signal baked
signal bodies_built
signal bodies_released

const GROUP := "ragdoll_actors"

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
var lod_tier: RagdollLOD.Tier = RagdollLOD.Tier.T0_FULL
var lod_pinned: bool = false
var drive_interval: int = 1
var kinematic_interval: int = 1
var bake_when_settled: bool = false
var is_baked: bool = false
var is_released: bool = false

var _free_bones: PackedInt32Array = PackedInt32Array()
var _kinematic_bones: PackedByteArray = PackedByteArray()
var _all_kinematic: PackedByteArray = PackedByteArray()
var _write_order: PackedInt32Array = PackedInt32Array()
var _settle := RagdollSettleTracker.new()
var _animation_lod := RagdollAnimationLOD.new()
var _body_cache := RagdollBodyCache.new()
var _total_mass: float = 0.0
var _reset_target_velocity: bool = true
var _drive_tick: int = 0
var _bake_requested: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	var skeleton := get_skeleton()
	if skeleton == null:
		push_warning("RagdollActor %s must be a child of a Skeleton3D" % name)
		return
	if profile == null:
		push_warning("RagdollActor %s has no profile" % name)
		return
	if build_at_runtime or not RagdollActorSetup.has_generated_bones(self):
		RagdollGenerator.build(self, skeleton, profile)
	refresh()
	if start_limp:
		go_limp()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_body_cache.free_all()


func detach_bones() -> void:
	bones.clear()
	targets.clear()


func refresh() -> void:
	RagdollActorSetup.collect_bones(self)
	RagdollActorSetup.apply_collision_rules(self)
	_attach_bones()
	RagdollActorSetup.rebind_joints(self)


func _attach_bones() -> void:
	if profile.driver != null:
		profile.driver.on_attached(self)
	_set_sleep_allowed(is_limp or profile.driver == null)
	snap_to_skeleton()


func release_bodies() -> void:
	if is_released or bones.is_empty():
		return
	_body_cache.release(self)
	is_released = true
	bodies_released.emit()


func build_bodies() -> void:
	if not is_released:
		return
	is_released = false
	_body_cache.restore(self)
	_attach_bones()
	var driven := drive_enabled and not is_limp and profile.driver != null
	RagdollKinematicBones.update(self, _kinematic_bones, driven and strength_scale >= 1.0)
	_drive_tick = 0
	bodies_built.emit()


func ensure_bodies() -> void:
	if lod_tier >= RagdollLOD.Tier.T2_KINEMATIC:
		RagdollLOD.apply(self, RagdollLOD.Tier.T1_REDUCED)


func has_ragdoll() -> bool:
	return not bones.is_empty() or is_released


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if not bones.is_empty() and lod_tier != RagdollLOD.Tier.T3_DORMANT:
		RagdollActorUpdate.write_pose(self, skeleton)
	if _bake_requested:
		_bake_requested = false
		RagdollBaker.bake(self, skeleton)


func _physics_process(delta: float) -> void:
	if profile == null or is_baked or lod_tier == RagdollLOD.Tier.T3_DORMANT:
		return
	RagdollActorUpdate.physics(self, delta)


func snap_to_skeleton() -> void:
	RagdollActorUpdate.snap_to_skeleton(self)


func knock(impulse: Vector3, source: Node = null) -> void:
	go_limp()
	var root := root_bone()
	if root != null:
		root.apply_central_impulse(impulse)
	knocked.emit(impulse, source)


func go_limp() -> void:
	if is_baked:
		return
	ensure_bodies()
	is_limp = true
	drive_enabled = false
	RagdollKinematicBones.update(self, _all_kinematic, false)
	_settle.reset()
	_set_sleep_allowed(true)
	for bone in bones:
		bone.sleeping = false


func resume_drive() -> void:
	is_limp = false
	_reset_target_velocity = true
	drive_enabled = true
	_settle.has_settled = false
	_set_sleep_allowed(profile.driver == null)


func apply_animation_lod(tier: RagdollLOD.Tier) -> void:
	_animation_lod.apply(self, tier)


func bake() -> void:
	if is_baked or not has_ragdoll():
		return
	_bake_requested = true


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


func all_kinematic_flags() -> PackedByteArray:
	return _all_kinematic


func root_bone() -> RagdollBone:
	ensure_bodies()
	if bones.is_empty():
		return null
	return bones[0]


func bone_for_slot(slot: String) -> RagdollBone:
	ensure_bodies()
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
	return _settle.has_settled


func limp_time() -> float:
	return _settle.limp_time


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
