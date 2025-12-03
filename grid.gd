extends Node3D
# Grid.gd - Manages the game grid for tower placement

var grid_width: int
var grid_height: int
var cell_size: float

# Terrain settings (set by Main)
var base_tile_height: float = 0.3
var obstacle_height_min: float = 2.0
var obstacle_height_max: float = 4.0
var obstacle_cluster_count: int = 8
var obstacle_cluster_size: int = 5

# Visual settings
var base_brightness: float = 0.15
var brightness_variation: float = 0.05
var metallic: float = 0.3
var roughness: float = 0.7

# Grid data - tracks what's in each cell
var grid_data: Array = []

# Path system reference
var path_system: Node3D = null

# Visual elements
var hover_indicator: MeshInstance3D
var tile_heights: Dictionary = {}  # Store heights for each tile

# Tower preview
var tower_preview: Node3D = null
var range_preview: MeshInstance3D = null
var current_preview_scene: PackedScene = null
var tower_info_label: Label3D = null

func _ready():
	initialize_grid()
	create_ground()
	create_hover_indicator()
	create_range_preview()
	create_tower_info_label()

func initialize_grid():
	# Create 2D array for grid data
	grid_data.clear()
	for x in range(grid_width):
		var column = []
		for y in range(grid_height):
			column.append(null)  # null = empty, can place tower
		grid_data.append(column)

func create_ground():
	# Generate obstacle clusters
	var obstacle_tiles = generate_obstacle_clusters()
	
	# Create individual cube tiles for each grid cell
	for x in range(grid_width):
		for z in range(grid_height):
			var tile = MeshInstance3D.new()
			var box_mesh = BoxMesh.new()
			
			var grid_pos = Vector2i(x, z)
			var tile_key = Vector2i(x, z)
			
			# Determine height - either base or obstacle
			var height = base_tile_height
			var is_obstacle = tile_key in obstacle_tiles
			
			if is_obstacle:
				height = randf_range(obstacle_height_min, obstacle_height_max)
				# Mark this grid cell as occupied so pathfinding avoids it
				grid_data[x][z] = "obstacle"
			
			tile_heights[tile_key] = height
			
			box_mesh.size = Vector3(cell_size * 0.95, height, cell_size * 0.95)
			tile.mesh = box_mesh
			
			# Position the tile
			var world_pos = grid_to_world(grid_pos)
			tile.position = world_pos
			tile.position.y = height / 2.0  # Center the box vertically
			
			# Dark material with slight variation
			var material = StandardMaterial3D.new()
			var brightness = base_brightness + randf_range(-brightness_variation, brightness_variation)
			
			# Make obstacles slightly brighter so they're visible
			#if is_obstacle:
				#brightness += 0.05
				#
				## ADD NOISE TEXTURE FOR OBSTACLES ONLY
				##var noise = FastNoiseLite.new()
				##noise.seed = randi()
				##noise.noise_type = FastNoiseLite.TYPE_PERLIN
				##noise.frequency = 0.5
				#var noise = FastNoiseLite.new()
				#noise.seed = randi()
				#noise.noise_type = FastNoiseLite.TYPE_CELLULAR  # Changed from PERLIN
				#noise.frequency = 0.3  # Lower = bigger patterns
				#noise.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
				#noise.fractal_octaves = 3  # More detail layers
				#var noise_texture = NoiseTexture2D.new()
				#noise_texture.noise = noise
				#noise_texture.width = 512
				#noise_texture.height = 512
				#
				#material.albedo_texture = noise_texture
				#material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				#material.uv1_scale = Vector3(2, 2, 2)  # Scale texture
				#material.uv1_triplanar = true  # Important for cubes!
				#material.uv1_triplanar_sharpness = 4.0
				#material.roughness = 0.8  # Rougher for stone
			#
			#if is_obstacle:
	# VERY PROMINENT NOISE SETUP
			var noise = FastNoiseLite.new()
			noise.seed = randi()
			
			#noise.noise_type = FastNoiseLite.TYPE_CELLULAR  # Rocky
			#noise.frequency = 0.25  # Bigger patterns
			#noise.fractal_octaves = 5  # Lots of detail
			#
			if is_obstacle:
				# Chunky rocky noise for obstacles
				noise.noise_type = FastNoiseLite.TYPE_CELLULAR
				noise.frequency = 0.3
				noise.fractal_octaves = 5
			else:
				# Subtle concrete-like noise for floor
				noise.noise_type = FastNoiseLite.TYPE_PERLIN
				noise.frequency = 0.6
				noise.fractal_octaves = 2
			
			noise.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
			noise.fractal_lacunarity = 2.5  # More variation
			noise.fractal_gain = 0.6

			var noise_texture = NoiseTexture2D.new()
			noise_texture.noise = noise
			noise_texture.width = 128	  # Higher resolution
			noise_texture.height = 128
			noise_texture.as_normal_map = false  # Use for color

			material.albedo_texture = noise_texture
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

			# Brighter base color so noise shows
			material.albedo_color = Color(0.4, 0.4, 0.4)  # Much brighter!

			# Bigger texture scale = smaller pattern (more visible detail)
			material.uv1_scale = Vector3(1.5, 1.5, 1.5)  # Reduced from 2
			material.uv1_triplanar = true
			material.uv1_triplanar_sharpness = 4.0

			# Add normal map for depth
			material.normal_enabled = true
			material.normal_texture = noise_texture
			material.normal_scale = 2.5  # Very bumpy

			material.roughness = 0.9
			material.metallic = 0.0
			# VERY PROMINENT NOISE SETUP
				
				
			material.albedo_color = Color(brightness, brightness, brightness)
			material.metallic = metallic
			tile.set_surface_override_material(0, material)
			
			# Add collision
			var static_body = StaticBody3D.new()
			var collision_shape = CollisionShape3D.new()
			var box_shape = BoxShape3D.new()
			box_shape.size = box_mesh.size
			collision_shape.shape = box_shape
			static_body.add_child(collision_shape)
			tile.add_child(static_body)
			
			add_child(tile)
	
	# Create border around play field
	create_border()

