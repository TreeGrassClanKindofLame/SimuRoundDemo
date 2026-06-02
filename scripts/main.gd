extends Node2D

enum AIType { IDLE }
enum CollisionSide { FRONT, SIDE, BACK }
enum EnemyState { IDLE, COMBAT }
enum FogState { DENSE, THIN, CLEAR }

const TILE_SIZE := 48
const MAP_ORIGIN := Vector2(48, 192)
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
const PLAYER_MAX_HP := 5
const PLAYER_VISION_RANGE := 5
const DAMAGE_PER_COLLISION := 1
const BACK_COLLISION_BONUS_DAMAGE := 1
const BUMP_DURATION := 0.16
const HIT_DURATION := 0.20
const DEATH_DURATION := 0.35
const PLAYER_RESET_DELAY := 0.65
const BUMP_PIXELS := 12.0
const DIR_NONE := Vector2i(0, 0)
const DIR_UP := Vector2i(0, -1)
const DIR_DOWN := Vector2i(0, 1)
const DIR_LEFT := Vector2i(-1, 0)
const DIR_RIGHT := Vector2i(1, 0)
const MOVE_ACTIONS := [DIR_UP, DIR_DOWN, DIR_LEFT, DIR_RIGHT]
const HEART_ORIGIN := Vector2(40, 70)
const HEART_BLOCK := 3.0
const HEART_GAP := 10.0
const HEART_PATTERN := [
	"01100110",
	"11111111",
	"11111111",
	"01111110",
	"00111100",
	"00011000",
]

var player_pos := PLAYER_START
var player_facing := DIR_RIGHT
var player_hp := PLAYER_MAX_HP
var player_alive := true
var player_bump_timer := 0.0
var player_bump_dir := DIR_NONE
var player_hit_timer := 0.0
var player_death_timer := 0.0
var reset_timer := 0.0
var enemies: Array[Dictionary] = []
var turn_count := 0
var last_event := "Ready"
var show_detection_ranges := false
var rng := RandomNumberGenerator.new()
var astar_grid := AStarGrid2D.new()
var sound_players: Dictionary = {}
var turn_collision_pairs: Dictionary = {}
var fog_by_cell: Dictionary = {}

@onready var status_label: Label = $HUD/Status

func _ready() -> void:
	rng.randomize()
	_setup_audio()
	_reset_demo()

func _process(delta: float) -> void:
	var needs_redraw := false

	if player_bump_timer > 0.0:
		player_bump_timer = maxf(0.0, player_bump_timer - delta)
		needs_redraw = true
	if player_hit_timer > 0.0:
		player_hit_timer = maxf(0.0, player_hit_timer - delta)
		needs_redraw = true
	if player_death_timer > 0.0:
		player_death_timer = maxf(0.0, player_death_timer - delta)
		needs_redraw = true

	for index in range(enemies.size()):
		var enemy: Dictionary = enemies[index]
		var changed := false

		var bump_timer := float(enemy["bump_timer"])
		if bump_timer > 0.0:
			enemy["bump_timer"] = maxf(0.0, bump_timer - delta)
			changed = true

		var hit_timer := float(enemy["hit_timer"])
		if hit_timer > 0.0:
			enemy["hit_timer"] = maxf(0.0, hit_timer - delta)
			changed = true

		var death_timer := float(enemy["death_timer"])
		if death_timer > 0.0:
			enemy["death_timer"] = maxf(0.0, death_timer - delta)
			changed = true

		if changed:
			enemies[index] = enemy
			needs_redraw = true

	if reset_timer > 0.0:
		reset_timer = maxf(0.0, reset_timer - delta)
		if reset_timer == 0.0:
			_reset_demo(true)
		needs_redraw = true

	if needs_redraw:
		queue_redraw()

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
			_reset_demo(true)
		KEY_V:
			show_detection_ranges = not show_detection_ranges
			last_event = "Detection ranges shown" if show_detection_ranges else "Detection ranges hidden"
			_update_hud()
			queue_redraw()
		_:
			return

	get_viewport().set_input_as_handled()

func _setup_audio() -> void:
	sound_players["bump"] = _create_sound_player(_make_tone(90.0, 60.0, 0.08, 0.35))
	sound_players["hit"] = _create_sound_player(_make_tone(420.0, 260.0, 0.10, 0.32))
	sound_players["death"] = _create_sound_player(_make_tone(180.0, 70.0, 0.22, 0.35))
	sound_players["reset"] = _create_sound_player(_make_tone(260.0, 520.0, 0.16, 0.25))

func _create_sound_player(stream: AudioStream) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	return player

