extends SceneTree

const AI_IDLE := 0
const STATE_IDLE := 0
const STATE_COMBAT := 1
const DIR_NONE := Vector2i(0, 0)
const DIR_UP := Vector2i(0, -1)
const DIR_DOWN := Vector2i(0, 1)
const DIR_LEFT := Vector2i(-1, 0)
const DIR_RIGHT := Vector2i(1, 0)
const FOG_DENSE := 0
const FOG_THIN := 1
const FOG_CLEAR := 2
const DOOR_HORIZONTAL := 0
const DOOR_VERTICAL := 1

var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_main_keyboard_one_waits_one_turn()
	_test_keypad_one_does_not_wait()
	_test_e_enters_interaction_selection_without_advancing_turn()
	_test_direction_confirms_interaction_and_hides_prompt()
	_test_interaction_selection_can_be_cancelled()
	_test_interaction_without_target_still_runs_enemy_turn()
	_test_door_interaction_toggles_open_and_closed()
	_test_occupied_open_door_cannot_close()
	_test_map_creates_horizontal_and_vertical_doors()
	_test_closed_door_blocks_movement_and_open_door_allows_it()
	_test_opening_door_changes_enemy_path_on_same_turn()
	_test_closing_door_blocks_enemy_path_on_same_turn()
	_test_closed_door_blocks_player_and_enemy_vision()
	_test_player_wins_empty_cell_contest()
	_test_enemy_enters_player_vacated_cell()
	_test_direct_swap_blocks_and_collides()
	_test_multiple_enemies_damage_stationary_player()
	_test_enemy_side_hit_damages_player()
	_test_monster_only_contest_picks_one_winner()
	_test_multiple_enemies_contest_player_vacated_cell()
	_test_player_back_hit_kills_enemy()
	_test_newly_alerted_enemy_chases_on_next_action()
	_test_initial_fog_reveals_line_of_sight_limited_vision()
	_test_fog_blocks_cells_behind_line_of_sight_wall()
	_test_fog_blocks_diagonal_corner_line_of_sight()
	_test_fog_allows_open_diagonal_corner_line_of_sight()
	_test_fog_blocks_closed_diagonal_corner_line_of_sight()
	_test_fog_reveals_walls_next_to_visible_floors()
	_test_fog_clear_cells_become_thin_after_player_moves()
	_test_fog_hides_enemies_outside_clear_cells()
	_test_fog_hides_closed_corner_blocked_enemies()
	_test_random_resolution_invariants()

	if failures.size() > 0:
		for failure in failures:
			push_error(failure)
		print("turn_resolution_tests: %d failed" % failures.size())
		quit(1)
		return

	print("turn_resolution_tests: all passed")
	quit(0)

func _new_main() -> Node:
	var scene := load("res://scenes/main.tscn")
	var main: Node = scene.instantiate()
	root.add_child(main)
	for sound_player in main.sound_players.values():
		sound_player.stop()
		sound_player.stream = null
		main.remove_child(sound_player)
		sound_player.free()
	main.sound_players.clear()
	return main

func _free_main(main: Node) -> void:
	root.remove_child(main)
	main.free()

func _make_enemy(main: Node, enemy_id: String, pos: Vector2i, facing: Vector2i, state := STATE_COMBAT) -> Dictionary:
	var enemy: Dictionary = main._create_enemy(pos, AI_IDLE)
	enemy["id"] = enemy_id
	enemy["pos"] = pos
	enemy["facing"] = facing
	enemy["state"] = state
	enemy["hp"] = 2
	enemy["max_hp"] = 2
	enemy["alive"] = true
	enemy["bump_timer"] = 0.0
	enemy["bump_dir"] = DIR_NONE
	enemy["hit_timer"] = 0.0
	enemy["death_timer"] = 0.0
	return enemy