func generate_obstacle_clusters() -> Array:
	var obstacles = []
	
	# Get spawn and goal positions to avoid them
	var spawn_pos = Vector2i(0, grid_height / 2)
	var goal_pos = Vector2i(grid_width - 1, grid_height / 2)
	var avoid_radius = 3  # Don't place obstacles within 3 cells of spawn/goal
	
	for i in range(obstacle_cluster_count):
		# Pick a random center point for the cluster
		var center_x = randi() % grid_width
		var center_z = randi() % grid_height
		var center = Vector2i(center_x, center_z)
		
		# Skip if too close to spawn or goal
		if center.distance_to(spawn_pos) < avoid_radius or center.distance_to(goal_pos) < avoid_radius:
			continue
		
		# Create cluster around this center
		var cluster_radius = obstacle_cluster_size / 2
		for dx in range(-cluster_radius, cluster_radius + 1):
			for dz in range(-cluster_radius, cluster_radius + 1):
				var x = center_x + dx
				var z = center_z + dz
				
				# Check if within grid bounds
				if x >= 0 and x < grid_width and z >= 0 and z < grid_height:
					var pos = Vector2i(x, z)
					
					# Skip if too close to spawn or goal
					if pos.distance_to(spawn_pos) < avoid_radius or pos.distance_to(goal_pos) < avoid_radius:
						continue
					
					# Use distance for probability (closer to center = more likely)
					var dist = sqrt(dx * dx + dz * dz)
					if randf() > (dist / cluster_radius) * 0.7:  # Fade out towards edges
						obstacles.append(pos)
	# Add permanent obstacles next to monster mouth (spawn area)
	# Convert world positions to grid positions
	var blocked_1 = world_to_grid(Vector3(-29.0, 0, 5.0))
	var blocked_2 = world_to_grid(Vector3(-29.0, 0, -3.0))
	var blocked_3 = world_to_grid(Vector3(-27.0, 0, 5.0))
	var blocked_4 = world_to_grid(Vector3(-27.0, 0, -3.0))
	var blocked_5 = world_to_grid(Vector3(-29.0, 0, -1.0))
	var blocked_6 = world_to_grid(Vector3(-29.0, 0, 3.0))
	var gblocked_1 = world_to_grid(Vector3(29.0, 0, 5.0))
	var gblocked_2 = world_to_grid(Vector3(29.0, 0, -3.0))
	var gblocked_3 = world_to_grid(Vector3(27.0, 0, 5.0))
	var gblocked_4 = world_to_grid(Vector3(27.0, 0, -3.0))
	var gblocked_5 = world_to_grid(Vector3(29.0, 0, -1.0))
	var gblocked_6 = world_to_grid(Vector3(29.0, 0, 3.0))
	obstacles.append(blocked_1)
	obstacles.append(blocked_2)
	obstacles.append(blocked_3)
	obstacles.append(blocked_4)
	obstacles.append(blocked_5)
	obstacles.append(blocked_6)
	obstacles.append(gblocked_1)
	obstacles.append(gblocked_2)
	obstacles.append(gblocked_3)
	obstacles.append(gblocked_4)
	obstacles.append(gblocked_5)
	obstacles.append(gblocked_6)
	#print("Grid: Added permanent obstacles at ", blocked_1, " and ", blocked_2)
	return obstacles

