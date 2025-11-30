extends Node3D
# Tower1.gd - Basic tower that rotates turret and shoots at enemies
#Tower 1 (Basic): 100 gold
#Tower 2 (Slow): 150 gold
#Tower 3 (AoE): 200 gold
#Tower 4 (Anti-Air): 175 gold
#Tower 5 (Ice): 125 gold
#Tower 6 (Pulse): 250 gold
# Tower stats
@export var tower_cost: int = 100  # Cost in gold to place this tower
@export var attack_range: float = 8.0
@export var damage: int = 10
@export var fire_rate: float = 1.0  # Shots per second
@export var rotation_speed: float = 5.0
@export var tower_level: int = 0  # Upgrade level (0 = base, 1-3 = upgraded)
@export var is_pulse_tower: bool = false  # Add this at top
# Special abilities
@export_group("Special Abilities")
@export var applies_slow: bool = false
@export var slow_amount: float = 0.5  # Multiplier (0.5 = 50% speed)
@export var slow_duration: float = 2.0  # Seconds

@export var area_of_effect: bool = false
@export var aoe_radius: float = 3.0  # Damage radius around target

@export var flying_only: bool = false  # Only targets flying enemies

@export_group("Projectile Settings")
@export_enum("None", "Bullet", "Missile", "Ice", "Pulse") var projectile_type: String = "None"
@export var projectile_speed: float = 20.0  # Speed for bullets/missiles
@export var projectile_scale: float = 1.0  # Size multiplier for projectile

# References
var turret: Node3D = null
var barrel: Node3D = null 
var barrel_left: Node3D = null  # For dual barrel towers
var barrel_right: Node3D = null
var current_barrel: int = 0
var current_target: Node3D = null
var fire_timer: float = 0.0
var kill_count: int = 0
# Range indicator (for debugging/visualization)
var range_indicator: MeshInstance3D

# Upgrade level indicators
var level_lights: Array = []

func _ready():
	# Find the turret node
	turret = get_node_or_null("Turret")
	if not turret:
		push_error("Tower: No 'Turret' node found! Make sure you named it 'Turret'")
		# Find the barrel node
	barrel = get_node_or_null("Turret/Barrel")  # ADD THIS
	if not barrel:
		push_error("Tower: No 'Barrel' node found! Recoil animation won't work")
	if not barrel:
		barrel_left = get_node_or_null("Turret/BarrelLeft")
		barrel_right = get_node_or_null("Turret/BarrelRight")
	# Create range indicator
	create_range_indicator()
	# ADD THESE FOR PULSE TOWER
		# Only run for pulse tower
	# Only pulse towers get this animation
	if projectile_type == "Pulse":
		#create_pulse_idle_rotation()
		create_pulse_idle_glow()
	# Create level indicator lights
	create_level_lights()
	
	# Add to towers group so enemies can find us
	add_to_group("towers")

func _process(delta):
	if get_tree().paused:
		return
		
	if projectile_type == "Pulse" and turret:
		turret.rotate_y(delta * 1.5)  
	# Update fire timer
	fire_timer += delta
	
	# Find and track target
	update_target()
	
	if current_target and turret:
		# Rotate turret toward target
		rotate_turret_to_target(delta)
		
		# Shoot if ready
		if fire_timer >= 1.0 / fire_rate:
			shoot_at_target()
			fire_timer = 0.0


func update_target():
	# Find all enemies
	var enemies = get_tree().get_nodes_in_group("enemies")
	
	# Filter to only those in range
	var enemies_in_range = []
	for enemy in enemies:
		if enemy and is_instance_valid(enemy):
			# Check if this tower only targets flying enemies
			if flying_only:
				# Skip if enemy is not flying
				if not enemy.get("is_flying"):
					continue
			
			var distance = global_position.distance_to(enemy.global_position)
			if distance <= attack_range:
				enemies_in_range.append(enemy)
	
	if enemies_in_range.size() == 0:
		current_target = null
		return
	
	# Target the closest enemy
	var closest = enemies_in_range[0]
	var closest_dist = global_position.distance_to(closest.global_position)
	
	for enemy in enemies_in_range:
		var dist = global_position.distance_to(enemy.global_position)
		if dist < closest_dist:
			closest = enemy
			closest_dist = dist
	
	current_target = closest