func _set_units(main: Node, player_pos: Vector2i, player_facing: Vector2i, enemies: Array) -> void:
	main.player_pos = player_pos
	main.player_facing = player_facing
	main.player_hp = 5
	main.player_alive = true
	main.player_bump_timer = 0.0
	main.player_bump_dir = DIR_NONE
	main.player_hit_timer = 0.0
	main.player_death_timer = 0.0
	main.reset_timer = 0.0
	main.turn_collision_pairs.clear()
	var typed_enemies: Array[Dictionary] = []
	for enemy in enemies:
		typed_enemies.append(enemy)
	main.enemies = typed_enemies
	main._reset_fog()
	main._update_player_fog()

func _resolve(main: Node, player_delta: Vector2i, enemy_deltas: Array[Vector2i]) -> void:
	var snapshot: Dictionary = main._create_turn_snapshot()
	var intents: Array[Dictionary] = []
	intents.append(main._make_turn_intent("player", -1, main.player_pos, player_delta))
	for index in range(enemy_deltas.size()):
		var enemy: Dictionary = main.enemies[index]
		intents.append(main._make_turn_intent(str(enemy["id"]), index, enemy["pos"], enemy_deltas[index]))
	main._apply_intent_facings(intents)
	main._resolve_turn_intents(intents, snapshot)

func _test_main_keyboard_one_waits_one_turn() -> void:
	var main := _new_main()
	_set_units(main, Vector2i(2, 1), DIR_RIGHT, [])
	var start_pos: Vector2i = main.player_pos
	var start_facing: Vector2i = main.player_facing

	var handled: bool = main._try_play_key_action(KEY_1)

	_expect_true("main keyboard 1 wait: key handled", handled)
	_expect_eq("main keyboard 1 wait: player stays", main.player_pos, start_pos)
	_expect_eq("main keyboard 1 wait: facing unchanged", main.player_facing, start_facing)
	_expect_eq("main keyboard 1 wait: turn advances", main.turn_count, 1)
	_expect_eq("main keyboard 1 wait: event", main.last_event, "Player waits")
	_free_main(main)

func _test_keypad_one_does_not_wait() -> void:
	var main := _new_main()
	_set_units(main, Vector2i(2, 1), DIR_RIGHT, [])

	var handled: bool = main._try_play_key_action(KEY_KP_1)

	_expect_true("keypad 1 ignored: key not handled", not handled)
	_expect_eq("keypad 1 ignored: turn unchanged", main.turn_count, 0)
	_free_main(main)

func _test_e_enters_interaction_selection_without_advancing_turn() -> void:
	var main := _new_main()
	_set_units(main, Vector2i(4, 1), DIR_DOWN, [])
	var start_pos: Vector2i = main.player_pos
	var start_facing: Vector2i = main.player_facing

	var handled: bool = main._try_play_key_action(KEY_E)

	_expect_true("E selection: key handled", handled)
	_expect_true("E selection: choosing direction", main.choosing_interaction_direction)
	_expect_true("E selection: red prompt visible", main.interaction_prompt.visible)
	_expect_eq("E selection: player stays", main.player_pos, start_pos)
	_expect_eq("E selection: facing unchanged", main.player_facing, start_facing)
	_expect_eq("E selection: turn unchanged", main.turn_count, 0)
	_expect_true("E selection: door unchanged", main._is_closed_door(Vector2i(4, 2)))
	_free_main(main)

func _test_direction_confirms_interaction_and_hides_prompt() -> void:
	var main := _new_main()
	_set_units(main, Vector2i(4, 1), DIR_RIGHT, [])
	var start_pos: Vector2i = main.player_pos
	var start_facing: Vector2i = main.player_facing

	main._try_play_key_action(KEY_E)
	var handled: bool = main._try_play_key_action(KEY_S)

	_expect_true("direction confirmation: key handled", handled)
	_expect_true("direction confirmation: selection ends", not main.choosing_interaction_direction)
	_expect_true("direction confirmation: prompt hidden", not main.interaction_prompt.visible)
	_expect_eq("direction confirmation: player stays", main.player_pos, start_pos)
	_expect_eq("direction confirmation: facing unchanged", main.player_facing, start_facing)
	_expect_eq("direction confirmation: turn advances", main.turn_count, 1)
	_expect_true("direction confirmation: door opens", not main._is_closed_door(Vector2i(4, 2)))
	_free_main(main)

