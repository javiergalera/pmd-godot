class_name DungeonAlgorithm
extends RefCounted
## GDScript implementation of dungeon-mystery (PMD:EoS dungeon algorithm).
## Original: https://github.com/EpicYoshiMaster/dungeon-mystery (GPL-3.0)

# ─── Globals ───
var dungeon_d: DungeonData.Dungeon
var gen_info: DungeonData.DungeonGenerationInfo
var status: DungeonData.FloorGenerationStatus
var rng: DungeonRandom
var gen_constants: DungeonData.GenerationConstants
var adv_settings: DungeonData.AdvancedGenerationSettings
var grid_cell_start_x: Array = []
var grid_cell_start_y: Array = []
var _default_tile: DungeonData.Tile = DungeonData.Tile.new()

var generation_callback: Callable = Callable()
var callback_frequency: int = DungeonData.GenerationStepLevel.GEN_STEP_COMPLETE

# ─── Entry Point ───

func generate_dungeon(
	floor_props: DungeonData.FloorProperties,
	dungeon_data: DungeonData.Dungeon,
	generation_constants: DungeonData.GenerationConstants = null,
	advanced_generation_settings: DungeonData.AdvancedGenerationSettings = null,
	dungeon_generation_callback: Callable = Callable(),
	generation_callback_frequency: int = DungeonData.GenerationStepLevel.GEN_STEP_COMPLETE
) -> Array:
	dungeon_d = _deep_copy_dungeon(dungeon_data)
	gen_info = DungeonData.DungeonGenerationInfo.new()
	status = DungeonData.FloorGenerationStatus.new()
	rng = DungeonRandom.new(floor_props.generation_seed)

	gen_constants = generation_constants if generation_constants != null else DungeonData.GenerationConstants.new()
	adv_settings = advanced_generation_settings if advanced_generation_settings != null else DungeonData.AdvancedGenerationSettings.new()

	if dungeon_generation_callback.is_valid():
		generation_callback = dungeon_generation_callback

	callback_frequency = generation_callback_frequency

	return _generate_floor(floor_props)

func _deep_copy_dungeon(src: DungeonData.Dungeon) -> DungeonData.Dungeon:
	var d := DungeonData.Dungeon.new()
	d.id = src.id
	d.dungeon_floor = src.dungeon_floor
	d.rescue_floor = src.rescue_floor
	d.nonstory_flag = src.nonstory_flag
	var mi := DungeonData.MissionDestinationInfo.new()
	mi.is_destination_floor = src.mission_destination.is_destination_floor
	mi.mission_type = src.mission_destination.mission_type
	mi.mission_subtype = src.mission_destination.mission_subtype
	d.mission_destination = mi
	d.dungeon_objective = src.dungeon_objective
	d.guaranteed_item_id = src.guaranteed_item_id
	d.n_floors_plus_one = src.n_floors_plus_one
	d.active_traps = src.active_traps.duplicate()
	return d

# ─── Helpers ───

func _pos_is_out_of_bounds(x: int, y: int) -> bool:
	return x < 0 or x >= DungeonData.FLOOR_MAX_X or y < 0 or y >= DungeonData.FLOOR_MAX_Y

func _reset_floor() -> void:
	dungeon_d.list_tiles = []
	for x in range(DungeonData.FLOOR_MAX_X):
		var col: Array = []
		for y in range(DungeonData.FLOOR_MAX_Y):
			var t := DungeonData.Tile.new()
			if (
				_pos_is_out_of_bounds(x - 1, y) or _pos_is_out_of_bounds(x, y - 1) or
				_pos_is_out_of_bounds(x + 1, y) or _pos_is_out_of_bounds(x, y + 1) or
				_pos_is_out_of_bounds(x - 1, y - 1) or _pos_is_out_of_bounds(x - 1, y + 1) or
				_pos_is_out_of_bounds(x + 1, y - 1) or _pos_is_out_of_bounds(x + 1, y + 1)
			):
				t.terrain_flags.f_impassable_wall = true
			col.append(t)
		dungeon_d.list_tiles.append(col)

	gen_info.stairs_spawn_x = -1
	gen_info.stairs_spawn_y = -1

	dungeon_d.fixed_room_tiles = []
	for x in range(8):
		var col: Array = []
		for y in range(8):
			col.append(DungeonData.Tile.new())
		dungeon_d.fixed_room_tiles.append(col)

	dungeon_d.num_items = 0
	dungeon_d.active_traps = []
	dungeon_d.active_traps.resize(64)
	grid_cell_start_x = []
	grid_cell_start_y = []
	_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MAJOR, 0)

func _get_grid_positions(grid_size_x: int, grid_size_y: int) -> Dictionary:
	var sum_x := 0
	var sum_y := 0
	var list_x: Array = []
	var list_y: Array = []
	for x in range(grid_size_x + 1):
		list_x.append(sum_x)
		sum_x += int(float(DungeonData.FLOOR_MAX_X) / grid_size_x)
	for y in range(grid_size_y + 1):
		list_y.append(sum_y)
		sum_y += int(float(DungeonData.FLOOR_MAX_Y) / grid_size_y)
	return {"list_x": list_x, "list_y": list_y}

func _init_dungeon_grid(grid_size_x: int, grid_size_y: int) -> Array:
	var grid: Array = []
	for x in range(15):
		var col: Array = []
		for y in range(15):
			col.append(DungeonData.GridCell.new())
		grid.append(col)

	for x in range(grid_size_x):
		for y in range(grid_size_y):
			if status.floor_size == DungeonData.FloorSize.FLOOR_SIZE_SMALL and x >= int(float(grid_size_x) / 2):
				grid[x][y].is_invalid = true
			elif status.floor_size == DungeonData.FloorSize.FLOOR_SIZE_MEDIUM and x >= int(float(3 * grid_size_x) / 4):
				grid[x][y].is_invalid = true
			else:
				grid[x][y].is_invalid = false
			grid[x][y].is_room = true

	_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MAJOR, 1)
	return grid

# ─── AssignRooms ───

func _assign_rooms(grid: Array, grid_size_x: int, grid_size_y: int, number_of_rooms: int) -> void:
	var extra_rooms := rng.rand_int(3)
	var num_rooms := number_of_rooms

	if num_rooms < 0:
		num_rooms = -num_rooms
	else:
		num_rooms += extra_rooms

	var random_room_bits: Array = []
	random_room_bits.resize(256)
	random_room_bits.fill(false)
	for i in range(num_rooms):
		if i < 256:
			random_room_bits[i] = true

	var max_rooms := grid_size_x * grid_size_y
	for x in range(64):
		var a := rng.rand_int(max_rooms)
		var b := rng.rand_int(max_rooms)
		var tmp = random_room_bits[a]
		random_room_bits[a] = random_room_bits[b]
		random_room_bits[b] = tmp

	status.num_rooms = 0
	var odd_x := grid_size_x % 2
	var counter := 0

	for x in range(grid_size_x):
		for y in range(grid_size_y):
			if grid[x][y].is_invalid:
				counter += 1
				continue
			if status.num_rooms >= 32:
				grid[x][y].is_room = false
			if random_room_bits[counter]:
				grid[x][y].is_room = true
				status.num_rooms += 1
				if odd_x != 0 and y == 1 and x == int(float(grid_size_x - 1) / 2):
					grid[x][y].is_room = false
			else:
				grid[x][y].is_room = false
			counter += 1

	if status.num_rooms >= 2:
		return

	var attempts := 0
	var enough_rooms := false
	while attempts < 200 and not enough_rooms:
		for x in range(grid_size_x):
			for y in range(grid_size_y):
				if grid[x][y].is_invalid:
					continue
				if rng.rand_int(100) < 60:
					grid[x][y].is_room = true
					enough_rooms = true
					break
			if enough_rooms:
				break
		attempts += 1

	status.second_spawn = false

# ─── CreateRoomsAndAnchors ───

func _carve_room_tiles(grid_cell: DungeonData.GridCell, room_number: int, floor_props: DungeonData.FloorProperties) -> void:
	var width := grid_cell.end_x - grid_cell.start_x
	var height := grid_cell.end_y - grid_cell.start_y
	var use_irregular: bool = floor_props.irregular_room_chance > 0 and width >= 6 and height >= 6 and rng.rand_int(100) < floor_props.irregular_room_chance
	var shape_type := rng.rand_int(4) if use_irregular else -1

	for room_x in range(grid_cell.start_x, grid_cell.end_x):
		for room_y in range(grid_cell.start_y, grid_cell.end_y):
			if not _should_carve_room_tile(room_x, room_y, grid_cell, use_irregular, shape_type):
				continue
			dungeon_d.list_tiles[room_x][room_y].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_NORMAL
			dungeon_d.list_tiles[room_x][room_y].room_index = room_number

	var center_x: int = (grid_cell.start_x + grid_cell.end_x - 1) >> 1
	var center_y: int = (grid_cell.start_y + grid_cell.end_y - 1) >> 1
	dungeon_d.list_tiles[center_x][center_y].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_NORMAL
	dungeon_d.list_tiles[center_x][center_y].room_index = room_number

	_add_room_columns(grid_cell, room_number, floor_props.room_obstacle_density)

func _should_carve_room_tile(tile_x: int, tile_y: int, grid_cell: DungeonData.GridCell, use_irregular: bool, shape_type: int) -> bool:
	if not use_irregular:
		return true

	var width := float(grid_cell.end_x - grid_cell.start_x)
	var height := float(grid_cell.end_y - grid_cell.start_y)
	var center_x := float(grid_cell.start_x) + (width - 1.0) / 2.0
	var center_y := float(grid_cell.start_y) + (height - 1.0) / 2.0
	var radius_x := maxf((width - 1.0) / 2.0, 1.0)
	var radius_y := maxf((height - 1.0) / 2.0, 1.0)
	var dx := (float(tile_x) - center_x) / radius_x
	var dy := (float(tile_y) - center_y) / radius_y

	match shape_type:
		0:
			return dx * dx + dy * dy <= 1.05
		1:
			var squeezed_y := dy / 0.72
			return dx * dx + squeezed_y * squeezed_y <= 1.05
		2:
			var squeezed_x := dx / 0.72
			return squeezed_x * squeezed_x + dy * dy <= 1.05
		_:
			return absf(dx) + absf(dy) <= 1.15

func _add_room_columns(grid_cell: DungeonData.GridCell, room_number: int, obstacle_density: int) -> void:
	if obstacle_density <= 0:
		return

	var width := grid_cell.end_x - grid_cell.start_x
	var height := grid_cell.end_y - grid_cell.start_y
	if width < 6 or height < 6:
		return

	var center_x: int = (grid_cell.start_x + grid_cell.end_x - 1) >> 1
	var center_y: int = (grid_cell.start_y + grid_cell.end_y - 1) >> 1
	var candidates: Array[Vector2i] = []

	for room_x in range(grid_cell.start_x + 1, grid_cell.end_x - 1):
		for room_y in range(grid_cell.start_y + 1, grid_cell.end_y - 1):
			if abs(room_x - center_x) <= 1 and abs(room_y - center_y) <= 1:
				continue
			if not _can_place_room_column(room_x, room_y, room_number):
				continue
			candidates.append(Vector2i(room_x, room_y))

	if candidates.is_empty():
		return

	for i in range(candidates.size() - 1, 0, -1):
		var swap_index := rng.rand_int(i + 1)
		var tmp := candidates[i]
		candidates[i] = candidates[swap_index]
		candidates[swap_index] = tmp

	var target_columns := int(round(candidates.size() * (float(obstacle_density) / 100.0) * 0.12))
	if obstacle_density >= 20:
		target_columns = maxi(target_columns, 1)
	target_columns = mini(target_columns, maxi(1, candidates.size() >> 2))

	var placed := 0
	for candidate in candidates:
		if placed >= target_columns:
			break
		if not _can_place_room_column(candidate.x, candidate.y, room_number):
			continue
		dungeon_d.list_tiles[candidate.x][candidate.y].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_WALL
		dungeon_d.list_tiles[candidate.x][candidate.y].room_index = 0xFF
		placed += 1

func _can_place_room_column(tile_x: int, tile_y: int, room_number: int) -> bool:
	var tile: DungeonData.Tile = dungeon_d.list_tiles[tile_x][tile_y]
	if tile.terrain_flags.terrain_type != DungeonData.TerrainType.TERRAIN_NORMAL or tile.room_index != room_number:
		return false

	var cardinal_neighbors := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for offset in cardinal_neighbors:
		var neighbor: DungeonData.Tile = dungeon_d.list_tiles[tile_x + offset.x][tile_y + offset.y]
		if neighbor.terrain_flags.terrain_type != DungeonData.TerrainType.TERRAIN_NORMAL or neighbor.room_index != room_number:
			return false

	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var neighbor_tile: DungeonData.Tile = dungeon_d.list_tiles[tile_x + dx][tile_y + dy]
			if neighbor_tile.terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_WALL and neighbor_tile.room_index == 0xFF:
				return false

	return true

func _create_rooms_and_anchors(grid: Array, grid_size_x: int, grid_size_y: int, list_x: Array, list_y: Array, floor_props: DungeonData.FloorProperties, room_flags: DungeonData.RoomFlags) -> void:
	var room_number := 0

	for y in range(grid_size_y):
		var cur_val_y: int = list_y[y]
		var next_val_y: int = list_y[y + 1]
		for x in range(grid_size_x):
			var cur_val_x: int = list_x[x]
			var next_val_x: int = list_x[x + 1]
			var range_x: int = next_val_x - cur_val_x - 4
			var range_y: int = next_val_y - cur_val_y - 3

			if grid[x][y].is_invalid:
				continue

			if not grid[x][y].is_room:
				# Hallway anchor
				var unk_x1 := 2
				var unk_x2 := 4
				if x == 0:
					unk_x1 = 1
				if x == grid_size_x - 1:
					unk_x2 = 2
				var unk_y1 := 2
				var unk_y2 := 4
				if y == 0:
					unk_y1 = 1
				if y == grid_size_y - 1:
					unk_y2 = 2

				var pt_x := rng.rand_range(cur_val_x + 2 + unk_x1, cur_val_x + 2 + range_x - unk_x2)
				var pt_y := rng.rand_range(cur_val_y + 2 + unk_y1, cur_val_y + 2 + range_y - unk_y2)

				grid[x][y].start_x = pt_x
				grid[x][y].start_y = pt_y
				grid[x][y].end_x = pt_x + 1
				grid[x][y].end_y = pt_y + 1

				dungeon_d.list_tiles[pt_x][pt_y].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_NORMAL
				dungeon_d.list_tiles[pt_x][pt_y].room_index = 0xFE

				_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)
			else:
				# Room
				var room_size_x := rng.rand_range(5, range_x)
				var room_size_y := rng.rand_range(4, range_y)

				if (room_size_x | 1) < range_x:
					room_size_x |= 1
				if (room_size_y | 1) < range_y:
					room_size_y |= 1

				# Aspect ratio 2/3 < x/y < 3/2
				if room_size_x > int(float(room_size_y * 3) / 2):
					room_size_x = int(float(room_size_y * 3) / 2)
				if room_size_y > int(float(room_size_x * 3) / 2):
					room_size_y = int(float(room_size_x * 3) / 2)

				var start_x := rng.rand_int(range_x - room_size_x) + cur_val_x + 2
				var end_x := start_x + room_size_x
				var start_y := rng.rand_int(range_y - room_size_y) + cur_val_y + 2
				var end_y := start_y + room_size_y

				grid[x][y].start_x = start_x
				grid[x][y].start_y = start_y
				grid[x][y].end_x = end_x
				grid[x][y].end_y = end_y

				_carve_room_tiles(grid[x][y], room_number, floor_props)

				var flag_secondary := rng.rand_int(100) < gen_constants.secondary_structure_flag_chance
				if status.secondary_structures_budget == 0:
					flag_secondary = false

				var flag_imp := room_flags.f_room_imperfections

				if flag_secondary and flag_imp:
					if rng.rand_int(100) < 50:
						flag_imp = false
					else:
						flag_secondary = false

				if flag_imp:
					grid[x][y].flag_imperfect = true
				if flag_secondary:
					grid[x][y].flag_secondary_structure = true

				room_number += 1
				_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)

	_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MAJOR, 2)

# ─── AssignGridCellConnections ───

