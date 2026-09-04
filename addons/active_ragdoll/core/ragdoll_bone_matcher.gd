class_name RagdollBoneMatcher
extends RefCounted

const SYNONYMS := {
	"pelvis": ["pelvis", "hips", "hip"],
	"spine": ["spine", "abdomen", "lowerback", "waist"],
	"chest": ["chest", "torso", "upperchest", "ribcage"],
	"neck": ["neck"],
	"head": ["head"],
	"upper_arm": ["upperarm", "uparm", "arm", "humerus", "shoulder"],
	"forearm": ["forearm", "lowerarm", "elbow", "radius", "ulna"],
	"hand": ["hand", "wrist", "palm"],
	"thigh": ["thigh", "upperleg", "upleg", "femur", "hip"],
	"shin": ["shin", "lowerleg", "calf", "knee", "tibia", "leg"],
	"foot": ["foot", "ankle"],
	"upper_leg": ["upperleg", "upleg", "thigh", "shoulder", "humerus", "leg"],
	"lower_leg": ["lowerleg", "shin", "calf", "forearm", "knee"],
	"cephalothorax": ["cephalothorax", "thorax", "body", "root", "hips"],
	"abdomen": ["abdomen", "belly", "butt"],
	"tail": ["tail"],
	"coxa": ["coxa", "hip", "upper", "root"],
	"femur": ["femur", "mid", "middle", "knee"],
	"tibia": ["tibia", "tip", "lower", "end"],
}

const SIDE_TOKENS := {"l": "l", "left": "l", "lft": "l", "r": "r", "right": "r", "rgt": "r"}
const POSITION_TOKENS := {"front": "front", "fore": "front", "f": "front", "hind": "hind", "rear": "hind", "back": "hind", "h": "hind", "b": "hind"}
const SLOT_SUFFIXES := {"_fl": ["l", "front"], "_fr": ["r", "front"], "_hl": ["l", "hind"], "_hr": ["r", "hind"]}


static func suggest(archetype: RagdollArchetype, skeleton: Skeleton3D) -> Dictionary:
	var candidates: Array = []
	var slots := archetype.all_slots()
	for slot in slots:
		for bone_index in skeleton.get_bone_count():
			var bone_name := skeleton.get_bone_name(bone_index)
			var score := _score(slot, bone_name)
			if score > 0:
				candidates.append([score, slot, bone_name])
	candidates.sort_custom(func(a, b): return a[0] > b[0])
	var result := {}
	var used := {}
	for candidate in candidates:
		if result.has(candidate[1]) or used.has(candidate[2]):
			continue
		result[candidate[1]] = candidate[2]
		used[candidate[2]] = true
	for slot in slots:
		if not result.has(slot):
			result[slot] = ""
	return result


static func _score(slot: String, bone_name: String) -> int:
	var slot_parts := _describe(slot)
	var bone_parts := _describe(_normalize(bone_name))
	if slot_parts.side != bone_parts.side:
		return 0
	if slot_parts.position != "" and slot_parts.position != bone_parts.position:
		return 0
	if slot_parts.index != "" and slot_parts.index != bone_parts.index:
		return 0
	var slot_core: String = slot_parts.core
	var bone_core: String = bone_parts.core
	if bone_core == slot_core:
		return 100
	var best := 0
	for key in SYNONYMS:
		if not slot_core.contains(key.replace("_", "")):
			continue
		for synonym in SYNONYMS[key]:
			if bone_core == synonym:
				best = maxi(best, 80 + synonym.length())
			elif bone_core.contains(synonym):
				best = maxi(best, synonym.length())
	if bone_core.begins_with(slot_core) or bone_core.ends_with(slot_core):
		best = maxi(best, 40 + slot_core.length())
	elif bone_core.contains(slot_core):
		best = maxi(best, 20 + slot_core.length())
	return best


static func _normalize(bone_name: String) -> String:
	var core := bone_name.to_lower()
	if core.contains(":"):
		core = core.get_slice(":", core.get_slice_count(":") - 1)
	core = core.replace("mixamorig", "").replace(" ", "_").replace("-", "_").replace(".", "_")
	for prefix in ["left", "right"]:
		if core.begins_with(prefix) and core.length() > prefix.length():
			core = prefix + "_" + core.substr(prefix.length())
	return core


static func _describe(text: String) -> Dictionary:
	var lowered := text.to_lower()
	var side := ""
	var position := ""
	for suffix in SLOT_SUFFIXES:
		if lowered.ends_with(suffix):
			side = SLOT_SUFFIXES[suffix][0]
			position = SLOT_SUFFIXES[suffix][1]
			lowered = lowered.substr(0, lowered.length() - suffix.length())
	var core_tokens := PackedStringArray()
	var index := ""
	for token in lowered.split("_", false):
		if SIDE_TOKENS.has(token):
			side = SIDE_TOKENS[token]
		elif POSITION_TOKENS.has(token):
			position = POSITION_TOKENS[token]
		elif token.is_valid_int():
			index = token
		else:
			core_tokens.append(token)
	var raw_core := "".join(core_tokens)
	if index == "":
		index = _index_of(raw_core)
	var core := ""
	for i in raw_core.length():
		if not raw_core[i].is_valid_int():
			core += raw_core[i]
	return {"side": side, "position": position, "index": index, "core": core}


static func _index_of(text: String) -> String:
	for i in text.length():
		if text[i].is_valid_int():
			return text[i]
	return ""
