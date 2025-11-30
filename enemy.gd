extends Node3D
# Enemy.gd - Configurable enemy that follows the path

# Signals
signal enemy_died(enemy)
signal enemy_reached_goal(damage)

# Enemy stats - these can be set per enemy type
@export var max_health: int = 100
@export var move_speed: float = 3.0
@export var is_flying: bool = false
@export var gold_reward: int = 10
@export var damage_to_player: int = 1

@export_group("Visual Effects")
@export var enable_smoke_trail: bool = true
@export var enable_death_shatter: bool = true
@export var shatter_cube_count: int = 10  # How many cubes to shatter into
@export var shatter_cube_size: float = 0.25  # Size of each cube
@export var shatter_cube_color_1: Color = Color(0.0, 0.0, 0.0)  # First cube color (black)
@export var shatter_cube_color_2: Color = Color(1.0, 0.0, 0.0)  # Second cube color (red, emissive)
@export var shatter_fade_time: float = 2.0  # How long cubes stay before fading
@export var enable_slow_particles: bool = true
@export var enable_damage_sparks: bool = true

var health: int = 100
var base_move_speed: float = 3.0
var rotation_speed: float = 8.0

# Slow effect tracking
var is_slowed: bool = false
var slow_timer: float = 0.0

var path: PackedVector3Array = PackedVector3Array()
var current_waypoint: int = 0
var is_alive: bool = true
var path_system: Node3D = null
var grid: Node3D = null
var my_path_version: int = 0

# Flying enemy direct path
var goal_position: Vector3 = Vector3.ZERO
var flying_height: float = 3.0

# Visual
var mesh_instance: MeshInstance3D
var original_material: StandardMaterial3D
var health_bar_bg: MeshInstance3D
var health_bar_fg: MeshInstance3D
var smoke_particles: GPUParticles3D
var slow_particles: GPUParticles3D
var last_tower_hit: Node3D = null
func _ready():
	health = max_health
	base_move_speed = move_speed
	add_to_group("enemies")
	
	# Find mesh instance in children
	mesh_instance = find_mesh_instance(self)
	if mesh_instance:
		var mat = mesh_instance.get_surface_override_material(0)
		if not mat and mesh_instance.mesh:
			mat = mesh_instance.mesh.surface_get_material(0)
		if mat:
			original_material = mat
	
	# Create health bar
	create_health_bar()
	
	# Create particle effects
	if enable_smoke_trail:
		create_smoke_trail()
	if enable_slow_particles:
		create_slow_particles()

func find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var result = find_mesh_instance(child)
		if result:
			return result
	return null

func set_path(new_path: PackedVector3Array, path_sys: Node3D = null):
	path = new_path
	current_waypoint = 0
	path_system = path_sys
	if path_system:
		my_path_version = path_system.get_path_version()
	
	# If flying, set goal position and fly higher
	if is_flying:
		if path.size() > 0:
			goal_position = path[path.size() - 1]  # Last point in path is the goal
			position = path[0]
			position.y = flying_height  # Start at flying height
	else:
		# Ground units use normal path
		if path.size() > 0:
			position = path[0]

func _process(delta):
	
	if get_tree().paused:
		return
	if not is_alive:
		return
	
	# Update slow timer
	if is_slowed:
		slow_timer -= delta
		if slow_timer <= 0:
			remove_slow()
	
	# Update health bar
	update_health_bar()
	
	# Flying enemies move straight to goal
	if is_flying:
		move_flying_to_goal(delta)
		return
	
	# Ground enemies follow path
	# Check if path has been recalculated
	if path_system and path_system.get_path_version() != my_path_version:
		#print("Enemy: Path version changed from ", my_path_version, " to ", path_system.get_path_version())
		var new_path = path_system.get_enemy_path()
		if new_path.size() > 0:
			# Find closest waypoint on new path
			var closest_idx = 0
			var closest_dist = INF
			for i in range(new_path.size()):
				var dist = position.distance_to(new_path[i])
				if dist < closest_dist:
					closest_dist = dist
					closest_idx = i
			path = new_path
			current_waypoint = closest_idx
			my_path_version = path_system.get_path_version()
			#print("Enemy: Switched to new path at waypoint ", closest_idx)
	
	if path.size() == 0 or current_waypoint >= path.size():
		reach_goal()
		return
	
	# Move toward current waypoint
	var target = path[current_waypoint]
	target.y = position.y  # Keep same height
	
	var direction = (target - position).normalized()
	var distance = position.distance_to(target)
	
	if distance < move_speed * delta:
		# Reached waypoint, move to next
		position = target
		current_waypoint += 1
	else:
		# Move toward waypoint
		position += direction * move_speed * delta
	
	# Smoothly rotate to face movement direction
	if direction.length() > 0.01:
		# Calculate the angle to face the direction
		var target_angle = atan2(direction.x, direction.z)
		# Smoothly interpolate to target angle
		rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)

