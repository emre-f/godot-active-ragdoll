class_name RagdollIKSupport
extends RefCounted


static func find_actor(from: Node, path: NodePath) -> RagdollActor:
	if not path.is_empty():
		return from.get_node_or_null(path) as RagdollActor
	var node := from.get_parent()
	while node != null:
		var found := node.find_children("*", "RagdollActor", true, false)
		if not found.is_empty():
			return found[0]
		node = node.get_parent()
	return null


static func when_ready(actor: RagdollActor, callback: Callable) -> void:
	if actor.is_node_ready():
		callback.call()
	else:
		actor.ready.connect(callback, CONNECT_ONE_SHOT)


static func chains_of_type(actor: RagdollActor, chain_type: RagdollChain.ChainType) -> Array[RagdollChain]:
	var result: Array[RagdollChain] = []
	for chain in actor.profile.archetype.chains:
		if chain.chain_type == chain_type:
			result.append(chain)
	return result


static func chain_named(actor: RagdollActor, chain_name: String) -> RagdollChain:
	for chain in actor.profile.archetype.chains:
		if chain.chain_name == chain_name:
			return chain
	return null


static func bone_names(actor: RagdollActor, chain: RagdollChain) -> PackedStringArray:
	var names := PackedStringArray()
	for slot in chain.slots:
		names.append(actor.profile.bone_map.bone_for(slot))
	return names


static func insert_modifier(actor: RagdollActor, modifier: SkeletonModifier3D, modifier_name: String) -> void:
	var skeleton := actor.get_skeleton()
	modifier.name = modifier_name
	skeleton.add_child(modifier)
	skeleton.move_child(modifier, actor.get_index())


static func make_target(actor: RagdollActor, target_name: String) -> Node3D:
	var target := Node3D.new()
	target.name = target_name
	target.top_level = true
	actor.get_skeleton().add_child(target)
	return target


static func tip_length(skeleton: Skeleton3D, bone_index: int) -> float:
	var longest := 0.0
	for child in skeleton.get_bone_children(bone_index):
		longest = maxf(longest, skeleton.get_bone_rest(child).origin.length())
	if longest > 0.0:
		return longest
	return skeleton.get_bone_rest(bone_index).origin.length()


static func bone_world_position(skeleton: Skeleton3D, bone_index: int) -> Vector3:
	return (skeleton.global_transform * skeleton.get_bone_global_pose(bone_index)).origin


static func ground_below(node: Node3D, from: Vector3, depth: float, mask: int, exclude: Array[RID]) -> Vector3:
	var space := node.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from + Vector3.UP * depth, from - Vector3.UP * depth, mask, exclude)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return from
	return hit.position


static func exclusions(actor: RagdollActor) -> Array[RID]:
	var rids: Array[RID] = []
	for bone in actor.bones:
		rids.append(bone.get_rid())
	var node := actor.get_parent()
	while node != null:
		if node is CollisionObject3D:
			rids.append(node.get_rid())
		node = node.get_parent()
	return rids
