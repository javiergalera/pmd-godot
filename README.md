# PMD-Godot

A Pokémon Mystery Dungeon-style turn-based dungeon crawler built in **Godot 4.6** with **GDScript**. Features procedurally generated dungeons using a reverse-engineered algorithm from *Pokémon Mystery Dungeon: Explorers of Sky*, playable in both **2D** and **3D** modes.

## Features

### Dungeon Generation
- **Procedural algorithm** based on PMD:EoS with 16 layout types, configurable room density, hallway connectivity, secondary terrain (water), monster houses, Kecleon shops, traps, items, and hidden stairs.
- **Custom room shapes** (circles, ovals, columns) beyond the original algorithm.
- **Autotile system** — 3×3 neighborhood-based tile selection for smooth wall/water/floor transitions.
- **Fully deterministic** — same seed produces the same dungeon every time.

### Dual Rendering Modes
- **2D mode** — classic top-down with `TileMapLayer`, `AnimatedSprite2D` entities, and canvas shaders.
- **3D mode** — procedural floor/wall meshes, FBX/OBJ models (Squirtle as player, Charmander as enemies), spatial audio, and Forward+ rendering.
- Toggle between modes from the start menu — both share the same dungeon generation algorithm.

### Movement & Controls
- **8-directional tile movement** — walk, dash (auto-run with Shift), and rotate in place (Ctrl).
- **Dash** stops automatically at walls, enemies, room/hallway transitions, and intersections.
- Each move, dash step, or attack consumes one turn.

### Turn-Based System
- **Signal-driven TurnManager** orchestrates player actions → enemy phase → turn-end events.
- **Shared EnemyAI** — BFS pathfinding within 12-tile chase range, 8-directional movement with diagonal corner validation, random wandering (35% chance), simultaneous movement for all enemies per turn.
- **Dictionary position cache** for O(1) enemy tile lookups.

### Combat
- **Generic CombatResolver** shared by player and enemies with attack/hurt animation sequences.
- **Z-index ordering** (2D) — Y-position-based sprite depth sorting with facing-direction tiebreaking and attacker boost during horizontal combat.
- **PMD-style defeat blink** (3D) — enemies flash before disappearing.
- Attack sound plays on every swing, even on air (no target).

### Entity System
- **TileEntity base class** — shared extension with 8-directional animation dictionaries (walk, idle, attack, hurt), tile position tracking, `face_toward()`, and z-index management.
- **Enemy animations** — walk animation plays only during tile-to-tile movement, idle otherwise. Race-condition-free tween callbacks using `_move_id` counter.

### Audio
- **AudioManager autoload** — background music with crossfading, SFX pooling (8 concurrent sounds), safe resource loading with existence validation.
- Separate audio assets for 2D (MP3) and 3D (WAV spatial) modes.
- Sound effects for player/enemy attacks and stairs transitions.

### Visual Systems
- **Fog of war** — PMD-style circular vision overlay (3.5-tile radius) with room auto-reveal, smooth lerp transitions, and 1-tile enemy peek distance. Implemented via canvas shader (2D) or spatial shader (3D).
- **Universal minimap** — real-time exploration with color-coded walls, rooms, hallways, water, stairs, and player position. Auto-detects 2D/3D context.
- **Floor transitions** — smooth fade-in/fade-out between floors with stairs SFX, universal script for both modes.

