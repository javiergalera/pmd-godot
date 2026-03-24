extends Node3D
## 3D fog-of-war overlay. A large plane hovering above the dungeon with a
## spatial shader that combines a player-circle and a tile vis-map, mirroring
## the 2D VisionOverlay approach.

const FOG_ALPHA := 0.55
const CIRCLE_RADIUS_TILES := 3.5
const ENEMY_PEEK_EXTRA := 1.0
const ENEMY_DIM_COLOR := Color(0.45, 0.45, 0.55)
const VIS_LERP_SPEED := 8.0

@onready var dungeon_map: Node3D = get_node_or_null("../DungeonRenderer3D")
@onready var player: Node = get_node_or_null("../Player3D")
@onready var enemy_manager: Node = get_node_or_null("../EnemyManager3D")
@onready var turn_manager: Node = get_node_or_null("../TurnManager")

var _tile_size: float = 2.0
var _last_player_tile := Vector2i(-1, -1)
var _visible_tiles: Dictionary = {}
var _in_hallway: bool = false

var _fog_mesh: MeshInstance3D
var _shader_mat: ShaderMaterial
var _vis_target: Image
var _vis_current: Image
var _vis_texture: ImageTexture
var _vis_dirty: bool = true

const _SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D vis_map : filter_linear;
uniform vec2 player_pos_xz;
uniform float circle_radius;
uniform float fog_alpha : hint_range(0.0, 1.0);
uniform vec2 dungeon_size_xz;

void fragment() {
	vec2 world_xz = UV * dungeon_size_xz;
	float tile_fog = texture(vis_map, UV).r;
	float dist = distance(world_xz, player_pos_xz);
	float edge = 1.5;
	float circle_fog = smoothstep(circle_radius - edge, circle_radius + 0.3, dist);
	float final_fog = min(tile_fog, circle_fog);
	ALBEDO = vec3(0.0);
	ALPHA = final_fog * fog_alpha;
}
"""

func _ready() -> void:
	if dungeon_map and "tile_size" in dungeon_map:
		_tile_size = dungeon_map.tile_size
	if turn_manager:
		turn_manager.enemy_phase_finished.connect(_update_enemy_visibility)
	_setup_fog_plane()

func _setup_fog_plane() -> void:
	var dw := DungeonData.FLOOR_MAX_X
	var dh := DungeonData.FLOOR_MAX_Y
	var size_xz := Vector2(dw * _tile_size, dh * _tile_size)

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
	_shader_mat.set_shader_parameter("dungeon_size_xz", size_xz)
	_shader_mat.set_shader_parameter("player_pos_xz", Vector2.ZERO)
	_shader_mat.set_shader_parameter("circle_radius", CIRCLE_RADIUS_TILES * _tile_size)

	var plane := PlaneMesh.new()
	plane.size = Vector2(size_xz.x, size_xz.y)

	_fog_mesh = MeshInstance3D.new()
	_fog_mesh.mesh = plane
	_fog_mesh.material_override = _shader_mat
	# Position: centered over dungeon, above walls
	var wall_h: float = 1.5
	if dungeon_map and "wall_height" in dungeon_map:
		wall_h = dungeon_map.wall_height
	_fog_mesh.position = Vector3(size_xz.x * 0.5, wall_h + 0.05, size_xz.y * 0.5)
	_fog_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fog_mesh)

func _process(delta: float) -> void:
	if player == null or dungeon_map == null:
		return
	# Pass player XZ position to shader
	_shader_mat.set_shader_parameter("player_pos_xz", Vector2(player.position.x, player.position.z))

	var pt: Vector2i = player.tile_position
	if pt != _last_player_tile:
		_last_player_tile = pt
		_recalculate_vision(pt)
		_update_vis_target()
		_update_enemy_visibility()

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
	for child in enemy_manager.get_children():
		if not is_instance_valid(child) or child.is_queued_for_deletion():
			continue
		if not ("tile_position" in child):
			continue
		if _visible_tiles.has(child.tile_position):
			child.visible = true
			_set_entity_dim(child, false)
		elif _in_hallway:
			var enemy_xz := Vector2(child.position.x, child.position.z)
			var player_xz := Vector2(player.position.x, player.position.z)
			var dist_sq := player_xz.distance_squared_to(enemy_xz)
			if dist_sq < vis_r_sq:
				child.visible = true
				_set_entity_dim(child, false)
			elif dist_sq < peek_r_sq:
				child.visible = true
				_set_entity_dim(child, true)
			else:
				child.visible = false
		else:
			child.visible = false

## Dim/undim a 3D entity by scaling its mesh albedo.
func _set_entity_dim(entity: Node, dimmed: bool) -> void:
	var meshes := _collect_mesh_instances(entity)
	for mi in meshes:
		if dimmed:
			if not mi.has_meta(&"_original_mat"):
				mi.set_meta(&"_original_mat", mi.get_active_material(0))
			var orig: Material = mi.get_meta(&"_original_mat")
			if orig is StandardMaterial3D:
				var dim_mat := orig.duplicate() as StandardMaterial3D
				dim_mat.albedo_color = ENEMY_DIM_COLOR
				mi.material_override = dim_mat
		else:
			if mi.has_meta(&"_original_mat"):
				mi.material_override = null

func _collect_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_collect_mesh_instances(child))
	return result

func is_tile_visible(tile: Vector2i) -> bool:
	return _visible_tiles.has(tile)

func refresh() -> void:
	_last_player_tile = Vector2i(-1, -1)
	if _vis_target:
		_vis_target.fill(Color(1, 0, 0))
		_vis_current.fill(Color(1, 0, 0))
		_vis_texture.update(_vis_current)
		_vis_dirty = true
