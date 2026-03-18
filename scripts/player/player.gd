extends Sprite2D
## PMD-style 8-directional tile movement with walk, dash, and turn system.
##
## Walk:  Hold direction → move tile by tile. Release → stop.
## Dash:  Hold Shift + direction → auto-run in that direction.
##        Continues even after releasing direction keys.
##        Stops on: wall/enemy, room↔hallway transition, hallway intersection.
##        Opposite direction → immediate stop. Other direction → redirect.
##        After any stop: must release Shift and re-press Shift+dir to dash again.
##        Normal walking (without Shift) is always available.
## Ctrl:  Hold Ctrl + direction → rotate facing without moving (no turn).
## Space: Attack the tile you're facing (consumes a turn).

@export var tile_size: int = 24
@export var walk_time: float = 0.12
@export var dash_time: float = 0.05

# ── Core state ──
var is_moving: bool = false
var is_frozen: bool = false
var facing: Vector2i = Vector2i.DOWN

# ── Dash state ──
var _dash_active: bool = false           # currently auto-running
var _dash_dir: Vector2i = Vector2i.ZERO  # locked dash heading
var _run_held_prev: bool = false         # for fresh-press detection

signal stepped_on_stairs

@onready var dungeon_map: TileMapLayer = get_node("../TileMapLayer")
@onready var enemy_manager: Node = get_node_or_null("../EnemyManager")

func _ready() -> void:
	_update_facing_arrow()

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  INPUT LOOP — runs every frame, decides what to do when idle
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _process(_delta: float) -> void:
	var run_held := _is_run_held()

	# While tweening or frozen, just track Shift state.
	if is_frozen or is_moving:
		_run_held_prev = run_held
		return

	var dir := _read_direction()
	# ── Ctrl + direction: rotate only, no turn consumed ──
	if Input.is_key_pressed(KEY_CTRL):
		if dir != Vector2i.ZERO:
			_set_facing(dir)
		_run_held_prev = run_held
		return

	# ── Start a new dash (Shift + direction) ──
	if not _dash_active and run_held and dir != Vector2i.ZERO:
			_dash_active = true
			_dash_dir = dir
			_set_facing(dir)
			if _can_move_to(_current_tile(), dir):
				_do_move(dir, dash_time)
			else:
				_stop_dash()
			_run_held_prev = run_held
			return

	# ── Normal walk (no Shift, or Shift blocked by repress) ──
	if dir != Vector2i.ZERO and not _dash_active:
		_set_facing(dir)
		if _can_move_to(_current_tile(), dir):
			_do_move(dir, walk_time)

	_run_held_prev = run_held

func _unhandled_input(event: InputEvent) -> void:
	if is_frozen or is_moving:
		return
	if event.is_action_pressed("attack"):
		_do_attack()

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  MOVEMENT
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _do_move(dir: Vector2i, duration: float) -> void:
	is_moving = true
	var target := _current_tile() + dir
	var tween := create_tween()
	tween.tween_property(self, "position", _tile_center(target), duration)
	tween.finished.connect(_on_move_finished)

func _on_move_finished() -> void:
	is_moving = false

	# ── Stairs ──
	if dungeon_map.get_tile_type(_current_tile()) == "stairs":
		_stop_dash()
		stepped_on_stairs.emit()
		return

	# ── Turn consumed → TurnManager orchestrates all phases ──
	var was_dashing := _dash_active
	var speed := dash_time if was_dashing else walk_time
	TurnManager.end_player_turn(speed)

	# ── Dash continuation (chained immediately for seamless auto-run) ──
	if _dash_active:
		_continue_dash()
		return

	# ── Walk continuation (chain while direction held) ──
	_continue_walk()

func _continue_dash() -> void:
	# Shift released → end dash
	if not _is_run_held():
		_stop_dash()
		return

	# Check direction change during dash
	var dir := _read_direction()
	if dir != Vector2i.ZERO and dir != _dash_dir:
		if dir == -_dash_dir:
			_stop_dash()
			return
		# Redirect dash
		_dash_dir = dir
		_set_facing(dir)

	# Check transition/wall/enemy stop
	if _is_dash_stop_point(_dash_dir):
		_stop_dash()
		return

	# Continue auto-run
	_do_move(_dash_dir, dash_time)