func rotate_turret_to_target(delta):
	if not current_target or not turret:
		return
	if projectile_type == "Pulse":
		return
	# Get direction to target (flatten to XZ plane for rotation)
	var target_pos = current_target.global_position
	var turret_pos = turret.global_position
	var direction = Vector3(target_pos.x - turret_pos.x, 0, target_pos.z - turret_pos.z)
	
	if direction.length() < 0.01:
		return
	
	direction = direction.normalized()
	
	# Calculate target rotation
	var target_rotation = atan2(direction.x, direction.z)
	
	# Smoothly rotate toward target
	var current_y_rotation = turret.rotation.y
	turret.rotation.y = lerp_angle(current_y_rotation, target_rotation, rotation_speed * delta)

func shoot_at_target():
	if not current_target:
		return
	
	# Determine which barrel to use
	var active_barrel = get_active_barrel()
	
	# Create recoil
	if active_barrel:
		create_barrel_recoil(active_barrel)
	
	# Launch projectile
	match projectile_type:
		"Bullet":
			launch_bullet(current_target, active_barrel)
		"Missile":
			launch_missile(current_target, active_barrel)
		"Ice":
			launch_ice(current_target, active_barrel)
		"Pulse":
			create_damage_pulse()
		"None":
			apply_damage_to_target(current_target)
	
	# If dual barrel, alternate for next shot
	if barrel_left and barrel_right:
		current_barrel = 1 - current_barrel
	
	# Visual effect for instant hit towers
	#if projectile_type == "None" or projectile_type == "Pulse":
	#	create_shot_effect()
func get_active_barrel() -> Node3D:
	# Single barrel tower
	if barrel:
		return barrel
	
	# Dual barrel tower - return active barrel
	if barrel_left and barrel_right:
		return barrel_left if current_barrel == 0 else barrel_right
	
	# Fallback to just left if only one exists
	if barrel_left:
		return barrel_left
	if barrel_right:
		return barrel_right
	
	return null
func create_barrel_recoil(active_barrel: Node3D = null):
	if not active_barrel:
		return
	
	# Store original position
	var original_pos = active_barrel.position
	
	# Recoil backwards along barrel's local Z axis
	var recoil_distance = 0.3  # Adjust based on your barrel length
	var recoil_pos = original_pos + Vector3(0, 0, -recoil_distance)  # Local space
	
	var tween = create_tween()
	tween.tween_property(active_barrel, "position", recoil_pos, 0.05)  # Quick snap back
	tween.tween_property(active_barrel, "position", original_pos, 0.15)  # Return smoothly
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_ELASTIC)  # Slight bounce for realism
func create_shot_effect():
	# Simple visual feedback - create a quick flash
	if not turret:
		return
	
	var flash = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	flash.mesh = sphere
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 0.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 1.0, 0.0)
	mat.emission_energy_multiplier = 2.0
	flash.set_surface_override_material(0, mat)
	
	# Position at turret tip
	flash.global_position = turret.global_position + turret.global_transform.basis.z * 0.8
	get_parent().add_child(flash)
	
	# Remove after short delay
	await get_tree().create_timer(0.1).timeout
	flash.queue_free()

func create_range_indicator():
	range_indicator = MeshInstance3D.new()
	
	# Create a flat cylinder to show range
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = attack_range
	cylinder.bottom_radius = attack_range
	cylinder.height = 0.05
	range_indicator.mesh = cylinder
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.8, 0.3, 0.2)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	range_indicator.set_surface_override_material(0, mat)
	
	range_indicator.position.y = 0.1
	range_indicator.visible = false  # Hidden by default
	add_child(range_indicator)

func show_range():
	if range_indicator:
		range_indicator.visible = true

func hide_range():
	if range_indicator:
		range_indicator.visible = false

func update_range_indicator():
	# Update the range indicator size when attack_range changes
	if range_indicator:
		var cylinder = range_indicator.mesh as CylinderMesh
		if cylinder:
			cylinder.top_radius = attack_range
			cylinder.bottom_radius = attack_range
		print("Tower range indicator updated to ", attack_range)

func create_level_lights():
	# Create 3 small cube lights on top of tower
	for i in range(3):
		var light = MeshInstance3D.new()
		var cube = BoxMesh.new()
		cube.size = Vector3(0.2, 0.2, 0.2)
		light.mesh = cube
		
		# Create material for the light
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.2, 0.2, 0.3)  # Dark and transparent when off
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA  # Enable transparency
		mat.emission_enabled = true
		mat.emission = Color(0.1, 0.1, 0.1)
		mat.emission_energy_multiplier = 0.1
		light.set_surface_override_material(0, mat)
		
		# Position lights in a row on top of tower
		var offset = (i - 1) * 0.3  # -0.3, 0, 0.3
		light.position = Vector3(offset, 2.5, 0)
		
		add_child(light)
		level_lights.append(light)
	
	# Update lights based on current level
	update_level_lights()

