class_name RagdollProfile
extends Resource

@export var archetype: RagdollArchetype
@export var bone_map: RagdollBoneMap
@export var slot_settings: Dictionary = {}
@export var driver: RagdollDriver
@export var self_collision: bool = false
@export var fit_to_mesh: bool = true
@export_range(0.1, 5000.0, 0.1) var total_mass: float = 70.0
@export_range(0.001, 0.2, 0.001) var min_mass_share: float = 0.01
@export_flags_3d_physics var collision_layer: int = 1
@export_flags_3d_physics var collision_mask: int = 1
@export_range(0.0, 2.0, 0.01) var tip_length_ratio: float = 0.6
@export_range(0.0, 20.0, 0.1) var linear_damp: float = 0.5
@export_range(0.0, 20.0, 0.1) var angular_damp: float = 2.0
@export var continuous_collision: bool = true
@export_range(0.0, 2.0, 0.05) var friction: float = 0.4
@export_range(0.0, 1.0, 0.05) var bounce: float = 0.0
@export var debug_meshes: bool = false
@export_range(0.0, 1.0, 0.001) var settle_energy_threshold: float = 0.02
@export_range(1, 300, 1) var settle_ticks: int = 30

var _default_settings := RagdollSlotSettings.new()


func settings_for(slot: String) -> RagdollSlotSettings:
	var settings: RagdollSlotSettings = slot_settings.get(slot)
	if settings == null:
		return _default_settings
	return settings


func set_settings(slot: String, settings: RagdollSlotSettings) -> void:
	slot_settings[slot] = settings
	emit_changed()


func twist_limit_for(slot: String) -> float:
	var settings := settings_for(slot)
	if settings.twist_limit_degrees >= 0.0:
		return settings.twist_limit_degrees
	var chain := archetype.chain_for_slot(slot) if archetype != null else null
	return chain.twist_limit_degrees if chain != null else 30.0


func swing_limit_for(slot: String) -> float:
	var settings := settings_for(slot)
	if settings.swing_limit_degrees >= 0.0:
		return settings.swing_limit_degrees
	var chain := archetype.chain_for_slot(slot) if archetype != null else null
	return chain.swing_limit_degrees if chain != null else 60.0


func radius_ratio_for(slot: String) -> float:
	if archetype == null:
		return 0.22
	if slot == archetype.root_slot:
		return archetype.root_radius_ratio
	var chain := archetype.chain_for_slot(slot)
	return chain.radius_ratio if chain != null else 0.22


func stiffness_for(slot: String) -> float:
	var chain := archetype.chain_for_slot(slot) if archetype != null else null
	var chain_stiffness := chain.stiffness if chain != null else 1.0
	return chain_stiffness * settings_for(slot).stiffness_multiplier


func validate(skeleton: Skeleton3D) -> PackedStringArray:
	var problems := PackedStringArray()
	if archetype == null:
		problems.append("profile has no archetype")
		return problems
	problems.append_array(archetype.validate())
	if bone_map == null:
		problems.append("profile has no bone map")
		return problems
	for slot in bone_map.missing_slots():
		problems.append("slot %s has no bone" % slot)
	if skeleton != null:
		for bone_name in bone_map.unresolved_bones(skeleton):
			problems.append("bone %s does not exist in %s" % [bone_name, skeleton.name])
		var scale := skeleton.global_transform.basis.get_scale()
		if not is_equal_approx(scale.x, scale.y) or not is_equal_approx(scale.x, scale.z):
			problems.append("skeleton %s has non-uniform scale; bodies cannot follow it" % skeleton.name)
	return problems
