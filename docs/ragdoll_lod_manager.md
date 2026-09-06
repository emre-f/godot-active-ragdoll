# RagdollLODManager

`RagdollLODManager` lowers the cost of ragdolls that are far away or off screen.
It sorts every `RagdollActor` in the scene into one of four tiers, and it bakes
dead ragdolls that have settled or that cost too much to keep simulating.

## Setup

Add one `RagdollLODManager` node anywhere in the scene tree. It is a plain
`Node`, not an autoload. One manager watches every `RagdollActor` in the
`ragdoll_actors` group, wherever those actors live in the tree.

Set `focus_paths` to the `NodePath` of one or more `Node3D` nodes, usually
players. Distance is measured from the nearest focus point. If `focus_paths`
is empty, the manager falls back to `get_viewport().get_camera_3d()`.

`groups` holds `RagdollLODGroup` resources, one per archetype name, so
different archetypes can cost more or scale their distance thresholds. An
actor with no matching group uses cost `1.0` and distance scale `1.0`.

## Tiers

| Tier | Name | What happens |
|---|---|---|
| 0 | T0_FULL | Full simulation. The driver runs every physics tick. |
| 1 | T1_REDUCED | The driver runs every second tick (`drive_interval = 2`). Bodies stay fully simulated. |
| 2 | T2_KINEMATIC | The actor stops driving freely. Every `kinematic_interval` ticks it snaps all bones straight to the last driven pose and advances the animation by that many ticks worth of time. Bodies are released (freed and cached) unless `profile.lod_kinematic_collision` is on, in which case they are kept, frozen, and made non-colliding. |
| 3 | T3_DORMANT | No physics tick runs at all, and the pose is not written to the skeleton, so the ragdoll freezes in place. Bodies are released unless `profile.lod_kinematic_collision` is on, in which case they are kept, frozen, and non-colliding, same as T2. |

`RagdollLOD.apply()` does the actual tier switch. If the target tier equals
the current tier, or the actor is already baked, it does nothing.

The manager sets `actor.kinematic_interval` from its own `kinematic_interval`
export before every tier assignment.

## Distance-based tiers

Distance tiers apply only to actors that are not limp (walking, running,
being driven normally):

| Export | Default | Meaning |
|---|---|---|
| `reduced_distance` | `12.0` | Below this distance, the actor wants T0. At or beyond it, T1. |
| `kinematic_distance` | `30.0` | At or beyond this distance, T2. |
| `dormant_distance` | `70.0` | At or beyond this distance, T3. |

Distance is `nearest focus point to the actor's skeleton, divided by the
group's distance_scale`. A group with `distance_scale = 2.0` looks twice as
close as it really is, so it keeps a higher tier for longer.

An actor with `lod_pinned = true` always gets T0, and skips the cost budget
and the build queue. Set this from game code for the player's own ragdoll,
or any actor you never want degraded.

## Cost budgets

`full_budget` and `reduced_budget` are cost totals, not actor counts. Each
actor contributes its group's `cost` (default `1.0`). If placing an actor at
T0 would push the running full cost total over `adaptive_full_budget`, it
drops to T1 instead. If placing it at T1 would push the reduced cost total
over `reduced_budget`, it drops to T2 instead. Actors are sorted closest
first, so close actors claim the budget before far ones.

`limp_budget` works differently: it is a plain count of limp actors kept
simulated at T0 or T1, not a cost total. Once that count is reached, further
limp actors are baked instead of simulated, even if they are close.

### Adaptive full budget

If `adaptive` is on, the manager reads `Performance.TIME_PHYSICS_PROCESS`
each update and compares it to `frame_budget_ms`:

- Above `frame_budget_ms`, `adaptive_full_budget` drops by 1, down to
  `min_full_budget`.
- Below 70% of `frame_budget_ms`, it rises by 1, up to `full_budget`.

If `adaptive` is off, `adaptive_full_budget` always equals `full_budget`.
This reading covers the whole physics frame, not only ragdoll cost, so other
heavy physics work in the scene also pushes ragdolls down a tier.

## Limp and dead ragdolls

Limp actors (knocked down or dead) never use the distance tiers above. They
are sorted closest first and each one is either baked, or kept at T0 or T1
under the full budget rule.

`RagdollCharacter.kill()` sets `actor.bake_when_settled = true`. On each
update the manager bakes a limp actor with `bake_when_settled` set when any
of these is true:

- `actor.is_settled()` returns true (its kinetic energy has stayed below
  `profile.settle_energy_threshold` for `profile.settle_ticks` ticks).