func _continue_walk() -> void:
	var dir := _read_direction()
	var run_held := _is_run_held()

	# Nothing held → stop
	if dir == Vector2i.ZERO and not run_held:
		return

	# Start dash from walk if Shift just pressed with direction
	if run_held and dir != Vector2i.ZERO:
		_dash_active = true
		_dash_dir = dir
		_set_facing(dir)
		if _can_move_to(_current_tile(), dir):
			_do_move(dir, dash_time)
		else:
			_stop_dash()
		return

	# Normal walk chain
	if dir != Vector2i.ZERO and _can_move_to(_current_tile(), dir):
		_set_facing(dir)
		_do_move(dir, walk_time)

func _stop_dash() -> void:
	_dash_active = false
	_dash_dir = Vector2i.ZERO

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  COMBAT
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _do_attack() -> void:
	var attack_tile := _current_tile() + facing
	if enemy_manager != null and enemy_manager.has_method("kill_enemy_at"):
		enemy_manager.kill_enemy_at(attack_tile)
	TurnManager.end_player_turn(walk_time)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  FACING
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _set_facing(dir: Vector2i) -> void:
	facing = dir
	_update_facing_arrow()

func _update_facing_arrow() -> void:
	var arrow := get_node_or_null("FacingArrow")
	if arrow != null:
		arrow.rotation = Vector2(facing).angle() + PI / 2.0

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  DASH STOP DETECTION
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _is_dash_stop_point(direction: Vector2i) -> bool:
	var tile := _current_tile()
	var next := tile + direction

	# Wall or enemy ahead
	if not _can_move_to(tile, direction):
		return true

	var cur_type: String = dungeon_map.get_tile_type(tile)
	var next_type: String = dungeon_map.get_tile_type(next)

	if cur_type == "room":
		# About to leave room into hallway
		if next_type == "hallway":
			return true
		# Perpendicular hallway nearby (near an exit)
		for p in _perpendiculars(direction):
			if dungeon_map.get_tile_type(tile + p) == "hallway":
				return true
	elif cur_type == "hallway":
		# About to enter a room
		if next_type == "room":
			return true
		# Intersection: perpendicular walkable tile
		for p in _perpendiculars(direction):
			if _is_walkable(tile + p):
				return true

	return false

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  INPUT HELPERS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

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

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  TILE HELPERS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _current_tile() -> Vector2i:
	var half := Vector2(tile_size / 2.0, tile_size / 2.0)
	return Vector2i(roundi((position.x - half.x) / tile_size), roundi((position.y - half.y) / tile_size))

func _tile_center(tile: Vector2i) -> Vector2:
	return Vector2(tile) * tile_size + Vector2(tile_size / 2.0, tile_size / 2.0)

func _can_move_to(origin: Vector2i, dir: Vector2i) -> bool:
	var target := origin + dir
	if not _is_walkable(target):
		return false
	if enemy_manager != null and enemy_manager.has_method("is_tile_occupied_by_enemy") and enemy_manager.is_tile_occupied_by_enemy(target):
		return false
	if dir.x != 0 and dir.y != 0:
		if not _is_walkable(origin + Vector2i(dir.x, 0)):
			return false
		if enemy_manager != null and enemy_manager.has_method("is_tile_occupied_by_enemy") and enemy_manager.is_tile_occupied_by_enemy(origin + Vector2i(dir.x, 0)):
			return false
		if not _is_walkable(origin + Vector2i(0, dir.y)):
			return false
		if enemy_manager != null and enemy_manager.has_method("is_tile_occupied_by_enemy") and enemy_manager.is_tile_occupied_by_enemy(origin + Vector2i(0, dir.y)):
			return false
	return true

func _is_walkable(coords: Vector2i) -> bool:
	return dungeon_map.is_walkable_tile(coords)