func create_hover_indicator():
	hover_indicator = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(cell_size * 0.9, 0.2, cell_size * 0.9)
	hover_indicator.mesh = box_mesh
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.8, 0.3, 0.7)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Remove this line material.disable_depth_test = true  # Always render on top
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS  # Add this instead
	hover_indicator.set_surface_override_material(0, material)
	hover_indicator.visible = false
	add_child(hover_indicator)

func create_range_preview():
	range_preview = MeshInstance3D.new()
	
	# Flat cylinder to show range
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 1.0  # Will be scaled
	cylinder.bottom_radius = 1.0
	cylinder.height = 0.05
	range_preview.mesh = cylinder
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.8, 0.3, 0.3)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	range_preview.set_surface_override_material(0, mat)
	
	range_preview.visible = false
	add_child(range_preview)

func create_tower_info_label():
	tower_info_label = Label3D.new()
	tower_info_label.pixel_size = 0.005
	tower_info_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tower_info_label.no_depth_test = true
	tower_info_label.modulate = Color(1, 1, 1, 1)
	tower_info_label.outline_size = 16  # Increased from 8 for thicker outline
	tower_info_label.outline_modulate = Color(0, 0, 0, 1.0)  # Fully opaque black
	tower_info_label.line_spacing = 10.0  # Add spacing between lines
	
	# Load custom font
	var font = load("res://models/HELVETICA73-EXTENDED.TTF")
	if font:
		tower_info_label.font = font
		tower_info_label.font_size = 72  # Increased from 64 for better readability
	
	tower_info_label.visible = false
	add_child(tower_info_label)

func _process(_delta):
	update_hover_indicator()

func update_hover_indicator():
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return
	
	var mouse_pos = get_viewport().get_mouse_position()
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space_state.intersect_ray(query)
	
	# Get selected tower scene from Main to check if player is building
	var main = get_parent()
	var is_building = false
	if main and main.has_method("get_selected_tower_scene"):
		var tower_scene = main.get_selected_tower_scene()
		if tower_scene:
			is_building = true
	
	if result and is_building:
		var hit_pos = result.position
		var grid_pos = world_to_grid(hit_pos)
		
		if is_valid_grid_position(grid_pos):
			hover_indicator.visible = true
			var hover_pos = grid_to_world(grid_pos)
			
			# Get the tile height at this position
			var tile_height = tile_heights.get(grid_pos, base_tile_height)
			hover_pos.y = tile_height + 0.2  # Place it above the tile
			
			hover_indicator.position = hover_pos
			
			# Change color based on whether cell is occupied
			var material = hover_indicator.get_surface_override_material(0)
			if is_cell_occupied(grid_pos):
				material.albedo_color = Color(0.8, 0.3, 0.3, 0.5)  # Red if occupied
			else:
				material.albedo_color = Color(0.3, 0.8, 0.3, 0.5)  # Green if free
			
			# Update tower preview
			update_tower_preview(grid_pos, hover_pos)
		else:
			hover_indicator.visible = false
			hide_tower_preview()
	else:
		hover_indicator.visible = false
		hide_tower_preview()

