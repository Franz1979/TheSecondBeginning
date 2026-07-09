# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

TheSecondBeginning is a 2D top-down world-simulation game built in **Godot 4.6** (GDScript, Forward+ renderer, Jolt physics, D3D12 on Windows). There is no external build system, package manager, or test framework — the project is opened and run directly in the Godot editor.

## Commands

- **Run the game**: open the project in the Godot 4.6 editor and press F5 (runs `run/main_scene` from `project.godot`), or run headless from the CLI if a Godot binary is available: `godot4 --path .`
- **Run a specific scene**: F6 in the editor, or `godot4 --path . scenes/game/GameScene.tscn`
- There are no lint, test, or build commands configured in this repo (no addons/, no test framework).
- `.gd` scripts each have a paired `.uid` file — these are Godot-managed (resource UIDs); don't hand-edit them, and always keep them alongside their script when moving/renaming files.

## Architecture

### Scene flow
`MainMenu` → `NewGameMenu` / `MapEditorMenu` → `GameScene` / `MapEditorScene`. Navigation is done via `get_tree().change_scene_to_file(...)`; state is *not* passed as scene params but through the `GameSettings` autoload (`scripts/core/GameSettings.gd`), which holds `selected_map_type` (`"random"`, `"island"`, `"saved"`, `"empty"`), `selected_map_file`, and `selected_save_file`, plus the `user://maps/` and `user://saves/` directories. Menu scripts set these fields before switching scenes; `GameScene`/`MapEditorScene` read them in `_ready()`/`_load_world()` to decide what to construct or load.

### World model
- `GameTypes.gd` (`scripts/core/GameTypes.gd`) is the single source of truth for all simulation enums (`TerrainBase`, `WaterType`, `Biome`, `CoastType`, `RiverShape`, `WorldObjectType`, `ResourceType`, `SuccessionLevel`). Add new terrain/resource categories here first.
- `World` (`scripts/world/world.gd`) owns a flat 100x100 grid (`WIDTH`/`HEIGHT` consts) of two parallel arrays indexed by `y * WIDTH + x`:
  - `cells: Array[MacroCellData]` — static terrain/geography (terrain base, water, biome, coast, river shape).
  - `cell_states: Array[MacroCellState]` — dynamic per-cell simulation state (resource quantities, "dedicated space" per resource type, river space). `TOTAL_SPACE` (10000) is the microcell budget each macro cell has to allocate across resources.
  - Always fetch cells via `world.get_cell_at(x, y)` / `get_cell_state_at(x, y)`, never index the arrays directly — these validate coordinates and index consistency.
- World generation is pluggable: `RandomMapGenerator` and `PresetMapGenerator` (island preset) both take a `World` and mutate it in place; `World.generate_empty_world()` dispatches to the right generator based on `GameSettings.selected_map_type`. `WorldProcessors` holds post-processing passes (e.g. coast derivation from adjacency).

### Resource simulation
Resource behavior (stone, trees, more to come per `GameTypes.WorldObjectType`) is data-driven via Godot `Resource` subclasses stored as `.tres` files, not hardcoded:
- `ResourceDensityRules` / `ResourceGrowthRules` (`scripts/core/`) are `@export`-driven Resource classes with base values plus multipliers per terrain/biome/coast.
- Data files live at `res://data/resource_density/{type_name}_density.tres` and `res://data/resource_growth/{type_name}_growth.tres`, where `{type_name}` is the lowercased `GameTypes.WorldObjectType` enum key (e.g. `tree_growth.tres`). `ResourceCalculator` (`scripts/core/ResourceCalculator.gd`) resolves and loads these by convention — adding a new resource type means adding the enum value in `GameTypes` and dropping in matching `.tres` files, no code changes needed in the calculator.
- Per-year simulation is split into services invoked from `GameScene._on_advance_year_pressed()`, in order: `ResourceGrowthService.grow_resources()` (logistic growth of dedicated space/quantity per cell) → `ResourceMigrationService.migrate_resources()` (spills surplus growth into neighboring cells, N/S/E/W, probabilistic). `InitialResourceSetupService` seeds starting resources when a new game/world is created.
- All of these "service" classes (`*Service.gd`, `RefCounted`, no autoload) are stateless — instantiate with `.new()` and call their single entry method per use; this is the established pattern for any new simulation logic.

### Rendering & input
- `WorldRenderer` (`scripts/world/worldRenderer.gd`, `Node2D`) draws the whole grid immediate-mode in `_draw()` — terrain color per cell, river shapes, and a resource-quantity overlay — keyed off `CELL_SIZE = 10` px per macro cell. Call `queue_redraw()` after mutating world/cell state to refresh.
- Cell picking/input is handled by `CellSelectorController` (base: click-to-select, emits `cell_selected(cell, state)`), extended by `MapEditorController` which adds terrain "painting" (brush + drag-paint) and keeps river/coast adjacency consistent as you paint (`_update_river_shape_around`, `_update_coast_type_around`).
- `CameraController` (`scripts/camera/CameraController.gd`) is a plain WASD/arrow-pan + scroll-zoom `Camera2D`, shared by game and editor scenes.

### Persistence
Save/load is hand-rolled JSON (no Godot `ResourceSaver`), with parallel service pairs:
- `WorldSaveService`/`WorldLoadService` — map-only, `file_type: "world_map"`, used by the map editor.
- `GameSaveService`/`GameLoadService` — full save including `GameData` (currently just `year`) and world + cell_states, `file_type: "game_save"`.
Both loaders validate `file_type` before parsing and reject/`push_error` on mismatch. When extending `MacroCellData`/`MacroCellState`/`GameData` with new fields, update both the matching save and load service together, and use `.get(key, default)` on load for new/optional fields to stay compatible with older save files.

### UI scripts
Menu/HUD scripts (`scripts/scenes/*.gd`, `scripts/game/GameScene.gd`, `scripts/world/MacroCellInfoPanel.gd`) follow a consistent pattern: `@onready` node refs matched to the paired `.tscn` structure, `tr()`-wrapped button labels (localization keys, though no translation CSV exists yet), and signal wiring done in `_ready()`.
