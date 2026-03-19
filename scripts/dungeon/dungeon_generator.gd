extends TileMapLayer
## TileMapLayer integration for dungeon-mystery algorithm (PMD:EoS).
## Uses DungeonAlgorithm + DungeonData to generate floors, then renders to TileMapLayer.

@export var tile_size: int = 24
@export var menu_scene_path: String = "res://scenes/start_menu.tscn"

# ─── Floor Properties (exported for inspector tweaking) ───
@export_group("Floor Properties")
@export var layout: int = 0
@export var room_density: int = 6
@export var irregular_room_chance: int = 35
@export var floor_connectivity: int = 15
@export var enemy_density: int = 10
@export var kecleon_shop_chance: int = 20
@export var monster_house_chance: int = 20
@export var maze_room_chance: int = 0
@export var allow_dead_ends: bool = false
@export var secondary_structures_budget: int = 0
@export var item_density: int = 5
@export var trap_density: int = 5
@export var floor_number: int = 0
@export var fixed_room_id: int = 0
@export var num_extra_hallways: int = 10
@export var buried_item_density: int = 0
@export var secondary_terrain_density: int = 5
@export var itemless_monster_house_chance: int = 0
@export var hidden_stairs_type: int = 0
@export var hidden_stairs_spawn_chance: int = 0
@export var f_room_imperfections: bool = false
@export var f_secondary_terrain_generation: bool = true
@export var room_obstacle_density: int = 8

@export_group("Dungeon Data")
@export var dungeon_id: int = 1
@export var dungeon_floor: int = 1
@export var rescue_floor: int = 1
@export var nonstory_flag: bool = true
@export var dungeon_objective: int = 0
@export var guaranteed_item_id: int = 0
@export var n_floors_plus_one: int = 4

@export_group("Generation Constants")
@export var merge_rooms_chance: int = 5
@export var no_imperfections_chance: int = 60
@export var secondary_structure_flag_chance: int = 80
@export var max_number_monster_house_item_spawns: int = 7
@export var max_number_monster_house_enemy_spawns: int = 30
@export var first_dungeon_id_allow_monster_house_traps: int = 28

@export_group("Advanced Settings")
@export var allow_wall_maze_room_generation: bool = false
@export var fix_dead_end_validation_error: bool = false
@export var fix_generate_outer_rooms_floor_error: bool = false

# TileSet source IDs
const TILE_SOURCE_FLOOR := 0
const TILE_SOURCE_WALL := 1
const TILE_SOURCE_WATER := 2
const TILE_SOURCE_STAIRS := 3

var tile_type_map: Dictionary = {}
var _algorithm: DungeonAlgorithm
var _gen_info: DungeonData.DungeonGenerationInfo
var _current_floor: int = 1
var _current_seed: int = 0
var _run_seed: int = 0
var _has_custom_seed: bool = false
var _transitioning: bool = false

func _ready() -> void:
	_apply_game_settings()
	_current_floor = dungeon_floor
	if _has_custom_seed:
		_run_seed = _current_seed
	else:
		_run_seed = randi()
	generate_dungeon()
	var player = get_node_or_null("../Player")
	if player:
		player.stepped_on_stairs.connect(_on_player_stepped_on_stairs)

func _apply_game_settings() -> void:
	var settings = get_node_or_null("/root/GameSettings")
	if settings == null:
		return

	var total_floors_cfg: int = maxi(int(settings.total_floors), 1)
	var room_density_cfg: int = clampi(int(settings.room_density), 0, 16)
	var irregular_room_chance_cfg: int = clampi(int(settings.irregular_room_chance), 0, 100)
	var floor_connectivity_cfg: int = clampi(int(settings.floor_connectivity), 0, 32)
	var enemy_density_cfg: int = clampi(int(settings.enemy_density), 0, 32)
	var item_density_cfg: int = clampi(int(settings.item_density), 0, 32)
	var trap_density_cfg: int = clampi(int(settings.trap_density), 0, 32)
	var room_obstacle_density_cfg: int = clampi(int(settings.room_obstacle_density), 0, 100)

	dungeon_floor = 1
	floor_number = 1
	n_floors_plus_one = total_floors_cfg + 1
	room_density = room_density_cfg
	irregular_room_chance = irregular_room_chance_cfg
	floor_connectivity = floor_connectivity_cfg
	enemy_density = enemy_density_cfg
	item_density = item_density_cfg
	trap_density = trap_density_cfg
	room_obstacle_density = room_obstacle_density_cfg

	_has_custom_seed = bool(settings.has_custom_seed)
	if _has_custom_seed:
		_current_seed = int(settings.seed_value)

