# RagdollActor

`RagdollActor` is a `SkeletonModifier3D`. You place it as a child of the `Skeleton3D` it drives.
It holds one `RagdollBone` (a `RigidBody3D`) and one joint per body slot, reads the animated pose
as a drive target, and writes the physics pose back onto the skeleton.

Source files: `core/ragdoll_actor.gd`, `core/ragdoll_actor_update.gd`, `core/ragdoll_actor_setup.gd`,
`core/ragdoll_bone.gd`, `core/ragdoll_generator.gd`, `core/ragdoll_kinematic_bones.gd`,
`core/ragdoll_free_bones.gd`.

## How the dock builds a ragdoll

The editor dock (`editor/ragdoll_dock.gd`) is a panel that shows when you select a `Skeleton3D`:

1. You pick an archetype (`biped_humanoid`, `quadruped`, `arachnid`, or `custom`).
2. "Auto-map bones" calls `RagdollBoneMatcher.suggest`, which guesses a bone name for every
   archetype slot by matching name parts (side, position, segment number, known synonyms).
3. You fix any wrong slot in the generated list, then set a profile save path and press
   "Generate ragdoll".
4. The dock saves the `RagdollProfile` resource, finds or creates a `RagdollActor` under the
   skeleton, and calls `RagdollGenerator.build(actor, skeleton, profile, scene_root)`.
