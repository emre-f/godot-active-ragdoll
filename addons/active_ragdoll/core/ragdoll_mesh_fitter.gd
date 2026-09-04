class_name RagdollMeshFitter
extends RefCounted

const MIN_WEIGHT := 0.35
const LENGTH_PERCENTILE := 0.97
const RADIUS_PERCENTILE := 0.85
const MIN_VERTICES := 12

var skeleton: Skeleton3D
var vertices_by_bone: Dictionary = {}
var skeleton_scale: float = 1.0


static func for_skeleton(target: Skeleton3D) -> RagdollMeshFitter:
	var fitter := RagdollMeshFitter.new()
	fitter.skeleton = target
	fitter.skeleton_scale = target.global_transform.basis.get_scale().x
	fitter._collect()
	return fitter


func has_data() -> bool:
	return not vertices_by_bone.is_empty()


func measure(bone_index: int, slot_bone_indices: PackedInt32Array, local_axis: Vector3, axis_is_guess: bool) -> Dictionary:
	var points := PackedVector3Array()
	var rest_inverse := skeleton.get_bone_global_rest(bone_index).affine_inverse()
	for owner_bone in vertices_by_bone:
		if _slot_owner(owner_bone, slot_bone_indices) != bone_index:
			continue
		for vertex in vertices_by_bone[owner_bone]:
			points.append(rest_inverse * vertex)
	if points.size() < MIN_VERTICES:
		return {}
	if not axis_is_guess:
		return _measure_along(points, local_axis)
	var best := {}
	for candidate in [local_axis, Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		var measured := _measure_along(points, candidate)
		if best.is_empty() or measured.length > best.length:
			best = measured
	return best


func _measure_along(points: PackedVector3Array, local_axis: Vector3) -> Dictionary:
	var axis := local_axis.normalized()
	var along := PackedFloat32Array()
	var across := PackedFloat32Array()
	for point in points:
		var t := point.dot(axis)
		along.append(t)
		across.append((point - axis * t).length())
	along.sort()
	across.sort()
	var t_min := along[int((1.0 - LENGTH_PERCENTILE) * (along.size() - 1))]
	var t_max := along[int(LENGTH_PERCENTILE * (along.size() - 1))]
	var radius := across[int(RADIUS_PERCENTILE * (across.size() - 1))]
	var s := skeleton_scale
	return {"axis": axis, "length": maxf((t_max - t_min) * s, 0.02), "radius": maxf(radius * s, 0.01), "center": axis * (t_min + t_max) * 0.5 * s}


func _slot_owner(bone_index: int, slot_bone_indices: PackedInt32Array) -> int:
	var current := bone_index
	while current >= 0:
		if slot_bone_indices.has(current):
			return current
		current = skeleton.get_bone_parent(current)
	return -1


func _collect() -> void:
	for mesh_instance in _skinned_meshes():
		var mesh := mesh_instance.mesh
		var to_skeleton := skeleton.global_transform.affine_inverse() * mesh_instance.global_transform
		var bind_to_bone := _bind_to_bone(mesh_instance)
		var bind_to_skeleton := _bind_to_skeleton(mesh_instance, bind_to_bone)
		for surface in mesh.get_surface_count():
			_collect_surface(mesh.surface_get_arrays(surface), to_skeleton, bind_to_bone, bind_to_skeleton)


func _skinned_meshes() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	var scene_root := skeleton.get_parent()
	if scene_root == null:
		return result
	for node in scene_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null or mesh_instance.skeleton.is_empty():
			continue
		if mesh_instance.get_node_or_null(mesh_instance.skeleton) == skeleton:
			result.append(mesh_instance)
	return result


func _bind_to_bone(mesh_instance: MeshInstance3D) -> PackedInt32Array:
	var mapping := PackedInt32Array()
	var skin := mesh_instance.skin
	if skin == null:
		for i in skeleton.get_bone_count():
			mapping.append(i)
		return mapping
	for i in skin.get_bind_count():
		var bone := skin.get_bind_bone(i)
		if bone < 0:
			bone = skeleton.find_bone(skin.get_bind_name(i))
		mapping.append(bone)
	return mapping


func _bind_to_skeleton(mesh_instance: MeshInstance3D, bind_to_bone: PackedInt32Array) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	var skin := mesh_instance.skin
	for i in bind_to_bone.size():
		var bone := bind_to_bone[i]
		if skin == null or bone < 0:
			result.append(Transform3D())
		else:
			result.append(skeleton.get_bone_global_rest(bone) * skin.get_bind_pose(i))
	return result


func _collect_surface(arrays: Array, to_skeleton: Transform3D, bind_to_bone: PackedInt32Array, bind_to_skeleton: Array[Transform3D]) -> void:
	if arrays.is_empty():
		return
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones = arrays[Mesh.ARRAY_BONES]
	var weights = arrays[Mesh.ARRAY_WEIGHTS]
	if positions.is_empty() or bones == null or weights == null:
		return
	var influences: int = bones.size() / positions.size()
	for vertex_index in positions.size():
		var mesh_position := to_skeleton * positions[vertex_index]
		for k in influences:
			var slot: int = vertex_index * influences + k
			if weights[slot] < MIN_WEIGHT:
				continue
			var bind := int(bones[slot])
			if bind < 0 or bind >= bind_to_bone.size():
				continue
			var bone := bind_to_bone[bind]
			if bone < 0:
				continue
			if not vertices_by_bone.has(bone):
				vertices_by_bone[bone] = PackedVector3Array()
			vertices_by_bone[bone].append(bind_to_skeleton[bind] * mesh_position)
