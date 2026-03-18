extends Sprite2D

@export var tile_size: int = 24

var tile_position: Vector2i = Vector2i.ZERO
var manager: Node

func configure(start_tile: Vector2i, map_tile_size: int, enemy_manager: Node) -> void:
	tile_size = map_tile_size
	tile_position = start_tile
	manager = enemy_manager
	position = _tile_center(tile_position)

func move_to_tile(target_tile: Vector2i, duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(self, "position", _tile_center(target_tile), duration)

func _tile_center(tile: Vector2i) -> Vector2:
	return Vector2(tile) * tile_size + Vector2(tile_size / 2.0, tile_size / 2.0)
