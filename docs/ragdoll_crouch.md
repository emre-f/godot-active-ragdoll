# RagdollCrouch

`RagdollCrouch` lowers the character's rig so the leg IK bends the knees, like a crouch. It also shortens the capsule and slows movement while crouched. It is an optional child of a `RagdollCharacter`.

## What it does

`RagdollCrouch` does not decide when to crouch. Your game sets `crouching` to `true` or `false`; `RagdollCrouch` reacts to it.

On ready, it reads its parent as a `RagdollCharacter`. Setup walks up from the skeleton until it finds the node that is a direct child of the `RagdollCharacter` (the rig root holding the mesh and skeleton), and records its starting local Y position. It also looks for a `CollisionShape3D` named `Capsule` directly under the character; this is the shape `RagdollCharacter` builds automatically when `auto_capsule` is on.

Every physics frame:

1. The target `amount` is `1.0` if `crouching` is true and the character is controllable (state `DRIVEN`), otherwise `0.0`.
2. `amount` moves toward the target at a constant rate, reaching it in `blend_time` seconds.
3. If `amount` did not change this frame, nothing else happens.
4. Otherwise, the rig root's Y position drops by `drop * amount` below its rest height. Because the feet stay planted (via foot IK), this pulls the hips down and bends the knees.
5. `character.crouch_speed_scale` is set to a blend between `1.0` and `speed_scale`, based on `amount`. `RagdollCharacter` multiplies its movement speed by this value.
6. If the `Capsule` collision shape was found and holds a `CapsuleShape3D`, its height shrinks by `drop * amount` and it is re-centered so it still sits on the ground.

## Exports

| Export | Default | Meaning |
|---|---|---|
| `drop` | `0.45` | How far, in meters, the rig and capsule lower at full crouch. |
| `speed_scale` | `0.5` | Movement speed multiplier at full crouch. |
| `blend_time` | `0.15` | Seconds to go from standing to fully crouched, or back. |

## Usage

```gdscript
# RagdollCharacter
#   RagdollActor
#   RagdollCrouch

extends Node

@onready var crouch: RagdollCrouch = $"../RagdollCrouch"

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("crouch"):
		crouch.crouching = not crouch.crouching
```

## Notes

- `RagdollCrouch` looks for a collision shape node literally named `Capsule`. This matches the shape `RagdollCharacter` builds for you. If you author your own collision shape under a different name, the rig will still lower and the speed will still change, but the capsule height will not shrink.
- Crouching only takes effect while the character is controllable. It is ignored while knocked down, settling, dead, or recovering.
