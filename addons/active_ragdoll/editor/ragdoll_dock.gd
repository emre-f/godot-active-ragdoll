@tool
extends ScrollContainer

const ARCHETYPE_DIR := "res://addons/active_ragdoll/archetypes/"

var editor_interface
var skeleton: Skeleton3D
var profile: RagdollProfile
var archetype_paths: PackedStringArray = PackedStringArray()

@onready var skeleton_label: Label = %SkeletonLabel if has_node("%SkeletonLabel") else $Content/SkeletonLabel
@onready var archetype_options: OptionButton = $Content/ArchetypeRow/ArchetypeOptions
@onready var profile_path: LineEdit = $Content/ProfileRow/ProfilePath
@onready var auto_map_button: Button = $Content/AutoMapButton
@onready var slot_list: VBoxContainer = $Content/SlotList
@onready var debug_meshes: CheckBox = $Content/DebugMeshes
@onready var generate_button: Button = $Content/GenerateButton
@onready var status: Label = $Content/Status


func _ready() -> void:
	_fill_archetypes()
	archetype_options.item_selected.connect(_on_archetype_selected)
	auto_map_button.pressed.connect(_on_auto_map)
	generate_button.pressed.connect(_on_generate)
	_refresh()


func set_selected_skeleton(selected: Skeleton3D) -> void:
	skeleton = selected
	profile = _find_existing_profile()
	if profile != null:
		_select_archetype_of(profile)
	_refresh()


func _fill_archetypes() -> void:
	archetype_options.clear()
	archetype_paths.clear()
	var dir := DirAccess.open(ARCHETYPE_DIR)
	if dir == null:
		return
	for file_name in dir.get_files():
		if file_name.ends_with(".tres"):
			archetype_paths.append(ARCHETYPE_DIR + file_name)
			archetype_options.add_item(file_name.get_basename())


func _find_existing_profile() -> RagdollProfile:
	if skeleton == null:
		return null
	for child in skeleton.get_children():
		if child is RagdollActor and child.profile != null:
			profile_path.text = child.profile.resource_path
			return child.profile
	return null


func _select_archetype_of(existing: RagdollProfile) -> void:
	if existing.archetype == null:
		return
	var index := archetype_paths.find(existing.archetype.resource_path)
	if index >= 0:
		archetype_options.select(index)


func _selected_archetype() -> RagdollArchetype:
	var index := archetype_options.selected
	if index < 0 or index >= archetype_paths.size():
		return null
	return load(archetype_paths[index])


func _ensure_profile() -> RagdollProfile:
	if profile == null:
		profile = RagdollProfile.new()
	var archetype := _selected_archetype()
	if profile.archetype != archetype:
		profile.archetype = archetype
		profile.bone_map = null
	if profile.bone_map == null:
		profile.bone_map = RagdollBoneMap.new()
		profile.bone_map.archetype = archetype
	return profile


func _refresh() -> void:
	if skeleton == null:
		skeleton_label.text = "Select a Skeleton3D in the scene tree."
	else:
		skeleton_label.text = "Skeleton: %s (%d bones)" % [skeleton.name, skeleton.get_bone_count()]
	var ready := skeleton != null and _selected_archetype() != null
	auto_map_button.disabled = not ready
	generate_button.disabled = not ready
	_rebuild_slot_list()


func _rebuild_slot_list() -> void:
	for child in slot_list.get_children():
		slot_list.remove_child(child)
		child.queue_free()
	if skeleton == null or profile == null or profile.bone_map == null:
		return
	var bone_names := PackedStringArray()
	for bone_index in skeleton.get_bone_count():
		bone_names.append(skeleton.get_bone_name(bone_index))
	for slot in profile.archetype.all_slots():
		slot_list.add_child(_make_slot_row(slot, bone_names))


func _make_slot_row(slot: String, bone_names: PackedStringArray) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = slot
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.add_item("(none)")
	var current := profile.bone_map.bone_for(slot)
	for bone_name in bone_names:
		picker.add_item(bone_name)
		if bone_name == current:
			picker.select(picker.item_count - 1)
	picker.item_selected.connect(func(index: int): profile.bone_map.set_bone(slot, "" if index == 0 else bone_names[index - 1]))
	row.add_child(picker)
	return row


func _on_archetype_selected(_index: int) -> void:
	if skeleton != null:
		_ensure_profile()
	_refresh()


func _on_auto_map() -> void:
	_ensure_profile()
	profile.bone_map.slot_to_bone = RagdollBoneMatcher.suggest(profile.archetype, skeleton)
	var missing := profile.bone_map.missing_slots()
	status.text = "All slots mapped." if missing.is_empty() else "Unmapped: " + ", ".join(missing)
	_refresh()


func _on_generate() -> void:
	_ensure_profile()
	var missing := profile.bone_map.missing_slots()
	if not missing.is_empty():
		status.text = "Map every slot first. Unmapped: " + ", ".join(missing)
		return
	profile.debug_meshes = debug_meshes.button_pressed
	if not _save_profile():
		return
	var scene_root: Node = editor_interface.get_edited_scene_root()
	_ensure_editable_instance(scene_root)
	var actor := _find_or_create_actor(scene_root)
	var bones := RagdollGenerator.build(actor, skeleton, profile, scene_root)
	status.text = "Generated %d bodies under %s. Save the scene to keep them." % [bones.size(), actor.name]
	editor_interface.mark_scene_as_unsaved()


func _save_profile() -> bool:
	var path := profile_path.text.strip_edges()
	if path.is_empty():
		path = "res://%s_ragdoll_profile.tres" % skeleton.name.to_snake_case()
		profile_path.text = path
	if profile.bone_map.resource_path.is_empty():
		profile.bone_map.resource_path = ""
	var error := ResourceSaver.save(profile, path)
	if error != OK:
		status.text = "Could not save profile to %s (error %d)" % [path, error]
		return false
	profile = load(path)
	editor_interface.get_resource_filesystem().scan()
	return true


func _ensure_editable_instance(scene_root: Node) -> void:
	var node: Node = skeleton
	while node != null and node != scene_root:
		if node.owner == scene_root and not node.scene_file_path.is_empty():
			scene_root.set_editable_instance(node, true)
			return
		node = node.get_parent()


func _find_or_create_actor(scene_root: Node) -> RagdollActor:
	for child in skeleton.get_children():
		if child is RagdollActor:
			child.profile = profile
			return child
	var actor := RagdollActor.new()
	actor.name = "RagdollActor"
	actor.profile = profile
	skeleton.add_child(actor)
	actor.owner = scene_root
	return actor
