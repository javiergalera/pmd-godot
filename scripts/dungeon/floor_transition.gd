extends Node

signal mid_transition
signal transition_finished

@onready var player_node: AnimatedSprite2D = get_node_or_null("../Player")
@onready var fade_rect: ColorRect = get_node_or_null("../CanvasLayer/FadeRect")

var is_transitioning := false

func start() -> void:
	if is_transitioning:
		return
	is_transitioning = true

	var audio = get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_stairs()

	if player_node:
		player_node.is_frozen = true
		player_node.is_moving = false
		if "_dash_active" in player_node:
			player_node._dash_active = false
			player_node._dash_dir = Vector2i.ZERO

	if not fade_rect:
		mid_transition.emit()
		return

	var tween_in := create_tween()
	tween_in.tween_property(fade_rect, "color:a", 1.0, 0.5)
	await tween_in.finished
	mid_transition.emit()

func finish() -> void:
	if not fade_rect:
		_end()
		return

	await get_tree().create_timer(0.3).timeout
	var tween_out := create_tween()
	tween_out.tween_property(fade_rect, "color:a", 0.0, 0.5)
	await tween_out.finished
	_end()

func _end() -> void:
	if player_node and is_instance_valid(player_node):
		player_node.is_frozen = false
	is_transitioning = false
	transition_finished.emit()
