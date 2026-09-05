class_name RagdollSettleTracker
extends RefCounted

var ticks: int = 0
var has_settled: bool = false
var limp_time: float = 0.0


func reset() -> void:
	ticks = 0
	has_settled = false
	limp_time = 0.0


func update(actor: RagdollActor, delta: float) -> bool:
	limp_time += delta
	if has_settled:
		return false
	if actor.kinetic_energy() < actor.profile.settle_energy_threshold * actor.total_mass():
		ticks += 1
	else:
		ticks = 0
	if ticks >= actor.profile.settle_ticks:
		has_settled = true
		return true
	return false
