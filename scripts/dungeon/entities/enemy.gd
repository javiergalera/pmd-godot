extends "res://scripts/dungeon/entities/tile_entity.gd"

var manager: Node
var _move_tween: Tween
var _move_id: int = 0

func configure(start_tile: Vector2i, map_tile_size: int, enemy_manager: Node) -> void:
	tile_size = map_tile_size
	tile_position = start_tile
	manager = enemy_manager
	position = tile_center(tile_position)
	set_meta(&"is_enemy", true)
	_update_z_order()
	play_idle()

func move_to_tile(target_tile: Vector2i, duration: float) -> void:
	_move_id += 1
	var current_id := _move_id
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
	var dir := target_tile - tile_position
	if dir != Vector2i.ZERO:
		facing = dir.sign()
		play_walk()
	tile_position = target_tile
	_update_z_order()
	_move_tween = create_tween()
	_move_tween.tween_property(self, "position", tile_center(target_tile), duration)
	_move_tween.finished.connect(func(): call_deferred(&"_on_move_done", current_id))

func _on_move_done(id: int) -> void:
	if id == _move_id:
		play_idle()

func stop_walking() -> void:
	play_idle()