func _assign_grid_cell_connections(grid: Array, grid_size_x: int, grid_size_y: int, cursor_x: int, cursor_y: int, floor_props: DungeonData.FloorProperties) -> void:
	var direction: int = rng.rand_int(4)

	for i in range(floor_props.floor_connectivity):
		var test := rng.rand_int(8)
		var new_direction := rng.rand_int(4)

		if test < 4:
			direction = new_direction

		if direction == DungeonData.CardinalDirection.DIR_RIGHT:
			if cursor_x < grid_size_x - 1:
				grid[cursor_x][cursor_y].connected_to_right = true
				grid[cursor_x + 1][cursor_y].connected_to_left = true
				cursor_x += 1
		elif direction == DungeonData.CardinalDirection.DIR_UP:
			if cursor_y > 0:
				grid[cursor_x][cursor_y].connected_to_top = true
				grid[cursor_x][cursor_y - 1].connected_to_bottom = true
				cursor_y -= 1
		elif direction == DungeonData.CardinalDirection.DIR_LEFT:
			if cursor_x > 0:
				grid[cursor_x][cursor_y].connected_to_left = true
				grid[cursor_x - 1][cursor_y].connected_to_right = true
				cursor_x -= 1
		elif direction == DungeonData.CardinalDirection.DIR_DOWN:
			if cursor_y < grid_size_y - 1:
				grid[cursor_x][cursor_y].connected_to_bottom = true
				grid[cursor_x][cursor_y + 1].connected_to_top = true
				cursor_y += 1

	# Remove dead ends
	if not floor_props.allow_dead_ends:
		var more := true
		while more:
			more = false
			for y in range(grid_size_y):
				for x in range(grid_size_x):
					if not grid[x][y].is_invalid and not grid[x][y].is_room:
						var count_connect := 0
						if grid[x][y].connected_to_top: count_connect += 1
						if grid[x][y].connected_to_bottom: count_connect += 1
						if grid[x][y].connected_to_left: count_connect += 1
						if grid[x][y].connected_to_right: count_connect += 1

						if count_connect == 1:
							var new_dir := rng.rand_int(4)
							for _a in range(4):
								if adv_settings.fix_dead_end_validation_error:
									if new_dir == 0 and x < grid_size_x - 1 and not grid[x + 1][y].is_invalid:
										grid[x][y].connected_to_right = true
										grid[x + 1][y].connected_to_left = true
										more = true
										break
									if new_dir == 1 and y > 0 and not grid[x][y - 1].is_invalid:
										grid[x][y].connected_to_top = true
										grid[x][y - 1].connected_to_bottom = true
										more = true
										break
									if new_dir == 2 and x > 0 and not grid[x - 1][y].is_invalid:
										grid[x][y].connected_to_left = true
										grid[x - 1][y].connected_to_right = true
										more = true
										break
									if new_dir == 3 and y < grid_size_y - 1 and not grid[x][y + 1].is_invalid:
										grid[x][y].connected_to_bottom = true
										grid[x][y + 1].connected_to_top = true
										more = true
										break
								else:
									# Original buggy behavior: always checks grid[x+1][y] regardless of direction
									if new_dir == 0 and x < grid_size_x - 1 and not grid[x + 1][y].is_invalid:
										grid[x][y].connected_to_right = true
										grid[x + 1][y].connected_to_left = true
										more = true
										break
									if new_dir == 1 and y > 0 and (x < grid_size_x - 1 and not grid[x + 1][y].is_invalid):
										grid[x][y].connected_to_top = true
										grid[x][y - 1].connected_to_bottom = true
										more = true
										break
									if new_dir == 2 and x > 0 and (x < grid_size_x - 1 and not grid[x + 1][y].is_invalid):
										grid[x][y].connected_to_left = true
										grid[x - 1][y].connected_to_right = true
										more = true
										break
									if new_dir == 3 and y < grid_size_y - 1 and (x < grid_size_x - 1 and not grid[x + 1][y].is_invalid):
										grid[x][y].connected_to_bottom = true
										grid[x][y + 1].connected_to_top = true
										more = true
										break
								new_dir = (new_dir + 1) % 4

	_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MAJOR, 3)

# ─── CreateHallway ───

func _create_hallway(start_x: int, start_y: int, end_x: int, end_y: int, vertical: bool, turn_x: int, turn_y: int) -> void:
	var cur_x := start_x
	var cur_y := start_y
	var counter := 0

	if not vertical:
		# Horizontal: first segment towards turn_x
		while cur_x != turn_x:
			if counter >= 56: return
			counter += 1
			if dungeon_d.list_tiles[cur_x][cur_y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL:
				if start_x != cur_x: return
			else:
				dungeon_d.list_tiles[cur_x][cur_y].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_NORMAL
			if cur_x >= turn_x: cur_x -= 1
			else: cur_x += 1

		counter = 0
		# Vertical connector
		while cur_y != end_y:
			if counter >= 56: return
			counter += 1
			if dungeon_d.list_tiles[cur_x][cur_y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL:
				if start_x != cur_x or start_y != cur_y: return
			else:
				dungeon_d.list_tiles[cur_x][cur_y].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_NORMAL
			if cur_y >= end_y: cur_y -= 1
			else: cur_y += 1

		counter = 0
		# Horizontal: second segment towards end_x
		while cur_x != end_x:
			if counter >= 56: return
			counter += 1
			if dungeon_d.list_tiles[cur_x][cur_y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL:
				if start_x != cur_x or start_y != cur_y: return
			else:
				dungeon_d.list_tiles[cur_x][cur_y].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_NORMAL
			if cur_x >= end_x: cur_x -= 1
			else: cur_x += 1
	else:
		# Vertical: first segment towards turn_y
		while cur_y != turn_y:
			if counter >= 56: return
			counter += 1
			if dungeon_d.list_tiles[cur_x][cur_y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL:
				if start_y != cur_y: return
			else:
				dungeon_d.list_tiles[cur_x][cur_y].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_NORMAL
			if cur_y >= turn_y: cur_y -= 1
			else: cur_y += 1

		counter = 0
		# Horizontal connector
		while cur_x != end_x:
			if counter >= 56: return
			counter += 1
			if dungeon_d.list_tiles[cur_x][cur_y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL:
				if start_x != cur_x or start_y != cur_y: return
			else:
				dungeon_d.list_tiles[cur_x][cur_y].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_NORMAL
			if cur_x >= end_x: cur_x -= 1
			else: cur_x += 1

		counter = 0
		# Vertical: second segment towards end_y
		while cur_y != end_y:
			if counter >= 56: return
			counter += 1
			if dungeon_d.list_tiles[cur_x][cur_y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL:
				if start_x != cur_x or start_y != cur_y: return
			else:
				dungeon_d.list_tiles[cur_x][cur_y].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_NORMAL
			if cur_y >= end_y: cur_y -= 1
			else: cur_y += 1

# ─── CreateGridCellConnections ───

func _create_grid_cell_connections(grid: Array, grid_size_x: int, grid_size_y: int, list_x: Array, list_y: Array, disable_room_merging: bool) -> void:
	# Copy connections to work array
	for x in range(grid_size_x):
		for y in range(grid_size_y):
			grid[x][y].should_connect_to_top = grid[x][y].connected_to_top
			grid[x][y].should_connect_to_bottom = grid[x][y].connected_to_bottom
			grid[x][y].should_connect_to_left = grid[x][y].connected_to_left
			grid[x][y].should_connect_to_right = grid[x][y].connected_to_right

	for y in range(grid_size_y):
		for x in range(grid_size_x):
			if grid[x][y].is_invalid or grid[x][y].has_been_merged:
				continue

			var pt_x: int
			var pt_y: int
			var pt2_x: int
			var pt2_y: int

			if not grid[x][y].is_room:
				pt_x = grid[x][y].start_x
				pt_y = grid[x][y].start_y
			else:
				pt_x = rng.rand_range(grid[x][y].start_x + 1, grid[x][y].end_x - 1)
				pt_y = rng.rand_range(grid[x][y].start_y + 1, grid[x][y].end_y - 1)

			if grid[x][y].should_connect_to_top:
				if not grid[x][y - 1].is_invalid:
					if not grid[x][y - 1].is_room:
						pt2_x = grid[x][y - 1].start_x
					else:
						pt2_x = rng.rand_range(grid[x][y - 1].start_x + 1, grid[x][y - 1].end_x - 1)
					_create_hallway(pt_x, grid[x][y].start_y, pt2_x, grid[x][y - 1].end_y - 1, true, list_x[x], list_y[y])
					_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)
				grid[x][y].should_connect_to_top = false
				grid[x][y - 1].should_connect_to_bottom = false
				grid[x][y].is_cell_connected = true
				grid[x][y - 1].is_cell_connected = true

			if grid[x][y].should_connect_to_bottom:
				if not grid[x][y + 1].is_invalid:
					if not grid[x][y + 1].is_room:
						pt2_x = grid[x][y + 1].start_x
					else:
						pt2_x = rng.rand_range(grid[x][y + 1].start_x + 1, grid[x][y + 1].end_x - 1)
					_create_hallway(pt_x, grid[x][y].end_y - 1, pt2_x, grid[x][y + 1].start_y, true, list_x[x], list_y[y + 1] - 1)
					_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)
				grid[x][y].should_connect_to_bottom = false
				grid[x][y + 1].should_connect_to_top = false
				grid[x][y].is_cell_connected = true
				grid[x][y + 1].is_cell_connected = true

			if grid[x][y].should_connect_to_left:
				if not grid[x - 1][y].is_invalid:
					if not grid[x - 1][y].is_room:
						pt2_y = grid[x - 1][y].start_y
					else:
						pt2_y = rng.rand_range(grid[x - 1][y].start_y + 1, grid[x - 1][y].end_y - 1)
					# Original bug: uses start_x - 1 instead of end_x - 1
					_create_hallway(grid[x][y].start_x, pt_y, grid[x - 1][y].start_x - 1, pt2_y, false, list_x[x], list_y[y])
					_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)
				grid[x][y].should_connect_to_left = false
				grid[x - 1][y].should_connect_to_right = false
				grid[x][y].is_cell_connected = true
				grid[x - 1][y].is_cell_connected = true

			if grid[x][y].should_connect_to_right:
				if not grid[x + 1][y].is_invalid:
					if not grid[x + 1][y].is_room:
						pt2_y = grid[x + 1][y].start_y
					else:
						pt2_y = rng.rand_range(grid[x + 1][y].start_y + 1, grid[x + 1][y].end_y - 1)
					_create_hallway(grid[x][y].end_x - 1, pt_y, grid[x + 1][y].start_x, pt2_y, false, list_x[x + 1] - 1, list_y[y])
					_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)
				grid[x][y].should_connect_to_right = false
				grid[x + 1][y].should_connect_to_left = false
				grid[x][y].is_cell_connected = true
				grid[x + 1][y].is_cell_connected = true

	if disable_room_merging:
		_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MAJOR, 3)
		return

	# Room merging
	for x in range(grid_size_x):
		for y in range(grid_size_y):
			var chance := rng.rand_int(100)
			if (
				chance < gen_constants.merge_rooms_chance and
				not grid[x][y].is_invalid and grid[x][y].is_cell_connected and
				not grid[x][y].is_merged and not grid[x][y].has_secondary_structure and
				grid[x][y].is_room
			):
				var chance_two := rng.rand_int(4)
				if (
					chance_two == 0 and x >= 1 and
					not grid[x - 1][y].is_invalid and grid[x - 1][y].is_cell_connected and
					not grid[x - 1][y].is_merged and not grid[x - 1][y].has_secondary_structure and
					grid[x - 1][y].is_room
				):
					_merge_rooms(grid, x, y, x - 1, y)
				elif (
					chance_two == 1 and y >= 1 and
					not grid[x][y - 1].is_invalid and grid[x][y - 1].is_cell_connected and
					not grid[x][y - 1].is_merged and not grid[x][y - 1].has_secondary_structure and
					grid[x][y - 1].is_room
				):
					_merge_rooms(grid, x, y, x, y - 1)
				elif (
					chance_two == 2 and x <= grid_size_x - 2 and
					not grid[x + 1][y].is_invalid and grid[x + 1][y].is_cell_connected and
					not grid[x + 1][y].is_merged and not grid[x + 1][y].has_secondary_structure and
					grid[x + 1][y].is_room
				):
					_merge_rooms(grid, x, y, x + 1, y)
				elif (
					chance_two == 3 and y <= grid_size_y - 2 and
					not grid[x][y + 1].is_invalid and grid[x][y + 1].is_cell_connected and
					not grid[x][y + 1].is_merged and not grid[x][y + 1].has_secondary_structure and
					grid[x][y + 1].is_room
				):
					_merge_rooms(grid, x, y, x, y + 1)

	_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MAJOR, 3)

func _merge_rooms(grid: Array, src_x: int, src_y: int, dst_x: int, dst_y: int) -> void:
	var min_sx := mini(grid[src_x][src_y].start_x, grid[dst_x][dst_y].start_x)
	var min_sy := mini(grid[src_x][src_y].start_y, grid[dst_x][dst_y].start_y)
	var max_ex := maxi(grid[src_x][src_y].end_x, grid[dst_x][dst_y].end_x)
	var max_ey := maxi(grid[src_x][src_y].end_y, grid[dst_x][dst_y].end_y)

	var merge_room_index: int = dungeon_d.list_tiles[grid[src_x][src_y].start_x][grid[src_x][src_y].start_y].room_index

	for cur_x in range(min_sx, max_ex):
		for cur_y in range(min_sy, max_ey):
			dungeon_d.list_tiles[cur_x][cur_y].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_NORMAL
			dungeon_d.list_tiles[cur_x][cur_y].room_index = merge_room_index

	grid[dst_x][dst_y].start_x = min_sx
	grid[dst_x][dst_y].start_y = min_sy
	grid[dst_x][dst_y].end_x = max_ex
	grid[dst_x][dst_y].end_y = max_ey

	grid[dst_x][dst_y].is_merged = true
	grid[src_x][src_y].is_merged = true
	grid[src_x][src_y].is_cell_connected = false
	grid[src_x][src_y].has_been_merged = true

	_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)

# ─── EnsureConnectedGrid ───

