@tool
extends EditorPlugin

const DOCK_SCENE := preload("res://addons/active_ragdoll/editor/ragdoll_dock.tscn")

var dock: Control


func _enter_tree() -> void:
	dock = DOCK_SCENE.instantiate()
	dock.editor_interface = get_editor_interface()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	get_editor_interface().get_selection().selection_changed.connect(_on_selection_changed)


func _exit_tree() -> void:
	var selection := get_editor_interface().get_selection()
	if selection.selection_changed.is_connected(_on_selection_changed):
		selection.selection_changed.disconnect(_on_selection_changed)
	if dock != null:
		remove_control_from_docks(dock)
		dock.queue_free()
		dock = null


func _on_selection_changed() -> void:
	var selected := get_editor_interface().get_selection().get_selected_nodes()
	for node in selected:
		if node is Skeleton3D:
			dock.set_selected_skeleton(node)
			return
		if node is RagdollActor and node.get_parent() is Skeleton3D:
			dock.set_selected_skeleton(node.get_parent())
			return
