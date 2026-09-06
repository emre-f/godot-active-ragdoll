class_name RagdollDemoWander
extends Node

@export_range(1.0, 200.0, 0.5) var arena_radius: float = 10.0
@export_range(0.5, 30.0, 0.1) var retarget_time: float = 5.0
@export_range(0.0, 1.0, 0.05) var run_chance: float = 0.1
@export var enabled: bool = true

var character: RagdollCharacter
var target: Vector3 = Vector3.ZERO
var timer: float = 0.0


func _ready() -> void:
	character = get_parent() as RagdollCharacter
	_pick_target()


func _physics_process(delta: float) -> void:
	if not enabled or character == null or character.state != RagdollCharacter.State.DRIVEN:
		return
	timer -= delta
	var to_target := target - character.global_position
	to_target.y = 0.0
	if timer <= 0.0 or to_target.length() < 0.5:
		_pick_target()
		return
	character.move_input = to_target.normalized()


func _pick_target() -> void:
	var angle := randf() * TAU
	var radius := sqrt(randf()) * arena_radius
	target = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	timer = retarget_time
	character.running = randf() < run_chance