func _test_interaction_selection_can_be_cancelled() -> void:
	var main := _new_main()

	main._try_play_key_action(KEY_E)
	var handled: bool = main._try_play_key_action(KEY_ESCAPE)

	_expect_true("interaction cancel: key handled", handled)
	_expect_true("interaction cancel: selection ends", not main.choosing_interaction_direction)
	_expect_true("interaction cancel: prompt hidden", not main.interaction_prompt.visible)
	_expect_eq("interaction cancel: turn unchanged", main.turn_count, 0)
	_free_main(main)

func _test_interaction_without_target_still_runs_enemy_turn() -> void:
	var main := _new_main()
	_set_units(main, Vector2i(1, 1), DIR_DOWN, [
		_make_enemy(main, "enemy_a", Vector2i(3, 1), DIR_LEFT),
	])
	var enemy_start: Vector2i = main.enemies[0]["pos"]

	main._try_play_key_action(KEY_E)
	var handled: bool = main._try_play_key_action(KEY_S)

	_expect_true("empty interaction: key handled", handled)
	_expect_eq("empty interaction: turn advances", main.turn_count, 1)
	_expect_eq("empty interaction: player stays", main.player_pos, Vector2i(1, 1))
	_expect_true("empty interaction: enemy acts", main.enemies[0]["pos"] != enemy_start)
	_expect_eq("empty interaction: event", main.last_event, "Nothing to interact with")
	_free_main(main)

func _test_door_interaction_toggles_open_and_closed() -> void:
	var main := _new_main()
	_set_units(main, Vector2i(4, 1), DIR_DOWN, [])
	var door_cell := Vector2i(4, 2)

	main._play_interaction_turn(DIR_DOWN)
	_expect_true("door toggle: opens", not main._is_closed_door(door_cell))
	_expect_eq("door toggle: open event", main.last_event, "Door opens")

	main._play_interaction_turn(DIR_DOWN)
	_expect_true("door toggle: closes", main._is_closed_door(door_cell))
	_expect_eq("door toggle: close event", main.last_event, "Door closes")
	_expect_eq("door toggle: two turns", main.turn_count, 2)
	_free_main(main)

func _test_occupied_open_door_cannot_close() -> void:
	var main := _new_main()
	var door_cell := Vector2i(4, 2)
	main._set_door_open(door_cell, true)
	_set_units(main, Vector2i(4, 1), DIR_DOWN, [
		_make_enemy(main, "door_enemy", door_cell, DIR_DOWN, STATE_IDLE),
	])

	main._play_interaction_turn(DIR_DOWN)

	_expect_true("occupied door: remains open", not main._is_closed_door(door_cell))
	_expect_eq("occupied door: enemy remains", main.enemies[0]["pos"], door_cell)
	_expect_eq("occupied door: turn advances", main.turn_count, 1)
	_expect_eq("occupied door: event", main.last_event, "Door cannot close while occupied")
	_free_main(main)

func _test_map_creates_horizontal_and_vertical_doors() -> void:
	var main := _new_main()
	var horizontal_cell := Vector2i(4, 2)
	var vertical_cell := Vector2i(9, 4)

	_expect_true("door map: horizontal exists", main._is_door(horizontal_cell))
	_expect_true("door map: vertical exists", main._is_door(vertical_cell))
	_expect_eq("door map: horizontal orientation", main.doors[main._cell_key(horizontal_cell)]["orientation"], DOOR_HORIZONTAL)
	_expect_eq("door map: vertical orientation", main.doors[main._cell_key(vertical_cell)]["orientation"], DOOR_VERTICAL)
	_expect_true("door map: horizontal starts closed", main._is_closed_door(horizontal_cell))
	_expect_true("door map: vertical starts closed", main._is_closed_door(vertical_cell))
	_free_main(main)

