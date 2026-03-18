extends Control

@onready var floors_spin: SpinBox = %FloorsSpin
@onready var room_density_spin: SpinBox = %RoomDensitySpin
@onready var irregular_room_spin: SpinBox = %IrregularRoomSpin
@onready var floor_connectivity_spin: SpinBox = %FloorConnectivitySpin
@onready var enemy_density_spin: SpinBox = %EnemyDensitySpin
@onready var item_density_spin: SpinBox = %ItemDensitySpin
@onready var trap_density_spin: SpinBox = %TrapDensitySpin
@onready var room_obstacle_spin: SpinBox = %RoomObstacleSpin
@onready var seed_input: LineEdit = %SeedInput
@onready var error_label: Label = %ErrorLabel

func _ready() -> void:
	if has_node("/root/GameSettings"):
		var settings = get_node("/root/GameSettings")
		floors_spin.value = settings.total_floors
		room_density_spin.value = settings.room_density
		irregular_room_spin.value = settings.irregular_room_chance
		floor_connectivity_spin.value = settings.floor_connectivity
		enemy_density_spin.value = settings.enemy_density
		item_density_spin.value = settings.item_density
		trap_density_spin.value = settings.trap_density
		room_obstacle_spin.value = settings.room_obstacle_density
		if settings.has_custom_seed:
			seed_input.text = str(settings.seed_value)
		else:
			seed_input.text = ""
	seed_input.placeholder_text = "Leave empty for random"
	error_label.text = ""

func _on_start_button_pressed() -> void:
	error_label.text = ""

	if not has_node("/root/GameSettings"):
		error_label.text = "GameSettings was not found"
		return

	var settings = get_node("/root/GameSettings")
	settings.total_floors = int(floors_spin.value)
	settings.room_density = int(room_density_spin.value)
	settings.irregular_room_chance = int(irregular_room_spin.value)
	settings.floor_connectivity = int(floor_connectivity_spin.value)
	settings.enemy_density = int(enemy_density_spin.value)
	settings.item_density = int(item_density_spin.value)
	settings.trap_density = int(trap_density_spin.value)
	settings.room_obstacle_density = int(room_obstacle_spin.value)

	var seed_text := seed_input.text.strip_edges()
	if seed_text.is_empty():
		settings.has_custom_seed = false
		settings.seed_value = 0
	elif seed_text.is_valid_int():
		settings.has_custom_seed = true
		settings.seed_value = int(seed_text)
	else:
		error_label.text = "Seed must be an integer"
		return

	get_tree().change_scene_to_file("res://scenes/basic_tests.tscn")
