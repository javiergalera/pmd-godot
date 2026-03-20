class_name DungeonData
extends RefCounted
## Data types, enums, and constants for dungeon-mystery algorithm (PMD:EoS).

# ──────────────────────────────────────────────
#  Floor Properties
# ──────────────────────────────────────────────
enum FloorLayout {
	LAYOUT_LARGE,
	LAYOUT_SMALL,
	LAYOUT_ONE_ROOM_MONSTER_HOUSE,
	LAYOUT_OUTER_RING,
	LAYOUT_CROSSROADS,
	LAYOUT_TWO_ROOMS_WITH_MONSTER_HOUSE,
	LAYOUT_LINE,
	LAYOUT_CROSS,
	LAYOUT_LARGE_0x8,
	LAYOUT_BEETLE,
	LAYOUT_OUTER_ROOMS,
	LAYOUT_MEDIUM,
	LAYOUT_UNUSED_0xC,
	LAYOUT_UNUSED_0xD,
	LAYOUT_UNUSED_0xE,
	LAYOUT_UNUSED_0xF,
}

# ──────────────────────────────────────────────
#  Dungeon Tile Data
# ──────────────────────────────────────────────
enum TerrainType {
	TERRAIN_WALL,
	TERRAIN_NORMAL,
	TERRAIN_SECONDARY,
	TERRAIN_CHASM,
}

enum SecondaryTerrainType {
	SECONDARY_TERRAIN_WATER,
	SECONDARY_TERRAIN_LAVA,
	SECONDARY_TERRAIN_CHASM,
}

# ──────────────────────────────────────────────
#  Dungeon Data
# ──────────────────────────────────────────────
enum DungeonObjectiveType {
	OBJECTIVE_STORY,
	OBJECTIVE_NORMAL,
	OBJECTIVE_RESCUE,
	OBJECTIVE_UNK_GAMEMODE_5,
}

enum MissionType {
	MISSION_RESCUE_CLIENT,
	MISSION_RESCUE_TARGET,
	MISSION_ESCORT_TO_TARGET,
	MISSION_EXPLORE_WITH_CLIENT,
	MISSION_PROSPECT_WITH_CLIENT,
	MISSION_GUIDE_CLIENT,
	MISSION_FIND_ITEM,
	MISSION_DELIVER_ITEM,
	MISSION_SEARCH_FOR_TARGET,
	MISSION_TAKE_ITEM_FROM_OUTLAW,
	MISSION_ARREST_OUTLAW,
	MISSION_CHALLENGE_REQUEST,
	MISSION_TREASURE_MEMO,
}

enum MissionSubtypeChallenge {
	MISSION_CHALLENGE_NORMAL,
	MISSION_CHALLENGE_MEWTWO,
	MISSION_CHALLENGE_ENTEI,
	MISSION_CHALLENGE_RAIKOU,
	MISSION_CHALLENGE_SUICUNE,
	MISSION_CHALLENGE_JIRACHI,
}

enum MissionSubtypeExplore {
	MISSION_EXPLORE_NORMAL,
	MISSION_EXPLORE_SEALED_CHAMBER,
	MISSION_EXPLORE_GOLDEN_CHAMBER,
	MISSION_EXPLORE_NEW_DUNGEON,
}

enum MissionSubtypeOutlaw {
	MISSION_OUTLAW_NORMAL_0,
	MISSION_OUTLAW_NORMAL_1,
	MISSION_OUTLAW_NORMAL_2,
	MISSION_OUTLAW_NORMAL_3,
	MISSION_OUTLAW_ESCORT,
	MISSION_OUTLAW_FLEEING,
	MISSION_OUTLAW_HIDEOUT,
	MISSION_OUTLAW_MONSTER_HOUSE,
}

enum MissionSubtypeTakeItem {
	MISSION_TAKE_ITEM_NORMAL_OUTLAW,
	MISSION_TAKE_ITEM_HIDDEN_OUTLAW,
	MISSION_TAKE_ITEM_FLEEING_OUTLAW,
}

# ──────────────────────────────────────────────
#  Floor Generation Status
# ──────────────────────────────────────────────
enum FloorSize {
	FLOOR_SIZE_LARGE,
	FLOOR_SIZE_SMALL,
	FLOOR_SIZE_MEDIUM,
}

enum HiddenStairsType {
	HIDDEN_STAIRS_NONE,
	HIDDEN_STAIRS_SECRET_BAZAAR,
	HIDDEN_STAIRS_SECRET_ROOM,
	HIDDEN_STAIRS_RANDOM_SECRET_BAZAAR_OR_SECRET_ROOM = 255,
}

enum FloorType {
	FLOOR_TYPE_NORMAL,
	FLOOR_TYPE_FIXED,
	FLOOR_TYPE_RESCUE,
}

