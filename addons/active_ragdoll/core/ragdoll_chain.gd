class_name RagdollChain
extends Resource

enum ChainType { SPINE, NECK, ARM, LEG, TAIL }

@export var chain_name: String = ""
@export var chain_type: ChainType = ChainType.SPINE
@export var parent_slot: String = ""
@export var slots: PackedStringArray = PackedStringArray()
@export_range(0.0, 180.0, 1.0) var twist_limit_degrees: float = 30.0
@export_range(0.0, 180.0, 1.0) var swing_limit_degrees: float = 60.0
@export_range(0.0, 2.0, 0.05) var stiffness: float = 1.0
@export_range(0.05, 1.5, 0.01) var radius_ratio: float = 0.22
@export var merge_tip_into_parent: bool = false


func contains(slot: String) -> bool:
	return slots.has(slot)


func slot_before(slot: String) -> String:
	var index := slots.find(slot)
	if index <= 0:
		return parent_slot
	return slots[index - 1]


func slot_after(slot: String) -> String:
	var index := slots.find(slot)
	if index < 0 or index >= slots.size() - 1:
		return ""
	return slots[index + 1]


func tip_slot() -> String:
	if slots.is_empty():
		return ""
	return slots[slots.size() - 1]
