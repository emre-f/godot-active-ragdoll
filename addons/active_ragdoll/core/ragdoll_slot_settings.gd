class_name RagdollSlotSettings
extends Resource

enum Shape { CAPSULE, BOX, SPHERE }

@export_range(0.0, 200.0, 0.01) var mass: float = 0.0
@export var shape: Shape = Shape.CAPSULE
@export_range(0.0, 2.0, 0.001) var radius: float = 0.0
@export_range(0.0, 5.0, 0.001) var length: float = 0.0
@export var offset: Vector3 = Vector3.ZERO
@export_range(0.0, 2.0, 0.05) var stiffness_multiplier: float = 1.0
@export_range(-1.0, 180.0, 1.0) var twist_limit_degrees: float = -1.0
@export_range(-1.0, 180.0, 1.0) var swing_limit_degrees: float = -1.0