func move_flying_to_goal(delta):
	# Flying enemies move in straight line to goal at higher altitude
	if goal_position == Vector3.ZERO:
		reach_goal()
		return
	
	# Maintain flying height
	var target = goal_position
	target.y = flying_height
	
	var direction = (target - position).normalized()
	var distance = position.distance_to(target)
	
	# Check if reached goal
	if distance < move_speed * delta or distance < 1.0:
		reach_goal()
		return
	
	# Move toward goal
	position += direction * move_speed * delta
	
	# Rotate to face goal
	if direction.length() > 0.01:
		var target_angle = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)


func take_damage(amount: int, from_tower: Node3D = null):
	if not is_alive:
		return
	health -= amount
	
	# Track which tower last hit us
	if from_tower:
		last_tower_hit = from_tower
	
	#print("Enemy took ", amount, " damage. Health: ", health)
	
	# Show floating damage number
	create_damage_number(amount)
	
	# Damage sparks effect
	if enable_damage_sparks:
		create_damage_sparks()
	
	# Visual feedback - flash red
	if mesh_instance and original_material:
		var flash_mat = StandardMaterial3D.new()
		flash_mat.albedo_color = Color(1.0, 0.0, 0.0)
		flash_mat.emission_enabled = true
		flash_mat.emission = Color(1.0, 0.0, 0.0)
		flash_mat.emission_energy_multiplier = 1.0
		mesh_instance.set_surface_override_material(0, flash_mat)
		
		# Reset material after flash
		await get_tree().create_timer(0.1).timeout
		if mesh_instance:
			mesh_instance.set_surface_override_material(0, original_material)
	
	if health <= 0:
		die()

func die():
	if not is_alive:
		return
	
	is_alive = false
	#print("Enemy died!")
	
		# Increment kill count for the tower that killed us
	if last_tower_hit and is_instance_valid(last_tower_hit):
		if last_tower_hit.get("kill_count") != null:
			last_tower_hit.kill_count += 1
	# Emit signal before death effects
	enemy_died.emit(self)
	var death_position = global_position  # Store position before removal
	
	# Death shatter effect
	if enable_death_shatter:
		create_death_shatter(death_position)
	
	# Remove enemy after short delay to show effect
	await get_tree().create_timer(0.3).timeout  # Increased from 0.1 to 0.3
	queue_free()

func reach_goal():
	# Enemy reached the end - player loses life
	#print("Enemy reached goal! Dealing ", damage_to_player, " damage")
	enemy_reached_goal.emit(damage_to_player)
	queue_free()

func apply_slow(slow_multiplier: float, duration: float):
	if is_slowed:
		# Refresh duration if already slowed
		slow_timer = max(slow_timer, duration)
		return
	
	is_slowed = true
	slow_timer = duration
	move_speed = base_move_speed * slow_multiplier
	
	# Visual feedback - make enemy blue-ish when slowed
	if mesh_instance and original_material:
		var slow_mat = StandardMaterial3D.new()
		slow_mat.albedo_color = Color(0.3, 0.5, 1.0)
		slow_mat.emission_enabled = true
		slow_mat.emission = Color(0.3, 0.5, 1.0)
		slow_mat.emission_energy_multiplier = 0.3
		mesh_instance.set_surface_override_material(0, slow_mat)
	
	# Enable slow particles
	if slow_particles and enable_slow_particles:
		slow_particles.emitting = true
	
	#print("Enemy slowed to ", move_speed, " for ", duration, " seconds")

func remove_slow():
	is_slowed = false
	move_speed = base_move_speed
	
	# Restore original material
	if mesh_instance and original_material:
		mesh_instance.set_surface_override_material(0, original_material)
	
	# Disable slow particles
	if slow_particles:
		slow_particles.emitting = false
	
	#print("Enemy slow effect ended")

