# Simu Round Demo

Godot 4 simultaneous-turn grid game demo.

## Current Demo

- Fixed grid map with walls and floors
- WASD player movement
- Units face their latest attempted movement direction
- Player and enemy units use temporary four-direction humanoid pixel sprites
- One player action advances one enemy phase
- Sequential enemy turns
- Player has 5 HP
- Enemies have fixed HP by AI type: idle 1, random 1, flee 2, chase 3
- Unit collision rule: both units take 1 damage, and movement is canceled
- The same two units can only deal collision damage to each other once per turn
- Wall collision rule: no damage, but the unit bumps back
- Enemy AI types: idle, random, chase, flee
- Chase AI uses `AStarGrid2D` pathfinding
- Temporary code-generated sound effects
- Temporary pixel-style shapes drawn in code

## Run

Open the folder in Godot and run the project. The default scene is `res://scenes/main.tscn`.