func _ensure_connected_grid(grid: Array, grid_size_x: int, grid_size_y: int, list_x: Array, list_y: Array) -> void:
	var was_grid_changed := false

	for x in range(grid_size_x):
		for y in range(grid_size_y):
			if grid[x][y].is_invalid or grid[x][y].is_cell_connected or grid[x][y].has_been_merged:
				continue

			if grid[x][y].is_room and not grid[x][y].has_secondary_structure:
				var rnd_x := rng.rand_range(grid[x][y].start_x + 1, grid[x][y].end_x - 1)
				var rnd_y := rng.rand_range(grid[x][y].start_y + 1, grid[x][y].end_y - 1)
				var pt_x: int
				var pt_y: int

				if y > 0 and not grid[x][y - 1].is_invalid and not grid[x][y - 1].is_merged and grid[x][y - 1].is_cell_connected:
					if not grid[x][y - 1].is_room:
						pt_x = grid[x][y - 1].start_x
					else:
						pt_x = rng.rand_range(grid[x][y - 1].start_x + 1, grid[x][y - 1].end_x - 1)
						var _unused := rng.rand_range(grid[x][y - 1].start_y + 1, grid[x][y - 1].end_y - 1)
					_create_hallway(rnd_x, grid[x][y].start_y, pt_x, grid[x][y - 1].end_y - 1, true, list_x[x], list_y[y])
					grid[x][y].is_cell_connected = true
					grid[x][y].connected_to_top = true
					grid[x][y - 1].connected_to_bottom = true
					_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)
					was_grid_changed = true
				elif y < grid_size_y - 1 and not grid[x][y + 1].is_invalid and not grid[x][y + 1].is_merged and grid[x][y + 1].is_cell_connected:
					if not grid[x][y + 1].is_room:
						pt_x = grid[x][y + 1].start_x
					else:
						pt_x = rng.rand_range(grid[x][y + 1].start_x + 1, grid[x][y + 1].end_x - 1)
						var _unused := rng.rand_range(grid[x][y + 1].start_y + 1, grid[x][y + 1].end_y - 1)
					_create_hallway(rnd_x, grid[x][y].end_y - 1, pt_x, grid[x][y + 1].start_y, true, list_x[x], list_y[y + 1] - 1)
					grid[x][y].is_cell_connected = true
					grid[x][y].connected_to_bottom = true
					grid[x][y + 1].connected_to_top = true
					_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)
					was_grid_changed = true
				elif x > 0 and not grid[x - 1][y].is_invalid and not grid[x - 1][y].is_merged and grid[x - 1][y].is_cell_connected:
					if not grid[x - 1][y].is_room:
						pt_y = grid[x - 1][y].start_y
					else:
						var _unused := rng.rand_range(grid[x - 1][y].start_x + 1, grid[x - 1][y].end_x - 1)
						pt_y = rng.rand_range(grid[x - 1][y].start_y + 1, grid[x - 1][y].end_y - 1)
					_create_hallway(grid[x][y].start_x, rnd_y, grid[x - 1][y].start_x - 1, pt_y, false, list_x[x], list_y[y])
					grid[x][y].is_cell_connected = true
					grid[x][y].connected_to_left = true
					grid[x - 1][y].connected_to_right = true
					_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)
					was_grid_changed = true
				elif x < grid_size_x - 1 and not grid[x + 1][y].is_invalid and not grid[x + 1][y].is_merged and grid[x + 1][y].is_cell_connected:
					if not grid[x + 1][y].is_room:
						pt_y = grid[x + 1][y].start_y
					else:
						var _unused := rng.rand_range(grid[x + 1][y].start_x + 1, grid[x + 1][y].end_x - 1)
						pt_y = rng.rand_range(grid[x + 1][y].start_y + 1, grid[x + 1][y].end_y - 1)
					_create_hallway(grid[x][y].end_x - 1, rnd_y, grid[x + 1][y].start_x, pt_y, false, list_x[x + 1] - 1, list_y[y])
					grid[x][y].is_cell_connected = true
					grid[x][y].connected_to_right = true
					grid[x + 1][y].connected_to_left = true
					_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)
					was_grid_changed = true
			else:
				# Unconnected anchor - fill it back in
				dungeon_d.list_tiles[grid[x][y].start_x][grid[x][y].start_y].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_WALL
				dungeon_d.list_tiles[grid[x][y].start_x][grid[x][y].start_y].spawn_or_visibility_flags.f_stairs = false
				dungeon_d.list_tiles[grid[x][y].start_x][grid[x][y].start_y].spawn_or_visibility_flags.f_item = false
				dungeon_d.list_tiles[grid[x][y].start_x][grid[x][y].start_y].spawn_or_visibility_flags.f_trap = false
				_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)
				was_grid_changed = true

	# Fill in still-unconnected rooms
	for x in range(grid_size_x):
		for y in range(grid_size_y):
			if grid[x][y].is_invalid or grid[x][y].has_been_merged or grid[x][y].is_cell_connected or grid[x][y].unk4:
				continue
			for cur_x in range(grid[x][y].start_x, grid[x][y].end_x):
				for cur_y in range(grid[x][y].start_y, grid[x][y].end_y):
					dungeon_d.list_tiles[cur_x][cur_y].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_WALL
					dungeon_d.list_tiles[cur_x][cur_y].room_index = 0xFF
			if grid[x][y].is_room:
				_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)

	if was_grid_changed:
		_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MAJOR, 4)

# ─── SetTerrainObstacleChecked / GenerateMazeLine / GenerateMaze ───

func _set_terrain_obstacle_checked(tile: DungeonData.Tile, use_secondary_terrain: bool, room_index: int) -> void:
	if use_secondary_terrain and tile.room_index == room_index:
		tile.terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_SECONDARY
	else:
		tile.terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_WALL

func _generate_maze_line(x0: int, y0: int, xmin: int, ymin: int, xmax: int, ymax: int, use_secondary_terrain: bool, room_index: int) -> void:
	var ok := true
	while ok:
		var direction := rng.rand_int(4)
		_set_terrain_obstacle_checked(dungeon_d.list_tiles[x0][y0], use_secondary_terrain, room_index)
		ok = false

		for _i in range(4):
			if direction == DungeonData.CardinalDirection.DIR_RIGHT:
				if x0 + 2 < xmax and dungeon_d.list_tiles[x0 + 2][y0].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL:
					ok = true
			elif direction == DungeonData.CardinalDirection.DIR_UP:
				if y0 - 2 >= ymin and dungeon_d.list_tiles[x0][y0 - 2].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL:
					ok = true
			elif direction == DungeonData.CardinalDirection.DIR_LEFT:
				if x0 - 2 >= xmin and dungeon_d.list_tiles[x0 - 2][y0].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL:
					ok = true
			elif direction == DungeonData.CardinalDirection.DIR_DOWN:
				if y0 + 2 < ymax and dungeon_d.list_tiles[x0][y0 + 2].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL:
					ok = true

			if ok:
				break
			direction = (direction + 1) % 4

		if ok:
			if direction == DungeonData.CardinalDirection.DIR_RIGHT:
				_set_terrain_obstacle_checked(dungeon_d.list_tiles[x0 + 1][y0], use_secondary_terrain, room_index)
				x0 += 2
			elif direction == DungeonData.CardinalDirection.DIR_UP:
				_set_terrain_obstacle_checked(dungeon_d.list_tiles[x0][y0 - 1], use_secondary_terrain, room_index)
				y0 -= 2
			elif direction == DungeonData.CardinalDirection.DIR_LEFT:
				_set_terrain_obstacle_checked(dungeon_d.list_tiles[x0 - 1][y0], use_secondary_terrain, room_index)
				x0 -= 2
			elif direction == DungeonData.CardinalDirection.DIR_DOWN:
				_set_terrain_obstacle_checked(dungeon_d.list_tiles[x0][y0 + 1], use_secondary_terrain, room_index)
				y0 += 2

func _generate_maze(grid_cell: DungeonData.GridCell, use_secondary_terrain: bool) -> void:
	grid_cell.is_maze_room = true
	status.has_maze = true
	var room_index: int = dungeon_d.list_tiles[grid_cell.start_x][grid_cell.start_y].room_index

	for cur_x in range(grid_cell.start_x + 1, grid_cell.end_x - 1, 2):
		if dungeon_d.list_tiles[cur_x][grid_cell.start_y - 1].terrain_flags.terrain_type != DungeonData.TerrainType.TERRAIN_NORMAL:
			_generate_maze_line(cur_x, grid_cell.start_y - 1, grid_cell.start_x, grid_cell.start_y, grid_cell.end_x, grid_cell.end_y, use_secondary_terrain, room_index)

	for cur_y in range(grid_cell.start_y + 1, grid_cell.end_y - 1, 2):
		if dungeon_d.list_tiles[grid_cell.end_x][cur_y].terrain_flags.terrain_type != DungeonData.TerrainType.TERRAIN_NORMAL:
			_generate_maze_line(grid_cell.end_x, cur_y, grid_cell.start_x, grid_cell.start_y, grid_cell.end_x, grid_cell.end_y, use_secondary_terrain, room_index)

	for cur_x in range(grid_cell.start_x + 1, grid_cell.end_x - 1, 2):
		if dungeon_d.list_tiles[cur_x][grid_cell.end_y].terrain_flags.terrain_type != DungeonData.TerrainType.TERRAIN_NORMAL:
			_generate_maze_line(cur_x, grid_cell.end_y, grid_cell.start_x, grid_cell.start_y, grid_cell.end_x, grid_cell.end_y, use_secondary_terrain, room_index)

	for cur_y in range(grid_cell.start_y + 1, grid_cell.end_y - 1, 2):
		if dungeon_d.list_tiles[grid_cell.start_x - 1][cur_y].terrain_flags.terrain_type != DungeonData.TerrainType.TERRAIN_NORMAL:
			_generate_maze_line(grid_cell.start_x - 1, cur_y, grid_cell.start_x, grid_cell.start_y, grid_cell.end_x, grid_cell.end_y, use_secondary_terrain, room_index)

	for cur_x in range(grid_cell.start_x + 3, grid_cell.end_x - 3, 2):
		for cur_y in range(grid_cell.start_y + 3, grid_cell.end_y - 3, 2):
			if dungeon_d.list_tiles[cur_x][cur_y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL:
				if use_secondary_terrain:
					dungeon_d.list_tiles[cur_x][cur_y].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_SECONDARY
				else:
					dungeon_d.list_tiles[cur_x][cur_y].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_WALL
				_generate_maze_line(cur_x, cur_y, grid_cell.start_x, grid_cell.start_y, grid_cell.end_x, grid_cell.end_y, use_secondary_terrain, room_index)

# ─── GenerateMazeRoom ───

func _generate_maze_room(grid: Array, grid_size_x: int, grid_size_y: int, maze_chance: int) -> void:
	if maze_chance <= 0: return
	if rng.rand_int(100) >= maze_chance: return

	if adv_settings.allow_wall_maze_room_generation or gen_info.floor_generation_attempts < 0:
		var num_valid := 0
		for y in range(grid_size_y):
			for x in range(grid_size_x):
				if (not grid[x][y].is_invalid and not grid[x][y].has_been_merged and
					grid[x][y].is_cell_connected and grid[x][y].is_room and
					not grid[x][y].has_secondary_structure and not grid[x][y].is_kecleon_shop and
					not grid[x][y].is_monster_house and not grid[x][y].unk4):
					if (grid[x][y].end_x - grid[x][y].start_x) % 2 != 0 and (grid[x][y].end_y - grid[x][y].start_y) % 2 != 0:
						num_valid += 1

		if num_valid <= 0: return

		var values: Array = []
		values.resize(256)
		values.fill(false)
		values[0] = true

		for i in range(64):
			var a := rng.rand_int(num_valid)
			var b := rng.rand_int(num_valid)
			var tmp = values[a]
			values[a] = values[b]
			values[b] = tmp

		var counter := 0
		for y in range(grid_size_y):
			for x in range(grid_size_x):
				if (not grid[x][y].is_invalid and not grid[x][y].has_been_merged and
					grid[x][y].is_cell_connected and grid[x][y].is_room and
					not grid[x][y].has_secondary_structure and not grid[x][y].is_kecleon_shop and
					not grid[x][y].is_monster_house and not grid[x][y].unk4):
					if (grid[x][y].end_x - grid[x][y].start_x) % 2 != 0 and (grid[x][y].end_y - grid[x][y].start_y) % 2 != 0:
						if values[counter]:
							_generate_maze(grid[x][y], false)
							_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MAJOR, 5)
						counter += 1

# ─── GetFloorType ───

func _get_floor_type() -> int:
	if dungeon_d.dungeon_objective == DungeonData.DungeonObjectiveType.OBJECTIVE_RESCUE and dungeon_d.dungeon_floor == dungeon_d.rescue_floor:
		return DungeonData.FloorType.FLOOR_TYPE_RESCUE
	if gen_info.fixed_room_id > 0 and gen_info.fixed_room_id <= 0x6E:
		return DungeonData.FloorType.FLOOR_TYPE_FIXED
	return DungeonData.FloorType.FLOOR_TYPE_NORMAL

# ─── GenerateKecleonShop ───

func _generate_kecleon_shop(grid: Array, grid_size_x: int, grid_size_y: int, kecleon_chance: int) -> void:
	if status.has_monster_house or _get_floor_type() == DungeonData.FloorType.FLOOR_TYPE_RESCUE or kecleon_chance <= 0:
		return
	if rng.rand_int(100) >= kecleon_chance: return

	var list_x_idx: Array = []
	var list_y_idx: Array = []
	for i in range(0xF):
		list_x_idx.append(i)
		list_y_idx.append(i)

	for _x in range(200):
		var a := rng.rand_int(0xF)
		var b := rng.rand_int(0xF)
		var tmp = list_x_idx[a]; list_x_idx[a] = list_x_idx[b]; list_x_idx[b] = tmp
	for _y in range(200):
		var a := rng.rand_int(0xF)
		var b := rng.rand_int(0xF)
		var tmp = list_y_idx[a]; list_y_idx[a] = list_y_idx[b]; list_y_idx[b] = tmp

	for i in range(list_x_idx.size()):
		if list_x_idx[i] >= grid_size_x: continue
		var x: int = list_x_idx[i]
		for j in range(list_y_idx.size()):
			if list_y_idx[j] >= grid_size_y: continue
			var y: int = list_y_idx[j]

			if (grid[x][y].is_invalid or grid[x][y].has_been_merged or grid[x][y].is_merged or
				not grid[x][y].is_cell_connected or not grid[x][y].is_room or
				grid[x][y].has_secondary_structure or grid[x][y].is_maze_room or
				grid[x][y].flag_secondary_structure):
				continue

			if abs(grid[x][y].start_x - grid[x][y].end_x) < 5 or abs(grid[x][y].start_y - grid[x][y].end_y) < 4:
				continue

			status.has_kecleon_shop = true
			grid[x][y].is_kecleon_shop = true

			status.kecleon_shop_min_x = grid[x][y].start_x
			status.kecleon_shop_min_y = grid[x][y].start_y
			status.kecleon_shop_max_x = grid[x][y].end_x
			status.kecleon_shop_max_y = grid[x][y].end_y

			if grid[x][y].end_y - grid[x][y].start_y < 3:
				status.kecleon_shop_max_y = grid[x][y].end_y + 1

			dungeon_d.kecleon_shop_min_x = DungeonData.DEFAULT_MAX_POSITION
			dungeon_d.kecleon_shop_min_y = DungeonData.DEFAULT_MAX_POSITION
			dungeon_d.kecleon_shop_max_x = -DungeonData.DEFAULT_MAX_POSITION
			dungeon_d.kecleon_shop_max_y = -DungeonData.DEFAULT_MAX_POSITION

			for cur_x in range(status.kecleon_shop_min_x + 1, status.kecleon_shop_max_x - 1):
				for cur_y in range(status.kecleon_shop_min_y + 1, status.kecleon_shop_max_y - 1):
					dungeon_d.list_tiles[cur_x][cur_y].terrain_flags.f_in_kecleon_shop = true
					dungeon_d.list_tiles[cur_x][cur_y].spawn_or_visibility_flags.f_monster = false
					dungeon_d.list_tiles[cur_x][cur_y].spawn_or_visibility_flags.f_stairs = false
					if cur_x <= dungeon_d.kecleon_shop_min_x: dungeon_d.kecleon_shop_min_x = cur_x
					if cur_y <= dungeon_d.kecleon_shop_min_y: dungeon_d.kecleon_shop_min_y = cur_y
					if cur_x >= dungeon_d.kecleon_shop_max_x: dungeon_d.kecleon_shop_max_x = cur_x
					if cur_y >= dungeon_d.kecleon_shop_max_y: dungeon_d.kecleon_shop_max_y = cur_y

			for cur_x in range(grid[x][y].start_x, grid[x][y].end_x):
				for cur_y in range(grid[x][y].start_y, grid[x][y].end_y):
					dungeon_d.list_tiles[cur_x][cur_y].spawn_or_visibility_flags.f_special_tile = true

			status.kecleon_shop_middle_x = int(float(status.kecleon_shop_min_x + status.kecleon_shop_max_x) / 2)
			status.kecleon_shop_middle_y = int(float(status.kecleon_shop_min_y + status.kecleon_shop_max_y) / 2)
			_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MAJOR, 6)
			return

# ─── Mission helper stubs ───

func _is_current_mission_type_exact(_mt: int, _ms: int) -> bool:
	if not dungeon_d.mission_destination.is_destination_floor: return false
	return dungeon_d.mission_destination.mission_type == _mt and dungeon_d.mission_destination.mission_subtype == _ms