func _test_closed_door_blocks_movement_and_open_door_allows_it() -> void:
	var main := _new_main()
	var door_cell := Vector2i(4, 2)

	_expect_true("door movement: closed door blocked", not main._is_walkable_cell(door_cell))
	main._set_door_open(door_cell, true)
	_expect_true("door movement: open door walkable", main._is_walkable_cell(door_cell))
	_free_main(main)

func _test_opening_door_changes_enemy_path_on_same_turn() -> void:
	var main := _new_main()
	var door_cell := Vector2i(4, 2)
	_set_units(main, Vector2i(4, 1), DIR_DOWN, [
		_make_enemy(main, "enemy_a", Vector2i(4, 3), DIR_UP),
	])

	main._play_interaction_turn(DIR_DOWN)

	_expect_true("open timing: door opens", not main._is_closed_door(door_cell))
	_expect_eq("open timing: enemy enters door this turn", main.enemies[0]["pos"], door_cell)
	_free_main(main)

func _test_closing_door_blocks_enemy_path_on_same_turn() -> void:
	var main := _new_main()
	var door_cell := Vector2i(4, 2)
	main._set_door_open(door_cell, true)
	_set_units(main, Vector2i(4, 1), DIR_DOWN, [
		_make_enemy(main, "enemy_a", Vector2i(4, 3), DIR_UP),
	])

	main._play_interaction_turn(DIR_DOWN)

	_expect_true("close timing: door closes", main._is_closed_door(door_cell))
	_expect_true("close timing: enemy cannot enter door", main.enemies[0]["pos"] != door_cell)
	_free_main(main)

func _test_closed_door_blocks_player_and_enemy_vision() -> void:
	var main := _new_main()
	var door_cell := Vector2i(4, 2)
	_set_units(main, Vector2i(4, 1), DIR_DOWN, [
		_make_enemy(main, "enemy_a", Vector2i(4, 3), DIR_UP, STATE_IDLE),
	])

	_expect_true("door vision: closed door visible", main._is_cell_clear(door_cell))
	_expect_true("door vision: player blocked behind closed door", not main._has_player_line_of_sight(main.player_pos, Vector2i(4, 3)))
	_expect_true("door vision: enemy detection blocked", not main._enemy_can_detect_player(main.enemies[0]))

	main._set_door_open(door_cell, true)
	main._update_player_fog()
	_expect_true("door vision: player sees through open door", main._has_player_line_of_sight(main.player_pos, Vector2i(4, 3)))
	_expect_true("door vision: cell behind open door revealed", main._is_cell_clear(Vector2i(4, 3)))
	_expect_true("door vision: enemy detects through open door", main._enemy_can_detect_player(main.enemies[0]))
	_free_main(main)

func _test_player_wins_empty_cell_contest() -> void:
	var main := _new_main()
	_set_units(main, Vector2i(1, 1), DIR_RIGHT, [
		_make_enemy(main, "enemy_a", Vector2i(3, 1), DIR_LEFT),
		_make_enemy(main, "enemy_b", Vector2i(2, 2), DIR_UP),
	])

	_resolve(main, DIR_RIGHT, [DIR_LEFT, DIR_UP])

	_expect_eq("player wins empty contest: player pos", main.player_pos, Vector2i(2, 1))
	_expect_eq("player wins empty contest: player hp", main.player_hp, 3)
	_expect_eq("player wins empty contest: enemy_a pos", main.enemies[0]["pos"], Vector2i(3, 1))
	_expect_eq("player wins empty contest: enemy_b pos", main.enemies[1]["pos"], Vector2i(2, 2))
	_expect_eq("player wins empty contest: enemy_a hp", main.enemies[0]["hp"], 1)
	_expect_eq("player wins empty contest: enemy_b hp", main.enemies[1]["hp"], 1)
	_expect_true("player wins empty contest: enemy_a bumps", float(main.enemies[0]["bump_timer"]) > 0.0)
	_expect_true("player wins empty contest: enemy_b bumps", float(main.enemies[1]["bump_timer"]) > 0.0)
	_free_main(main)

