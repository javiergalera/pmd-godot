extends AnimatedSprite2D

const _WALK_NAMES: Dictionary = {
	Vector2i(0, 1): &"walk_down",
	Vector2i(1, 1): &"walk_down_right",
	Vector2i(1, 0): &"walk_right",
	Vector2i(1, -1): &"walk_up_right",
	Vector2i(0, -1): &"walk_up",
	Vector2i(-1, -1): &"walk_up_left",
	Vector2i(-1, 0): &"walk_left",
	Vector2i(-1, 1): &"walk_down_left",
}

const _IDLE_NAMES: Dictionary = {
	Vector2i(0, 1): &"idle_down",
	Vector2i(1, 1): &"idle_down_right",
	Vector2i(1, 0): &"idle_right",
	Vector2i(1, -1): &"idle_up_right",
	Vector2i(0, -1): &"idle_up",
	Vector2i(-1, -1): &"idle_up_left",
	Vector2i(-1, 0): &"idle_left",
	Vector2i(-1, 1): &"idle_down_left",
}

const _HURT_NAMES: Dictionary = {
	Vector2i(0, 1): &"hurt_down",
	Vector2i(1, 1): &"hurt_down_right",
	Vector2i(1, 0): &"hurt_right",
	Vector2i(1, -1): &"hurt_up_right",
	Vector2i(0, -1): &"hurt_up",
	Vector2i(-1, -1): &"hurt_up_left",
	Vector2i(-1, 0): &"hurt_left",
	Vector2i(-1, 1): &"hurt_down_left",
}

const _ATTACK_NAMES: Dictionary = {
	Vector2i(0, 1): &"attack_down",
	Vector2i(1, 1): &"attack_down_right",
	Vector2i(1, 0): &"attack_right",
	Vector2i(1, -1): &"attack_up_right",
	Vector2i(0, -1): &"attack_up",
	Vector2i(-1, -1): &"attack_up_left",
	Vector2i(-1, 0): &"attack_left",
	Vector2i(-1, 1): &"attack_down_left",
}

@export var tile_size: int = 24

var tile_position: Vector2i = Vector2i.ZERO
var facing: Vector2i = Vector2i.DOWN
var manager: Node

func configure(start_tile: Vector2i, map_tile_size: int, enemy_manager: Node) -> void:
	tile_size = map_tile_size
	tile_position = start_tile
	manager = enemy_manager
	position = _tile_center(tile_position)
	play(_IDLE_NAMES.get(facing, &"idle_down"))

func move_to_tile(target_tile: Vector2i, duration: float) -> void:
	var dir := target_tile - tile_position
	if dir != Vector2i.ZERO:
		facing = dir.sign()
		var anim_name: StringName = _WALK_NAMES.get(facing, &"walk_down")
		if animation != anim_name:
			play(anim_name)
		elif not is_playing():
			play(anim_name)
	var tween := create_tween()
	tween.tween_property(self, "position", _tile_center(target_tile), duration)

func stop_walking() -> void:
	play(_IDLE_NAMES.get(facing, &"idle_down"))

func face_toward(target_tile: Vector2i) -> void:
	var dir := (target_tile - tile_position).sign()
	if dir != Vector2i.ZERO:
		facing = dir

func play_hurt() -> void:
	play(_HURT_NAMES.get(facing, &"hurt_down"))

func play_attack() -> void:
	play(_ATTACK_NAMES.get(facing, &"attack_down"))

func _tile_center(tile: Vector2i) -> Vector2:
	return Vector2(tile) * tile_size + Vector2(tile_size / 2.0, tile_size / 2.0)
