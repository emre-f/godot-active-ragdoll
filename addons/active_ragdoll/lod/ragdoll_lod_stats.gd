class_name RagdollLODStats
extends RefCounted

var tier_counts: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var baked_count: int = 0
var released_count: int = 0
var pending_builds: int = 0
var full_cost: float = 0.0
var reduced_cost: float = 0.0
var adaptive_full_budget: float = 0.0
var physics_ms: float = 0.0
var distances: Dictionary = {}
var per_archetype: Dictionary = {}


func reset() -> void:
	tier_counts = PackedInt32Array([0, 0, 0, 0])
	baked_count = 0
	released_count = 0
	pending_builds = 0
	full_cost = 0.0
	reduced_cost = 0.0
	distances.clear()
	per_archetype.clear()


func count(actor: RagdollActor, tier: RagdollLOD.Tier, cost: float) -> void:
	tier_counts[tier] += 1
	if actor.is_released:
		released_count += 1
	if tier == RagdollLOD.Tier.T0_FULL:
		full_cost += cost
	elif tier == RagdollLOD.Tier.T1_REDUCED:
		reduced_cost += cost
	_archetype_counts(actor)[tier] += 1


func count_baked(actor: RagdollActor) -> void:
	baked_count += 1
	_archetype_counts(actor)[4] += 1


func _archetype_counts(actor: RagdollActor) -> PackedInt32Array:
	var archetype_name := actor.profile.archetype.archetype_name if actor.profile.archetype != null else "none"
	if not per_archetype.has(archetype_name):
		per_archetype[archetype_name] = PackedInt32Array([0, 0, 0, 0, 0])
	return per_archetype[archetype_name]


func total() -> int:
	return tier_counts[0] + tier_counts[1] + tier_counts[2] + tier_counts[3] + baked_count


func summary() -> String:
	var lines := PackedStringArray()
	lines.append("ragdolls %d   physics %.2f ms   full budget %.0f" % [total(), physics_ms, adaptive_full_budget])
	lines.append("T0 %d   T1 %d   T2 %d   T3 %d   baked %d" % [tier_counts[0], tier_counts[1], tier_counts[2], tier_counts[3], baked_count])
	lines.append("no bodies %d   building %d" % [released_count, pending_builds])
	for archetype_name in per_archetype:
		var counts: PackedInt32Array = per_archetype[archetype_name]
		lines.append("%-10s T0 %d  T1 %d  T2 %d  T3 %d  baked %d" % [archetype_name, counts[0], counts[1], counts[2], counts[3], counts[4]])
	return "\n".join(lines)
