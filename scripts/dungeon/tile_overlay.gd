extends Node2D

@export var tile_size: int = 24

const COLOR_WALL_EDGE := Color(0.13, 0.11, 0.08, 0.72)
const COLOR_WALL_HIGHLIGHT := Color(0.34, 0.28, 0.19, 0.48)
const COLOR_WATER_EDGE := Color(0.85, 0.97, 1.0, 0.7)
const COLOR_WATER_CORNER := Color(0.73, 0.95, 1.0, 0.38)
const COLOR_FLOOR_SHADOW := Color(0.0, 0.0, 0.0, 0.16)

var _dungeon_map: TileMapLayer

func _ready() -> void:
	_dungeon_map = get_node_or_null("../TileMapLayer")

func refresh() -> void:
	queue_redraw()

func _draw() -> void:
	if _dungeon_map == null:
		return

	for x in range(DungeonData.FLOOR_MAX_X):
		for y in range(DungeonData.FLOOR_MAX_Y):
			var coords := Vector2i(x, y)
			var tile_type: String = _dungeon_map.get_tile_type(coords)
			var tile_rect := Rect2(Vector2(coords) * tile_size, Vector2.ONE * tile_size)

			match tile_type:
				"wall":
					_draw_wall_overlay(coords, tile_rect)
				"water":
					_draw_water_overlay(coords, tile_rect)
				"room", "hallway", "stairs":
					_draw_floor_overlay(coords, tile_rect)

func _draw_wall_overlay(coords: Vector2i, tile_rect: Rect2) -> void:
	var inset := 2.0
	var thickness := 3.0
	var open_top := _is_open_tile(_tile_type(coords + Vector2i.UP))
	var open_right := _is_open_tile(_tile_type(coords + Vector2i.RIGHT))
	var open_bottom := _is_open_tile(_tile_type(coords + Vector2i.DOWN))
	var open_left := _is_open_tile(_tile_type(coords + Vector2i.LEFT))

	if open_top:
		draw_rect(Rect2(tile_rect.position, Vector2(tile_size, thickness)), COLOR_WALL_HIGHLIGHT)
	if open_left:
		draw_rect(Rect2(tile_rect.position, Vector2(thickness, tile_size)), COLOR_WALL_HIGHLIGHT)
	if open_bottom:
		draw_rect(Rect2(tile_rect.position + Vector2(0, tile_size - thickness), Vector2(tile_size, thickness)), COLOR_WALL_EDGE)
	if open_right:
		draw_rect(Rect2(tile_rect.position + Vector2(tile_size - thickness, 0), Vector2(thickness, tile_size)), COLOR_WALL_EDGE)

	if open_top and open_left:
		draw_rect(Rect2(tile_rect.position + Vector2(inset, inset), Vector2(5, 5)), COLOR_WALL_HIGHLIGHT)
	if open_top and open_right:
		draw_rect(Rect2(tile_rect.position + Vector2(tile_size - inset - 5, inset), Vector2(5, 5)), COLOR_WALL_HIGHLIGHT)
	if open_bottom and open_left:
		draw_rect(Rect2(tile_rect.position + Vector2(inset, tile_size - inset - 5), Vector2(5, 5)), COLOR_WALL_EDGE)
	if open_bottom and open_right:
		draw_rect(Rect2(tile_rect.position + Vector2(tile_size - inset - 5, tile_size - inset - 5), Vector2(5, 5)), COLOR_WALL_EDGE)

func _draw_water_overlay(coords: Vector2i, tile_rect: Rect2) -> void:
	var thickness := 2.0
	var open_top := _is_open_tile(_tile_type(coords + Vector2i.UP))
	var open_right := _is_open_tile(_tile_type(coords + Vector2i.RIGHT))
	var open_bottom := _is_open_tile(_tile_type(coords + Vector2i.DOWN))
	var open_left := _is_open_tile(_tile_type(coords + Vector2i.LEFT))

	if open_top:
		draw_rect(Rect2(tile_rect.position, Vector2(tile_size, thickness)), COLOR_WATER_EDGE)
	if open_bottom:
		draw_rect(Rect2(tile_rect.position + Vector2(0, tile_size - thickness), Vector2(tile_size, thickness)), COLOR_WATER_EDGE)
	if open_left:
		draw_rect(Rect2(tile_rect.position, Vector2(thickness, tile_size)), COLOR_WATER_EDGE)
	if open_right:
		draw_rect(Rect2(tile_rect.position + Vector2(tile_size - thickness, 0), Vector2(thickness, tile_size)), COLOR_WATER_EDGE)

	if open_top and open_left:
		draw_rect(Rect2(tile_rect.position, Vector2(4, 4)), COLOR_WATER_CORNER)
	if open_top and open_right:
		draw_rect(Rect2(tile_rect.position + Vector2(tile_size - 4, 0), Vector2(4, 4)), COLOR_WATER_CORNER)
	if open_bottom and open_left:
		draw_rect(Rect2(tile_rect.position + Vector2(0, tile_size - 4), Vector2(4, 4)), COLOR_WATER_CORNER)
	if open_bottom and open_right:
		draw_rect(Rect2(tile_rect.position + Vector2(tile_size - 4, tile_size - 4), Vector2(4, 4)), COLOR_WATER_CORNER)

func _draw_floor_overlay(coords: Vector2i, tile_rect: Rect2) -> void:
	var thickness := 2.0
	if _tile_type(coords + Vector2i.UP) == "wall":
		draw_rect(Rect2(tile_rect.position, Vector2(tile_size, thickness)), COLOR_FLOOR_SHADOW)
	if _tile_type(coords + Vector2i.LEFT) == "wall":
		draw_rect(Rect2(tile_rect.position, Vector2(thickness, tile_size)), COLOR_FLOOR_SHADOW)
	if _tile_type(coords + Vector2i.RIGHT) == "water":
		draw_rect(Rect2(tile_rect.position + Vector2(tile_size - thickness, 0), Vector2(thickness, tile_size)), COLOR_WATER_EDGE)
	if _tile_type(coords + Vector2i.DOWN) == "water":
		draw_rect(Rect2(tile_rect.position + Vector2(0, tile_size - thickness), Vector2(tile_size, thickness)), COLOR_WATER_EDGE)

func _tile_type(coords: Vector2i) -> String:
	if coords.x < 0 or coords.x >= DungeonData.FLOOR_MAX_X or coords.y < 0 or coords.y >= DungeonData.FLOOR_MAX_Y:
		return "wall"
	return _dungeon_map.get_tile_type(coords)

func _is_open_tile(tile_type: String) -> bool:
	return tile_type == "room" or tile_type == "hallway" or tile_type == "stairs"