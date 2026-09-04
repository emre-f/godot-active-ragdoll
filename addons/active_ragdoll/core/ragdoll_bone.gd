class_name RagdollBone
extends RigidBody3D

@export var slot: String = ""
@export var bone_index: int = -1
@export var parent_slot: String = ""
@export_range(0.0, 2.0, 0.05) var strength: float = 1.0
@export var joint: Generic6DOFJoint3D
@export var parent_bone: RagdollBone
@export var bone_length: float = 0.1
@export var bone_axis: Vector3 = Vector3.UP
@export var joint_anchor_in_parent: Vector3 = Vector3.ZERO


func kinetic_energy() -> float:
	var linear := linear_velocity.length_squared()
	var angular := angular_velocity.length_squared()
	return 0.5 * mass * linear + 0.5 * angular * bone_length * bone_length * mass


func joint_separation() -> float:
	if joint == null or parent_bone == null:
		return 0.0
	var anchor_parent := parent_bone.global_transform * joint_anchor_in_parent
	return global_transform.origin.distance_to(anchor_parent)
