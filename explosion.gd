extends Node3D
@onready var debris: GPUParticles3D = $Debris
@onready var smoke: GPUParticles3D = $Smoke
@onready var fire: GPUParticles3D = $Fire
@onready var boom: AudioStreamPlayer3D = $Boom



func explode():
	debris.emitting = true
	smoke.emitting = true
	fire.emitting = true
	boom.play()
	await  get_tree().create_timer(2.0).timeout
	queue_free()
