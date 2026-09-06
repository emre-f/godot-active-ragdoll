# RagdollProfile and the body plan resources

A ragdoll is described by a stack of resources. `RagdollArchetype` says what slots exist and how
they chain together, for one body plan (biped, quadruped, spider). `RagdollBoneMap` says which
bone name, on one specific rig, fills each slot. `RagdollProfile` holds the tuning: mass, shape,
joint limits, stiffness, and the driver. `RagdollSlotSettings` overrides one slot inside a profile.
`RagdollBoneMatcher` guesses a bone map for you. `RagdollShapeBuilder` and `RagdollMeshFitter` turn
that data into real collision shapes.

Source files: `core/ragdoll_profile.gd`, `core/ragdoll_archetype.gd`, `core/ragdoll_chain.gd`,
`core/ragdoll_slot_settings.gd`, `core/ragdoll_bone_map.gd`, `core/ragdoll_bone_matcher.gd`,
`core/ragdoll_shape_builder.gd`, `core/ragdoll_mesh_fitter.gd`,
`drivers/ragdoll_velocity_match_driver.gd`, `core/ragdoll_driver.gd`, `archetypes/*.tres`.

## RagdollArchetype

Describes a body plan as a root slot plus chains. It never mentions bone names.

| Export | Default | Meaning |
|---|---|---|
| `archetype_name` | `""` | Display name shown in the dock. |
| `root_slot` | `"pelvis"` | The slot with no parent. Becomes bone index 0, generated first. |
| `root_radius_ratio` | `0.6` | Collider radius for the root, as a fraction of its bone length. |
| `root_kinematic_when_driven` | `false` | If true, the root bone freezes to its animated pose while driven, instead of being pushed by physics. |
| `chains` | `[]` | Array of `RagdollChain`. Order does not matter; each chain names its own parent slot. |
| `symmetry` | `{}` | Left-slot to right-slot name map, used by tools that mirror settings; not read by the generator. |
| `ground_contact_slots` | `[]` | Slots expected to touch the ground; not read by any script in this addon yet. |

Shipped archetypes: `biped_humanoid`, `quadruped`, `arachnid`, `custom` (an empty starting point
with only a `root_slot`).

## RagdollChain

One connected run of slots inside an archetype, such as an arm or a leg.

| Export | Default | Meaning |
|---|---|---|
| `chain_name` | `""` | Identifier used by `set_strength_multiplier(mult, chain_name)`. |
| `chain_type` | `SPINE` | One of `SPINE`, `NECK`, `ARM`, `LEG`, `TAIL`. Only affects which fallback slot the generator picks for the root's own direction. |
| `parent_slot` | `""` | Slot this chain attaches to (root slot, or a slot in another chain). |
| `slots` | `[]` | Ordered slot names from the chain's base to its tip. |
| `twist_limit_degrees` | `30.0` | Joint twist limit, used unless a slot setting overrides it. |
| `swing_limit_degrees` | `60.0` | Joint swing limit, used unless a slot setting overrides it. |
| `stiffness` | `1.0` | Multiplies every bone's drive strength in this chain, before `RagdollSlotSettings.stiffness_multiplier`. |
| `radius_ratio` | `0.22` | Collider radius as a fraction of bone length, for slots in this chain. |
| `merge_tip_into_parent` | `false` | Declared on every shipped chain's tip, but not read by the generator or the driver; currently has no effect. |
| `kinematic_when_driven` | `false` | If true, every bone in this chain freezes to its animated pose while driven. Used by all arachnid leg chains. |

## RagdollBoneMap

Maps each archetype slot to one bone name on a specific `Skeleton3D`.

| Export | Default | Meaning |
|---|---|---|
| `archetype` | `null` | The archetype this map is for. |
| `slot_to_bone` | `{}` | Dictionary from slot name to bone name. |

`missing_slots()` lists archetype slots with no bone assigned. `is_complete()` is true only when
every slot has one. `unresolved_bones(skeleton)` lists mapped names that do not exist on a given
skeleton, so `RagdollProfile.validate` can warn about a rig mismatch.

## RagdollBoneMatcher

`RagdollBoneMatcher.suggest(archetype, skeleton)` fills a bone map automatically. For every slot
and every bone name, it scores a match: side (`l`/`r`) and front/hind position must agree, leading
digit sequences must agree, and then it prefers an exact core-name match, then a known synonym
(`"thigh"` matches `"upperleg"`, `"upleg"`, `"femur"`, and so on), then a prefix or substring match.
It also strips rig prefixes such as `mixamorig` and armature namespaces before matching. Every
match is used at most once. Slots with no acceptable bone are left empty for you to fill in by
hand in the dock.

