# RagdollCharacter

`RagdollCharacter` is a `CharacterBody3D`. The capsule moves the character. The ragdoll hangs below the capsule and reacts, but the capsule decides where the character goes. This is what keeps an active ragdoll controllable.

Source: `controller/ragdoll_character.gd`.

## Scene layout

```
RagdollCharacter
  Rig                 your imported scene, with Skeleton3D and RagdollActor under it
  Aim, Feet, Steps, Animator, Grab, Crouch, Climb, NetSync    optional helper nodes
```

The character finds its `RagdollActor` with `actor_path`, or by a search of its children when the path is empty. When `auto_capsule` is on and the node has no `CollisionShape3D`, it adds a capsule named `Capsule` of `capsule_radius` and `capsule_height`, with its base at the node origin.

## Exports

| Export | Default | Meaning |
|---|---|---|
| `actor_path` | empty | Path to the `RagdollActor`. Empty finds the first one below the node. |
| `model_forward` | `(0, 0, 1)` | The direction the rig faces in its own space. Set `(1, 0, 0)` for a rig that faces +X. |
| `walk_speed` | `3.0` | Target speed without `running`. |
| `run_speed` | `6.0` | Target speed with `running`. |
| `acceleration` | `25.0` | How fast the horizontal velocity moves toward the target. |
| `turn_speed` | `12.0` | Exponential turn rate toward the wish or face direction. |
| `max_turn_rate` | `6.0` | Hard cap on yaw change per second. Fast spawn turns made arms explode without it. |
| `jump_speed` | `4.5` | Vertical speed set by `jump_requested` on the floor. |
| `auto_capsule` | `true` | Add a capsule shape when the node has none. |
| `capsule_radius` | `0.3` | Radius of the auto capsule. |
| `capsule_height` | `1.8` | Height of the auto capsule. |
| `knock_impulse_threshold` | `4.0` | `hit()` knocks when the impulse is at least this value times the total mass. |
| `settle_timeout` | `4.0` | Seconds in `KNOCKED` before the state goes on without a settled ragdoll. |
| `rest_time` | `0.4` | Seconds in `SETTLING` before recovery starts. |
| `get_up_time` | `1.2` | Seconds for the drive strength to ramp from 0 to 1. |
| `get_up_animation` | empty | Clip to play on the rig `AnimationPlayer` while the strength ramps. |

## Inputs the game sets each tick

| Var | Meaning |
|---|---|
| `move_input` | Horizontal direction with length 0 to 1. |
| `running` | Use `run_speed` instead of `walk_speed`. |
| `jump_requested` | Jump on the next tick when on the floor. The character clears it. |
| `face_direction` | Direction to face. Zero faces the move direction. |
| `speed_scale` | Multiplies the target speed. `RagdollGrab` sets it while holding. |
| `crouch_speed_scale` | Multiplies the target speed. `RagdollCrouch` sets it. |
| `drag_velocity` | Added to the target velocity. A grab that drags this character sets it. |

The helpers never read `Input`. Your player script reads the input and writes these vars.

```gdscript
func _physics_process(_delta: float) -> void:
	var input := Input.get_vector("left", "right", "forward", "back")
	player.move_input = (camera_forward * -input.y + camera_right * input.x).limit_length(1.0)
	player.running = Input.is_action_pressed("run")
	if Input.is_action_just_pressed("jump"):
		player.jump_requested = true
```

## States

| State | What happens |
|---|---|
| `DRIVEN` | The capsule moves. The drive pulls the bodies to the animated pose. |
| `KNOCKED` | The capsule collision is off and the capsule follows the root bone. Waits for the ragdoll to settle or for `settle_timeout`. |
| `SETTLING` | Rests for `rest_time` on the ground. |
| `RECOVERING` | The capsule stands at the root bone. `strength_scale` ramps from 0 to 1 over `get_up_time`, squared. The root snap is off. Then `DRIVEN`. |
| `DEAD` | Limp for good. `actor.bake_when_settled` is set, so a `RagdollLODManager` bakes it later. |

`state_changed(old_state, new_state)` fires on every transition. `state_name()` returns the name as text. `is_controllable()` is true only in `DRIVEN`. `is_dead()` is true in `DEAD`.

## Knock, kill, hit

```gdscript
character.knock(direction * 6.0 * character.actor.total_mass())
character.kill(direction * 3.0 * character.actor.total_mass())
character.hit(direction * 200.0, self, "chest")
```

- `knock(impulse, source)`: goes limp and enters `KNOCKED`. In any other state it only applies the impulse to the root bone.
- `kill(impulse, source)`: enters `DEAD` and applies the impulse. A limp body keeps its pose.
- `hit(impulse, source, slot)`: compares the impulse length with `knock_impulse_threshold` times the total mass. At or above it calls `knock()`. Below it applies the impulse to the bone of `slot`, or the root bone when the slot is empty or unknown, and emits `hit_applied(impulse, slot)`. `RagdollNetSync` forwards that signal to the other peers.

Impulses scale with mass, so give them as a factor times `actor.total_mass()`.

## Collision layers

Put the capsule on a layer that only static geometry uses. The bodies use the layers of the profile. Thrown objects must not collide with the capsule, or they stop before they reach the ragdoll bodies. The bodies and the capsule never collide with each other. While knocked or dead the capsule turns its collision off, and turns it on again when it recovers.

## Notes

- `horizontal_speed()` returns the capsule speed on the ground plane. `RagdollAnimator` uses it.
- `RagdollClimb` changes `up_direction`. The move code projects the wish direction on the surface.
- A remote copy in a multiplayer scene is driven by `RagdollNetSync`, which writes the same inputs from the network state.
