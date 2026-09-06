# RagdollClimb

`RagdollClimb` lets a `RagdollCharacter` walk on walls and ceilings, not just the floor. It probes the surface in front of and below the character, and rotates the character's up direction to match. It is built for spiders, and works alongside `RagdollStepSolver`, which already walks relative to the body's own up direction. It is an optional child of a `RagdollCharacter`.

## What it does

On ready, `RagdollClimb` reads its parent as a `RagdollCharacter`. Setup builds a list of raycast exclusions (the ragdoll's own bones, and collision objects above the actor in the tree), and looks for a sibling `RagdollGrab` node, if one exists, so that anything currently held or pulled is also excluded from surface probing.

Every physics frame:

- If the character is not controllable (knocked down, dead, settling, or recovering), climbing resets: `surface_up` and `character.up_direction` go back to world up, `on_surface` becomes false, and the lost-surface timer clears.
- If `enabled` is false, the character is smoothly rotated back toward world up, and `on_surface` stays false. This lets a character keep its `RagdollClimb` node but walk on flat ground until you turn climbing on.
- If `enabled` is true, `RagdollClimb` probes for a surface (see below). If it finds one, `surface_up` blends toward that surface's normal and `on_surface` becomes true. If it finds nothing, a timer starts counting; while under `fall_reset_time`, the character keeps its last known surface orientation (a short grace period so a small gap in contact does not cause an instant fall). Past `fall_reset_time`, it blends back to world up and `on_surface` becomes false.

## How it probes

The probe uses the character's current up direction and movement heading (from `move_input`, or the current velocity if there is no input):

1. Cast a ray straight down, along the current up direction, from the character's mid-height. This is the resting surface, if any.
2. If the character is moving, cast a second ray forward, out to the capsule radius plus `probe_ahead`. If this hits something, the surface normal blends between the resting surface and this forward hit, based on how close the capsule's edge is to the forward surface. This is what makes turning from a floor onto a wall feel smooth instead of snapping.
3. If there is no forward hit but there is a resting surface, that resting surface is used.
4. If neither ray hits anything, and the character is moving, a third ray checks for a surface just past the capsule's edge, arcing back the other way. This catches going around an edge or corner, such as from a wall onto a ceiling.
5. If nothing is found at all, the probe reports no surface.

Once a target surface normal is chosen, `RagdollClimb` reorients the character: `surface_up` eases toward the target at a rate set by `align_speed`, `character.up_direction` is updated to match, and the character's basis is rotated around its own mid-height point, so it does not pop up or down as it turns onto a new surface.

## Exports

| Export | Default | Meaning |
|---|---|---|
| `enabled` | `false` | Turns climbing on or off. While off, the character eases back to world up. |
| `surface_mask` | `1` | Physics layers the surface probe rays can hit. |
| `probe_ahead` | `0.5` | How far, in meters, the forward probe reaches past the capsule radius. |
| `contact_gap` | `0.05` | Distance from a forward surface at which the blend fully switches to that surface's normal. |
| `probe_depth` | `0.6` | How far the downward and edge-wrap probes reach. |
| `align_speed` | `10.0` | How fast the character's up direction eases toward the found surface. Higher is snappier. |
| `fall_reset_time` | `0.5` | Seconds of no surface contact allowed before the character gives up and falls back to world up. |

`surface_up`, `on_surface`, and `character`/`grab` are runtime state, not exports. `surface_up` is the current climbing up direction; `on_surface` is true while a surface is currently held.

## Usage

```gdscript
# RagdollCharacter
#   RagdollActor
#   RagdollStepSolver
#   RagdollClimb
#   RagdollGrab

extends Node

@onready var climb: RagdollClimb = $"../RagdollClimb"

func _ready() -> void:
	climb.enabled = true

func _process(_delta: float) -> void:
	if not climb.on_surface:
		play_falling_effect()
```

## Notes

- `RagdollClimb` changes `character.up_direction` directly. Any other script reading world-space "up" on this character (cameras, other IK nodes) should use `character.up_direction`, not a hardcoded `Vector3.UP`, once climbing is enabled.
- The forward probe direction comes from `move_input` first, and only falls back to current velocity when there is little or no input. A character standing still with no input and some residual velocity may still turn to face a wall it is drifting toward.