func create_health_bar():
	# Create background (dark red/black bar)
	health_bar_bg = MeshInstance3D.new()
	var bg_mesh = BoxMesh.new()
	bg_mesh.size = Vector3(1.0, 0.15, 0.05)
	health_bar_bg.mesh = bg_mesh
	
	var bg_mat = StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.2, 0.0, 0.0)
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	health_bar_bg.set_surface_override_material(0, bg_mat)
	
	health_bar_bg.position = Vector3(0, 2.0, 0)
	add_child(health_bar_bg)
	
	# Create foreground (red bar)
	health_bar_fg = MeshInstance3D.new()
	var fg_mesh = BoxMesh.new()
	fg_mesh.size = Vector3(0.98, 0.13, 0.06)  # Slightly smaller than background
	health_bar_fg.mesh = fg_mesh
	
	var fg_mat = StandardMaterial3D.new()
	fg_mat.albedo_color = Color(1.0, 0.0, 0.0)
	fg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	health_bar_fg.set_surface_override_material(0, fg_mat)
	
	health_bar_fg.position = Vector3(0, 2.0, 0)
	add_child(health_bar_fg)
# Get the target position for projectiles (adjusted for flying enemies)
func get_target_position() -> Vector3:
	if is_flying:
		# For flying enemies, return a position at ground level
		var target_pos = global_position
		target_pos.y = 0.5  # Hit at base level, not at flying height
		return target_pos
	else:
		# For ground enemies, return center position
		return global_position
#func update_health_bar():
	#if not health_bar_fg or not health_bar_bg:
		#return
	#
	## Calculate health percentage
	#var health_percent = float(health) / float(max_health)
	#health_percent = clamp(health_percent, 0.0, 1.0)
	#
	## Update foreground bar scale
	#health_bar_fg.scale.x = health_percent
	#
	## Position health bars above enemy
	#health_bar_bg.position = Vector3(0, 2.0, 0)
	#
	## Offset position so it shrinks from the right
	#var offset = (1.0 - health_percent) * 0.49  # Half of 0.98 width
	#health_bar_fg.position = Vector3(-offset, 2.0, 0)
func update_health_bar():
	if not health_bar_fg or not health_bar_bg:
		return
	
	# Calculate health percentage
	var health_percent = float(health) / float(max_health)
	health_percent = clamp(health_percent, 0.0, 1.0)
	
	# Update foreground bar scale
	health_bar_fg.scale.x = health_percent
	
	# Position health bars - for flying enemies, show below the model
	var bar_y_pos = 2.0
	if is_flying:
		bar_y_pos = -0.5  # Below the flying model
	
	health_bar_bg.position = Vector3(0, bar_y_pos, 0)
	
	# Offset position so it shrinks from the right
	var offset = (1.0 - health_percent) * 0.49  # Half of 0.98 width
	health_bar_fg.position = Vector3(-offset, bar_y_pos, 0)
# PARTICLE EFFECT FUNCTIONS

func create_smoke_trail():
	smoke_particles = GPUParticles3D.new()
	smoke_particles.emitting = true
	smoke_particles.amount = 20
	smoke_particles.lifetime = 1.0
	smoke_particles.explosiveness = 0.0
	
	# Create particle material
	var particle_mat = ParticleProcessMaterial.new()
	particle_mat.direction = Vector3(0, 1, 0)
	particle_mat.spread = 20.0
	particle_mat.initial_velocity_min = 0.5
	particle_mat.initial_velocity_max = 1.0
	particle_mat.gravity = Vector3(0, 0.5, 0)
	particle_mat.scale_min = 0.1
	particle_mat.scale_max = 0.3
	
	# Color gradient (dark grey to transparent)
	var gradient = Gradient.new()
	gradient.set_color(0, Color(0.3, 0.3, 0.3, 0.6))
	gradient.set_color(1, Color(0.2, 0.2, 0.2, 0.0))
	var gradient_texture = GradientTexture1D.new()
	gradient_texture.gradient = gradient
	particle_mat.color_ramp = gradient_texture
	
	smoke_particles.process_material = particle_mat
	
	# Use cube mesh for particles
	var cube_mesh = BoxMesh.new()
	cube_mesh.size = Vector3(0.1, 0.1, 0.1)
	smoke_particles.draw_pass_1 = cube_mesh
	
	smoke_particles.position = Vector3(0, 0.2, 0)
	add_child(smoke_particles)

