extends TileMapLayer
## TileMapLayer integration for dungeon-mystery algorithm (PMD:EoS).
## Uses DungeonAlgorithm + DungeonData to generate floors, then renders to TileMapLayer.

@export var tile_size: int = 24

# ─── Floor Properties (exported for inspector tweaking) ───
@export_group("Floor Properties")
@export var layout: int = 0
@export var room_density: int = 6
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

func _ready() -> void:
	_current_floor = dungeon_floor
	generate_dungeon()
	var player = get_node_or_null("../Player")
	if player:
		player.stepped_on_stairs.connect(_on_player_stepped_on_stairs)

func generate_dungeon() -> void:
	_current_seed = randi()
	seed(_current_seed)
	tile_type_map.clear()
	clear()

	var fp := DungeonData.FloorProperties.new()
	fp.layout = layout
	fp.room_density = room_density
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

	_render_tiles(tiles)
	_spawn_player()

	var minimap = get_node_or_null("../CanvasLayer/Minimap")
	if minimap:
		minimap.reset()

	var floor_label = get_node_or_null("../CanvasLayer/FloorLabel")
	if floor_label:
		floor_label.text = "%dF" % _current_floor

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

func get_tile_type(coords: Vector2i) -> String:
	return tile_type_map.get(coords, "wall")

func is_walkable_tile(coords: Vector2i) -> bool:
	var tt: String = tile_type_map.get(coords, "wall")
	return tt == "room" or tt == "hallway" or tt == "stairs"

func _on_player_stepped_on_stairs() -> void:
	var player = get_node_or_null("../Player")
	if player:
		player.is_frozen = true

	var fade_rect = get_node_or_null("../CanvasLayer/FadeRect")
	if not fade_rect:
		return

	# Fade to black
	var tween := create_tween()
	tween.tween_property(fade_rect, "color:a", 1.0, 0.5)
	tween.tween_callback(_advance_floor)
	tween.tween_interval(0.3)
	tween.tween_property(fade_rect, "color:a", 0.0, 0.5)
	tween.tween_callback(func() -> void:
		if player:
			player.is_frozen = false
	)

func _advance_floor() -> void:
	_current_floor += 1
	dungeon_floor = _current_floor
	floor_number = _current_floor
	generate_dungeon()
