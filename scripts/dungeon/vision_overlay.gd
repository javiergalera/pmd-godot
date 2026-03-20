extends Node2D
## Fog-of-war overlay for PMD-style vision.
##
## Circle always follows the player (smooth, every frame).
## In rooms the vis-map clears the room area; the shader merges both
## shapes with min() so they form one unified silhouette.
## Vis-map transitions are lerped each frame for smooth fade.

const FOG_ALPHA := 0.55
const CIRCLE_RADIUS_TILES := 3.5
const ENEMY_PEEK_EXTRA := 1.0
const ENEMY_DIM_COLOR := Color(0.45, 0.45, 0.55)
const VIS_LERP_SPEED := 8.0  # fog value lerp per second

@onready var dungeon_map: TileMapLayer = get_node_or_null("../TileMapLayer")
@onready var player: Node2D = get_node_or_null("../Player")
@onready var enemy_manager: Node2D = get_node_or_null("../EnemyManager")
@onready var turn_manager: Node = get_node_or_null("../TurnManager")

var _tile_size: int = 24
var _last_player_tile := Vector2i(-1, -1)
var _visible_tiles: Dictionary = {}
var _in_hallway: bool = false

var _fog_sprite: Sprite2D
var _shader_mat: ShaderMaterial
var _vis_target: Image      # target fog values (0=visible, 1=fogged)
var _vis_current: Image     # current interpolated values
var _vis_texture: ImageTexture
var _vis_dirty: bool = true # true while lerp hasn't converged

const _SHADER_CODE := """
shader_type canvas_item;

uniform sampler2D vis_map : filter_linear;
uniform vec2 player_pos_px;
uniform float circle_radius_px;
uniform float fog_alpha : hint_range(0.0, 1.0);
uniform vec2 dungeon_size_px;

void fragment() {
	float tile_fog = texture(vis_map, UV).r;
	vec2 world_pos = UV * dungeon_size_px;
	float dist = distance(world_pos, player_pos_px);
	float edge = 16.0;
	float circle_fog = smoothstep(circle_radius_px - edge, circle_radius_px + 2.0, dist);
	float final_fog = min(tile_fog, circle_fog);
	COLOR = vec4(0.0, 0.0, 0.0, final_fog * fog_alpha);
}
"""

func _ready() -> void:
	if dungeon_map:
		_tile_size = dungeon_map.tile_size
	if turn_manager:
		turn_manager.enemy_phase_finished.connect(_update_enemy_visibility)
	_setup_fog_shader()

func _setup_fog_shader() -> void:
	var dw := DungeonData.FLOOR_MAX_X
	var dh := DungeonData.FLOOR_MAX_Y
	var size_px := Vector2(dw * _tile_size, dh * _tile_size)

	_vis_target = Image.create(dw, dh, false, Image.FORMAT_R8)
	_vis_target.fill(Color(1, 0, 0))
	_vis_current = Image.create(dw, dh, false, Image.FORMAT_R8)
	_vis_current.fill(Color(1, 0, 0))
	_vis_texture = ImageTexture.create_from_image(_vis_current)

	var shader := Shader.new()
	shader.code = _SHADER_CODE
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = shader
	_shader_mat.set_shader_parameter("vis_map", _vis_texture)
	_shader_mat.set_shader_parameter("fog_alpha", FOG_ALPHA)
	_shader_mat.set_shader_parameter("dungeon_size_px", size_px)
	_shader_mat.set_shader_parameter("player_pos_px", Vector2.ZERO)
	_shader_mat.set_shader_parameter("circle_radius_px", CIRCLE_RADIUS_TILES * _tile_size)

	var white_img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	white_img.fill(Color.WHITE)

	_fog_sprite = Sprite2D.new()
	_fog_sprite.texture = ImageTexture.create_from_image(white_img)
	_fog_sprite.centered = false
	_fog_sprite.scale = size_px
	_fog_sprite.material = _shader_mat
	add_child(_fog_sprite)

