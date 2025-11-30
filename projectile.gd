extends Node3D
# Projectile.gd - Handles bullet/missile/ice projectile movement

var target: Node3D = null
var speed: float = 20.0
var tower: Node3D = null
var projectile_type: String = "bullet"
var lifetime: float = 5.0  # Max lifetime before auto-destroy
var smoke_trail: GPUParticles3D = null
func _ready():
	# Get metadata set by tower
	if has_meta("target"):
		target = get_meta("target")
	if has_meta("speed"):
		speed = get_meta("speed")
	if has_meta("tower"):
		tower = get_meta("tower")
	if has_meta("projectile_type"):
		projectile_type = get_meta("projectile_type")
		
	# Create smoke trail for missiles
	if projectile_type == "missile":
		create_smoke_trail()
	# Start lifetime countdown
	await get_tree().create_timer(lifetime).timeout
	if is_instance_valid(self):
		queue_free()

func _process(delta):
	if not target or not is_instance_valid(target):
		if projectile_type == "missile":
			create_missile_impact()
		queue_free()
		return
	
	# Get target position
	var target_pos = target.global_position
	
	# Only add height offset for ground enemies
	if not target.get("is_flying"):
		target_pos += Vector3(0, 0.5, 0)
	
	# Move toward target
	var direction = (target_pos - global_position).normalized()
	var distance = global_position.distance_to(target_pos)
	
	# Rotate to face direction
	if direction.length() > 0.01:
		look_at(target_pos, Vector3.UP)
	
	# Move
	var move_distance = speed * delta
	
	if distance <= move_distance or distance < 0.5:
		# Hit target!
		hit_target()
		return
	
	global_position += direction * move_distance
	
	# Add rotation spin for visual effect
	if projectile_type == "ice":
		rotate_y(delta * 10)

func hit_target():
	var ink_pos = global_position  
	#spawn_ink_splash(ink_pos)
	print("HIT_TARGET CALLED!")

	if not tower or not is_instance_valid(tower):
		queue_free()
		return

	# Apply damage through tower's damage system
	if tower.has_method("apply_damage_to_target"):
		tower.apply_damage_to_target(target)

	# Create impact effect based on projectile type
	create_impact_effect()

	# Remove projectile
	queue_free()

func create_impact_effect():
	match projectile_type:
		"bullet":
			create_bullet_impact()
		"missile":
			create_missile_impact()
		"ice":
			create_ice_impact()

func create_bullet_impact():
	# Small yellow cube burst
	var spark = MeshInstance3D.new()
	var cube = BoxMesh.new()
	cube.size = Vector3(0.6, 0.6, 0.6)
	spark.mesh = cube
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.188, 0.184, 0.384, 1.0)
	mat.emission_energy_multiplier = 5.0
	spark.set_surface_override_material(0, mat)
	
	# Store position before adding to tree
	var impact_pos = global_position
	get_parent().add_child(spark)
	spark.global_position = impact_pos  # Set position AFTER adding to tree
	
	# Animate scale down and fade
	var tween = get_tree().create_tween()
	tween.tween_property(spark, "scale", Vector3(0, 0, 0), 0.1)
	tween.finished.connect(func(): 
		if is_instance_valid(spark):
			spark.queue_free()
	)
func create_missile_impact():
	var impact_position = global_position

	var explosion = MeshInstance3D.new()
	var cube = BoxMesh.new()
	explosion.mesh = cube
	cube.size = Vector3(1, 1, 1)

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.0, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.0)
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	mat = mat.duplicate()
	mat.resource_local_to_scene = true
	explosion.set_surface_override_material(0, mat)

	var explosion_pos = global_position
	#explosion.global_position = impact_position
	get_parent().add_child(explosion)
	explosion.global_position = explosion_pos 
	# Tween attached TO THE EXPLOSION itself!
	var tween = explosion.create_tween()
	tween.tween_property(explosion, "scale", Vector3(2.5, 2.5, 2.5), 0.3)
	tween.parallel().tween_property(explosion, "rotation", Vector3(PI, PI, PI), 0.3)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.3)

	tween.finished.connect(func():
		explosion.queue_free()
	)