func update_level_lights():
	# Light up cubes based on tower level
	for i in range(3):
		if i < level_lights.size():
			var light = level_lights[i]
			var mat = light.get_surface_override_material(0)
			
			if i < tower_level:
				# Light is ON - bright cyan/blue glow (opaque)
				mat.albedo_color = Color(0.3, 0.8, 1.0, 1.0)
				mat.emission = Color(0.3, 0.8, 1.0)
				mat.emission_energy_multiplier = 3.0
			else:
				# Light is OFF - dark and transparent
				mat.albedo_color = Color(0.2, 0.2, 0.2, 0.3)
				mat.emission = Color(0.1, 0.1, 0.1)
				mat.emission_energy_multiplier = 0.1

func apply_damage_to_target(target: Node3D):
	if not target or not is_instance_valid(target):
		return
	
	# Area of Effect damage
	if area_of_effect:
		# Find all enemies within AoE radius of target
		var enemies = get_tree().get_nodes_in_group("enemies")
		var hit_count = 0
		
		for enemy in enemies:
			if enemy and is_instance_valid(enemy):
				var distance = target.global_position.distance_to(enemy.global_position)
				if distance <= aoe_radius:
					# Deal damage
					if enemy.has_method("take_damage"):
						target.take_damage(damage, self)
						hit_count += 1
					
					# Apply slow if this tower slows
					if applies_slow and enemy.has_method("apply_slow"):
						enemy.apply_slow(slow_amount, slow_duration)
		
		print("Tower (AoE): Hit ", hit_count, " enemies for ", damage, " damage each")
		
	else:
		# Single target damage
		if target.has_method("take_damage"):
			target.take_damage(damage, self)  # Pass tower reference
			print("Tower: Shot enemy for ", damage, " damage")
	
		# Apply slow if this tower slows
		if applies_slow and target.has_method("apply_slow"):
			target.apply_slow(slow_amount, slow_duration)
			print("Tower: Applied slow (", slow_amount, "x speed for ", slow_duration, "s)")

# PROJECTILE FUNCTIONS

func launch_bullet(target: Node3D, active_barrel: Node3D = null):
	if not turret:
		return
	
	var projectile_script = load("res://projectile.gd")
	if not projectile_script:
		push_error("Tower: projectile.gd not found!")
		return
	
	var bullet = Node3D.new()
	var mesh_instance = MeshInstance3D.new()
	
	var cube = BoxMesh.new()
	cube.size = Vector3(0.2, 0.2, 0.2) * projectile_scale
	mesh_instance.mesh = cube
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.9, 0.3)
	mat.emission_energy_multiplier = 2.0
	mesh_instance.set_surface_override_material(0, mat)
	
	bullet.add_child(mesh_instance)
	
	# Spawn from active barrel
	var spawn_pos
	if active_barrel:
		spawn_pos = active_barrel.global_position + active_barrel.global_transform.basis.z * 1.0
	else:
		# Fallback to turret center
		spawn_pos = turret.global_position + turret.global_transform.basis.z * 0.8
	
	bullet.set_script(projectile_script)
	bullet.set_meta("target", target)
	bullet.set_meta("speed", projectile_speed)
	bullet.set_meta("tower", self)
	bullet.set_meta("projectile_type", "bullet")
	
	get_parent().add_child(bullet)
	bullet.global_position = spawn_pos

func launch_missile(target: Node3D, _active_barrel: Node3D = null):
	if not turret:
		return
	
	# Create projectile script
	var projectile_script = load("res://projectile.gd")
	if not projectile_script:
		push_error("Tower: projectile.gd not found!")
		return
	
	var missile = Node3D.new()
	var mesh_instance = MeshInstance3D.new()
	
	# Elongated cube for missile
	var cube = BoxMesh.new()
	cube.size = Vector3(0.3, 0.3, 0.8) * projectile_scale
	mesh_instance.mesh = cube
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.2, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.0)
	mat.emission_energy_multiplier = 1.5
	mesh_instance.set_surface_override_material(0, mat)
	
	missile.add_child(mesh_instance)
	#missile.global_position = turret.global_position + turret.global_transform.basis.z * 0.8
	var spawn_pos = turret.global_position + turret.global_transform.basis.z * 0.8
	# Add script first
	missile.set_script(projectile_script)
	
	# Store target reference on missile
	missile.set_meta("target", target)
	missile.set_meta("speed", projectile_speed)
	missile.set_meta("tower", self)
	missile.set_meta("projectile_type", "missile")
	
	get_parent().add_child(missile)
	missile.global_position = spawn_pos
