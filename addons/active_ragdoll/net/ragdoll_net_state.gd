class_name RagdollNetState
extends RefCounted

var time: float = 0.0
var position: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var velocity: Vector3 = Vector3.ZERO
var state: int = RagdollCharacter.State.DRIVEN
var running: bool = false
var root: Transform3D = Transform3D.IDENTITY
var hold: bool = false
var aim_pitch: float = 0.0
var crouching: bool = false
var baked: bool = false


static func blend(older: RagdollNetState, newer: RagdollNetState, weight: float) -> RagdollNetState:
	var result := RagdollNetState.new()
	result.time = lerpf(older.time, newer.time, weight)
	result.position = older.position.lerp(newer.position, weight)
	result.yaw = lerp_angle(older.yaw, newer.yaw, weight)
	result.velocity = older.velocity.lerp(newer.velocity, weight)
	result.state = newer.state
	result.running = newer.running
	result.root = older.root.interpolate_with(newer.root, weight)
	result.hold = newer.hold
	result.aim_pitch = lerpf(older.aim_pitch, newer.aim_pitch, weight)
	result.crouching = newer.crouching
	result.baked = newer.baked
	return result