func update_tower_preview(grid_pos: Vector2i, world_pos: Vector3):
	# Get selected tower scene from Main
	var main = get_parent()
	if not main or not main.has_method("get_selected_tower_scene"):
		hide_tower_preview()
		return
	
	var tower_scene = main.get_selected_tower_scene()
	
	if not tower_scene:
		hide_tower_preview()
		return
	
	# Create or update preview
	if current_preview_scene != tower_scene:
		# Different tower selected, recreate preview
		clear_tower_preview()
		tower_preview = tower_scene.instantiate()
		add_child(tower_preview)
		current_preview_scene = tower_scene
		
		# Disable the tower's processing so it doesn't shoot
		disable_tower_behavior(tower_preview)
	
	if tower_preview:
		tower_preview.visible = true
		tower_preview.position = world_pos
		tower_preview.position.y = tile_heights.get(grid_pos, base_tile_height) + 1.0
		
		# Check if cell is occupied
		var is_occupied = is_cell_occupied(grid_pos)
		
		# Check if player can afford this tower
		var can_afford = true
		var tower_cost = tower_preview.get("tower_cost")
		if tower_cost and main.has_method("get"):
			var player_gold = main.get("player_gold")
			if player_gold != null and player_gold < tower_cost:
				can_afford = false
		
		# Make preview semi-transparent and color based on validity and affordability
		make_preview_transparent(tower_preview, is_occupied or not can_afford)
		
		# Update tower info label
		if tower_info_label:
			tower_info_label.visible = true
			var tower_type = main.tower_names[main.selected_tower_type] if main.has_method("get") else "Tower"
			var cost_text = str(tower_cost) + " Gold" if tower_cost else "FREE"
			tower_info_label.text = tower_type + "\n" + cost_text
			
			# Position label above tower
			tower_info_label.position = world_pos
			tower_info_label.position.y = tile_heights.get(grid_pos, base_tile_height) + 4.0
			
			# Color label based on affordability
			if is_occupied:
				tower_info_label.modulate = Color(1.0, 0.3, 0.3, 1.0)  # Red if occupied
			elif not can_afford:
				tower_info_label.modulate = Color(1.0, 0.5, 0.0, 1.0)  # Orange if can't afford
			else:
				tower_info_label.modulate = Color(0.3, 1.0, 0.3, 1.0)  # Green if valid
		
		# Show range indicator
		if tower_preview.has_method("get") and tower_preview.get("attack_range"):
			var attack_range = tower_preview.get("attack_range")
			range_preview.visible = true
			range_preview.position = world_pos
			range_preview.position.y = tile_heights.get(grid_pos, base_tile_height) + 0.1
			range_preview.scale = Vector3(attack_range, 1.0, attack_range)
			
			# Color range based on validity and affordability
			var range_mat = range_preview.get_surface_override_material(0)
			if is_occupied or not can_afford:
				range_mat.albedo_color = Color(0.8, 0.3, 0.3, 0.3)  # Red if can't place or afford
			else:
				range_mat.albedo_color = Color(0.3, 0.8, 0.3, 0.3)  # Green if valid
		else:
			range_preview.visible = false

func disable_tower_behavior(node: Node):
	# Disable processing so tower doesn't shoot
	if node.has_method("set_process"):
		node.set_process(false)
	if node.has_method("set_physics_process"):
		node.set_physics_process(false)
	
	# Recursively disable for all children
	for child in node.get_children():
		disable_tower_behavior(child)

