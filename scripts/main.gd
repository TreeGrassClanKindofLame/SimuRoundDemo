extends Node2D

enum AIType { IDLE, RANDOM, CHASE, FLEE }

const TILE_SIZE := 48
const MAP_ORIGIN := Vector2(48, 144)
const MAP_ROWS := [
	"###############",
	"#.............#",
	"#..###........#",
	"#.....#..##...#",
	"#.....#.......#",
	"#..#.....#....#",
	"#..#..###.....#",
	"#.............#",
	"###############",
]
const PLAYER_START := Vector2i(1, 1)
const DIR_NONE := Vector2i(0, 0)
const DIR_UP := Vector2i(0, -1)
const DIR_DOWN := Vector2i(0, 1)
const DIR_LEFT := Vector2i(-1, 0)
const DIR_RIGHT := Vector2i(1, 0)
const ACTIONS := [DIR_NONE, DIR_UP, DIR_DOWN, DIR_LEFT, DIR_RIGHT]

var player_pos := PLAYER_START
var enemies: Array[Dictionary] = []
var turn_count := 0
var last_event := "Ready"
var rng := RandomNumberGenerator.new()
var astar_grid := AStarGrid2D.new()

@onready var status_label: Label = $HUD/Status

func _ready() -> void:
	rng.randomize()
	_setup_astar_grid()
	_reset_demo()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	match key_event.keycode:
		KEY_W:
			_play_turn(DIR_UP)
		KEY_S:
			_play_turn(DIR_DOWN)
		KEY_A:
			_play_turn(DIR_LEFT)
		KEY_D:
			_play_turn(DIR_RIGHT)
		KEY_R:
			_reset_demo()
		_:
			return

	get_viewport().set_input_as_handled()

func _setup_astar_grid() -> void:
	astar_grid.region = Rect2i(Vector2i.ZERO, Vector2i(_map_width(), _map_height()))
	astar_grid.cell_size = Vector2(1, 1)
	astar_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar_grid.update()

	for y in range(_map_height()):
		for x in range(_map_width()):
			var cell := Vector2i(x, y)
			astar_grid.set_point_solid(cell, _is_wall(cell))

func _reset_demo() -> void:
	player_pos = PLAYER_START
	turn_count = 0
	last_event = "Ready"
	enemies = [
		_create_enemy(Vector2i(6, 1), AIType.IDLE),
		_create_enemy(Vector2i(12, 1), AIType.RANDOM),
		_create_enemy(Vector2i(12, 7), AIType.CHASE),
		_create_enemy(Vector2i(2, 7), AIType.FLEE),
		_create_enemy(Vector2i(8, 5), AIType.RANDOM),
	]
	_update_hud()
	queue_redraw()

func _create_enemy(pos: Vector2i, ai_type: int) -> Dictionary:
	return {
		"pos": pos,
		"ai": ai_type,
		"alive": true,
	}

func _play_turn(player_delta: Vector2i) -> void:
	_try_move_player(player_delta)
	_take_enemy_turns()
	turn_count += 1
	_update_hud()
	queue_redraw()

func _try_move_player(delta: Vector2i) -> void:
	var target: Vector2i = player_pos + delta
	if not _is_walkable_cell(target):
		last_event = "Player bumps into a wall"
		return

	var enemy_index := _enemy_at(target)
	if enemy_index != -1:
		_kill_enemy(enemy_index)
		last_event = "Player collides with enemy"
		return

	player_pos = target
	last_event = "Player moves"

func _take_enemy_turns() -> void:
	for index in range(enemies.size()):
		if not enemies[index]["alive"]:
			continue

		var enemy: Dictionary = enemies[index]
		var delta := _decide_enemy_action(enemy)
		_try_move_enemy(index, delta)

func _decide_enemy_action(enemy: Dictionary) -> Vector2i:
	match enemy["ai"]:
		AIType.IDLE:
			return DIR_NONE
		AIType.RANDOM:
			var action_index := rng.randi_range(0, ACTIONS.size() - 1)
			var action: Vector2i = ACTIONS[action_index]
			return action
		AIType.CHASE:
			return _decide_chase_action(enemy["pos"])
		AIType.FLEE:
			return _decide_flee_action(enemy["pos"])
	return DIR_NONE

func _decide_chase_action(enemy_pos: Vector2i) -> Vector2i:
	var path: Array[Vector2i] = astar_grid.get_id_path(enemy_pos, player_pos)
	if path.size() < 2:
		return DIR_NONE

	return path[1] - enemy_pos