func launch_ice(target: Node3D, _active_barrel: Node3D = null):
	if not turret:
		return
	
	# Create projectile script
	var projectile_script = load("res://projectile.gd")
	if not projectile_script:
		push_error("Tower: projectile.gd not found!")
		return
	
	var ice = Node3D.new()
	var mesh_instance = MeshInstance3D.new()
	
	# Crystal cube for ice
	var cube = BoxMesh.new()
	cube.size = Vector3(0.25, 0.25, 0.25) * projectile_scale
	mesh_instance.mesh = cube
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.7, 1.0, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.9, 1.0)
	mat.emission_energy_multiplier = 1.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.set_surface_override_material(0, mat)
	
	ice.add_child(mesh_instance)
	#ice.global_position = turret.global_position + turret.global_transform.basis.z * 0.8
	var spawn_pos = turret.global_position + turret.global_transform.basis.z * 0.8
	
	# Add script first
	ice.set_script(projectile_script)
	
	# Store target reference on ice projectile
	ice.set_meta("target", target)
	ice.set_meta("speed", projectile_speed * 1.2)  # Ice slightly faster
	ice.set_meta("tower", self)
	ice.set_meta("projectile_type", "ice")
	
	get_parent().add_child(ice)
	ice.global_position = spawn_pos
func create_damage_pulse():
	# Create expanding damage pulse from tower base - flat square
	var pulse = MeshInstance3D.new()
	var cube = BoxMesh.new()
	cube.size = Vector3(1.0, 0.1, 1.0)  # Flat square with thin height
	pulse.mesh = cube
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.3, 1.0, 0.6)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 1.0)
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pulse.set_surface_override_material(0, mat)
	
	# Position at tower base
	pulse.position = Vector3(0, 0.1, 0)  # Just above ground
	
	add_child(pulse)  # Add as child of tower
	
	# Damage all enemies in range immediately
	var enemies = get_tree().get_nodes_in_group("enemies")
	var hit_count = 0
	
	for enemy in enemies:
		if enemy and is_instance_valid(enemy):
			var distance = global_position.distance_to(enemy.global_position)
			if distance <= attack_range:
				apply_damage_to_target(enemy)
				hit_count += 1
	
	print("Tower (Pulse): Hit ", hit_count, " enemies")
	
	# Animate pulse expanding outward (scale X and Z, keep Y thin)
	var max_scale = attack_range  # Scale to match the range exactly
	var tween = get_tree().create_tween()
	tween.tween_property(pulse, "scale", Vector3(max_scale, 1.0, max_scale), 0.6)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.6)
	tween.finished.connect(func():
		if is_instance_valid(pulse):
			pulse.queue_free()
	)
func create_pulse_idle_rotation():
	if not turret:
		return
	
	# Smooth continuous rotation
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(turret, "rotation:y", TAU, 4.0)  # Full rotation every 4 seconds
	tween.set_trans(Tween.TRANS_LINEAR)  # Constant speed
	tween.finished.connect(func():
		if is_instance_valid(turret):
			turret.rotation.y = 0  # Reset to prevent float drift
	)
func create_pulse_idle_glow():
	if not turret:
		return
	
	# Find the cube mesh in the turret
	var cube_mesh = find_mesh_in_children(turret)
	if not cube_mesh:
		return
	
	var mat = cube_mesh.get_surface_override_material(0)
	if not mat:
		# Try to get material from mesh
		mat = cube_mesh.mesh.surface_get_material(0)
		if mat:
			# Create a copy we can animate
			mat = mat.duplicate()
			cube_mesh.set_surface_override_material(0, mat)
	
	if not mat:
		return
	
	# Pulse the emission intensity
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(mat, "emission_energy_multiplier", 1.0, 1.0)
	tween.tween_property(mat, "emission_energy_multiplier", 3.0, 1.0)
	tween.set_ease(Tween.EASE_IN_OUT)

func find_mesh_in_children(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	
	for child in node.get_children():
		var result = find_mesh_in_children(child)
		if result:
			return result
	
	return null