func _floor_has_mission_monster() -> bool:
	return (
		_is_current_mission_type_exact(DungeonData.MissionType.MISSION_ARREST_OUTLAW, DungeonData.MissionSubtypeOutlaw.MISSION_OUTLAW_NORMAL_0) or
		_is_current_mission_type_exact(DungeonData.MissionType.MISSION_ARREST_OUTLAW, DungeonData.MissionSubtypeOutlaw.MISSION_OUTLAW_NORMAL_1) or
		_is_current_mission_type_exact(DungeonData.MissionType.MISSION_ARREST_OUTLAW, DungeonData.MissionSubtypeOutlaw.MISSION_OUTLAW_NORMAL_2) or
		_is_current_mission_type_exact(DungeonData.MissionType.MISSION_ARREST_OUTLAW, DungeonData.MissionSubtypeOutlaw.MISSION_OUTLAW_NORMAL_3) or
		_is_current_mission_type_exact(DungeonData.MissionType.MISSION_ARREST_OUTLAW, DungeonData.MissionSubtypeOutlaw.MISSION_OUTLAW_FLEEING) or
		_is_current_mission_type_exact(DungeonData.MissionType.MISSION_ARREST_OUTLAW, DungeonData.MissionSubtypeOutlaw.MISSION_OUTLAW_HIDEOUT) or
		_is_current_mission_type_exact(DungeonData.MissionType.MISSION_TAKE_ITEM_FROM_OUTLAW, DungeonData.MissionSubtypeTakeItem.MISSION_TAKE_ITEM_NORMAL_OUTLAW) or
		_is_current_mission_type_exact(DungeonData.MissionType.MISSION_TAKE_ITEM_FROM_OUTLAW, DungeonData.MissionSubtypeTakeItem.MISSION_TAKE_ITEM_HIDDEN_OUTLAW) or
		_is_current_mission_type_exact(DungeonData.MissionType.MISSION_TAKE_ITEM_FROM_OUTLAW, DungeonData.MissionSubtypeTakeItem.MISSION_TAKE_ITEM_FLEEING_OUTLAW) or
		_is_current_mission_type_exact(DungeonData.MissionType.MISSION_CHALLENGE_REQUEST, 0) or
		_is_current_mission_type_exact(DungeonData.MissionType.MISSION_SEARCH_FOR_TARGET, 0) or
		_is_current_mission_type_exact(DungeonData.MissionType.MISSION_RESCUE_TARGET, 0)
	)

func _is_outlaw_monster_house_floor() -> bool:
	return _is_current_mission_type_exact(DungeonData.MissionType.MISSION_ARREST_OUTLAW, DungeonData.MissionSubtypeOutlaw.MISSION_OUTLAW_MONSTER_HOUSE)

func _is_destination_floor_with_monster() -> bool:
	return _floor_has_mission_monster()

# ─── GenerateMonsterHouse ───

func _generate_monster_house(grid: Array, grid_size_x: int, grid_size_y: int, monster_house_chance: int) -> void:
	if monster_house_chance <= 0: return
	if rng.rand_int(100) >= monster_house_chance: return
	if status.has_kecleon_shop: return
	if (not _is_outlaw_monster_house_floor() and _is_destination_floor_with_monster()) or _get_floor_type() != DungeonData.FloorType.FLOOR_TYPE_NORMAL:
		return

	var num_valid := 0
	for x in range(grid_size_x):
		for y in range(grid_size_y):
			if (not grid[x][y].is_invalid and not grid[x][y].has_been_merged and
				grid[x][y].is_cell_connected and grid[x][y].is_room and
				not grid[x][y].is_kecleon_shop and not grid[x][y].unk4 and
				not grid[x][y].is_maze_room and not grid[x][y].has_secondary_structure):
				num_valid += 1

	if num_valid <= 0: return

	var values: Array = []
	values.resize(256)
	values.fill(false)
	values[0] = true

	for i in range(64):
		var a := rng.rand_int(num_valid)
		var b := rng.rand_int(num_valid)
		var tmp = values[a]; values[a] = values[b]; values[b] = tmp

	var counter := 0
	for x in range(grid_size_x):
		for y in range(grid_size_y):
			if (not grid[x][y].is_invalid and not grid[x][y].has_been_merged and
				grid[x][y].is_cell_connected and grid[x][y].is_room and
				not grid[x][y].is_kecleon_shop and not grid[x][y].unk4 and
				not grid[x][y].is_maze_room and not grid[x][y].has_secondary_structure):
				if values[counter]:
					status.has_monster_house = true
					grid[x][y].is_monster_house = true
					for cur_x in range(grid[x][y].start_x, grid[x][y].end_x):
						for cur_y in range(grid[x][y].start_y, grid[x][y].end_y):
							dungeon_d.list_tiles[cur_x][cur_y].terrain_flags.f_in_monster_house = true
							gen_info.monster_house_room = dungeon_d.list_tiles[cur_x][cur_y].room_index
					_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MAJOR, 7)
					return
				counter += 1

# ─── GenerateExtraHallways ───

func _is_next_to_hallway(x: int, y: int) -> bool:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0: continue
			var nx := x + dx
			var ny := y + dy
			if nx >= 0 and nx < DungeonData.FLOOR_MAX_X and ny >= 0 and ny < DungeonData.FLOOR_MAX_Y:
				if dungeon_d.list_tiles[nx][ny].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL and dungeon_d.list_tiles[nx][ny].room_index == 0xFF:
					return true
	return false

