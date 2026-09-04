class_name RagdollAnimator
extends Node

@export var player_path: NodePath
@export var idle_animation: String = "Idle"
@export var walk_animation: String = "Walk"
@export var run_animation: String = "Run"
@export var fall_animation: String = "Fall"
@export_range(0.1, 10.0, 0.1) var walk_clip_speed: float = 1.5
@export_range(0.1, 20.0, 0.1) var run_clip_speed: float = 5.0
@export_range(0.0, 1.0, 0.01) var blend_time: float = 0.2
@export var scale_playback: bool = true

var character: RagdollCharacter
var player: AnimationPlayer
var current: String = ""


func _ready() -> void:
	character = get_parent() as RagdollCharacter
	if not player_path.is_empty():
		player = get_node_or_null(player_path) as AnimationPlayer
	elif character != null:
		var players := character.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty():
			player = players[0]
	if player == null:
		push_warning("RagdollAnimator %s found no AnimationPlayer" % name)
		return
	for clip in [idle_animation, walk_animation, run_animation]:
		if player.has_animation(clip):
			player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR


func _process(_delta: float) -> void:
	if player == null or character == null or character.state != RagdollCharacter.State.DRIVEN:
		return
	var speed := character.horizontal_speed()
	var clip := idle_animation
	var clip_speed := 1.0
	if not character.is_on_floor() and player.has_animation(fall_animation):
		clip = fall_animation
	elif speed > 0.2:
		var run_threshold := (character.walk_speed + character.run_speed) * 0.5
		clip = run_animation if speed > run_threshold else walk_animation
		clip_speed = run_clip_speed if clip == run_animation else walk_clip_speed
	if not player.has_animation(clip):
		return
	if clip != current:
		player.play(clip, blend_time)
		current = clip
	player.speed_scale = speed / clip_speed if scale_playback and clip != idle_animation and clip != fall_animation else 1.0
