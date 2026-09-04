# Godot Active Ragdoll

An active ragdoll addon for Godot 4.7 with Jolt Physics. It works for any body plan: bipeds, quadrupeds, spiders, and custom rigs. Characters stay controllable while they react to hits, stumble, fly, and get up again.

Status: in development. The generator, the velocity-match drive, and the capsule controller are done. LOD and net sync come next.

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
- `RagdollCharacter` is a `CharacterBody3D` capsule that moves the character. The ragdoll hangs below it and reacts, but the capsule decides where the character goes.

## Drive

Set `driver` in the profile to a `RagdollVelocityMatchDriver`. Each physics tick it computes the velocity that moves a body to its animated target in `response_time` seconds and applies the difference as an impulse. `response_time` is the one stiffness knob: `0.0` reaches the target in one tick and looks kinematic, `0.5` lags and looks floppy. The impulse is scaled by the bone `strength`, which comes from the chain `stiffness` and the slot `stiffness_multiplier`. `max_linear_acceleration` caps how hard the drive pulls, so a heavy object can still push a driven body. When the root body is more than `max_root_separation` from its target, every body is moved to close the gap.

At runtime, `actor.set_strength_multiplier(0.3, "arm_l")` scales the strength of one chain, and `actor.set_strength_multiplier(0.3)` scales all of them.

The profile `friction` defaults to `0.4`. Higher values make planted feet stick to the ground and fight the drive.

## Controller

The controller layer is optional. Put the character scene under a `RagdollCharacter` and add the helper nodes you need as its children:

```
RagdollCharacter            capsule, movement, knock state machine
  Rig                       your imported scene with Skeleton3D and RagdollActor
  RagdollAim                one arm chain follows the aim direction, the head looks at it
  RagdollFootSolver         biped feet find the ground below the animated foot
  RagdollStepSolver         procedural stepping for legs without animation, for spiders and quadrupeds
  RagdollAnimator           picks idle, walk, run, and fall clips from the capsule speed
```

The capsule adds its own `CapsuleShape3D` when `auto_capsule` is on. Put the capsule on a layer that only static geometry uses. Thrown objects must not collide with the capsule, or they stop before they reach the ragdoll bodies. The bodies and the capsule never collide with each other.

The game sets `move_input`, `running`, `jump_requested`, and `face_direction` every tick. The animated skeleton moves with the capsule, and the driver adds the target velocity as feed-forward, so the bodies do not lag behind a walking capsule.

Aim never comes from the ragdoll. Call `aim.set_aim(origin, direction)` with the camera ray and set `aim_active`. The hand chases an IK target on that ray with the built-in `TwoBoneIK3D`, the arm chain strength rises to `aim_strength`, and the head turns with `LookAtModifier3D`. Fire your shot from the same ray.

Knocks are explicit. `character.knock(impulse)` launches the body. `character.hit(impulse, source, slot)` compares the impulse with `knock_impulse_threshold` times the total mass and either knocks or only shoves the body. The states are `DRIVEN`, `KNOCKED`, `SETTLING`, `RECOVERING`. The capsule turns its collision off and follows the root body while knocked. After the body settles, or after `settle_timeout`, the capsule teleports to the body and the drive strength ramps from zero to one over `get_up_time`. Set `get_up_animation` to play a clip during that ramp.

## Runtime API

```gdscript
var actor: RagdollActor = $Skeleton3D/RagdollActor
actor.knock(Vector3(0, 4, -8) * actor.total_mass())
actor.go_limp()
actor.resume_drive()
actor.set_strength_multiplier(0.5, "leg_l")
actor.is_settled()
actor.settled.connect(_on_corpse_settled)

var character: RagdollCharacter = $Player
character.move_input = direction
character.hit(direction * 200.0, self, "chest")
character.state_changed.connect(_on_state_changed)
$Player/Aim.set_aim(camera.global_position, -camera.global_transform.basis.z)
```

## Requirements

- Godot 4.7 or later.
- Jolt Physics. Godot Physics is not supported.
- The skeleton must have unit scale. Apply the scale on import.
- Stiff drives want 90 to 120 physics ticks per second. The addon works at 60 but the drive is softer.

## License

MIT
