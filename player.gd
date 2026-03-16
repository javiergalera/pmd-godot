extends Sprite2D

@export var tile_size: int = 24
@export var normal_speed: float = 0.15
@export var dash_speed: float = 0.05

var is_moving: bool = false
var is_auto_dashing: bool = false
var current_dir: Vector2 = Vector2.ZERO
var input_locked_dir: Vector2 = Vector2.ZERO # The "banned" direction after a forced stop

@onready var dungeon_map: TileMapLayer = get_node("../TileMapLayer")

func _process(_delta: float) -> void:
	if is_moving:
		return

	# 1. Capture current input
	var input_dir = Vector2.ZERO
	input_dir.x = Input.get_axis("ui_left", "ui_right")
	input_dir.y = Input.get_axis("ui_up", "ui_down")

	# 2. Unlock Logic: If the user releases the key or changes direction, clear the lock
	if input_dir != input_locked_dir or input_dir == Vector2.ZERO:
		input_locked_dir = Vector2.ZERO

	# 3. Process movement only if there is input AND it's not locked
	if input_dir != Vector2.ZERO and input_dir != input_locked_dir:
		if Input.is_action_pressed("run"): # Assuming "run" is your B-button action
			current_dir = input_dir
			start_move(current_dir, dash_speed, true)
		else:
			is_auto_dashing = false
			start_move(input_dir, normal_speed, false)

func start_move(direction: Vector2, duration: float, dashing: bool) -> void:
	var target_tile = Vector2i((position / tile_size) + direction)
	
	if dungeon_map.get_cell_source_id(target_tile) == 0: # 0 is Floor
		is_moving = true
		is_auto_dashing = dashing
		
		var target_pos = position + (direction * tile_size)
		var tween = create_tween()
		tween.tween_property(self, "position", target_pos, duration)
		tween.finished.connect(_on_move_completed)
	else:
		is_auto_dashing = false # Stop if wall hit

func _on_move_completed() -> void:
	is_moving = false
	
	if is_auto_dashing:
		var current_tile = Vector2i(position / tile_size)
		var tile_data = dungeon_map.get_cell_tile_data(current_tile)
		var tile_type = ""
		
		if tile_data:
			tile_type = tile_data.get_custom_data("type")

		# STRATEGIC BRAKING LOGIC
		var should_stop = false
		
		if tile_type == "room":
			# In a room, only stop if the NEXT tile is a hallway (Exit) or a wall
			if is_approaching_exit(current_dir) or is_approaching_wall(current_dir):
				should_stop = true
		else:
			# In a hallway, use the intersection check we built before
			if is_at_decision_point(current_dir) or is_approaching_wall(current_dir):
				should_stop = true

		if should_stop:
			stop_and_lock_input("Stopping point reached.")
		else:
			start_move(current_dir, dash_speed, true)

func is_approaching_exit(dir: Vector2) -> bool:
	var next_tile = Vector2i((position / tile_size) + dir)
	var next_data = dungeon_map.get_cell_tile_data(next_tile)
	if next_data:
		# If we are in a room and the next tile is a hallway, we stop at the door
		return next_data.get_custom_data("type") == "hallway"
	return false

func stop_and_lock_input(reason: String) -> void:
	print(reason)
	is_auto_dashing = false
	# This is the key: we "ban" the current direction from triggering again in _process
	input_locked_dir = current_dir 

func is_at_decision_point(dir: Vector2) -> bool:
	var current_tile = Vector2i(position / tile_size)
	# If moving horizontal, check for floor above or below
	if dir.x != 0:
		return is_floor(current_tile + Vector2i.UP) or is_floor(current_tile + Vector2i.DOWN)
	# If moving vertical, check for floor to the left or right
	if dir.y != 0:
		return is_floor(current_tile + Vector2i.LEFT) or is_floor(current_tile + Vector2i.RIGHT)
	return false

func is_approaching_wall(dir: Vector2) -> bool:
	var next_tile = Vector2i((position / tile_size) + dir)
	return dungeon_map.get_cell_source_id(next_tile) != 0

func is_floor(coords: Vector2i) -> bool:
	return dungeon_map.get_cell_source_id(coords) == 0