func _test_enemy_enters_player_vacated_cell() -> void:
	var main := _new_main()
	_set_units(main, Vector2i(2, 1), DIR_RIGHT, [
		_make_enemy(main, "enemy_a", Vector2i(1, 1), DIR_RIGHT),
	])

	_resolve(main, DIR_RIGHT, [DIR_RIGHT])

	_expect_eq("vacated cell: player pos", main.player_pos, Vector2i(3, 1))
	_expect_eq("vacated cell: enemy pos", main.enemies[0]["pos"], Vector2i(2, 1))
	_expect_eq("vacated cell: player hp", main.player_hp, 5)
	_expect_eq("vacated cell: enemy hp", main.enemies[0]["hp"], 2)
	_free_main(main)

func _test_direct_swap_blocks_and_collides() -> void:
	var main := _new_main()
	_set_units(main, Vector2i(2, 1), DIR_LEFT, [
		_make_enemy(main, "enemy_a", Vector2i(1, 1), DIR_RIGHT),
	])

	_resolve(main, DIR_LEFT, [DIR_RIGHT])

	_expect_eq("swap blocks: player pos", main.player_pos, Vector2i(2, 1))
	_expect_eq("swap blocks: enemy pos", main.enemies[0]["pos"], Vector2i(1, 1))
	_expect_eq("swap blocks: player hp", main.player_hp, 4)
	_expect_eq("swap blocks: enemy hp", main.enemies[0]["hp"], 1)
	_free_main(main)

func _test_multiple_enemies_damage_stationary_player() -> void:
	var main := _new_main()
	_set_units(main, Vector2i(2, 2), DIR_UP, [
		_make_enemy(main, "enemy_left", Vector2i(1, 2), DIR_RIGHT),
		_make_enemy(main, "enemy_right", Vector2i(3, 2), DIR_LEFT),
	])

	_resolve(main, DIR_NONE, [DIR_RIGHT, DIR_LEFT])

	_expect_eq("multi enemy hit: player pos", main.player_pos, Vector2i(2, 2))
	_expect_eq("multi enemy hit: player hp", main.player_hp, 3)
	_expect_eq("multi enemy hit: enemy_left hp", main.enemies[0]["hp"], 2)
	_expect_eq("multi enemy hit: enemy_right hp", main.enemies[1]["hp"], 2)
	_expect_true("multi enemy hit: enemy_left bumps", float(main.enemies[0]["bump_timer"]) > 0.0)
	_expect_true("multi enemy hit: enemy_right bumps", float(main.enemies[1]["bump_timer"]) > 0.0)
	_free_main(main)

func _test_enemy_side_hit_damages_player() -> void:
	var main := _new_main()
	_set_units(main, Vector2i(2, 2), DIR_UP, [
		_make_enemy(main, "enemy_left", Vector2i(1, 2), DIR_RIGHT),
	])

	_resolve(main, DIR_NONE, [DIR_RIGHT])

	_expect_eq("enemy side hit: player hp", main.player_hp, 4)
	_expect_eq("enemy side hit: enemy hp", main.enemies[0]["hp"], 2)
	_free_main(main)

func _test_monster_only_contest_picks_one_winner() -> void:
	var main := _new_main()
	main.rng.seed = 42
	_set_units(main, Vector2i(1, 7), DIR_RIGHT, [
		_make_enemy(main, "enemy_left", Vector2i(1, 1), DIR_RIGHT),
		_make_enemy(main, "enemy_right", Vector2i(3, 1), DIR_LEFT),
	])

	_resolve(main, DIR_NONE, [DIR_RIGHT, DIR_LEFT])

	var winners := 0
	var bumpers := 0
	for enemy in main.enemies:
		if enemy["pos"] == Vector2i(2, 1):
			winners += 1
		if float(enemy["bump_timer"]) > 0.0:
			bumpers += 1
		_expect_eq("monster-only contest: hp unchanged", enemy["hp"], 2)
	_expect_eq("monster-only contest: one winner", winners, 1)
	_expect_eq("monster-only contest: one bumper", bumpers, 1)
	_free_main(main)

