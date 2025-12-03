extends Node3D
# Main.gd - Main game scene

@export_group("Grid Settings")
@export var grid_width: int = 30
@export var grid_height: int = 30
@export var cell_size: float = 2.0

@export_group("Terrain Settings")
@export var use_random_seed: bool = true
@export var terrain_seed: int = 0
@export var base_tile_height: float = 0.3
@export var obstacle_height_min: float = 2.0
@export var obstacle_height_max: float = 4.0
@export var obstacle_cluster_count: int = 8
@export var obstacle_cluster_size: int = 5

@export_group("Visual Settings")
@export var base_brightness: float = 0.15
@export var brightness_variation: float = 0.05
@export var metallic: float = 0.3
@export var roughness: float = 0.7

@export_group("Tower Scenes")
@export var tower_0_scene: PackedScene
@export var tower_1_scene: PackedScene
@export var tower_2_scene: PackedScene
@export var tower_3_scene: PackedScene
@export var tower_4_scene: PackedScene
@export var tower_5_scene: PackedScene
@export var tower_6_scene: PackedScene

@export_group("Enemy Scenes")
@export var creep_1_scene: PackedScene
@export var creep_2_scene: PackedScene
@export var creep_3_scene: PackedScene
@export var creep_4_scene: PackedScene
@export var creep_5_scene: PackedScene

@export_group("Special Scenes")
@export var monster_mouth_scene: PackedScene

@export_group("Enemy Spawning")
@export var wave_duration: float = 30.0
@export var wave_break_time: float = 5.0

var grid: Node3D
var path_system: Node3D
var spawn_timer: Timer
var fps_label: Label

# Tower selection
var selected_tower_type: int = -1
var tower_scenes: Array = []
var tower_names: Array = ["Wall", "Basic", "Rapid Fire", "Missles", "Anti-Air", "Ice", "Pulse"]
# Wave system
var current_wave: int = 0
var enemies_in_wave: int = 0
var enemies_spawned: int = 0
var wave_active: bool = false
var wave_label: Label
var between_waves: bool = false
var next_wave_countdown: int = 0
var countdown_timer: Timer
var last_hovered_tower: Node3D = null
# Economy and score
#var player_gold: int = 100
var player_score: int = 0
var player_kills: int = 0  
var gold_label: Label
var score_label: Label
# High scores
var high_score_wave: int = 0
var high_score_kills: int = 0
var high_score_points: int = 0
# Player health
@export_group("Player Stuff")
@export var player_health: int = 20
@export var max_player_health: int = 20

@export var player_gold: int = 100

var health_label: Label
var goal_bunker: Node3D = null
var goal_health_bar_bg: MeshInstance3D = null
var goal_health_bar_fg: MeshInstance3D = null

# Game state
var game_started: bool = false
var game_paused: bool = false 
var game_speed: float = 1.0 
var start_button: Button = null
var monster_mouth: Node3D = null
var wave_label_3d: Label3D = null
var tower_stats_label: Label3D = null
var selected_tower: Node3D = null
var upgrade_card: PanelContainer = null
var sell_card: PanelContainer = null

var goal_gold_text: MeshInstance3D = null
var goal_score_text: MeshInstance3D = null
var mouth_wave_text: MeshInstance3D = null
var mouth_spawn_text: MeshInstance3D = null

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS 
	if not use_random_seed:
		seed(terrain_seed)
	

	
	load_high_scores() 
	 
	tower_scenes = [
		tower_0_scene,
		tower_1_scene,
		tower_2_scene,
		tower_3_scene,
		tower_4_scene,
		tower_5_scene,
		tower_6_scene
	]
	
	# Create the grid system
	var grid_script = preload("res://grid.gd")
	grid = Node3D.new()
	grid.set_script(grid_script)
	grid.grid_width = grid_width
	grid.grid_height = grid_height
	grid.cell_size = cell_size
	
	grid.base_tile_height = base_tile_height
	grid.obstacle_height_min = obstacle_height_min
	grid.obstacle_height_max = obstacle_height_max
	grid.obstacle_cluster_count = obstacle_cluster_count
	grid.obstacle_cluster_size = obstacle_cluster_size
	grid.base_brightness = base_brightness
	grid.brightness_variation = brightness_variation
	grid.metallic = metallic
	grid.roughness = roughness
	
	add_child(grid)
	
	# Create path system
	var path_script = preload("res://PathSystem.gd")
	path_system = Node3D.new()
	path_system.set_script(path_script)
	add_child(path_system)
	
	await get_tree().process_frame
	grid.path_system = path_system
	
	var start_pos = Vector2i(0, grid.grid_height / 2)
	#var end_pos = Vector2i(grid.grid_width - 1, grid.grid_height / 2)
	# Convert world position to grid position
	var target_world_pos = Vector3(27, 0, 1)
	var end_pos = grid.world_to_grid(target_world_pos)
	
	
	path_system.initialize(grid, start_pos, end_pos)
	
	setup_spawner()
	setup_fps_counter()
	setup_tower_ui()
	setup_wave_ui()
	setup_economy_ui()
	setup_health_ui()
	create_goal_bunker()
	create_monster_mouth()
	add_lighting()
	add_dynamic_lights()  
	create_3d_stat_displays() 
	create_speed_controls()
	# Create start button instead of auto-starting
	create_start_button()

func setup_fps_counter():
	fps_label = Label.new()
	fps_label.position = Vector2(10, 10)
	fps_label.add_theme_font_size_override("font_size", 24)
	fps_label.add_theme_color_override("font_color", Color(1, 1, 0))
	add_child(fps_label)
		# Add seed label below FPS
	var seed_label = Label.new()
	seed_label.name = "SeedLabel"
	seed_label.position = Vector2(10, 40)
	seed_label.add_theme_font_size_override("font_size", 20)
	seed_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	
	if use_random_seed:
		seed_label.text = "Seed: " + str(randi())
	else:
		seed_label.text = "Seed: " + str(terrain_seed)
	
	add_child(seed_label)

func setup_tower_ui():
	# Remove old label-based UI
	var old_label = get_node_or_null("TowerLabel")
	if old_label:
		old_label.queue_free()
	
	# Create horizontal container for buttons (no panel background)
	var hbox = HBoxContainer.new()
	hbox.name = "TowerButtonContainer"
	hbox.add_theme_constant_override("separation", 10)
	
	# Position at bottom left
	hbox.position = Vector2(20, 0)
	hbox.anchor_left = 0.0
	hbox.anchor_right = 0.0
	hbox.anchor_top = 1.0
	hbox.anchor_bottom = 1.0
	hbox.offset_top = -130
	hbox.grow_vertical = Control.GROW_DIRECTION_BEGIN
	
	# Create 6 tower buttons
	for i in range(7):
		var tower_button = create_tower_button(i)
		hbox.add_child(tower_button)
	
	add_child(hbox)

func setup_wave_ui():
	wave_label = Label.new()
	wave_label.name = "WaveLabel"
	wave_label.position = Vector2(10, 80)
	wave_label.add_theme_font_size_override("font_size", 24)
	wave_label.add_theme_color_override("font_color", Color(1, 1, 0))
	wave_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	wave_label.custom_minimum_size = Vector2(600, 100)
	wave_label.text = "Wave: 0 | Enemies: 0/0"
	add_child(wave_label)

func setup_economy_ui():
	gold_label = Label.new()
	gold_label.name = "GoldLabel"
	gold_label.position = Vector2(10, 160)
	gold_label.add_theme_font_size_override("font_size", 28)
	gold_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
	gold_label.text = "Gold: " + str(player_gold)
	add_child(gold_label)
	
	score_label = Label.new()
	score_label.name = "ScoreLabel"
	score_label.position = Vector2(10, 200)
	score_label.add_theme_font_size_override("font_size", 24)
	score_label.add_theme_color_override("font_color", Color(0.5, 1, 0.5))
	score_label.text = "Score: " + str(player_score)
	add_child(score_label)
	# Add kills label
	var kills_label = Label.new()
	kills_label.name = "KillsLabel"
	kills_label.position = Vector2(10, 280)
	kills_label.add_theme_font_size_override("font_size", 24)
	kills_label.add_theme_color_override("font_color", Color(1, 0.5, 0.5))
	kills_label.text = "Kills: " + str(player_kills)
	add_child(kills_label)

func setup_health_ui():
	health_label = Label.new()
	health_label.name = "HealthLabel"
	health_label.position = Vector2(10, 240)
	health_label.add_theme_font_size_override("font_size", 28)
	health_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	health_label.text = "Health: " + str(player_health) + "/" + str(max_player_health)
	add_child(health_label)