func generate_dungeon() -> void:
	_current_seed = _run_seed + (_current_floor - 1)
	seed(_current_seed)
	tile_type_map.clear()
	clear()
	TurnManager.reset()

	var fp := DungeonData.FloorProperties.new()
	fp.layout = layout
	fp.room_density = room_density
	fp.irregular_room_chance = irregular_room_chance
	fp.floor_connectivity = floor_connectivity
	fp.enemy_density = enemy_density
	fp.kecleon_shop_chance = kecleon_shop_chance
	fp.monster_house_chance = monster_house_chance
	fp.maze_room_chance = maze_room_chance
	fp.allow_dead_ends = allow_dead_ends
	fp.secondary_structures_budget = secondary_structures_budget
	fp.item_density = item_density
	fp.trap_density = trap_density
	fp.floor_number = floor_number
	fp.fixed_room_id = fixed_room_id
	fp.num_extra_hallways = num_extra_hallways
	fp.buried_item_density = buried_item_density
	fp.secondary_terrain_density = secondary_terrain_density
	fp.itemless_monster_house_chance = itemless_monster_house_chance
	fp.hidden_stairs_type = hidden_stairs_type
	fp.hidden_stairs_spawn_chance = hidden_stairs_spawn_chance
	fp.room_obstacle_density = room_obstacle_density
	fp.generation_seed = _current_seed
	fp.room_flags.f_room_imperfections = f_room_imperfections
	fp.room_flags.f_secondary_terrain_generation = f_secondary_terrain_generation

	var dd := DungeonData.Dungeon.new()
	dd.id = dungeon_id
	dd.dungeon_floor = dungeon_floor
	dd.rescue_floor = rescue_floor
	dd.nonstory_flag = nonstory_flag
	dd.dungeon_objective = dungeon_objective
	dd.guaranteed_item_id = guaranteed_item_id
	dd.n_floors_plus_one = n_floors_plus_one

	var gc := DungeonData.GenerationConstants.new()
	gc.merge_rooms_chance = merge_rooms_chance
	gc.no_imperfections_chance = no_imperfections_chance
	gc.secondary_structure_flag_chance = secondary_structure_flag_chance
	gc.max_number_monster_house_item_spawns = max_number_monster_house_item_spawns
	gc.max_number_monster_house_enemy_spawns = max_number_monster_house_enemy_spawns
	gc.first_dungeon_id_allow_monster_house_traps = first_dungeon_id_allow_monster_house_traps

	var adv := DungeonData.AdvancedGenerationSettings.new()
	adv.allow_wall_maze_room_generation = allow_wall_maze_room_generation
	adv.fix_dead_end_validation_error = fix_dead_end_validation_error
	adv.fix_generate_outer_rooms_floor_error = fix_generate_outer_rooms_floor_error

	_algorithm = DungeonAlgorithm.new()
	var tiles: Array = _algorithm.generate_dungeon(fp, dd, gc, adv)
	_gen_info = _algorithm.get_generation_info()

	var enemy_spawn_tiles := _collect_enemy_spawns(tiles)
	_render_tiles(tiles)
	_refresh_tile_overlay()
	_spawn_player()
	_spawn_enemies(enemy_spawn_tiles)

	var minimap = get_node_or_null("../CanvasLayer/Minimap")
	if minimap:
		minimap.reset()

	var floor_label = get_node_or_null("../CanvasLayer/FloorLabel")
	if floor_label:
		floor_label.text = "%dF/%dF" % [_current_floor, _max_floor()]

	var seed_label = get_node_or_null("../CanvasLayer/SeedLabel")
	if seed_label:
		seed_label.text = "Seed: %d" % _current_seed


func _render_tiles(tiles: Array) -> void:
	for x in range(DungeonData.FLOOR_MAX_X):
		for y in range(DungeonData.FLOOR_MAX_Y):
			var coords := Vector2i(x, y)
			var tile: DungeonData.Tile = tiles[x][y]

			match tile.terrain_flags.terrain_type:
				DungeonData.TerrainType.TERRAIN_NORMAL:
					if tile.spawn_or_visibility_flags.f_stairs:
						set_cell(coords, TILE_SOURCE_STAIRS, Vector2i(0, 0))
						tile_type_map[coords] = "stairs"
					else:
						set_cell(coords, TILE_SOURCE_FLOOR, Vector2i(0, 0))
						if tile.room_index < 0xF0:
							tile_type_map[coords] = "room"
						else:
							tile_type_map[coords] = "hallway"
				DungeonData.TerrainType.TERRAIN_SECONDARY:
					set_cell(coords, TILE_SOURCE_WATER, Vector2i(0, 0))
					tile_type_map[coords] = "water"
				DungeonData.TerrainType.TERRAIN_CHASM:
					set_cell(coords, TILE_SOURCE_WALL, Vector2i(0, 0))
					tile_type_map[coords] = "wall"
				DungeonData.TerrainType.TERRAIN_WALL:
					set_cell(coords, TILE_SOURCE_WALL, Vector2i(0, 0))
					tile_type_map[coords] = "wall"

