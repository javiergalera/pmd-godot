class_name TileEntity3D
extends Node3D
## Base class for 3D tile-based entities using imported 3D models.
## Loads a model scene, finds its AnimationPlayer, and maps animations.

@export var model_scene: PackedScene
@export var tile_size: float = 1.0
@export var model_scale: Vector3 = Vector3(1, 1, 1)
## Target height for the model in world units. If > 0, auto-scales model to fit.
@export var target_height: float = 1.2

var tile_position: Vector2i = Vector2i.ZERO
var facing: Vector2i = Vector2i.DOWN

var _model_node: Node3D
var _anim_player: AnimationPlayer
var _anim_map: Dictionary = {}  # "idle" → actual animation name

signal animation_finished

var speed_scale: float = 1.0:
	set(v):
		speed_scale = v
		if _anim_player:
			_anim_player.speed_scale = v

func _setup_model() -> void:
	if model_scene == null:
		push_warning("TileEntity3D: model_scene is null on %s" % name)
		_model_node = Node3D.new()
		var debug_mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.5, 1.0, 0.5)
		debug_mesh.mesh = box
		debug_mesh.position.y = 0.5
		_model_node.add_child(debug_mesh)
		add_child(_model_node)
		return

	_model_node = model_scene.instantiate()
	add_child(_model_node)

	# Auto-scale based on actual AABB
	var aabb := _compute_model_aabb(_model_node)
	if aabb.size.length() > 0.0 and target_height > 0.0:
		var model_height := aabb.size.y
		if model_height > 0.001:
			var scale_factor := target_height / model_height
			_model_node.scale = Vector3(scale_factor, scale_factor, scale_factor)
		else:
			_model_node.scale = model_scale
	else:
		_model_node.scale = model_scale

	_find_animation_player(_model_node)
	_build_animation_map()
	if not _anim_player:
		push_warning("TileEntity3D [%s]: No AnimationPlayer found in model" % name)
	_update_facing_rotation()

func _compute_model_aabb(_node: Node) -> AABB:
	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(_node, meshes)
	if meshes.is_empty():
		return AABB()
	var result := AABB()
	var first := true
	for mi in meshes:
		if mi.mesh == null:
			continue
		var mesh_aabb := mi.mesh.get_aabb()
		# Transform corners into model_node local space
		var mi_to_model := _model_node.global_transform.affine_inverse() * mi.global_transform
		for i in range(8):
			var corner := Vector3(
				mesh_aabb.position.x + mesh_aabb.size.x * (1.0 if (i & 1) else 0.0),
				mesh_aabb.position.y + mesh_aabb.size.y * (1.0 if (i & 2) else 0.0),
				mesh_aabb.position.z + mesh_aabb.size.z * (1.0 if (i & 4) else 0.0),
			)
			var local_pt := mi_to_model * corner
			if first:
				result.position = local_pt
				result.size = Vector3.ZERO
				first = false
			else:
				result = result.expand(local_pt)
	return result

func _collect_mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_mesh_instances(child, out)

func _find_animation_player(node: Node) -> void:
	if node is AnimationPlayer:
		_anim_player = node
		_anim_player.animation_finished.connect(_on_anim_finished)
		return
	for child in node.get_children():
		_find_animation_player(child)
		if _anim_player:
			return

