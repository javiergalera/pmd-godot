extends Node2D
## 2D enemy manager — spawning, turn coordination, combat.
## AI logic (pathfinding, destination choosing) is delegated to EnemyAI.

@export var enemy_scene: PackedScene

@onready var dungeon_map: TileMapLayer = get_node_or_null("../TileMapLayer")
@onready var player: Node2D = get_node_or_null("../Player")
@onready var turn_manager: Node = get_node_or_null("../TurnManager")

var _ai := EnemyAI.new()
## tile → enemy node cache for O(1) position lookups.
var _position_cache: Dictionary = {}

func _ready() -> void:
	_ai.randomize_rng()
	if turn_manager:
		turn_manager.enemy_phase_started.connect(_on_enemy_phase)

func _exit_tree() -> void:
	if turn_manager and turn_manager.enemy_phase_started.is_connected(_on_enemy_phase):
		turn_manager.enemy_phase_started.disconnect(_on_enemy_phase)

func reset_enemies(spawn_tiles: Array[Vector2i], tile_size: int, seed_value: int, player_tile: Vector2i) -> void:
	for child in get_children():
		child.queue_free()
	_position_cache.clear()

	_ai.set_seed(seed_value)
	for spawn_tile in spawn_tiles:
		if spawn_tile == player_tile:
			continue
		if enemy_scene == null:
			continue
		var enemy = enemy_scene.instantiate()
		add_child(enemy)
		enemy.configure(spawn_tile, tile_size, self)
		_position_cache[spawn_tile] = enemy

func _on_enemy_phase(action_speed: float) -> void:
	run_enemy_turns(action_speed)

func run_enemy_turns(move_duration: float = 0.07) -> void:
	if player == null or dungeon_map == null:
		if turn_manager:
			turn_manager.finish_enemy_phase()
		return

	var player_tile: Vector2i = player.tile_position
	var attackers: Array[Node] = []
	for child in get_children():
		if not is_instance_valid(child) or child.is_queued_for_deletion():
			continue
		if not child.has_method("move_to_tile"):
			continue
		if not ("tile_position" in child):
			continue
		var old_tile: Vector2i = child.tile_position
		var next_tile := _ai.choose_destination(
			old_tile, player_tile, dungeon_map, _get_occupied_tiles, child
		)
		if next_tile == old_tile:
			child.face_toward(player_tile)
			child.stop_walking()
			if _ai.is_adjacent_to_player(old_tile, player_tile, dungeon_map):
				attackers.append(child)
		else:
			_position_cache.erase(old_tile)
			_position_cache[next_tile] = child
			child.move_to_tile(next_tile, move_duration)

	if attackers.size() > 0:
		await get_tree().create_timer(move_duration).timeout
		for attacker in attackers:
			if not is_instance_valid(attacker) or attacker.is_queued_for_deletion():
				continue
			await CombatResolver.resolve_attack(attacker, attacker.tile_position, player, player.tile_position)
			if is_instance_valid(attacker) and not attacker.is_queued_for_deletion():
				attacker.stop_walking()

	if turn_manager:
		turn_manager.finish_enemy_phase()

func is_tile_occupied_by_enemy(tile: Vector2i) -> bool:
	var enemy = _position_cache.get(tile)
	return enemy != null and is_instance_valid(enemy) and not enemy.is_queued_for_deletion()

func kill_enemy_at(tile: Vector2i, attacker: AnimatedSprite2D, attacker_tile: Vector2i) -> bool:
	var target := get_enemy_at(tile)
	if target == null:
		return false
	await CombatResolver.resolve_attack(attacker, attacker_tile, target, target.tile_position)
	_position_cache.erase(tile)
	target.queue_free()
	return true

func get_enemy_at(tile: Vector2i) -> Node:
	var enemy = _position_cache.get(tile)
	if enemy != null and is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
		return enemy
	_position_cache.erase(tile)
	return null

## Returns a Dictionary of tiles occupied by other enemies (excluding the given one).
func _get_occupied_tiles(exclude: Node) -> Dictionary:
	var result: Dictionary = {}
	for tile in _position_cache:
		var enemy = _position_cache[tile]
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		if enemy == exclude:
			continue
		result[tile] = true
	return result
