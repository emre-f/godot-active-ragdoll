# Godot Active Ragdoll

An active ragdoll addon for Godot 4.7 with Jolt Physics. It works for any body plan: bipeds, quadrupeds, spiders, and custom rigs. Characters stay controllable while they react to hits, stumble, fly, and get up again. It is made for cooperative games with many characters, so it has LOD tiers and a network adapter.

## Features

- Generator: one rigid body and one joint per slot, fitted to the skinned mesh, from an archetype and a bone map. Works from the editor dock, once, at authoring time.
- Drive: `RagdollVelocityMatchDriver` pulls the bodies to the animated pose with impulses. One stiffness knob per profile, per chain stiffness, per slot multipliers.
- Controller: `RagdollCharacter` is a capsule that moves the character. States `DRIVEN`, `KNOCKED`, `SETTLING`, `RECOVERING`, `DEAD`. Helper nodes for aim, feet, procedural steps, animation, grab, crouch, and wall climb.
- LOD: `RagdollLODManager` keeps hundreds of characters inside a physics budget. Far units release their bodies and get them back when they come close or get hit. Dead units bake to a static pose.
- Net: `RagdollNetSync` replicates the capsule and the root bone at a low rate. Remote limbs simulate locally as ghost limbs. Sender clock sync, adaptive interpolation delay, replicated knocks, kills, and hits.

## Installation

1. Copy `addons/active_ragdoll` into the `addons` folder of your project.
2. Enable "Active Ragdoll" in Project > Project Settings > Plugins.
3. Set Project > Physics > 3D > Physics Engine to Jolt Physics. The addon targets Jolt only.

The release zip named `no-demo` has the addon without the demo folder.

## Demo

Open `addons/active_ragdoll/demo/demo.tscn` and run it. It has a player, a spider, eight wandering bipeds, crates, a ball, and a LOD manager. The rigs are placeholder skeletons without a mesh, so the bodies are drawn as capsules.

| Key | Action |
| --- | --- |
| WASD, Shift | Move, run |
| Space, Ctrl | Jump, crouch |
| E | Grab and hold the thing in front of you |
| RMB, LMB | Aim, shoot the aimed ragdoll |
| Tab | Switch to the next character |
| K, X | Knock, kill the current character |
| T | Throw a crate at the current character |
| O, B | LOD overlay, body capsules |
| R, Esc | Reload, release the mouse |

## Generate a ragdoll

1. Open the scene that has your character and select its `Skeleton3D`. If the character is an instanced scene, such as an imported `.glb`, enable "Editable Children" on it first. The dock also turns this on when it generates.
2. In the "Active Ragdoll" dock, pick an archetype: `biped_humanoid`, `quadruped`, `arachnid`, or `custom`.
3. Click "Auto-map bones". Correct any slot that got the wrong bone.
4. Set a profile path and click "Generate ragdoll". The dock adds a `RagdollActor` under the skeleton with one rigid body and one joint per slot.
5. Save the scene. Generation happens once, at authoring time. At runtime you instance the saved scene.

Tuning lives in the profile `.tres`, not in the scene. Regenerate after a profile change. Masses default to a split of `total_mass` by collider volume. Set `mass` on a slot to override it.

## Scene layout

```
RagdollCharacter            capsule, movement, knock state machine
  Rig                       your imported scene with Skeleton3D and RagdollActor
  Aim (RagdollAim)          one arm chain follows the aim direction, the head looks at it
  Feet (RagdollFootSolver)  biped feet find the ground below the animated foot
  Steps (RagdollStepSolver) procedural stepping for legs without animation
  Animator (RagdollAnimator) picks idle, walk, run, and fall clips from the capsule speed
  Grab (RagdollGrab)        lift light bodies, pull heavy ones on a rope
  Crouch (RagdollCrouch)    lowers the rig and shortens the capsule
  Climb (RagdollClimb)      spiders walk on walls
  NetSync (RagdollNetSync)  replication, only in a multiplayer scene
RagdollLODManager           one per scene, no autoload
```

Every helper is optional. The game sets `move_input`, `running`, `jump_requested`, and `face_direction` on the character each tick. The helpers never read `Input`.

Put the capsule on a layer that only static geometry uses. Thrown objects must not collide with the capsule, or they stop before they reach the ragdoll bodies. The bodies and the capsule never collide with each other.

## Runtime API

```gdscript
var actor: RagdollActor = $Rig/Skeleton3D/RagdollActor
actor.knock(Vector3(0, 4, -8) * actor.total_mass())
actor.go_limp()
actor.resume_drive()
actor.set_strength_multiplier(0.5, "leg_l")
actor.settled.connect(_on_corpse_settled)

var character: RagdollCharacter = $Player
character.move_input = direction
character.hit(direction * 200.0, self, "chest")
character.knock(direction * 6.0 * actor.total_mass())
character.kill()
character.state_changed.connect(_on_state_changed)
$Player/Aim.set_aim(camera.global_position, -camera.global_transform.basis.z)
$Player/Grab.hold = Input.is_action_pressed("grab")
```

## Documentation

- [RagdollActor](docs/ragdoll_actor.md): the modifier that owns the bodies, the joints, and the drive.
- [Profile, archetype, chains, slots, driver](docs/ragdoll_profile.md): everything you tune.
- [RagdollCharacter](docs/ragdoll_character.md): the capsule and the state machine.
- [RagdollAim](docs/ragdoll_aim.md), [RagdollFootSolver](docs/ragdoll_foot_solver.md), [RagdollStepSolver](docs/ragdoll_step_solver.md), [RagdollAnimator](docs/ragdoll_animator.md), [RagdollCrouch](docs/ragdoll_crouch.md), [RagdollClimb](docs/ragdoll_climb.md): the controller helpers.
- [RagdollGrab](docs/ragdoll_grab.md): lift, pull, drag, and throw.
- [RagdollLODManager](docs/ragdoll_lod_manager.md): tiers, budgets, bodies on demand, bake.
- [RagdollNetSync](docs/ragdoll_net_sync.md): what goes over the wire and how remotes follow.

## Requirements

- Godot 4.7 or later.
- Jolt Physics. Godot Physics is not supported.
- The skeleton must have unit scale. Apply the scale on import.
- Stiff drives want 90 to 120 physics ticks per second. The addon works at 60 but the drive is softer.
- IK modifiers made by the helpers must come before `RagdollActor` under the skeleton. The helpers place them there.

## Development

The addon is developed in a separate lab project with playgrounds and headless tests for every layer: drop, bake, glb import, dock, drive, character, steps, LOD, bodies on demand, grab, climb, net, late join, and the demo scene.

## License

MIT