## RagdollSlotSettings

Optional per-slot override, stored in `RagdollProfile.slot_settings` keyed by slot name. Any value
left at its default falls back to the profile or chain default instead.

| Export | Default | Meaning |
|---|---|---|
| `mass` | `0.0` | Fixed mass in kg. `0.0` means auto: this slot's mass is instead computed from `total_mass` split by collider volume, see below. |
| `shape` | `CAPSULE` | `CAPSULE`, `BOX`, or `SPHERE`. |
| `radius` | `0.0` | Fixed collider radius. `0.0` means use the chain's `radius_ratio`, or the mesh-fitted radius. |
| `length` | `0.0` | Fixed bone length. `0.0` means measure from the skeleton (next slot, farthest child, or a guess). |
| `offset` | `(0,0,0)` | Local offset applied to the collision shape's center. |
| `stiffness_multiplier` | `1.0` | Multiplies this slot's drive strength, on top of the chain's `stiffness`. |
| `twist_limit_degrees` | `-1.0` | `-1.0` means use the chain's `twist_limit_degrees`. Any value `>= 0.0` overrides it for this slot's joint. |
| `swing_limit_degrees` | `-1.0` | Same rule as twist, for swing. |

## RagdollProfile

Holds the tuning that applies across a whole ragdoll, plus the slot overrides above.

| Export | Default | Meaning |
|---|---|---|
| `archetype` | `null` | The `RagdollArchetype` to generate. |
| `bone_map` | `null` | The `RagdollBoneMap` for the target skeleton. |
| `slot_settings` | `{}` | Slot name to `RagdollSlotSettings`. |
| `driver` | `null` | The `RagdollDriver` used to drive bones toward their target pose. No driver means the ragdoll only ever ragdolls; it is never actively driven. |
| `self_collision` | `false` | If false, every pair of bones gets a collision exception, so the ragdoll cannot collide with itself. |
| `fit_to_mesh` | `true` | If true, measure bone length and radius from skinned mesh vertices instead of only the skeleton rest pose. See Fit to mesh below. |
| `total_mass` | `70.0` | Total kg split across every bone whose slot has no fixed `mass`. |
| `min_mass_share` | `0.01` | Floor on each auto-computed bone's share of `total_mass`, so a tiny sliver of volume never gets an unreasonably small mass. |
| `collision_layer` | `1` | Collision layer for every generated `RagdollBone`. |
| `collision_mask` | `1` | Collision mask for every generated `RagdollBone`. |
| `tip_length_ratio` | `0.6` | Length given to a tip bone (one with no next slot and no child bone found) as a fraction of its parent's length. |
| `tip_radius_scale` | `0.6` | Extra radius scale applied to tip slots (the last slot in a chain with 2+ slots), on top of the chain's `radius_ratio`. |
| `linear_damp` | `0.5` | `RigidBody3D.linear_damp` for every bone. |
| `angular_damp` | `2.0` | `RigidBody3D.angular_damp` for every bone. |
| `continuous_collision` | `true` | `RigidBody3D.continuous_cd` for every bone. |
| `friction` | `0.4` | Physics material friction for every bone. Higher values make planted feet stick and fight the drive. |
| `bounce` | `0.0` | Physics material bounce for every bone. |
| `debug_meshes` | `false` | If true, the generator adds a visible `MeshInstance3D` on every bone matching its collision shape, in a flat debug color. |
| `lod_kinematic_collision` | `false` | If true, T2/T3 LOD tiers freeze bones in place instead of releasing them, and keep their collision on. |
| `settle_energy_threshold` | `0.02` | Kinetic energy per kg, below which a limp ragdoll counts as resting this tick. |
| `settle_ticks` | `30` | Consecutive resting ticks needed before `is_settled()` becomes true. |

### Mass split by volume

`RagdollGenerator._assign_auto_masses` gives every slot with `RagdollSlotSettings.mass <= 0.0` a
share of `total_mass` proportional to its collider's volume (capsule, box, or sphere volume from
`RagdollShapeBuilder.volume`), after subtracting the mass already claimed by slots with a fixed
`mass`. Each auto share is floored at `total_mass * min_mass_share`. `RagdollGenerator` then warns
if any parent/child mass ratio falls outside 0.02 to 5, since extreme ratios make joints unstable.

