class_name TileEntity
extends AnimatedSprite2D

const ANIM_WALK: Dictionary = {
	Vector2i(0, 1): &"walk_down",
	Vector2i(1, 1): &"walk_down_right",
	Vector2i(1, 0): &"walk_right",
	Vector2i(1, -1): &"walk_up_right",
	Vector2i(0, -1): &"walk_up",
	Vector2i(-1, -1): &"walk_up_left",
	Vector2i(-1, 0): &"walk_left",
	Vector2i(-1, 1): &"walk_down_left",
}

const ANIM_IDLE: Dictionary = {
	Vector2i(0, 1): &"idle_down",
	Vector2i(1, 1): &"idle_down_right",
	Vector2i(1, 0): &"idle_right",
	Vector2i(1, -1): &"idle_up_right",
	Vector2i(0, -1): &"idle_up",
	Vector2i(-1, -1): &"idle_up_left",
	Vector2i(-1, 0): &"idle_left",
	Vector2i(-1, 1): &"idle_down_left",
}

const ANIM_ATTACK: Dictionary = {
	Vector2i(0, 1): &"attack_down",
	Vector2i(1, 1): &"attack_down_right",
	Vector2i(1, 0): &"attack_right",
	Vector2i(1, -1): &"attack_up_right",
	Vector2i(0, -1): &"attack_up",
	Vector2i(-1, -1): &"attack_up_left",
	Vector2i(-1, 0): &"attack_left",
	Vector2i(-1, 1): &"attack_down_left",
}

const ANIM_HURT: Dictionary = {
	Vector2i(0, 1): &"hurt_down",
	Vector2i(1, 1): &"hurt_down_right",
	Vector2i(1, 0): &"hurt_right",
	Vector2i(1, -1): &"hurt_up_right",
	Vector2i(0, -1): &"hurt_up",
	Vector2i(-1, -1): &"hurt_up_left",
	Vector2i(-1, 0): &"hurt_left",
	Vector2i(-1, 1): &"hurt_down_left",
}

@export var tile_size: int = 24

var tile_position: Vector2i = Vector2i.ZERO
var facing: Vector2i = Vector2i.DOWN

func play_walk() -> void:
	var anim_name: StringName = ANIM_WALK.get(facing, &"walk_down")
	if animation != anim_name:
		play(anim_name)
	elif not is_playing():
		play(anim_name)

func play_idle() -> void:
	play(ANIM_IDLE.get(facing, &"idle_down"))

func play_attack() -> void:
	play(ANIM_ATTACK.get(facing, &"attack_down"))

func play_hurt() -> void:
	play(ANIM_HURT.get(facing, &"hurt_down"))

func face_toward(target_tile: Vector2i) -> void:
	var dir := (target_tile - tile_position).sign()
	if dir != Vector2i.ZERO:
		facing = dir
		_update_z_order()

func update_z_order() -> void:
	_update_z_order()

func _update_z_order() -> void:
	z_index = tile_position.y * 2 + (1 if facing.y > 0 else 0)

func tile_center(tile: Vector2i) -> Vector2:
	return Vector2(tile) * tile_size + Vector2(tile_size / 2.0, tile_size / 2.0)
