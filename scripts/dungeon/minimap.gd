extends Control
## Minimap showing explored dungeon tiles.
## Reveals entire rooms when entered; shows a limited radius in hallways.

@export var pixel_scale: int = 3
@export var vision_radius: int = 4

@onready var dungeon_map: TileMapLayer = get_node_or_null("../../TileMapLayer")
@onready var player: Node2D = get_node_or_null("../../Player")
var explored: Dictionary = {}
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
	if dungeon_map:
		_tile_size = dungeon_map.tile_size
	size = Vector2(DungeonData.FLOOR_MAX_X * pixel_scale, DungeonData.FLOOR_MAX_Y * pixel_scale)
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	if player == null or dungeon_map == null:
		return
	var pt: Vector2i = player.tile_position
	if pt != _last_revealed_tile:
		_last_revealed_tile = pt
		_reveal(pt)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), _color_bg)
	for tile_key in explored:
		var tile: Vector2i = tile_key
		var c: Color
		match dungeon_map.get_tile_type(tile):
			"room": c = _color_room
			"hallway": c = _color_hallway
			"water": c = _color_water
			"stairs": c = _color_stairs
			_: c = _color_wall
		draw_rect(Rect2(tile.x * pixel_scale, tile.y * pixel_scale, pixel_scale, pixel_scale), c)
	if player == null:
		return
	var pt: Vector2i = player.tile_position
	draw_rect(Rect2(pt.x * pixel_scale, pt.y * pixel_scale, pixel_scale, pixel_scale), _color_player)

func _reveal(center: Vector2i) -> void:
	for dx in range(-vision_radius, vision_radius + 1):
		for dy in range(-vision_radius, vision_radius + 1):
			var tile := center + Vector2i(dx, dy)
			if tile.x >= 0 and tile.x < DungeonData.FLOOR_MAX_X and tile.y >= 0 and tile.y < DungeonData.FLOOR_MAX_Y:
				explored[tile] = true
	if dungeon_map.get_tile_type(center) == "room":
		_flood_reveal_room(center)

func _flood_reveal_room(start: Vector2i) -> void:
	var stack: Array[Vector2i] = [start]
	var visited: Dictionary = {}
	while stack.size() > 0:
		var tile: Vector2i = stack.pop_back()
		if visited.has(tile):
			continue
		visited[tile] = true
		if tile.x < 0 or tile.x >= DungeonData.FLOOR_MAX_X or tile.y < 0 or tile.y >= DungeonData.FLOOR_MAX_Y:
			continue
		explored[tile] = true
		if dungeon_map.get_tile_type(tile) == "room":
			stack.append(tile + Vector2i(1, 0))
			stack.append(tile + Vector2i(-1, 0))
			stack.append(tile + Vector2i(0, 1))
			stack.append(tile + Vector2i(0, -1))

func reset() -> void:
	explored.clear()
	_last_revealed_tile = Vector2i(-1, -1)
	queue_redraw()
