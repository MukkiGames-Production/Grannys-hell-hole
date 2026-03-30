extends explodingObject
class_name Dryer

@export var air_max: float = 10.0
@export var air_drain_rate: float = 10.0      # per second while blowing
@export var blow_force: float = 1
@export var blow_range: float = 5.0
@export var blow_angle: float = 30.0          # cone angle in degrees
@export var blow_cone: PackedScene

var air_amount: float = air_max
var is_blowing: bool = false

#@onready var progress_bar: ProgressBar = $AirBar

func _ready():
	super._ready()
	air_amount = air_max
	freeze = true
	#_update_bar()

func special(): ##on right click, start blowing
	start_blow()

func special_released():
	is_blowing = false

func _physics_process(delta):
	super._physics_process(delta)

	if not is_held or holder == null:
		return

	var tilt = Basis(Vector3.RIGHT, deg_to_rad(90))
	global_basis = global_basis * tilt

	if is_blowing and is_held:
		_do_blow(delta)

func start_blow():
	if air_amount > 0:
		is_blowing = true

func _do_blow(delta: float):
	print(air_amount)
	air_amount -= air_drain_rate * delta
	air_amount = max(air_amount, 0.0)
	var cone = blow_cone.instantiate()
	get_parent().add_child(cone)
	cone.global_position = global_position
	cone.global_basis = global_basis  # ← copy dryer's rotation so it faces the same way
	cone.collision_shape.shape.radius = blow_range
	cone.force = blow_force
	cone.apply_blow(global_position, -global_transform.basis.y)
	if air_amount <= 0:
		summon_boom(5, 10)
