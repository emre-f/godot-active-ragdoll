class_name RagdollBoneMatcher
extends RefCounted

const SYNONYMS := {
	"pelvis": ["pelvis", "hips", "hip"],
	"spine": ["spine", "abdomen", "lowerback", "waist"],
	"chest": ["chest", "torso", "upperchest", "ribcage", "spine"],
	"neck": ["neck"],
	"head": ["head"],
	"upper_arm": ["upperarm", "uparm", "arm", "humerus"],
	"forearm": ["forearm", "lowerarm", "elbow", "radius", "ulna"],
	"hand": ["hand", "wrist", "palm"],
	"thigh": ["thigh", "upperleg", "upleg", "femur", "hip"],
	"shin": ["shin", "lowerleg", "calf", "knee", "tibia", "leg"],
	"foot": ["foot", "ankle"],
	"upper_leg": ["upperleg", "upleg", "thigh", "shoulder", "humerus", "leg"],
	"lower_leg": ["lowerleg", "shin", "calf", "forearm", "knee"],
	"cephalothorax": ["cephalothorax", "thorax", "sternum", "carapace", "body", "root", "hips"],
	"abdomen": ["abdomen", "belly", "butt"],
	"tail": ["tail"],
	"coxa": ["coxa", "hip", "upper", "root"],
	"femur": ["femur", "mid", "middle", "knee"],
	"tibia": ["tibia", "tip", "lower", "end"],
}

const SIDE_TOKENS := {"l": "l", "left": "l", "lft": "l", "r": "r", "right": "r", "rgt": "r"}
const POSITION_TOKENS := {"front": "front", "fore": "front", "f": "front", "hind": "hind", "rear": "hind", "back": "hind", "h": "hind", "b": "hind"}
const SLOT_SUFFIXES := {"_fl": ["l", "front"], "_fr": ["r", "front"], "_hl": ["l", "hind"], "_hr": ["r", "hind"]}
const SEGMENT_WORDS := {"coxa": 1, "femur": 2, "tibia": 3}
const NUMBER_PREFERENCE := {"spine": -1, "chest": 1}


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
	var slot_numbers: Array = slot_parts.numbers
	var bone_numbers: Array = bone_parts.numbers
	if bone_numbers.slice(0, slot_numbers.size()) != slot_numbers:
		return 0
	var slot_core: String = slot_parts.core
	var bone_core: String = bone_parts.core
	var segment := _segment_of(slot_core)
	if segment > 0 and bone_numbers.size() > slot_numbers.size():
		return 90 if bone_numbers[slot_numbers.size()] == segment else 0
	var number_bonus := 0
	if slot_numbers.is_empty() and not bone_numbers.is_empty():
		number_bonus = NUMBER_PREFERENCE.get(slot_core, -1) * bone_numbers[0]
	if bone_core == slot_core:
		return 100 + number_bonus
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
	return best + number_bonus if best > 0 else 0


static func _segment_of(slot_core: String) -> int:
	for word in SEGMENT_WORDS:
		if slot_core.contains(word):
			return SEGMENT_WORDS[word]
	return 0


static func _normalize(bone_name: String) -> String:
	var core := bone_name.to_lower()
	if core.contains(":"):
		core = core.get_slice(":", core.get_slice_count(":") - 1)
	core = core.replace("mixamorig", "").replace(" ", "_").replace("-", "_").replace(".", "_")
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
	var core := ""
	var numbers: Array = []
	for raw_token in lowered.split("_", false):
		var token: String = raw_token
		for prefix in ["left", "right"]:
			if token.begins_with(prefix) and token.length() > prefix.length():
				side = SIDE_TOKENS[prefix]
				token = token.substr(prefix.length())
		if SIDE_TOKENS.has(token):
			side = SIDE_TOKENS[token]
		elif POSITION_TOKENS.has(token):
			position = POSITION_TOKENS[token]
		else:
			core += _split_digits(token, numbers)
	return {"side": side, "position": position, "numbers": numbers, "core": core}


static func _split_digits(token: String, numbers: Array) -> String:
	var letters := ""
	var digits := ""
	for i in token.length():
		if token[i].is_valid_int():
			digits += token[i]
		else:
			if not digits.is_empty():
				numbers.append(int(digits))
				digits = ""
			letters += token[i]
	if not digits.is_empty():
		numbers.append(int(digits))
	return letters
