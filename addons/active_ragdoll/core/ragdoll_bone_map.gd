class_name RagdollBoneMap
extends Resource

@export var archetype: RagdollArchetype
@export var slot_to_bone: Dictionary = {}


func bone_for(slot: String) -> String:
	return slot_to_bone.get(slot, "")


func set_bone(slot: String, bone_name: String) -> void:
	slot_to_bone[slot] = bone_name
	emit_changed()


func missing_slots() -> PackedStringArray:
	var missing := PackedStringArray()
	if archetype == null:
		return missing
	for slot in archetype.all_slots():
		if bone_for(slot).is_empty():
			missing.append(slot)
	return missing


func is_complete() -> bool:
	return archetype != null and missing_slots().is_empty()


func unresolved_bones(skeleton: Skeleton3D) -> PackedStringArray:
	var unresolved := PackedStringArray()
	for slot in slot_to_bone:
		var bone_name: String = slot_to_bone[slot]
		if not bone_name.is_empty() and skeleton.find_bone(bone_name) < 0:
			unresolved.append(bone_name)
	return unresolved
