class_name RagdollVelocityMatchDriver
extends RagdollDriver

@export_range(0.0, 1.0, 0.005) var response_time: float = 0.05
@export_range(0.0, 1.0, 0.005) var root_response_time: float = 0.03
@export_range(0.0, 2.0, 0.05) var root_strength: float = 1.0
@export_range(0.0, 5.0, 0.05) var max_root_separation: float = 0.5
@export_range(0.0, 5000.0, 1.0) var max_linear_acceleration: float = 80.0
@export_range(0.0, 1.0, 0.05) var feed_forward: float = 1.0
@export_range(0.0, 20000.0, 1.0) var max_angular_acceleration: float = 1500.0
@export_range(0.0, 1.0, 0.05) var gravity_compensation: float = 1.0
@export var drive_at_joint: bool = true


func drive(actor: RagdollActor, delta: float) -> void:
	var bones := actor.bones
	var targets := actor.targets
	var max_dv := max_linear_acceleration * delta
	var max_dw := max_angular_acceleration * delta
	var limb_time := maxf(response_time, delta)
	var root_time := maxf(root_response_time, delta)
	var scale := actor.strength_scale
	for i in bones.size():
		var bone := bones[i]
		var strength := bone.strength * scale * (root_strength if i == 0 else 1.0)
		if strength <= 0.0:
			continue
		var time := root_time if i == 0 else limb_time
		var target := targets[i]
		var current := bone.global_transform
		var desired_linear := (target.origin - current.origin) / time + actor.target_velocities[i] * feed_forward
		var dv := ((desired_linear - bone.linear_velocity) * strength).limit_length(max_dv)
		bone.apply_central_impulse(-bone.get_gravity() * delta * gravity_compensation * minf(strength, 1.0) * bone.mass)
		if i == 0 or not drive_at_joint:
			bone.apply_central_impulse(dv * bone.mass)
		else:
			bone.apply_impulse(dv * bone.mass, Vector3.ZERO)
		var rotation := (target.basis * current.basis.inverse()).get_rotation_quaternion()
		if rotation.w < 0.0:
			rotation = -rotation
		var angle := rotation.get_angle()
		var desired_angular := actor.target_angular_velocities[i] * feed_forward
		if angle > 0.0001:
			desired_angular += rotation.get_axis().normalized() * angle / time
		var dw := ((desired_angular - bone.angular_velocity) * strength).limit_length(max_dw)
		var inverse_inertia := bone.get_inverse_inertia_tensor()
		if is_zero_approx(inverse_inertia.determinant()):
			continue
		var inertia := inverse_inertia.inverse()
		if i > 0 and drive_at_joint:
			inertia = _inertia_about_origin(bone, inertia)
		bone.apply_torque_impulse(inertia * dw)
	if max_root_separation > 0.0 and actor.root_snap_enabled and not bones.is_empty():
		var offset := targets[0].origin - bones[0].global_position
		if offset.length() > max_root_separation:
			actor.shift_bones(offset)


static func _inertia_about_origin(bone: RagdollBone, inertia_at_center: Basis) -> Basis:
	var d := bone.global_transform.basis * bone.center_of_mass
	var m := bone.mass
	var dd := d.length_squared()
	var x := inertia_at_center.x + m * (Vector3(dd, 0.0, 0.0) - d * d.x)
	var y := inertia_at_center.y + m * (Vector3(0.0, dd, 0.0) - d * d.y)
	var z := inertia_at_center.z + m * (Vector3(0.0, 0.0, dd) - d * d.z)
	return Basis(x, y, z)
