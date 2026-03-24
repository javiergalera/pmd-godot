extends Node3D
## 3D dungeon renderer: generates floor/wall meshes from DungeonAlgorithm output.
## Equivalent of dungeon_generator.gd (2D TileMapLayer) but using MeshInstance3D.

@export var tile_size: float = 2.0
@export var wall_height: float = 1.5
@export var menu_scene_path: String = "res://scenes/start_menu.tscn"

# ─── Floor Properties ───
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

@onready var player_node = get_node_or_null("../Player3D")
@onready var enemy_manager = get_node_or_null("../EnemyManager3D")
@onready var minimap_node: Control = get_node_or_null("../CanvasLayer/Minimap")
@onready var floor_label: Label = get_node_or_null("../CanvasLayer/FloorLabel")
@onready var seed_label: Label = get_node_or_null("../CanvasLayer/SeedLabel")
@onready var turn_manager: Node = get_node_or_null("../TurnManager")
@onready var floor_transition: Node = get_node_or_null("../FloorTransition")
@onready var vision_overlay: Node3D = get_node_or_null("../VisionOverlay3D")

var tile_type_map: Dictionary = {}
var room_index_map: Dictionary = {}
var _algorithm: DungeonAlgorithm
var _gen_info: DungeonData.DungeonGenerationInfo
var _current_floor: int = 1
var _current_seed: int = 0
var _run_seed: int = 0
var _floor_seeds: Array[int] = []
var _has_custom_seed: bool = false

var _floor_mat: StandardMaterial3D
var _wall_mat: StandardMaterial3D
var _water_mat: StandardMaterial3D
var _stairs_mat: StandardMaterial3D
var _stairs_mesh: Mesh
var _tiles_parent: Node3D

func _ready() -> void:
	_create_materials()
	_stairs_mesh = load("res://resources/Stairs/ev_stairs_down.obj") as Mesh
	_apply_game_settings()
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

func _create_materials() -> void:
	_floor_mat = StandardMaterial3D.new()
	_floor_mat.albedo_color = Color(0.55, 0.5, 0.4)
	_floor_mat.roughness = 0.9

	_wall_mat = StandardMaterial3D.new()
	_wall_mat.albedo_color = Color(0.3, 0.28, 0.25)
	_wall_mat.roughness = 0.95

	_water_mat = StandardMaterial3D.new()
	_water_mat.albedo_color = Color(0.2, 0.35, 0.65)
	_water_mat.roughness = 0.3
	_water_mat.metallic = 0.1

	_stairs_mat = StandardMaterial3D.new()
	_stairs_mat.albedo_color = Color(0.9, 0.85, 0.3)
	_stairs_mat.roughness = 0.7
	_stairs_mat.emission_enabled = true
	_stairs_mat.emission = Color(0.9, 0.85, 0.3)
	_stairs_mat.emission_energy_multiplier = 0.3

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
	dungeon_floor = 1
	floor_number = 1
	n_floors_plus_one = total_floors_cfg + 1
	room_density = clampi(int(settings.room_density), 0, 16)
	irregular_room_chance = clampi(int(settings.irregular_room_chance), 0, 100)
	floor_connectivity = clampi(int(settings.floor_connectivity), 0, 32)
	enemy_density = clampi(int(settings.enemy_density), 0, 32)
	item_density = clampi(int(settings.item_density), 0, 32)
	trap_density = clampi(int(settings.trap_density), 0, 32)
	room_obstacle_density = clampi(int(settings.room_obstacle_density), 0, 100)
	_has_custom_seed = bool(settings.has_custom_seed)
	if _has_custom_seed:
		_current_seed = int(settings.seed_value)

func generate_dungeon() -> void:
	_current_seed = _floor_seeds[_current_floor - 1]
	seed(_current_seed)
	tile_type_map.clear()
	room_index_map.clear()
	_clear_tiles()
	if turn_manager:
		turn_manager.reset()

	var params := _build_generation_params(_current_seed)
	_algorithm = DungeonAlgorithm.new()
	var tiles: Array = _algorithm.generate_dungeon(params.fp, params.dd, params.gc, params.adv)
	_gen_info = _algorithm.get_generation_info()

	var enemy_spawn_tiles := _collect_enemy_spawns(tiles)
	_classify_tiles(tiles)
	_build_meshes()
	_spawn_player()
	_spawn_enemies(enemy_spawn_tiles)

	if minimap_node and minimap_node.has_method("reset"):
		minimap_node.reset()
	if floor_label:
		floor_label.text = "%dF/%dF" % [_current_floor, _max_floor()]
	if seed_label:
		seed_label.text = "Seed: %d" % _run_seed
	if vision_overlay and vision_overlay.has_method("refresh"):
		vision_overlay.refresh()