func _build_animation_map() -> void:
	if _anim_player == null:
		return
	var anims := _anim_player.get_animation_list()
	# Two passes: first pass skips event animations (bd_evXXX_), second pass includes them as fallback
	for pass_idx in range(2):
		for anim_name in anims:
			# Strip library prefix (e.g. "LibName/bd_wait" → "bd_wait") for keyword matching
			var base_name := anim_name
			if "/" in base_name:
				base_name = base_name.get_slice("/", base_name.get_slice_count("/") - 1)
			var lower := base_name.to_lower()
			# On first pass, skip event/cutscene animations (bd_evNNN_*)
			if pass_idx == 0 and lower.contains("_ev"):
				continue
			# Idle / wait / stand / breathe
			if not _anim_map.has("idle"):
				if "idle" in lower or "wait" in lower or "stand" in lower or "breath" in lower:
					_anim_map["idle"] = anim_name
			# Walk / run / move / locomotion
			if not _anim_map.has("walk"):
				if "walk" in lower or "run" in lower or "move" in lower or "locomot" in lower:
					_anim_map["walk"] = anim_name
			# Attack / slash / punch / kick / tackle
			if not _anim_map.has("attack"):
				if "attack" in lower or "slash" in lower or "punch" in lower or "kick" in lower or "tackle" in lower:
					_anim_map["attack"] = anim_name
			# Damage (bd_damage) — hurt but alive
			if not _anim_map.has("hurt"):
				if "bd_damage" in lower or "damage" in lower or "hurt" in lower or "pain" in lower or "flinch" in lower:
					_anim_map["hurt"] = anim_name
			# Fall (bd_fall) — death/faint
			if not _anim_map.has("fall"):
				if "bd_fall" in lower or "fall" in lower or "faint" in lower or "death" in lower or "die" in lower:
					_anim_map["fall"] = anim_name
	# Fallback: if no idle found, use first non-RESET animation
	if not _anim_map.has("idle") and anims.size() > 0:
		for anim_name in anims:
			if anim_name != "RESET" and not anim_name.ends_with("/RESET"):
				_anim_map["idle"] = anim_name
				break
	# Fallback: if still no walk, use idle for walk
	if not _anim_map.has("walk") and _anim_map.has("idle"):
		_anim_map["walk"] = _anim_map["idle"]

func _on_anim_finished(_anim_name: StringName) -> void:
	animation_finished.emit()

func play_walk() -> void:
	_play_mapped("walk")

func play_idle() -> void:
	_play_mapped("idle")

func play_attack() -> void:
	_play_mapped("attack", false)

func play_hurt() -> void:
	_play_mapped("hurt", false)

func play_defeat_blink() -> void:
	## PMD-style blink effect during hurt animation: both run simultaneously.
	_play_mapped("hurt", false)
	var blink_count := 6
	var blink_speed := 0.08
	var tw := create_tween()
	for i in range(blink_count):
		tw.tween_callback(func(): visible = false)
		tw.tween_interval(blink_speed)
		tw.tween_callback(func(): visible = true)
		tw.tween_interval(blink_speed)
	tw.tween_callback(func(): visible = false)
	await tw.finished

func _play_mapped(key: String, looped: bool = true) -> void:
	if _anim_player == null:
		return
	var anim_name: String = _anim_map.get(key, "")
	if anim_name.is_empty():
		anim_name = _anim_map.get("idle", "")
	if anim_name.is_empty():
		return
	# Stop current animation before switching to a different one
	if _anim_player.current_animation != anim_name:
		_anim_player.stop()
	# Set loop mode on the animation resource
	var anim := _anim_player.get_animation(anim_name)
	if anim:
		anim.loop_mode = Animation.LOOP_LINEAR if looped else Animation.LOOP_NONE
	_anim_player.play(anim_name)

func is_playing() -> bool:
	return _anim_player != null and _anim_player.is_playing()

func face_toward(target_tile: Vector2i) -> void:
	var dir := (target_tile - tile_position).sign()
	if dir != Vector2i.ZERO:
		facing = dir
		_update_facing_rotation()

func _update_facing_rotation() -> void:
	if _model_node == null:
		return
	# facing: (x, y) where y is down on the grid → z in 3D
	var angle := atan2(float(facing.x), float(facing.y))
	_model_node.rotation.y = angle

func update_z_order() -> void:
	pass

func _update_z_order() -> void:
	pass

func tile_center_3d(tile: Vector2i) -> Vector3:
	return Vector3(tile.x * tile_size + tile_size * 0.5, 0.0, tile.y * tile_size + tile_size * 0.5)
