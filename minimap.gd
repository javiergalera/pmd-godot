extends Control
## Minimap showing explored dungeon tiles.
## Reveals entire rooms when entered; shows a limited radius in hallways.

const FLOOR_MAX_X := 56
const FLOOR_MAX_Y := 32

@export var pixel_scale: int = 3
@export var vision_radius: int = 4

var explored: Dictionary = {}

var _player: Node2D
var _dungeon_map: TileMapLayer
var _tile_size: int = 24
var _last_revealed_tile := Vector2i(-1, -1)

var _color_bg := Color(0.05, 0.05, 0.1, 0.75)
var _color_wall := Color(0.3, 0.3, 0.4)
var _color_room := Color(0.5, 0.6, 0.5)
var _color_hallway := Color(0.45, 0.45, 0.55)
var _color_water := Color(0.3, 0.4, 0.75)
var _color_stairs := Color(1.0, 1.0, 1.0)
var _color_player := Color(1.0, 0.9, 0.15)

func _ready() -> void:
	_dungeon_map = get_node("/root/Node2D/TileMapLayer")
	_player = get_node("/root/Node2D/Player")
	_tile_size = _dungeon_map.tile_size
	size = Vector2(FLOOR_MAX_X * pixel_scale, FLOOR_MAX_Y * pixel_scale)
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	var pt := _player_tile()
	if pt != _last_revealed_tile:
		_last_revealed_tile = pt
		_reveal(pt)
	queue_redraw()

func _reveal(center: Vector2i) -> void:
	for dx in range(-vision_radius, vision_radius + 1):
		for dy in range(-vision_radius, vision_radius + 1):
			var t := center + Vector2i(dx, dy)
			if t.x >= 0 and t.x < FLOOR_MAX_X and t.y >= 0 and t.y < FLOOR_MAX_Y:
				explored[t] = true
	if _dungeon_map.get_tile_type(center) == "room":
		_flood_reveal_room(center)

func _flood_reveal_room(start: Vector2i) -> void:
	var stack: Array[Vector2i] = [start]
	var visited: Dictionary = {}
	while stack.size() > 0:
		var t: Vector2i = stack.pop_back()
		if visited.has(t):
			continue
		visited[t] = true
		if t.x < 0 or t.x >= FLOOR_MAX_X or t.y < 0 or t.y >= FLOOR_MAX_Y:
			continue
		explored[t] = true
		if _dungeon_map.get_tile_type(t) == "room":
			stack.append(t + Vector2i(1, 0))
			stack.append(t + Vector2i(-1, 0))
			stack.append(t + Vector2i(0, 1))
			stack.append(t + Vector2i(0, -1))

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), _color_bg)
	for tile_key in explored:
		var tile: Vector2i = tile_key
		var c: Color
		match _dungeon_map.get_tile_type(tile):
			"room": c = _color_room
			"hallway": c = _color_hallway
			"water": c = _color_water
			"stairs": c = _color_stairs
			_: c = _color_wall
		draw_rect(Rect2(tile.x * pixel_scale, tile.y * pixel_scale, pixel_scale, pixel_scale), c)
	var pt := _player_tile()
	draw_rect(Rect2(pt.x * pixel_scale, pt.y * pixel_scale, pixel_scale, pixel_scale), _color_player)

func _player_tile() -> Vector2i:
	var half := Vector2(_tile_size / 2.0, _tile_size / 2.0)
	return Vector2i(
		roundi((_player.position.x - half.x) / _tile_size),
		roundi((_player.position.y - half.y) / _tile_size)
	)

func reset() -> void:
	explored.clear()
	_last_revealed_tile = Vector2i(-1, -1)