func _process(_delta):
	if fps_label:
		fps_label.text = "FPS: " + str(Engine.get_frames_per_second())
	
	# Update tower buttons
	update_tower_buttons()
	
	
	update_tower_selection()
	
	# Update 3D wave label
	update_wave_label_3d()
		# Update 3D stat displays
	if goal_gold_text:
		update_3d_text(goal_gold_text, "Gold: " + str(player_gold))
	if goal_score_text:
		update_3d_text(goal_score_text, "Score: " + str(player_score))
	if mouth_wave_text:
		update_3d_text(mouth_wave_text, "Wave: " + str(current_wave))
	if mouth_spawn_text:
		var enemies_remaining = get_tree().get_nodes_in_group("enemies").size()
		update_3d_text(mouth_spawn_text, "Spawned: " + str(enemies_spawned) + "/" + str(enemies_in_wave) + " | Active: " + str(enemies_remaining))
	
	if wave_label:
		var enemies_remaining = get_tree().get_nodes_in_group("enemies").size()
		var wave_text = "Wave: " + str(current_wave) + " | Spawned: " + str(enemies_spawned) + "/" + str(enemies_in_wave) + " | Active: " + str(enemies_remaining)
		wave_text += "\nNext wave in: " + str(next_wave_countdown) + "s | " + get_next_wave_preview()
		wave_label.text = wave_text
	
	if gold_label:
		gold_label.text = "Gold: " + str(player_gold)
	if score_label:
		score_label.text = "Score: " + str(player_score)
	if health_label:
		health_label.text = "Health: " + str(player_health) + "/" + str(max_player_health)
		# Update kills label
	var kills_label = get_node_or_null("KillsLabel")
	if kills_label:
		kills_label.text = "Kills: " + str(player_kills)
	update_goal_health_bar()

func setup_spawner():
	spawn_timer = Timer.new()
	spawn_timer.timeout.connect(spawn_enemy)
	spawn_timer.process_mode = Node.PROCESS_MODE_PAUSABLE 
	add_child(spawn_timer)
	
	countdown_timer = Timer.new()
	countdown_timer.wait_time = 1.0
	countdown_timer.timeout.connect(_on_countdown_tick)
	countdown_timer.process_mode = Node.PROCESS_MODE_PAUSABLE 
	add_child(countdown_timer)

func start_next_wave():
	if not game_started:
		return
	
	current_wave += 1
	enemies_spawned = 0
	wave_active = true
	between_waves = false
	
	enemies_in_wave = calculate_wave_size()
	var spawn_interval = wave_duration / enemies_in_wave
	spawn_timer.wait_time = spawn_interval
	
	next_wave_countdown = int(wave_duration + wave_break_time)
	countdown_timer.start()
	
	#print("Starting Wave ", current_wave, " with ", enemies_in_wave, " enemies")
		# Show wave notification
	show_wave_notification(current_wave)
	spawn_timer.start()

func _on_countdown_tick():
	next_wave_countdown -= 1
	if next_wave_countdown < 0:
		next_wave_countdown = 0

func calculate_wave_size() -> int:
	return 5 + (current_wave * 3)

func spawn_enemy():
	if not wave_active or enemies_spawned >= enemies_in_wave:
		spawn_timer.stop()
		#print("Wave spawn complete. Starting break before next wave...")
		wave_active = false
		between_waves = true
		await get_tree().create_timer(wave_break_time).timeout
		start_next_wave()
		return
	
	var path = path_system.get_enemy_path()
	if path.size() == 0:
		#print("Main: No valid path for enemy!")
		return
	
	var enemy_scene = select_enemy_for_wave()
	if not enemy_scene:
		#print("Main: No enemy scene available!")
		return
	
	var enemy = enemy_scene.instantiate()
	enemy.process_mode = Node.PROCESS_MODE_PAUSABLE
	
	if path.size() > 0:
		enemy.position = path[0]
		enemy.position.y = 0.5
	
	add_child(enemy)
	
	await get_tree().process_frame
	enemy.grid = grid
	enemy.set_path(path, path_system)
	
	if enemy.has_signal("enemy_died"):
		enemy.enemy_died.connect(_on_enemy_died)
	
	if enemy.has_signal("enemy_reached_goal"):
		enemy.enemy_reached_goal.connect(_on_enemy_reached_goal)
	
	enemies_spawned += 1
	#print("Main: Spawned enemy ", enemies_spawned, "/", enemies_in_wave)

func select_enemy_for_wave() -> PackedScene:
	if current_wave <= 3:
		return creep_1_scene
	
	if current_wave <= 6:
		if randf() < 0.7:
			return creep_1_scene
		else:
			return creep_2_scene if creep_2_scene else creep_1_scene
	
	if current_wave <= 10:
		var rand = randf()
		if rand < 0.5:
			return creep_1_scene
		elif rand < 0.8:
			return creep_2_scene if creep_2_scene else creep_1_scene
		else:
			return creep_3_scene if creep_3_scene else creep_1_scene
	
	var rand = randf()
	if rand < 0.3:
		return creep_1_scene
	elif rand < 0.5:
		return creep_2_scene if creep_2_scene else creep_1_scene
	elif rand < 0.7:
		return creep_3_scene if creep_3_scene else creep_1_scene
	elif rand < 0.9:
		return creep_4_scene if creep_4_scene else creep_1_scene
	else:
		return creep_5_scene if creep_5_scene else creep_1_scene

func get_next_wave_preview() -> String:
	var next_wave = current_wave + 1
	
	if next_wave <= 3:
		return "Basic"
	elif next_wave <= 6:
		return "Basic + Fast"
	elif next_wave <= 10:
		return "Basic, Fast + Tank"
	else:
		return "All Types (Flying + Boss!)"
func add_dynamic_lights():
	# Light at goal bunker
	if goal_bunker:
		var bunker_light = OmniLight3D.new()
		bunker_light.light_energy = 2.0
		bunker_light.light_color = Color(0.3, 0.8, 1.0)
		bunker_light.omni_range = 15.0
		bunker_light.position = Vector3(0, 5, 0)
		bunker_light.shadow_enabled = true
		goal_bunker.add_child(bunker_light)
	
	# Light at monster mouth
	if monster_mouth:
		var mouth_light = OmniLight3D.new()
		mouth_light.light_energy = 2.5
		mouth_light.light_color = Color(1.0, 0.2, 0.2)
		mouth_light.omni_range = 12.0
		mouth_light.position = Vector3(0, 4, 0)
		mouth_light.shadow_enabled = false
		monster_mouth.add_child(mouth_light)
		
		
func add_lighting():
	# Key light (main light source)
	var key_light = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-50, -45, 0)
	key_light.light_energy = 0.9  # Reduced from 1.5
	key_light.light_color = Color(1.0, 0.95, 0.85)
	key_light.shadow_enabled = true
	key_light.shadow_opacity = 0.7
	key_light.shadow_blur = 2.0
	add_child(key_light)
	
	# Fill light
	var fill_light = DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-25, 135, 0)
	fill_light.light_energy = 0.3  # Reduced from 0.6
	fill_light.light_color = Color(0.6, 0.7, 1.0)
	fill_light.shadow_enabled = false
	add_child(fill_light)
	
	# Rim light (back light for edge definition)
	var rim_light = DirectionalLight3D.new()
	rim_light.rotation_degrees = Vector3(-20, 180, 0)
	rim_light.light_energy = 0.4  # Reduced from 0.8
	rim_light.light_color = Color(0.8, 0.9, 1.0)
	rim_light.shadow_enabled = false
	add_child(rim_light)
	
	# Environment with glow
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.1, 0.1, 0.15)  # Darker ambient
	env.ambient_light_energy = 0.3  # Reduced from 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	
	# Enable glow for emissive materials
	env.glow_enabled = true
	env.glow_intensity = 0.5  # Reduced from 0.8
	env.glow_strength = 1.0  # Reduced from 1.2
	env.glow_bloom = 0.2  # Reduced from 0.3
	
	# SSAO for depth
	env.ssao_enabled = true
	env.ssao_radius = 2.5
	env.ssao_intensity = 1.5
	
	
	
	var world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)		
#func add_lighting():
	## Main directional light (sun)
	#var main_light = DirectionalLight3D.new()
	#main_light.rotation_degrees = Vector3(-45, -30, 0)
	#main_light.light_energy = 1.2
	#main_light.light_color = Color(1.0, 0.95, 0.9)  # Warm sunlight
	#main_light.shadow_enabled = true
	#main_light.shadow_opacity = 0.6
	#main_light.shadow_blur = 1.5
	#add_child(main_light)
	#
	## Fill light (softer, opposite direction)
	#var fill_light = DirectionalLight3D.new()
	#fill_light.rotation_degrees = Vector3(-30, 150, 0)
	#fill_light.light_energy = 0.4
	#fill_light.light_color = Color(0.7, 0.8, 1.0)  # Cool blue fill
	#fill_light.shadow_enabled = false
	#add_child(fill_light)
	#
	## Environment
	#var env = Environment.new()
	#env.background_mode = Environment.BG_COLOR
	#env.background_color = Color(0.05, 0.05, 0.08)
	#env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	#env.ambient_light_color = Color(0.2, 0.2, 0.25)
	#env.ambient_light_energy = 0.5
	#env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	#env.ssao_enabled = true
	#env.ssao_radius = 2.0
	#env.ssao_intensity = 1.5
	#
	#var world_env = WorldEnvironment.new()
	#world_env.environment = env
	#add_child(world_env)