func _generate_extra_hallways(grid: Array, grid_size_x: int, grid_size_y: int, num_extra_hallways: int) -> void:
	var added_extra_hallway := false

	for _i in range(num_extra_hallways):
		var x := rng.rand_int(grid_size_x)
		var y := rng.rand_int(grid_size_y)

		if not grid[x][y].is_room or not grid[x][y].is_cell_connected or grid[x][y].is_invalid or grid[x][y].is_maze_room:
			continue

		var cur_x := rng.rand_range(grid[x][y].start_x, grid[x][y].end_x - 1)
		var cur_y := rng.rand_range(grid[x][y].start_y, grid[x][y].end_y - 1)
		var direction: int = rng.rand_int(4) * 2

		for j in range(3):
			if direction == DungeonData.DirectionId.DIR_DOWN and y >= grid_size_y - 1:
				direction = DungeonData.DirectionId.DIR_RIGHT
			if direction == DungeonData.DirectionId.DIR_RIGHT and x >= grid_size_x - 1:
				direction = DungeonData.DirectionId.DIR_UP
			if direction == DungeonData.DirectionId.DIR_UP and y <= 0:
				direction = DungeonData.DirectionId.DIR_LEFT
			if direction == DungeonData.DirectionId.DIR_LEFT and x <= 0:
				direction = DungeonData.DirectionId.DIR_DOWN

		var room_index: int = dungeon_d.list_tiles[cur_x][cur_y].room_index

		# Walk out of the room
		var continue_walk := true
		while continue_walk:
			if _pos_is_out_of_bounds(cur_x, cur_y):
				continue_walk = false
			elif dungeon_d.list_tiles[cur_x][cur_y].room_index == room_index:
				cur_x += DungeonData.LIST_DIRECTIONS[direction * 4]
				cur_y += DungeonData.LIST_DIRECTIONS[direction * 4 + 2]
			else:
				continue_walk = false

		if _pos_is_out_of_bounds(cur_x, cur_y):
			continue

		# Walk until obstacle
		continue_walk = true
		while continue_walk:
			if _pos_is_out_of_bounds(cur_x, cur_y):
				continue_walk = false
			elif dungeon_d.list_tiles[cur_x][cur_y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL:
				cur_x += DungeonData.LIST_DIRECTIONS[direction * 4]
				cur_y += DungeonData.LIST_DIRECTIONS[direction * 4 + 2]
			else:
				continue_walk = false

		if _pos_is_out_of_bounds(cur_x, cur_y):
			continue

		if dungeon_d.list_tiles[cur_x][cur_y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_SECONDARY:
			continue

		# Check 2-tile margin from borders
		var valid := true
		for check_x in range(cur_x - 2, cur_x + 3):
			for check_y in range(cur_y - 2, cur_y + 3):
				if check_x < 0 or check_x >= DungeonData.FLOOR_MAX_X or check_y < 0 or check_y >= DungeonData.FLOOR_MAX_Y:
					valid = false
					break
			if not valid: break
		if not valid: continue

		# Check CCW direction isn't open
		var check_direction: int = (direction + 2) % 8
		var check_x: int = cur_x + DungeonData.LIST_DIRECTIONS[check_direction * 4]
		var check_y: int = cur_y + DungeonData.LIST_DIRECTIONS[check_direction * 4 + 2]
		if dungeon_d.list_tiles[check_x][check_y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL:
			continue

		# Check CW direction isn't open
		check_direction = (direction + 6) % 8
		check_x = cur_x + DungeonData.LIST_DIRECTIONS[check_direction * 4]
		check_y = cur_y + DungeonData.LIST_DIRECTIONS[check_direction * 4 + 2]
		if dungeon_d.list_tiles[check_x][check_y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL:
			continue

		var steps := rng.rand_int(3) + 3
		var hallway_done := false
		while not hallway_done:
			if cur_x <= 1 or cur_y <= 1 or cur_x >= 55 or cur_y >= 31: break
			if dungeon_d.list_tiles[cur_x][cur_y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL: break
			if dungeon_d.list_tiles[cur_x][cur_y].terrain_flags.f_impassable_wall: break

			# Check no 2x2 square would form
			var will_not_make_square := true
			if (dungeon_d.list_tiles[cur_x + 1][cur_y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL and
				dungeon_d.list_tiles[cur_x + 1][cur_y + 1].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL and
				dungeon_d.list_tiles[cur_x][cur_y + 1].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL):
				will_not_make_square = false
			if (dungeon_d.list_tiles[cur_x + 1][cur_y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL and
				dungeon_d.list_tiles[cur_x + 1][cur_y - 1].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL and
				dungeon_d.list_tiles[cur_x][cur_y - 1].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL):
				will_not_make_square = false
			if (dungeon_d.list_tiles[cur_x - 1][cur_y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL and
				dungeon_d.list_tiles[cur_x - 1][cur_y + 1].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL and
				dungeon_d.list_tiles[cur_x][cur_y + 1].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL):
				will_not_make_square = false
			if (dungeon_d.list_tiles[cur_x - 1][cur_y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL and
				dungeon_d.list_tiles[cur_x - 1][cur_y - 1].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL and
				dungeon_d.list_tiles[cur_x][cur_y - 1].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL):
				will_not_make_square = false

			if not will_not_make_square: break

			dungeon_d.list_tiles[cur_x][cur_y].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_NORMAL

			# Check CCW/CW again
			check_direction = (direction + 2) % 8
			check_x = cur_x + DungeonData.LIST_DIRECTIONS[check_direction * 4]
			check_y = cur_y + DungeonData.LIST_DIRECTIONS[check_direction * 4 + 2]
			if dungeon_d.list_tiles[check_x][check_y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL: break

			check_direction = (direction + 6) % 8
			check_x = cur_x + DungeonData.LIST_DIRECTIONS[check_direction * 4]
			check_y = cur_y + DungeonData.LIST_DIRECTIONS[check_direction * 4 + 2]
			if dungeon_d.list_tiles[check_x][check_y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL: break

			steps -= 1
			if steps == 0:
				steps = rng.rand_int(3) + 3
				var rotate_rand := rng.rand_int(100)
				if rotate_rand < 50:
					direction = (direction + 2) % 8
				else:
					direction = (direction + 6) % 8

				if cur_x >= 32 and status.floor_size == DungeonData.FloorSize.FLOOR_SIZE_SMALL and direction == DungeonData.DirectionId.DIR_RIGHT:
					break
				if cur_x >= 48 and status.floor_size == DungeonData.FloorSize.FLOOR_SIZE_MEDIUM and direction == DungeonData.DirectionId.DIR_RIGHT:
					break

			cur_x += DungeonData.LIST_DIRECTIONS[direction * 4]
			cur_y += DungeonData.LIST_DIRECTIONS[direction * 4 + 2]

		_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)
		added_extra_hallway = true

	if added_extra_hallway:
		_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MAJOR, 8)

# ─── GenerateRoomImperfections ───

func _generate_room_imperfections(grid: Array, grid_size_x: int, grid_size_y: int) -> void:
	var added_room_imperfections := false

	for x in range(grid_size_x):
		for y in range(grid_size_y):
			if (grid[x][y].is_invalid or grid[x][y].has_been_merged or grid[x][y].is_merged or
				not grid[x][y].is_room or not grid[x][y].is_cell_connected or
				grid[x][y].has_secondary_structure or grid[x][y].is_maze_room or
				not grid[x][y].flag_imperfect):
				continue

			if rng.rand_int(100) < gen_constants.no_imperfections_chance:
				continue

			var added_imperfections_to_this_room := false
			var length: int = grid[x][y].end_x - grid[x][y].start_x + (grid[x][y].end_y - grid[x][y].start_y)
			length = maxi(int(float(length) / 4), 1)

			for _counter in range(length):
				for i in range(2):
					var starting_corner := rng.rand_int(4)
					var pt_x := 0
					var pt_y := 0
					var move_x := 0
					var move_y := 0

					if starting_corner == 0:
						pt_x = grid[x][y].start_x
						pt_y = grid[x][y].start_y
						if i == 0: move_x = 0; move_y = 1
						else: move_x = 1; move_y = 0
					elif starting_corner == 1:
						pt_x = grid[x][y].end_x - 1
						pt_y = grid[x][y].start_y
						if i == 0: move_x = -1; move_y = 0
						else: move_x = 0; move_y = 1
					elif starting_corner == 2:
						pt_x = grid[x][y].end_x - 1
						pt_y = grid[x][y].end_y - 1
						if i == 0: move_x = 0; move_y = -1
						else: move_x = -1; move_y = 0
					elif starting_corner == 3:
						pt_x = grid[x][y].start_x
						pt_y = grid[x][y].end_y - 1
						if i == 0: move_x = 1; move_y = 0
						else: move_x = 0; move_y = -1

					for _step in range(10):
						if pt_x < grid[x][y].start_x or pt_x >= grid[x][y].end_x: break
						if pt_y < grid[x][y].start_y or pt_y >= grid[x][y].end_y: break

						if dungeon_d.list_tiles[pt_x][pt_y].terrain_flags.terrain_type != DungeonData.TerrainType.TERRAIN_NORMAL:
							break

						# Check no adjacent hallways
						var found := false
						var direction := 0
						while direction < 8:
							var next_x: int = pt_x + DungeonData.LIST_DIRECTIONS[direction * 4]
							var next_y: int = pt_y + DungeonData.LIST_DIRECTIONS[direction * 4 + 2]
							for offset_x in range(-1, 2):
								for offset_y in range(-1, 2):
									if (dungeon_d.list_tiles[next_x + offset_x][next_y + offset_y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL):
										if dungeon_d.list_tiles[next_x + offset_x][next_y + offset_y].room_index == 0xFF:
											found = true
											break
								if found: break
							if found: break
							direction += 1

						if direction != 8:
							break

						# Check cardinal neighbor expectations
						var base := starting_corner * 8
						direction = 0
						var should_break := false
						while direction < 8:
							var next_x: int = pt_x + DungeonData.LIST_DIRECTIONS[direction * 4]
							var next_y: int = pt_y + DungeonData.LIST_DIRECTIONS[direction * 4 + 2]
							var is_open: bool
							if (dungeon_d.list_tiles[next_x][next_y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL or
								dungeon_d.list_tiles[next_x][next_y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_SECONDARY):
								is_open = true
							else:
								is_open = false
							if is_open != DungeonData.CORNER_CARDINAL_NEIGHBOR_EXPECT_OPEN[base + direction]:
								should_break = true
								break
							direction += 1
						if should_break:
							break

						dungeon_d.list_tiles[pt_x][pt_y].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_WALL
						added_imperfections_to_this_room = true
						pt_x += move_x
						pt_y += move_y

			if added_imperfections_to_this_room:
				_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)
				added_room_imperfections = true

	if added_room_imperfections:
		_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MAJOR, 9)

# ─── SetSpawnFlag5 ───

func _set_spawn_flag5(grid_cell: DungeonData.GridCell) -> void:
	for x in range(grid_cell.start_x, grid_cell.end_x):
		for y in range(grid_cell.start_y, grid_cell.end_y):
			dungeon_d.list_tiles[x][y].spawn_or_visibility_flags.spawn_flags_field_0x5 = true

# ─── GenerateSecondaryStructures ───

func _generate_secondary_structures(grid: Array, grid_size_x: int, grid_size_y: int) -> void:
	var generated := false

	for y in range(grid_size_y):
		for x in range(grid_size_x):
			if (grid[x][y].is_invalid or grid[x][y].is_monster_house or grid[x][y].is_merged or
				not grid[x][y].is_room or not grid[x][y].flag_secondary_structure or grid[x][y].flag_imperfect):
				continue

			var structure_type: int = rng.rand_int(6)
			var room_size_x: int = grid[x][y].end_x - grid[x][y].start_x
			var room_size_y: int = grid[x][y].end_y - grid[x][y].start_y
			var middle_x: int = int((grid[x][y].end_x + grid[x][y].start_x) / 2)
			var middle_y: int = int((grid[x][y].end_y + grid[x][y].start_y) / 2)

			if structure_type == DungeonData.SecondaryStructureType.SECONDARY_STRUCTURE_MAZE_PLUS_DOT and status.secondary_structures_budget > 0:
				status.secondary_structures_budget -= 1
				if room_size_x % 2 != 0 and room_size_y % 2 != 0:
					_set_spawn_flag5(grid[x][y])
					_generate_maze(grid[x][y], true)
				else:
					if room_size_x >= 5 and room_size_y >= 5:
						dungeon_d.list_tiles[middle_x][middle_y].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_SECONDARY
						dungeon_d.list_tiles[middle_x][middle_y - 1].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_SECONDARY
						dungeon_d.list_tiles[middle_x - 1][middle_y].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_SECONDARY
						dungeon_d.list_tiles[middle_x + 1][middle_y].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_SECONDARY
						dungeon_d.list_tiles[middle_x][middle_y + 1].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_SECONDARY
					else:
						dungeon_d.list_tiles[middle_x][middle_y].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_SECONDARY
				grid[x][y].has_secondary_structure = true
				_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)
				generated = true

			elif structure_type == DungeonData.SecondaryStructureType.SECONDARY_STRUCTURE_CHECKERBOARD and status.secondary_structures_budget > 0:
				if room_size_x % 2 != 0 and room_size_y % 2 != 0:
					status.secondary_structures_budget -= 1
					_set_spawn_flag5(grid[x][y])
					for _ci in range(64):
						var rand_x := rng.rand_int(room_size_x)
						var rand_y := rng.rand_int(room_size_y)
						if (rand_x + rand_y) % 2 != 0:
							dungeon_d.list_tiles[grid[x][y].start_x + rand_x][grid[x][y].start_y + rand_y].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_SECONDARY
					grid[x][y].has_secondary_structure = true
					_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)
					generated = true

			elif structure_type == DungeonData.SecondaryStructureType.SECONDARY_STRUCTURE_POOL:
				if room_size_x >= 5 and room_size_y >= 5:
					var rand_x1 := rng.rand_range(grid[x][y].start_x + 2, grid[x][y].end_x - 3)
					var rand_y1 := rng.rand_range(grid[x][y].start_y + 2, grid[x][y].end_y - 3)
					var rand_x2 := rng.rand_range(grid[x][y].start_x + 2, grid[x][y].end_x - 3)
					var rand_y2 := rng.rand_range(grid[x][y].start_y + 2, grid[x][y].end_y - 3)
					if status.secondary_structures_budget > 0:
						status.secondary_structures_budget -= 1
						_set_spawn_flag5(grid[x][y])
						if rand_x1 > rand_x2:
							var tmp := rand_x1; rand_x1 = rand_x2; rand_x2 = tmp
						if rand_y1 > rand_y2:
							var tmp := rand_y1; rand_y1 = rand_y2; rand_y2 = tmp
						for cur_x in range(rand_x1, rand_x2 + 1):
							for cur_y in range(rand_y1, rand_y2 + 1):
								dungeon_d.list_tiles[cur_x][cur_y].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_SECONDARY
						grid[x][y].has_secondary_structure = true
						_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)
						generated = true

			elif structure_type == DungeonData.SecondaryStructureType.SECONDARY_STRUCTURE_ISLAND:
				if room_size_x >= 6 and room_size_y >= 6:
					if status.secondary_structures_budget > 0:
						status.secondary_structures_budget -= 1
						_set_spawn_flag5(grid[x][y])
						# Water moat (island pattern)
						var offsets := [
							[-2,-2],[-1,-2],[0,-2],[1,-2],
							[-2,-1],[-2,0],[-2,1],
							[2,-2],[2,-1],[2,0],[2,1],
							[-1,1],[0,1],[1,1],
							[1,-1],[1,0],[-1,-1],[-1,0]
						]
						for off in offsets:
							dungeon_d.list_tiles[middle_x + off[0]][middle_y + off[1]].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_SECONDARY
							dungeon_d.list_tiles[middle_x + off[0]][middle_y + off[1]].terrain_flags.f_corner_cuttable = true

						# Items on the island center
						dungeon_d.list_tiles[middle_x][middle_y].spawn_or_visibility_flags.f_item = true
						dungeon_d.list_tiles[middle_x - 1][middle_y].spawn_or_visibility_flags.f_item = true
						dungeon_d.list_tiles[middle_x + 1][middle_y].spawn_or_visibility_flags.f_item = true
						dungeon_d.list_tiles[middle_x][middle_y - 1].spawn_or_visibility_flags.f_item = true
						dungeon_d.list_tiles[middle_x - 1][middle_y - 1].spawn_or_visibility_flags.f_item = true
						dungeon_d.list_tiles[middle_x + 1][middle_y - 1].spawn_or_visibility_flags.f_item = true

						# Warp tile
						dungeon_d.list_tiles[middle_x][middle_y].spawn_or_visibility_flags.f_trap = true

						grid[x][y].has_secondary_structure = true
						_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)
						generated = true

			elif structure_type == DungeonData.SecondaryStructureType.SECONDARY_STRUCTURE_DIVIDER and status.secondary_structures_budget > 0:
				status.secondary_structures_budget -= 1
				_set_spawn_flag5(grid[x][y])
				var valid := true

				if rng.rand_int(2) == 0:
					# Horizontal divider
					for ci in range(grid[x][y].start_x, grid[x][y].end_x):
						if _is_next_to_hallway(ci, middle_y):
							valid = false
							break
					if valid:
						for ci in range(grid[x][y].start_x, grid[x][y].end_x):
							dungeon_d.list_tiles[ci][middle_y].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_SECONDARY
						for cur_x in range(grid[x][y].start_x, grid[x][y].end_x):
							for cur_y in range(grid[x][y].start_y, grid[x][y].end_y):
								dungeon_d.list_tiles[cur_x][cur_y].spawn_or_visibility_flags.spawn_flags_field_0x7 = true
						grid[x][y].has_secondary_structure = true
						_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)
						generated = true
				else:
					# Vertical divider
					for ci in range(grid[x][y].start_y, grid[x][y].end_y):
						if _is_next_to_hallway(middle_x, ci):
							valid = false
							break
					if valid:
						for ci in range(grid[x][y].start_y, grid[x][y].end_y):
							dungeon_d.list_tiles[middle_x][ci].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_SECONDARY
						for cur_x in range(grid[x][y].start_x, grid[x][y].end_x):
							for cur_y in range(grid[x][y].start_y, grid[x][y].end_y):
								dungeon_d.list_tiles[cur_x][cur_y].spawn_or_visibility_flags.spawn_flags_field_0x7 = true
						grid[x][y].has_secondary_structure = true
						_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)
						generated = true

	if generated:
		_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MAJOR, 10)

# ─── Layout Generators ───

func _generate_standard_floor(grid_size_x: int, grid_size_y: int, floor_props: DungeonData.FloorProperties) -> void:
	var positions := _get_grid_positions(grid_size_x, grid_size_y)
	var list_x: Array = positions.list_x
	var list_y: Array = positions.list_y
	grid_cell_start_x = list_x
	grid_cell_start_y = list_y

	var grid := _init_dungeon_grid(grid_size_x, grid_size_y)
	_assign_rooms(grid, grid_size_x, grid_size_y, floor_props.room_density)
	_create_rooms_and_anchors(grid, grid_size_x, grid_size_y, list_x, list_y, floor_props, floor_props.room_flags)

	var cursor_x := rng.rand_int(grid_size_x)
	var cursor_y := rng.rand_int(grid_size_y)
	_assign_grid_cell_connections(grid, grid_size_x, grid_size_y, cursor_x, cursor_y, floor_props)
	_create_grid_cell_connections(grid, grid_size_x, grid_size_y, list_x, list_y, false)
	_ensure_connected_grid(grid, grid_size_x, grid_size_y, list_x, list_y)

	_generate_maze_room(grid, grid_size_x, grid_size_y, floor_props.maze_room_chance)
	_generate_kecleon_shop(grid, grid_size_x, grid_size_y, status.kecleon_shop_chance)
	_generate_monster_house(grid, grid_size_x, grid_size_y, status.monster_house_chance)
	_generate_extra_hallways(grid, grid_size_x, grid_size_y, floor_props.num_extra_hallways)
	_generate_room_imperfections(grid, grid_size_x, grid_size_y)
	_generate_secondary_structures(grid, grid_size_x, grid_size_y)

func _generate_one_room_monster_house_floor() -> void:
	var grid := _init_dungeon_grid(1, 1)
	grid[0][0].start_x = 2
	grid[0][0].end_x = 0x36
	grid[0][0].start_y = 2
	grid[0][0].end_y = 0x1E
	grid[0][0].is_room = true
	grid[0][0].is_cell_connected = true
	grid[0][0].is_invalid = false

	for cx in range(grid[0][0].start_x, grid[0][0].end_x):
		for cy in range(grid[0][0].start_y, grid[0][0].end_y):
			dungeon_d.list_tiles[cx][cy].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_NORMAL
			dungeon_d.list_tiles[cx][cy].room_index = 0

	_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MAJOR, 11)
	_generate_monster_house(grid, 1, 1, 999)

func _generate_outer_ring_floor(floor_props: DungeonData.FloorProperties) -> void:
	var grid_size_x := 6
	var grid_size_y := 4
	var list_x := [0, 5, 0x10, 0x1C, 0x27, 0x33, 0x38]
	var list_y := [2, 7, 0x10, 0x19, 0x1E]
	grid_cell_start_x = list_x
	grid_cell_start_y = list_y

	var grid := _init_dungeon_grid(grid_size_x, grid_size_y)

	for gx in range(grid_size_x):
		grid[gx][0].is_room = false
		grid[gx][grid_size_y - 1].is_room = false
	for gy in range(grid_size_y):
		grid[0][gy].is_room = false
		grid[grid_size_x - 1][gy].is_room = false
	for gx in range(1, grid_size_x - 1):
		for gy in range(1, grid_size_y - 1):
			grid[gx][gy].is_room = true

	var cur_room_index := 0
	for gy in range(grid_size_y):
		for gx in range(grid_size_x):
			if grid[gx][gy].is_room:
				var rx: int = list_x[gx + 1] - list_x[gx] - 3
				var ry: int = list_y[gy + 1] - list_y[gy] - 3
				var rsx := rng.rand_range(5, rx)
				var rsy := rng.rand_range(4, ry)
				var sx: int = rng.rand_int(rx - rsx) + list_x[gx] + 2
				var sy: int = rng.rand_int(ry - rsy) + list_y[gy] + 2
				grid[gx][gy].start_x = sx
				grid[gx][gy].start_y = sy
				grid[gx][gy].end_x = sx + rsx
				grid[gx][gy].end_y = sy + rsy
				for cx in range(grid[gx][gy].start_x, grid[gx][gy].end_x):
					for cy in range(grid[gx][gy].start_y, grid[gx][gy].end_y):
						dungeon_d.list_tiles[cx][cy].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_NORMAL
						dungeon_d.list_tiles[cx][cy].room_index = cur_room_index
				cur_room_index += 1
				_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)
			else:
				var sx: int = rng.rand_range(list_x[gx] + 1, list_x[gx + 1] - 2)
				var sy: int = rng.rand_range(list_y[gy] + 1, list_y[gy + 1] - 2)
				grid[gx][gy].start_x = sx
				grid[gx][gy].start_y = sy
				grid[gx][gy].end_x = sx + 1
				grid[gx][gy].end_y = sy + 1
				dungeon_d.list_tiles[sx][sy].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_NORMAL
				dungeon_d.list_tiles[sx][sy].room_index = 0xFF
				_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)

	_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MAJOR, 12)

	# Set outer ring connections
	grid[0][0].connected_to_right = true; grid[1][0].connected_to_left = true
	grid[1][0].connected_to_right = true; grid[2][0].connected_to_left = true
	grid[2][0].connected_to_right = true; grid[3][0].connected_to_left = true
	grid[3][0].connected_to_right = true; grid[4][0].connected_to_left = true
	grid[4][0].connected_to_right = true; grid[5][0].connected_to_left = true
	grid[0][0].connected_to_bottom = true; grid[0][1].connected_to_top = true
	grid[0][1].connected_to_bottom = true; grid[0][2].connected_to_top = true
	grid[0][2].connected_to_bottom = true; grid[0][3].connected_to_top = true
	grid[0][3].connected_to_right = true; grid[1][3].connected_to_left = true
	grid[1][3].connected_to_right = true; grid[2][3].connected_to_left = true
	grid[2][3].connected_to_right = true; grid[3][3].connected_to_left = true
	grid[3][3].connected_to_right = true; grid[4][3].connected_to_left = true
	grid[4][3].connected_to_right = true; grid[5][3].connected_to_left = true
	grid[5][0].connected_to_bottom = true; grid[5][1].connected_to_top = true
	grid[5][1].connected_to_bottom = true; grid[5][2].connected_to_top = true
	grid[5][2].connected_to_bottom = true; grid[5][3].connected_to_top = true

	var cursor_x := rng.rand_int(grid_size_x)
	var cursor_y := rng.rand_int(grid_size_y)
	_assign_grid_cell_connections(grid, grid_size_x, grid_size_y, cursor_x, cursor_y, floor_props)
	_create_grid_cell_connections(grid, grid_size_x, grid_size_y, list_x, list_y, false)
	_ensure_connected_grid(grid, grid_size_x, grid_size_y, list_x, list_y)
	_generate_kecleon_shop(grid, grid_size_x, grid_size_y, status.kecleon_shop_chance)
	_generate_monster_house(grid, grid_size_x, grid_size_y, status.monster_house_chance)
	_generate_extra_hallways(grid, grid_size_x, grid_size_y, floor_props.num_extra_hallways)
	_generate_room_imperfections(grid, grid_size_x, grid_size_y)

func _generate_crossroads_floor(floor_props: DungeonData.FloorProperties) -> void:
	var grid_size_x := 5
	var grid_size_y := 4
	var list_x := [0, 0x0B, 0x16, 0x21, 0x2C, 0x38]
	var list_y := [1, 9, 0x10, 0x17, 0x1F]
	grid_cell_start_x = list_x
	grid_cell_start_y = list_y

	var grid := _init_dungeon_grid(grid_size_x, grid_size_y)

	for gx in range(grid_size_x):
		grid[gx][0].is_room = true
		grid[gx][grid_size_y - 1].is_room = true
	for gy in range(grid_size_y):
		grid[0][gy].is_room = true
		grid[grid_size_x - 1][gy].is_room = true
	for gx in range(1, grid_size_x - 1):
		for gy in range(1, grid_size_y - 1):
			grid[gx][gy].is_room = false

	grid[0][0].is_invalid = true
	grid[0][grid_size_y - 1].is_invalid = true
	grid[grid_size_x - 1][0].is_invalid = true
	grid[grid_size_x - 1][grid_size_y - 1].is_invalid = true

	var cur_room_index := 0
	for gy in range(grid_size_y):
		for gx in range(grid_size_x):
			if grid[gx][gy].is_invalid: continue
			if grid[gx][gy].is_room:
				var rx: int = list_x[gx + 1] - list_x[gx] - 3
				var ry: int = list_y[gy + 1] - list_y[gy] - 3
				var rsx := rng.rand_range(5, rx)
				var rsy := rng.rand_range(4, ry)
				var sx: int = rng.rand_int(rx - rsx) + list_x[gx] + 2
				var sy: int = rng.rand_int(ry - rsy) + list_y[gy] + 2
				grid[gx][gy].start_x = sx; grid[gx][gy].start_y = sy
				grid[gx][gy].end_x = sx + rsx; grid[gx][gy].end_y = sy + rsy
				for cx in range(sx, sx + rsx):
					for cy in range(sy, sy + rsy):
						dungeon_d.list_tiles[cx][cy].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_NORMAL
						dungeon_d.list_tiles[cx][cy].room_index = cur_room_index
				cur_room_index += 1
				_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)
			else:
				var sx: int = rng.rand_range(list_x[gx] + 1, list_x[gx + 1] - 2)
				var sy: int = rng.rand_range(list_y[gy] + 1, list_y[gy + 1] - 2)
				grid[gx][gy].start_x = sx; grid[gx][gy].start_y = sy
				grid[gx][gy].end_x = sx + 1; grid[gx][gy].end_y = sy + 1
				dungeon_d.list_tiles[sx][sy].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_NORMAL
				dungeon_d.list_tiles[sx][sy].room_index = 0xFF
				_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)

	_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MAJOR, 14)

	for gx in range(1, grid_size_x - 1):
		for gy in range(0, grid_size_y - 1):
			grid[gx][gy].connected_to_bottom = true
			grid[gx][gy + 1].connected_to_top = true
	for gx in range(0, grid_size_x - 1):
		for gy in range(1, grid_size_y - 1):
			grid[gx][gy].connected_to_right = true
			grid[gx + 1][gy].connected_to_left = true

	_create_grid_cell_connections(grid, grid_size_x, grid_size_y, list_x, list_y, true)
	_ensure_connected_grid(grid, grid_size_x, grid_size_y, list_x, list_y)
	_generate_kecleon_shop(grid, grid_size_x, grid_size_y, status.kecleon_shop_chance)
	_generate_monster_house(grid, grid_size_x, grid_size_y, status.monster_house_chance)
	_generate_extra_hallways(grid, grid_size_x, grid_size_y, floor_props.num_extra_hallways)
	_generate_room_imperfections(grid, grid_size_x, grid_size_y)