enum DirectionId {
	DIR_NONE = -1,
	DIR_DOWN = 0,
	DIR_DOWN_RIGHT = 1,
	DIR_RIGHT = 2,
	DIR_UP_RIGHT = 3,
	DIR_UP = 4,
	DIR_UP_LEFT = 5,
	DIR_LEFT = 6,
	DIR_DOWN_LEFT = 7,
	DIR_CURRENT = 8,
}

enum CardinalDirection {
	DIR_RIGHT,
	DIR_UP,
	DIR_LEFT,
	DIR_DOWN,
}

enum SecondaryStructureType {
	SECONDARY_STRUCTURE_NONE,
	SECONDARY_STRUCTURE_MAZE_PLUS_DOT,
	SECONDARY_STRUCTURE_CHECKERBOARD,
	SECONDARY_STRUCTURE_POOL,
	SECONDARY_STRUCTURE_ISLAND,
	SECONDARY_STRUCTURE_DIVIDER,
}

enum GenerationStepLevel {
	GEN_STEP_COMPLETE,
	GEN_STEP_MAJOR,
	GEN_STEP_MINOR,
}

# ──────────────────────────────────────────────
#  Constants
# ──────────────────────────────────────────────
const FLOOR_MAX_X: int = 56
const FLOOR_MAX_Y: int = 32
const DEFAULT_MAX_POSITION: int = 9999

# NA: 0235171C - (X, Y) direction offset pairs, repeated twice per direction
const LIST_DIRECTIONS: Array[int] = [
	# Down
	0, 0, 1, 1,
	# Down-Right
	1, 1, 1, 1,
	# Right
	1, 1, 0, 0,
	# Up-Right
	1, 1, -1, -1,
	# Up
	0, 0, -1, -1,
	# Up-Left
	-1, -1, -1, -1,
	# Left
	-1, -1, 0, 0,
	# Down-Left
	-1, -1, 1, 1,
]

# NA: 02353010 - Used in GenerateRoomImperfections
const CORNER_CARDINAL_NEIGHBOR_EXPECT_OPEN: Array[bool] = [
	# Top-Left Corner
	true, false, true, false, false, false, false, false,
	# Top-Right Corner
	true, false, false, false, false, false, true, false,
	# Bottom-Right Corner
	false, false, false, false, true, false, true, false,
	# Bottom-Left Corner
	false, false, true, false, true, false, false, false,
]

# NA: 020A1AE8 - The type of secondary terrain for each dungeon
const SECONDARY_TERRAIN_TYPES: Array[int] = [
	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
	0,0,0,2,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,2,2,0,0,0,0,0,0,0,0,0,2,2,2,1,1,
	0,0,2,0,0,0,0,0,0,0,0,0,0,0,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
	0,0,0,0,0,2,0,0,0,0,0,0,0,0,0,0,0,1,0,1,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,
	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,0,0,1,2,0,0,0,0,0,2,0,0,0,
	0,1,0,0,0,0,0,
]


# ──────────────────────────────────────────────
#  Data Classes
# ──────────────────────────────────────────────

class RoomFlags:
	var f_secondary_terrain_generation: bool = false
	var f_room_imperfections: bool = false

class TerrainFlags:
	var terrain_type: int = TerrainType.TERRAIN_WALL
	var f_corner_cuttable: bool = false
	var f_natural_junction: bool = false
	var f_impassable_wall: bool = false
	var f_in_kecleon_shop: bool = false
	var f_in_monster_house: bool = false
	var terrain_flags_unk7: bool = false
	var f_unbreakable: bool = false
	var f_stairs: bool = false
	var terrain_flags_unk10: bool = false
	var f_key_door: bool = false
	var f_key_door_key_locked: bool = false
	var f_key_door_escort_locked: bool = false
	var terrain_flags_unk14: bool = false
	var f_unreachable_from_stairs: bool = false

class SpawnFlags:
	var f_stairs: bool = false
	var f_item: bool = false
	var f_trap: bool = false
	var f_monster: bool = false
	var f_special_tile: bool = false
	var spawn_flags_field_0x5: bool = false
	var spawn_flags_field_0x6: bool = false
	var spawn_flags_field_0x7: bool = false

class MissionDestinationInfo:
	var is_destination_floor: bool = false
	var mission_type: int = MissionType.MISSION_RESCUE_CLIENT
	var mission_subtype: int = MissionSubtypeChallenge.MISSION_CHALLENGE_NORMAL

class StairsReachableFlags:
	var f_cannot_corner_cut: bool = false
	var f_secondary_terrain_cannot_corner_cut: bool = false
	var f_unknown_field_0x2: bool = false
	var f_starting_point: bool = false
	var f_in_visit_queue: bool = false
	var f_visited: bool = false

