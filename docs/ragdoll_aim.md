# RagdollAim

`RagdollAim` points an arm at a target and, if you want, turns the head to look at it.
It uses a `TwoBoneIK3D` modifier on each arm chain, and a `LookAtModifier3D` on the head.
It is an optional child of a `RagdollCharacter`.

## What it does

On ready, `RagdollAim` finds the `RagdollActor` above it and waits for the actor to be ready.
Then, for each name in `arm_chains`, it looks up the matching arm chain on the archetype.
The chain must have at least three slots. The first three slots become the shoulder, elbow, and hand bones for a `TwoBoneIK3D`.

For each chain, the node builds a target and a pole, both plain `Node3D` marks under the skeleton.
It inserts the `TwoBoneIK3D` as an earlier sibling of the `RagdollActor` under the skeleton, and points the IK at the target and pole.

If `look_with_head` is on, it also builds a `LookAtModifier3D` on the head bone, with an angle limit.

Every frame, `RagdollAim`:
- Blends `weight` toward 1 when `aim_active` is true and the ragdoll is not limp, or toward 0 otherwise. The blend takes `blend_time` seconds.
- Moves each arm target to `shoulder position + aim_direction * reach`.
- Moves each pole to a spot beside and behind the shoulder, using `pole_offset`.
- Sets each IK's `influence` to `weight`.
- While `weight` is changing, raises the arm chain's joint strength toward `aim_strength` (via `RagdollActor.set_strength_multiplier`), so the arm holds its pose against gravity.
- If head look is on, moves the look target to `aim_origin + aim_direction * 20.0` and sets the look modifier's `influence` to `weight`.

`RagdollAim` never reads where the ragdoll's hand or head already is. It only uses the origin and direction you give it. You must call `set_aim` and set `aim_active` yourself, every frame, from your own aim logic (mouse look, target lock, and so on).

## Exports

| Export | Default | Meaning |
|---|---|---|
| `actor_path` | (empty) | Path to the `RagdollActor`. If empty, `RagdollAim` searches its parents for one. |
| `arm_chains` | `["arm_r"]` | Names of the arm chains to drive. Each chain needs at least three slots. |
| `reach` | `0.55` | Distance from the shoulder to the aim target, in meters. |
| `aim_strength` | `1.6` | Joint strength multiplier applied to the arm chain while aiming, blended by `weight`. |
| `blend_time` | `0.25` | Seconds for `weight` to go from 0 to 1, or back. |
| `pole_offset` | `(0, -0.5, -0.5)` | Local offset (right, up, forward) used to place the elbow pole relative to the shoulder. |
| `look_with_head` | `true` | If true, also turns the head toward the aim point. |
| `head_slot` | `"head"` | Bone slot used for the head look modifier. |
| `head_forward_axis` | `+Z` | Which local axis of the head bone points forward. |
| `head_limit_degrees` | `70.0` | Maximum angle the head may turn from its rest pose, on each side. |

## Usage

```gdscript
# RagdollCharacter
#   RagdollActor
#   RagdollAim

extends Node

@onready var aim: RagdollAim = $"../RagdollAim"

func _process(_delta: float) -> void:
	var muzzle_position := global_position + Vector3.UP
	var direction := (target.global_position - muzzle_position).normalized()
	aim.set_aim(muzzle_position, direction)
	aim.aim_active = is_aiming_at_target
```

## Gotchas

- The `TwoBoneIK3D` and `LookAtModifier3D` modifiers must sit earlier than the `RagdollActor` in the skeleton's child order. `RagdollAim` places its own modifiers correctly. If you add more modifiers by hand, keep them before the `RagdollActor` too, or they run after the ragdoll pose and have no visible effect.
- A `TwoBoneIK3D` with no pole node set does nothing, with no warning. `RagdollAim` always creates a pole for you, so this only matters if you build your own IK setup.
- `RagdollAim` never computes the aim direction from the ragdoll. If you never call `set_aim`, the arm aims at `Vector3.ZERO` with direction `Vector3.FORWARD`. Always feed it a fresh origin and direction.
- `aim_active` only requests the aim. The ragdoll must also not be limp, or `weight` stays at 0 and the arm will not move.
