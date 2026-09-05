class_name RagdollCrouch
extends Node

@export_range(0.0, 1.5, 0.01) var drop: float = 0.45
@export_range(0.1, 1.0, 0.05) var speed_scale: float = 0.5
@export_range(0.01, 1.0, 0.01) var blend_time: float = 0.15

var crouching: bool = false
var amount: float = 0.0
var character: RagdollCharacter
var rig: Node3D
var capsule: CollisionShape3D
var _rig_rest_y: float = 0.0


func _ready() -> void:
	character = get_parent() as RagdollCharacter
	if character == null:
		push_warning("RagdollCrouch %s must be a child of a RagdollCharacter" % name)
		return
	if character.is_node_ready():
		_setup()
	else:
		character.ready.connect(_setup, CONNECT_ONE_SHOT)


func _setup() -> void:
	if character.actor == null:
		return
	var node: Node = character.actor.get_skeleton()
	while node != null and node.get_parent() != character:
		node = node.get_parent()
	rig = node as Node3D
	if rig != null:
		_rig_rest_y = rig.position.y
	capsule = character.get_node_or_null("Capsule") as CollisionShape3D


func _physics_process(delta: float) -> void:
	if rig == null:
		return
	var goal := 1.0 if crouching and character.is_controllable() else 0.0
	var previous := amount
	amount = move_toward(amount, goal, delta / blend_time)
	if amount == previous:
		return
	rig.position.y = _rig_rest_y - drop * amount
	character.crouch_speed_scale = lerpf(1.0, speed_scale, amount)
	if capsule != null and capsule.shape is CapsuleShape3D:
		var height := character.capsule_height - drop * amount
		capsule.shape.height = height
		capsule.position.y = height * 0.5