5. `RagdollGenerator` clears any old bodies, then for every slot in the archetype: finds the rest
   pose, works out a bone axis and length (from the next slot in the chain, the farthest child
   bone, the parent's axis, or a straight-up guess, in that order), builds one `RagdollBone`
   (`RigidBody3D`) with a `CollisionShape3D`, gives it a `Generic6DOFJoint3D` to its parent bone
   with twist and swing limits from the profile, and splits `total_mass` across bones by collider
   volume.
6. The generator warns if a bone map slot is missing, if a chain attaches to an unknown slot, or
   if a parent/child mass ratio is outside 0.02 to 5 (joints may explode at extreme ratios).

Generation happens once, in the editor, at authoring time. Save the scene afterward to keep the
generated bodies. `RagdollGenerator.build` only calls `actor.refresh()` itself when not running in
the editor, so a freshly generated actor is wired up properly the first time you run the scene.

## build_at_runtime and start_limp

`RagdollActor` has two `@export` flags read once in `_ready()`:

- `build_at_runtime`: if true, the actor calls `RagdollGenerator.build` itself on ready, instead
  of relying on bodies you already generated and saved in the scene. Use this when you spawn a
  rig that has never been through the dock.
- `start_limp`: if true, the actor calls `go_limp()` right after its first `refresh()`, so the
  ragdoll starts collapsed instead of driven.

`_ready()` also checks that it sits under a `Skeleton3D` and has a `profile` set, and adds itself
to the group `"ragdoll_actors"`.

## Runtime API

```gdscript
actor.knock(Vector3(0, 4, -6), attacker)
if actor.is_settled():
    actor.resume_drive()
```

- `knock(impulse, source = null)`: calls `go_limp()`, applies `impulse` as a central impulse on
  the root bone, and emits `knocked`.
- `go_limp()`: makes every bone dynamic and asleep-allowed, turns off drive, and resets the settle
  tracker. Does nothing if the actor is already baked.
- `resume_drive()`: turns drive back on, clears the limp and settled flags, and resets the target
  velocity so the drive does not see a large jump on the next tick.
- `set_strength_multiplier(multiplier, chain_name = "")`: rewrites `bone.strength` for every bone
  as `profile.stiffness_for(slot) * multiplier`. With no chain name, this affects every bone.
- `shift_bones(offset)`: adds `offset` to every bone's `global_position`. Used by the driver to
  pull the whole ragdoll back when the root has drifted past `max_root_separation`.
- `root_bone()`: the first bone (the archetype root slot), or null if there are no bones. Calls
  `ensure_bodies()` first.
- `bone_for_slot(slot)`: the bone whose `slot` matches, or null. Also calls `ensure_bodies()`.
- `total_mass()`: the sum of every bone's mass, cached when bones are collected.
- `is_settled()`: true once the ragdoll's kinetic energy has stayed below
  `profile.settle_energy_threshold * total_mass()` for `profile.settle_ticks` physics ticks in a
  row, while limp.
- `limp_time()`: seconds elapsed since the last `go_limp()`, counted while the settle tracker runs.
- `max_joint_separation()`: the largest distance, across all bones, between a bone's origin and
  where its joint anchor says it should be relative to its parent. A growing value means a joint
  is stretching or has broken.
- `lowest_point()`: the lowest `global_position.y` among all bones. `RagdollCharacter` uses this
  to plant its capsule while following a fallen ragdoll.
- `release_bodies()` / `build_bodies()`: hand bones to, or take them back from, a
  `RagdollBodyCache`. Released bodies are detached from the actor (freeing physics and process
  cost) but kept alive, not freed; `build_bodies()` re-adds them, restores their pose from the
  skeleton, and re-attaches their joints. These back the T2/T3 LOD tiers.
- `ensure_bodies()`: if the actor is at `T2_KINEMATIC` or deeper, brings it back to `T1_REDUCED`.
  `root_bone()` and `bone_for_slot()` call this so a caller can always get a bone back.
- `bake()`: if the actor has a ragdoll and is not already baked, flags a bake request. The actual
  bake (freeing all physics bodies and freezing the skeleton to its last pose) runs on the next
  `_process_modification_with_delta`, via `RagdollBaker.bake`.
- Debug meshes: there is no `set_debug_meshes_visible` method on `RagdollActor` itself. Debug
  capsule/box/sphere meshes are built by `RagdollShapeBuilder` when `profile.debug_meshes` is on,
  and their visibility is toggled with the static call
  `RagdollShapeBuilder.set_debug_visible(actor, visible)` (and read back with
  `RagdollShapeBuilder.debug_visible(actor)`).

## Signals

| Signal | Emitted when |
|---|---|
| `knocked(impulse, source)` | `knock()` runs, after the impulse is applied. |
| `settled` | The settle tracker reports settled, while limp. |
| `lod_tier_changed(old_tier, new_tier)` | `RagdollLOD.apply` changes the actor's tier. |
| `baked` | `RagdollBaker.bake` finishes freeing bodies and freezing the pose. |
| `bodies_built` | `build_bodies()` finishes restoring bodies from the cache. |
| `bodies_released` | `release_bodies()` finishes moving bodies into the cache. |

## Public vars

| Var | Meaning |
|---|---|
| `strength_scale` | Multiplies every bone's drive strength inside the driver. `RagdollCharacter` ramps this from 0 to 1 while recovering. |
| `drive_enabled` | Whether the driver runs at all this tick. Separate from `is_limp`. |
| `is_limp` | True between `go_limp()` and `resume_drive()`. Blocks driving and lets bones sleep. |
| `lod_tier` | Current `RagdollLOD.Tier` (`T0_FULL`, `T1_REDUCED`, `T2_KINEMATIC`, `T3_DORMANT`). |
| `is_baked` | True once `RagdollBaker.bake` has run. A baked actor stops processing and has no physics bodies left. |
| `is_released` | True while bodies are held in the `RagdollBodyCache` instead of attached. |
| `bake_when_settled` | If true, an external `RagdollLODManager` bakes this actor once it settles, times out, or falls off the simulation budget. `RagdollCharacter.kill()` sets this. |

## The "ragdoll_actors" group

Every `RagdollActor` adds itself to the group `"ragdoll_actors"` in `_ready()`. Systems that need
to see every ragdoll in the scene, such as `RagdollLODManager`, iterate this group instead of
holding direct references.

## Gotchas

- Bones are `top_level = true`. Their transform is independent of the `RagdollActor` and the
  `Skeleton3D`; moving the skeleton node does not move the bodies. Only physics and the drive move
  them.
- Read animated poses only from inside a modifier callback
  (`_process_modification_with_delta`), not from an arbitrary `_process`. `write_pose` captures the
  skeleton's current animated pose into `targets` there before it overwrites the pose with the
  physics result. Reading `skeleton.get_bone_global_pose` outside this callback can race with that
  overwrite.
- Some chains stay kinematic even while the ragdoll is driven. `RagdollKinematicBones.update`
  freezes any bone whose chain has `kinematic_when_driven` (or the root bone, if
  `root_kinematic_when_driven`) set on the archetype, and snaps it straight to its animated target
  instead of letting the driver push it. The arachnid archetype uses this for every leg and its
  root, since spider legs should not wobble under physics.
