# Simu Round Demo

Godot 4 simultaneous-turn grid game demo.

## Current Demo

- Fixed grid map with walls and floors
- WASD player movement
- Press 1/2 to switch between the normal map and the boss arena
- Units face their latest attempted movement direction
- Player and enemy units use temporary four-direction humanoid pixel sprites
- One player action advances one enemy phase
- Sequential enemy turns
- Player has 5 HP shown as pixel heart icons
- Enemies have fixed HP by AI type: idle 1, random 1, flee 2, chase 3
- Unit collision rule: both units take 1 damage, and movement is canceled
- If a unit is hit from behind during a collision, that unit takes 1 extra damage
- The same two units can only deal collision damage to each other once per turn
- Wall collision rule: no damage, but the unit bumps back
- Enemy AI types: idle, random, chase, flee
- Chase AI uses `AStarGrid2D` pathfinding
- Boss arena has an open map and a 2x2 boss with 5 HP
- Boss moves 1 tile toward the player, charges a locked front 2x2 warning area, attacks on its next action, then spends 1 action stunned
- Temporary code-generated sound effects
- Temporary pixel-style shapes drawn in code

## Run

Open the folder in Godot and run the project. The default scene is `res://scenes/main.tscn`.
