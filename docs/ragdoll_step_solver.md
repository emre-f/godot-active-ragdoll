# RagdollStepSolver

`RagdollStepSolver` moves legs that have no walk animation to work from. It is built for spiders, quadrupeds, and other multi-legged bodies. It picks foot targets on the ground and swings each leg from its old spot to its new one. It is an optional child of a `RagdollCharacter`, next to the `RagdollActor`.

## Setup

On ready, `RagdollStepSolver` finds the `RagdollActor`, waits for it to be ready, then builds one `Leg` per `LEG` chain on the archetype. For each leg it makes a `TwoBoneIK3D` (knee and lower leg bone), a target, and a pole. The pole sits at a fixed spot beside the leg, outward from the body and lifted up, set once at startup.

Each leg also gets a `home_local` position (its rest foothold, in body space) and a `foot_shift_body` correction, so the true foot or toe tip lands in the right place even though the IK only reasons about two bones.

## The group gait

Legs are not free to step whenever they want. They are split into groups, and only one group steps at a time; the rest stay planted for balance.

Grouping uses `leg.group = (i + i / 2) % groups`, where `i` is the leg's order in the archetype's leg chain list. This alternates neighboring leg pairs between groups instead of simply splitting left from right, so the walking pattern looks like an alternating tripod or diagonal gait rather than both legs of a segment lifting together.

Each physics step:

1. Compute body speed: horizontal velocity, plus a turning term (`yaw change / delta * leg radius`) so that turning in place also counts as movement.
2. Compute `swing_time`, the time one step should take: `step_distance / speed`, clamped between `min_step_time` and `step_time`. A faster body gets quicker steps; a slow or still body gets the slowest, longest steps.
3. If no leg is currently swinging, pick the next group to step: for every idle leg, measure the distance between where its foot should be (its desired ground spot) and where it is currently planted. The group whose worst (largest) such distance clears a threshold is chosen. If no leg has drifted far enough, no group is chosen this tick.
4. Any idle leg either belonging to the chosen group, or that has drifted past `step_distance * overreach_ratio` on its own (an overreach), starts a step immediately, even if its group was not chosen. Overreach is a safety valve so a leg does not get left stretched too far during a sharp turn.
5. Legs already mid-swing keep advancing; idle legs stay pinned to their last planted position.

A step aims not at the foot's current desired spot, but slightly ahead of it, using the body's own velocity, so the foot lands where it should be by the time the swing finishes rather than where it should be right now.

While swinging, the foot arcs up and back down (`sin(progress * PI) * step_height`) as it moves in a straight line from its old planted spot to its new one.

`steps_taken` counts every step started, across all legs. It is a plain running counter, useful for tests and debugging, not an export.

## Exports

| Export | Default | Meaning |
|---|---|---|
| `actor_path` | (empty) | Path to the `RagdollActor`. If empty, `RagdollStepSolver` searches its parents for one. |
| `step_distance` | `0.25` | Baseline foot drift, in meters, used to size the step trigger threshold and the overreach threshold. |
| `step_time` | `0.2` | Slowest (longest) swing time, used when the body is barely moving. |
| `min_step_time` | `0.08` | Fastest (shortest) swing time, used when the body moves quickly. |
| `step_height` | `0.1` | Height of the foot's arc during a swing. |
| `velocity_lead` | `0.15` | Seconds of body velocity used to predict where a foothold should land. |
| `foot_height` | `0.0` | Extra height added above the ground hit, to account for foot sole thickness. |
| `ground_probe_depth` | `0.6` | How far up and down, in meters, the ground ray reaches from each foot's desired spot. |
| `ground_mask` | `1` | Physics layers the ground ray can hit. |
| `groups` | `2` | Number of step groups. Legs step group by group, never all at once. |
| `pole_lift` | `0.5` | Height the knee pole sits above the knee, set once at startup. |
| `pole_out` | `0.5` | How far the knee pole sits outward from the body, set once at startup. |
| `overreach_ratio` | `2.0` | Multiplier on `step_distance`. A leg past this drift steps immediately, ignoring the group turn. |

## Usage

```gdscript
# RagdollCharacter
#   RagdollActor
#   RagdollStepSolver

extends Node

@onready var step_solver: RagdollStepSolver = $"../RagdollStepSolver"

func _process(_delta: float) -> void:
	print("steps taken: ", step_solver.steps_taken)
```

## Notes

- Ground probing uses the body's own up direction, not world up, so this solver also works on tilted or climbing bodies (see `RagdollClimb`).
- Only leg chains are used; chains with fewer than two slots are skipped.
- The knee pole position is fixed relative to the body at setup time. It does not track the knee's current pose during a step.