func _input(event):
	if event is InputEventKey and event.pressed:
		# Handle 0 key separately for wall tower
		if event.keycode == KEY_0:
			selected_tower_type = 0
			var button = get_node_or_null("TowerButtonContainer/TowerButton0")
			if button:
				button.grab_focus()
		# Handle 1-6 for other towers
		elif event.keycode >= KEY_1 and event.keycode <= KEY_6:
			selected_tower_type = event.keycode - KEY_0
			var button = get_node_or_null("TowerButtonContainer/TowerButton" + str(selected_tower_type))
			if button:
				button.grab_focus()
		elif event.keycode == KEY_ESCAPE and event.pressed:
			# Priority: 1. Close pause menu, 2. Close tower cards, 3. Open pause menu
			close_tower_cards()
			if game_paused:
				hide_pause_menu()
			elif selected_tower:  # Cards are showing
				close_tower_cards()
			elif game_started:  # Game is running, no cards showing
				show_pause_menu()
				
			# If game hasn't started, ESC does nothing
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Check if mouse is over UI before placing tower
			var mouse_pos = get_viewport().get_mouse_position()
			
			# Check if clicking on tower buttons
			var clicking_ui = false
			for i in range(1, 7):
				var button = get_node_or_null("TowerButtonContainer/TowerButton" + str(i))
				if button and button.get_global_rect().has_point(mouse_pos):
					clicking_ui = true
					break
			
			if not clicking_ui:
				# Check if clicking on upgrade/sell cards
				if not try_click_tower_card():
					# Try to select a tower or place a new one
					if not try_select_tower():
						place_tower()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# Check if Shift is held for quick selling
			if Input.is_key_pressed(KEY_SHIFT):
				try_sell_tower()
			else:
				# Close tower cards or cancel tower selection
				if selected_tower:
					close_tower_cards()
				else:
					cancel_tower_selection()

func get_selected_tower_scene() -> PackedScene:
	if selected_tower_type < 0 or selected_tower_type > 6:  # Changed from 1-6 to 0-6
		return null
	return tower_scenes[selected_tower_type]  #

func place_tower():
	if selected_tower_type < 0:  # Changed from == 0
		return
	
	if selected_tower_type < 0 or selected_tower_type > 6:  # Changed range
		#print("Main: Invalid tower type selected")
		return
	
	var tower_scene = tower_scenes[selected_tower_type]
	if not tower_scene:
		#print("Main: Tower ", selected_tower_type, " scene not assigned!")
		return
	
	var temp_tower = tower_scene.instantiate()
	var tower_cost = temp_tower.get("tower_cost")
	if not tower_cost:
		tower_cost = 0
	
	if player_gold < tower_cost:
		#print("Main: Not enough gold! Need ", tower_cost, ", have ", player_gold)
		temp_tower.queue_free()
		return
	
	temp_tower.queue_free()
	
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return
	
	var mouse_pos = get_viewport().get_mouse_position()
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space_state.intersect_ray(query)
	
	if result:
		var grid_pos = grid.world_to_grid(result.position)
		
		if grid.is_valid_grid_position(grid_pos) and not grid.is_cell_occupied(grid_pos):
			var tower = tower_scene.instantiate()
			#tower.rotation_degrees.y = -90
			if grid.place_tower(grid_pos, tower):
				player_gold -= tower_cost
				#print("Main: Tower ", selected_tower_type, " placed for ", tower_cost, " gold. Remaining: ", player_gold)
			else:
				#print("Main: Tower placement failed - would block path")
				tower.queue_free()
		else:
			print("Main: Cannot place tower - cell occupied or invalid")

func cancel_tower_selection():
	selected_tower_type = -1
	#print("Main: Tower selection cancelled")
	
	if grid:
		grid.hide_tower_preview()
	if selected_tower and selected_tower.has_method("hide_range"):
		selected_tower.hide_range()
	selected_tower = null

func try_sell_tower() -> bool:
	# Raycast to find tower under mouse
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return false
	
	var mouse_pos = get_viewport().get_mouse_position()
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space_state.intersect_ray(query)
	
	if result:
		var grid_pos = grid.world_to_grid(result.position)
		
		if grid.is_valid_grid_position(grid_pos) and grid.is_cell_occupied(grid_pos):
			var tower = grid.grid_data[grid_pos.x][grid_pos.y]
			
			# Check if it's actually a tower (not an obstacle)
			if tower and tower is Node3D and tower.is_in_group("towers"):
				# Get tower cost and calculate refund (75%)
				var tower_cost = tower.get("tower_cost")
				var tower_position = tower.global_position
				
				if tower_cost:
					var refund = int(tower_cost * 0.75)
					player_gold += refund
					print("Tower sold for ", refund, " gold (75% of ", tower_cost, ")")
					
					# Show floating sold text
					create_sold_text(tower_position, refund)
				
				# Remove tower from grid
				grid.grid_data[grid_pos.x][grid_pos.y] = null
				tower.queue_free()
				
				# Recalculate path
				if path_system:
					path_system.calculate_path()
				
				return true
	
	return false

func create_upgrade_effect(position: Vector3):
	var upgrade_label = Label3D.new()
	upgrade_label.text = "UPGRADED!"
	upgrade_label.font_size = 64
	upgrade_label.pixel_size = 0.008
	upgrade_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	upgrade_label.no_depth_test = true
	upgrade_label.outline_size = 10
	upgrade_label.outline_modulate = Color(0, 0, 0, 1)
	upgrade_label.modulate = Color(0.3, 0.8, 1.0, 1)  # Cyan/blue color
	
	# Load custom font if available
	var font = load("res://models/HELVETICA73-EXTENDED.TTF")
	if font:
		upgrade_label.font = font
	
# Store position before adding to tree
	var label_pos = position + Vector3(0, 3.0, 0)
	add_child(upgrade_label)
	upgrade_label.global_position = label_pos 
	
	# Animate: float up and fade out
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(upgrade_label, "global_position", position + Vector3(0, 5.0, 0), 1.5)
	tween.tween_property(upgrade_label, "modulate:a", 0.0, 1.5)
	tween.finished.connect(func():
		if is_instance_valid(upgrade_label):
			upgrade_label.queue_free()
	)

func create_sold_text(position: Vector3, refund: int):
	var sold_label = Label3D.new()
	sold_label.text = "SOLD +" + str(refund) + "g"
	sold_label.font_size = 48
	sold_label.pixel_size = 0.008
	sold_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sold_label.no_depth_test = true
	sold_label.outline_size = 8
	sold_label.outline_modulate = Color(0, 0, 0, 1)
	sold_label.modulate = Color(1, 0.84, 0, 1)  # Gold color
	
	# Load custom font if available
	var font = load("res://models/HELVETICA73-EXTENDED.TTF")
	if font:
		sold_label.font = font
	
	# Position above where tower was
	sold_label.global_position = position + Vector3(0, 3.0, 0)
	add_child(sold_label)
	
	# Animate: float up and fade out
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(sold_label, "global_position", position + Vector3(0, 5.0, 0), 1.5)
	tween.tween_property(sold_label, "modulate:a", 0.0, 1.5)
	tween.finished.connect(func():
		if is_instance_valid(sold_label):
			sold_label.queue_free()
	)

func _on_enemy_died(enemy: Node3D):
	if enemy and is_instance_valid(enemy):
		var gold_reward = enemy.get("gold_reward")
		if gold_reward:
			player_gold += gold_reward
			player_score += gold_reward
			player_kills += 1
			#print("Enemy killed! +", gold_reward, " gold. Total: ", player_gold)

func _on_enemy_reached_goal(damage: int):
	player_health -= damage
	#print("Player took ", damage, " damage! Health: ", player_health, "/", max_player_health)
	
	if goal_bunker:
		flash_goal_bunker()
	
	if player_health <= 0:
		game_over()

func flash_goal_bunker():
	var bunker_mesh = goal_bunker.get_child(0)
	if bunker_mesh and bunker_mesh is MeshInstance3D:
		var flash_mat = StandardMaterial3D.new()
		flash_mat.albedo_color = Color(1.0, 0.2, 0.2)
		flash_mat.emission_enabled = true
		flash_mat.emission = Color(1.0, 0.2, 0.2)
		flash_mat.emission_energy_multiplier = 2.0
		bunker_mesh.set_surface_override_material(0, flash_mat)
		
		await get_tree().create_timer(0.2).timeout
		if bunker_mesh:
			var normal_mat = StandardMaterial3D.new()
			normal_mat.albedo_color = Color(0.2, 0.3, 0.4)
			normal_mat.metallic = 0.6
			normal_mat.roughness = 0.4
			bunker_mesh.set_surface_override_material(0, normal_mat)
#
#func game_over():
	#print("GAME OVER!")
	#player_health = 0
	#
	#spawn_timer.stop()
	#countdown_timer.stop()
	#
	## Pause the game
	#get_tree().paused = true
	#
	#var game_over_label = Label.new()
	#game_over_label.name = "GameOverLabel"
	#game_over_label.position = Vector2(get_viewport().get_visible_rect().size.x / 2 - 200, get_viewport().get_visible_rect().size.y / 2 - 50)
	#game_over_label.add_theme_font_size_override("font_size", 72)
	#game_over_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
	#game_over_label.text = "GAME OVER"
	#game_over_label.process_mode = Node.PROCESS_MODE_ALWAYS
	#add_child(game_over_label)
	#
	#var final_score_label = Label.new()
	#final_score_label.name = "FinalScoreLabel"
	#final_score_label.position = Vector2(get_viewport().get_visible_rect().size.x / 2 - 150, get_viewport().get_visible_rect().size.y / 2 + 50)
	#final_score_label.add_theme_font_size_override("font_size", 36)
	#final_score_label.add_theme_color_override("font_color", Color(1, 1, 1))
	#final_score_label.text = "Final Score: " + str(player_score) + "\nWaves Survived: " + str(current_wave) + "\nTotal Kills: " + str(player_kills)
	#final_score_label.process_mode = Node.PROCESS_MODE_ALWAYS
	#add_child(final_score_label)
	#
	## Add restart button
	#var restart_button = Button.new()
	#restart_button.name = "RestartButton"
	#restart_button.text = "RESTART"
	#restart_button.add_theme_font_size_override("font_size", 48)
	#restart_button.custom_minimum_size = Vector2(300, 80)
	#restart_button.position = Vector2(get_viewport().get_visible_rect().size.x / 2 - 150, get_viewport().get_visible_rect().size.y / 2 + 220)
	#restart_button.process_mode = Node.PROCESS_MODE_ALWAYS
	#restart_button.pressed.connect(_on_restart_button_pressed)
	#add_child(restart_button)