class GridCell:
	var start_x: int = 0
	var start_y: int = 0
	var end_x: int = 0
	var end_y: int = 0
	var is_invalid: bool = false
	var has_secondary_structure: bool = false
	var is_room: bool = false
	var is_cell_connected: bool = false
	var is_kecleon_shop: bool = false
	var unk3: bool = false
	var is_monster_house: bool = false
	var unk4: bool = false
	var is_maze_room: bool = false
	var has_been_merged: bool = false
	var is_merged: bool = false
	var connected_to_top: bool = false
	var connected_to_bottom: bool = false
	var connected_to_left: bool = false
	var connected_to_right: bool = false
	var should_connect_to_top: bool = false
	var should_connect_to_bottom: bool = false
	var should_connect_to_left: bool = false
	var should_connect_to_right: bool = false
	var unk5: bool = false
	var flag_imperfect: bool = false
	var flag_secondary_structure: bool = false

class Tile:
	var terrain_flags: TerrainFlags = TerrainFlags.new()
	var spawn_or_visibility_flags: SpawnFlags = SpawnFlags.new()
	var texture_id: int = 0
	var room_index: int = 0xFF

class FloorProperties:
	var layout: int = FloorLayout.LAYOUT_SMALL
	var room_density: int = 4
	var irregular_room_chance: int = 0
	var floor_connectivity: int = 15
	var enemy_density: int = 0
	var kecleon_shop_chance: int = 0
	var monster_house_chance: int = 0
	var maze_room_chance: int = 0
	var allow_dead_ends: bool = false
	var secondary_structures_budget: int = 0
	var room_flags: RoomFlags = RoomFlags.new()
	var item_density: int = 0
	var trap_density: int = 0
	var floor_number: int = 0
	var fixed_room_id: int = 0
	var num_extra_hallways: int = 0
	var buried_item_density: int = 0
	var secondary_terrain_density: int = 10
	var itemless_monster_house_chance: int = 0
	var hidden_stairs_type: int = HiddenStairsType.HIDDEN_STAIRS_NONE
	var hidden_stairs_spawn_chance: int = 0
	var room_obstacle_density: int = 0
	var generation_seed: int = 0

class FloorGenerationStatus:
	var second_spawn: bool = false
	var has_monster_house: bool = false
	var stairs_room_index: int = 0
	var has_kecleon_shop: bool = false
	var has_chasms_as_secondary_terrain: bool = false
	var is_invalid: bool = false
	var floor_size: int = FloorSize.FLOOR_SIZE_LARGE
	var has_maze: bool = false
	var no_enemy_spawn: bool = false
	var kecleon_shop_chance: int = 100
	var monster_house_chance: int = 0
	var num_rooms: int = 0
	var secondary_structures_budget: int = 0
	var hidden_stairs_spawn_x: int = 0
	var hidden_stairs_spawn_y: int = 0
	var kecleon_shop_middle_x: int = 0
	var kecleon_shop_middle_y: int = 0
	var num_tiles_reachable_from_stairs: int = 0
	var layout: int = FloorLayout.LAYOUT_LARGE
	var hidden_stairs_type: int = HiddenStairsType.HIDDEN_STAIRS_NONE
	var kecleon_shop_min_x: int = 0
	var kecleon_shop_min_y: int = 0
	var kecleon_shop_max_x: int = 0
	var kecleon_shop_max_y: int = 0

class DungeonGenerationInfo:
	var force_create_monster_house: bool = false
	var monster_house_room: int = -1
	var hidden_stairs_type: int = HiddenStairsType.HIDDEN_STAIRS_NONE
	var fixed_room_id: int = 0
	var floor_generation_attempts: int = 0
	var player_spawn_x: int = -1
	var player_spawn_y: int = -1
	var stairs_spawn_x: int = -1
	var stairs_spawn_y: int = -1
	var hidden_stairs_spawn_x: int = -1
	var hidden_stairs_spawn_y: int = -1

class Dungeon:
	var id: int = 1
	var dungeon_floor: int = 1
	var rescue_floor: int = 1
	var nonstory_flag: bool = true
	var mission_destination: MissionDestinationInfo = MissionDestinationInfo.new()
	var dungeon_objective: int = DungeonObjectiveType.OBJECTIVE_NORMAL
	var kecleon_shop_min_x: int = 0
	var kecleon_shop_min_y: int = 0
	var kecleon_shop_max_x: int = 0
	var kecleon_shop_max_y: int = 0
	var num_items: int = 0
	var guaranteed_item_id: int = 0
	var n_floors_plus_one: int = 4
	var list_tiles: Array = []
	var fixed_room_tiles: Array = []
	var active_traps: Array = []

class GenerationConstants:
	var merge_rooms_chance: int = 5
	var no_imperfections_chance: int = 60
	var secondary_structure_flag_chance: int = 80
	var max_number_monster_house_item_spawns: int = 7
	var max_number_monster_house_enemy_spawns: int = 30
	var first_dungeon_id_allow_monster_house_traps: int = 28

class AdvancedGenerationSettings:
	var allow_wall_maze_room_generation: bool = false
	var fix_dead_end_validation_error: bool = false
	var fix_generate_outer_rooms_floor_error: bool = false
