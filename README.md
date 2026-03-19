# PMD-Godot

A Pokémon Mystery Dungeon-style turn-based dungeon crawler built in **Godot 4.6** with **GDScript**. Features procedurally generated dungeons using a reverse-engineered algorithm from *Pokémon Mystery Dungeon: Explorers of Sky*.

## Features

- **Procedural Dungeon Generation** — Based on the original PMD:EoS algorithm with 16 layout types, configurable room density, hallway connectivity, secondary terrain (water), monster houses, Kecleon shops, traps, items, and hidden stairs. Extended with custom room shapes (circles, ovals, columns) beyond the original algorithm. Fully deterministic: same seed = same dungeon.
- **8-Directional Tile Movement** — Walk, dash (auto-run with Shift), and rotate in place (Ctrl). Dash stops automatically at walls, enemies, room/hallway transitions, and intersections.
- **Turn-Based System** — Signal-driven TurnManager autoload orchestrates player actions, enemy phases, and turn-end events. Each move, dash step, or attack consumes one turn.
- **Enemy AI** — BFS pathfinding within 12-tile chase range, random wandering, simultaneous movement for all enemies per turn.
- **Combat** — Attack the tile you're facing with Space. Enemies are defeated and removed from the map.
- **Multi-Floor Dungeons** — Configurable floor count. Step on stairs to advance. Smooth fade transitions between floors.
- **Minimap** — Real-time fog of war with room auto-reveal on entry and limited hallway vision.
- **Tile Overlay** — Wall edge highlighting, water corners, and floor shadows for visual polish.
- **Start Menu** — Configure all dungeon parameters (room density, floors, enemies, items, traps, seed) before entering.

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
│   ├── player/         # Movement, dash, combat
│   ├── enemy/          # Enemy AI, spawning, turn coordination
│   ├── dungeon/        # Generation algorithm, tile rendering, overlays
│   ├── turn/           # TurnManager autoload singleton
│   ├── config/         # GameSettings autoload
│   └── ui/             # Start menu, minimap
├── scenes/             # .tscn scene files
├── addons/             # Plugins (empty)
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

## Credits

- **Dungeon Algorithm** — Reverse-engineered from [EpicYoshiMaster/dungeon-mystery](https://github.com/EpicYoshiMaster/dungeon-mystery) (GPL-3.0)
- **Original Game** — *Pokémon Mystery Dungeon: Explorers of Sky* by Chunsoft / Nintendo
- **Engine** — [Godot Engine 4.6](https://godotengine.org/)
