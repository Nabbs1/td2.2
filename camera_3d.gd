extends Camera3D

# Camera movement settings
@export var pan_speed: float = 20.0
@export var zoom_speed: float = 2.0
@export var rotation_speed: float = 2.0
@export var mouse_rotation_sensitivity: float = 0.3
@export var mouse_angle_sensitivity: float = 0.15
@export var camera_smoothing: float = 10.0

# Camera limits
@export var min_zoom: float = 5.0
@export var max_zoom: float = 30.0
@export var min_angle: float = 20.0
@export var max_angle: float = 80.0

# Camera target (the point we're looking at)
var target_position: Vector3 = Vector3.ZERO
var current_zoom: float = 30.0
var current_angle: float = 25.0
var camera_rotation: float = 0.0
# Tilt-shift / Depth of Field settings
@export var enable_tilt_shift: bool = true
@export var only_at_max_zoom: bool = true
@export var dof_focus_distance: float = 25.0
@export var dof_blur_amount: float = 0.15
@export var dof_far_offset: float = 20.0  # How much farther than focus to start blur
@export var dof_far_transition: float = 15.0
@export var dof_near_offset: float = 10.0  # How much closer than focus to start blur
@export var dof_near_transition: float = 8.0
# Mouse dragging
var is_panning: bool = false
var is_right_dragging: bool = false
var last_mouse_pos: Vector2
var right_click_start_pos: Vector2
var right_click_moved: bool = false

func _ready():
	# Set initial camera position and angle
	update_camera_transform()
		# Enable tilt-shift effect
	if enable_tilt_shift:
		attributes = CameraAttributesPractical.new()

func _process(delta):
	handle_keyboard_movement(delta)
	update_dof_based_on_zoom()  # ← Add this line

func update_dof_based_on_zoom():
	if not enable_tilt_shift or not attributes:
		return
	
	if only_at_max_zoom:
		# Only enable DOF when at or near max zoom
		var zoom_threshold = max_zoom - 2.0  # Enable within 2 units of max zoom
		var should_enable = current_zoom >= zoom_threshold
		
		if should_enable:
			attributes.dof_blur_far_enabled = true
			attributes.dof_blur_far_distance = dof_focus_distance + dof_far_offset
			attributes.dof_blur_far_transition = dof_far_transition
			
			attributes.dof_blur_near_enabled = true
			attributes.dof_blur_near_distance = dof_focus_distance - dof_near_offset
			attributes.dof_blur_near_transition = dof_near_transition
			
			attributes.dof_blur_amount = dof_blur_amount
		else:
			# Disable DOF when zoomed in
			attributes.dof_blur_far_enabled = false
			attributes.dof_blur_near_enabled = false
	else:
		# Always enabled mode
		attributes.dof_blur_far_enabled = true
		attributes.dof_blur_far_distance = dof_focus_distance + dof_far_offset
		attributes.dof_blur_far_transition = dof_far_transition
		
		attributes.dof_blur_near_enabled = true
		attributes.dof_blur_near_distance = dof_focus_distance - dof_near_offset
		attributes.dof_blur_near_transition = dof_near_transition
		
		attributes.dof_blur_amount = dof_blur_amount
func _input(event):
	# Mouse wheel zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			current_zoom = clamp(current_zoom - zoom_speed, min_zoom, max_zoom)
			update_camera_transform()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			current_zoom = clamp(current_zoom + zoom_speed, min_zoom, max_zoom)
			update_camera_transform()
		
		# Middle mouse button for panning
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			is_panning = event.pressed
			if event.pressed:
				last_mouse_pos = event.position
		
		# Right mouse button for camera rotation/angle
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				is_right_dragging = true
				last_mouse_pos = event.position  # Initialize last_mouse_pos here
				right_click_start_pos = event.position
				right_click_moved = false
			else:
				is_right_dragging = false
				# Only cancel tower selection if we didn't drag
				if not right_click_moved:
					# Signal to Main to cancel tower selection
					get_parent().cancel_tower_selection()
	
	# Mouse motion for panning
	if event is InputEventMouseMotion and is_panning:
		var delta_mouse = event.position - last_mouse_pos
		last_mouse_pos = event.position
		
		# Pan the target position based on mouse movement
		var forward = -transform.basis.z
		var right = transform.basis.x
		forward.y = 0
		right.y = 0
		forward = forward.normalized()
		right = right.normalized()
		
		target_position -= right * delta_mouse.x * 0.05
		target_position += forward * delta_mouse.y * 0.05
		update_camera_transform()
	
	# Mouse motion for right-click camera control
	if event is InputEventMouseMotion and is_right_dragging:
		var delta_mouse = event.position - last_mouse_pos
		last_mouse_pos = event.position
		
		# Check if we've moved enough to consider it a drag
		if event.position.distance_to(right_click_start_pos) > 5.0:
			right_click_moved = true
		
		# Horizontal movement = rotation (like Q/E)
		if abs(delta_mouse.x) > 0.1:
			camera_rotation -= delta_mouse.x * mouse_rotation_sensitivity
			# Slide to maintain center
			var right = transform.basis.x
			right.y = 0
			right = right.normalized()
			target_position -= right * delta_mouse.x * 0.005
			update_camera_transform()
		
		# Vertical movement = angle adjustment (like Up/Down arrows) - FIXED: inverted
		if abs(delta_mouse.y) > 0.1:
			current_angle = clamp(current_angle + delta_mouse.y * mouse_angle_sensitivity, min_angle, max_angle)
			update_camera_transform()

func handle_keyboard_movement(delta):
	var movement = Vector3.ZERO
	
	# WASD movement
	if Input.is_key_pressed(KEY_W):
		movement.z -= 1
	if Input.is_key_pressed(KEY_S):
		movement.z += 1
	if Input.is_key_pressed(KEY_A):
		movement.x -= 1
	if Input.is_key_pressed(KEY_D):
		movement.x += 1
	
	# Arrow keys for rotation with counter-strafe
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_LEFT):
		camera_rotation += rotation_speed * delta * 50
		# Slide right to maintain center
		var right = transform.basis.x
		right.y = 0
		right = right.normalized()
		target_position += right * pan_speed * delta * 0.5
		update_camera_transform()
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_RIGHT):
		camera_rotation -= rotation_speed * delta * 50
		# Slide left to maintain center
		var right = transform.basis.x
		right.y = 0
		right = right.normalized()
		target_position -= right * pan_speed * delta * 0.5
		update_camera_transform()
	
	# Angle adjustment
	if Input.is_key_pressed(KEY_UP):
		current_angle = clamp(current_angle + 30 * delta, min_angle, max_angle)
		update_camera_transform()
	if Input.is_key_pressed(KEY_DOWN):
		current_angle = clamp(current_angle - 30 * delta, min_angle, max_angle)
		update_camera_transform()
	
	# Apply movement to target
	if movement != Vector3.ZERO:
		movement = movement.normalized()
		# Rotate movement by camera rotation
		var rotated = movement.rotated(Vector3.UP, deg_to_rad(camera_rotation))
		target_position += rotated * pan_speed * delta
		update_camera_transform()

func update_camera_transform():
	# Calculate camera offset from target based on zoom and angle
	var angle_rad = deg_to_rad(current_angle)
	var rotation_rad = deg_to_rad(camera_rotation)
	
	var offset = Vector3(
		sin(rotation_rad) * current_zoom * cos(angle_rad),
		current_zoom * sin(angle_rad),
		cos(rotation_rad) * current_zoom * cos(angle_rad)
	)
	
	# Position camera relative to target
	position = target_position + offset
	
	# Look at the target
	look_at(target_position, Vector3.UP)
