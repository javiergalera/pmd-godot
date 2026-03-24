extends Node
## Universal floor transition — works for both 2D and 3D dungeons.
## Auto-detects the player node from sibling nodes.

signal mid_transition
signal transition_finished

@export var player_path: NodePath = ""

var is_transitioning := false

var _player_node: Node
var _fade_rect: ColorRect

func _ready() -> void:
	if not player_path.is_empty():
		_player_node = get_node_or_null(player_path)
	else:
		_player_node = get_node_or_null("../Player")
		if _player_node == null:
			_player_node = get_node_or_null("../Player3D")
	_fade_rect = get_node_or_null("../CanvasLayer/FadeRect")

func start() -> void:
	if is_transitioning:
		return
	is_transitioning = true

	var audio = get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_stairs()

	if _player_node:
		_player_node.is_frozen = true
		_player_node.is_moving = false
		if _player_node.has_method("reset_dash"):
			_player_node.reset_dash()

	if not _fade_rect:
		mid_transition.emit()
		return

	var tween_in := create_tween()
	tween_in.tween_property(_fade_rect, "color:a", 1.0, 0.5)
	await tween_in.finished
	mid_transition.emit()

func finish() -> void:
	if not _fade_rect:
		_end()
		return

	await get_tree().create_timer(0.3).timeout
	var tween_out := create_tween()
	tween_out.tween_property(_fade_rect, "color:a", 0.0, 0.5)
	await tween_out.finished
	_end()

func _end() -> void:
	if _player_node and is_instance_valid(_player_node):
		_player_node.is_frozen = false
	is_transitioning = false
	transition_finished.emit()
