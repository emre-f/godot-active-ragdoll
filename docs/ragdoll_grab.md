# RagdollGrab

`RagdollGrab` lets a character grab things with both hands. Light bodies are lifted and carried. Heavy bodies and other ragdolls are pulled on a rope from the chest. The game sets `hold` and `aim_pitch` each tick. The addon never reads `Input`.

Source: `controller/ragdoll_grab.gd`, `controller/ragdoll_grab_hold.gd`, `controller/ragdoll_arm_ik.gd`, `net/ragdoll_grab_sync.gd`.

## Setup

Add a `RagdollGrab` node as a child of the `RagdollCharacter`. It finds the actor with `actor_path` or by search. It makes a child node named `Sync` for network display.

```gdscript
func _physics_process(_delta: float) -> void:
	var grab: RagdollGrab = $Player/Grab
	grab.hold = Input.is_action_pressed("grab")
	grab.aim_pitch = asin(clampf(-camera.global_transform.basis.z.y, -1.0, 1.0))
	if grab.hold:
		$Player.face_direction = camera_forward_flat
```

For a spider, set `arm_chains` to the front legs, `chest_slot` to the body slot, and `hands_at_chain_tip` on.

## How it works

While `hold` is on and the character is controllable, both arms go to a ready pose with `RagdollArmIK`: two `TwoBoneIK3D` targets at chest height plus `hand_height`, forward by `reach`, `hand_spacing` apart, tilted by `aim_pitch` between `pitch_min_degrees` and `pitch_max_degrees`. The arm chains get `arm_strength` while the pose blends in over `blend_time`.

Each physics tick without a held body, a sphere of `grab_radius` at the hands, led by the capsule velocity times `grab_lead_time`, looks for the nearest `RigidBody3D` on `grab_mask`. A `StaticBody3D` is never grabbed. The first body found is grabbed.

A knock, a limp actor, or `hold` off releases the body.

### LIFT

A body with mass at or below `lift_mass_limit` that is not a `RagdollBone` and not frozen is lifted. No joint is made. Each tick the body velocity is set toward the hand anchor with `lift_response_time`, capped at `lift_speed_max`, and its rotation keeps the grab time rotation relative to the holder facing. Raising `aim_pitch` raises the item. Release keeps the anchor velocity, so a throw is momentum only: move and release.

Collision between the item and the holder bodies is off while lifted.

### PULL

Any other body hangs on a rope from the chest with rest length `reach`. The rope point is a ray cast surface point on the body, kept in body space.

- Beyond the rest length the point is pulled toward the chest with a force capped at `pull_force_max`, horizontal only, plus a vertical pull toward the anchor height capped at `lift_force_max`. One end of a plank can be tilted up. A heavy crate is not lifted.
- Beyond `reach + leash_slack` the holder is dragged toward the body with `drag_velocity`, capped at `drag_speed_max`.
- Beyond `reach + break_slack` for `break_time` the hold breaks.
- A too heavy body is not a special case. Friction beats the capped force.

The holder capsule speed is scaled by `held_speed_scale` while pulling.

### Grabbing a character

A grabbed `RagdollBone` belongs to a `RagdollCharacter` victim. A controllable victim is not pulled by force. It gets `drag_velocity` toward the holder, capped at `drag_speed_max`, and `speed_scale` set to `held_speed_scale`. An idle victim is dragged. A running victim beats the drag and breaks the rope after about a second.

A hold on a leg trips the victim: after `trip_time`, when the victim moves faster than `trip_speed` or the rope is stretched, `hit()` is called on the victim with `trip_impulse` times its mass, upward and toward the holder. That knocks the victim when the impulse is above its threshold.

## API

| Call | Meaning |
|---|---|
| `is_holding()` | True while a body is held. |
| `held_body()` | The held `RigidBody3D`, or null. |
| `held.kind` | `RagdollGrabHold.Kind.LIFT` or `PULL`. |
| `anchor()` | World position of the hands in the ready pose. |
| `pull_direction()` | Flat direction from the chest to the held point. Use it to face the load. |
| `release()` | Drop the body. |
| `grab(body, hands)` | Grab a body directly. |

Signals: `grabbed(body)` and `released(body)`.

## Network

Grab physics runs only where `simulates()` is true: on the server, or offline. `hold` and `aim_pitch` replicate through `RagdollNetSync`, so the server runs the grab for every unit at the hands of that unit's server copy. The server announces the held body path, kind, and point through `RagdollGrabSync`, and every peer sets `shown_body` and `shown_kind` for the arm display. Only the authority of the holder gets the speed scale. Drags and trips go to the victim's authority with `RagdollNetSync`.

## Exports

| Export | Default | Meaning |
|---|---|---|
| `actor_path` | empty | Path to the actor. Empty searches. |
| `arm_chains` | `arm_l, arm_r` | Chains that hold. |
| `chest_slot` | `chest` | Slot the rope starts from. |
| `hands_at_chain_tip` | `false` | Use the chain tip bone as the hand. Spiders. |
| `reach` | `0.6` | Hand distance forward, and the rope rest length. |
| `hand_spacing` | `0.3` | Distance between the hands. |
| `hand_height` | `0.0` | Hand height offset from the chest. |
| `grab_radius` | `0.7` | Search sphere radius at the hands. |
| `grab_lead_time` | `0.1` | The search sphere leads by the capsule velocity times this. |
| `pitch_min_degrees` | `-80` | Lowest `aim_pitch`. |
| `pitch_max_degrees` | `70` | Highest `aim_pitch`. |
| `grab_mask` | `1` | Layers searched. |
| `arm_strength` | `1.6` | Arm chain strength while holding. |
| `blend_time` | `0.2` | Arm IK blend time. |
| `pole_offset` | `(0, -0.5, -0.5)` | Elbow pole offset from the shoulder, in right, up, forward. |
| `lift_mass_limit` | `10.0` | Heaviest body that is lifted. |
| `lift_response_time` | `0.08` | Time for a lifted body to reach the hands. |
| `lift_speed_max` | `8.0` | Speed cap for a lifted body. |
| `lift_force_max` | `150.0` | Vertical pull force cap in a PULL hold. |
| `pull_force_max` | `1200.0` | Horizontal pull force cap. |
| `drag_speed_max` | `1.5` | Speed cap for a dragged character. |
| `pull_response_time` | `0.15` | Time constant of the pull. |
| `leash_slack` | `0.4` | Stretch before the holder is dragged. |
| `break_slack` | `1.0` | Stretch that breaks the hold after `break_time`. |
| `break_time` | `0.15` | Seconds over `break_slack` before the hold breaks. |
| `held_speed_scale` | `0.6` | Speed scale of the holder and a dragged victim. |
| `trip_time` | `0.2` | Seconds a leg is held before it can trip. |
| `trip_speed` | `0.3` | Victim speed that trips. |
| `trip_impulse` | `5.0` | Trip impulse per kilogram of the victim. |
