class_name RagdollShapeBuilder
extends RefCounted

const SHAPE_NAME := "Shape"
const DEBUG_MESH_NAME := "DebugMesh"
const DEBUG_COLOR := Color("#feae34")

static var _shared_debug_material: StandardMaterial3D


static func build(bone: RagdollBone, settings: RagdollSlotSettings, profile: RagdollProfile, length: float, center: Vector3, fitted_radius: float) -> void:
	var radius := length * profile.radius_ratio_for(bone.slot)
	if settings.radius > 0.0:
		radius = settings.radius
	elif fitted_radius > 0.0:
		radius = fitted_radius
	radius = maxf(radius, 0.01)
	var shape_node := CollisionShape3D.new()
	shape_node.name = SHAPE_NAME
	var mesh: Mesh = null
	match settings.shape:
		RagdollSlotSettings.Shape.CAPSULE:
			var capsule := CapsuleShape3D.new()
			capsule.radius = radius
			capsule.height = maxf(length, radius * 2.0)
			shape_node.shape = capsule
			mesh = CapsuleMesh.new()
			mesh.radius = radius
			mesh.height = capsule.height
		RagdollSlotSettings.Shape.BOX:
			var box := BoxShape3D.new()
			box.size = Vector3(radius * 2.0, length, radius * 2.0)
			shape_node.shape = box
			mesh = BoxMesh.new()
			mesh.size = box.size
		RagdollSlotSettings.Shape.SPHERE:
			var sphere := SphereShape3D.new()
			sphere.radius = settings.radius if settings.radius > 0.0 else length * 0.5
			shape_node.shape = sphere
			mesh = SphereMesh.new()
			mesh.radius = sphere.radius
			mesh.height = sphere.radius * 2.0
	shape_node.transform = Transform3D(basis_with_y(bone.bone_axis), center + settings.offset)
	bone.add_child(shape_node)
	if profile.debug_meshes:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = DEBUG_MESH_NAME
		mesh_instance.mesh = mesh
		mesh_instance.transform = shape_node.transform
		mesh_instance.material_override = debug_material()
		bone.add_child(mesh_instance)


static func debug_material() -> StandardMaterial3D:
	if _shared_debug_material == null:
		_shared_debug_material = StandardMaterial3D.new()
		_shared_debug_material.albedo_color = DEBUG_COLOR
	return _shared_debug_material


static func basis_with_y(axis: Vector3) -> Basis:
	var y := axis.normalized()
	var helper := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var z := y.cross(helper).normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)


static func basis_with_x(axis: Vector3) -> Basis:
	var x := axis.normalized()
	var helper := Vector3.UP if absf(x.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var y := helper.cross(x).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


static func volume(bone: RagdollBone) -> float:
	var shape_node := bone.get_node_or_null(SHAPE_NAME) as CollisionShape3D
	if shape_node == null:
		return 0.001
	var shape := shape_node.shape
	if shape is CapsuleShape3D:
		var cylinder := maxf(shape.height - 2.0 * shape.radius, 0.0)
		return PI * shape.radius * shape.radius * cylinder + 4.0 / 3.0 * PI * pow(shape.radius, 3)
	if shape is BoxShape3D:
		return shape.size.x * shape.size.y * shape.size.z
	if shape is SphereShape3D:
		return 4.0 / 3.0 * PI * pow(shape.radius, 3)
	return 0.001
