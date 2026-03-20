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
@export var fix_dead_end_validation_error: bool = true
@export var fix_generate_outer_rooms_floor_error: bool = true

# ─── Scene References (resolved at _ready) ───
@onready var player_node: AnimatedSprite2D = get_node_or_null("../Player")
@onready var enemy_manager: Node2D = get_node_or_null("../EnemyManager")
@onready var vision_overlay: Node2D = get_node_or_null("../VisionOverlay")
@onready var minimap_node: Control = get_node_or_null("../CanvasLayer/Minimap")
@onready var floor_label: Label = get_node_or_null("../CanvasLayer/FloorLabel")
@onready var seed_label: Label = get_node_or_null("../CanvasLayer/SeedLabel")
@onready var turn_manager: Node = get_node_or_null("../TurnManager")
@onready var floor_transition: Node = get_node_or_null("../FloorTransition")

# TileSet source IDs
const TILE_SOURCE_AUTOTILE := 0
const TILE_SOURCE_STAIRS := 1
const WALL_COL_OFFSET := 0
const WATER_COL_OFFSET := 6
const FLOOR_COL_OFFSET := 12

var tile_type_map: Dictionary = {}
var room_index_map: Dictionary = {}
var _algorithm: DungeonAlgorithm
var _gen_info: DungeonData.DungeonGenerationInfo
var _current_floor: int = 1
var _current_seed: int = 0
var _run_seed: int = 0
var _floor_seeds: Array[int] = []
var _has_custom_seed: bool = false

const _AutotileData := preload("res://scripts/dungeon/generation/autotile_data.gd")

func _ready() -> void:
	_apply_game_settings()
	_setup_tileset()
	_current_floor = dungeon_floor
	if _has_custom_seed:
		_run_seed = _current_seed
	else:
		_run_seed = randi()
	_generate_floor_seeds()
	_prevalidate_all_floors()
	generate_dungeon()
	if player_node:
		player_node.stepped_on_stairs.connect(_on_player_stepped_on_stairs)
	var audio = get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_dungeon_music()

func _generate_floor_seeds() -> void:
	_floor_seeds.clear()
	seed(_run_seed)
	for i in range(_max_floor()):
		_floor_seeds.append(randi())

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
	_current_seed = _floor_seeds[_current_floor - 1]
	seed(_current_seed)
	tile_type_map.clear()
	room_index_map.clear()
	clear()
	if turn_manager:
		turn_manager.reset()

	var params := _build_generation_params(_current_seed)

	_algorithm = DungeonAlgorithm.new()
	var tiles: Array = _algorithm.generate_dungeon(params.fp, params.dd, params.gc, params.adv)
	_gen_info = _algorithm.get_generation_info()

	var enemy_spawn_tiles := _collect_enemy_spawns(tiles)
	_render_tiles(tiles)
	_spawn_player()
	_spawn_enemies(enemy_spawn_tiles)

	if minimap_node:
		minimap_node.reset()
	if vision_overlay:
		vision_overlay.refresh()
	if floor_label:
		floor_label.text = "%dF/%dF" % [_current_floor, _max_floor()]
	if seed_label:
		seed_label.text = "Seed: %d" % _run_seed

func _build_generation_params(gen_seed: int) -> Dictionary:
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
	fp.generation_seed = gen_seed
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

	return {"fp": fp, "dd": dd, "gc": gc, "adv": adv}

func _prevalidate_all_floors() -> void:
	var max_f := _max_floor()
	for f in range(1, max_f + 1):
		var f_seed := _floor_seeds[f - 1]
		seed(f_seed)
		var params := _build_generation_params(f_seed)
		var algo := DungeonAlgorithm.new()
		var tiles: Array = algo.generate_dungeon(params.fp, params.dd, params.gc, params.adv)
		var info := algo.get_generation_info()
		# Validate tiles array
		if tiles.is_empty() or tiles.size() != DungeonData.FLOOR_MAX_X:
			push_error("  Floor %d: INVALID tiles (size=%d, expected=%d)" % [f, tiles.size(), DungeonData.FLOOR_MAX_X])
			continue
		# Validate stairs spawn
		var has_stairs := false
		for x in range(DungeonData.FLOOR_MAX_X):
			for y in range(DungeonData.FLOOR_MAX_Y):
				if tiles[x][y].spawn_or_visibility_flags.f_stairs:
					has_stairs = true
					break
			if has_stairs:
				break
		if not has_stairs and f < max_f:
			push_warning("  Floor %d: No stairs found!" % f)
		# Validate player spawn
		if info.player_spawn_x < 0 or info.player_spawn_y < 0:
			push_warning("  Floor %d: Invalid player spawn (%d, %d)" % [f, info.player_spawn_x, info.player_spawn_y])


func _setup_tileset() -> void:
	# Clear existing TileSet sources and set up autotile atlas from tileset_0.png
	while tile_set.get_source_count() > 0:
		tile_set.remove_source(tile_set.get_source_id(0))

	var tileset_tex := preload("res://sprites/dungeon/tileset_0.png")
	var atlas := TileSetAtlasSource.new()
	atlas.texture = tileset_tex
	atlas.texture_region_size = Vector2i(24, 24)
	for col in range(18):
		for row in range(8):
			atlas.create_tile(Vector2i(col, row))
	tile_set.add_source(atlas, TILE_SOURCE_AUTOTILE)

	var stairs_tex := preload("res://sprites/tiles/stairs.png")
	var stairs_atlas := TileSetAtlasSource.new()
	stairs_atlas.texture = stairs_tex
	stairs_atlas.texture_region_size = Vector2i(24, 24)
	stairs_atlas.create_tile(Vector2i(0, 0))
	tile_set.add_source(stairs_atlas, TILE_SOURCE_STAIRS)