func create_ice_impact():
	# Store position once at the start
	var impact_pos = global_position
	
	# Blue ice shatter - main cube
	var shatter = MeshInstance3D.new()
	var cube = BoxMesh.new()
	cube.size = Vector3(0.5, 0.5, 0.5)
	shatter.mesh = cube
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.7, 1.0, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.9, 1.0)
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shatter.set_surface_override_material(0, mat)
	
	get_parent().add_child(shatter)
	shatter.global_position = impact_pos  # ← Set AFTER add_child
	
	# Create ice cube shards
	for i in range(5):
		var shard = MeshInstance3D.new()
		var shard_cube = BoxMesh.new()
		shard_cube.size = Vector3(0.25, 0.25, 0.25)
		shard.mesh = shard_cube
		shard.set_surface_override_material(0, mat)
		
		var random_dir = Vector3(randf_range(-1, 1), randf_range(0.5, 1), randf_range(-1, 1)).normalized()
		
		get_parent().add_child(shard)
		shard.global_position = impact_pos  # ← Use stored position
		
		# Animate shards flying out
		var shard_tween = get_tree().create_tween()
		shard_tween.tween_property(shard, "global_position", impact_pos + random_dir * 1.5, 0.3)  # ← Use stored position
		shard_tween.parallel().tween_property(shard, "rotation", Vector3(randf() * TAU, randf() * TAU, randf() * TAU), 0.3)
		shard_tween.finished.connect(func():
			if is_instance_valid(shard):
				shard.queue_free()
		)
	
	# Clean up main shatter effect
	var main_tween = get_tree().create_tween()
	main_tween.tween_property(shatter, "scale", Vector3(0, 0, 0), 0.2)
	main_tween.finished.connect(func():
		if is_instance_valid(shatter):
			shatter.queue_free()
	)
	
func spawn_ink_splash(position: Vector3):
	var splash_parent = Node3D.new()
	get_tree().current_scene.add_child(splash_parent)

	var floor_pos = position
	floor_pos.y = 0.5
	splash_parent.global_position = floor_pos

	var droplet_count = 10 + randi() % 8

	for i in range(droplet_count):
		# Create RigidBody3D for physics
		var droplet = RigidBody3D.new()
		droplet.mass = 0.1
		droplet.gravity_scale = 0.3  # Light gravity
		
		# Create mesh
		var mesh_instance = MeshInstance3D.new()
		var cube_size = randf_range(0.1, 0.2)
		var cube = BoxMesh.new()
		cube.size = Vector3(cube_size, cube_size, cube_size)
		mesh_instance.mesh = cube

		var mat = StandardMaterial3D.new()
		#mat.albedo_color = Color(0, 0, 0, randf_range(0.6, 0.9))
		var cube_color = randf_range(0.0, 0.2)
		mat.albedo_color = Color(cube_color, cube_color, cube_color, randf_range(0.6, 0.9))
		#mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
		mesh_instance.material_override = mat

		droplet.add_child(mesh_instance)
		
		# Add collision shape
		var collision = CollisionShape3D.new()
		var box_shape = BoxShape3D.new()
		box_shape.size = Vector3(cube_size, cube_size, cube_size)
		collision.shape = box_shape
		droplet.add_child(collision)

		# Random splash spread
		var angle = randf() * TAU
		var radius = randf_range(0.2, 1.2)

		droplet.position = Vector3(
			cos(angle) * radius,
			randf_range(0.5, 1.0),  # Drop from height
			sin(angle) * radius
		)

		droplet.rotation_degrees = Vector3(randf() * 360, randf() * 360, randf() * 360)

		splash_parent.add_child(droplet)

		# Fade splatter
		var tween = splash_parent.create_tween()
		tween.tween_property(mat, "albedo_color:a", 0.0, 6.0)

	# Cleanup
	var cleanup = splash_parent.create_tween()
	cleanup.tween_interval(6.2)
	cleanup.finished.connect(func():
		if splash_parent:
			splash_parent.queue_free()
	)
	
func create_smoke_trail():
	smoke_trail = GPUParticles3D.new()
	smoke_trail.emitting = true
	smoke_trail.amount = 40
	smoke_trail.lifetime = 1.0
	smoke_trail.local_coords = false  # Trail stays in world space
	
	var particle_mat = ParticleProcessMaterial.new()
	particle_mat.direction = Vector3(0, 0, 0)  # Emit in all directions
	particle_mat.spread = 20.0
	particle_mat.initial_velocity_min = 0.5
	particle_mat.initial_velocity_max = 1.0
	particle_mat.gravity = Vector3(0, -3.0, 0)
	particle_mat.scale_min = 0.2
	particle_mat.scale_max = 0.4
	
	# Gray smoke that fades
	var gradient = Gradient.new()
	gradient.set_color(0, Color(0.3, 0.3, 0.3, 0.8))
	gradient.set_color(1, Color(0.2, 0.2, 0.2, 0.0))
	var gradient_texture = GradientTexture1D.new()
	gradient_texture.gradient = gradient
	particle_mat.color_ramp = gradient_texture
	
	smoke_trail.process_material = particle_mat
	
	# Use small cube mesh for smoke puffs
	var cube_mesh = BoxMesh.new()
	cube_mesh.size = Vector3(0.3, 0.3, 0.3)
	smoke_trail.draw_pass_1 = cube_mesh
	
	add_child(smoke_trail)
