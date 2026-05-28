# Simu Round Demo

Godot 4 simultaneous-turn grid game demo.

## Current Demo

- Fixed grid map with walls and floors
- WASD player movement
- One player action advances one enemy phase
- Sequential enemy turns
- Collision rule: if either unit is the player, the other unit dies
- Enemy AI types: idle, random, chase, flee
- Chase AI uses `AStarGrid2D` pathfinding
- Temporary pixel-style shapes drawn in code

## Run

Open the folder in Godot and run the project. The default scene is `res://scenes/main.tscn`.
