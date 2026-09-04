class_name RagdollVelocityMatchDriver
extends RagdollDriver

@export_range(0.0, 1.0, 0.005) var response_time: float = 0.05
@export_range(0.0, 1.0, 0.005) var root_response_time: float = 0.03
@export_range(0.0, 2.0, 0.05) var root_strength: float = 1.0
@export_range(0.0, 5.0, 0.05) var max_root_separation: float = 0.5
@export_range(0.0, 5000.0, 1.0) var max_linear_acceleration: float = 80.0
@export_range(0.0, 20000.0, 1.0) var max_angular_acceleration: float = 1500.0


func drive(actor: RagdollActor, delta: float) -> void:
	var bones := actor.bones
	var targets := actor.targets
	var max_dv := max_linear_acceleration * delta
	var max_dw := max_angular_acceleration * delta
	var limb_time := maxf(response_time, delta)
	var root_time := maxf(root_response_time, delta)
	for i in bones.size():
		var bone := bones[i]
		var strength := bone.strength * (root_strength if i == 0 else 1.0)
		if strength <= 0.0:
			continue
		var time := root_time if i == 0 else limb_time
		var target := targets[i]
		var current := bone.global_transform
		var desired_linear := (target.origin - current.origin) / time
		var dv := ((desired_linear - bone.linear_velocity) * strength).limit_length(max_dv)
		bone.apply_central_impulse(dv * bone.mass)
		var rotation := (target.basis * current.basis.inverse()).get_rotation_quaternion()
		if rotation.w < 0.0:
			rotation = -rotation
		var angle := rotation.get_angle()
		var desired_angular := Vector3.ZERO
		if angle > 0.0001:
			desired_angular = rotation.get_axis().normalized() * angle / time
		var dw := ((desired_angular - bone.angular_velocity) * strength).limit_length(max_dw)
		var inverse_inertia := bone.get_inverse_inertia_tensor()
		if is_zero_approx(inverse_inertia.determinant()):
			continue
		bone.apply_torque_impulse(inverse_inertia.inverse() * dw)
	if max_root_separation > 0.0 and not bones.is_empty():
		var offset := targets[0].origin - bones[0].global_position
		if offset.length() > max_root_separation:
			actor.shift_bones(offset)
