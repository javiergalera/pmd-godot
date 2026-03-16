extends TileMapLayer

@export var map_width: int = 50
@export var map_height: int = 40
@export var grid_columns: int = 3
@export var grid_rows: int = 2
@export var tile_size: int = 24

# Tile IDs (Ensure these match your TileSet)
const TILE_FLOOR = 0
const TILE_WALL = 1

func _ready() -> void:
	generate_dungeon()

func generate_dungeon() -> void:
	clear()
	fill_with_walls()
	
	var cell_w = map_width / grid_columns
	var cell_h = map_height / grid_rows
	var rooms_data = []

	# 1. Create one room per grid cell
	for y in range(grid_rows):
		for x in range(grid_columns):
			var room_rect = create_room_in_cell(x, y, cell_w, cell_h)
			rooms_data.append(room_rect)
			dig_room(room_rect)

	# 2. Connect rooms using the grid sequence
	for i in range(rooms_data.size() - 1):
		connect_rooms(rooms_data[i], rooms_data[i+1])

	# 3. Position the Player in the first room
	spawn_player(rooms_data[0])

func fill_with_walls() -> void:
	for x in range(map_width):
		for y in range(map_height):
			set_cell(Vector2i(x, y), TILE_WALL, Vector2i(0, 0))

func create_room_in_cell(gx: int, gy: int, cw: int, ch: int) -> Rect2i:
	# Room size (min 4x4, max fits cell with padding)
	var w = randi_range(4, cw - 4)
	var h = randi_range(4, ch - 4)
	
	# Random position within the grid cell
	var px = (gx * cw) + randi_range(2, cw - w - 2)
	var py = (gy * ch) + randi_range(2, ch - h - 2)
	
	return Rect2i(px, py, w, h)

func dig_room(rect: Rect2i) -> void:
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			var coords = Vector2i(x, y)
			set_cell(coords, TILE_FLOOR, Vector2i(0, 0))
			# Set custom data so the player knows this is a ROOM
			set_cells_terrain_connect([coords], 0, 0) # (Optional: for autotiling)
			
			# Logic: We override the custom data for these specific tiles
			var data = get_cell_tile_data(coords)
			if data:
				data.set_custom_data("type", "room")

func connect_rooms(r1: Rect2i, r2: Rect2i) -> void:
	var start = r1.get_center()
	var end = r2.get_center()
	
	# Create L-shaped corridor
	if randf() > 0.5:
		dig_corridor_h(start.x, end.x, start.y)
		dig_corridor_v(start.y, end.y, end.x)
	else:
		dig_corridor_v(start.y, end.y, start.x)
		dig_corridor_h(start.x, end.x, end.y)

func dig_corridor_h(x1, x2, y) -> void:
	for x in range(min(x1, x2), max(x1, x2) + 1):
		set_cell(Vector2i(x, y), TILE_FLOOR, Vector2i(0, 0))

func dig_corridor_v(y1, y2, x) -> void:
	for y in range(min(y1, y2), max(y1, y2) + 1):
		set_cell(Vector2i(x, y), TILE_FLOOR, Vector2i(0, 0))

func spawn_player(first_room: Rect2i) -> void:
	var player = get_node("../Player")
	if player:
		# Center the player within the 24px tile
		var spawn_pos = Vector2(first_room.get_center()) * tile_size
		player.position = spawn_pos + Vector2(tile_size/2, tile_size/2)
		
	var camera = player.get_node("Camera2D")
	if camera:
		camera.limit_left = 0
		camera.limit_top = 0
		camera.limit_right = map_width * tile_size
		camera.limit_bottom = map_height * tile_size