func make_preview_transparent(node: Node, make_red: bool = false):
	# Recursively make all meshes semi-transparent
	if node is MeshInstance3D:
		var mat_count = node.get_surface_override_material_count()
		if mat_count == 0:
			mat_count = node.mesh.get_surface_count() if node.mesh else 0
		
		for i in range(mat_count):
			var mat = node.get_surface_override_material(i)
			if not mat:
				mat = node.mesh.surface_get_material(i) if node.mesh else null
			
			if mat:
				# Create a copy and make it transparent
				var preview_mat = mat.duplicate()
				preview_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				
				if make_red:
					# Red tint if can't place/afford
					preview_mat.albedo_color = Color(1.0, 0.3, 0.3, 0.5)
				else:
					# Normal semi-transparent
					preview_mat.albedo_color.a = 0.5
				
				node.set_surface_override_material(i, preview_mat)
	
	for child in node.get_children():
		make_preview_transparent(child, make_red)

func hide_tower_preview():
	if tower_preview:
		tower_preview.visible = false
	if range_preview:
		range_preview.visible = false
	if tower_info_label:
		tower_info_label.visible = false

func clear_tower_preview():
	if tower_preview:
		tower_preview.queue_free()
		tower_preview = null
	current_preview_scene = null

func world_to_grid(world_pos: Vector3) -> Vector2i:
	var half_width = (grid_width * cell_size) / 2.0
	var half_height = (grid_height * cell_size) / 2.0
	
	var grid_x = int((world_pos.x + half_width) / cell_size)
	var grid_z = int((world_pos.z + half_height) / cell_size)
	
	return Vector2i(grid_x, grid_z)

func grid_to_world(grid_pos: Vector2i) -> Vector3:
	var half_width = (grid_width * cell_size) / 2.0
	var half_height = (grid_height * cell_size) / 2.0
	
	var world_x = grid_pos.x * cell_size - half_width + cell_size / 2.0
	var world_z = grid_pos.y * cell_size - half_height + cell_size / 2.0
	
	return Vector3(world_x, 0, world_z)

func is_valid_grid_position(grid_pos: Vector2i) -> bool:
	return grid_pos.x >= 0 and grid_pos.x < grid_width and grid_pos.y >= 0 and grid_pos.y < grid_height

func is_cell_occupied(grid_pos: Vector2i) -> bool:
	if not is_valid_grid_position(grid_pos):
		return true
	return grid_data[grid_pos.x][grid_pos.y] != null

func place_tower(grid_pos: Vector2i, tower: Node3D) -> bool:
	if not is_valid_grid_position(grid_pos) or is_cell_occupied(grid_pos):
		#print("Grid: Cannot place tower - invalid or occupied")
		return false
	
	# Temporarily mark cell as occupied to test if path still exists
	var original_value = grid_data[grid_pos.x][grid_pos.y]
	grid_data[grid_pos.x][grid_pos.y] = "test_tower"
	
	# Test if a path still exists using simple pathfinding check
	var path_exists = test_path_exists()
	
	if not path_exists:
		# No path exists - reject tower placement
		grid_data[grid_pos.x][grid_pos.y] = original_value
		#print("Grid: Tower would block path - placement rejected!")
		return false
	
	# Path exists - allow placement
	grid_data[grid_pos.x][grid_pos.y] = tower
	#print("Grid: Tower placed in grid_data at ", grid_pos)
	tower.position = grid_to_world(grid_pos)
	tower.position.y = 0.5
	add_child(tower)
	
	# Recalculate path immediately
	if path_system:
		#print("Grid: Recalculating path...")
		path_system.calculate_path()
	
	return true