func _process(delta: float) -> void:
	if player == null or dungeon_map == null:
		return
	_shader_mat.set_shader_parameter("player_pos_px", player.position)

	var pt: Vector2i = player.tile_position
	if pt != _last_player_tile:
		_last_player_tile = pt
		_recalculate_vision(pt)
		_update_vis_target()
		_update_enemy_visibility()

	# Lerp vis_current toward vis_target each frame
	if _vis_dirty:
		var converged := true
		var step := VIS_LERP_SPEED * delta
		for x in range(DungeonData.FLOOR_MAX_X):
			for y in range(DungeonData.FLOOR_MAX_Y):
				var cur: float = _vis_current.get_pixel(x, y).r
				var tgt: float = _vis_target.get_pixel(x, y).r
				if not is_equal_approx(cur, tgt):
					cur = move_toward(cur, tgt, step)
					_vis_current.set_pixel(x, y, Color(cur, 0, 0))
					converged = false
		_vis_texture.update(_vis_current)
		if converged:
			_vis_dirty = false

func _recalculate_vision(player_tile: Vector2i) -> void:
	_visible_tiles.clear()
	var tile_type: String = dungeon_map.get_tile_type(player_tile)
	_in_hallway = tile_type != "room"

	if tile_type == "room":
		_reveal_room(player_tile)
	# Always reveal adjacent rooms (from room or hallway)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var adj := player_tile + Vector2i(dx, dy)
			if dungeon_map.get_tile_type(adj) == "room":
				_reveal_room(adj)

func _reveal_room(origin_tile: Vector2i) -> void:
	var room: int = dungeon_map.get_room_index(origin_tile)
	if room >= 0xF0:
		return
	for x in range(DungeonData.FLOOR_MAX_X):
		for y in range(DungeonData.FLOOR_MAX_Y):
			var tile := Vector2i(x, y)
			if dungeon_map.get_room_index(tile) == room:
				_visible_tiles[tile] = true
				for ddx in range(-1, 2):
					for ddy in range(-1, 2):
						_visible_tiles[tile + Vector2i(ddx, ddy)] = true

func _update_vis_target() -> void:
	for x in range(DungeonData.FLOOR_MAX_X):
		for y in range(DungeonData.FLOOR_MAX_Y):
			if _visible_tiles.has(Vector2i(x, y)):
				_vis_target.set_pixel(x, y, Color(0, 0, 0))
			else:
				_vis_target.set_pixel(x, y, Color(1, 0, 0))
	_vis_dirty = true

func _update_enemy_visibility() -> void:
	if enemy_manager == null or player == null:
		return
	var vis_r := CIRCLE_RADIUS_TILES * _tile_size
	var peek_r := (CIRCLE_RADIUS_TILES + ENEMY_PEEK_EXTRA) * _tile_size
	var vis_r_sq := vis_r ** 2
	var peek_r_sq := peek_r ** 2
	var half := Vector2(_tile_size / 2.0, _tile_size / 2.0)
	for child in enemy_manager.get_children():
		if not is_instance_valid(child) or child.is_queued_for_deletion():
			continue
		if not ("tile_position" in child):
			continue
		if _visible_tiles.has(child.tile_position):
			child.visible = true
			child.modulate = Color.WHITE
		elif _in_hallway:
			var enemy_center := Vector2(child.tile_position) * _tile_size + half
			var dist_sq := player.position.distance_squared_to(enemy_center)
			if dist_sq < vis_r_sq:
				child.visible = true
				child.modulate = Color.WHITE
			elif dist_sq < peek_r_sq:
				child.visible = true
				child.modulate = ENEMY_DIM_COLOR
			else:
				child.visible = false
		else:
			child.visible = false

func is_tile_visible(tile: Vector2i) -> bool:
	return _visible_tiles.has(tile)

func refresh() -> void:
	_last_player_tile = Vector2i(-1, -1)
	if _vis_target:
		_vis_target.fill(Color(1, 0, 0))
		_vis_current.fill(Color(1, 0, 0))
		_vis_texture.update(_vis_current)
		_vis_dirty = true