func create_slow_particles():
	slow_particles = GPUParticles3D.new()
	slow_particles.emitting = false  # Only emit when slowed
	slow_particles.amount = 30
	slow_particles.lifetime = 0.8
	
	var particle_mat = ParticleProcessMaterial.new()
	particle_mat.direction = Vector3(0, 1, 0)
	particle_mat.spread = 45.0
	particle_mat.initial_velocity_min = 1.0
	particle_mat.initial_velocity_max = 2.0
	particle_mat.gravity = Vector3(0, -2.0, 0)
	particle_mat.scale_min = 0.1
	particle_mat.scale_max = 0.2
	
	# Blue/cyan color for ice
	var gradient = Gradient.new()
	gradient.set_color(0, Color(0.3, 0.7, 1.0, 0.8))
	gradient.set_color(1, Color(0.5, 0.9, 1.0, 0.0))
	var gradient_texture = GradientTexture1D.new()
	gradient_texture.gradient = gradient
	particle_mat.color_ramp = gradient_texture
	
	slow_particles.process_material = particle_mat
	
	# Use cube mesh for particles
	var cube_mesh = BoxMesh.new()
	cube_mesh.size = Vector3(0.1, 0.1, 0.1)
	slow_particles.draw_pass_1 = cube_mesh
	
	slow_particles.position = Vector3(0, 0.5, 0)
	add_child(slow_particles)

func create_damage_sparks():
	var sparks = GPUParticles3D.new()
	sparks.emitting = true
	sparks.one_shot = true
	sparks.amount = 20
	sparks.lifetime = 0.5
	sparks.explosiveness = 1.0
	
	var particle_mat = ParticleProcessMaterial.new()
	particle_mat.direction = Vector3(0, 1, 0)
	particle_mat.spread = 180.0
	particle_mat.initial_velocity_min = 3.0
	particle_mat.initial_velocity_max = 5.0
	particle_mat.gravity = Vector3(0, -9.8, 0)
	particle_mat.scale_min = 0.05
	particle_mat.scale_max = 0.1
	
	# Yellow/orange sparks
	var gradient = Gradient.new()
	gradient.set_color(0, Color(1.0, 0.9, 0.3, 1.0))
	gradient.set_color(1, Color(1.0, 0.5, 0.0, 0.0))
	var gradient_texture = GradientTexture1D.new()
	gradient_texture.gradient = gradient
	particle_mat.color_ramp = gradient_texture
	
	sparks.process_material = particle_mat
	
	# Use cube mesh for particles
	var cube_mesh = BoxMesh.new()
	cube_mesh.size = Vector3(0.05, 0.05, 0.05)
	sparks.draw_pass_1 = cube_mesh
	get_parent().add_child(sparks)
	sparks.global_position = global_position + Vector3(0, 0.5, 0)
	
	
	# Auto cleanup
	await get_tree().create_timer(sparks.lifetime + 0.1).timeout
	if is_instance_valid(sparks):
		sparks.queue_free()

func create_damage_number(damage: int):
	var damage_label = Label3D.new()
	damage_label.text = str(damage)
	damage_label.font_size = 32
	damage_label.pixel_size = 0.01
	damage_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	damage_label.no_depth_test = true
	damage_label.outline_size = 6
	damage_label.outline_modulate = Color(0, 0, 0, 1)
	
	# Color based on damage amount
	if damage >= 50:
		damage_label.modulate = Color(1.0, 0.3, 0.0, 1.0)  # Orange for high damage
	elif damage >= 20:
		damage_label.modulate = Color(1.0, 0.8, 0.0, 1.0)  # Yellow for medium damage
	else:
		damage_label.modulate = Color(1.0, 1.0, 1.0, 1.0)  # White for low damage
	
	# Calculate position BEFORE adding to tree
	var offset = Vector3(randf_range(-0.5, 0.5), 2.5, randf_range(-0.5, 0.5))
	var spawn_pos = global_position + offset
	
	# Add to tree FIRST
	get_parent().add_child(damage_label)
	
	# THEN set position
	damage_label.global_position = spawn_pos
	
	# Animate: float up and fade out
	var tween = get_tree().create_tween()
	tween.set_parallel(true)
	tween.tween_property(damage_label, "global_position", spawn_pos + Vector3(0, 2.0, 0), 1.0)
	tween.tween_property(damage_label, "modulate:a", 0.0, 1.0)
	tween.finished.connect(func():
		if is_instance_valid(damage_label):
			damage_label.queue_free()
	)

