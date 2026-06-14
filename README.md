# Simu Round Demo

Godot 4 simultaneous-turn grid game demo.

## Current Demo

- Fixed grid map with walls and floors
- WASD player movement
- Press E, then W/A/S/D, to interact with an adjacent cell in the selected direction
- Entering interaction selection does not advance time; confirming a direction performs the action and advances one turn
- Press E again or Escape to cancel direction selection without advancing time
- Horizontal and vertical doors can be opened or closed; closed doors block movement and vision, while open doors behave like floor
- Interaction changes a door before enemies choose their action for that turn, and every interaction attempt advances time
- Press V to toggle enemy detection ranges
- Units face their latest attempted movement direction
- Player and enemy units use temporary four-direction humanoid pixel sprites
- One player action advances one simultaneous turn
- Player and active enemies resolve movement from the same turn-start snapshot
- Player has 5 HP shown as pixel heart icons
- Normal-map enemies are idle blockers with 2 HP
- Player-enemy collision checks which side of the enemy was hit: front hits damage both units, side hits damage only the enemy, and back hits deal 2 damage to the enemy
- Monster-to-monster collision causes no damage
- The same two units can only deal collision damage to each other once per turn
- Wall collision rule: no damage, but the unit bumps back
- When multiple units enter the same empty cell, the player wins priority; otherwise one monster is picked randomly and the rest bump
- Player-monster contests for the same empty cell resolve one front collision per monster, while monster-monster contests deal no damage
- Units can move into cells vacated during the same turn, but attempted swaps and non-vacated occupied cells are blocked
- Enemies start in IDLE state and switch to COMBAT when the player enters their wall-blocked detection cone; each enemy shows its state above its head without changing body appearance
- COMBAT enemies use `AStarGrid2D` to chase the player while avoiding walls and other living enemies
- COMBAT enemies damage the player when colliding into the player's front, side, or back
- Temporary code-generated sound effects
- Temporary pixel-style shapes drawn in code

## Run

Open the folder in Godot and run the project. The default scene is `res://scenes/main.tscn`.

## Tests

Run the turn-resolution regression tests with Godot headless:

```powershell
& "D:\claude code\Godot_v4.6.3-stable_win64.exe" --headless --path "D:\claude code\SimuRoundDemo" --script "res://tests/turn_resolution_tests.gd"
```

The suite includes deterministic collision scenarios and randomized invariant checks for simultaneous movement resolution.