func _test_multiple_enemies_contest_player_vacated_cell() -> void:
	var main := _new_main()
	main.rng.seed = 17
	_set_units(main, Vector2i(2, 1), DIR_RIGHT, [
		_make_enemy(main, "enemy_left", Vector2i(1, 1), DIR_RIGHT),
		_make_enemy(main, "enemy_down", Vector2i(2, 2), DIR_UP),
	])

	_resolve(main, DIR_RIGHT, [DIR_RIGHT, DIR_UP])

	var winners := 0
	var bumpers := 0
	for enemy in main.enemies:
		if enemy["pos"] == Vector2i(2, 1):
			winners += 1
		if float(enemy["bump_timer"]) > 0.0:
			bumpers += 1
	_expect_eq("vacated contest: player escapes", main.player_pos, Vector2i(3, 1))
	_expect_eq("vacated contest: player hp unchanged", main.player_hp, 5)
	_expect_eq("vacated contest: one enemy enters old player cell", winners, 1)
	_expect_eq("vacated contest: one enemy bumps", bumpers, 1)
	_free_main(main)

func _test_player_back_hit_kills_enemy() -> void:
	var main := _new_main()
	_set_units(main, Vector2i(1, 1), DIR_RIGHT, [
		_make_enemy(main, "enemy_a", Vector2i(2, 1), DIR_RIGHT),
	])

	_resolve(main, DIR_RIGHT, [DIR_NONE])

	_expect_eq("back hit: player stays", main.player_pos, Vector2i(1, 1))
	_expect_eq("back hit: player hp unchanged", main.player_hp, 5)
	_expect_eq("back hit: enemy hp zero", main.enemies[0]["hp"], 0)
	_expect_eq("back hit: enemy dead", main.enemies[0]["alive"], false)
	_free_main(main)

func _test_newly_alerted_enemy_chases_on_next_action() -> void:
	var main := _new_main()
	_set_units(main, Vector2i(1, 1), DIR_DOWN, [
		_make_enemy(main, "enemy_a", Vector2i(3, 1), DIR_LEFT, STATE_IDLE),
	])

	main._play_turn(DIR_DOWN)
	_expect_eq("alert: enemy becomes combat", main.enemies[0]["state"], STATE_COMBAT)
	var position_after_alert: Vector2i = main.enemies[0]["pos"]

	main._play_turn(DIR_DOWN)
	_expect_true("alert: enemy moves on next action", main.enemies[0]["pos"] != position_after_alert)
	_free_main(main)

func _test_initial_fog_reveals_line_of_sight_limited_vision() -> void:
	var main := _new_main()

	_expect_eq("initial fog: player cell clear", main._fog_state(Vector2i(1, 1)), FOG_CLEAR)
	_expect_eq("initial fog: range edge clear", main._fog_state(Vector2i(6, 1)), FOG_CLEAR)
	_expect_eq("initial fog: outside range dense", main._fog_state(Vector2i(7, 1)), FOG_DENSE)
	_expect_eq("initial fog: first wall visible", main._fog_state(Vector2i(3, 2)), FOG_CLEAR)
	_free_main(main)

func _test_fog_blocks_cells_behind_line_of_sight_wall() -> void:
	var main := _new_main()
	_set_units(main, Vector2i(3, 1), DIR_DOWN, [])

	_expect_eq("fog blocked line of sight: blocking wall visible", main._fog_state(Vector2i(3, 2)), FOG_CLEAR)
	_expect_eq("fog blocked line of sight: cell behind wall dense", main._fog_state(Vector2i(3, 4)), FOG_DENSE)
	_free_main(main)

