extends Control

signal closed

@onready var player_preview = $PanelContainer/HBoxContainer/MarginContainer/SubViewportContainer/SubViewport/StuBLEND/Stu
@onready var Leye_grid = $"PanelContainer/HBoxContainer/Right Side/TabContainer/Left Eye"
@onready var Reye_grid = $"PanelContainer/HBoxContainer/Right Side/TabContainer/Right Eye"
@onready var mouth_grid = $"PanelContainer/HBoxContainer/Right Side/TabContainer/Mouth"
@onready var accept_btn = $"PanelContainer/HBoxContainer/Right Side/CenterContainer/Accept"
const LEYE_SURFACE = 3
const REYE_SURFACE = 2
#custom colors are impossible i think cause baked texture
const MOUTH_SURFACE = 0

const EYE_TEXTURES = [
	preload("res://Assets/Blender/textures/customization/eye1.png"),
	preload("res://Assets/Blender/textures/customization/eye2.png"),
	preload("res://Assets/Blender/textures/customization/eye3.png"),
	preload("res://Assets/Blender/textures/customization/eye4.png"),
	preload("res://Assets/Blender/textures/customization/eye5.png"),
	preload("res://Assets/Blender/textures/customization/eye6.png"),
	preload("res://Assets/Blender/textures/customization/eye7.png"),
	preload("res://Assets/Blender/textures/customization/eye8.png"),
	preload("res://Assets/Blender/textures/customization/eye9.png"),
	preload("res://Assets/Blender/textures/customization/eye10.png"),
]

const MOUTH_TEXTURES = [
	preload("res://Assets/Blender/textures/customization/mouth1.png"),
	preload("res://Assets/Blender/textures/customization/mouth2.png"),
	preload("res://Assets/Blender/textures/customization/mouth3.png"),
	preload("res://Assets/Blender/textures/customization/mouth4.png"),
	preload("res://Assets/Blender/textures/customization/mouth5.png"),
	preload("res://Assets/Blender/textures/customization/mouth6.png"),
	preload("res://Assets/Blender/textures/customization/mouth7.png"),
	preload("res://Assets/Blender/textures/customization/mouth8.png"),
	preload("res://Assets/Blender/textures/customization/mouth9.png"),
	preload("res://Assets/Blender/textures/customization/mouth10.png"),
]

# Track selected indices
var selected_leye: int = 0
var selected_reye: int = 0
var selected_mouth: int = 0


func _ready():
	for i in Leye_grid.get_child_count():
		var btn = Leye_grid.get_child(i) as TextureButton
		btn.pressed.connect(_on_Leye_pressed.bind(i))
	for i in Reye_grid.get_child_count():
		var btn = Reye_grid.get_child(i) as TextureButton
		btn.pressed.connect(_on_Reye_pressed.bind(i))
	for i in mouth_grid.get_child_count():
		var btn = mouth_grid.get_child(i) as TextureButton
		btn.pressed.connect(_on_mouth_pressed.bind(i))

	accept_btn.pressed.connect(_accept_changes)  # No () here

func _on_Leye_pressed(index: int):
	selected_leye = index
	change_texture(player_preview, EYE_TEXTURES[index], LEYE_SURFACE)

func _on_Reye_pressed(index: int):
	selected_reye = index
	change_texture(player_preview, EYE_TEXTURES[index], REYE_SURFACE)

func _on_mouth_pressed(index: int):
	selected_mouth = index
	change_texture(player_preview, MOUTH_TEXTURES[index], MOUTH_SURFACE)

func _on_close_button_pressed():
	closed.emit()
	queue_free()

func change_texture(mesh: MeshInstance3D, new_texture: Texture2D, surface_index: int = 0):
	mesh.set_surface_override_material(surface_index, mesh.get_active_material(surface_index).duplicate())
	var mat = mesh.get_surface_override_material(surface_index)
	mat.albedo_texture = new_texture

func _accept_changes():
	var player = get_tree().get_first_node_in_group("players")
	var player_mesh: MeshInstance3D = player.get_node("Rag Bones/Stu")
	change_texture(player_mesh, EYE_TEXTURES[selected_leye], LEYE_SURFACE)
	change_texture(player_mesh, EYE_TEXTURES[selected_reye], REYE_SURFACE)
	change_texture(player_mesh, MOUTH_TEXTURES[selected_mouth], MOUTH_SURFACE)
