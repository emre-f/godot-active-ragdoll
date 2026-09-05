class_name RagdollLODOverlay
extends CanvasLayer

@export var manager_path: NodePath

@onready var label: Label = $Label

var manager: RagdollLODManager


func _ready() -> void:
	manager = get_node_or_null(manager_path) as RagdollLODManager
	if manager == null:
		var found := get_tree().current_scene.find_children("*", "RagdollLODManager", true, false) if get_tree().current_scene != null else []
		manager = found[0] if not found.is_empty() else null
	if manager == null:
		label.text = "RagdollLODOverlay: no RagdollLODManager found"
		return
	manager.tiers_updated.connect(_refresh)
	_refresh()


func _refresh() -> void:
	label.text = manager.stats.summary()
