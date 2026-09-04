# Godot Active Ragdoll

An active ragdoll addon for Godot 4.7 with Jolt Physics. It works for any body plan: bipeds, quadrupeds, spiders, and custom rigs. Characters stay controllable while they react to hits, stumble, fly, and get up again.

Status: in development. Milestone 0 (generator and passive ragdoll) is done. The velocity-match drive, the capsule controller, LOD, and net sync come next.

## Installation

1. Copy `addons/active_ragdoll` into the `addons` folder of your project.
2. Enable "Active Ragdoll" in Project > Project Settings > Plugins.
3. Set Project > Physics > 3D > Physics Engine to Jolt Physics. The addon targets Jolt only.

## Generate a ragdoll

1. Open the scene that has your character and select its `Skeleton3D`. If the character is an instanced scene, such as an imported `.glb`, enable "Editable Children" on it first. The dock also turns this on when it generates.
2. In the "Active Ragdoll" dock, pick an archetype: `biped_humanoid`, `quadruped`, `arachnid`, or `custom`.
3. Click "Auto-map bones". Correct any slot that got the wrong bone.
4. Set a profile path and click "Generate ragdoll". The dock adds a `RagdollActor` under the skeleton with one rigid body and one joint per slot.
5. Save the scene. Generation happens once, at authoring time. At runtime you instance the saved scene.

Tuning lives in the profile `.tres`, not in the scene. Regenerate after a profile change. Masses default to a split of `total_mass` by collider volume. Set `mass` on a slot to override it.

## Concepts

- `RagdollArchetype` describes a body plan as chains of slots. It does not know bone names.
- `RagdollBoneMap` maps slots to the bone names of one rig. One archetype fits many rigs.
- `RagdollProfile` holds per-slot mass, collider shape, joint limits, stiffness, and the driver.
- `RagdollActor` is a `SkeletonModifier3D`. It reads the animated pose as the drive target and writes the physics pose back to the bones.
- `RagdollBone` is the rigid body of one slot.
- `RagdollDriver` is the strategy that pulls the bodies to the target pose. `RagdollVelocityMatchDriver` ships with the addon.

## Drive

Set `driver` in the profile to a `RagdollVelocityMatchDriver`. Each physics tick it computes the velocity that moves a body to its animated target in `response_time` seconds and applies the difference as an impulse. `response_time` is the one stiffness knob: `0.0` reaches the target in one tick and looks kinematic, `0.5` lags and looks floppy. The impulse is scaled by the bone `strength`, which comes from the chain `stiffness` and the slot `stiffness_multiplier`. `max_linear_acceleration` caps how hard the drive pulls, so a heavy object can still push a driven body. When the root body is more than `max_root_separation` from its target, every body is moved to close the gap.

At runtime, `actor.set_strength_multiplier(0.3, "arm_l")` scales the strength of one chain, and `actor.set_strength_multiplier(0.3)` scales all of them.

The profile `friction` defaults to `0.4`. Higher values make planted feet stick to the ground and fight the drive.

## Runtime API

```gdscript
var actor: RagdollActor = $Skeleton3D/RagdollActor
actor.knock(Vector3(0, 4, -8) * actor.total_mass())
actor.go_limp()
actor.resume_drive()
actor.set_strength_multiplier(0.5, "leg_l")
actor.is_settled()
actor.settled.connect(_on_corpse_settled)
```

## Requirements

- Godot 4.7 or later.
- Jolt Physics. Godot Physics is not supported.
- The skeleton must have unit scale. Apply the scale on import.
- Stiff drives want 90 to 120 physics ticks per second. The addon works at 60 but the drive is softer.

## License

MIT
