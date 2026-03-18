extends Node2D

const CARDINAL_DIRECTIONS := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
const WANDER_CHANCE := 35
const CHASE_DISTANCE := 12

@export var enemy_scene: PackedScene

var _dungeon_map: TileMapLayer
var _player: Sprite2D
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_dungeon_map = get_node_or_null("../TileMapLayer")
	_player = get_node_or_null("../Player")
	TurnManager.enemy_phase_started.connect(_on_enemy_phase)

func _exit_tree() -> void:
	if TurnManager.enemy_phase_started.is_connected(_on_enemy_phase):
		TurnManager.enemy_phase_started.disconnect(_on_enemy_phase)

func reset_enemies(spawn_tiles: Array[Vector2i], tile_size: int, seed_value: int, player_tile: Vector2i) -> void:
	for child in get_children():
		remove_child(child)
		child.free()

	_rng.seed = seed_value
	for spawn_tile in spawn_tiles:
		if spawn_tile == player_tile:
			continue
		if enemy_scene == null:
			continue
		var enemy = enemy_scene.instantiate()
		add_child(enemy)
		enemy.configure(spawn_tile, tile_size, self)

func _on_enemy_phase(action_speed: float) -> void:
	run_enemy_turns(action_speed)

# All enemies move simultaneously at the same speed as the player's action.
# tile_position is updated before any tween starts so occupancy is consistent.
func run_enemy_turns(move_duration: float = 0.07) -> void:
	if _player == null:
		_player = get_node_or_null("../Player")
	if _dungeon_map == null:
		_dungeon_map = get_node_or_null("../TileMapLayer")
	if _player == null or _dungeon_map == null:
		return

	var player_tile := _player_tile()
	for child in get_children():
		if not is_instance_valid(child):
			continue
		if child.is_queued_for_deletion():
			continue
		if not child.has_method("move_to_tile"):
			continue
		if not ("tile_position" in child):
			continue
		var next_tile := choose_enemy_destination(child, player_tile)
		child.tile_position = next_tile
		child.move_to_tile(next_tile, move_duration)

func is_tile_occupied_by_enemy(tile: Vector2i) -> bool:
	for child in get_children():
		if not is_instance_valid(child):
			continue
		if child.is_queued_for_deletion():
			continue
		if not ("tile_position" in child):
			continue
		if child.tile_position == tile:
			return true
	return false

func kill_enemy_at(tile: Vector2i) -> bool:
	for child in get_children():
		if not is_instance_valid(child):
			continue
		if child.is_queued_for_deletion():
			continue
		if not ("tile_position" in child):
			continue
		if child.tile_position == tile:
			remove_child(child)
			child.free()
			return true
	return false

func choose_enemy_destination(enemy: Sprite2D, player_tile: Vector2i) -> Vector2i:
	var start_tile: Vector2i = enemy.tile_position
	if start_tile == player_tile:
		return start_tile

	var path := _find_path(start_tile, player_tile, enemy)
	if path.size() >= 2 and path.size() - 1 <= CHASE_DISTANCE:
		var next_step: Vector2i = path[1]
		# Adjacent to player — skip turn (no attack yet)
		if next_step == player_tile:
			return start_tile
		return next_step

	if _rng.randi_range(0, 99) >= WANDER_CHANCE:
		return start_tile

	var valid_moves: Array[Vector2i] = []
	for direction in CARDINAL_DIRECTIONS:
		var candidate: Vector2i = start_tile + direction
		if _can_enemy_step(candidate, enemy):
			valid_moves.append(candidate)
	if valid_moves.is_empty():
		return start_tile
	return valid_moves[_rng.randi_range(0, valid_moves.size() - 1)]

func _find_path(start_tile: Vector2i, goal_tile: Vector2i, moving_enemy: Sprite2D) -> Array[Vector2i]:
	var frontier: Array[Vector2i] = [start_tile]
	var came_from: Dictionary = {start_tile: start_tile}
	var found := false

	while frontier.size() > 0:
		var current: Vector2i = frontier.pop_front()
		if current == goal_tile:
			found = true
			break
		for direction in CARDINAL_DIRECTIONS:
			var next: Vector2i = current + direction
			if came_from.has(next):
				continue
			if next != goal_tile and not _can_enemy_step(next, moving_enemy):
				continue
			came_from[next] = current
			frontier.append(next)

	if not found:
		return [start_tile]

	var path: Array[Vector2i] = [goal_tile]
	var cursor := goal_tile
	while cursor != start_tile:
		cursor = came_from[cursor]
		path.push_front(cursor)
	return path

func _can_enemy_step(tile: Vector2i, moving_enemy: Sprite2D) -> bool:
	if _dungeon_map == null or not _dungeon_map.is_walkable_tile(tile):
		return false
	if tile == _player_tile():
		return false
	for child in get_children():
		if not is_instance_valid(child):
			continue
		if child.is_queued_for_deletion():
			continue
		if not ("tile_position" in child):
			continue
		if child == moving_enemy:
			continue
		if child.tile_position == tile:
			return false
	return true

func _player_tile() -> Vector2i:
	if _player == null:
		return Vector2i.ZERO
	var half := Vector2(_dungeon_map.tile_size / 2.0, _dungeon_map.tile_size / 2.0)
	return Vector2i(
		roundi((_player.position.x - half.x) / _dungeon_map.tile_size),
		roundi((_player.position.y - half.y) / _dungeon_map.tile_size)
	)