- `bake_timeout` has elapsed since it went limp (`actor.limp_time()`).
- It is over the `limp_budget` count for this update, and it is not
  `lod_pinned`.

### What bake does

`RagdollBaker.bake()`:

1. Captures every bone's current global pose from the skeleton.
2. Frees all `RagdollBone` and joint nodes and returns the actor to the
   released state.
3. Sets every `AnimationMixer` under the rig to `active = false`.
4. Writes the captured poses back into the skeleton as local bone poses
   (deferred), so the skeleton holds the last ragdoll pose with no bodies
   left to simulate.
5. Stops the actor's `_physics_process` and sets `actor.active = false`.
6. Emits `baked`.

A baked actor never changes tier again.

## Released bodies and rebuilding

Actors at T2 or T3 with `lod_kinematic_collision` off have no `RagdollBone`
nodes at all (`is_released = true`). When a released actor's distance tier
rises back to T0 or T1, the manager queues it instead of rebuilding it at
once. `_drain_build_queue()` rebuilds up to `builds_per_tick` actors every
physics tick, spreading the cost of a crowd walking back into range over
several frames. `lod_pinned` actors skip the queue and rebuild immediately.

Anything that touches an actor's bones directly, such as `root_bone()`,
`bone_for_slot()`, or `go_limp()`, calls `ensure_bodies()` first. This forces
a released actor straight to T1 and rebuilds its bodies at once, bypassing
the queue. A hit on a released, far away unit still builds a real body.

## Animation LOD

At T2, the animation advances manually every `kinematic_interval` ticks, by
`delta * kinematic_interval` seconds at a time, matching how often the pose
refreshes. At T3, the animation switches to manual advance but is never
advanced again, so the last pose holds. Coming back to T0 or T1 restores
each `AnimationMixer` to its original `callback_mode_process`.

## Overlay and stats

`RagdollLODOverlay` (`ragdoll_lod_overlay.tscn`) is a `CanvasLayer` with one
`Label`. Set `manager_path` to a `RagdollLODManager`, or leave it empty and
the overlay searches `get_tree().current_scene` for the first one it finds.
It listens to `tiers_updated` and shows `manager.stats.summary()`.

`RagdollLODStats` (on `manager.stats`) is rebuilt every `update_interval`:

| Field | Meaning |
|---|---|
| `tier_counts` | Actor count per tier, indexed by `RagdollLOD.Tier`. |
| `baked_count` | Actors baked so far. |
| `released_count` | Actors currently with no bodies. |
| `pending_builds` | Actors waiting in the build queue. |
| `full_cost`, `reduced_cost` | Summed group cost at T0 and T1 this update. |
| `adaptive_full_budget` | The current adaptive full budget. |
| `physics_ms` | Last read `TIME_PHYSICS_PROCESS`, in milliseconds. |
| `distances` | Actor to distance, for actors that are not limp. |
| `per_archetype` | Per archetype tier and bake counts. |

The `tiers_updated` signal fires once per `update_interval`, after tiers,
budgets, and stats are all recomputed.

## Exports

| Export | Default | Meaning |
|---|---|---|
| `focus_paths` | `[]` | Node paths to measure distance from. Falls back to the current camera. |
| `update_interval` | `0.25` | Seconds between full tier reassignments. |
| `full_budget` | `12.0` | Cost budget for T0. |
| `reduced_budget` | `24.0` | Cost budget for T1. |
| `limp_budget` | `16` | Count budget for simulated limp actors. |
| `kinematic_interval` | `4` | Ticks between T2 pose refreshes. |
| `adaptive` | `true` | Scale the full budget by measured physics time. |
| `frame_budget_ms` | `4.0` | Physics time target used by the adaptive budget. |
| `min_full_budget` | `2.0` | Floor for the adaptive full budget. |
| `builds_per_tick` | `4` | Released actors rebuilt per physics tick. |
| `reduced_distance` | `12.0` | Distance where T0 gives way to T1. |
| `kinematic_distance` | `30.0` | Distance where T1 gives way to T2. |
| `dormant_distance` | `70.0` | Distance where T2 gives way to T3. |
| `bake_timeout` | `6.0` | Seconds limp before a settled or timed out actor bakes. |
| `groups` | `[]` | `RagdollLODGroup` resources, one per archetype name. |

`RagdollLODGroup` exports: `archetype_name` (must match
`RagdollArchetype.archetype_name`), `cost` (default `1.0`, counted against
`full_budget` and `reduced_budget`), and `distance_scale` (default `1.0`,
divides measured distance before comparing to the distance thresholds).
