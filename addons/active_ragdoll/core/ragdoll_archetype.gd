class_name RagdollArchetype
extends Resource

@export var archetype_name: String = ""
@export var root_slot: String = "pelvis"
@export_range(0.05, 1.5, 0.01) var root_radius_ratio: float = 0.6
@export var root_kinematic_when_driven: bool = false
@export var chains: Array[RagdollChain] = []
@export var symmetry: Dictionary = {}
@export var ground_contact_slots: PackedStringArray = PackedStringArray()


func all_slots() -> PackedStringArray:
	var result := PackedStringArray([root_slot])
	for chain in chains:
		for slot in chain.slots:
			if not result.has(slot):
				result.append(slot)
	return result


func chain_for_slot(slot: String) -> RagdollChain:
	for chain in chains:
		if chain.contains(slot):
			return chain
	return null


func parent_slot(slot: String) -> String:
	if slot == root_slot:
		return ""
	var chain := chain_for_slot(slot)
	if chain == null:
		return ""
	return chain.slot_before(slot)


func child_slot_in_chain(slot: String) -> String:
	var chain := chain_for_slot(slot)
	if chain == null:
		return ""
	return chain.slot_after(slot)


func mirrored_slot(slot: String) -> String:
	if symmetry.has(slot):
		return symmetry[slot]
	for key in symmetry:
		if symmetry[key] == slot:
			return key
	return ""


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if root_slot.is_empty():
		problems.append("root_slot is empty")
	var known := PackedStringArray([root_slot])
	for chain in chains:
		if chain.slots.is_empty():
			problems.append("chain %s has no slots" % chain.chain_name)
		if not known.has(chain.parent_slot) and not all_slots().has(chain.parent_slot):
			problems.append("chain %s attaches to unknown slot %s" % [chain.chain_name, chain.parent_slot])
		for slot in chain.slots:
			if known.has(slot):
				problems.append("slot %s is defined twice" % slot)
			known.append(slot)
	return problems