func _make_tone(freq_start: float, freq_end: float, duration: float, volume: float) -> AudioStreamWAV:
	var mix_rate := 22050
	var sample_count := int(mix_rate * duration)
	var data := PackedByteArray()

	for index in range(sample_count):
		var progress := float(index) / float(sample_count)
		var frequency := lerpf(freq_start, freq_end, progress)
		var envelope := 1.0 - progress
		var wave := sin(TAU * frequency * float(index) / float(mix_rate))
		var sample := int(clampf(128.0 + wave * 127.0 * volume * envelope, 0.0, 255.0))
		data.append(sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = data
	return stream

func _play_sound(sound_name: String) -> void:
	if not sound_players.has(sound_name):
		return

	var player: AudioStreamPlayer = sound_players[sound_name]
	player.stop()
	player.play()

func _reset_demo(play_reset_sound := false) -> void:
	player_pos = PLAYER_START
	player_facing = _random_direction()
	player_hp = PLAYER_MAX_HP
	player_alive = true
	player_bump_timer = 0.0
	player_bump_dir = DIR_NONE
	player_hit_timer = 0.0
	player_death_timer = 0.0
	reset_timer = 0.0
	turn_count = 0
	turn_collision_pairs.clear()
	last_event = "Ready"
	enemies = [
		_create_enemy(Vector2i(5, 1), AIType.IDLE),
		_create_enemy(Vector2i(9, 1), AIType.IDLE),
		_create_enemy(Vector2i(12, 1), AIType.IDLE),
		_create_enemy(Vector2i(2, 3), AIType.IDLE),
		_create_enemy(Vector2i(5, 4), AIType.IDLE),
		_create_enemy(Vector2i(10, 4), AIType.IDLE),
		_create_enemy(Vector2i(3, 7), AIType.IDLE),
		_create_enemy(Vector2i(12, 7), AIType.IDLE),
	]
	_reset_fog()
	_update_player_fog()
	if play_reset_sound:
		_play_sound("reset")
	_update_hud()
	queue_redraw()

func _create_enemy(pos: Vector2i, ai_type: int) -> Dictionary:
	return {
		"id": "%s_%s_%s" % [_ai_name(ai_type).to_lower(), pos.x, pos.y],
		"pos": pos,
		"facing": _random_direction(),
		"ai": ai_type,
		"hp": 2,
		"max_hp": 2,
		"alive": true,
		"state": EnemyState.IDLE,
		"bump_timer": 0.0,
		"bump_dir": DIR_NONE,
		"hit_timer": 0.0,
		"death_timer": 0.0,
	}

func _play_turn(player_delta: Vector2i) -> void:
	if not player_alive or reset_timer > 0.0:
		return

	turn_collision_pairs.clear()
	var snapshot := _create_turn_snapshot()
	var intents := _collect_turn_intents(player_delta, snapshot)
	_apply_intent_facings(intents)
	var turn_event := _resolve_turn_intents(intents, snapshot)
	var alert_event := ""
	if player_alive:
		_update_player_fog()
		alert_event = _update_enemy_alerts()
	if player_alive and alert_event != "" and (turn_event == "" or turn_event == "Player moves"):
		last_event = alert_event
	elif player_alive and turn_event != "":
		last_event = turn_event
	turn_count += 1
	_update_hud()
	queue_redraw()

func _create_turn_snapshot() -> Dictionary:
	var occupants := {}
	var enemy_indices_by_id := {}
	occupants[_cell_key(player_pos)] = "player"

	for index in range(enemies.size()):
		var enemy: Dictionary = enemies[index]
		if not enemy["alive"]:
			continue

		var enemy_id := str(enemy["id"])
		occupants[_cell_key(enemy["pos"])] = enemy_id
		enemy_indices_by_id[enemy_id] = index

	return {
		"player_pos": player_pos,
		"occupants": occupants,
		"enemy_indices_by_id": enemy_indices_by_id,
	}

func _collect_turn_intents(player_delta: Vector2i, snapshot: Dictionary) -> Array[Dictionary]:
	var intents: Array[Dictionary] = []
	intents.append(_make_turn_intent("player", -1, snapshot["player_pos"], player_delta))

	for index in range(enemies.size()):
		var enemy: Dictionary = enemies[index]
		if not enemy["alive"] or int(enemy["state"]) != EnemyState.COMBAT:
			continue

		var delta := _decide_enemy_chase_action(index)
		intents.append(_make_turn_intent(str(enemy["id"]), index, enemy["pos"], delta))

	return intents

func _make_turn_intent(unit_id: String, enemy_index: int, from: Vector2i, delta: Vector2i) -> Dictionary:
	var target := from + delta
	return {
		"unit_id": unit_id,
		"enemy_index": enemy_index,
		"from": from,
		"to": target,
		"delta": delta,
		"valid_target": delta == DIR_NONE or _is_walkable_cell(target),
	}

func _apply_intent_facings(intents: Array[Dictionary]) -> void:
	for intent in intents:
		var delta: Vector2i = intent["delta"]
		if delta == DIR_NONE:
			continue

		if _is_player_intent(intent):
			_face_player(delta)
		else:
			_face_enemy(int(intent["enemy_index"]), delta)

func _resolve_turn_intents(intents: Array[Dictionary], snapshot: Dictionary) -> String:
	var blocked := {}
	var intent_by_unit := {}
	var target_claims := {}
	var events: Array[String] = []
	var moved_player := false
	var moved_enemy := false

	for intent in intents:
		var unit_id := str(intent["unit_id"])
		blocked[unit_id] = false
		intent_by_unit[unit_id] = intent

		var delta: Vector2i = intent["delta"]
		if delta == DIR_NONE or not bool(intent["valid_target"]):
			continue

		var target_key := _cell_key(intent["to"])
		if not target_claims.has(target_key):
			target_claims[target_key] = []
		target_claims[target_key].append(unit_id)

	for intent in intents:
		var unit_id := str(intent["unit_id"])
		var delta: Vector2i = intent["delta"]
		if delta == DIR_NONE:
			continue

		if not bool(intent["valid_target"]):
			blocked[unit_id] = true
			_add_bump_event(events, intent, "wall")

	var occupants: Dictionary = snapshot["occupants"]
	for target_key in target_claims.keys():
		var claimants: Array = target_claims[target_key]
		if claimants.size() < 2:
			continue

		if not _is_target_cell_available_for_claimants(target_key, claimants, occupants, intent_by_unit, blocked):
			var occupant_id := ""
			if occupants.has(target_key):
				occupant_id = str(occupants[target_key])
			for unit_id in claimants:
				blocked[str(unit_id)] = true
				var intent: Dictionary = intent_by_unit[str(unit_id)]
				var collision_event := _resolve_occupied_cell_collision(intent, occupant_id, snapshot)
				if collision_event != "":
					_add_unique_event(events, collision_event)
				else:
					_add_bump_event(events, intent, "contest")
			continue

		var winner_id := _select_contested_cell_winner(claimants)
		for unit_id in claimants:
			if str(unit_id) == winner_id:
				continue
			blocked[str(unit_id)] = true
			var intent: Dictionary = intent_by_unit[str(unit_id)]
			_add_bump_event(events, intent, "contest")
		_resolve_contested_cell_collisions(claimants, intent_by_unit, events)

	for intent in intents:
		var unit_id := str(intent["unit_id"])
		var delta: Vector2i = intent["delta"]
		if delta == DIR_NONE or not bool(intent["valid_target"]):
			continue

		var target_key := _cell_key(intent["to"])
		if not occupants.has(target_key):
			continue

		var occupant_id := str(occupants[target_key])
		if occupant_id == unit_id:
			continue
		if bool(blocked[unit_id]):
			continue
		if _can_enter_vacated_cell(intent, occupant_id, intent_by_unit, blocked):
			continue

		blocked[unit_id] = true
		if intent_by_unit.has(occupant_id):
			var occupant_intent: Dictionary = intent_by_unit[occupant_id]
			if occupant_intent["delta"] != DIR_NONE:
				blocked[occupant_id] = true
				_add_bump_event(events, occupant_intent, "occupied")

		var collision_event := _resolve_occupied_cell_collision(intent, occupant_id, snapshot)
		if collision_event != "":
			_add_unique_event(events, collision_event)
		else:
			_add_bump_event(events, intent, "occupied")

	for intent in intents:
		var unit_id := str(intent["unit_id"])
		var delta: Vector2i = intent["delta"]
		if delta == DIR_NONE:
			continue

		if bool(blocked[unit_id]):
			_start_intent_bump(intent)
			continue

		if _is_player_intent(intent):
			player_pos = intent["to"]
			moved_player = true
		else:
			var enemy_index := int(intent["enemy_index"])
			if enemy_index < 0 or enemy_index >= enemies.size() or not enemies[enemy_index]["alive"]:
				continue
			var enemy: Dictionary = enemies[enemy_index]
			enemy["pos"] = intent["to"]
			enemies[enemy_index] = enemy
			moved_enemy = true

	if player_alive and moved_player:
		_add_unique_event(events, "Player moves")
	if moved_enemy:
		_add_unique_event(events, "Enemy chases player")

	if not player_alive:
		return last_event
	return _select_turn_event(events)

func _is_target_cell_available_for_claimants(target_key: String, claimants: Array, occupants: Dictionary, intent_by_unit: Dictionary, blocked: Dictionary) -> bool:
	if not occupants.has(target_key):
		return true

	var occupant_id := str(occupants[target_key])
	for unit_id in claimants:
		var claimant_intent: Dictionary = intent_by_unit[str(unit_id)]
		if not _can_enter_vacated_cell(claimant_intent, occupant_id, intent_by_unit, blocked):
			return false
	return true

func _can_enter_vacated_cell(intent: Dictionary, occupant_id: String, intent_by_unit: Dictionary, blocked: Dictionary) -> bool:
	if not intent_by_unit.has(occupant_id):
		return false
	if bool(blocked.get(occupant_id, false)):
		return false

	var occupant_intent: Dictionary = intent_by_unit[occupant_id]
	var occupant_delta: Vector2i = occupant_intent["delta"]
	if occupant_delta == DIR_NONE or not bool(occupant_intent["valid_target"]):
		return false

	var occupant_target: Vector2i = occupant_intent["to"]
	var mover_start: Vector2i = intent["from"]
	if occupant_target == mover_start:
		return false
	return true

func _select_contested_cell_winner(claimants: Array) -> String:
	for unit_id in claimants:
		if str(unit_id) == "player":
			return "player"
	return str(claimants[rng.randi_range(0, claimants.size() - 1)])

func _resolve_contested_cell_collisions(claimants: Array, intent_by_unit: Dictionary, events: Array[String]) -> void:
	if not claimants.has("player"):
		return

	var hit_count := 0
	for unit_id in claimants:
		var enemy_id := str(unit_id)
		if enemy_id == "player":
			continue
		if not _register_collision_pair("player", enemy_id):
			continue

		var enemy_intent: Dictionary = intent_by_unit[enemy_id]
		var enemy_index := int(enemy_intent["enemy_index"])
		if enemy_index < 0 or enemy_index >= enemies.size() or not enemies[enemy_index]["alive"]:
			continue

		_damage_enemy(enemy_index, DAMAGE_PER_COLLISION)
		_damage_player(DAMAGE_PER_COLLISION)
		hit_count += 1

	if hit_count > 0:
		_play_sound("hit")
		_add_unique_event(events, _player_enemy_collision_event_text(CollisionSide.FRONT))

func _resolve_occupied_cell_collision(intent: Dictionary, occupant_id: String, snapshot: Dictionary) -> String:
	var unit_id := str(intent["unit_id"])
	if unit_id != "player" and occupant_id != "player":
		return ""

	var enemy_indices_by_id: Dictionary = snapshot["enemy_indices_by_id"]
	if unit_id == "player":
		if not enemy_indices_by_id.has(occupant_id):
			return ""
		if not _register_collision_pair("player", occupant_id):
			return "Player and enemy already collided this turn"

		var enemy_index := int(enemy_indices_by_id[occupant_id])
		if enemy_index < 0 or enemy_index >= enemies.size() or not enemies[enemy_index]["alive"]:
			return ""

		var enemy: Dictionary = enemies[enemy_index]
		var enemy_pos: Vector2i = enemy["pos"]
		var enemy_facing: Vector2i = enemy["facing"]
		var attacker_pos: Vector2i = intent["from"]
		var collision_side := _collision_side(enemy_pos, enemy_facing, attacker_pos)
		var enemy_damage := _enemy_collision_damage(collision_side)
		var player_damage := _player_collision_damage(collision_side)
		_damage_enemy(enemy_index, enemy_damage)
		if player_damage > 0:
			_damage_player(player_damage)
		_play_sound("hit")
		return _player_enemy_collision_event_text(collision_side)

	if occupant_id != "player":
		return ""
	if not _register_collision_pair("player", unit_id):
		return "Player and enemy already collided this turn"

	var attacker_enemy_index := int(intent["enemy_index"])
	if attacker_enemy_index < 0 or attacker_enemy_index >= enemies.size() or not enemies[attacker_enemy_index]["alive"]:
		return ""

	var enemy_attacker_pos: Vector2i = intent["from"]
	var player_side := _collision_side(player_pos, player_facing, enemy_attacker_pos)
	var damage_to_player := _enemy_collision_damage(player_side)
	var damage_to_enemy := _player_collision_damage(player_side)
	if damage_to_enemy > 0:
		_damage_enemy(attacker_enemy_index, damage_to_enemy)
	if damage_to_player > 0:
		_damage_player(damage_to_player)
	_play_sound("hit")
	return _enemy_player_collision_event_text(player_side)

func _add_bump_event(events: Array[String], intent: Dictionary, reason: String) -> void:
	if _is_player_intent(intent):
		if reason == "wall":
			_add_unique_event(events, "Player bumps into a wall")
		elif reason == "occupied":
			_add_unique_event(events, "Player bumps into an occupied cell")
		else:
			_add_unique_event(events, "Player cannot enter a contested cell")
		return

	if reason == "wall":
		_add_unique_event(events, "Enemy bumps into wall")
	elif reason == "occupied":
		var target: Vector2i = intent["to"]
		if target == player_pos:
			_add_unique_event(events, "Enemy bumps into player")
		else:
			_add_unique_event(events, "Enemy bumps into enemy")
	else:
		_add_unique_event(events, "Enemies contest the same cell")

func _start_intent_bump(intent: Dictionary) -> void:
	var delta: Vector2i = intent["delta"]
	if delta == DIR_NONE:
		return

	if _is_player_intent(intent):
		_start_player_bump(delta)
	else:
		_start_enemy_bump(int(intent["enemy_index"]), delta)
	_play_sound("bump")

func _is_player_intent(intent: Dictionary) -> bool:
	return str(intent["unit_id"]) == "player"

func _add_unique_event(events: Array[String], event_text: String) -> void:
	if event_text == "":
		return
	if not events.has(event_text):
		events.append(event_text)

func _select_turn_event(events: Array[String]) -> String:
	for event_text in events:
		if event_text.begins_with("Front collision") or event_text.begins_with("Back collision") or event_text.begins_with("Side collision"):
			return event_text
	for event_text in events:
		if event_text == "Player and enemy already collided this turn":
			return event_text
	for event_text in events:
		if event_text.begins_with("Player bumps") or event_text.begins_with("Player cannot"):
			return event_text
	for event_text in events:
		if event_text.begins_with("Enemy") or event_text.begins_with("Enemies"):
			return event_text
	for event_text in events:
		if event_text == "Player moves":
			return event_text
	if events.size() > 0:
		return events[0]
	return ""

func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

func _reset_fog() -> void:
	fog_by_cell.clear()
	for y in range(_map_height()):
		for x in range(_map_width()):
			fog_by_cell[_cell_key(Vector2i(x, y))] = FogState.DENSE

func _update_player_fog() -> void:
	if not player_alive:
		return

	var visible_cells := _player_visible_cells()
	for key in fog_by_cell.keys():
		if visible_cells.has(key):
			fog_by_cell[key] = FogState.CLEAR
		elif int(fog_by_cell[key]) == FogState.CLEAR:
			fog_by_cell[key] = FogState.THIN

func _player_visible_cells() -> Dictionary:
	var visible_cells := {}
	for y in range(_map_height()):
		for x in range(_map_width()):
			var cell := Vector2i(x, y)
			if _is_cell_in_player_vision(cell):
				visible_cells[_cell_key(cell)] = true

	return visible_cells

func _is_cell_in_player_vision(cell: Vector2i) -> bool:
	if not _is_inside_map(cell):
		return false
	if _manhattan_distance(player_pos, cell) > PLAYER_VISION_RANGE:
		return false
	return _has_unblocked_shortest_vision_path(player_pos, cell)

func _has_unblocked_shortest_vision_path(from: Vector2i, to: Vector2i) -> bool:
	if from == to:
		return true

	var queue: Array[Vector2i] = [from]
	var visited := {}
	visited[_cell_key(from)] = true

	while queue.size() > 0:
		var cell: Vector2i = queue.pop_front()
		var current_distance := _manhattan_distance(cell, to)
		for neighbor in _cardinal_neighbors(cell):
			if not _is_inside_map(neighbor):
				continue
			if _manhattan_distance(neighbor, to) >= current_distance:
				continue
			if neighbor != to and _is_wall(neighbor):
				continue
			if neighbor == to:
				return true

			var neighbor_key := _cell_key(neighbor)
			if visited.has(neighbor_key):
				continue
			visited[neighbor_key] = true
			queue.append(neighbor)

	return false

func _cardinal_neighbors(cell: Vector2i) -> Array[Vector2i]:
	return [
		cell + DIR_UP,
		cell + DIR_DOWN,
		cell + DIR_LEFT,
		cell + DIR_RIGHT,
	]

func _manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

func _fog_state(cell: Vector2i) -> int:
	return int(fog_by_cell.get(_cell_key(cell), FogState.DENSE))

func _is_cell_clear(cell: Vector2i) -> bool:
	return _fog_state(cell) == FogState.CLEAR

func _should_draw_enemy(enemy: Dictionary) -> bool:
	var enemy_pos: Vector2i = enemy["pos"]
	return _is_cell_clear(enemy_pos)

func _update_enemy_alerts() -> String:
	var alerted_count := 0
	for index in range(enemies.size()):
		var enemy: Dictionary = enemies[index]
		if not enemy["alive"] or int(enemy["state"]) != EnemyState.IDLE:
			continue
		if _enemy_can_detect_player(enemy):
			enemy["state"] = EnemyState.COMBAT
			enemies[index] = enemy
			alerted_count += 1

	if alerted_count == 1:
		return "An enemy spotted the player"
	elif alerted_count > 1:
		return "%d enemies spotted the player" % alerted_count
	return ""

func _decide_enemy_chase_action(index: int) -> Vector2i:
	_setup_chase_astar(index)
	var enemy_pos: Vector2i = enemies[index]["pos"]
	var path: Array[Vector2i] = astar_grid.get_id_path(enemy_pos, player_pos)
	if path.size() < 2:
		return DIR_NONE
	return path[1] - enemy_pos

func _damage_player(amount: int) -> void:
	if not player_alive:
		return

	player_hp = maxi(0, player_hp - amount)
	player_hit_timer = HIT_DURATION
	if player_hp == 0:
		player_alive = false
		player_death_timer = DEATH_DURATION
		reset_timer = PLAYER_RESET_DELAY
		last_event = "Player died. Resetting..."
		_play_sound("death")

func _damage_enemy(index: int, amount: int) -> void:
	if index < 0 or index >= enemies.size():
		return

	var enemy: Dictionary = enemies[index]
	if not enemy["alive"]:
		return

	enemy["hp"] = maxi(0, int(enemy["hp"]) - amount)
	enemy["hit_timer"] = HIT_DURATION
	if int(enemy["hp"]) == 0:
		enemy["alive"] = false
		enemy["death_timer"] = DEATH_DURATION
		_play_sound("death")
	enemies[index] = enemy

func _start_player_bump(direction: Vector2i) -> void:
	player_bump_dir = direction
	player_bump_timer = BUMP_DURATION

func _face_player(direction: Vector2i) -> void:
	if direction != DIR_NONE:
		player_facing = direction

func _face_enemy(index: int, direction: Vector2i) -> void:
	if direction == DIR_NONE:
		return

	var enemy: Dictionary = enemies[index]
	enemy["facing"] = direction
	enemies[index] = enemy

func _start_enemy_bump(index: int, direction: Vector2i) -> void:
	var enemy: Dictionary = enemies[index]
	enemy["bump_dir"] = direction
	enemy["bump_timer"] = BUMP_DURATION
	enemies[index] = enemy

func _register_collision_pair(unit_a: String, unit_b: String) -> bool:
	var pair := [unit_a, unit_b]
	pair.sort()
	var key := "%s|%s" % [pair[0], pair[1]]
	if turn_collision_pairs.has(key):
		return false

	turn_collision_pairs[key] = true
	return true

func _collision_side(victim_pos: Vector2i, victim_facing: Vector2i, attacker_pos: Vector2i) -> int:
	if attacker_pos == victim_pos + victim_facing:
		return CollisionSide.FRONT
	if attacker_pos == victim_pos + _back_direction(victim_facing):
		return CollisionSide.BACK
	return CollisionSide.SIDE

func _enemy_collision_damage(collision_side: int) -> int:
	if collision_side == CollisionSide.BACK:
		return DAMAGE_PER_COLLISION + BACK_COLLISION_BONUS_DAMAGE
	return DAMAGE_PER_COLLISION

func _player_collision_damage(collision_side: int) -> int:
	if collision_side == CollisionSide.FRONT:
		return DAMAGE_PER_COLLISION
	return 0

func _player_enemy_collision_event_text(collision_side: int) -> String:
	match collision_side:
		CollisionSide.FRONT:
			return "Front collision: player and enemy both take damage"
		CollisionSide.BACK:
			return "Back collision: enemy takes heavy damage"
	return "Side collision: enemy takes damage"

func _enemy_player_collision_event_text(collision_side: int) -> String:
	match collision_side:
		CollisionSide.FRONT:
			return "Front collision: player and enemy both take damage"
		CollisionSide.BACK:
			return "Back collision: player takes heavy damage"
	return "Side collision: player takes damage"

func _setup_chase_astar(current_enemy_index: int) -> void:
	astar_grid.region = Rect2i(Vector2i.ZERO, Vector2i(_map_width(), _map_height()))
	astar_grid.cell_size = Vector2(1, 1)
	astar_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar_grid.update()

	for y in range(_map_height()):
		for x in range(_map_width()):
			var cell := Vector2i(x, y)
			astar_grid.set_point_solid(cell, _is_wall(cell))

	for index in range(enemies.size()):
		if index == current_enemy_index or not enemies[index]["alive"]:
			continue
		astar_grid.set_point_solid(enemies[index]["pos"], true)

func _enemy_can_detect_player(enemy: Dictionary) -> bool:
	return _has_cell(_visible_detection_cells(enemy), player_pos)

func _visible_detection_cells(enemy: Dictionary) -> Array[Vector2i]:
	var visible_cells: Array[Vector2i] = []
	var origin: Vector2i = enemy["pos"]
	for cell in _raw_detection_cells(origin, enemy["facing"]):
		if not _is_inside_map(cell) or _has_cell(visible_cells, cell):
			continue
		if _has_detection_line_of_sight(origin, cell):
			visible_cells.append(cell)
	return visible_cells

func _raw_detection_cells(origin: Vector2i, facing: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var side := _side_up_direction(facing)
	cells.append(origin + side)
	cells.append(origin - side)
	for offset in range(-1, 2):
		cells.append(origin + facing + side * offset)
	for offset in range(-2, 3):
		cells.append(origin + facing * 2 + side * offset)
	return cells

func _has_detection_line_of_sight(origin: Vector2i, target: Vector2i) -> bool:
	if not _is_inside_map(target) or _is_wall(target):
		return false

	var delta := target - origin
	var steps := maxi(abs(delta.x), abs(delta.y))
	var visited: Array[Vector2i] = []
	for step in range(1, steps + 1):
		var progress := float(step) / float(steps)
		var cell := Vector2i(
			int(round(float(origin.x) + float(delta.x) * progress)),
			int(round(float(origin.y) + float(delta.y) * progress))
		)
		if cell == origin or _has_cell(visited, cell):
			continue
		visited.append(cell)
		if _is_wall(cell):
			return false
	return true

func _has_cell(cells: Array, target: Vector2i) -> bool:
	for cell in cells:
		if cell == target:
			return true
	return false

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

func _living_enemy_count() -> int:
	var count := 0
	for enemy in enemies:
		if enemy["alive"]:
			count += 1
	return count

func _random_direction() -> Vector2i:
	var directions := [DIR_UP, DIR_DOWN, DIR_LEFT, DIR_RIGHT]
	var direction: Vector2i = directions[rng.randi_range(0, directions.size() - 1)]
	return direction

func _back_direction(facing: Vector2i) -> Vector2i:
	return -facing

func _side_up_direction(facing: Vector2i) -> Vector2i:
	return Vector2i(facing.y, -facing.x)

func _side_down_direction(facing: Vector2i) -> Vector2i:
	return Vector2i(-facing.y, facing.x)

func _update_hud() -> void:
	status_label.text = "Turn %d\nEnemies: %d\n%s" % [
		turn_count,
		_living_enemy_count(),
		last_event,
	]

func _draw() -> void:
	_draw_player_hp_hearts()
	_draw_map()
	_draw_detection_ranges()
	_draw_units()
	_draw_fog()

func _draw_player_hp_hearts() -> void:
	var heart_width := _heart_width(HEART_BLOCK)
	for heart_index in range(PLAYER_MAX_HP):
		var heart_pos := HEART_ORIGIN + Vector2(heart_index * (heart_width + HEART_GAP), 0)
		var filled := heart_index < player_hp
		_draw_heart_icon(heart_pos, filled, HEART_BLOCK)

func _draw_heart_icon(heart_pos: Vector2, filled: bool, block_size: float) -> void:
	var fill_color := Color(0.91, 0.12, 0.18) if filled else Color(0.18, 0.10, 0.12)
	var shadow_color := Color(0.03, 0.02, 0.02, 0.60)
	var shine_color := Color(1.0, 0.46, 0.50) if filled else Color(0.30, 0.18, 0.20)
	for y in range(HEART_PATTERN.size()):
		var row: String = HEART_PATTERN[y]
		for x in range(row.length()):
			if row.substr(x, 1) != "1":
				continue
			var block_pos := heart_pos + Vector2(x, y) * block_size
			draw_rect(Rect2(block_pos + Vector2(1, 1), Vector2(block_size, block_size)), shadow_color)
			draw_rect(Rect2(block_pos, Vector2(block_size, block_size)), fill_color)
	if filled:
		draw_rect(Rect2(heart_pos + Vector2(block_size, block_size), Vector2(block_size, block_size)), shine_color)

func _heart_width(block_size: float) -> float:
	return HEART_PATTERN[0].length() * block_size

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
	if player_alive or player_death_timer > 0.0:
		var player_color := Color(0.15, 0.78, 0.42)
		var player_alpha := 1.0
		var player_scale := 1.0
		if player_hit_timer > 0.0:
			player_color = player_color.lerp(Color.WHITE, 0.65)
		if not player_alive:
			player_alpha = player_death_timer / DEATH_DURATION
			player_scale = maxf(0.15, player_alpha)
		_draw_unit(player_pos, player_color, Color(0.85, 1.0, 0.90), player_facing, _player_bump_offset(), player_alpha, player_scale, true)

	for enemy in enemies:
		if enemy["alive"] or float(enemy["death_timer"]) > 0.0:
			if not _should_draw_enemy(enemy):
				continue

			var enemy_color := _enemy_color(enemy["ai"])
			var alpha := 1.0
			var unit_scale := 1.0
			if float(enemy["hit_timer"]) > 0.0:
				enemy_color = enemy_color.lerp(Color.WHITE, 0.65)
			if not enemy["alive"]:
				alpha = float(enemy["death_timer"]) / DEATH_DURATION
				unit_scale = maxf(0.15, alpha)

			var facing: Vector2i = enemy["facing"]
			_draw_unit(enemy["pos"], enemy_color, Color(1.0, 0.92, 0.72), facing, _enemy_bump_offset(enemy), alpha, unit_scale, false)
			if enemy["alive"]:
				_draw_enemy_hp(enemy)
				_draw_enemy_state_label(enemy)

func _draw_detection_ranges() -> void:
	if not show_detection_ranges:
		return

	for enemy in enemies:
		if not enemy["alive"]:
			continue
		if not _should_draw_enemy(enemy):
			continue
		var range_color := Color(0.22, 0.55, 1.0, 0.24)
		var border_color := Color(0.30, 0.70, 1.0, 0.55)
		for cell in _visible_detection_cells(enemy):
			if not _is_cell_clear(cell):
				continue
			var rect := _cell_rect(cell).grow(-6)
			draw_rect(rect, range_color)
			draw_rect(rect, border_color, false, 2.0)

func _draw_fog() -> void:
	for y in range(_map_height()):
		for x in range(_map_width()):
			var cell := Vector2i(x, y)
			var fog_state := _fog_state(cell)
			if fog_state == FogState.CLEAR:
				continue

			var rect := _cell_rect(cell)
			if fog_state == FogState.DENSE:
				draw_rect(rect, Color(0.015, 0.018, 0.026, 1.0))
			else:
				draw_rect(rect, Color(0.05, 0.08, 0.10, 0.48))

func _draw_unit(cell: Vector2i, body_color: Color, eye_color: Color, facing: Vector2i, offset: Vector2, alpha: float, unit_scale: float, is_player_unit: bool) -> void:
	var base_rect := _cell_rect(cell).grow(-7)
	var scaled_size := base_rect.size * unit_scale
	var rect := Rect2(base_rect.position + (base_rect.size - scaled_size) * 0.5 + offset, scaled_size)
	if is_player_unit:
		_draw_player_sprite(rect, facing, body_color, alpha, unit_scale)
	else:
		_draw_enemy_sprite(rect, facing, body_color, eye_color, alpha, unit_scale)

func _draw_player_sprite(rect: Rect2, facing: Vector2i, outfit_color: Color, alpha: float, unit_scale: float) -> void:
	var outline := Color(0.04, 0.03, 0.02, alpha)
	var skin := Color(0.96, 0.72, 0.50, alpha)
	var hair := Color(0.36, 0.20, 0.10, alpha)
	var outfit := Color(outfit_color.r, outfit_color.g, outfit_color.b, alpha)
	var trim := Color(0.92, 0.74, 0.28, alpha)
	var eye := Color(0.05, 0.20, 0.16, alpha)
	var boot := Color(0.18, 0.10, 0.05, alpha)

	_draw_sprite_shadow(rect, alpha, unit_scale)
	if facing == DIR_UP:
		_draw_px(rect, 9, 4, 16, 8, outline, unit_scale)
		_draw_px(rect, 8, 6, 18, 10, hair, unit_scale)
		_draw_px(rect, 7, 15, 20, 13, outfit, unit_scale)
		_draw_px(rect, 11, 18, 12, 3, trim, unit_scale)
		_draw_px(rect, 10, 28, 5, 4, boot, unit_scale)
		_draw_px(rect, 20, 28, 5, 4, boot, unit_scale)
	elif facing == DIR_DOWN:
		_draw_px(rect, 8, 4, 18, 8, outline, unit_scale)
		_draw_px(rect, 7, 5, 20, 8, hair, unit_scale)
		_draw_px(rect, 10, 11, 14, 10, skin, unit_scale)
		_draw_px(rect, 12, 15, 3, 3, eye, unit_scale)
		_draw_px(rect, 20, 15, 3, 3, eye, unit_scale)
		_draw_px(rect, 8, 21, 18, 8, outfit, unit_scale)
		_draw_px(rect, 15, 22, 5, 3, trim, unit_scale)
		_draw_px(rect, 10, 29, 5, 4, boot, unit_scale)
		_draw_px(rect, 20, 29, 5, 4, boot, unit_scale)
	elif facing == DIR_LEFT:
		_draw_player_side_sprite(rect, -1, outfit, skin, hair, trim, eye, boot, outline, unit_scale)
	elif facing == DIR_RIGHT:
		_draw_player_side_sprite(rect, 1, outfit, skin, hair, trim, eye, boot, outline, unit_scale)

func _draw_player_side_sprite(rect: Rect2, side: int, outfit: Color, skin: Color, hair: Color, trim: Color, eye: Color, boot: Color, outline: Color, unit_scale: float) -> void:
	var x_face := 9 if side < 0 else 16
	var x_back := 18 if side < 0 else 8
	_draw_px(rect, x_back, 5, 12, 8, outline, unit_scale)
	_draw_px(rect, x_back, 5, 13, 9, hair, unit_scale)
	_draw_px(rect, x_face, 11, 10, 9, skin, unit_scale)
	_draw_px(rect, x_face + (1 if side < 0 else 6), 15, 3, 3, eye, unit_scale)
	_draw_px(rect, 10, 20, 15, 9, outfit, unit_scale)
	_draw_px(rect, 12, 22, 10, 3, trim, unit_scale)
	_draw_px(rect, 12, 29, 5, 4, boot, unit_scale)
	_draw_px(rect, 21, 29, 5, 4, boot, unit_scale)

func _draw_enemy_sprite(rect: Rect2, facing: Vector2i, armor_color: Color, eye_color: Color, alpha: float, unit_scale: float) -> void:
	var outline := Color(0.03, 0.03, 0.05, alpha)
	var metal := Color(0.30, 0.30, 0.38, alpha)
	var dark_metal := Color(0.13, 0.12, 0.18, alpha)
	var armor := Color(armor_color.r, armor_color.g, armor_color.b, alpha)
	var crest := Color(0.94, 0.70, 0.22, alpha)
	var eye := Color(eye_color.r, 0.12, 0.10, alpha)

	_draw_sprite_shadow(rect, alpha, unit_scale)
	if facing == DIR_UP:
		_draw_px(rect, 8, 5, 18, 11, outline, unit_scale)
		_draw_px(rect, 10, 4, 14, 12, armor, unit_scale)
		_draw_px(rect, 16, 3, 3, 14, crest, unit_scale)
		_draw_px(rect, 7, 15, 20, 13, armor, unit_scale)
		_draw_px(rect, 10, 21, 14, 4, dark_metal, unit_scale)
		_draw_px(rect, 9, 29, 6, 4, dark_metal, unit_scale)
		_draw_px(rect, 20, 29, 6, 4, dark_metal, unit_scale)
	elif facing == DIR_DOWN:
		_draw_px(rect, 8, 4, 18, 10, outline, unit_scale)
		_draw_px(rect, 10, 4, 14, 12, armor, unit_scale)
		_draw_px(rect, 16, 3, 3, 13, crest, unit_scale)
		_draw_px(rect, 10, 12, 14, 8, metal, unit_scale)
		_draw_px(rect, 12, 15, 3, 3, eye, unit_scale)
		_draw_px(rect, 20, 15, 3, 3, eye, unit_scale)
		_draw_px(rect, 8, 21, 18, 8, armor, unit_scale)
		_draw_px(rect, 10, 29, 6, 4, dark_metal, unit_scale)
		_draw_px(rect, 20, 29, 6, 4, dark_metal, unit_scale)
	elif facing == DIR_LEFT:
		_draw_enemy_side_sprite(rect, -1, armor, metal, dark_metal, crest, eye, outline, unit_scale)
	elif facing == DIR_RIGHT:
		_draw_enemy_side_sprite(rect, 1, armor, metal, dark_metal, crest, eye, outline, unit_scale)

func _draw_enemy_side_sprite(rect: Rect2, side: int, armor: Color, metal: Color, dark_metal: Color, crest: Color, eye: Color, outline: Color, unit_scale: float) -> void:
	var face_x := 9 if side < 0 else 16
	var helm_x := 10 if side < 0 else 12
	_draw_px(rect, helm_x, 4, 14, 11, outline, unit_scale)
	_draw_px(rect, helm_x, 5, 14, 10, armor, unit_scale)
	_draw_px(rect, helm_x + 5, 3, 3, 13, crest, unit_scale)
	_draw_px(rect, face_x, 12, 10, 8, metal, unit_scale)
	_draw_px(rect, face_x + (1 if side < 0 else 6), 15, 3, 3, eye, unit_scale)
	_draw_px(rect, 10, 21, 16, 8, armor, unit_scale)
	_draw_px(rect, 12, 29, 6, 4, dark_metal, unit_scale)
	_draw_px(rect, 21, 29, 6, 4, dark_metal, unit_scale)

func _draw_sprite_shadow(rect: Rect2, alpha: float, unit_scale: float) -> void:
	_draw_px(rect, 7, 30, 20, 3, Color(0.02, 0.02, 0.02, alpha * 0.55), unit_scale)

func _draw_px(rect: Rect2, x: int, y: int, width: int, height: int, color: Color, unit_scale: float) -> void:
	draw_rect(Rect2(rect.position + Vector2(x, y) * unit_scale, Vector2(width, height) * unit_scale), color)

func _draw_enemy_hp(enemy: Dictionary) -> void:
	var hp := int(enemy["hp"])
	var max_hp := int(enemy["max_hp"])
	var start := _cell_rect(enemy["pos"]).position + Vector2(8, -9) + _enemy_bump_offset(enemy)
	for index in range(max_hp):
		var pip_rect := Rect2(start + Vector2(index * 10, 0), Vector2(7, 5))
		var pip_color := Color(0.88, 0.16, 0.18) if index < hp else Color(0.20, 0.05, 0.06)
		draw_rect(pip_rect, pip_color)

func _draw_enemy_state_label(enemy: Dictionary) -> void:
	var text := _enemy_state_name(enemy)
	var font := ThemeDB.fallback_font
	var font_size := 10
	var offset := _enemy_bump_offset(enemy)
	var top_left := _cell_rect(enemy["pos"]).position + Vector2(4, -25) + offset
	var text_width := float(text.length() * 7)
	var tag_rect := Rect2(top_left, Vector2(maxf(34.0, text_width + 8.0), 13))
	draw_rect(tag_rect, Color(0.04, 0.08, 0.12, 0.82))
	draw_rect(tag_rect, Color(0.02, 0.02, 0.02, 0.85), false, 1.0)
	draw_string(font, top_left + Vector2(4, 10), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(0.70, 0.90, 1.0))

func _player_bump_offset() -> Vector2:
	return _bump_offset(player_bump_timer, player_bump_dir)

func _enemy_bump_offset(enemy: Dictionary) -> Vector2:
	var timer := float(enemy["bump_timer"])
	var direction: Vector2i = enemy["bump_dir"]
	return _bump_offset(timer, direction)

func _bump_offset(timer: float, direction: Vector2i) -> Vector2:
	if timer <= 0.0 or direction == DIR_NONE:
		return Vector2.ZERO

	var progress := 1.0 - timer / BUMP_DURATION
	var distance := sin(progress * PI) * BUMP_PIXELS
	return Vector2(direction) * distance

func _cell_rect(cell: Vector2i) -> Rect2:
	var pixel_pos := Vector2(cell.x * TILE_SIZE, cell.y * TILE_SIZE)
	return Rect2(MAP_ORIGIN + pixel_pos, Vector2(TILE_SIZE, TILE_SIZE))

func _enemy_color(ai_type: int) -> Color:
	match ai_type:
		AIType.IDLE:
			return Color(0.20, 0.42, 0.92)
	return Color.WHITE

func _enemy_state_name(enemy: Dictionary) -> String:
	if int(enemy["state"]) == EnemyState.COMBAT:
		return "COMBAT"
	return "IDLE"

func _ai_name(ai_type: int) -> String:
	match ai_type:
		AIType.IDLE:
			return "Idle"
	return "Unknown"
