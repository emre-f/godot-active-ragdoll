# RagdollFootSolver

`RagdollFootSolver` keeps a biped's feet on the ground. It looks straight down from each animated foot, finds the floor, and moves a `TwoBoneIK3D` target to that height. It is an optional child of a `RagdollCharacter`, next to the `RagdollActor`.

## What it does

On ready, `RagdollFootSolver` finds the `RagdollActor` and waits for it to be ready. Its own parent must be a `Node3D` (normally the `RagdollCharacter`); the script reads this parent as the body.

During setup, it looks at every `LEG` chain on the archetype that has exactly three slots (hip, knee, foot). For each one it builds a target and a pole, and a `TwoBoneIK3D`:

- Root bone is the hip, middle bone is the knee.
- If the foot bone is a direct child of the knee bone, the foot is the end bone.
- Otherwise (for example, a separate toe bone), the solver uses a virtual end bone that extends straight along the knee's local Y axis, with a length equal to the rest distance from knee to foot. This lets the same code work when the foot slot is not the knee's immediate child.

Each `TwoBoneIK3D` is inserted as an earlier sibling of the `RagdollActor` under the skeleton.

## How it probes

Every frame, for each leg:

1. Read the foot bone's current world position (its animated pose).
2. Cast a ray straight up and down (world up, not the body's own up) from that position, `ground_probe_depth` meters each way, on `ground_mask`. Bones of the ragdoll itself, and any collision object above the actor in the tree (the character's own capsule), are excluded.
3. `offset = ground.y + foot_height - floor_y`, where `floor_y` is the body node's own Y position. This is how far the target must move up or down from the animated foot pose.
4. Move the foot target to `foot + up * offset`.
5. Move the pole to the knee bone's world position, shifted by `pole_offset` rotated into the body's own orientation. This keeps the knee pointing the way you set (forward, by default).
6. Set the IK's `influence` to the exported `influence` value.

Because the ray always goes straight up and down in world space, this solver assumes the character walks on roughly flat, gravity-aligned ground. It is built for bipeds, not for climbing or sloped-surface characters.

## Exports

| Export | Default | Meaning |
|---|---|---|
| `actor_path` | (empty) | Path to the `RagdollActor`. If empty, `RagdollFootSolver` searches its parents for one. |
| `ground_probe_depth` | `0.6` | How far up and down, in meters, the ground ray reaches from each foot. |
| `foot_height` | `0.0` | Extra height added above the ground hit, to account for foot sole thickness. |
| `ground_mask` | `1` | Physics layers the ground ray can hit. |
| `influence` | `1.0` | Blend weight for all foot IK, applied every frame. Lower it to blend with the raw animation. |
| `pole_offset` | `(0, 0, 1)` | Local offset (right, up, forward) from the body, used to aim the knee pole. |

`last_offsets` is a runtime array (not exported), one float per leg, holding the last computed ground offset for that leg. Other scripts can read it, for example to react to uneven ground.

## Usage

```gdscript
# RagdollCharacter
#   RagdollActor
#   RagdollFootSolver

extends Node

@onready var foot_solver: RagdollFootSolver = $"../RagdollFootSolver"

func _on_ragdoll_knocked() -> void:
	foot_solver.influence = 0.0

func _on_ragdoll_recovered() -> void:
	foot_solver.influence = 1.0
```

## Notes

- Only leg chains with exactly three slots are picked up. A chain with more or fewer slots is skipped with no warning.
- The ground ray ignores the body's own tilt. On a sloped or climbing character, use `RagdollStepSolver` instead, which probes along the body's own up direction.