func _decide_flee_action(enemy_pos: Vector2i) -> Vector2i:
	var best_delta := DIR_NONE
	var best_distance := _grid_distance(enemy_pos, player_pos)

	for raw_delta in ACTIONS:
		var delta: Vector2i = raw_delta
		var target: Vector2i = enemy_pos + delta
		if delta != DIR_NONE and not _is_walkable_cell(target):
			continue

		var distance := _grid_distance(target, player_pos)
		if distance > best_distance:
			best_distance = distance
			best_delta = delta

	return best_delta

func _try_move_enemy(index: int, delta: Vector2i) -> void:
	if delta == DIR_NONE:
		return

	var enemy: Dictionary = enemies[index]
	var target: Vector2i = enemy["pos"] + delta
	if not _is_walkable_cell(target):
		return

	if target == player_pos:
		_kill_enemy(index)
		last_event = "%s enemy collides with player" % _ai_name(enemy["ai"])
		return

	var other_enemy_index := _enemy_at(target)
	if other_enemy_index != -1:
		return

	enemy["pos"] = target
	enemies[index] = enemy

func _kill_enemy(index: int) -> void:
	var enemy: Dictionary = enemies[index]
	enemy["alive"] = false
	enemies[index] = enemy

func _enemy_at(cell: Vector2i) -> int:
	for index in range(enemies.size()):
		if enemies[index]["alive"] and enemies[index]["pos"] == cell:
			return index
	return -1

func _is_walkable_cell(cell: Vector2i) -> bool:
	return _is_inside_map(cell) and not _is_wall(cell)

func _is_inside_map(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _map_width() and cell.y < _map_height()

func _is_wall(cell: Vector2i) -> bool:
	return MAP_ROWS[cell.y].substr(cell.x, 1) == "#"

func _map_width() -> int:
	return MAP_ROWS[0].length()

func _map_height() -> int:
	return MAP_ROWS.size()

func _grid_distance(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

func _living_enemy_count() -> int:
	var count := 0
	for enemy in enemies:
		if enemy["alive"]:
			count += 1
	return count

func _update_hud() -> void:
	status_label.text = "Turn %d\nEnemies: %d\n%s" % [turn_count, _living_enemy_count(), last_event]

func _draw() -> void:
	_draw_map()
	_draw_units()

func _draw_map() -> void:
	for y in range(_map_height()):
		for x in range(_map_width()):
			var cell := Vector2i(x, y)
			var rect := _cell_rect(cell)
			if _is_wall(cell):
				draw_rect(rect, Color(0.13, 0.14, 0.16))
				draw_rect(rect.grow(-8), Color(0.23, 0.24, 0.28))
			else:
				draw_rect(rect, Color(0.20, 0.22, 0.24))
				draw_rect(rect.grow(-10), Color(0.25, 0.27, 0.29))

			draw_rect(rect, Color(0.07, 0.08, 0.09), false, 2.0)

func _draw_units() -> void:
	_draw_unit(player_pos, Color(0.15, 0.78, 0.42), Color(0.85, 1.0, 0.90))

	for enemy in enemies:
		if enemy["alive"]:
			_draw_unit(enemy["pos"], _enemy_color(enemy["ai"]), Color(1.0, 0.92, 0.72))

func _draw_unit(cell: Vector2i, body_color: Color, eye_color: Color) -> void:
	var rect := _cell_rect(cell).grow(-7)
	draw_rect(rect, Color(0.03, 0.04, 0.05))
	draw_rect(rect.grow(-4), body_color)
	draw_rect(Rect2(rect.position + Vector2(10, 14), Vector2(7, 7)), eye_color)
	draw_rect(Rect2(rect.position + Vector2(25, 14), Vector2(7, 7)), eye_color)
	draw_rect(Rect2(rect.position + Vector2(14, 29), Vector2(17, 5)), Color(0.03, 0.04, 0.05))

func _cell_rect(cell: Vector2i) -> Rect2:
	var pixel_pos := Vector2(cell.x * TILE_SIZE, cell.y * TILE_SIZE)
	return Rect2(MAP_ORIGIN + pixel_pos, Vector2(TILE_SIZE, TILE_SIZE))

func _enemy_color(ai_type: int) -> Color:
	match ai_type:
		AIType.IDLE:
			return Color(0.20, 0.42, 0.92)
		AIType.RANDOM:
			return Color(0.94, 0.70, 0.20)
		AIType.CHASE:
			return Color(0.88, 0.18, 0.18)
		AIType.FLEE:
			return Color(0.55, 0.28, 0.86)
	return Color.WHITE

func _ai_name(ai_type: int) -> String:
	match ai_type:
		AIType.IDLE:
			return "Idle"
		AIType.RANDOM:
			return "Random"
		AIType.CHASE:
			return "Chase"
		AIType.FLEE:
			return "Flee"
	return "Unknown"