func _spawn_player() -> void:
	var player = get_node_or_null("../Player")
	if player == null:
		return

	var px: int = _gen_info.player_spawn_x
	var py: int = _gen_info.player_spawn_y

	if px < 0 or py < 0:
		# Fallback: find any walkable tile
		for x in range(DungeonData.FLOOR_MAX_X):
			for y in range(DungeonData.FLOOR_MAX_Y):
				if is_walkable_tile(Vector2i(x, y)):
					px = x; py = y
					break
			if px >= 0:
				break

	player.position = Vector2(px, py) * tile_size + Vector2(tile_size / 2.0, tile_size / 2.0)

	var camera = player.get_node_or_null("Camera2D")
	if camera:
		camera.limit_left = 0
		camera.limit_top = 0
		camera.limit_right = DungeonData.FLOOR_MAX_X * tile_size
		camera.limit_bottom = DungeonData.FLOOR_MAX_Y * tile_size

func _refresh_tile_overlay() -> void:
	var overlay = get_node_or_null("../TileOverlay")
	if overlay and overlay.has_method("refresh"):
		overlay.tile_size = tile_size
		overlay.refresh()

func _collect_enemy_spawns(tiles: Array) -> Array[Vector2i]:
	var spawns: Array[Vector2i] = []
	for x in range(DungeonData.FLOOR_MAX_X):
		for y in range(DungeonData.FLOOR_MAX_Y):
			if tiles[x][y].spawn_or_visibility_flags.f_monster:
				spawns.append(Vector2i(x, y))
	return spawns

func _spawn_enemies(spawn_tiles: Array[Vector2i]) -> void:
	var enemy_manager = get_node_or_null("../EnemyManager")
	var player = get_node_or_null("../Player")
	if enemy_manager == null or player == null or not enemy_manager.has_method("reset_enemies"):
		return

	var player_tile := Vector2i(
		roundi((player.position.x - tile_size / 2.0) / tile_size),
		roundi((player.position.y - tile_size / 2.0) / tile_size)
	)
	enemy_manager.reset_enemies(spawn_tiles, tile_size, _current_seed, player_tile)

func get_tile_type(coords: Vector2i) -> String:
	return tile_type_map.get(coords, "wall")

func is_walkable_tile(coords: Vector2i) -> bool:
	var tt: String = tile_type_map.get(coords, "wall")
	return tt == "room" or tt == "hallway" or tt == "stairs"

func _on_player_stepped_on_stairs() -> void:
	if _transitioning:
		return
	_transitioning = true

	var player = get_node_or_null("../Player")
	if player:
		player.is_frozen = true
		player.is_moving = false
		if "_dash_active" in player:
			player._dash_active = false
			player._dash_dir = Vector2i.ZERO

	var fade_rect = get_node_or_null("../CanvasLayer/FadeRect")
	if not fade_rect:
		_transitioning = false
		return

	var tween_in := create_tween()
	tween_in.tween_property(fade_rect, "color:a", 1.0, 0.5)
	await tween_in.finished

	if _is_last_floor():
		await get_tree().create_timer(0.3).timeout
		_transitioning = false
		_finish_dungeon()
		return

	_advance_floor()

	await get_tree().create_timer(0.3).timeout

	var tween_out := create_tween()
	tween_out.tween_property(fade_rect, "color:a", 0.0, 0.5)
	await tween_out.finished

	if player and is_instance_valid(player):
		player.is_frozen = false
	_transitioning = false

func _advance_floor() -> void:
	_current_floor += 1
	dungeon_floor = _current_floor
	floor_number = _current_floor
	generate_dungeon()

func _max_floor() -> int:
	return maxi(1, n_floors_plus_one - 1)

func _is_last_floor() -> bool:
	return _current_floor >= _max_floor()

func _finish_dungeon() -> void:
	get_tree().change_scene_to_file(menu_scene_path)
