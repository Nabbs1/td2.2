extends Node3D
# PathSystem.gd - Grid-based A* pathfinding

var grid_ref: Node3D
var path_start: Vector2i
var path_end: Vector2i
var current_path: PackedVector3Array = PackedVector3Array()
var current_grid_path: Array = []
var path_version: int = 0  # Increment each time path changes

# Visual path
var path_visual: MeshInstance3D

func _ready():
	create_path_visual()

func initialize(grid: Node3D, start: Vector2i, end: Vector2i):
	grid_ref = grid
	path_start = start
	path_end = end
	await get_tree().process_frame
	calculate_path()

func calculate_path():
	if not grid_ref:
		print("PathSystem: No grid reference!")
		return
	
	print("PathSystem: Calculating A* path from ", path_start, " to ", path_end)
	
	# A* pathfinding
	var open_set: Array = []
	var closed_set: Dictionary = {}
	var came_from: Dictionary = {}
	var g_score: Dictionary = {}
	var f_score: Dictionary = {}
	
	open_set.append(path_start)
	g_score[path_start] = 0
	f_score[path_start] = heuristic(path_start, path_end)
	
	while open_set.size() > 0:
		# Find node with lowest f_score
		var current = open_set[0]
		var current_f = f_score.get(current, INF)
		
		for node in open_set:
			var node_f = f_score.get(node, INF)
			if node_f < current_f:
				current = node
				current_f = node_f
		
		# Reached goal?
		if current == path_end:
			current_grid_path = reconstruct_path(came_from, current)
			convert_to_world_path()
			path_version += 1  # Increment version when path changes
			print("PathSystem: Path found with ", current_grid_path.size(), " grid cells (version ", path_version, ")")
			update_path_visual()
			return
		
		open_set.erase(current)
		closed_set[current] = true
		
		# Check neighbors (4-directional only)
		var neighbors = get_neighbors(current)
		for neighbor in neighbors:
			if neighbor in closed_set:
				continue
			
			if grid_ref.is_cell_occupied(neighbor):
				continue
			
			var tentative_g = g_score.get(current, INF) + 1
			
			if neighbor not in open_set:
				open_set.append(neighbor)
			elif tentative_g >= g_score.get(neighbor, INF):
				continue
			
			came_from[neighbor] = current
			g_score[neighbor] = tentative_g
			f_score[neighbor] = tentative_g + heuristic(neighbor, path_end)
	
	# No path found
	print("PathSystem: No path found!")
	current_grid_path.clear()
	current_path = PackedVector3Array()
	update_path_visual()

func reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array:
	var path: Array = [current]
	while current in came_from:
		current = came_from[current]
		path.insert(0, current)
	return path

func heuristic(a: Vector2i, b: Vector2i) -> float:
	# Manhattan distance (4-directional)
	return abs(a.x - b.x) + abs(a.y - b.y)

func get_neighbors(pos: Vector2i) -> Array:
	var neighbors: Array = []
	var directions = [
		Vector2i(1, 0),   # Right
		Vector2i(-1, 0),  # Left
		Vector2i(0, 1),   # Down
		Vector2i(0, -1)   # Up
	]
	
	for dir in directions:
		var neighbor = pos + dir
		if grid_ref.is_valid_grid_position(neighbor):
			neighbors.append(neighbor)
	
	return neighbors

func convert_to_world_path():
	current_path = PackedVector3Array()
	for grid_pos in current_grid_path:
		var world_pos = grid_ref.grid_to_world(grid_pos)
		world_pos.y = 0.5
		current_path.append(world_pos)

func create_path_visual():
	path_visual = MeshInstance3D.new()
	var immediate_mesh = ImmediateMesh.new()
	path_visual.mesh = immediate_mesh
	
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.0, 0.0, 0.2)
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	material.no_depth_test = false
	#path_visual.set_surface_override_material(0, material)
	path_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	add_child(path_visual)

func update_path_visual():
	if current_path.size() == 0:
		print("PathSystem: Cannot update visual - empty path")
		# Clear the visual
		var immediate_mesh = ImmediateMesh.new()
		path_visual.mesh = immediate_mesh
		create_path_markers()
		return
	
	print("PathSystem: Updating visual with ", current_path.size(), " points")
	
	var immediate_mesh = ImmediateMesh.new()
	
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	
	for i in range(current_path.size() - 1):
		var current_point = current_path[i]
		var next_point = current_path[i + 1]
		
		immediate_mesh.surface_add_vertex(current_point)
		immediate_mesh.surface_add_vertex(next_point)
	
	immediate_mesh.surface_end()
	
	# Assign mesh and material
	path_visual.mesh = immediate_mesh
	
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.0, 0.0, 0.2)
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	material.no_depth_test = false
	path_visual.set_surface_override_material(0, material)
	
	create_path_markers()

func create_path_markers():
	# Remove old markers
	for child in get_children():
		if child != path_visual:
			child.queue_free()
	
	if current_path.size() == 0:
		return
	
	# Start marker (green)
	var start_marker = MeshInstance3D.new()
	var start_mesh = CylinderMesh.new()
	start_mesh.top_radius = 0.7
	start_mesh.bottom_radius = 0.7
	start_mesh.height = 1.0
	start_marker.mesh = start_mesh
	
	var start_mat = StandardMaterial3D.new()
	start_mat.albedo_color = Color(0.2, 1.0, 0.2)
	start_mat.emission_enabled = true
	start_mat.emission = Color(0.2, 1.0, 0.2)
	start_mat.emission_energy_multiplier = 0.5
	start_marker.set_surface_override_material(0, start_mat)
	var start_pos = grid_ref.grid_to_world(path_start)
	start_pos.y = 2.0
	start_marker.position = start_pos
	add_child(start_marker)
	
	# End marker (red)
	var end_marker = MeshInstance3D.new()
	var end_mesh = CylinderMesh.new()
	end_mesh.top_radius = 0.7
	end_mesh.bottom_radius = 0.7
	end_mesh.height = 1.0
	end_marker.mesh = end_mesh
	end_marker.visible = false
	var end_mat = StandardMaterial3D.new()
	end_mat.albedo_color = Color(1.0, 0.2, 0.2)
	end_mat.emission_enabled = true
	end_mat.emission = Color(1.0, 0.2, 0.2)
	end_mat.emission_energy_multiplier = 0.5
	end_marker.set_surface_override_material(0, end_mat)
	var end_pos = grid_ref.grid_to_world(path_end)
	end_pos.y = 2.0
	end_marker.position = end_pos
	add_child(end_marker)

func get_enemy_path() -> PackedVector3Array:
	return current_path

func get_grid_path() -> Array:
	return current_grid_path

func get_path_version() -> int:
	return path_version