func game_over():
	#print("GAME OVER!")
	player_health = 0
	
	# Play game over sound
	#play_sound("game_over")
	
	spawn_timer.stop()
	countdown_timer.stop()
	
	# Check and update high scores
	var is_new_record = update_high_scores()
	
	# Pause the game
	get_tree().paused = true
	
	var game_over_label = Label.new()
	game_over_label.name = "GameOverLabel"
	game_over_label.position = Vector2(get_viewport().get_visible_rect().size.x / 2 - 200, get_viewport().get_visible_rect().size.y / 2 - 100)
	game_over_label.add_theme_font_size_override("font_size", 72)
	game_over_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
	game_over_label.text = "GAME OVER"
	game_over_label.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(game_over_label)
	
	var final_score_label = Label.new()
	final_score_label.name = "FinalScoreLabel"
	final_score_label.position = Vector2(get_viewport().get_visible_rect().size.x / 2 - 200, get_viewport().get_visible_rect().size.y / 2 + 20)
	final_score_label.add_theme_font_size_override("font_size", 28)
	final_score_label.add_theme_color_override("font_color", Color(1, 1, 1))
	
	# Build score text with current run stats
	var score_text = "Final Score: " + str(player_score) + "\n"
	score_text += "Waves Survived: " + str(current_wave) + "\n"
	score_text += "Total Kills: " + str(player_kills) + "\n\n"
	
	# Add high score section
	if is_new_record:
		score_text += "NEW RECORD!\n\n"
	
	score_text += "PERSONAL BEST:\n"
	score_text += "Best Wave: " + str(high_score_wave) + "\n"
	score_text += "Most Kills: " + str(high_score_kills) + "\n"
	score_text += "High Score: " + str(high_score_points)
	
	final_score_label.text = score_text
	final_score_label.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(final_score_label)
	
	# Add restart button
	var restart_button = Button.new()
	restart_button.name = "RestartButton"
	restart_button.text = "RESTART"
	restart_button.add_theme_font_size_override("font_size", 48)
	restart_button.custom_minimum_size = Vector2(300, 80)
	restart_button.position = Vector2(get_viewport().get_visible_rect().size.x / 2 - 150, get_viewport().get_visible_rect().size.y / 2 + 280)
	restart_button.process_mode = Node.PROCESS_MODE_ALWAYS
	restart_button.pressed.connect(_on_restart_button_pressed)
	add_child(restart_button)
func _on_restart_button_pressed():
	# Unpause the game
	get_tree().paused = false
	Engine.time_scale = 1.0 
	game_speed = 1.0 
	# Reload the current scene
	get_tree().reload_current_scene()

func create_goal_bunker():
	goal_bunker = Node3D.new()
	goal_bunker.name = "GoalBunker"
	
	var goal_grid_pos = Vector2i(grid.grid_width - 1, grid.grid_height / 2)
	var goal_world_pos = grid.grid_to_world(goal_grid_pos)
	goal_world_pos.y = 0
	goal_bunker.position = goal_world_pos
	
	var bunker_mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(3.0, 4.0, 3.0)
	bunker_mesh.mesh = box
	bunker_mesh.position.y = 2.0
	
	var bunker_mat = StandardMaterial3D.new()
	bunker_mat.albedo_color = Color(0.2, 0.3, 0.4)
	bunker_mat.metallic = 0.6
	bunker_mat.roughness = 0.4
	bunker_mesh.set_surface_override_material(0, bunker_mat)
	goal_bunker.add_child(bunker_mesh)
	
	var core = MeshInstance3D.new()
	var core_box = BoxMesh.new()
	core_box.size = Vector3(-1.0, 1.0, 1.0)
	core.mesh = core_box
	core.position.y = 2.5
	
	var core_mat = StandardMaterial3D.new()
	core_mat.albedo_color = Color(0.3, 0.8, 1.0)
	core_mat.emission_enabled = true
	core_mat.emission = Color(0.3, 0.8, 1.0)
	core_mat.emission_energy_multiplier = 2.0
	core.set_surface_override_material(0, core_mat)
	goal_bunker.add_child(core)
	
	add_child(goal_bunker)
	create_goal_health_bar()

func create_goal_health_bar():
	goal_health_bar_bg = MeshInstance3D.new()
	var bg_mesh = BoxMesh.new()
	bg_mesh.size = Vector3(6.0, 0.8, 0.3)
	goal_health_bar_bg.mesh = bg_mesh
	
	var bg_mat = StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.1, 0.0, 0.0)
	#bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	goal_health_bar_bg.set_surface_override_material(0, bg_mat)
	
	goal_health_bar_bg.position = Vector3(0, 5.5, 0)
	goal_bunker.add_child(goal_health_bar_bg)
	
	goal_health_bar_fg = MeshInstance3D.new()
	var fg_mesh = BoxMesh.new()
	fg_mesh.size = Vector3(5.8, 0.7, 0.35)
	goal_health_bar_fg.mesh = fg_mesh
	
	var fg_mat = StandardMaterial3D.new()
	fg_mat.albedo_color = Color(0.2,  1.0, 0.3)
	fg_mat.emission_enabled = true
	fg_mat.emission = Color(0.2, 1.0, 0.3)
	fg_mat.emission_energy_multiplier = 1.5
	fg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	goal_health_bar_fg.set_surface_override_material(0, fg_mat)
	
	goal_health_bar_fg.position = Vector3(0, 5.5, 0)
	goal_bunker.add_child(goal_health_bar_fg)
	
	goal_health_bar_bg.rotation.y = PI / 2
	goal_health_bar_fg.rotation.y = PI / 2
		# Add health text above the bar
	var health_text = create_3d_text_mesh(
		"Health: " + str(player_health) + "/" + str(max_player_health),
		Vector3(0, 6.5, 0),  # Above the health bar
		Color(1, 0.3, 0.3),  # Red color
		HORIZONTAL_ALIGNMENT_CENTER
	)
	health_text.rotation_degrees = Vector3(0, -90, 0)  # Match bar rotation
	goal_bunker.add_child(health_text)
	
	# Store reference so we can update it
	goal_bunker.set_meta("health_text", health_text)

func update_goal_health_bar():
	if not goal_health_bar_fg or not goal_health_bar_bg:
		return
	
	var health_percent = float(player_health) / float(max_player_health)
	health_percent = clamp(health_percent, 0.0, 1.0)
	
	goal_health_bar_fg.scale.x = health_percent
	
	var fg_mat = goal_health_bar_fg.get_surface_override_material(0)
	if health_percent > 0.5:
		var t = (1.0 - health_percent) * 2.0
		fg_mat.albedo_color = Color(0.2 + t * 0.8, 1.0, 0.3 - t * 0.3)
		fg_mat.emission = fg_mat.albedo_color
	else:
		var t = health_percent * 2.0
		fg_mat.albedo_color = Color(1.0, t, 0.0)
		fg_mat.emission = fg_mat.albedo_color
		# Update health text
	if goal_bunker and goal_bunker.has_meta("health_text"):
		var health_text = goal_bunker.get_meta("health_text")
		update_3d_text(health_text, "Health: " + str(player_health) + "/" + str(max_player_health))