func _test_fog_blocks_diagonal_corner_line_of_sight() -> void:
	var main := _new_main()
	_set_units(main, Vector2i(1, 1), DIR_RIGHT, [])

	_expect_eq("fog corner line of sight: grazing wall visible", main._fog_state(Vector2i(3, 2)), FOG_CLEAR)
	_expect_eq("fog corner line of sight: corner-blocked floor dense", main._fog_state(Vector2i(4, 3)), FOG_DENSE)
	_free_main(main)

func _test_fog_allows_open_diagonal_corner_line_of_sight() -> void:
	var main := _new_main()
	_set_units(main, Vector2i(1, 1), DIR_RIGHT, [])

	_expect_eq("fog open diagonal corner: floor beside single wall clear", main._fog_state(Vector2i(3, 3)), FOG_CLEAR)
	_free_main(main)

func _test_fog_blocks_closed_diagonal_corner_line_of_sight() -> void:
	var main := _new_main()
	_set_units(main, Vector2i(4, 4), DIR_RIGHT, [])

	_expect_eq("fog closed diagonal corner: floor behind paired walls dense", main._fog_state(Vector2i(6, 2)), FOG_DENSE)
	_free_main(main)

func _test_fog_reveals_walls_next_to_visible_floors() -> void:
	var main := _new_main()
	_set_units(main, Vector2i(1, 1), DIR_RIGHT, [])

	_expect_eq("fog adjacent wall reveal: wall beside visible floor clear", main._fog_state(Vector2i(3, 2)), FOG_CLEAR)
	_expect_eq("fog adjacent wall reveal: out-of-range wall remains dense", main._fog_state(Vector2i(6, 0)), FOG_DENSE)
	_free_main(main)

func _test_fog_clear_cells_become_thin_after_player_moves() -> void:
	var main := _new_main()

	_expect_eq("fog downgrade: old edge starts clear", main._fog_state(Vector2i(1, 6)), FOG_CLEAR)
	main._play_turn(DIR_RIGHT)

	_expect_eq("fog downgrade: old edge becomes thin", main._fog_state(Vector2i(1, 6)), FOG_THIN)
	_expect_eq("fog downgrade: new edge becomes clear", main._fog_state(Vector2i(7, 1)), FOG_CLEAR)
	_free_main(main)

func _test_fog_hides_enemies_outside_clear_cells() -> void:
	var main := _new_main()
	_set_units(main, Vector2i(1, 1), DIR_RIGHT, [
		_make_enemy(main, "near_enemy", Vector2i(6, 1), DIR_LEFT, STATE_IDLE),
		_make_enemy(main, "far_enemy", Vector2i(7, 1), DIR_LEFT, STATE_IDLE),
	])

	_expect_true("fog hidden enemies: near enemy visible", main._should_draw_enemy(main.enemies[0]))
	_expect_true("fog hidden enemies: far enemy hidden", not main._should_draw_enemy(main.enemies[1]))
	_free_main(main)

func _test_fog_hides_closed_corner_blocked_enemies() -> void:
	var main := _new_main()
	_set_units(main, Vector2i(4, 4), DIR_RIGHT, [
		_make_enemy(main, "corner_blocked_enemy", Vector2i(6, 2), DIR_LEFT, STATE_IDLE),
	])

	_expect_true("fog hidden enemies: closed-corner enemy hidden", not main._should_draw_enemy(main.enemies[0]))
	_free_main(main)