func _generate_two_rooms_with_monster_house_floor() -> void:
	var grid_size_x := 2
	var grid_size_y := 1
	var list_x := [2, 0x1C, 0x36]
	var list_y := [2, 0x1E]
	grid_cell_start_x = list_x
	grid_cell_start_y = list_y

	var grid := _init_dungeon_grid(grid_size_x, grid_size_y)
	var cur_room_index := 0

	for gx in range(grid_size_x):
		var rx: int = list_x[gx + 1] - list_x[gx] - 3
		var ry: int = list_y[1] - list_y[0] - 3
		var rsx := rng.rand_range(10, rx)
		var rsy := rng.rand_range(16, ry)
		var sx: int = rng.rand_int(rx - rsx) + list_x[gx] + 1
		var sy: int = rng.rand_int(ry - rsy) + list_y[0] + 1
		grid[gx][0].start_x = sx; grid[gx][0].start_y = sy
		grid[gx][0].end_x = sx + rsx; grid[gx][0].end_y = sy + rsy
		for cx in range(sx, sx + rsx):
			for cy in range(sy, sy + rsy):
				dungeon_d.list_tiles[cx][cy].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_NORMAL
				dungeon_d.list_tiles[cx][cy].room_index = cur_room_index
		cur_room_index += 1
		_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)

	_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MAJOR, 15)
	grid[0][0].connected_to_right = true
	grid[1][0].connected_to_left = true
	_create_grid_cell_connections(grid, grid_size_x, grid_size_y, list_x, list_y, false)
	_generate_monster_house(grid, grid_size_x, grid_size_y, 999)

func _generate_line_floor(floor_props: DungeonData.FloorProperties) -> void:
	var grid_size_x := 5
	var grid_size_y := 1
	var list_x := [0, 0x0B, 0x16, 0x21, 0x2C, 0x38]
	var list_y := [4, 0x0F]
	grid_cell_start_x = list_x
	grid_cell_start_y = list_y

	var grid := _init_dungeon_grid(grid_size_x, grid_size_y)
	_assign_rooms(grid, grid_size_x, grid_size_y, floor_props.room_density)
	_create_rooms_and_anchors(grid, grid_size_x, grid_size_y, list_x, list_y, floor_props, floor_props.room_flags)

	var cursor_x := rng.rand_int(grid_size_x)
	var cursor_y := rng.rand_int(grid_size_y)
	_assign_grid_cell_connections(grid, grid_size_x, grid_size_y, cursor_x, cursor_y, floor_props)
	_create_grid_cell_connections(grid, grid_size_x, grid_size_y, list_x, list_y, true)
	_ensure_connected_grid(grid, grid_size_x, grid_size_y, list_x, list_y)
	_generate_kecleon_shop(grid, grid_size_x, grid_size_y, status.kecleon_shop_chance)
	_generate_monster_house(grid, grid_size_x, grid_size_y, status.monster_house_chance)
	_generate_extra_hallways(grid, grid_size_x, grid_size_y, floor_props.num_extra_hallways)
	_generate_room_imperfections(grid, grid_size_x, grid_size_y)

func _generate_cross_floor(floor_props: DungeonData.FloorProperties) -> void:
	var grid_size_x := 3
	var grid_size_y := 3
	var list_x := [0x0B, 0x16, 0x21, 0x2C]
	var list_y := [2, 0x0B, 0x14, 0x1E]
	grid_cell_start_x = list_x
	grid_cell_start_y = list_y

	var grid := _init_dungeon_grid(grid_size_x, grid_size_y)
	for gx in range(grid_size_x):
		for gy in range(grid_size_y):
			grid[gx][gy].is_room = true

	grid[0][0].is_invalid = true
	grid[0][grid_size_y - 1].is_invalid = true
	grid[grid_size_x - 1][0].is_invalid = true
	grid[grid_size_x - 1][grid_size_y - 1].is_invalid = true

	_create_rooms_and_anchors(grid, grid_size_x, grid_size_y, list_x, list_y, floor_props, floor_props.room_flags)

	grid[1][0].connected_to_bottom = true; grid[1][1].connected_to_top = true
	grid[1][1].connected_to_bottom = true; grid[1][2].connected_to_top = true
	grid[0][1].connected_to_right = true; grid[1][1].connected_to_left = true
	grid[1][1].connected_to_right = true; grid[2][1].connected_to_left = true

	_create_grid_cell_connections(grid, grid_size_x, grid_size_y, list_x, list_y, true)
	_ensure_connected_grid(grid, grid_size_x, grid_size_y, list_x, list_y)
	_generate_kecleon_shop(grid, grid_size_x, grid_size_y, status.kecleon_shop_chance)
	_generate_monster_house(grid, grid_size_x, grid_size_y, status.monster_house_chance)
	_generate_extra_hallways(grid, grid_size_x, grid_size_y, floor_props.num_extra_hallways)
	_generate_room_imperfections(grid, grid_size_x, grid_size_y)

func _merge_rooms_vertically(room_x: int, room_y1: int, room_dy: int, grid: Array) -> void:
	var room_y2 := room_y1 + room_dy
	var sx: int = mini(grid[room_x][room_y1].start_x, grid[room_x][room_y2].start_x)
	var ex: int = maxi(grid[room_x][room_y1].end_x, grid[room_x][room_y2].end_x)
	var sy: int = grid[room_x][room_y1].start_y
	var ey: int = grid[room_x][room_y2].end_y
	var merge_room_index: int = dungeon_d.list_tiles[grid[room_x][room_y1].start_x][grid[room_x][room_y1].start_y].room_index
	for cx in range(sx, ex):
		for cy in range(sy, ey):
			dungeon_d.list_tiles[cx][cy].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_NORMAL
			dungeon_d.list_tiles[cx][cy].room_index = merge_room_index
	grid[room_x][room_y1].start_x = sx; grid[room_x][room_y1].end_x = ex
	grid[room_x][room_y1].start_y = sy; grid[room_x][room_y1].end_y = ey
	grid[room_x][room_y1].is_merged = true
	grid[room_x][room_y2].is_merged = true
	grid[room_x][room_y2].is_cell_connected = false
	grid[room_x][room_y2].has_been_merged = true
	_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)

func _generate_beetle_floor(floor_props: DungeonData.FloorProperties) -> void:
	var grid_size_x := 3
	var grid_size_y := 3
	var list_x := [0x05, 0x0F, 0x23, 0x32]
	var list_y := [2, 0x0B, 0x14, 0x1E]
	grid_cell_start_x = list_x
	grid_cell_start_y = list_y

	var grid := _init_dungeon_grid(grid_size_x, grid_size_y)
	for gx in range(grid_size_x):
		for gy in range(grid_size_y):
			grid[gx][gy].is_room = true

	_create_rooms_and_anchors(grid, grid_size_x, grid_size_y, list_x, list_y, floor_props, floor_props.room_flags)

	for gy in range(grid_size_y):
		grid[0][gy].connected_to_right = true
		grid[1][gy].connected_to_left = true
		grid[1][gy].connected_to_right = true
		grid[2][gy].connected_to_left = true

	_create_grid_cell_connections(grid, grid_size_x, grid_size_y, list_x, list_y, true)
	_merge_rooms_vertically(1, 0, 1, grid)
	_merge_rooms_vertically(1, 0, 2, grid)
	_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MAJOR, 16)
	_ensure_connected_grid(grid, grid_size_x, grid_size_y, list_x, list_y)
	_generate_kecleon_shop(grid, grid_size_x, grid_size_y, status.kecleon_shop_chance)
	_generate_monster_house(grid, grid_size_x, grid_size_y, status.monster_house_chance)
	_generate_extra_hallways(grid, grid_size_x, grid_size_y, floor_props.num_extra_hallways)
	_generate_room_imperfections(grid, grid_size_x, grid_size_y)

func _generate_outer_rooms_floor(grid_size_x: int, grid_size_y: int, floor_props: DungeonData.FloorProperties) -> void:
	var positions := _get_grid_positions(grid_size_x, grid_size_y)
	var list_x: Array = positions.list_x
	var list_y: Array = positions.list_y
	grid_cell_start_x = list_x
	grid_cell_start_y = list_y

	var grid := _init_dungeon_grid(grid_size_x, grid_size_y)

	for gx in range(grid_size_x):
		for gy in range(grid_size_y):
			grid[gx][gy].is_room = true

	for gx in range(1, grid_size_x - 1):
		for gy in range(1, grid_size_y - 1):
			grid[gx][gy].is_invalid = true

	_create_rooms_and_anchors(grid, grid_size_x, grid_size_y, list_x, list_y, floor_props, floor_props.room_flags)

	if adv_settings.fix_generate_outer_rooms_floor_error:
		for gx in range(grid_size_x):
			if gx > 0:
				grid[gx][0].connected_to_left = true
				grid[gx][grid_size_y - 1].connected_to_left = true
			if gx < grid_size_x - 1:
				grid[gx + 1][0].connected_to_right = true
				grid[gx + 1][grid_size_y - 1].connected_to_right = true
		for gy in range(grid_size_y):
			if gy > 0:
				grid[0][gy].connected_to_top = true
				grid[grid_size_x - 1][gy].connected_to_top = true
			if gy < grid_size_y - 1:
				grid[0][gy + 1].connected_to_bottom = true
				grid[grid_size_x - 1][gy + 1].connected_to_bottom = true
	else:
		for gx in range(grid_size_x):
			if gx > 0:
				grid[gx][0].connected_to_left = true
				grid[gx][grid_size_y - 1].connected_to_left = true
			if gx < grid_size_x - 1:
				grid[gx + 1][grid_size_y - 1].connected_to_left = true
		for gy in range(grid_size_y):
			if gy > 0:
				grid[0][gy].connected_to_top = true
				grid[grid_size_x - 1][gy].connected_to_top = true
			if gy < grid_size_y - 2:
				grid[0][gy].connected_to_bottom = true
				grid[grid_size_x - 1][gy].connected_to_bottom = true

	_create_grid_cell_connections(grid, grid_size_x, grid_size_y, list_x, list_y, false)
	_ensure_connected_grid(grid, grid_size_x, grid_size_y, list_x, list_y)
	_generate_maze_room(grid, grid_size_x, grid_size_y, floor_props.maze_room_chance)
	_generate_kecleon_shop(grid, grid_size_x, grid_size_y, status.kecleon_shop_chance)
	_generate_monster_house(grid, grid_size_x, grid_size_y, status.monster_house_chance)
	_generate_extra_hallways(grid, grid_size_x, grid_size_y, floor_props.num_extra_hallways)
	_generate_room_imperfections(grid, grid_size_x, grid_size_y)
	_generate_secondary_structures(grid, grid_size_x, grid_size_y)

# ─── Post-generation functions ───

func _reset_inner_boundary_tile_rows() -> void:
	for x in range(DungeonData.FLOOR_MAX_X):
		dungeon_d.list_tiles[x][1] = DungeonData.Tile.new()
		if x == 0 or x == DungeonData.FLOOR_MAX_X - 1:
			dungeon_d.list_tiles[x][1].terrain_flags.f_impassable_wall = true
		dungeon_d.list_tiles[x][0x1E] = DungeonData.Tile.new()
		if x == 0 or x == DungeonData.FLOOR_MAX_X - 1:
			dungeon_d.list_tiles[x][0x1E].terrain_flags.f_impassable_wall = true

func _ensure_impassable_tiles_are_walls() -> void:
	for x in range(DungeonData.FLOOR_MAX_X):
		for y in range(DungeonData.FLOOR_MAX_Y):
			if dungeon_d.list_tiles[x][y].terrain_flags.f_impassable_wall:
				dungeon_d.list_tiles[x][y].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_WALL

func _set_secondary_terrain_on_wall(tile: DungeonData.Tile) -> void:
	if tile.terrain_flags.f_impassable_wall or tile.terrain_flags.terrain_type != DungeonData.TerrainType.TERRAIN_WALL:
		return
	tile.terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_SECONDARY