func create_monster_mouth():
	# Use scene if available, otherwise create procedurally
	if monster_mouth_scene:
		monster_mouth = monster_mouth_scene.instantiate()
		monster_mouth.name = "MonsterMouth"
		
		var spawn_grid_pos = Vector2i(0, grid.grid_height / 2)
		var spawn_world_pos = grid.grid_to_world(spawn_grid_pos)
		spawn_world_pos.y = 0
		monster_mouth.position = spawn_world_pos
		
		# Face the goal (rotate to face right)
		monster_mouth.rotation.y = PI / 2
		
		add_child(monster_mouth)
		#create_wave_label_3d()
		return
	
	# Fallback: Create procedurally if no scene is assigned
	monster_mouth = Node3D.new()
	monster_mouth.name = "MonsterMouth"
	
	var spawn_grid_pos = Vector2i(0, grid.grid_height / 2)
	var spawn_world_pos = grid.grid_to_world(spawn_grid_pos)
	spawn_world_pos.y = 0
	monster_mouth.position = spawn_world_pos
	
	# Main body
	var body = MeshInstance3D.new()
	var body_box = BoxMesh.new()
	body_box.size = Vector3(4.0, 5.0, 4.0)
	body.mesh = body_box
	body.position.y = 2.5
	
	var body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.15, 0.1, 0.2)
	body_mat.metallic = 0.3
	body_mat.roughness = 0.8
	body.set_surface_override_material(0, body_mat)
	monster_mouth.add_child(body)
	
	# Left eye
	var left_eye = MeshInstance3D.new()
	var eye_box = BoxMesh.new()
	eye_box.size = Vector3(0.6, 0.6, 0.6)
	left_eye.mesh = eye_box
	left_eye.position = Vector3(-0.8, 3.5, 2.1)
	
	var eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = Color(1.0, 0.0, 0.0)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.0, 0.0)
	eye_mat.emission_energy_multiplier = 2.0
	left_eye.set_surface_override_material(0, eye_mat)
	monster_mouth.add_child(left_eye)
	
	# Right eye
	var right_eye = MeshInstance3D.new()
	right_eye.mesh = eye_box
	right_eye.position = Vector3(0.8, 3.5, 2.1)
	right_eye.set_surface_override_material(0, eye_mat)
	monster_mouth.add_child(right_eye)
	
	# Giant Maw (no teeth - just dark void)
	var maw = MeshInstance3D.new()
	var maw_box = BoxMesh.new()
	maw_box.size = Vector3(2.5, 2.0, 1.2)  # Bigger, deeper mouth
	maw.mesh = maw_box
	maw.position = Vector3(0, 2.0, 2.2)
	
	var maw_mat = StandardMaterial3D.new()
	maw_mat.albedo_color = Color(0.0, 0.0, 0.0)  # Pure black void
	maw_mat.emission_enabled = true
	maw_mat.emission = Color(0.1, 0.0, 0.0)  # Very subtle red glow
	maw_mat.emission_energy_multiplier = 0.3
	maw.set_surface_override_material(0, maw_mat)
	monster_mouth.add_child(maw)
	
	# Left horn
	var left_horn = MeshInstance3D.new()
	var horn_box = BoxMesh.new()
	horn_box.size = Vector3(0.5, 1.5, 0.5)
	left_horn.mesh = horn_box
	left_horn.position = Vector3(-1.5, 5.5, 0)
	left_horn.rotation.z = -0.3
	
	var horn_mat = StandardMaterial3D.new()
	horn_mat.albedo_color = Color(0.1, 0.05, 0.15)
	left_horn.set_surface_override_material(0, horn_mat)
	monster_mouth.add_child(left_horn)
	
	# Right horn
	var right_horn = MeshInstance3D.new()
	right_horn.mesh = horn_box
	right_horn.position = Vector3(1.5, 5.5, 0)
	right_horn.rotation.z = 0.3
	right_horn.set_surface_override_material(0, horn_mat)
	monster_mouth.add_child(right_horn)
	
	# Face the goal (rotate to face right) - FIXED!
	monster_mouth.rotation.y = PI / 2
	
	add_child(monster_mouth)
	create_wave_label_3d()

func create_wave_label_3d():
	wave_label_3d = Label3D.new()
	wave_label_3d.name = "WaveLabel3D"
	wave_label_3d.text = "0"
	wave_label_3d.font_size = 128
	wave_label_3d.pixel_size = 0.01
	wave_label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	wave_label_3d.no_depth_test = true
	wave_label_3d.outline_size = 16
	wave_label_3d.outline_modulate = Color(0, 0, 0, 1)
	
	# Load custom font if available
	var font = load("res://models/HELVETICA73-EXTENDED.TTF")
	if font:
		wave_label_3d.font = font
	
	# Purple/blue gradient color
	wave_label_3d.modulate = Color(0.6, 0.4, 1.0, 1.0)
	
	# Position above monster mouth
	wave_label_3d.position = Vector3(0, 8.0, 0)
	
	if monster_mouth:
		monster_mouth.add_child(wave_label_3d)

func update_wave_label_3d():
	if wave_label_3d and current_wave > 0:
		wave_label_3d.text = str(current_wave)
		wave_label_3d.visible = true
	elif wave_label_3d:
		wave_label_3d.visible = false

#func update_tower_hover():
	## Hide hover stats when tower is selected or building
	#if selected_tower or selected_tower_type != 0:
		#if tower_stats_label:
			#tower_stats_label.visible = false
		## Hide all tower ranges when building (but NOT when a tower is selected)
		#if selected_tower_type != 0:
			#for tower in get_tree().get_nodes_in_group("towers"):
				#if tower.has_method("hide_range"):
					#tower.hide_range()
			#return  # Only return if building
		## If selected_tower exists, keep its range visible
		#if selected_tower and selected_tower.has_method("show_range"):
			#selected_tower.show_range()
		#return
	#
	## Raycast to find tower under mouse
	#var camera = get_viewport().get_camera_3d()
	#if not camera:
		#return
	#
	#var mouse_pos = get_viewport().get_mouse_position()
	#var from = camera.project_ray_origin(mouse_pos)
	#var to = from + camera.project_ray_normal(mouse_pos) * 1000
	#
	#var space_state = get_world_3d().direct_space_state
	#var query = PhysicsRayQueryParameters3D.create(from, to)
	#var result = space_state.intersect_ray(query)
	#
	#var hovered_tower = null
	#
	#if result:
		#var grid_pos = grid.world_to_grid(result.position)
		#
		#if grid.is_valid_grid_position(grid_pos) and grid.is_cell_occupied(grid_pos):
			#var tower = grid.grid_data[grid_pos.x][grid_pos.y]
			#
			## Check if it's actually a tower
			#if tower and tower is Node3D and tower.is_in_group("towers"):
				#hovered_tower = tower
	#
	## Update all towers - show range only for hovered tower
	#for tower in get_tree().get_nodes_in_group("towers"):
		#if tower.has_method("show_range") and tower.has_method("hide_range"):
			#if tower == hovered_tower:
				#tower.show_range()
			#else:
				#tower.hide_range()
	#
	## Show/update stats label for hovered tower
	#if hovered_tower:
		#show_tower_stats(hovered_tower)
	#else:
		#if tower_stats_label:
			#tower_stats_label.visible = false

func update_tower_selection():
		# PLACING MODE: Hide stats when building
	if selected_tower_type >= 1 and selected_tower_type <= 6:
		hide_tower_ui()
		return
	
	# SELECTED MODE: Show range and stats for selected tower
	if selected_tower:
		if selected_tower.has_method("show_range"):
			selected_tower.show_range()
		show_tower_stats(selected_tower)
	else:
		# Nothing selected - hide everything
		hide_tower_ui()
		
func hide_tower_ui():
	# Hide stats label
	if tower_stats_label:
		tower_stats_label.visible = false
	
	# Hide selected tower range
	if selected_tower and selected_tower.has_method("hide_range"):
		selected_tower.hide_range()			
func show_tower_stats(tower: Node3D):

	if not tower_stats_label:
		tower_stats_label = Label3D.new()
		tower_stats_label.pixel_size = 0.005
		tower_stats_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tower_stats_label.no_depth_test = true
		tower_stats_label.modulate = Color(1, 1, 1, 1)
		tower_stats_label.outline_size = 8
		tower_stats_label.outline_modulate = Color(0, 0, 0, 0.9)
		tower_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tower_stats_label.line_spacing = 5.0  # Add spacing between lines
		
		# Load custom font
		var font = load("res://models/HELVETICA73-EXTENDED.TTF")
		if font:
			tower_stats_label.font = font
			tower_stats_label.font_size = 32
		
		add_child(tower_stats_label)
	
	# Get tower stats
	var tower_cost = tower.get("tower_cost") if tower.get("tower_cost") else 100
	var damage = tower.get("damage") if tower.get("damage") else 0  # Changed from "?"
	var attack_range = tower.get("attack_range") if tower.get("attack_range") else 0  # Changed from "?"
	var fire_rate = tower.get("fire_rate") if tower.get("fire_rate") else 0.0  # Changed from "?"
	var kill_count = tower.get("kill_count") if tower.get("kill_count") else 0
	var sell_value = int(tower_cost * 0.75) if tower_cost is int else 0  # Changed from "?"

	# Build stats text
	var stats_text = ""
	stats_text += "Damage: " + str(int(damage)) + "\n"
	stats_text += "Range: " + str(int(attack_range)) + "\n"
	stats_text += "Fire Rate: " + str(snapped(fire_rate, 0.01)) + "/s\n"
	stats_text += "Kills: " + str(kill_count) + "\n"
	stats_text += "Sell: " + str(int(sell_value)) + "g (Shift+RClick)"
	
	tower_stats_label.text = stats_text
	
	# Position above tower
	tower_stats_label.global_position = tower.global_position + Vector3(0, 4.0, 0)
	tower_stats_label.visible = true

func try_select_tower() -> bool:
	# Raycast to find tower under mouse
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return false
	
	var mouse_pos = get_viewport().get_mouse_position()
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space_state.intersect_ray(query)
	
	if result:
		var grid_pos = grid.world_to_grid(result.position)
		
		if grid.is_valid_grid_position(grid_pos) and grid.is_cell_occupied(grid_pos):
			var tower = grid.grid_data[grid_pos.x][grid_pos.y]
			
			# Check if it's actually a tower
			if tower and tower is Node3D and tower.is_in_group("towers"):
				selected_tower = tower
				show_tower_cards(tower)
				return true
	
	return false

