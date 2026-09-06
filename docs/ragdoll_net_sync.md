# RagdollNetSync

`RagdollNetSync` replicates a `RagdollCharacter` over the Godot high level multiplayer API. Only the capsule and the root bone go over the wire. The other limbs simulate locally on every peer as ghost limbs, so the traffic is small and the ragdoll still moves.

Source: `net/ragdoll_net_sync.gd`, `net/ragdoll_net_remote.gd`, `net/ragdoll_net_state.gd`, `net/ragdoll_net_buffer.gd`, `net/ragdoll_net_clock.gd`, `net/ragdoll_grab_sync.gd`.

## Setup

Add a `RagdollNetSync` node as a child of the `RagdollCharacter`. The authority is the multiplayer authority of the node, so set it on the character with `set_multiplayer_authority(peer_id)` when you spawn it. A `MultiplayerSpawner` spawn function is the usual place:

```gdscript
func _spawn_player(data: Variant) -> Node:
	var id: int = data[0]
	var unit: RagdollCharacter = player_scene.instantiate()
	unit.name = "Player%d" % id
	unit.set_multiplayer_authority(id)
	unit.position = data[1]
	return unit
```

The node finds `RagdollGrab` and `RagdollCrouch` siblings by type and replicates their state too.

## What the authority sends

Every `1 / send_rate` seconds, as `unreliable_ordered`:

- the sender time from its own clock
- capsule position, yaw, and velocity
- character state and `running`
- the root bone `Transform3D`
- grab `hold` and `aim_pitch`, `crouching`
- `actor.is_baked`

Events go as `reliable` when the state changes: `KNOCK` and `KILL` with the impulse from `actor.knocked`, `RECOVER`, and `HIT` with the impulse and slot from `character.hit_applied`. So `character.hit()`, `knock()`, and `kill()` on the authority replicate without extra calls. `event_received(kind, impulse)` fires on the remotes.

`apply_hit(impulse, slot)` can be called on any peer. It sends the hit to the authority with an RPC, and the authority calls `character.hit()`.

## How a remote follows

Each physics tick a remote:

1. Samples the buffer at the sample time from the clock. States are interpolated between the two snapshots around that time.
2. On the first snapshot, and when the capsule is more than `snap_distance` away, teleports the capsule and shifts all bones by the same offset.
3. Coerces the local state to the authority state. `KNOCKED` and `SETTLING` make the local actor limp, `DRIVEN` and `RECOVERING` recover it, `DEAD` kills it.
4. While `DRIVEN`, moves the capsule toward the target with `correction_rate`, sets `move_input` from the network velocity divided by the top speed so `RagdollAnimator` plays the same clip, sets `face_direction` from the yaw, and jumps when the network velocity goes up fast.
5. While limp, freezes the root bone as kinematic on the network root pose. The other bones hang from it. When the authority has baked, the remote bakes when its own bodies settle or after `bake_timeout`.

## Clock and delay

The receiver keeps a smoothed offset between its clock and the sender clock, and a jitter estimate, with `clock_smoothing`. The sample time is the sender time now minus a delay. The delay is `1.5 / send_rate + jitter * jitter_scale`, clamped between `interpolation_delay` and `interpolation_delay_max`. It grows at once when the sample time runs past the newest snapshot and shrinks slowly. `adaptive_delay` off pins the delay to `interpolation_delay`.

`clock.samples`, `clock.jitter`, `clock.delay`, and `clock.starved` are readable for debugging.

## Grab over the network

Grab physics runs only on the server. Because `hold` and `aim_pitch` replicate, the server runs the grab for every unit at the hands of that unit's copy on the server. The server tells all peers which body is held with `RagdollGrabSync`, a child node named `Sync` made by `RagdollGrab`. The peers show the arms on that body. Only the authority of the holder gets the speed scale.

A grabbed character is dragged by its own authority. The server sends the drag velocity to that authority with `send_drag`, refreshed every tick and dropped after `drag_timeout`, and `send_drag_end` on release.

Props that are not characters need their own replication. The lab uses a small server owned body script that sends the transform at 20 Hz.

## Exports

| Export | Default | Meaning |
|---|---|---|
| `send_rate` | `20.0` | State packets per second from the authority. |
| `interpolation_delay` | `0.1` | Minimum delay in seconds behind the newest snapshot. |
| `interpolation_delay_max` | `0.5` | Maximum adaptive delay. |
| `adaptive_delay` | `true` | Grow the delay with jitter and starvation. |
| `jitter_scale` | `3.0` | Delay added per second of measured jitter. |
| `clock_smoothing` | `0.1` | Weight of each new clock sample. |
| `bake_timeout` | `3.0` | Seconds a remote waits for its bodies to settle before it bakes. |
| `snap_distance` | `2.0` | Capsule error that teleports instead of correcting. |
| `correction_rate` | `6.0` | How fast the remote capsule closes the error. |
| `drag_timeout` | `0.25` | Seconds without a drag packet before the drag stops. |

## Gotchas

- `multiplayer.multiplayer_peer` is an `OfflineMultiplayerPeer` by default, never null. Test with `peer is OfflineMultiplayerPeer` or the connection status. Setting the peer to null makes spawned nodes fail in `is_multiplayer_authority()`.
- A late joiner gets no old events. It gets the current state in the first snapshot and coerces to it, so a dead unit shows as dead and bakes.
- Clients send their state through the server relay. Keep `server_relay` on in `SceneMultiplayer`.
