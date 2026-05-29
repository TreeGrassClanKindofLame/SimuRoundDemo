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
const PLAYER_MAX_HP := 5
const DAMAGE_PER_COLLISION := 1
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
var rng := RandomNumberGenerator.new()
var astar_grid := AStarGrid2D.new()
var sound_players: Dictionary = {}
var turn_collision_pairs: Dictionary = {}

@onready var status_label: Label = $HUD/Status

func _ready() -> void:
	rng.randomize()
	_setup_audio()
	_setup_astar_grid()
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
	last_event = "Ready"
	enemies = [
		_create_enemy(Vector2i(6, 1), AIType.IDLE),
		_create_enemy(Vector2i(12, 1), AIType.RANDOM),
		_create_enemy(Vector2i(12, 7), AIType.CHASE),
		_create_enemy(Vector2i(2, 7), AIType.FLEE),
		_create_enemy(Vector2i(8, 5), AIType.RANDOM),
	]
	if play_reset_sound:
		_play_sound("reset")
	_update_hud()
	queue_redraw()

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

func _play_turn(player_delta: Vector2i) -> void:
	if not player_alive or reset_timer > 0.0:
		return

	turn_collision_pairs.clear()
	_try_move_player(player_delta)
	if player_alive:
		_take_enemy_turns()

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

	var enemy_index := _enemy_at(target)
	if enemy_index != -1:
		_start_player_bump(delta)
		if _register_collision_pair("player", _enemy_unit_id(enemy_index)):
			_damage_player(DAMAGE_PER_COLLISION)
			_damage_enemy(enemy_index, DAMAGE_PER_COLLISION)
			_play_sound("hit")
			last_event = "Player and enemy both take damage"
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

	if target == player_pos and player_alive:
		_start_enemy_bump(index, delta)
		if _register_collision_pair(_enemy_unit_id(index), "player"):
			_damage_enemy(index, DAMAGE_PER_COLLISION)
			_damage_player(DAMAGE_PER_COLLISION)
			_play_sound("hit")
			last_event = "%s enemy and player both take damage" % _ai_name(enemy["ai"])
		else:
			_play_sound("bump")
			last_event = "%s enemy and player already collided this turn" % _ai_name(enemy["ai"])
		return

	var other_enemy_index := _enemy_at(target)
	if other_enemy_index != -1:
		_start_enemy_bump(index, delta)
		if _register_collision_pair(_enemy_unit_id(index), _enemy_unit_id(other_enemy_index)):
			_damage_enemy(index, DAMAGE_PER_COLLISION)
			_damage_enemy(other_enemy_index, DAMAGE_PER_COLLISION)
			_play_sound("hit")
			last_event = "Two enemies collide and both take damage"
		else:
			_play_sound("bump")
			last_event = "Those enemies already collided this turn"
		return

	enemy["pos"] = target
	enemies[index] = enemy

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

func _enemy_at(cell: Vector2i) -> int:
	for index in range(enemies.size()):
		if enemies[index]["alive"] and enemies[index]["pos"] == cell:
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

func _update_hud() -> void:
	status_label.text = "Turn %d\nPlayer HP: %d/%d %s\nEnemies: %d\n%s" % [
		turn_count,
		player_hp,
		PLAYER_MAX_HP,
		_player_hp_bar(),
		_living_enemy_count(),
		last_event,
	]

func _player_hp_bar() -> String:
	var filled := ""
	for index in range(PLAYER_MAX_HP):
		filled += "#" if index < player_hp else "-"
	return "[%s]" % filled

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
