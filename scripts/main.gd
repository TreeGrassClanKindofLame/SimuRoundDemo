extends Node2D

enum AIType { IDLE, RANDOM, CHASE, FLEE }
enum MapId { NORMAL, BOSS }
enum BossState { NORMAL, CHARGING, STUNNED }

const TILE_SIZE := 48
const MAP_ORIGIN := Vector2(48, 192)
const NORMAL_MAP_ROWS := [
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
const BOSS_MAP_ROWS := [
	"###############",
	"#.............#",
	"#.............#",
	"#.............#",
	"#.............#",
	"#.............#",
	"#.............#",
	"#.............#",
	"###############",
]
const NORMAL_PLAYER_START := Vector2i(1, 1)
const BOSS_PLAYER_START := Vector2i(2, 4)
const BOSS_START := Vector2i(10, 4)
const BOSS_SIZE := Vector2i(2, 2)
const PLAYER_MAX_HP := 5
const BOSS_MAX_HP := 5
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
const ACTIONS := [DIR_NONE, DIR_UP, DIR_DOWN, DIR_LEFT, DIR_RIGHT]
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

var current_map_id: MapId = MapId.NORMAL
var player_pos := NORMAL_PLAYER_START
var player_facing := DIR_RIGHT
var player_hp := PLAYER_MAX_HP
var player_alive := true
var player_bump_timer := 0.0
var player_bump_dir := DIR_NONE
var player_hit_timer := 0.0
var player_death_timer := 0.0
var reset_timer := 0.0
var enemies: Array[Dictionary] = []
var boss: Dictionary = {}
var turn_count := 0
var last_event := "Ready"
var rng := RandomNumberGenerator.new()
var astar_grid := AStarGrid2D.new()
var sound_players: Dictionary = {}
var turn_collision_pairs: Dictionary = {}

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

	if _has_boss():
		var changed_boss := false
		var boss_bump_timer := float(boss["bump_timer"])
		if boss_bump_timer > 0.0:
			boss["bump_timer"] = maxf(0.0, boss_bump_timer - delta)
			changed_boss = true

		var boss_hit_timer := float(boss["hit_timer"])
		if boss_hit_timer > 0.0:
			boss["hit_timer"] = maxf(0.0, boss_hit_timer - delta)
			changed_boss = true

		var boss_death_timer := float(boss["death_timer"])
		if boss_death_timer > 0.0:
			boss["death_timer"] = maxf(0.0, boss_death_timer - delta)
			changed_boss = true

		if changed_boss:
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
		KEY_1:
			_switch_map(MapId.NORMAL)
		KEY_2:
			_switch_map(MapId.BOSS)
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

func _switch_map(map_id: MapId) -> void:
	current_map_id = map_id
	_reset_demo(true)

func _reset_demo(play_reset_sound := false) -> void:
	_setup_astar_grid()
	player_pos = _player_start_for_current_map()
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
	enemies = []
	boss = {}

	if current_map_id == MapId.NORMAL:
		last_event = "Ready"
		enemies = [
			_create_enemy(Vector2i(6, 1), AIType.IDLE),
			_create_enemy(Vector2i(12, 1), AIType.RANDOM),
			_create_enemy(Vector2i(12, 7), AIType.CHASE),
			_create_enemy(Vector2i(2, 7), AIType.FLEE),
			_create_enemy(Vector2i(8, 5), AIType.RANDOM),
		]
	else:
		last_event = "Boss arena ready"
		boss = _create_boss(BOSS_START)

	if play_reset_sound:
		_play_sound("reset")
	_update_hud()
	queue_redraw()

func _player_start_for_current_map() -> Vector2i:
	if current_map_id == MapId.BOSS:
		return BOSS_PLAYER_START
	return NORMAL_PLAYER_START

func _create_enemy(pos: Vector2i, ai_type: int) -> Dictionary:
	var max_hp := _enemy_max_hp(ai_type)
	return {
		"id": "%s_%s_%s" % [_ai_name(ai_type).to_lower(), pos.x, pos.y],
		"pos": pos,
		"facing": _random_direction(),
		"ai": ai_type,
		"hp": max_hp,
		"max_hp": max_hp,
		"alive": true,
		"bump_timer": 0.0,
		"bump_dir": DIR_NONE,
		"hit_timer": 0.0,
		"death_timer": 0.0,
	}

func _create_boss(pos: Vector2i) -> Dictionary:
	return {
		"id": "boss",
		"pos": pos,
		"facing": DIR_LEFT,
		"hp": BOSS_MAX_HP,
		"max_hp": BOSS_MAX_HP,
		"alive": true,
		"state": BossState.NORMAL,
		"charge_area": [],
		"bump_timer": 0.0,
		"bump_dir": DIR_NONE,
		"hit_timer": 0.0,
		"death_timer": 0.0,
	}

func _play_turn(player_delta: Vector2i) -> void:
	if not player_alive or reset_timer > 0.0:
		return

	turn_collision_pairs.clear()
	_try_move_player(player_delta)
	if player_alive:
		_take_enemy_turns()
	if player_alive:
		_take_boss_turn()

	turn_count += 1
	_update_hud()
	queue_redraw()

func _try_move_player(delta: Vector2i) -> void:
	_face_player(delta)

	var target: Vector2i = player_pos + delta
	if not _is_walkable_cell(target):
		_start_player_bump(delta)
		_play_sound("bump")
		last_event = "Player bumps into a wall"
		return

	if _is_boss_at_cell(target):
		_start_player_bump(delta)
		if _register_collision_pair("player", "boss"):
			var player_damage := _collision_damage(player_pos, player_facing, target)
			var boss_damage := _boss_collision_damage(player_pos)
			_damage_player(player_damage)
			_damage_boss(boss_damage)
			_play_sound("hit")
			last_event = _collision_event_text("Player and boss both take damage", "Player", player_damage, "boss", boss_damage)
		else:
			_play_sound("bump")
			last_event = "Player and boss already collided this turn"
		return

	var enemy_index := _enemy_at(target)
	if enemy_index != -1:
		_start_player_bump(delta)
		if _register_collision_pair("player", _enemy_unit_id(enemy_index)):
			var enemy: Dictionary = enemies[enemy_index]
			var enemy_pos: Vector2i = enemy["pos"]
			var enemy_facing: Vector2i = enemy["facing"]
			var player_damage := _collision_damage(player_pos, player_facing, enemy_pos)
			var enemy_damage := _collision_damage(enemy_pos, enemy_facing, player_pos)
			_damage_player(player_damage)
			_damage_enemy(enemy_index, enemy_damage)
			_play_sound("hit")
			last_event = _collision_event_text("Player and enemy both take damage", "Player", player_damage, "enemy", enemy_damage)
		else:
			_play_sound("bump")
			last_event = "Player and enemy already collided this turn"
		return

	player_pos = target
	last_event = "Player moves"

func _take_enemy_turns() -> void:
	for index in range(enemies.size()):
		if not player_alive:
			return
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
		if delta != DIR_NONE and _is_boss_at_cell(target):
			continue

		var distance := _grid_distance(target, player_pos)
		if distance > best_distance:
			best_distance = distance
			best_delta = delta

	return best_delta

func _try_move_enemy(index: int, delta: Vector2i) -> void:
	if delta == DIR_NONE:
		return

	_face_enemy(index, delta)
	var enemy: Dictionary = enemies[index]
	var target: Vector2i = enemy["pos"] + delta
	if not _is_walkable_cell(target):
		_start_enemy_bump(index, delta)
		_play_sound("bump")
		return

	if _is_boss_at_cell(target):
		_start_enemy_bump(index, delta)
		if _register_collision_pair(_enemy_unit_id(index), "boss"):
			var enemy_pos: Vector2i = enemy["pos"]
			var enemy_facing: Vector2i = enemy["facing"]
			var enemy_damage := _collision_damage(enemy_pos, enemy_facing, target)
			var boss_damage := _boss_collision_damage(enemy_pos)
			_damage_enemy(index, enemy_damage)
			_damage_boss(boss_damage)
			_play_sound("hit")
			last_event = _collision_event_text("Enemy and boss both take damage", "enemy", enemy_damage, "boss", boss_damage)
		else:
			_play_sound("bump")
			last_event = "Enemy and boss already collided this turn"
		return

	if target == player_pos and player_alive:
		_start_enemy_bump(index, delta)
		if _register_collision_pair(_enemy_unit_id(index), "player"):
			var enemy_pos: Vector2i = enemy["pos"]
			var enemy_facing: Vector2i = enemy["facing"]
			var enemy_damage := _collision_damage(enemy_pos, enemy_facing, player_pos)
			var player_damage := _collision_damage(player_pos, player_facing, enemy_pos)
			_damage_enemy(index, enemy_damage)
			_damage_player(player_damage)
			_play_sound("hit")
			last_event = _collision_event_text("%s enemy and player both take damage" % _ai_name(enemy["ai"]), "%s enemy" % _ai_name(enemy["ai"]), enemy_damage, "player", player_damage)
		else:
			_play_sound("bump")
			last_event = "%s enemy and player already collided this turn" % _ai_name(enemy["ai"])
		return

	var other_enemy_index := _enemy_at(target)
	if other_enemy_index != -1:
		_start_enemy_bump(index, delta)
		if _register_collision_pair(_enemy_unit_id(index), _enemy_unit_id(other_enemy_index)):
			var other_enemy: Dictionary = enemies[other_enemy_index]
			var enemy_pos: Vector2i = enemy["pos"]
			var enemy_facing: Vector2i = enemy["facing"]
			var other_enemy_pos: Vector2i = other_enemy["pos"]
			var other_enemy_facing: Vector2i = other_enemy["facing"]
			var enemy_damage := _collision_damage(enemy_pos, enemy_facing, other_enemy_pos)
			var other_enemy_damage := _collision_damage(other_enemy_pos, other_enemy_facing, enemy_pos)
			_damage_enemy(index, enemy_damage)
			_damage_enemy(other_enemy_index, other_enemy_damage)
			_play_sound("hit")
			last_event = _collision_event_text("Two enemies collide and both take damage", "moving enemy", enemy_damage, "target enemy", other_enemy_damage)
		else:
			_play_sound("bump")
			last_event = "Those enemies already collided this turn"
		return

	enemy["pos"] = target
	enemies[index] = enemy

func _take_boss_turn() -> void:
	if not _is_boss_alive():
		return

	var state := int(boss["state"])
	if state == BossState.CHARGING:
		_release_boss_attack()
		return
	if state == BossState.STUNNED:
		boss["state"] = BossState.NORMAL
		last_event = "Boss is stunned"
		return

	if _has_cell(_boss_attack_area(boss["pos"], boss["facing"]), player_pos):
		_start_boss_charge()
		return

	var delta := _decide_boss_move()
	if delta == DIR_NONE:
		last_event = "Boss waits"
		return

	_try_move_boss(delta)

func _decide_boss_move() -> Vector2i:
	var best_delta := DIR_NONE
	var best_score := 100000

	for raw_delta in MOVE_ACTIONS:
		var delta: Vector2i = raw_delta
		var target_pos: Vector2i = boss["pos"] + delta
		if not _is_boss_footprint_walkable(target_pos):
			continue
		if _enemy_in_boss_footprint(target_pos) != -1:
			continue

		var distance := _boss_distance_to_player(target_pos)
		var score := distance
		if _has_cell(_boss_attack_area(target_pos, delta), player_pos):
			score -= 1000
		if score < best_score:
			best_score = score
			best_delta = delta

	return best_delta

func _try_move_boss(delta: Vector2i) -> void:
	boss["facing"] = delta
	var target_pos: Vector2i = boss["pos"] + delta
	if not _is_boss_footprint_walkable(target_pos):
		_start_boss_bump(delta)
		_play_sound("bump")
		last_event = "Boss bumps into a wall"
		return

	var enemy_index := _enemy_in_boss_footprint(target_pos)
	if enemy_index != -1:
		_start_boss_bump(delta)
		if _register_collision_pair("boss", _enemy_unit_id(enemy_index)):
			var enemy: Dictionary = enemies[enemy_index]
			var enemy_pos: Vector2i = enemy["pos"]
			var attacker_cell := enemy_pos - delta
			var boss_damage := _boss_collision_damage(enemy_pos)
			var enemy_damage := _collision_damage(enemy_pos, enemy["facing"], attacker_cell)
			_damage_boss(boss_damage)
			_damage_enemy(enemy_index, enemy_damage)
			_play_sound("hit")
			last_event = _collision_event_text("Boss and enemy both take damage", "boss", boss_damage, "enemy", enemy_damage)
		else:
			_play_sound("bump")
			last_event = "Boss and enemy already collided this turn"
		return

	if player_alive and _has_cell(_boss_footprint_at(target_pos), player_pos):
		_start_boss_bump(delta)
		if _register_collision_pair("boss", "player"):
			var attacker_cell := player_pos - delta
			var boss_damage := _boss_collision_damage(player_pos)
			var player_damage := _collision_damage(player_pos, player_facing, attacker_cell)
			_damage_boss(boss_damage)
			_damage_player(player_damage)
			_play_sound("hit")
			last_event = _collision_event_text("Boss and player both take damage", "boss", boss_damage, "player", player_damage)
		else:
			_play_sound("bump")
			last_event = "Boss and player already collided this turn"
		return

	boss["pos"] = target_pos
	last_event = "Boss moves"

func _start_boss_charge() -> void:
	boss["state"] = BossState.CHARGING
	boss["charge_area"] = _boss_attack_area(boss["pos"], boss["facing"])
	last_event = "Boss starts charging"

func _release_boss_attack() -> void:
	var area: Array = boss["charge_area"]
	var hit_anything := false

	if player_alive and _has_cell(area, player_pos):
		_damage_player(DAMAGE_PER_COLLISION)
		hit_anything = true

	for index in range(enemies.size()):
		if enemies[index]["alive"] and _has_cell(area, enemies[index]["pos"]):
			_damage_enemy(index, DAMAGE_PER_COLLISION)
			hit_anything = true

	boss["state"] = BossState.STUNNED
	boss["charge_area"] = []
	if hit_anything:
		_play_sound("hit")
		last_event = "Boss releases the charged attack"
	else:
		_play_sound("bump")
		last_event = "Boss attack misses"

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

func _damage_boss(amount: int) -> void:
	if not _is_boss_alive():
		return

	boss["hp"] = maxi(0, int(boss["hp"]) - amount)
	boss["hit_timer"] = HIT_DURATION
	if int(boss["hp"]) == 0:
		boss["alive"] = false
		boss["state"] = BossState.NORMAL
		boss["charge_area"] = []
		boss["death_timer"] = DEATH_DURATION
		last_event = "Boss defeated"
		_play_sound("death")

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

func _start_boss_bump(direction: Vector2i) -> void:
	boss["bump_dir"] = direction
	boss["bump_timer"] = BUMP_DURATION

func _enemy_at(cell: Vector2i) -> int:
	for index in range(enemies.size()):
		if enemies[index]["alive"] and enemies[index]["pos"] == cell:
			return index
	return -1

func _enemy_in_boss_footprint(boss_pos: Vector2i) -> int:
	var footprint := _boss_footprint_at(boss_pos)
	for index in range(enemies.size()):
		if enemies[index]["alive"] and _has_cell(footprint, enemies[index]["pos"]):
			return index
	return -1

func _enemy_unit_id(index: int) -> String:
	if index < 0 or index >= enemies.size():
		return "missing"
	return str(enemies[index]["id"])

func _register_collision_pair(unit_a: String, unit_b: String) -> bool:
	var pair := [unit_a, unit_b]
	pair.sort()
	var key := "%s|%s" % [pair[0], pair[1]]
	if turn_collision_pairs.has(key):
		return false

	turn_collision_pairs[key] = true
	return true

func _collision_damage(victim_pos: Vector2i, victim_facing: Vector2i, attacker_pos: Vector2i) -> int:
	var amount := DAMAGE_PER_COLLISION
	if _is_hit_from_behind(victim_pos, victim_facing, attacker_pos):
		amount += BACK_COLLISION_BONUS_DAMAGE
	return amount

func _boss_collision_damage(attacker_pos: Vector2i) -> int:
	var amount := DAMAGE_PER_COLLISION
	if _is_boss_hit_from_behind(attacker_pos):
		amount += BACK_COLLISION_BONUS_DAMAGE
	return amount

func _is_hit_from_behind(victim_pos: Vector2i, victim_facing: Vector2i, attacker_pos: Vector2i) -> bool:
	return attacker_pos == victim_pos + _back_direction(victim_facing)

func _is_boss_hit_from_behind(attacker_pos: Vector2i) -> bool:
	if not _has_boss():
		return false
	return _has_cell(_boss_back_edge_cells(boss["pos"], boss["facing"]), attacker_pos)

func _boss_back_edge_cells(boss_pos: Vector2i, boss_facing: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var footprint := _boss_footprint_at(boss_pos)
	var back_direction := _back_direction(boss_facing)
	for body_cell in footprint:
		var back_cell := body_cell + back_direction
		if not _has_cell(footprint, back_cell) and not _has_cell(cells, back_cell):
			cells.append(back_cell)
	return cells

func _collision_event_text(base_text: String, unit_a_name: String, unit_a_damage: int, unit_b_name: String, unit_b_damage: int) -> String:
	var back_hits := PackedStringArray()
	if unit_a_damage > DAMAGE_PER_COLLISION:
		back_hits.append("%s hit from behind" % unit_a_name)
	if unit_b_damage > DAMAGE_PER_COLLISION:
		back_hits.append("%s hit from behind" % unit_b_name)
	if back_hits.is_empty():
		return base_text
	return "%s (%s)" % [base_text, ", ".join(back_hits)]

func _is_walkable_cell(cell: Vector2i) -> bool:
	return _is_inside_map(cell) and not _is_wall(cell)

func _is_inside_map(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _map_width() and cell.y < _map_height()

func _is_wall(cell: Vector2i) -> bool:
	return _map_rows()[cell.y].substr(cell.x, 1) == "#"

func _map_width() -> int:
	return _map_rows()[0].length()

func _map_height() -> int:
	return _map_rows().size()

func _map_rows() -> Array:
	if current_map_id == MapId.BOSS:
		return BOSS_MAP_ROWS
	return NORMAL_MAP_ROWS

func _map_name() -> String:
	if current_map_id == MapId.BOSS:
		return "Boss Arena"
	return "Training Map"

func _grid_distance(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

func _boss_distance_to_player(boss_pos: Vector2i) -> int:
	var best_distance := 100000
	for cell in _boss_footprint_at(boss_pos):
		best_distance = mini(best_distance, _grid_distance(cell, player_pos))
	return best_distance

func _living_enemy_count() -> int:
	var count := 0
	for enemy in enemies:
		if enemy["alive"]:
			count += 1
	return count

func _enemy_max_hp(ai_type: int) -> int:
	match ai_type:
		AIType.IDLE:
			return 1
		AIType.RANDOM:
			return 1
		AIType.FLEE:
			return 2
		AIType.CHASE:
			return 3
	return 1

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

func _has_boss() -> bool:
	return not boss.is_empty()

func _is_boss_alive() -> bool:
	return _has_boss() and bool(boss["alive"])

func _is_boss_at_cell(cell: Vector2i) -> bool:
	return _is_boss_alive() and _has_cell(_boss_footprint_at(boss["pos"]), cell)

func _boss_footprint_at(boss_pos: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(BOSS_SIZE.y):
		for x in range(BOSS_SIZE.x):
			cells.append(boss_pos + Vector2i(x, y))
	return cells

func _is_boss_footprint_walkable(boss_pos: Vector2i) -> bool:
	for cell in _boss_footprint_at(boss_pos):
		if not _is_walkable_cell(cell):
			return false
	return true

func _boss_attack_area(boss_pos: Vector2i, boss_facing: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if boss_facing == DIR_RIGHT:
		for x in range(2):
			for y in range(2):
				cells.append(boss_pos + Vector2i(BOSS_SIZE.x + x, y))
	elif boss_facing == DIR_LEFT:
		for x in range(2):
			for y in range(2):
				cells.append(boss_pos + Vector2i(-1 - x, y))
	elif boss_facing == DIR_DOWN:
		for y in range(2):
			for x in range(2):
				cells.append(boss_pos + Vector2i(x, BOSS_SIZE.y + y))
	elif boss_facing == DIR_UP:
		for y in range(2):
			for x in range(2):
				cells.append(boss_pos + Vector2i(x, -1 - y))
	return cells

func _has_cell(cells: Array, target: Vector2i) -> bool:
	for cell in cells:
		if cell == target:
			return true
	return false

func _update_hud() -> void:
	if current_map_id == MapId.BOSS:
		var boss_status := "Boss defeated"
		if _is_boss_alive():
			boss_status = "Boss HP: %d/%d (%s)" % [boss["hp"], boss["max_hp"], _boss_state_name()]
		status_label.text = "Map: %s\nTurn %d\n%s\n%s" % [
			_map_name(),
			turn_count,
			boss_status,
			last_event,
		]
	else:
		status_label.text = "Map: %s\nTurn %d\nEnemies: %d\n%s" % [
			_map_name(),
			turn_count,
			_living_enemy_count(),
			last_event,
		]

func _boss_state_name() -> String:
	if not _has_boss():
		return "none"
	match int(boss["state"]):
		BossState.NORMAL:
			return "normal"
		BossState.CHARGING:
			return "charging"
		BossState.STUNNED:
			return "stunned"
	return "unknown"

func _draw() -> void:
	_draw_player_hp_hearts()
	_draw_map()
	_draw_boss_charge_area()
	_draw_units()

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
				var floor_color := Color(0.20, 0.22, 0.24)
				var inset_color := Color(0.25, 0.27, 0.29)
				if current_map_id == MapId.BOSS:
					floor_color = Color(0.18, 0.17, 0.20)
					inset_color = Color(0.25, 0.22, 0.27)
				draw_rect(rect, floor_color)
				draw_rect(rect.grow(-10), inset_color)

			draw_rect(rect, Color(0.07, 0.08, 0.09), false, 2.0)

func _draw_boss_charge_area() -> void:
	if not _is_boss_alive():
		return
	if int(boss["state"]) != BossState.CHARGING:
		return

	var area: Array = boss["charge_area"]
	for cell in area:
		if not _is_inside_map(cell):
			continue
		var rect := _cell_rect(cell).grow(-3)
		draw_rect(rect, Color(0.92, 0.16, 0.10, 0.32))
		draw_rect(rect, Color(1.0, 0.42, 0.18, 0.90), false, 3.0)

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

	if _has_boss() and (bool(boss["alive"]) or float(boss["death_timer"]) > 0.0):
		_draw_boss()

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

func _draw_boss() -> void:
	var top_left: Vector2i = boss["pos"]
	var offset := _boss_bump_offset()
	var alpha := 1.0
	var unit_scale := 1.0
	if not bool(boss["alive"]):
		alpha = float(boss["death_timer"]) / DEATH_DURATION
		unit_scale = maxf(0.15, alpha)

	var base_rect := Rect2(_cell_rect(top_left).position, Vector2(TILE_SIZE * BOSS_SIZE.x, TILE_SIZE * BOSS_SIZE.y)).grow(-5)
	var scaled_size := base_rect.size * unit_scale
	var rect := Rect2(base_rect.position + (base_rect.size - scaled_size) * 0.5 + offset, scaled_size)
	var body_color := Color(0.55, 0.16, 0.20, alpha)
	if int(boss["state"]) == BossState.CHARGING:
		body_color = Color(0.90, 0.34, 0.13, alpha)
	elif int(boss["state"]) == BossState.STUNNED:
		body_color = Color(0.34, 0.34, 0.50, alpha)
	if float(boss["hit_timer"]) > 0.0:
		body_color = body_color.lerp(Color.WHITE, 0.65)

	var outline := Color(0.05, 0.02, 0.03, alpha)
	var armor := Color(0.18, 0.10, 0.14, alpha)
	var horn := Color(0.88, 0.76, 0.44, alpha)
	var eye := Color(1.0, 0.86, 0.36, alpha)
	draw_rect(rect.grow(-4), outline)
	draw_rect(rect.grow(-10), body_color)
	draw_rect(Rect2(rect.position + Vector2(14, 58) * unit_scale, Vector2(68, 20) * unit_scale), armor)
	_draw_boss_face_marks(rect, boss["facing"], eye, horn, outline, unit_scale)
	if bool(boss["alive"]):
		_draw_boss_hp(rect)

func _draw_boss_face_marks(rect: Rect2, facing: Vector2i, eye: Color, horn: Color, outline: Color, unit_scale: float) -> void:
	if facing == DIR_LEFT:
		draw_rect(Rect2(rect.position + Vector2(9, 18) * unit_scale, Vector2(13, 10) * unit_scale), horn)
		draw_rect(Rect2(rect.position + Vector2(9, 64) * unit_scale, Vector2(13, 10) * unit_scale), horn)
		draw_rect(Rect2(rect.position + Vector2(27, 35) * unit_scale, Vector2(8, 8) * unit_scale), eye)
	elif facing == DIR_RIGHT:
		draw_rect(Rect2(rect.position + Vector2(74, 18) * unit_scale, Vector2(13, 10) * unit_scale), horn)
		draw_rect(Rect2(rect.position + Vector2(74, 64) * unit_scale, Vector2(13, 10) * unit_scale), horn)
		draw_rect(Rect2(rect.position + Vector2(61, 35) * unit_scale, Vector2(8, 8) * unit_scale), eye)
	elif facing == DIR_UP:
		draw_rect(Rect2(rect.position + Vector2(18, 9) * unit_scale, Vector2(10, 13) * unit_scale), horn)
		draw_rect(Rect2(rect.position + Vector2(64, 9) * unit_scale, Vector2(10, 13) * unit_scale), horn)
		draw_rect(Rect2(rect.position + Vector2(43, 27) * unit_scale, Vector2(8, 8) * unit_scale), eye)
	elif facing == DIR_DOWN:
		draw_rect(Rect2(rect.position + Vector2(18, 74) * unit_scale, Vector2(10, 13) * unit_scale), horn)
		draw_rect(Rect2(rect.position + Vector2(64, 74) * unit_scale, Vector2(10, 13) * unit_scale), horn)
		draw_rect(Rect2(rect.position + Vector2(43, 61) * unit_scale, Vector2(8, 8) * unit_scale), eye)
	draw_rect(rect.grow(-4), outline, false, 3.0 * unit_scale)

func _draw_boss_hp(boss_rect: Rect2) -> void:
	var block_size := 2.0
	var heart_width := _heart_width(block_size)
	var start := boss_rect.position + Vector2((boss_rect.size.x - (heart_width * BOSS_MAX_HP + 6.0 * (BOSS_MAX_HP - 1))) * 0.5, -18)
	for index in range(BOSS_MAX_HP):
		var heart_pos := start + Vector2(index * (heart_width + 6.0), 0)
		_draw_heart_icon(heart_pos, index < int(boss["hp"]), block_size)

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

func _player_bump_offset() -> Vector2:
	return _bump_offset(player_bump_timer, player_bump_dir)

func _enemy_bump_offset(enemy: Dictionary) -> Vector2:
	var timer := float(enemy["bump_timer"])
	var direction: Vector2i = enemy["bump_dir"]
	return _bump_offset(timer, direction)

func _boss_bump_offset() -> Vector2:
	var timer := float(boss["bump_timer"])
	var direction: Vector2i = boss["bump_dir"]
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