func create_death_shatter(death_pos: Vector3 = Vector3.ZERO):
	# Hide the original mesh
	if mesh_instance:
		mesh_instance.visible = false
	
	# If no position provided, try to get it
	if death_pos == Vector3.ZERO:
		if is_inside_tree():
			death_pos = global_position
		else:
			return  # Can't create shatter without position
	
	# Make sure cubes spawn above ground
	death_pos.y = max(death_pos.y, 0.5)  # Ensure at least 0.5 units above ground
	
	# Create cube fragments based on shatter_cube_count
	for i in range(shatter_cube_count):
		# Create RigidBody3D for physics
		var fragment = RigidBody3D.new()
		fragment.mass = 0.15  # Reduced from 0.5
		fragment.gravity_scale = 0.8  # Increased from 0.4 for faster settling
		fragment.linear_damp = 2.0  # Add damping to slow down movement
		fragment.angular_damp = 2.0  # Add damping to slow down rotation
		fragment.physics_material_override = PhysicsMaterial.new()
		fragment.physics_material_override.bounce = 0.1  # Very little bounce
		fragment.physics_material_override.friction = 0.4  # High friction
		
		# Create mesh
		var mesh_inst = MeshInstance3D.new()
		var cube = BoxMesh.new()
		cube.size = Vector3(shatter_cube_size, shatter_cube_size, shatter_cube_size)
		mesh_inst.mesh = cube
		
		# Randomly pick between color 1 or color 2
		var use_color_2 = randf() > 0.5
		var frag_mat = StandardMaterial3D.new()
		
		if use_color_2:
			# Color 2 with emission
			frag_mat.albedo_color = shatter_cube_color_2
			frag_mat.emission_enabled = true
			frag_mat.emission = Color(shatter_cube_color_2.r, shatter_cube_color_2.g, shatter_cube_color_2.b)
			frag_mat.emission_energy_multiplier = 1.0
		else:
			# Color 1 with emission so it's visible
			frag_mat.albedo_color = shatter_cube_color_1
			frag_mat.emission_enabled = true
			frag_mat.emission = Color(shatter_cube_color_1.r, shatter_cube_color_1.g, shatter_cube_color_1.b)
			frag_mat.emission_energy_multiplier = 0.5  # Dimmer than color 2
		
		frag_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh_inst.set_surface_override_material(0, frag_mat)
		
		fragment.add_child(mesh_inst)
		
		# Add collision shape
		var collision = CollisionShape3D.new()
		var box_shape = BoxShape3D.new()
		box_shape.size = Vector3(shatter_cube_size, shatter_cube_size, shatter_cube_size)
		collision.shape = box_shape
		fragment.add_child(collision)
		
		# Position cubes tightly around the enemy position (voxel grid style)
		var offset = Vector3(
			randf_range(-0.3, 0.3),
			randf_range(0.2, 0.8),  # Stack vertically above ground
			randf_range(-0.3, 0.3)
		)
		var fragment_pos = death_pos + offset
		#fragment.global_position = death_pos + offset
		
		# Give random initial rotation
		fragment.rotation = Vector3(
			randf_range(0, TAU),
			randf_range(0, TAU),
			randf_range(0, TAU)
		)
		
		# Add to scene
		get_parent().add_child(fragment)
		fragment.global_position = fragment_pos
		# Very gentle tumble as they fall (no outward force)
		await get_tree().process_frame
		if is_instance_valid(fragment):
			fragment.apply_torque_impulse(Vector3(
				randf_range(-0.3, 0.3),
				randf_range(-0.3, 0.3),
				randf_range(-0.3, 0.3)
			))
		
		# Fade out and remove after delay
		var tween = get_tree().create_tween()
		tween.tween_property(frag_mat, "albedo_color:a", 0.0, 0.5).set_delay(shatter_fade_time - 0.5)
		tween.tween_callback(func():
			if is_instance_valid(fragment):
				fragment.queue_free()
		)
