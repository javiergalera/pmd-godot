extends Sprite2D
## PMD-style 8-directional tile movement with walk and dash (run).

@export var tile_size: int = 24
@export var walk_time: float = 0.15
@export var dash_time: float = 0.05

var is_moving: bool = false
var is_dashing: bool = false
var is_frozen: bool = false
var facing: Vector2i = Vector2i.DOWN
var _queued_dir: Vector2i = Vector2i.ZERO

signal stepped_on_stairs

@onready var dungeon_map: TileMapLayer = get_node("../TileMapLayer")

# ─── Input ───

func _process(_delta: float) -> void:
	if is_frozen:
		return
	var dir := _read_input()

	if is_moving:
		if dir != Vector2i.ZERO and dir != facing:
			_queued_dir = dir
		return

	if dir != Vector2i.ZERO:
		facing = dir
		_queued_dir = Vector2i.ZERO
		var run := Input.is_action_pressed("run")
		_start_move(dir, dash_time if run else walk_time, run)

func _read_input() -> Vector2i:
	var ix := int(sign(Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")))
	var iy := int(sign(Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")))
	return Vector2i(ix, iy)

# ─── Movement ───

func _start_move(dir: Vector2i, duration: float, dashing: bool) -> bool:
	if dir == Vector2i.ZERO:
		return false

	var origin := _current_tile()
	var target := origin + dir

	if not _can_move_to(origin, dir):
		is_dashing = false
		return false

	is_moving = true
	is_dashing = dashing

	var tween := create_tween()
	tween.tween_property(self, "position", _tile_center(target), duration)
	tween.finished.connect(_on_move_finished)
	return true

func _on_move_finished() -> void:
	is_moving = false

	# Check if we landed on stairs
	if dungeon_map.get_tile_type(_current_tile()) == "stairs":
		is_dashing = false
		_queued_dir = Vector2i.ZERO
		stepped_on_stairs.emit()
		return

	# Process queued direction change first
	if is_dashing and _queued_dir != Vector2i.ZERO:
		facing = _queued_dir
		_queued_dir = Vector2i.ZERO
		var run := Input.is_action_pressed("run")
		if _start_move(facing, dash_time if run else walk_time, run):
			return

	_queued_dir = Vector2i.ZERO

	if not is_dashing:
		return

	# Dash auto-continue logic
	if not Input.is_action_pressed("run"):
		is_dashing = false
		return

	if _should_stop_dash():
		is_dashing = false
		return

	_start_move(facing, dash_time, true)

# ─── Dash braking (PMD rules) ───

func _should_stop_dash() -> bool:
	var tile := _current_tile()
	var next := tile + facing
	var tile_type: String = dungeon_map.get_tile_type(tile)

	# Always stop before a wall
	if not _can_move_to(tile, facing):
		return true

	if tile_type == "room":
		# Stop at room exits: next tile is hallway, or adjacent perpendicular tile is hallway
		if dungeon_map.get_tile_type(next) == "hallway":
			return true
		if _has_adjacent_hallway(tile, facing):
			return true
	else:
		# In hallway: stop at intersections (branching path perpendicular to movement)
		if _is_intersection(tile, facing):
			return true
		# Stop when entering a room
		if dungeon_map.get_tile_type(next) == "room":
			return true

	return false

func _has_adjacent_hallway(tile: Vector2i, dir: Vector2i) -> bool:
	# Check perpendicular neighbors for hallway tiles
	var perps := _perpendiculars(dir)
	for p in perps:
		if dungeon_map.get_tile_type(tile + p) == "hallway":
			return true
	return false

func _is_intersection(tile: Vector2i, dir: Vector2i) -> bool:
	var perps := _perpendiculars(dir)
	for p in perps:
		if _is_walkable(tile + p):
			return true
	return false

func _perpendiculars(dir: Vector2i) -> Array[Vector2i]:
	if dir.x != 0 and dir.y != 0:
		# Diagonal: perpendiculars are the two cardinal components
		return [Vector2i(dir.x, 0), Vector2i(0, dir.y)]
	if dir.x != 0:
		return [Vector2i(0, -1), Vector2i(0, 1)]
	return [Vector2i(-1, 0), Vector2i(1, 0)]

# ─── Tile helpers ───

func _current_tile() -> Vector2i:
	var half := Vector2(tile_size / 2.0, tile_size / 2.0)
	return Vector2i(roundi((position.x - half.x) / tile_size), roundi((position.y - half.y) / tile_size))

func _tile_center(tile: Vector2i) -> Vector2:
	return Vector2(tile) * tile_size + Vector2(tile_size / 2.0, tile_size / 2.0)

func _can_move_to(origin: Vector2i, dir: Vector2i) -> bool:
	var target := origin + dir
	if not _is_walkable(target):
		return false
	# Diagonal corner-cutting prevention: both adjacent cardinal tiles must be walkable
	if dir.x != 0 and dir.y != 0:
		if not _is_walkable(origin + Vector2i(dir.x, 0)):
			return false
		if not _is_walkable(origin + Vector2i(0, dir.y)):
			return false
	return true

func _is_walkable(coords: Vector2i) -> bool:
	return dungeon_map.is_walkable_tile(coords)
