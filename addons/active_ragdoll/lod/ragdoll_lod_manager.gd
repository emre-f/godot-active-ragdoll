class_name RagdollLODManager
extends Node

signal tiers_updated

@export var focus_paths: Array[NodePath] = []
@export_range(0.02, 2.0, 0.01) var update_interval: float = 0.25
@export_group("Budget")
@export_range(0.0, 500.0, 0.5) var full_budget: float = 12.0
@export_range(0.0, 500.0, 0.5) var reduced_budget: float = 24.0
@export_range(0, 500, 1) var limp_budget: int = 16
@export_range(1, 30, 1) var kinematic_interval: int = 4
@export var adaptive: bool = true
@export_range(0.5, 33.0, 0.1) var frame_budget_ms: float = 6.0
@export_range(0.0, 500.0, 0.5) var min_full_budget: float = 2.0
@export_group("Distances")
@export_range(0.0, 500.0, 0.5) var reduced_distance: float = 12.0
@export_range(0.0, 500.0, 0.5) var kinematic_distance: float = 30.0
@export_range(0.0, 1000.0, 0.5) var dormant_distance: float = 70.0
@export_group("Bake")
@export_range(0.0, 60.0, 0.1) var bake_timeout: float = 6.0
@export var groups: Array[RagdollLODGroup] = []

var adaptive_full_budget: float = 0.0
var last_physics_ms: float = 0.0
var stats := RagdollLODStats.new()
var _timer: float = 0.0
var _focus_points: PackedVector3Array = PackedVector3Array()


func _ready() -> void:
	adaptive_full_budget = full_budget


func _physics_process(delta: float) -> void:
	_timer += delta
	if _timer < update_interval:
		return
	_timer = 0.0
	update_tiers()


func update_tiers() -> void:
	_collect_focus_points()
	_adapt_budget()
	stats.reset()
	var alive: Array[RagdollActor] = []
	var limp: Array[RagdollActor] = []
	for node in get_tree().get_nodes_in_group(RagdollActor.GROUP):
		var actor := node as RagdollActor
		if actor == null or actor.bones.is_empty() and not actor.is_baked:
			continue
		if actor.is_baked:
			stats.count_baked(actor)
			continue
		stats.distances[actor] = _distance_to(actor)
		if actor.is_limp:
			limp.append(actor)
		else:
			alive.append(actor)
	_assign_limp(limp)
	_assign_alive(alive)
	stats.adaptive_full_budget = adaptive_full_budget
	stats.physics_ms = last_physics_ms
	tiers_updated.emit()


func _assign_limp(actors: Array[RagdollActor]) -> void:
	actors.sort_custom(_closer_first)
	var simulated := 0
	for actor in actors:
		var over_budget := simulated >= limp_budget and not actor.lod_pinned
		var timed_out := bake_timeout > 0.0 and actor.limp_time() >= bake_timeout
		if actor.bake_when_settled and (actor.is_settled() or timed_out or over_budget):
			actor.bake()
			stats.count_baked(actor)
			continue
		simulated += 1
		var tier := RagdollLOD.Tier.T0_FULL if stats.full_cost + _cost(actor) <= adaptive_full_budget else RagdollLOD.Tier.T1_REDUCED
		_set_tier(actor, tier)


func _assign_alive(actors: Array[RagdollActor]) -> void:
	actors.sort_custom(_closer_first)
	for actor in actors:
		var tier := _distance_tier(stats.distances[actor])
		if actor.lod_pinned:
			tier = RagdollLOD.Tier.T0_FULL
		elif tier == RagdollLOD.Tier.T0_FULL and stats.full_cost + _cost(actor) > adaptive_full_budget:
			tier = RagdollLOD.Tier.T1_REDUCED
		if tier == RagdollLOD.Tier.T1_REDUCED and stats.reduced_cost + _cost(actor) > reduced_budget and not actor.lod_pinned:
			tier = RagdollLOD.Tier.T2_KINEMATIC
		_set_tier(actor, tier)


func _set_tier(actor: RagdollActor, tier: RagdollLOD.Tier) -> void:
	actor.kinematic_interval = kinematic_interval
	RagdollLOD.apply(actor, tier)
	stats.count(actor, tier, _cost(actor))


func _distance_tier(distance: float) -> RagdollLOD.Tier:
	if distance < reduced_distance:
		return RagdollLOD.Tier.T0_FULL
	if distance < kinematic_distance:
		return RagdollLOD.Tier.T1_REDUCED
	if distance < dormant_distance:
		return RagdollLOD.Tier.T2_KINEMATIC
	return RagdollLOD.Tier.T3_DORMANT


func _closer_first(a: RagdollActor, b: RagdollActor) -> bool:
	if a.lod_pinned != b.lod_pinned:
		return a.lod_pinned
	return stats.distances[a] < stats.distances[b]


func _distance_to(actor: RagdollActor) -> float:
	var group := group_for(actor)
	var scale := group.distance_scale if group != null else 1.0
	var position := actor.get_skeleton().global_position
	var nearest := INF
	for point in _focus_points:
		nearest = minf(nearest, position.distance_to(point))
	return (0.0 if nearest == INF else nearest) / scale


func _cost(actor: RagdollActor) -> float:
	var group := group_for(actor)
	return group.cost if group != null else 1.0


func group_for(actor: RagdollActor) -> RagdollLODGroup:
	var archetype := actor.profile.archetype
	if archetype == null:
		return null
	for group in groups:
		if group.archetype_name == archetype.archetype_name:
			return group
	return null


func _collect_focus_points() -> void:
	_focus_points.clear()
	for path in focus_paths:
		var node := get_node_or_null(path) as Node3D
		if node != null:
			_focus_points.append(node.global_position)
	if _focus_points.is_empty():
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			_focus_points.append(camera.global_position)


func _adapt_budget() -> void:
	last_physics_ms = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	if not adaptive:
		adaptive_full_budget = full_budget
		return
	if last_physics_ms > frame_budget_ms:
		adaptive_full_budget = maxf(min_full_budget, adaptive_full_budget - 1.0)
	elif last_physics_ms < frame_budget_ms * 0.7:
		adaptive_full_budget = minf(full_budget, adaptive_full_budget + 1.0)
