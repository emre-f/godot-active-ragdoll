# RagdollAnimator

`RagdollAnimator` picks which clip to play (idle, walk, run, or fall) based on how fast the `RagdollCharacter` capsule is moving. It is an optional child of a `RagdollCharacter`, sitting next to an `AnimationPlayer`.

## What it does

On ready, `RagdollAnimator` reads its parent as a `RagdollCharacter`. It finds the `AnimationPlayer` from `player_path`, or, if that is empty, the first `AnimationPlayer` under the character. It sets the idle, walk, and run clips to loop. The fall clip is left as-is, so it plays once.

Every frame, while the character is in the `DRIVEN` state:

1. Read the capsule's horizontal speed (`character.horizontal_speed()`).
2. If the character is off the floor and a fall clip exists, play the fall clip.
3. Otherwise, if speed is above `0.2`, pick walk or run: the cutoff is the midpoint between `walk_speed` and `run_speed` on the `RagdollCharacter`. Below `0.2`, play idle.
4. If the chosen clip does not exist on the player, nothing changes this frame; whatever was last playing keeps playing.
5. If the clip changed, play it with a `blend_time` cross-fade.
6. If `scale_playback` is on, and the clip is walk or run, scale the player's `speed_scale` to `speed / walk_clip_speed` (or `run_clip_speed`). This keeps footstep timing matched to the actual ground speed instead of sliding. Idle and fall always play at normal speed.

`RagdollAnimator` does nothing while the character is knocked down, settling, dead, or recovering. During those states the ragdoll's own pose, or a get-up animation played from `RagdollCharacter`, drives the skeleton instead.

## Exports

| Export | Default | Meaning |
|---|---|---|
| `player_path` | (empty) | Path to the `AnimationPlayer`. If empty, `RagdollAnimator` searches the character for one. |
| `idle_animation` | `"Idle"` | Clip played at rest. |
| `walk_animation` | `"Walk"` | Clip played at low speed. |
| `run_animation` | `"Run"` | Clip played above the walk/run midpoint speed. |
| `fall_animation` | `"Fall"` | Clip played while airborne, if it exists. |
| `walk_clip_speed` | `1.5` | Ground speed, in meters per second, the walk clip was authored at. Used to scale playback. |
| `run_clip_speed` | `5.0` | Ground speed the run clip was authored at. Used to scale playback. |
| `blend_time` | `0.2` | Cross-fade time, in seconds, when switching clips. |
| `scale_playback` | `true` | If true, walk and run playback speed follows the character's actual speed. |

## Usage

```gdscript
# RagdollCharacter
#   AnimationPlayer
#   RagdollAnimator

extends Node

@onready var animator: RagdollAnimator = $"../RagdollAnimator"

func _ready() -> void:
	animator.walk_clip_speed = 1.2
	animator.run_clip_speed = 4.5
```

## Notes

- If a clip named in an export does not exist on the `AnimationPlayer`, `RagdollAnimator` quietly keeps whatever is already playing. Check clip names carefully if animation seems stuck.
- If `fall_animation` is missing (or its name is blank) and the character goes airborne, `RagdollAnimator` falls back to the normal speed-based pick (idle, walk, or run) instead of a fall pose.