### Fit to mesh

When `fit_to_mesh` is on, `RagdollMeshFitter` collects skinned vertex positions per bone from every
`MeshInstance3D` bound to the skeleton (weight >= 0.35 counts), in the bone's rest space. For each
slot it measures how far those vertices spread along the bone's axis (2.5th to 97th percentile, so
outliers do not stretch the shape) and across it (85th percentile), and uses that for length,
radius, and center instead of the raw skeleton guess. If the generator only guessed the axis
direction, the fitter tries several candidate axes and keeps whichever gives the longest spread.

### Tip ratios

A tip slot is the last slot in a chain with two or more slots (`RagdollProfile.is_tip_slot`). Its
radius gets multiplied by `tip_radius_scale`, since tip bones (hands, feet, the head) are usually
thinner than their chain's default ratio. Its length, when the generator cannot find a next bone
to measure to, is a fallback of the parent's length times `tip_length_ratio`.

### kinematic_when_driven and root_kinematic_when_driven

While the ragdoll is being driven, `RagdollKinematicBones.update` snaps a bone straight to its
animated target and marks it kinematic instead of letting physics move it, for: the root bone if
`archetype.root_kinematic_when_driven` is true, or any other bone whose chain has
`kinematic_when_driven` set. Kinematic bones still block driven strength from dropping below 1.0:
this substitution only happens when `strength_scale >= 1.0`. It is used so legs that must place
precisely (spiders) or a root that must not wobble stay exact while driven, but still fall and
tumble normally once the ragdoll goes limp.

### self_collision and collision layers

With `self_collision` false (the default), `RagdollActorSetup.apply_collision_rules` adds a
pairwise collision exception between every two bones on the same actor, so a ragdoll's own limbs
never push against each other. `collision_layer` and `collision_mask` apply to every bone equally;
there is no per-slot layer override.

### Settle thresholds

`RagdollSettleTracker.update` runs only while `is_limp`. Each physics tick it compares
`actor.kinetic_energy()` (summed linear plus a length-scaled angular term, per bone) against
`settle_energy_threshold * total_mass()`. If it stays under that for `settle_ticks` ticks in a row,
`is_settled()` becomes true and the actor emits `settled`.

## RagdollDriver and RagdollVelocityMatchDriver

`RagdollDriver` is the base resource: `drive(actor, delta)` (called every drive tick) and
`on_attached(actor)` (called once when the actor attaches its bones), both empty by default.

`RagdollVelocityMatchDriver` is the shipped driver. Each tick, for every bone, it computes the
linear and angular velocity that would reach the bone's target transform in `response_time`
seconds (or `root_response_time` for the root), applies that as an impulse scaled by the bone's
`strength` and `actor.strength_scale`, and adds a feed-forward term from the target's own recent
velocity.

| Export | Default | Meaning |
|---|---|---|
| `response_time` | `0.05` | Seconds to close the gap to target for non-root bones. Lower is stiffer and more kinematic-looking; higher looks floppier. |
| `root_response_time` | `0.03` | Same, for the root bone only. |
| `root_strength` | `1.0` | Extra multiplier applied only to the root bone's strength. |
| `max_root_separation` | `0.5` | If the root drifts this far (meters) from its target, `shift_bones` pulls every bone back by the offset. `0.0` disables the snap. |
| `max_linear_acceleration` | `80.0` | Caps the linear velocity change applied per tick, so a heavy obstacle can still push a driven body instead of the drive overpowering it. |
| `feed_forward` | `1.0` | How much of the target's own recent velocity/angular velocity is added on top of the position-correction term. |
| `max_angular_acceleration` | `1500.0` | Caps the angular velocity change applied per tick. |
| `gravity_compensation` | `1.0` | Fraction of the bone's own gravity canceled out every tick (scaled by `min(strength, 1.0)`), so limbs do not sag under the drive. |
| `drive_at_joint` | `true` | If true, non-root bones get their linear impulse and torque applied through the joint anchor (using inertia recomputed about that point) instead of the center of mass, which resists stretching the joint. |

`root_snap_enabled` (a var on `RagdollActor`, not exported here) gates the `max_root_separation`
snap; `RagdollCharacter` turns it off while recovering so the capsule, not the driver, controls
where the root ends up.