func show_tower_cards(tower: Node3D):
	# Close existing cards first
	#close_tower_cards()
	# Show tower range
	if upgrade_card:
		upgrade_card.queue_free()
		upgrade_card = null
	if sell_card:
		sell_card.queue_free()
		sell_card = null
# Show tower range - add debug
	print("Showing cards for tower: ", tower)
	print("Tower has show_range method: ", tower.has_method("show_range"))
	if tower.has_method("show_range"):
		tower.show_range()
		print("Called show_range()")
	# Get tower level and cost
	var tower_level = tower.get("tower_level") if tower.get("tower_level") else 0
	var tower_cost = tower.get("tower_cost") if tower.get("tower_cost") else 100
	var max_level = 3
	
	# WALL TOWERS - only show sell card, no upgrades
	if tower_cost <= 25:  # Walls are cheap
		sell_card = create_tower_ui_card(tower, "SELL", false)
		add_child(sell_card)
		return  # Don't create upgrade card
	# Create upgrade card
	if tower_level < max_level:
		upgrade_card = create_tower_ui_card(tower, "UPGRADE", true)
		add_child(upgrade_card)
	
	# Create sell card
	sell_card = create_tower_ui_card(tower, "SELL", false)
	add_child(sell_card)

func create_tower_ui_card(tower: Node3D, card_type: String, is_upgrade: bool) -> PanelContainer:
	var card = PanelContainer.new()
	
	# Style the card panel
	var style = StyleBoxFlat.new()
	if is_upgrade:
		style.bg_color = Color(0.2, 0.6, 0.2, 0.95)
	else:
		style.bg_color = Color(0.6, 0.2, 0.2, 0.95)
	
	style.border_width_left = 4
	style.border_width_right = 4
	style.border_width_top = 4
	style.border_width_bottom = 4
	style.border_color = Color(0, 0, 0, 1)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	
	card.add_theme_stylebox_override("panel", style)
	card.custom_minimum_size = Vector2(250, 200)
	
	# Create button inside card
	var button = Button.new()
	button.custom_minimum_size = Vector2(250, 200)
	
		# Create VBox for card content
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.anchor_left = 0.0
	vbox.anchor_right = 1.0
	vbox.anchor_top = 0.0
	vbox.anchor_bottom = 1.0
	vbox.add_theme_constant_override("separation", 5)
	
	# Load custom font
	var custom_font = load("res://models/HELVETICA73-EXTENDED.TTF")
	
	# Title label
	var title_label = Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 32)
	title_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	title_label.add_theme_constant_override("outline_size", 4)
	if custom_font:
		title_label.add_theme_font_override("font", custom_font)
	
	# Info label
	var info_label = Label.new()
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info_label.add_theme_font_size_override("font_size", 18)
	info_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	info_label.add_theme_constant_override("outline_size", 4)
	if custom_font:
		info_label.add_theme_font_override("font", custom_font)
	
	if is_upgrade:
		var tower_cost = tower.get("tower_cost") if tower.get("tower_cost") else 100
		var tower_level = tower.get("tower_level") if tower.get("tower_level") else 0
		var upgrade_cost = tower_cost * (tower_level + 1)
		
		# Get current stats
		var current_damage = tower.get("damage") if tower.get("damage") else 10
		var current_range = tower.get("attack_range") if tower.get("attack_range") else 8.0
		var current_fire_rate = tower.get("fire_rate") if tower.get("fire_rate") else 1.0
		
		# Calculate upgraded stats
		var new_damage = int(current_damage * 1.5)
		var new_range = current_range + 2.0
		var new_fire_rate = current_fire_rate * 1.25
		
		title_label.text = "UPGRADE"
		info_label.text = "Level " + str(tower_level) + " → " + str(tower_level + 1) + "\n"
		info_label.text += "Damage: " + str(int(current_damage)) + " → " + str(int(new_damage)) + "\n"
		info_label.text += "Range: " + str(int(current_range)) + " → " + str(int(new_range)) + "\n"
		info_label.text += "Fire Rate: " + str(int(current_fire_rate)) + " → " + str(int(new_fire_rate)) + "\n"
		info_label.text += "Cost: " + str(upgrade_cost) + " Gold"
		
		# Check if can afford
		if player_gold < upgrade_cost:
			style.bg_color = Color(0.3, 0.3, 0.3, 0.95)
			title_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			info_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			button.disabled = true
	else:
		var tower_cost = tower.get("tower_cost") if tower.get("tower_cost") else 100
		var sell_value = int(tower_cost * 0.75)
		
		title_label.text = "SELL"
		info_label.text = "Refund: " + str(sell_value) + " Gold\n(75% of cost)"
	
	vbox.add_child(title_label)
	vbox.add_child(info_label)
	button.add_child(vbox)
	card.add_child(button)
	
	# Position cards in center of screen
# Position cards on right side, vertically centered
	var viewport_size = get_viewport().get_visible_rect().size
	var card_width = 250
	var card_height = 200
	var y_offset = -110 if is_upgrade else 110  # offset from center
	card.position = Vector2(viewport_size.x - card_width - 20, viewport_size.y / 2 + y_offset - card_height / 2)
	
	# Store metadata
	card.set_meta("tower", tower)
	card.set_meta("card_type", card_type)
	card.set_meta("is_upgrade", is_upgrade)
	
	# Connect button
	var tower_ref = tower
	button.pressed.connect(func():
		if not tower_ref or not is_instance_valid(tower_ref):
			#print("Tower no longer valid")
			close_tower_cards()
			return
		
		if is_upgrade:
			upgrade_tower(tower_ref)
		else:
			sell_tower_from_card(tower_ref)
		#close_tower_cards()
	)
	
	return card

func try_click_tower_card() -> bool:
	# Cards now handle their own clicks via button.pressed
	return false

func upgrade_tower(tower: Node3D):
	if not tower or not is_instance_valid(tower):
		#print("Invalid tower reference")
		return
	
	var tower_cost = tower.get("tower_cost") if tower.get("tower_cost") else 100
	var tower_level = tower.get("tower_level") if tower.get("tower_level") else 0
	var upgrade_cost = tower_cost * (tower_level + 1)  # Level 1: 1x, Level 2: 2x, Level 3: 3x
	if tower == selected_tower and tower.has_method("show_range"):
		tower.show_range()
	
	# Check max level
	if tower_level >= 3:
		#print("Tower already at max level!")
		return
	
	# Check if can afford
	if player_gold < upgrade_cost:
		#print("Can't afford upgrade! Need ", upgrade_cost, " gold, have ", player_gold)
		return
	
	# Pay cost
	player_gold -= upgrade_cost
	
	# Get current stats
	var current_damage = tower.get("damage") if tower.get("damage") else 10
	var current_range = tower.get("attack_range") if tower.get("attack_range") else 8.0
	var current_fire_rate = tower.get("fire_rate") if tower.get("fire_rate") else 1.0
	
	# Upgrade stats
	tower.set("tower_level", tower_level + 1)
	tower.set("damage", int(current_damage * 1.5))
	#tower.set("attack_range", current_range * 1.2)
	tower.set("attack_range", current_range + 1.2)
	tower.set("fire_rate", current_fire_rate * 1.25)
	
	#print("Tower upgraded to level ", tower_level + 1)
	#print("  Damage: ", current_damage, " -> ", int(current_damage * 1.5))
	#print("  Range: ", current_range, " -> ", current_range + 2.0)
	#print("  Fire Rate: ", current_fire_rate, " -> ", current_fire_rate * 1.25)
	
	# Update range indicator visual
	if tower.has_method("update_range_indicator"):
		tower.update_range_indicator()
		# Force range to show during upgrade if tower is selected

	# Update visual level indicators
	if tower.has_method("update_level_lights"):
		tower.update_level_lights()
	
	# Show upgrade effect
	create_upgrade_effect(tower.global_position)
	# Wait one frame to ensure all tower properties are updated
	await get_tree().process_frame
	
	# Now refresh the cards with updated stats
	close_tower_cards()  # Clear old cards
	show_tower_cards(tower)  # Create new cards with fresh data
	
	
func sell_tower_from_card(tower: Node3D):
	if not tower or not is_instance_valid(tower):
		#print("Invalid tower reference")
		return
	
	# Calculate refund - use current level's total cost
	var base_cost = tower.get("tower_cost") if tower.get("tower_cost") else 100
	var tower_level = tower.get("tower_level") if tower.get("tower_level") else 0
	
	# Total invested = base cost + upgrade costs
	var total_cost = base_cost
	for i in range(tower_level):
		total_cost += base_cost  # Each upgrade costs the base cost
	
	var refund = int(total_cost * 0.75)
	var tower_position = tower.global_position
	
	player_gold += refund
	#print("Tower sold for ", refund, " gold (level ", tower_level, ")")
	
	# Show floating sold text
	create_sold_text(tower_position, refund)
	
	# Find grid position and remove tower
	for x in range(grid.grid_width):
		for y in range(grid.grid_height):
			var cell_value = grid.grid_data[x][y]
			# Check if cell contains our tower (handle both Node3D and string "rock")
			if cell_value is Node3D and cell_value == tower:
				grid.grid_data[x][y] = null
				#print("Removed tower from grid at ", x, ",", y)
				break
	
	tower.queue_free()
	
	# Recalculate path
	if path_system:
		path_system.calculate_path()