func _finalize_junctions() -> void:
	for x in range(DungeonData.FLOOR_MAX_X):
		for y in range(DungeonData.FLOOR_MAX_Y):
			if dungeon_d.list_tiles[x][y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL and dungeon_d.list_tiles[x][y].room_index == 0xFF:
				# Hallway tile - check for adjacent rooms
				if x > 0 and dungeon_d.list_tiles[x - 1][y].room_index != 0xFF and dungeon_d.list_tiles[x - 1][y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL:
					dungeon_d.list_tiles[x - 1][y].terrain_flags.f_natural_junction = true
					if dungeon_d.list_tiles[x - 1][y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_SECONDARY:
						dungeon_d.list_tiles[x - 1][y].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_NORMAL
				elif y > 0 and dungeon_d.list_tiles[x][y - 1].room_index != 0xFF and dungeon_d.list_tiles[x][y - 1].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL:
					dungeon_d.list_tiles[x][y - 1].terrain_flags.f_natural_junction = true
					if dungeon_d.list_tiles[x][y - 1].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_SECONDARY:
						dungeon_d.list_tiles[x][y - 1].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_NORMAL
				elif y < DungeonData.FLOOR_MAX_Y - 1 and dungeon_d.list_tiles[x][y + 1].room_index != 0xFF and dungeon_d.list_tiles[x][y + 1].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL:
					dungeon_d.list_tiles[x][y + 1].terrain_flags.f_natural_junction = true
					if dungeon_d.list_tiles[x][y + 1].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_SECONDARY:
						dungeon_d.list_tiles[x][y + 1].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_NORMAL
				elif x < DungeonData.FLOOR_MAX_X - 1 and dungeon_d.list_tiles[x + 1][y].room_index != 0xFF and dungeon_d.list_tiles[x + 1][y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL:
					dungeon_d.list_tiles[x + 1][y].terrain_flags.f_natural_junction = true
					if dungeon_d.list_tiles[x + 1][y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_SECONDARY:
						dungeon_d.list_tiles[x + 1][y].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_NORMAL
			elif dungeon_d.list_tiles[x][y].room_index == 0xFE:
				dungeon_d.list_tiles[x][y].room_index = 0xFF

# ─── GenerateSecondaryTerrainFormations ───

func _generate_secondary_terrain_formations(test_flag: bool, floor_props: DungeonData.FloorProperties) -> void:
	if not floor_props.room_flags.f_secondary_terrain_generation or not test_flag:
		return

	var num_to_gen: int = [1, 1, 1, 2, 2, 2, 3, 3][rng.rand_int(8)]

	for _i in range(num_to_gen):
		var pt_x: int
		var pt_y: int
		var dir_x: int
		var dir_y: int
		var dir_y_upwards: bool

		if rng.rand_int(100) < 50:
			pt_y = DungeonData.FLOOR_MAX_Y - 1
			dir_y = -1
			dir_y_upwards = true
		else:
			pt_y = 0
			dir_y = 1
			dir_y_upwards = false

		var steps_until_lake := rng.rand_int(50) + 10
		pt_x = rng.rand_range(2, DungeonData.FLOOR_MAX_X - 2)
		dir_x = 0

		var done := false
		while not done:
			var generated_river_tiles := false
			var num_tiles_fill := rng.rand_int(6) + 2

			for _v in range(num_tiles_fill):
				if pt_x >= 0 and pt_x < DungeonData.FLOOR_MAX_X:
					var tile: DungeonData.Tile
					if pt_y >= 0 and pt_y < DungeonData.FLOOR_MAX_Y:
						tile = dungeon_d.list_tiles[pt_x][pt_y]
					else:
						tile = _default_tile
					if tile.terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_SECONDARY:
						done = true
						if generated_river_tiles:
							_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)
						break

					if not _pos_is_out_of_bounds(pt_x, pt_y):
						_set_secondary_terrain_on_wall(dungeon_d.list_tiles[pt_x][pt_y])
						generated_river_tiles = true

				pt_x += dir_x
				pt_y += dir_y
				if pt_y < 0 or pt_y >= DungeonData.FLOOR_MAX_Y:
					break

			if done:
				break

			steps_until_lake -= 1

			if steps_until_lake != 0:
				if dir_x != 0:
					if dir_y_upwards: dir_y = -1
					else: dir_y = 1
					dir_x = 0
				else:
					if rng.rand_int(100) < 50: dir_x = -1
					else: dir_x = 1
					dir_y = 0
				continue

			if generated_river_tiles:
				_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)

			# Generate lake
			for _j in range(64):
				var offset_x := rng.rand_int(7) - 3
				var offset_y := rng.rand_int(7) - 3
				var target_x := pt_x + offset_x
				var target_y := pt_y + offset_y

				if target_x >= 2 and target_x < DungeonData.FLOOR_MAX_X - 2 and target_y >= 2 and target_y < DungeonData.FLOOR_MAX_Y - 2:
					var num_adjacent := 0
					for lx in range(-1, 2):
						for ly in range(-1, 2):
							if lx == 0 and ly == 0: continue
							if dungeon_d.list_tiles[target_x + lx][target_y + ly].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_SECONDARY:
								num_adjacent += 1
					if num_adjacent >= 4:
						if not _pos_is_out_of_bounds(target_x, target_y):
							_set_secondary_terrain_on_wall(dungeon_d.list_tiles[target_x][target_y])

			_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)

			if not done:
				if dir_x != 0:
					if dir_y_upwards: dir_y = -1
					else: dir_y = 1
					dir_x = 0
				else:
					if rng.rand_int(100) < 50: dir_x = -1
					else: dir_x = 1
					dir_y = 0

			if pt_y < 0 or pt_y >= DungeonData.FLOOR_MAX_Y:
				done = true

	# Standalone lakes
	for _i in range(floor_props.secondary_terrain_density):
		var attempts := 0
		var rnd_x := 0
		var rnd_y := 0

		while attempts < 200:
			rnd_x = rng.rand_int(DungeonData.FLOOR_MAX_X)
			rnd_y = rng.rand_int(DungeonData.FLOOR_MAX_Y)
			if rnd_x >= 1 and rnd_x < DungeonData.FLOOR_MAX_X - 1 and rnd_y >= 1 and rnd_y < DungeonData.FLOOR_MAX_Y - 1:
				break
			attempts += 1

		if attempts == 200: continue

		var table: Array = []
		for tx in range(10):
			var row: Array = []
			for ty in range(10):
				if tx == 0 or ty == 0 or tx == 9 or ty == 9:
					row.append(true)
				else:
					row.append(false)
			table.append(row)

		for _v in range(80):
			var tx := rng.rand_int(8) + 1
			var ty := rng.rand_int(8) + 1
			if table[tx - 1][ty] or table[tx + 1][ty] or table[tx][ty - 1] or table[tx][ty + 1]:
				table[tx][ty] = true

		for tx in range(10):
			for ty in range(10):
				if not table[tx][ty]:
					if not _pos_is_out_of_bounds(rnd_x + tx - 5, rnd_y + ty - 5):
						_set_secondary_terrain_on_wall(dungeon_d.list_tiles[rnd_x + tx - 5][rnd_y + ty - 5])
					else:
						_set_secondary_terrain_on_wall(_default_tile)

		_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)

	# Clean up secondary terrain
	for x in range(DungeonData.FLOOR_MAX_X):
		for y in range(DungeonData.FLOOR_MAX_Y):
			if dungeon_d.list_tiles[x][y].terrain_flags.terrain_type != DungeonData.TerrainType.TERRAIN_SECONDARY:
				continue
			if dungeon_d.list_tiles[x][y].terrain_flags.f_in_kecleon_shop:
				dungeon_d.list_tiles[x][y].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_NORMAL
			elif x <= 1 or x >= DungeonData.FLOOR_MAX_X - 1 or y <= 1 or y >= DungeonData.FLOOR_MAX_Y - 1:
				dungeon_d.list_tiles[x][y].terrain_flags.terrain_type = DungeonData.TerrainType.TERRAIN_WALL

	_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MAJOR, 17)

# ─── SpawnStairs ───

func _spawn_stairs(x: int, y: int, hidden_stairs_type: int) -> void:
	dungeon_d.list_tiles[x][y].spawn_or_visibility_flags.f_item = false
	dungeon_d.list_tiles[x][y].spawn_or_visibility_flags.f_stairs = true

	if hidden_stairs_type == DungeonData.HiddenStairsType.HIDDEN_STAIRS_NONE:
		gen_info.stairs_spawn_x = x
		gen_info.stairs_spawn_y = y
		status.stairs_room_index = dungeon_d.list_tiles[x][y].room_index
	else:
		if status.second_spawn:
			status.hidden_stairs_spawn_x = x
			status.hidden_stairs_spawn_y = y
		else:
			gen_info.hidden_stairs_spawn_x = x
			gen_info.hidden_stairs_spawn_y = y
		gen_info.hidden_stairs_type = hidden_stairs_type

	if hidden_stairs_type == DungeonData.HiddenStairsType.HIDDEN_STAIRS_NONE and _get_floor_type() == DungeonData.FloorType.FLOOR_TYPE_RESCUE:
		var room_index: int = dungeon_d.list_tiles[x][y].room_index
		for cx in range(DungeonData.FLOOR_MAX_X):
			for cy in range(DungeonData.FLOOR_MAX_Y):
				if (dungeon_d.list_tiles[cx][cy].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL and
					dungeon_d.list_tiles[cx][cy].room_index == room_index):
					dungeon_d.list_tiles[cx][cy].terrain_flags.f_in_monster_house = true
					gen_info.monster_house_room = dungeon_d.list_tiles[x][y].room_index
	_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)

# ─── ShuffleSpawnPositions ───

func _shuffle_spawn_positions(spawn_x: Array, spawn_y: Array) -> void:
	for _i in range(spawn_x.size() * 2):
		var a := rng.rand_int(spawn_x.size())
		var b := rng.rand_int(spawn_x.size())
		var tmp_x = spawn_x[a]; spawn_x[a] = spawn_x[b]; spawn_x[b] = tmp_x
		var tmp_y = spawn_y[a]; spawn_y[a] = spawn_y[b]; spawn_y[b] = tmp_y

# ─── SpawnNonEnemies ───

func _spawn_non_enemies(floor_props: DungeonData.FloorProperties, is_empty_monster_house: bool) -> void:
	# Spawn Stairs
	if gen_info.stairs_spawn_x == -1 or gen_info.stairs_spawn_y == -1:
		var stairs_valid_x: Array = []
		var stairs_valid_y: Array = []
		for x in range(DungeonData.FLOOR_MAX_X):
			for y in range(DungeonData.FLOOR_MAX_Y):
				if (dungeon_d.list_tiles[x][y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL and
					dungeon_d.list_tiles[x][y].room_index != 0xFF and
					not dungeon_d.list_tiles[x][y].terrain_flags.f_in_kecleon_shop and
					not dungeon_d.list_tiles[x][y].spawn_or_visibility_flags.f_monster and
					not dungeon_d.list_tiles[x][y].spawn_or_visibility_flags.f_special_tile and
					not dungeon_d.list_tiles[x][y].terrain_flags.f_natural_junction):
					stairs_valid_x.append(x)
					stairs_valid_y.append(y)

		if stairs_valid_x.size() > 0:
			var stairs_index := rng.rand_int(stairs_valid_x.size())
			_spawn_stairs(stairs_valid_x[stairs_index], stairs_valid_y[stairs_index], DungeonData.HiddenStairsType.HIDDEN_STAIRS_NONE)

			if status.hidden_stairs_type != DungeonData.HiddenStairsType.HIDDEN_STAIRS_NONE:
				stairs_valid_x.remove_at(stairs_index)
				stairs_valid_y.remove_at(stairs_index)
				if dungeon_d.dungeon_floor + 1 < dungeon_d.n_floors_plus_one:
					rng.dungeon_rng_set_secondary(3)
					var hidden_index := rng.rand_int(stairs_valid_x.size())
					_spawn_stairs(stairs_valid_x[hidden_index], stairs_valid_y[hidden_index], status.hidden_stairs_type)

	# Spawn normal items
	var valid_x: Array = []
	var valid_y: Array = []
	for x in range(DungeonData.FLOOR_MAX_X):
		for y in range(DungeonData.FLOOR_MAX_Y):
			if (dungeon_d.list_tiles[x][y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL and
				dungeon_d.list_tiles[x][y].room_index != 0xFF and
				not dungeon_d.list_tiles[x][y].terrain_flags.f_in_kecleon_shop and
				not dungeon_d.list_tiles[x][y].terrain_flags.f_in_monster_house and
				not dungeon_d.list_tiles[x][y].terrain_flags.f_natural_junction):
				valid_x.append(x)
				valid_y.append(y)

	if valid_x.size() > 0:
		var num_items := floor_props.item_density
		if num_items != 0:
			num_items = maxi(rng.rand_range(num_items - 2, num_items + 2), 1)
		if dungeon_d.guaranteed_item_id != 0:
			num_items += 1
		dungeon_d.num_items = num_items + 1
		if num_items + 1 > 0:
			_shuffle_spawn_positions(valid_x, valid_y)
			var cur_index := rng.rand_int(valid_x.size())
			num_items += 1
			for _si in range(num_items):
				dungeon_d.list_tiles[valid_x[cur_index]][valid_y[cur_index]].spawn_or_visibility_flags.f_item = true
				cur_index += 1
				if cur_index == valid_x.size(): cur_index = 0
			_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)

	# Spawn buried items
	valid_x = []; valid_y = []
	for x in range(DungeonData.FLOOR_MAX_X):
		for y in range(DungeonData.FLOOR_MAX_Y):
			if dungeon_d.list_tiles[x][y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_WALL:
				valid_x.append(x); valid_y.append(y)

	if valid_x.size() > 0:
		var num_items := floor_props.buried_item_density
		if num_items != 0:
			num_items = rng.rand_range(num_items - 2, num_items + 2)
		if num_items > 0:
			_shuffle_spawn_positions(valid_x, valid_y)
			var cur_index := rng.rand_int(valid_x.size())
			for _si in range(num_items):
				dungeon_d.list_tiles[valid_x[cur_index]][valid_y[cur_index]].spawn_or_visibility_flags.f_item = true
				cur_index += 1
				if cur_index == valid_x.size(): cur_index = 0
			_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)

	# Spawn monster house items/traps
	valid_x = []; valid_y = []
	if not is_empty_monster_house and status.has_monster_house:
		for x in range(DungeonData.FLOOR_MAX_X):
			for y in range(DungeonData.FLOOR_MAX_Y):
				if (dungeon_d.list_tiles[x][y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL and
					dungeon_d.list_tiles[x][y].terrain_flags.f_in_monster_house and
					not dungeon_d.list_tiles[x][y].spawn_or_visibility_flags.f_item and
					not dungeon_d.list_tiles[x][y].spawn_or_visibility_flags.f_stairs):
					valid_x.append(x); valid_y.append(y)

	if valid_x.size() > 0:
		var num_items := maxi(6, rng.rand_range(int(float(5 * valid_x.size()) / 10), int(float(8 * valid_x.size()) / 10)))
		if num_items >= gen_constants.max_number_monster_house_item_spawns:
			num_items = gen_constants.max_number_monster_house_item_spawns
		_shuffle_spawn_positions(valid_x, valid_y)
		var cur_index := rng.rand_int(valid_x.size())
		for _si in range(num_items):
			if rng.rand_int(2) == 1:
				dungeon_d.list_tiles[valid_x[cur_index]][valid_y[cur_index]].spawn_or_visibility_flags.f_item = true
			elif dungeon_d.nonstory_flag or dungeon_d.id >= gen_constants.first_dungeon_id_allow_monster_house_traps:
				dungeon_d.list_tiles[valid_x[cur_index]][valid_y[cur_index]].spawn_or_visibility_flags.f_trap = true
			cur_index += 1
			if cur_index == valid_x.size(): cur_index = 0
		_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)

	# Spawn normal traps
	valid_x = []; valid_y = []
	for x in range(DungeonData.FLOOR_MAX_X):
		for y in range(DungeonData.FLOOR_MAX_Y):
			if (dungeon_d.list_tiles[x][y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL and
				dungeon_d.list_tiles[x][y].room_index != 0xFF and
				not dungeon_d.list_tiles[x][y].terrain_flags.f_in_kecleon_shop and
				not dungeon_d.list_tiles[x][y].spawn_or_visibility_flags.f_item and
				not dungeon_d.list_tiles[x][y].terrain_flags.f_natural_junction and
				not dungeon_d.list_tiles[x][y].terrain_flags.f_unbreakable):
				valid_x.append(x); valid_y.append(y)

	if valid_x.size() > 0:
		var num_traps := rng.rand_range(int(float(floor_props.trap_density) / 2), floor_props.trap_density)
		if num_traps > 0:
			if num_traps >= 56: num_traps = 56
			_shuffle_spawn_positions(valid_x, valid_y)
			var cur_index := rng.rand_int(valid_x.size())
			for _si in range(num_traps):
				dungeon_d.list_tiles[valid_x[cur_index]][valid_y[cur_index]].spawn_or_visibility_flags.f_trap = true
				cur_index += 1
				if cur_index == valid_x.size(): cur_index = 0
			_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)

	# Spawn player
	var is_rescue_floor := _get_floor_type() == DungeonData.FloorType.FLOOR_TYPE_RESCUE
	if gen_info.player_spawn_x == -1 or gen_info.player_spawn_y == -1:
		valid_x = []; valid_y = []
		for x in range(DungeonData.FLOOR_MAX_X):
			for y in range(DungeonData.FLOOR_MAX_Y):
				if (dungeon_d.list_tiles[x][y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL and
					dungeon_d.list_tiles[x][y].room_index != 0xFF and
					not dungeon_d.list_tiles[x][y].terrain_flags.f_in_kecleon_shop and
					not dungeon_d.list_tiles[x][y].terrain_flags.f_in_monster_house and
					not dungeon_d.list_tiles[x][y].spawn_or_visibility_flags.f_monster and
					not dungeon_d.list_tiles[x][y].spawn_or_visibility_flags.f_trap):
					if not is_rescue_floor or not dungeon_d.list_tiles[x][y].spawn_or_visibility_flags.f_stairs:
						valid_x.append(x); valid_y.append(y)

		if valid_x.size() > 0:
			var spawn_index := rng.rand_int(valid_x.size())
			gen_info.player_spawn_x = valid_x[spawn_index]
			gen_info.player_spawn_y = valid_y[spawn_index]
			_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)

	_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MAJOR, 18)

# ─── SpawnEnemies ───