func test_path_exists() -> bool:
	if not path_system:
		return true
	
	# Simple BFS to check if start can reach end
	var start = path_system.path_start
	var goal = path_system.path_end
	
	var queue: Array = [start]
	var visited: Dictionary = {start: true}
	
	while queue.size() > 0:
		var current = queue.pop_front()
		
		if current == goal:
			return true
		
		# Check all 4 neighbors
		var neighbors = [
			current + Vector2i(1, 0),
			current + Vector2i(-1, 0),
			current + Vector2i(0, 1),
			current + Vector2i(0, -1)
		]
		
		for neighbor in neighbors:
			if not is_valid_grid_position(neighbor):
				continue
			if neighbor in visited:
				continue
			if is_cell_occupied(neighbor):
				continue
			
			visited[neighbor] = true
			queue.append(neighbor)
	
	return false  # No path found

func remove_tower(grid_pos: Vector2i):
	if is_valid_grid_position(grid_pos) and is_cell_occupied(grid_pos):
		var tower = grid_data[grid_pos.x][grid_pos.y]
		grid_data[grid_pos.x][grid_pos.y] = null
		if tower:
			tower.queue_free()

func create_border():
	var border_width = 3  # How many cells wide the border is
	
	# Create blocks for each border position
	for ring in range(border_width):
		# Top and bottom edges
		for x in range(-ring - 1, grid_width + ring + 1):
			create_border_tile(Vector2i(x, -ring - 1), ring)
			create_border_tile(Vector2i(x, grid_height + ring), ring)
		
		# Left and right edges (excluding corners already done)
		for z in range(-ring, grid_height + ring):
			create_border_tile(Vector2i(-ring - 1, z), ring)
			create_border_tile(Vector2i(grid_width + ring, z), ring)

func create_border_tile(pos: Vector2i, ring: int):
	var world_pos = grid_to_world(pos)
	
	var tile = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	
	# Height based on ring - innermost to outermost
	var height_ranges = [
		Vector2(2.0, 6.0),   # Ring 0 (innermost)
		Vector2(3.0, 7.0),   # Ring 1 (middle)
		Vector2(4.0, 8.0)    # Ring 2 (outermost)
	]
	
	var height_range = height_ranges[ring]
	var height = randf_range(height_range.x, height_range.y)
	
	box_mesh.size = Vector3(cell_size * 0.95, height, cell_size * 0.95)
	tile.mesh = box_mesh
	
	tile.position = world_pos
	tile.position.y = height / 2.0
	
	# CREATE CELLULAR NOISE TEXTURE
	var material = StandardMaterial3D.new()
	
	var noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.4
	noise.fractal_octaves = 4
	noise.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	
	var noise_texture = NoiseTexture2D.new()
	noise_texture.noise = noise
	noise_texture.width = 128
	noise_texture.height = 128
	
	material.albedo_texture = noise_texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.uv1_scale = Vector3(1.5, 1.5, 1.5)
	material.uv1_triplanar = true
	material.uv1_triplanar_sharpness = 4.0
	
	# Add normal map for depth
	material.normal_enabled = true
	material.normal_texture = noise_texture
	material.normal_scale = 2.0
	
	# Randomly pick grey tone
	var color_choice = randi() % 3
	var color: Color
	
	match color_choice:
		0:  # Dark grey
			var brightness = base_brightness - 0.1
			color = Color(brightness, brightness, brightness)
		1:  # Grey
			var brightness = base_brightness - 0.05
			color = Color(brightness, brightness, brightness)
		2:  # Blue-grey
			var brightness = base_brightness - 0.03
			color = Color(brightness * 1, brightness * 0.85, brightness * 1.15)
			# ADD EMISSION FOR BLUE-GREY ONLY
			material.emission_enabled = true
			material.emission = Color(0.3, 0.0, 0.5)  # Purple  glow
			material.emission_energy_multiplier = 0.05  # Adjust brightness (0.2 = subtle, 2.0 = bright)

	material.albedo_color = color
	material.metallic = 0.1  # Less metallic for stone
	material.roughness = 0.9  # Very rough for stone
	tile.set_surface_override_material(0, material)
	
	add_child(tile)

func get_floor_height_at(world_pos: Vector3) -> float:
	var grid_pos = world_to_grid(world_pos)
	return tile_heights.get(grid_pos, base_tile_height)