func close_tower_cards():
		# Hide range for previously selected tower
	hide_tower_ui()
	if selected_tower and selected_tower.has_method("hide_range"):
		selected_tower.hide_range()
	selected_tower = null
	if upgrade_card:
		upgrade_card.queue_free()
		upgrade_card = null
	if sell_card:
		sell_card.queue_free()
		sell_card = null

func create_start_button():
	start_button = Button.new()
	start_button.name = "StartButton"
	start_button.text = "START GAME"
	
	start_button.add_theme_font_size_override("font_size", 48)
	start_button.custom_minimum_size = Vector2(300, 80)
	
	var viewport_size = get_viewport().get_visible_rect().size
	start_button.position = Vector2(viewport_size.x / 2 - 150, viewport_size.y - 120)
	
	start_button.pressed.connect(_on_start_button_pressed)
	add_child(start_button)

func _on_start_button_pressed():
	#print("Game started!")
	game_started = true
	
	if start_button:
		start_button.queue_free()
		start_button = null
	
	await get_tree().create_timer(2.0).timeout
	start_next_wave()
func create_tower_button(tower_index: int) -> Control:
	var button = Button.new()
	button.name = "TowerButton" + str(tower_index)  # TowerButton0, TowerButton1, etc
	button.custom_minimum_size = Vector2(100, 100)
	button.set_meta("tower_index", tower_index)
	
	# Create a container that fills the button
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.anchor_left = 0.0
	margin.anchor_right = 1.0
	margin.anchor_top = 0.0
	margin.anchor_bottom = 1.0
	
	# Tower icon fills the background
	var icon = TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Load tower icon
	var icon_path = "res://icons/tower_" + str(tower_index) + "_icon.png"
	var texture = load(icon_path)
	icon.texture = texture
	
	margin.add_child(icon)
	button.add_child(margin)
	
	# Create vertical layout for text labels on top (separate from icon)
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.anchor_left = 0.0
	vbox.anchor_right = 1.0
	vbox.anchor_top = 0.0
	vbox.anchor_bottom = 1.0
	
	# Tower name with thick outline
	var name_label = Label.new()
	name_label.text = tower_names[tower_index]  # Changed from tower_index - 1
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", Color(1, 1, 1))
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	name_label.add_theme_constant_override("outline_size", 6)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)
	
	# Cost label with thick outline
	var cost_label = Label.new()
	cost_label.name = "CostLabel"
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_label.add_theme_font_size_override("font_size", 14)
	cost_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	cost_label.add_theme_constant_override("outline_size", 6)
	cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Get cost from tower scene
	var tower_scene = tower_scenes[tower_index]  # Changed from tower_index - 1
	if tower_scene:
		var temp_tower = tower_scene.instantiate()
		var tower_cost = temp_tower.get("tower_cost")
		temp_tower.queue_free()
		cost_label.text = str(tower_cost) + "g"
	else:
		cost_label.text = "N/A"
	
	vbox.add_child(cost_label)
	
	# Hotkey label with thick outline
	var hotkey_label = Label.new()
	hotkey_label.text = "[" + str(tower_index) + "]"  # Show [0], [1], [2], etc
	hotkey_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hotkey_label.add_theme_font_size_override("font_size", 11)
	hotkey_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	hotkey_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	hotkey_label.add_theme_constant_override("outline_size", 5)
	hotkey_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hotkey_label)
	
	button.add_child(vbox)
	
	# Connect button press
	button.pressed.connect(_on_tower_button_pressed.bind(tower_index))
	
	return button
func _on_tower_button_pressed(tower_index: int):
	selected_tower_type = tower_index
	#print("Tower button pressed: ", tower_index)

func update_tower_buttons():
	for i in range(0, 7):  # Changed from range(1, 8)
		var button = get_node_or_null("TowerButtonContainer/TowerButton" + str(i))
		if not button:
			continue
		
		var tower_scene = tower_scenes[i]  # Changed from i - 1
		if not tower_scene:
			continue
		
		var temp_tower = tower_scene.instantiate()
		var tower_cost = temp_tower.get("tower_cost")
		temp_tower.queue_free()
		
		var can_afford = player_gold >= tower_cost
		var is_selected = selected_tower_type == i
		
		# Update button style with black border and semi-transparent overlay
		var style = StyleBoxFlat.new()
		var hover_style = StyleBoxFlat.new()
		
		if is_selected:
			# Selected button - green overlay with thick black border
			style.bg_color = Color(0.2, 0.6, 0.2, 0.4)
			style.border_width_left = 5
			style.border_width_right = 5
			style.border_width_top = 5
			style.border_width_bottom = 5
			style.border_color = Color(0, 0, 0, 1)
			
			# Hover: brighter green
			hover_style.bg_color = Color(0.3, 0.7, 0.3, 0.5)
			hover_style.border_width_left = 5
			hover_style.border_width_right = 5
			hover_style.border_width_top = 5
			hover_style.border_width_bottom = 5
			hover_style.border_color = Color(0.4, 1.0, 0.4, 1)
		elif not can_afford:
			# Can't afford - red overlay with black border
			style.bg_color = Color(0.5, 0.1, 0.1, 0.5)
			style.border_width_left = 4
			style.border_width_right = 4
			style.border_width_top = 4
			style.border_width_bottom = 4
			style.border_color = Color(0, 0, 0, 1)
			
			# Hover: brighter red
			hover_style.bg_color = Color(0.6, 0.2, 0.2, 0.6)
			hover_style.border_width_left = 4
			hover_style.border_width_right = 4
			hover_style.border_width_top = 4
			hover_style.border_width_bottom = 4
			hover_style.border_color = Color(0.8, 0.3, 0.3, 1)
		else:
			# Can afford - subtle overlay with black border
			style.bg_color = Color(0.15, 0.15, 0.15, 0.3)
			style.border_width_left = 4
			style.border_width_right = 4
			style.border_width_top = 4
			style.border_width_bottom = 4
			style.border_color = Color(0, 0, 0, 1)
			
			# Hover: brighter overlay
			hover_style.bg_color = Color(0.3, 0.3, 0.35, 0.5)
			hover_style.border_width_left = 4
			hover_style.border_width_right = 4
			hover_style.border_width_top = 4
			hover_style.border_width_bottom = 4
			hover_style.border_color = Color(0.5, 0.5, 0.5, 1)
		
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", hover_style)
		button.add_theme_stylebox_override("pressed", style)
		
		# Update cost label color
		var cost_label = button.get_node_or_null("VBoxContainer/CostLabel")
		if cost_label:
			if can_afford:
				cost_label.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
			else:
				cost_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
func create_3d_stat_displays():
	# Gold display at goal bunker
	if goal_bunker:
		goal_gold_text = create_3d_text_mesh("Gold: " + str(player_gold), Vector3(.6, 5, 11), Color(1, 0.84, 0), HORIZONTAL_ALIGNMENT_CENTER)
		goal_gold_text.rotation_degrees = Vector3(0, -90, 0)
		goal_bunker.add_child(goal_gold_text)
		
		goal_score_text = create_3d_text_mesh("Score: " + str(player_score), Vector3(.6, 6, 11), Color(0.5, 1, 0.5), HORIZONTAL_ALIGNMENT_CENTER)
		goal_score_text.rotation_degrees = Vector3(0, -90, 0)
		goal_bunker.add_child(goal_score_text)
	
	# Wave info at monster mouth
	if monster_mouth:
		#var wave_text_shadow = create_3d_text_mesh("Wave: 0", Vector3(4, 7, -0.1), Color(0, 0, 0, 1), HORIZONTAL_ALIGNMENT_LEFT, 148)
		#monster_mouth.add_child(wave_text_shadow)
		mouth_wave_text = create_3d_text_mesh("Wave: 0", Vector3(4, 7, 0), Color(0.6, 0.4, 1.0),HORIZONTAL_ALIGNMENT_LEFT, 128)
		monster_mouth.add_child(mouth_wave_text)
		
		mouth_spawn_text = create_3d_text_mesh("Spawned: 0/0", Vector3(4, 6, 0), Color(1, 0.5, 0.5))
		monster_mouth.add_child(mouth_spawn_text)

func create_3d_text_mesh(text: String, position: Vector3, color: Color, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, font_size: int = 64) -> MeshInstance3D:
	var text_mesh_instance = MeshInstance3D.new()
	
	# Create the 3D text mesh
	var text_mesh = TextMesh.new()
	text_mesh.text = text
	text_mesh.font_size = font_size  # Use the parameter
	text_mesh.depth = 0.1  # Thickness
	text_mesh.curve_step = 0.5
	text_mesh.horizontal_alignment = alignment  
	
	# Load custom font
	var font = load("res://models/HELVETICA73-EXTENDED.TTF")
	if font:
		text_mesh.font = font
	
	text_mesh_instance.mesh = text_mesh
	
	# Create material
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.4
	mat.roughness = 0.6
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # Always bright
	text_mesh_instance.set_surface_override_material(0, mat)
	
	text_mesh_instance.position = position
	
	return text_mesh_instance

