extends "res://scripts/dungeon_3d/entities/tile_entity_3d.gd"
## PMD-style 8-directional tile movement in 3D. Walk, dash, turn, attack.

@export var walk_time: float = 0.12
@export var dash_time: float = 0.05

var is_moving: bool = false
var is_frozen: bool = false

var _dash_active: bool = false
var _dash_dir: Vector2i = Vector2i.ZERO
var _run_held_prev: bool = false
var _pending_continuation: Callable = Callable()

signal stepped_on_stairs

@onready var dungeon_map = get_node_or_null("../DungeonRenderer3D")
@onready var enemy_manager: Node = get_node_or_null("../EnemyManager3D")
@onready var turn_manager: Node = get_node_or_null("../TurnManager")

func _ready() -> void:
	_setup_model()
	play_idle()
	if turn_manager:
		turn_manager.enemy_phase_finished.connect(_on_enemy_phase_finished)

func _process(_delta: float) -> void:
	var run_held := _is_run_held()
	if is_frozen or is_moving:
		_run_held_prev = run_held
		return

	var dir := _read_direction()
	if Input.is_key_pressed(KEY_CTRL):
		if dir != Vector2i.ZERO:
			_set_facing(dir)
			_stop_anim()
		_run_held_prev = run_held
		return

	if not _dash_active and run_held and dir != Vector2i.ZERO:
		_dash_active = true
		_dash_dir = dir
		_set_facing(dir)
		if _can_move_to(tile_position, dir):
			_do_move(dir, dash_time)
		else:
			_stop_dash()
			_stop_anim()
		_run_held_prev = run_held
		return

	if dir != Vector2i.ZERO and not _dash_active:
		_set_facing(dir)
		if _can_move_to(tile_position, dir):
			_do_move(dir, walk_time)
		else:
			_stop_anim()

	_run_held_prev = run_held

func _unhandled_input(event: InputEvent) -> void:
	if is_frozen or is_moving:
		return
	if event.is_action_pressed("attack"):
		_do_attack()

# ── MOVEMENT ──

func _do_move(dir: Vector2i, duration: float) -> void:
	is_moving = true
	speed_scale = 2.0 if duration == dash_time else 1.0
	play_walk()
	var target := tile_position + dir
	tile_position = target
	var tween := create_tween()
	tween.tween_property(self, "position", tile_center_3d(target), duration)
	tween.finished.connect(_on_move_finished)

func _on_move_finished() -> void:
	is_moving = false
	if dungeon_map and dungeon_map.get_tile_type(tile_position) == "stairs":
		_stop_dash()
		_stop_anim()
		stepped_on_stairs.emit()
		return
	if _dash_active:
		_pending_continuation = _continue_dash
	else:
		_pending_continuation = _continue_walk
	is_frozen = true
	var speed := dash_time if _dash_active else walk_time
	if turn_manager:
		turn_manager.end_player_turn(speed)
	else:
		is_frozen = false

func _continue_dash() -> void:
	if not _is_run_held():
		_stop_dash()
		return
	var dir := _read_direction()
	if dir != Vector2i.ZERO and dir != _dash_dir:
		if dir == -_dash_dir:
			_stop_dash()
			return
		_dash_dir = dir
		_set_facing(dir)
	if _is_dash_stop_point(_dash_dir):
		_stop_dash()
		return
	_set_facing(_dash_dir)
	_do_move(_dash_dir, dash_time)

func _continue_walk() -> void:
	var dir := _read_direction()
	var run_held := _is_run_held()
	if dir == Vector2i.ZERO and not run_held:
		return
	if run_held and dir != Vector2i.ZERO:
		_dash_active = true
		_dash_dir = dir
		_set_facing(dir)
		if _can_move_to(tile_position, dir):
			_do_move(dir, dash_time)
		else:
			_stop_dash()
		return
	if dir != Vector2i.ZERO and _can_move_to(tile_position, dir):
		_set_facing(dir)
		_do_move(dir, walk_time)