func _clear_tiles() -> void:
	if _tiles_parent and is_instance_valid(_tiles_parent):
		_tiles_parent.queue_free()
	_tiles_parent = Node3D.new()
	_tiles_parent.name = "Tiles"
	add_child(_tiles_parent)

func _classify_tiles(tiles: Array) -> void:
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

func _build_meshes() -> void:
	# Use batched MultiMesh for floor, water, stairs (all flat quads)
	# Walls get boxes
	var floor_transforms: Array[Transform3D] = []
	var wall_transforms: Array[Transform3D] = []
	var water_transforms: Array[Transform3D] = []
	var stairs_transforms: Array[Transform3D] = []

	for x in range(DungeonData.FLOOR_MAX_X):
		for y in range(DungeonData.FLOOR_MAX_Y):
			var tt: String = tile_type_map.get(Vector2i(x, y), "wall")
			var pos := Vector3(x * tile_size + tile_size * 0.5, 0.0, y * tile_size + tile_size * 0.5)
			match tt:
				"room", "hallway":
					floor_transforms.append(Transform3D(Basis(), pos))
				"stairs":
					floor_transforms.append(Transform3D(Basis(), pos))
					stairs_transforms.append(Transform3D(Basis(), pos))
				"water":
					water_transforms.append(Transform3D(Basis(), pos + Vector3(0, -0.05, 0)))
				"wall":
					wall_transforms.append(Transform3D(Basis(), pos + Vector3(0, wall_height * 0.5, 0)))

	_create_multimesh("FloorMesh", _make_floor_quad(), _floor_mat, floor_transforms)
	_create_multimesh("WaterMesh", _make_floor_quad(), _water_mat, water_transforms)
	_create_multimesh("WallMesh", _make_wall_box(), _wall_mat, wall_transforms)
	_spawn_stairs_models(stairs_transforms)

func _is_wall_visible(x: int, y: int) -> bool:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx := x + dx
			var ny := y + dy
			if nx < 0 or nx >= DungeonData.FLOOR_MAX_X or ny < 0 or ny >= DungeonData.FLOOR_MAX_Y:
				continue
			var tt: String = tile_type_map.get(Vector2i(nx, ny), "wall")
			if tt != "wall":
				return true
	return false

func _make_floor_quad() -> Mesh:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(tile_size, tile_size)
	return mesh

func _make_wall_box() -> Mesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(tile_size, wall_height, tile_size)
	return mesh

func _spawn_stairs_models(transforms: Array[Transform3D]) -> void:
	if _stairs_mesh == null:
		_create_multimesh("StairsMesh", _make_floor_quad(), _stairs_mat, transforms)
		return
	# OBJ spans roughly -0.42..+0.42 (~0.84 units). Scale to ~80% of tile.
	var stairs_scale_factor: float = (tile_size * 0.8) / 0.84
	for t in transforms:
		var mi := MeshInstance3D.new()
		mi.mesh = _stairs_mesh
		mi.position = t.origin + Vector3(0, 0.01, 0)
		mi.scale = Vector3(stairs_scale_factor, stairs_scale_factor, stairs_scale_factor)
		_tiles_parent.add_child(mi)

func _create_multimesh(mesh_name: String, mesh: Mesh, mat: Material, transforms: Array[Transform3D]) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.name = mesh_name
	mmi.multimesh = mm
	mmi.material_override = mat
	_tiles_parent.add_child(mmi)

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
		if tiles.is_empty() or tiles.size() != DungeonData.FLOOR_MAX_X:
			push_error("  Floor %d: INVALID tiles" % f)
			continue
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
		if info.player_spawn_x < 0 or info.player_spawn_y < 0:
			push_warning("  Floor %d: Invalid player spawn" % f)

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
	player_node.tile_size = tile_size
	player_node.tile_position = Vector2i(px, py)
	player_node.position = Vector3(px * tile_size + tile_size * 0.5, 0.5, py * tile_size + tile_size * 0.5)

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
