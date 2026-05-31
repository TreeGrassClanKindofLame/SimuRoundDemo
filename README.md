# Simu Round Demo

Godot 4 simultaneous-turn grid game demo.

## Current Demo

- Fixed grid map with walls and floors
- WASD player movement
- Press V to toggle enemy detection ranges
- Units face their latest attempted movement direction
- Player and enemy units use temporary four-direction humanoid pixel sprites
- One player action advances one enemy phase
- Sequential enemy turns
- Player has 5 HP shown as pixel heart icons
- Normal-map enemies are idle blockers with 2 HP
- Player-enemy collision checks which side of the enemy was hit: front hits damage both units, side hits damage only the enemy, and back hits deal 2 damage to the enemy
- Monster-to-monster collision causes no damage
- The same two units can only deal collision damage to each other once per turn
- Wall collision rule: no damage, but the unit bumps back
- Enemies start in IDLE state, show their current state, and switch to COMBAT when the player enters their wall-blocked detection cone
- Newly alerted enemies wait until their next turn before chasing
- COMBAT enemies use `AStarGrid2D` to chase the player while avoiding walls and other living enemies
- COMBAT enemies bump into the player without dealing damage
- Temporary code-generated sound effects
- Temporary pixel-style shapes drawn in code

## Run

Open the folder in Godot and run the project. The default scene is `res://scenes/main.tscn`.