func _test_random_resolution_invariants() -> void:
	var main := _new_main()
	var random := RandomNumberGenerator.new()
	random.seed = 20260601
	var walkable_cells := _walkable_cells(main)
	var directions: Array[Vector2i] = [DIR_NONE, DIR_UP, DIR_DOWN, DIR_LEFT, DIR_RIGHT]

	for case_index in range(300):
		var used := {}
		var player_pos: Vector2i = _take_random_unused_cell(walkable_cells, used, random)
		var enemy_count := random.randi_range(1, 5)
		var enemies: Array = []
		for enemy_index in range(enemy_count):
			var enemy_pos := _take_random_unused_cell(walkable_cells, used, random)
			var enemy_facing := directions[random.randi_range(1, directions.size() - 1)]
			enemies.append(_make_enemy(main, "enemy_%d_%d" % [case_index, enemy_index], enemy_pos, enemy_facing))

		var player_facing := directions[random.randi_range(1, directions.size() - 1)]
		_set_units(main, player_pos, player_facing, enemies)

		var before_positions := {"player": main.player_pos}
		for enemy_index in range(main.enemies.size()):
			before_positions[str(main.enemies[enemy_index]["id"])] = main.enemies[enemy_index]["pos"]

		var player_delta := directions[random.randi_range(0, directions.size() - 1)]
		var enemy_deltas: Array[Vector2i] = []
		for enemy_index in range(main.enemies.size()):
			enemy_deltas.append(directions[random.randi_range(0, directions.size() - 1)])

		_resolve(main, player_delta, enemy_deltas)
		_assert_resolution_invariants(main, before_positions, case_index)

	_free_main(main)

func _walkable_cells(main: Node) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(main._map_height()):
		for x in range(main._map_width()):
			var cell := Vector2i(x, y)
			if main._is_walkable_cell(cell):
				cells.append(cell)
	return cells

func _take_random_unused_cell(cells: Array[Vector2i], used: Dictionary, random: RandomNumberGenerator) -> Vector2i:
	while true:
		var cell := cells[random.randi_range(0, cells.size() - 1)]
		var key := "%d,%d" % [cell.x, cell.y]
		if used.has(key):
			continue
		used[key] = true
		return cell
	return cells[0]

func _assert_resolution_invariants(main: Node, before_positions: Dictionary, case_index: int) -> void:
	if main.player_alive:
		_expect_true("random %d: player remains walkable" % case_index, main._is_walkable_cell(main.player_pos))
		_expect_true("random %d: player moves at most one cell" % case_index, _manhattan(main.player_pos, before_positions["player"]) <= 1)
	_expect_true("random %d: player hp in range" % case_index, main.player_hp >= 0 and main.player_hp <= main.PLAYER_MAX_HP)
	_expect_eq("random %d: player alive matches hp" % case_index, main.player_alive, main.player_hp > 0)

	var occupied := {}
	if main.player_alive:
		occupied[main._cell_key(main.player_pos)] = "player"

	for enemy in main.enemies:
		var enemy_id := str(enemy["id"])
		var enemy_pos: Vector2i = enemy["pos"]
		var enemy_hp := int(enemy["hp"])
		var enemy_alive := bool(enemy["alive"])
		_expect_true("random %d: %s hp in range" % [case_index, enemy_id], enemy_hp >= 0 and enemy_hp <= int(enemy["max_hp"]))
		_expect_eq("random %d: %s alive matches hp" % [case_index, enemy_id], enemy_alive, enemy_hp > 0)
		if not enemy_alive:
			continue
		_expect_true("random %d: %s remains walkable" % [case_index, enemy_id], main._is_walkable_cell(enemy_pos))
		_expect_true("random %d: %s moves at most one cell" % [case_index, enemy_id], _manhattan(enemy_pos, before_positions[enemy_id]) <= 1)
		var key: String = main._cell_key(enemy_pos)
		_expect_true("random %d: no living unit overlap at %s" % [case_index, key], not occupied.has(key))
		occupied[key] = enemy_id

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

func _expect_eq(label: String, actual: Variant, expected: Variant) -> void:
	if actual != expected:
		failures.append("%s expected %s but got %s" % [label, str(expected), str(actual)])

func _expect_true(label: String, condition: bool) -> void:
	if not condition:
		failures.append("%s expected true" % label)
