class_name EnemyAI
extends RefCounted
## Shared enemy AI logic: BFS pathfinding, destination choosing, adjacency checks.
## Used by both 2D and 3D enemy managers to avoid code duplication.

const ALL_DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT,
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]
const WANDER_CHANCE := 35
const CHASE_DISTANCE := 12

var _rng := RandomNumberGenerator.new()

func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value

func randomize_rng() -> void:
	_rng.randomize()

## Decides the next tile for an enemy given the current dungeon state.
## Returns the tile the enemy should move to (or its current tile if it should stay).
func choose_destination(
	enemy_tile: Vector2i,
	player_tile: Vector2i,
	dungeon_map: Node,
	get_occupied_tiles: Callable,
	moving_enemy: Node,
) -> Vector2i:
	if enemy_tile == player_tile:
		return enemy_tile

	# Adjacent to player — stay put (attack range)
	var diff := player_tile - enemy_tile
	if absi(diff.x) <= 1 and absi(diff.y) <= 1 and diff != Vector2i.ZERO:
		if diff.x == 0 or diff.y == 0:
			return enemy_tile
		if dungeon_map.is_walkable_tile(enemy_tile + Vector2i(diff.x, 0)) and dungeon_map.is_walkable_tile(enemy_tile + Vector2i(0, diff.y)):
			return enemy_tile

	var path := _find_path(enemy_tile, player_tile, dungeon_map, get_occupied_tiles, moving_enemy)
	if path.size() >= 2 and path.size() - 1 <= CHASE_DISTANCE:
		var next_step: Vector2i = path[1]
		if next_step == player_tile:
			return enemy_tile
		return next_step

	if _rng.randi_range(0, 99) >= WANDER_CHANCE:
		return enemy_tile

	var valid_moves: Array[Vector2i] = []
	for direction in ALL_DIRECTIONS:
		var candidate: Vector2i = enemy_tile + direction
		if _can_step(enemy_tile, candidate, player_tile, dungeon_map, get_occupied_tiles, moving_enemy):
			valid_moves.append(candidate)
	if valid_moves.is_empty():
		return enemy_tile
	return valid_moves[_rng.randi_range(0, valid_moves.size() - 1)]

## BFS pathfinding from start to goal, respecting diagonal corner-cutting rules.
func _find_path(
	start_tile: Vector2i,
	goal_tile: Vector2i,
	dungeon_map: Node,
	get_occupied_tiles: Callable,
	moving_enemy: Node,
) -> Array[Vector2i]:
	var frontier: Array[Vector2i] = [start_tile]
	var frontier_idx: int = 0
	var came_from: Dictionary = {start_tile: start_tile}
	var found := false

	while frontier_idx < frontier.size():
		var current: Vector2i = frontier[frontier_idx]
		frontier_idx += 1
		if current == goal_tile:
			found = true
			break
		for direction in ALL_DIRECTIONS:
			var next: Vector2i = current + direction
			if came_from.has(next):
				continue
			if next == goal_tile:
				if direction.x != 0 and direction.y != 0:
					if not dungeon_map.is_walkable_tile(current + Vector2i(direction.x, 0)):
						continue
					if not dungeon_map.is_walkable_tile(current + Vector2i(0, direction.y)):
						continue
				came_from[next] = current
				frontier.append(next)
				continue
			if not _can_step(current, next, goal_tile, dungeon_map, get_occupied_tiles, moving_enemy):
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

## Checks if an enemy can step from origin to tile.
func _can_step(
	origin: Vector2i,
	tile: Vector2i,
	player_tile: Vector2i,
	dungeon_map: Node,
	get_occupied_tiles: Callable,
	moving_enemy: Node,
) -> bool:
	if not dungeon_map.is_walkable_tile(tile):
		return false
	if tile == player_tile:
		return false
	var diff := tile - origin
	if diff.x != 0 and diff.y != 0:
		if not dungeon_map.is_walkable_tile(origin + Vector2i(diff.x, 0)):
			return false
		if not dungeon_map.is_walkable_tile(origin + Vector2i(0, diff.y)):
			return false
	# Check other enemies via callback
	var occupied: Dictionary = get_occupied_tiles.call(moving_enemy)
	return not occupied.has(tile)

## Checks if enemy_tile is adjacent to player_tile (including diagonal if corners clear).
func is_adjacent_to_player(enemy_tile: Vector2i, player_tile: Vector2i, dungeon_map: Node) -> bool:
	var diff := player_tile - enemy_tile
	if absi(diff.x) > 1 or absi(diff.y) > 1 or diff == Vector2i.ZERO:
		return false
	if diff.x == 0 or diff.y == 0:
		return true
	return dungeon_map.is_walkable_tile(enemy_tile + Vector2i(diff.x, 0)) and dungeon_map.is_walkable_tile(enemy_tile + Vector2i(0, diff.y))
