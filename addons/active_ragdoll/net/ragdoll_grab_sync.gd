class_name RagdollGrabSync
extends Node

var grab: RagdollGrab
var _shown_local_point: Vector3 = Vector3.ZERO


static func is_online(node: Node) -> bool:
	var peer := node.multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return false
	return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func announce(body: RigidBody3D, kind: RagdollGrabHold.Kind, local_point: Vector3) -> void:
	_show(body, kind, local_point)
	if is_online(self):
		_receive_held.rpc(NodePath("") if body == null else body.get_path(), kind, local_point)


func shown_point() -> Vector3:
	if grab.shown_body == null:
		return Vector3.ZERO
	return grab.shown_body.to_global(_shown_local_point)


func _show(body: RigidBody3D, kind: RagdollGrabHold.Kind, local_point: Vector3) -> void:
	_shown_local_point = local_point
	grab.show_held(body, kind)


@rpc("any_peer", "call_remote", "reliable")
func _receive_held(path: NodePath, kind: int, local_point: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	var body: RigidBody3D = null
	if not path.is_empty():
		body = get_node_or_null(path) as RigidBody3D
	_show(body, kind as RagdollGrabHold.Kind, local_point)
