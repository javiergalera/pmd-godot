class_name CombatResolver
extends RefCounted

static func resolve_attack(attacker: Node, attacker_tile: Vector2i,
		defender: Node, defender_tile: Vector2i,
		skip_defender_reaction: bool = false) -> void:
	if attacker.has_method("face_toward"):
		attacker.face_toward(defender_tile)
	# Z-index boost only for 2D nodes on the same row (horizontal attacks)
	var old_z := 0
	var is_2d := attacker is Node2D
	if is_2d:
		old_z = attacker.z_index
		if attacker_tile.y == defender_tile.y:
			attacker.z_index = maxi(attacker.z_index, defender.z_index) + 1
	if attacker.has_method("play_attack"):
		# Play the appropriate attack sound
		var audio = attacker.get_node_or_null("/root/AudioManager")
		if audio:
			if attacker.get_meta(&"is_enemy", false):
				audio.play_enemy_attack()
			else:
				audio.play_player_attack()
		attacker.play_attack()
		await attacker.animation_finished
	if is_2d:
		attacker.z_index = old_z
	if skip_defender_reaction:
		return
	if defender.has_method("face_toward"):
		defender.face_toward(attacker_tile)
	if defender.has_method("play_hurt"):
		defender.play_hurt()
		await defender.animation_finished
	if defender.has_method("play_idle"):
		defender.play_idle()
