class_name RagdollTargetVelocity
extends RefCounted


static func measure(actor: RagdollActor, previous_targets: Array[Transform3D], delta: float, reset: bool) -> bool:
	for i in actor.bones.size():
		var target := actor.targets[i]
		if reset:
			actor.target_velocities[i] = Vector3.ZERO
			actor.target_angular_velocities[i] = Vector3.ZERO
		else:
			actor.target_velocities[i] = (target.origin - previous_targets[i].origin) / delta
			actor.target_angular_velocities[i] = angular_step(previous_targets[i].basis, target.basis) / delta
		previous_targets[i] = target
	return false


static func angular_step(from: Basis, to: Basis) -> Vector3:
	var rotation := (to * from.inverse()).get_rotation_quaternion()
	if rotation.w < 0.0:
		rotation = -rotation
	var angle := rotation.get_angle()
	if angle < 0.0001:
		return Vector3.ZERO
	return rotation.get_axis().normalized() * angle