func update_3d_text(mesh_instance: MeshInstance3D, new_text: String):
	if mesh_instance and mesh_instance.mesh is TextMesh:
		mesh_instance.mesh.text = new_text
func create_pause_menu():
	# Semi-transparent overlay
	var overlay = ColorRect.new()
	overlay.name = "PauseOverlay"
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(overlay)
	
	# Pause menu panel
	var pause_panel = PanelContainer.new()
	pause_panel.name = "PausePanel"
	pause_panel.custom_minimum_size = Vector2(400, 500)
	pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	
	var viewport_size = get_viewport().get_visible_rect().size
	pause_panel.position = Vector2(viewport_size.x / 2 - 200, viewport_size.y / 2 - 250)
	
	# Style the panel
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.border_width_left = 4
	style.border_width_right = 4
	style.border_width_top = 4
	style.border_width_bottom = 4
	style.border_color = Color(0.3, 0.3, 0.4, 1)
	style.corner_radius_top_left = 15
	style.corner_radius_top_right = 15
	style.corner_radius_bottom_left = 15
	style.corner_radius_bottom_right = 15
	pause_panel.add_theme_stylebox_override("panel", style)
	
	overlay.add_child(pause_panel)
	
	# VBox for menu items
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	pause_panel.add_child(vbox)
	
	# Title
	var title = Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	vbox.add_child(title)
	
	# Add some spacing
	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer1)
	
	# Current run stats
	var current_stats = Label.new()
	current_stats.text = "CURRENT RUN:"
	current_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	current_stats.add_theme_font_size_override("font_size", 24)
	current_stats.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	vbox.add_child(current_stats)
	
	var stats_detail = Label.new()
	stats_detail.text = "Wave: " + str(current_wave) + " | Kills: " + str(player_kills) + " | Score: " + str(player_score)
	stats_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_detail.add_theme_font_size_override("font_size", 20)
	stats_detail.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	vbox.add_child(stats_detail)
	
	# Spacing
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 15)
	vbox.add_child(spacer2)
	
	# High scores
	var high_scores = Label.new()
	high_scores.text = "PERSONAL BEST:"
	high_scores.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	high_scores.add_theme_font_size_override("font_size", 24)
	high_scores.add_theme_color_override("font_color", Color(0.3, 1, 0.3))
	vbox.add_child(high_scores)
	
	var high_scores_detail = Label.new()
	high_scores_detail.text = "Wave: " + str(high_score_wave) + " | Kills: " + str(high_score_kills) + " | Score: " + str(high_score_points)
	high_scores_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	high_scores_detail.add_theme_font_size_override("font_size", 20)
	high_scores_detail.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	vbox.add_child(high_scores_detail)
	
	# Add some spacing before buttons
	var spacer3 = Control.new()
	spacer3.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(spacer3)
	
	# Resume button
	var resume_button = Button.new()
	resume_button.text = "RESUME"
	resume_button.custom_minimum_size = Vector2(300, 70)
	resume_button.add_theme_font_size_override("font_size", 32)
	resume_button.pressed.connect(_on_resume_pressed)
	vbox.add_child(resume_button)
	
	# Restart button
	var restart_button = Button.new()
	restart_button.text = "RESTART"
	restart_button.custom_minimum_size = Vector2(300, 70)
	restart_button.add_theme_font_size_override("font_size", 32)
	restart_button.pressed.connect(_on_restart_from_pause)
	vbox.add_child(restart_button)
	
	# Quit button
	var quit_button = Button.new()
	quit_button.text = "QUIT TO DESKTOP"
	quit_button.custom_minimum_size = Vector2(300, 70)
	quit_button.add_theme_font_size_override("font_size", 32)
	quit_button.pressed.connect(_on_quit_pressed)
	vbox.add_child(quit_button)

func show_pause_menu():
	if not game_started or player_health <= 0:
		return
	
	game_paused = true
	get_tree().paused = true
	create_pause_menu()

func hide_pause_menu():
	game_paused = false
	get_tree().paused = false
	
	var overlay = get_node_or_null("PauseOverlay")
	if overlay:
		overlay.queue_free()

func _on_resume_pressed():
	hide_pause_menu()

func _on_restart_from_pause():
	hide_pause_menu()
	Engine.time_scale = 1.0  
	game_speed = 1.0  #
	get_tree().reload_current_scene()

func _on_quit_pressed():
	get_tree().quit()
func show_wave_notification(wave_number: int):
	# Create big wave notification
	var wave_notif = Label.new()
	wave_notif.name = "WaveNotification"
	wave_notif.text = "WAVE " + str(wave_number)
	wave_notif.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wave_notif.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wave_notif.add_theme_font_size_override("font_size", 120)
	wave_notif.add_theme_color_override("font_color", Color(1, 1, 0.3))
	wave_notif.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	wave_notif.add_theme_constant_override("outline_size", 10)
	
	# Center on screen
	var viewport_size = get_viewport().get_visible_rect().size
	wave_notif.position = Vector2(viewport_size.x / 2 - 400, viewport_size.y / 2 - 100)
	wave_notif.custom_minimum_size = Vector2(800, 200)
	
	# Start fully transparent
	wave_notif.modulate = Color(1, 1, 1, 0)
	
	add_child(wave_notif)
	
	# Animate: fade in, hold, fade out
	var tween = create_tween()
	tween.tween_property(wave_notif, "modulate:a", 1.0, 0.3)  # Fade in
	tween.tween_property(wave_notif, "modulate:a", 1.0, 1.5)  # Hold
	tween.tween_property(wave_notif, "modulate:a", 0.0, 0.5)  # Fade out
	tween.finished.connect(func():
		if is_instance_valid(wave_notif):
			wave_notif.queue_free()
	)
func create_speed_controls():
	# Container for speed buttons
	var speed_container = HBoxContainer.new()
	speed_container.name = "SpeedControls"
	speed_container.add_theme_constant_override("separation", 5)
	var viewport_size = get_viewport().get_visible_rect().size 
	# Position in top-right corner
	#speed_container.position = Vector2(10, 280)  # Below health label
	speed_container.position = Vector2(viewport_size.x - 200, 10) # top right
	# Create 1x, 2x, 3x buttons
	var speeds = [1.0, 2.0, 3.0]
	for speed in speeds:
		var button = Button.new()
		button.text = str(speed) + "x"
		button.custom_minimum_size = Vector2(60, 40)
		button.add_theme_font_size_override("font_size", 20)
		button.set_meta("speed", speed)
		
		# Highlight current speed
		if speed == game_speed:
			var style = StyleBoxFlat.new()
			style.bg_color = Color(0.2, 0.6, 0.2, 0.8)
			style.border_width_left = 2
			style.border_width_right = 2
			style.border_width_top = 2
			style.border_width_bottom = 2
			style.border_color = Color(0.4, 1.0, 0.4)
			button.add_theme_stylebox_override("normal", style)
		
		button.pressed.connect(_on_speed_button_pressed.bind(speed))
		speed_container.add_child(button)
	
	add_child(speed_container)

func _on_speed_button_pressed(speed: float):
	game_speed = speed
	Engine.time_scale = speed
	#print("Game speed set to ", speed, "x")
	
	# Update button highlights
	update_speed_button_highlights()

func update_speed_button_highlights():
	var speed_container = get_node_or_null("SpeedControls")
	if not speed_container:
		return
	
	for button in speed_container.get_children():
		var button_speed = button.get_meta("speed")
		
		if button_speed == game_speed:
			# Highlight selected speed
			var style = StyleBoxFlat.new()
			style.bg_color = Color(0.2, 0.6, 0.2, 0.8)
			style.border_width_left = 2
			style.border_width_right = 2
			style.border_width_top = 2
			style.border_width_bottom = 2
			style.border_color = Color(0.4, 1.0, 0.4)
			button.add_theme_stylebox_override("normal", style)
			button.add_theme_stylebox_override("hover", style)
			button.add_theme_stylebox_override("pressed", style)
		else:
			# Normal style
			button.remove_theme_stylebox_override("normal")
			button.remove_theme_stylebox_override("hover")
			button.remove_theme_stylebox_override("pressed")
func save_high_scores():
	# Save to config file
	var config = ConfigFile.new()
	config.set_value("highscores", "wave", high_score_wave)
	config.set_value("highscores", "kills", high_score_kills)
	config.set_value("highscores", "points", high_score_points)
	config.save("user://highscores.cfg")
	#print("High scores saved: Wave ", high_score_wave, ", Kills ", high_score_kills, ", Points ", high_score_points)

func load_high_scores():
	var config = ConfigFile.new()
	var err = config.load("user://highscores.cfg")
	
	if err == OK:
		high_score_wave = config.get_value("highscores", "wave", 0)
		high_score_kills = config.get_value("highscores", "kills", 0)
		high_score_points = config.get_value("highscores", "points", 0)
		#print("High scores loaded: Wave ", high_score_wave, ", Kills ", high_score_kills, ", Points ", high_score_points)
	#else:
		#print("No high scores file found, starting fresh")

func update_high_scores():
	var updated = false
	
	if current_wave > high_score_wave:
		high_score_wave = current_wave
		updated = true
	
	if player_kills > high_score_kills:
		high_score_kills = player_kills
		updated = true
	
	if player_score > high_score_points:
		high_score_points = player_score
		updated = true
	
	if updated:
		save_high_scores()
		return true
	return false
