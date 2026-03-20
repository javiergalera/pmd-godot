# PMD-Godot

A Pokémon Mystery Dungeon-style turn-based dungeon crawler built in **Godot 4.6** with **GDScript**. Features procedurally generated dungeons using a reverse-engineered algorithm from *Pokémon Mystery Dungeon: Explorers of Sky*.

## Features

### Dungeon Generation
- **Procedural algorithm** based on PMD:EoS with 16 layout types, configurable room density, hallway connectivity, secondary terrain (water), monster houses, Kecleon shops, traps, items, and hidden stairs.
- **Custom room shapes** (circles, ovals, columns) beyond the original algorithm.
- **Autotile system** — 3×3 neighborhood-based tile selection for smooth wall/water/floor transitions.
- **Fully deterministic** — same seed produces the same dungeon every time.

### Movement & Controls
- **8-directional tile movement** — walk, dash (auto-run with Shift), and rotate in place (Ctrl).
- **Dash** stops automatically at walls, enemies, room/hallway transitions, and intersections.
- Each move, dash step, or attack consumes one turn.

### Turn-Based System
- **Signal-driven TurnManager** orchestrates player actions → enemy phase → turn-end events.
- **Enemy AI** — BFS pathfinding within 12-tile chase range, 8-directional movement with diagonal corner validation, random wandering (35% chance), simultaneous movement for all enemies per turn.

### Combat
- **Generic combat resolver** shared by player and enemies with attack/hurt animation sequences.
- **Z-index ordering** — Y-position-based sprite depth sorting with facing-direction tiebreaking and attacker boost during horizontal combat.
- **Sequential hurt animations** — player's hurt animation completes before the next enemy can attack.
- Attack sound plays on every swing, even on air (no target).

### Entity System
- **TileEntity base class** — shared `AnimatedSprite2D` extension with 8-directional animation dictionaries (walk, idle, attack, hurt), tile position tracking, `face_toward()`, and z-index management.
- **Enemy animations** — walk animation plays only during tile-to-tile movement, idle otherwise. Race-condition-free tween callbacks using `_move_id` counter + `call_deferred`.

### Audio
- **AudioManager autoload** — background music with crossfading, SFX pooling (8 concurrent sounds).
- Sound effects for player/enemy attacks, stairs transitions, and floor changes.
- Music stops on menu return.

### Visual Systems
- **Fog of war** — PMD-style circular vision overlay (3.5-tile radius) with room auto-reveal, smooth lerp transitions, and 1-tile enemy peek distance.
- **Minimap** — real-time exploration with color-coded walls, rooms, hallways, water, stairs, and player position. Limited hallway radius (4 tiles).
- **Tile overlay** — wall edge highlighting, water corners, and floor shadows.

### Multi-Floor Dungeons
- Configurable floor count. Step on stairs to advance.
- Smooth fade-in/fade-out transitions between floors with stairs SFX.

### Start Menu
- Configure all dungeon parameters (room density, floors, enemies, items, traps, seed) before entering.

## Controls

| Action | Key |
|--------|-----|
| Move | Arrow keys / WASD |
| Dash (auto-run) | Shift + direction |
| Rotate in place | Ctrl + direction |
| Attack | Space |

## Project Structure

```
pmd-godot/
├── scripts/
│   ├── core/                       # Autoload singletons
│   │   ├── audio_manager.gd        # Music crossfade + SFX pooling
│   │   └── game_settings.gd        # Dungeon parameter storage
│   ├── dungeon/
│   │   ├── dungeon_generator.gd    # TileMapLayer rendering + floor management
│   │   ├── combat_resolver.gd      # Attack/hurt animation + z-index logic
│   │   ├── turn_manager.gd         # Turn phase orchestration
│   │   ├── floor_transition.gd     # Stairs + fade transitions
│   │   ├── minimap.gd              # Minimap with fog of war
│   │   ├── vision_overlay.gd       # Fog-of-war shader overlay
│   │   ├── entities/
│   │   │   ├── tile_entity.gd      # Base class (8-dir animations, z-index)
│   │   │   ├── enemy.gd            # Enemy entity (extends TileEntity)
│   │   │   ├── enemy_manager.gd    # Spawning, BFS pathfinding, AI
│   │   │   └── enemy_tint.gdshader # Enemy visibility shader
│   │   └── generation/
│   │       ├── dungeon_algorithm.gd # PMD:EoS generation algorithm
│   │       ├── dungeon_data.gd      # Enums, constants, data classes
│   │       ├── dungeon_random.gd    # Deterministic 3-value LCG RNG
│   │       └── autotile_data.gd     # 3×3 neighborhood tile lookups
│   ├── player/
│   │   └── player.gd               # Movement, dash, attack (extends TileEntity)
│   └── ui/
│       └── start_menu.gd           # Menu controller + parameter validation
├── scenes/
│   ├── start_menu.tscn             # Main menu scene
│   └── dungeon/
│       ├── dungeon.tscn            # Dungeon gameplay scene
│       └── enemy.tscn              # Enemy prefab
├── sprites/
│   ├── player/                     # 8-directional player spritesheets
│   ├── enemy/                      # 8-directional enemy spritesheets
│   ├── tiles/                      # Floor, wall, water, stairs tiles
│   └── dungeon/                    # Tileset atlas
├── audio/
│   ├── music/                      # Background music
│   └── sfx/                        # Attack + stairs sound effects
├── resources/                      # SpriteFrames (.tres)
└── project.godot
```

## Running

1. Open the project in **Godot 4.6+**
2. Run the main scene (`scenes/start_menu.tscn`)
3. Configure dungeon parameters and click **Start**

## Dungeon Generation Parameters

| Parameter | Range | Description |
|-----------|-------|-------------|
| Total Floors | 1+ | Number of floors in the dungeon |
| Room Density | 0–16 | Rooms per floor |
| Irregular Room Chance | 0–100% | Irregular vs rectangular rooms |
| Floor Connectivity | 0–32 | Hallway frequency |
| Enemy Density | 0–32 | Enemies per floor |
| Item Density | 0–32 | Items per floor |
| Trap Density | 0–32 | Traps per floor |
| Room Obstacle Density | 0–100% | Obstacles inside rooms |
| Seed | Any integer | For reproducible generation |

## Architecture

### Autoloads
- **GameSettings** — persists dungeon configuration between scenes.
- **TurnManager** — signal-driven turn phases (`player_turn_ended` → `enemy_phase_started` → `enemy_phase_finished` → `turn_ended`).
- **AudioManager** — centralized music/SFX with crossfade and pooling.

### Inheritance
```
AnimatedSprite2D
  └── TileEntity (tile_entity.gd)
        ├── Player (player.gd)
        └── Enemy (enemy.gd)
```

Player and Enemy share animation dictionaries, tile positioning, facing logic, and z-index management through the TileEntity base class. Path-based `extends` is used instead of `class_name` references.

## Credits

- **Dungeon Algorithm** — Reverse-engineered from [EpicYoshiMaster/dungeon-mystery](https://github.com/EpicYoshiMaster/dungeon-mystery) (GPL-3.0)
- **Original Game** — *Pokémon Mystery Dungeon: Explorers of Sky* by Chunsoft / Nintendo
- **Engine** — [Godot Engine 4.6](https://godotengine.org/)