func _render_tiles(tiles: Array) -> void:
	# First pass: classify all tiles
	for x in range(DungeonData.FLOOR_MAX_X):
		for y in range(DungeonData.FLOOR_MAX_Y):
			var coords := Vector2i(x, y)
			var tile: DungeonData.Tile = tiles[x][y]
			match tile.terrain_flags.terrain_type:
				DungeonData.TerrainType.TERRAIN_NORMAL:
					if tile.spawn_or_visibility_flags.f_stairs:
						tile_type_map[coords] = "stairs"
					else:
						tile_type_map[coords] = "room" if tile.room_index < 0xF0 else "hallway"
					room_index_map[coords] = tile.room_index
				DungeonData.TerrainType.TERRAIN_SECONDARY:
					tile_type_map[coords] = "water"
				DungeonData.TerrainType.TERRAIN_CHASM, DungeonData.TerrainType.TERRAIN_WALL:
					tile_type_map[coords] = "wall"

	# Second pass: render with autotile lookup
	for x in range(DungeonData.FLOOR_MAX_X):
		for y in range(DungeonData.FLOOR_MAX_Y):
			var coords := Vector2i(x, y)
			var tt: String = tile_type_map.get(coords, "wall")
			match tt:
				"room", "hallway":
					var ac := _autotile_lookup(x, y, "floor")
					set_cell(coords, TILE_SOURCE_AUTOTILE, ac + Vector2i(FLOOR_COL_OFFSET, 0))
				"stairs":
					set_cell(coords, TILE_SOURCE_STAIRS, Vector2i(0, 0))
				"water":
					var ac := _autotile_lookup(x, y, "water")
					set_cell(coords, TILE_SOURCE_AUTOTILE, ac + Vector2i(WATER_COL_OFFSET, 0))
				"wall":
					var ac := _autotile_lookup(x, y, "wall")
					set_cell(coords, TILE_SOURCE_AUTOTILE, ac + Vector2i(WALL_COL_OFFSET, 0))

func _autotile_lookup(x: int, y: int, group: String) -> Vector2i:
	var id := ""
	for j in range(y - 1, y + 2):
		for i in range(x - 1, x + 2):
			var cx := clampi(i, 0, DungeonData.FLOOR_MAX_X - 1)
			var cy := clampi(j, 0, DungeonData.FLOOR_MAX_Y - 1)
			var tt: String = tile_type_map.get(Vector2i(cx, cy), "wall")
			var matches: bool
			match group:
				"floor":
					matches = (tt == "room" or tt == "hallway" or tt == "stairs")
				"water":
					matches = (tt == "water")
				_:
					matches = (tt == "wall")
			id += "1" if matches else "0"
	return _AutotileData.MAP.get(id, _AutotileData.DEFAULT)

func _spawn_player() -> void:
	if player_node == null:
		return

	var px: int = _gen_info.player_spawn_x
	var py: int = _gen_info.player_spawn_y

	if px < 0 or py < 0:
		for x in range(DungeonData.FLOOR_MAX_X):
			for y in range(DungeonData.FLOOR_MAX_Y):
				if is_walkable_tile(Vector2i(x, y)):
					px = x; py = y
					break
			if px >= 0:
				break

	player_node.position = Vector2(px, py) * tile_size + Vector2(tile_size / 2.0, tile_size / 2.0)
	if "tile_position" in player_node:
		player_node.tile_position = Vector2i(px, py)
	if player_node.has_method("_update_z_order"):
		player_node._update_z_order()

	var camera = player_node.get_node_or_null("Camera2D")
	if camera:
		camera.limit_left = 0
		camera.limit_top = 0
		camera.limit_right = DungeonData.FLOOR_MAX_X * tile_size
		camera.limit_bottom = DungeonData.FLOOR_MAX_Y * tile_size

func _collect_enemy_spawns(tiles: Array) -> Array[Vector2i]:
	var spawns: Array[Vector2i] = []
	for x in range(DungeonData.FLOOR_MAX_X):
		for y in range(DungeonData.FLOOR_MAX_Y):
			if tiles[x][y].spawn_or_visibility_flags.f_monster:
				spawns.append(Vector2i(x, y))
	return spawns

func _spawn_enemies(spawn_tiles: Array[Vector2i]) -> void:
	if enemy_manager == null or player_node == null:
		return
	var player_tile: Vector2i = player_node.tile_position
	enemy_manager.reset_enemies(spawn_tiles, tile_size, _current_seed, player_tile)

func get_tile_type(coords: Vector2i) -> String:
	return tile_type_map.get(coords, "wall")

func get_room_index(coords: Vector2i) -> int:
	return room_index_map.get(coords, 0xFF)

func is_walkable_tile(coords: Vector2i) -> bool:
	var tt: String = tile_type_map.get(coords, "wall")
	return tt == "room" or tt == "hallway" or tt == "stairs"

func _on_player_stepped_on_stairs() -> void:
	if not floor_transition or floor_transition.is_transitioning:
		return
	floor_transition.start()
	await floor_transition.mid_transition
	if _is_last_floor():
		await get_tree().create_timer(0.3).timeout
		_finish_dungeon()
		return
	_advance_floor()
	floor_transition.finish()

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
	var audio = get_node_or_null("/root/AudioManager")
	if audio:
		audio.stop_music(0.0)
	get_tree().change_scene_to_file(menu_scene_path)