func reset_dash() -> void:
	_dash_active = false
	_dash_dir = Vector2i.ZERO

func _stop_dash() -> void:
	reset_dash()

func _stop_anim() -> void:
	speed_scale = 1.0
	play_idle()

func _on_enemy_phase_finished() -> void:
	is_frozen = false
	var continuation := _pending_continuation
	_pending_continuation = Callable()
	if continuation.is_valid():
		continuation.call()
	if not is_moving:
		_stop_anim()

# ── COMBAT ──

func _do_attack() -> void:
	is_frozen = true
	var attack_tile := tile_position + facing
	var killed := false
	if enemy_manager and enemy_manager.has_method("kill_enemy_at"):
		killed = await enemy_manager.kill_enemy_at(attack_tile, self, tile_position)
	if not killed:
		var audio = get_node_or_null("/root/AudioManager")
		if audio:
			audio.play_player_attack()
		play_attack()
		await animation_finished
	_stop_anim()
	_pending_continuation = Callable()
	if turn_manager:
		turn_manager.end_player_turn(walk_time)
	else:
		is_frozen = false

func face_toward(target_tile: Vector2i) -> void:
	var dir := (target_tile - tile_position).sign()
	if dir != Vector2i.ZERO:
		facing = dir
		_update_facing_rotation()
	_stop_anim()

# ── FACING ──

func _set_facing(dir: Vector2i) -> void:
	facing = dir
	_update_facing_rotation()

# ── DASH STOP DETECTION ──

func _is_dash_stop_point(direction: Vector2i) -> bool:
	var tile := tile_position
	var next := tile + direction
	if not _can_move_to(tile, direction):
		return true
	if not dungeon_map:
		return false
	var cur_type: String = dungeon_map.get_tile_type(tile)
	var next_type: String = dungeon_map.get_tile_type(next)
	if cur_type == "room":
		if next_type == "hallway":
			return true
		for p in _perpendiculars(direction):
			if dungeon_map.get_tile_type(tile + p) == "hallway":
				return true
	elif cur_type == "hallway":
		if next_type == "room":
			return true
		for p in _perpendiculars(direction):
			if _is_walkable(tile + p):
				return true
	return false

# ── INPUT HELPERS ──

func _read_direction() -> Vector2i:
	var ix := int(sign(Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")))
	var iy := int(sign(Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")))
	return Vector2i(ix, iy)

func _is_run_held() -> bool:
	return Input.is_action_pressed("run") or Input.is_key_pressed(KEY_SHIFT)

func _perpendiculars(dir: Vector2i) -> Array[Vector2i]:
	if dir.x != 0 and dir.y != 0:
		return [Vector2i(dir.x, 0), Vector2i(0, dir.y)]
	if dir.x != 0:
		return [Vector2i(0, -1), Vector2i(0, 1)]
	return [Vector2i(-1, 0), Vector2i(1, 0)]

# ── TILE HELPERS ──

func _can_move_to(_origin: Vector2i, dir: Vector2i) -> bool:
	var target := tile_position + dir
	if not _is_walkable(target):
		return false
	if enemy_manager and enemy_manager.has_method("is_tile_occupied_by_enemy") and enemy_manager.is_tile_occupied_by_enemy(target):
		return false
	if dir.x != 0 and dir.y != 0:
		if not _is_walkable(tile_position + Vector2i(dir.x, 0)):
			return false
		if enemy_manager and enemy_manager.has_method("is_tile_occupied_by_enemy") and enemy_manager.is_tile_occupied_by_enemy(tile_position + Vector2i(dir.x, 0)):
			return false
		if not _is_walkable(tile_position + Vector2i(0, dir.y)):
			return false
		if enemy_manager and enemy_manager.has_method("is_tile_occupied_by_enemy") and enemy_manager.is_tile_occupied_by_enemy(tile_position + Vector2i(0, dir.y)):
			return false
	return true

func _is_walkable(coords: Vector2i) -> bool:
	if not dungeon_map:
		return true
	return dungeon_map.is_walkable_tile(coords)