### Start Menu
- Configure all dungeon parameters before entering: room density, irregular rooms, floor connectivity, enemy/item/trap/obstacle density, floor count, and seed.
- **2D / 3D mode toggle** via checkbox.

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
│   ├── core/                        # Shared systems & autoloads
│   │   ├── game_settings.gd         # Dungeon parameter storage (autoload)
│   │   ├── turn_manager.gd          # Turn phase orchestration (autoload)
│   │   ├── audio_manager.gd         # Music crossfade + SFX pooling (autoload)
│   │   ├── combat_resolver.gd       # Attack/hurt animation + z-index logic
│   │   ├── enemy_ai.gd              # BFS pathfinding + AI (shared by 2D/3D)
│   │   ├── floor_transition.gd      # Stairs + fade transitions (universal)
│   │   └── minimap.gd               # Minimap with fog of war (universal)
│   ├── dungeon/                     # 2D mode
│   │   ├── dungeon_generator.gd     # TileMapLayer rendering + floor management
│   │   ├── vision_overlay.gd        # Fog-of-war shader overlay
│   │   ├── entities/
│   │   │   ├── tile_entity.gd       # Base class (8-dir animations, z-index)
│   │   │   ├── player.gd            # Player movement, dash, attack
│   │   │   ├── enemy.gd             # Enemy entity
│   │   │   ├── enemy_manager.gd     # Enemy spawning + turn coordination
│   │   │   └── enemy_tint.gdshader  # Enemy visibility shader
│   │   └── generation/
│   │       ├── dungeon_algorithm.gd  # PMD:EoS generation algorithm (GPL-3.0)
│   │       ├── dungeon_data.gd       # Enums, constants, data classes
│   │       ├── dungeon_random.gd     # Deterministic 3-value LCG RNG
│   │       └── autotile_data.gd      # 3×3 neighborhood tile lookups
│   ├── dungeon_3d/                  # 3D mode
│   │   ├── dungeon_generator_3d.gd  # Procedural mesh generation
│   │   ├── player_3d.gd             # 3D player with FBX animations
│   │   ├── vision_overlay_3d.gd     # Spatial fog-of-war shader
│   │   └── entities/
│   │       ├── tile_entity_3d.gd    # 3D base entity (AABB auto-scaling)
│   │       ├── enemy_3d.gd          # 3D enemy with defeat blink
│   │       └── enemy_manager_3d.gd  # 3D enemy spawning + turns
│   └── ui/
│       └── start_menu.gd            # Menu controller + parameter config
├── scenes/
│   ├── start_menu.tscn              # Main menu scene
│   ├── dungeon_2d/
│   │   ├── dungeon_2d.tscn          # 2D gameplay scene
│   │   └── enemy_2d.tscn            # 2D enemy prefab
│   └── dungeon_3d/
│       ├── dungeon_3d.tscn          # 3D gameplay scene
│       └── enemy_3d.tscn            # 3D enemy prefab
├── sprites/                         # 2D spritesheets & tiles
├── resources/                       # SpriteFrames + 3D models (Squirtle, Charmander, Stairs)
└── audio/
    ├── music/                       # Background music (2D & 3D variants)
    └── sfx/                         # Attack + stairs SFX (2D & 3D variants)
```

## Dungeon Algorithm

The dungeon generation is a GDScript port of the reverse-engineered PMD:EoS algorithm by [EpicYoshiMaster](https://github.com/EpicYoshiMaster/dungeon-mystery), licensed under **GPL-3.0**. It faithfully replicates the original game's floor layout logic including room placement, hallway routing, secondary terrain, and special room types.

## Disclaimer

This is a **non-commercial fan project** made solely for **educational and learning purposes**. All music, sprites, 3D models, and other audiovisual assets used in this project are the property of **Nintendo, The Pokémon Company, Spike Chunsoft**, and their respective copyright holders.

- **2D assets** (sprites, music, sound effects) originate from *Pokémon Mystery Dungeon: Red/Blue Rescue Team* (2005) and *Pokémon Mystery Dungeon: Explorers of Sky* (2009).
- **3D assets** (models, textures, music, sound effects) originate from *Pokémon Mystery Dungeon: Rescue Team DX* (2020).

The author of this project does **not** claim ownership or authorship of any of these assets. No profit is being made from this project. If any rights holder wishes for this content to be removed, please open an issue and it will be taken down promptly.

## License

- **Dungeon generation algorithm**: GPL-3.0 (ported from [EpicYoshiMaster/dungeon-mystery](https://github.com/EpicYoshiMaster/dungeon-mystery))

## Credits

- **Dungeon Algorithm** — Reverse-engineered from [EpicYoshiMaster/dungeon-mystery](https://github.com/EpicYoshiMaster/dungeon-mystery) (GPL-3.0)
- **Original Games** — *Pokémon Mystery Dungeon: Red/Blue Rescue Team*, *Explorers of Sky* & *Rescue Team DX* by Spike Chunsoft / Nintendo / The Pokémon Company
- **Engine** — [Godot Engine 4.6](https://godotengine.org/)
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