func _spawn_enemies(floor_props: DungeonData.FloorProperties, is_empty_monster_house: bool) -> void:
	var valid_x: Array = []
	var valid_y: Array = []
	var num_enemies: int

	if floor_props.enemy_density < 1:
		num_enemies = abs(floor_props.enemy_density)
	else:
		num_enemies = rng.rand_range(int(float(floor_props.enemy_density) / 2), floor_props.enemy_density)
		if num_enemies < 1: num_enemies = 1

	for x in range(DungeonData.FLOOR_MAX_X):
		for y in range(DungeonData.FLOOR_MAX_Y):
			if (dungeon_d.list_tiles[x][y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL and
				dungeon_d.list_tiles[x][y].room_index != 0xFF and
				not dungeon_d.list_tiles[x][y].terrain_flags.f_in_kecleon_shop and
				not dungeon_d.list_tiles[x][y].spawn_or_visibility_flags.f_item and
				not dungeon_d.list_tiles[x][y].spawn_or_visibility_flags.f_stairs and
				not dungeon_d.list_tiles[x][y].terrain_flags.f_natural_junction and
				not dungeon_d.list_tiles[x][y].terrain_flags.f_unbreakable):
				if gen_info.player_spawn_x != x or gen_info.player_spawn_y != y:
					if not status.no_enemy_spawn or gen_info.monster_house_room != dungeon_d.list_tiles[x][y].room_index:
						valid_x.append(x); valid_y.append(y)

	if valid_x.size() > 0 and num_enemies + 1 > 0:
		_shuffle_spawn_positions(valid_x, valid_y)
		num_enemies += 1
		var cur_index := rng.rand_int(valid_x.size())
		for _si in range(num_enemies):
			dungeon_d.list_tiles[valid_x[cur_index]][valid_y[cur_index]].spawn_or_visibility_flags.f_monster = true
			cur_index += 1
			if cur_index == valid_x.size(): cur_index = 0
		_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)

	if not gen_info.force_create_monster_house:
		_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MAJOR, 19)
		return

	# Monster house extra enemies
	valid_x = []; valid_y = []
	var num_mh_spawn := gen_constants.max_number_monster_house_enemy_spawns
	if is_empty_monster_house: num_mh_spawn = 3
	if gen_info.force_create_monster_house:
		num_mh_spawn = int(float(num_mh_spawn * 3) / 2)

	for x in range(DungeonData.FLOOR_MAX_X):
		for y in range(DungeonData.FLOOR_MAX_Y):
			if (dungeon_d.list_tiles[x][y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL and
				dungeon_d.list_tiles[x][y].terrain_flags.f_in_monster_house and
				not dungeon_d.list_tiles[x][y].terrain_flags.f_in_kecleon_shop and
				not dungeon_d.list_tiles[x][y].spawn_or_visibility_flags.f_item and
				not dungeon_d.list_tiles[x][y].spawn_or_visibility_flags.f_stairs and
				not dungeon_d.list_tiles[x][y].spawn_or_visibility_flags.f_monster and
				not dungeon_d.list_tiles[x][y].terrain_flags.f_unbreakable):
				if gen_info.player_spawn_x != x or gen_info.player_spawn_y != y:
					valid_x.append(x); valid_y.append(y)

	if valid_x.size() > 0 and num_mh_spawn > 0:
		_shuffle_spawn_positions(valid_x, valid_y)
		var cur_index := rng.rand_int(valid_x.size())
		for _si in range(mini(num_mh_spawn, valid_x.size())):
			dungeon_d.list_tiles[valid_x[cur_index]][valid_y[cur_index]].spawn_or_visibility_flags.f_monster = true
			cur_index += 1
			if cur_index == valid_x.size(): cur_index = 0
		_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MINOR, 0)

	_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_MAJOR, 19)

# ─── ResolveInvalidSpawns ───

func _resolve_invalid_spawns() -> void:
	for x in range(DungeonData.FLOOR_MAX_X):
		for y in range(DungeonData.FLOOR_MAX_Y):
			if dungeon_d.list_tiles[x][y].terrain_flags.terrain_type != DungeonData.TerrainType.TERRAIN_NORMAL:
				dungeon_d.list_tiles[x][y].spawn_or_visibility_flags.f_trap = false
				if dungeon_d.list_tiles[x][y].terrain_flags.f_impassable_wall:
					dungeon_d.list_tiles[x][y].spawn_or_visibility_flags.f_item = false

# ─── StairsAlwaysReachable ───

func _stairs_always_reachable(x_stairs: int, y_stairs: int, mark_unreachable: bool) -> bool:
	var test: Array = []
	for x in range(DungeonData.FLOOR_MAX_X):
		var col: Array = []
		for y in range(DungeonData.FLOOR_MAX_Y):
			var f := DungeonData.StairsReachableFlags.new()
			if mark_unreachable:
				dungeon_d.list_tiles[x][y].terrain_flags.f_unreachable_from_stairs = false
			if dungeon_d.list_tiles[x][y].terrain_flags.terrain_type != DungeonData.TerrainType.TERRAIN_NORMAL:
				if not dungeon_d.list_tiles[x][y].terrain_flags.f_corner_cuttable:
					f.f_cannot_corner_cut = true
			if dungeon_d.list_tiles[x][y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_SECONDARY:
				if not dungeon_d.list_tiles[x][y].terrain_flags.f_corner_cuttable:
					f.f_secondary_terrain_cannot_corner_cut = true
			col.append(f)
		test.append(col)

	test[x_stairs][y_stairs].f_in_visit_queue = true
	test[x_stairs][y_stairs].f_starting_point = true

	var checked := 1
	while checked > 0:
		checked = 0
		for x in range(DungeonData.FLOOR_MAX_X):
			for y in range(DungeonData.FLOOR_MAX_Y):
				if not test[x][y].f_visited and test[x][y].f_in_visit_queue:
					test[x][y].f_in_visit_queue = false
					test[x][y].f_visited = true
					checked += 1

					# Cardinal directions
					if x > 0 and not test[x-1][y].f_cannot_corner_cut and not test[x-1][y].f_secondary_terrain_cannot_corner_cut and not test[x-1][y].f_visited:
						test[x-1][y].f_in_visit_queue = true
					if y > 0 and not test[x][y-1].f_cannot_corner_cut and not test[x][y-1].f_secondary_terrain_cannot_corner_cut and not test[x][y-1].f_visited:
						test[x][y-1].f_in_visit_queue = true
					if x < DungeonData.FLOOR_MAX_X-1 and not test[x+1][y].f_cannot_corner_cut and not test[x+1][y].f_secondary_terrain_cannot_corner_cut and not test[x+1][y].f_visited:
						test[x+1][y].f_in_visit_queue = true
					if y < DungeonData.FLOOR_MAX_Y-1 and not test[x][y+1].f_cannot_corner_cut and not test[x][y+1].f_secondary_terrain_cannot_corner_cut and not test[x][y+1].f_visited:
						test[x][y+1].f_in_visit_queue = true

					# Diagonal directions
					if x > 0 and y > 0 and not test[x-1][y-1].f_cannot_corner_cut and not test[x-1][y-1].f_secondary_terrain_cannot_corner_cut and not test[x-1][y-1].f_unknown_field_0x2 and not test[x-1][y-1].f_visited and not test[x][y-1].f_cannot_corner_cut and not test[x-1][y].f_cannot_corner_cut:
						test[x-1][y-1].f_in_visit_queue = true
					if x < DungeonData.FLOOR_MAX_X-1 and y > 0 and not test[x+1][y-1].f_cannot_corner_cut and not test[x+1][y-1].f_secondary_terrain_cannot_corner_cut and not test[x+1][y-1].f_unknown_field_0x2 and not test[x+1][y-1].f_visited and not test[x][y-1].f_cannot_corner_cut and not test[x+1][y].f_cannot_corner_cut:
						test[x+1][y-1].f_in_visit_queue = true
					if x > 0 and y < DungeonData.FLOOR_MAX_Y-1 and not test[x-1][y+1].f_cannot_corner_cut and not test[x-1][y+1].f_secondary_terrain_cannot_corner_cut and not test[x-1][y+1].f_unknown_field_0x2 and not test[x-1][y+1].f_visited and not test[x][y+1].f_cannot_corner_cut and not test[x-1][y].f_cannot_corner_cut:
						test[x-1][y+1].f_in_visit_queue = true
					if x < DungeonData.FLOOR_MAX_X-1 and y < DungeonData.FLOOR_MAX_Y-1 and not test[x+1][y+1].f_cannot_corner_cut and not test[x+1][y+1].f_secondary_terrain_cannot_corner_cut and not test[x+1][y+1].f_unknown_field_0x2 and not test[x+1][y+1].f_visited and not test[x][y+1].f_cannot_corner_cut and not test[x+1][y].f_cannot_corner_cut:
						test[x+1][y+1].f_in_visit_queue = true

	# Check all walkable tiles were visited
	for x in range(DungeonData.FLOOR_MAX_X):
		for y in range(DungeonData.FLOOR_MAX_Y):
			if dungeon_d.list_tiles[x][y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL and not test[x][y].f_visited:
				if mark_unreachable:
					dungeon_d.list_tiles[x][y].terrain_flags.f_unreachable_from_stairs = true
				else:
					if not dungeon_d.list_tiles[x][y].terrain_flags.f_unbreakable:
						return false
	return true

# ─── GenerateFloor (Master Function) ───

func _generate_floor(floor_props: DungeonData.FloorProperties) -> Array:
	status.stairs_room_index = 0xFF
	status.floor_size = DungeonData.FloorSize.FLOOR_SIZE_LARGE
	gen_info.fixed_room_id = floor_props.fixed_room_id
	status.monster_house_chance = floor_props.monster_house_chance
	status.kecleon_shop_chance = floor_props.kecleon_shop_chance
	status.secondary_structures_budget = floor_props.secondary_structures_budget
	status.hidden_stairs_type = floor_props.hidden_stairs_type

	for spawn_attempts in range(10):
		gen_info.player_spawn_x = -1
		gen_info.player_spawn_y = -1
		gen_info.stairs_spawn_x = -1
		gen_info.stairs_spawn_y = -1
		gen_info.hidden_stairs_spawn_x = -1
		gen_info.hidden_stairs_spawn_y = -1

		var fixed_room := false
		var secondary_gen := false

		var exhausted_gen_attempts := true
		for gen_attempts in range(10):
			if fixed_room:
				if gen_info.fixed_room_id > 0 and gen_info.fixed_room_id < 0xA5:
					exhausted_gen_attempts = false
					break
				fixed_room = false

			gen_info.floor_generation_attempts = gen_attempts
			if gen_attempts > 0:
				status.secondary_structures_budget = 0

			status.is_invalid = false
			status.kecleon_shop_middle_x = -1
			status.kecleon_shop_middle_y = -1
			_reset_floor()
			gen_info.player_spawn_x = -1
			gen_info.player_spawn_y = -1

			var grid_size_x := 2
			var grid_size_y := 2

			var attempts := 32
			while attempts > 0:
				var max_x: int
				var max_y: int
				if floor_props.layout == DungeonData.FloorLayout.LAYOUT_LARGE_0x8:
					max_x = 5; max_y = 4
				else:
					max_x = 9; max_y = 8

				grid_size_x = rng.rand_range(2, max_x)
				grid_size_y = rng.rand_range(2, max_y)
				if grid_size_x <= 6 and grid_size_y <= 4: break
				attempts -= 1

			if attempts == 0:
				grid_size_x = 4; grid_size_y = 4

			if int(float(DungeonData.FLOOR_MAX_X) / grid_size_x) < 8:
				grid_size_x = 1
			if int(float(DungeonData.FLOOR_MAX_Y) / grid_size_y) < 8:
				grid_size_y = 1

			status.layout = floor_props.layout

			match floor_props.layout:
				DungeonData.FloorLayout.LAYOUT_LARGE, DungeonData.FloorLayout.LAYOUT_LARGE_0x8:
					_generate_standard_floor(grid_size_x, grid_size_y, floor_props)
					secondary_gen = true
				DungeonData.FloorLayout.LAYOUT_SMALL:
					grid_size_x = 4
					grid_size_y = rng.rand_int(2) + 2
					status.floor_size = DungeonData.FloorSize.FLOOR_SIZE_SMALL
					_generate_standard_floor(grid_size_x, grid_size_y, floor_props)
					secondary_gen = true
				DungeonData.FloorLayout.LAYOUT_ONE_ROOM_MONSTER_HOUSE:
					_generate_one_room_monster_house_floor()
					gen_info.force_create_monster_house = true
				DungeonData.FloorLayout.LAYOUT_OUTER_RING:
					_generate_outer_ring_floor(floor_props)
					secondary_gen = true
				DungeonData.FloorLayout.LAYOUT_CROSSROADS:
					_generate_crossroads_floor(floor_props)
					secondary_gen = true
				DungeonData.FloorLayout.LAYOUT_TWO_ROOMS_WITH_MONSTER_HOUSE:
					_generate_two_rooms_with_monster_house_floor()
					gen_info.force_create_monster_house = true
				DungeonData.FloorLayout.LAYOUT_LINE:
					_generate_line_floor(floor_props)
					secondary_gen = true
				DungeonData.FloorLayout.LAYOUT_CROSS:
					_generate_cross_floor(floor_props)
				DungeonData.FloorLayout.LAYOUT_BEETLE:
					_generate_beetle_floor(floor_props)
				DungeonData.FloorLayout.LAYOUT_OUTER_ROOMS:
					_generate_outer_rooms_floor(grid_size_x, grid_size_y, floor_props)
					secondary_gen = true
				DungeonData.FloorLayout.LAYOUT_MEDIUM:
					grid_size_x = 4
					grid_size_y = rng.rand_int(2) + 2
					status.floor_size = DungeonData.FloorSize.FLOOR_SIZE_MEDIUM
					_generate_standard_floor(grid_size_x, grid_size_y, floor_props)
					secondary_gen = true
				_:
					_generate_standard_floor(grid_size_x, grid_size_y, floor_props)
					secondary_gen = true

			_reset_inner_boundary_tile_rows()
			_ensure_impassable_tiles_are_walls()

			if not status.is_invalid:
				var room: Array = []
				room.resize(64)
				room.fill(false)
				var room_tiles := 0
				for x in range(DungeonData.FLOOR_MAX_X):
					for y in range(DungeonData.FLOOR_MAX_Y):
						if dungeon_d.list_tiles[x][y].terrain_flags.terrain_type == DungeonData.TerrainType.TERRAIN_NORMAL:
							if dungeon_d.list_tiles[x][y].room_index < 0xF0:
								room_tiles += 1
								if dungeon_d.list_tiles[x][y].room_index < 0x40:
									room[dungeon_d.list_tiles[x][y].room_index] = true

				var num_rooms := 0
				for r in room:
					if r: num_rooms += 1

				if num_rooms >= 2 and room_tiles >= 20:
					exhausted_gen_attempts = false
					break

		if exhausted_gen_attempts:
			status.kecleon_shop_middle_x = -1
			status.kecleon_shop_middle_y = -1
			_generate_one_room_monster_house_floor()
			gen_info.force_create_monster_house = true

		_finalize_junctions()
		if secondary_gen:
			_generate_secondary_terrain_formations(true, floor_props)

		var is_empty_mh := rng.rand_int(100) < floor_props.itemless_monster_house_chance
		_spawn_non_enemies(floor_props, is_empty_mh)
		_spawn_enemies(floor_props, is_empty_mh)
		_resolve_invalid_spawns()

		if gen_info.player_spawn_x != -1 and gen_info.player_spawn_y != -1:
			if _get_floor_type() == DungeonData.FloorType.FLOOR_TYPE_FIXED:
				break
			if gen_info.stairs_spawn_x != -1 and gen_info.stairs_spawn_y != -1:
				if _stairs_always_reachable(gen_info.stairs_spawn_x, gen_info.stairs_spawn_y, false):
					break

		if spawn_attempts + 1 == 10:
			status.kecleon_shop_middle_x = -1
			status.kecleon_shop_middle_y = -1
			_reset_floor()
			_generate_one_room_monster_house_floor()
			gen_info.force_create_monster_house = true
			_finalize_junctions()
			_spawn_non_enemies(floor_props, false)
			_spawn_enemies(floor_props, false)
			_resolve_invalid_spawns()

	_on_complete_generation_step(DungeonData.GenerationStepLevel.GEN_STEP_COMPLETE, 20)
	return dungeon_d.list_tiles

# ─── Callback ───

func _on_complete_generation_step(step_level: int, _gen_type: int) -> void:
	if callback_frequency >= step_level and generation_callback.is_valid():
		generation_callback.call(step_level, _gen_type, dungeon_d, gen_info, status, grid_cell_start_x, grid_cell_start_y)

# ─── Accessors ───

func get_generation_info() -> DungeonData.DungeonGenerationInfo:
	return gen_info

func get_status() -> DungeonData.FloorGenerationStatus:
	return status

func get_dungeon() -> DungeonData.Dungeon:
	return dungeon_d
