extends Node

# Keeps the two animated overlays aligned with the panorama and holds their
# tuning in one place. The panorama itself is never transformed: the smoke is
# placed in a Node2D whose local coordinates are the pixels of the source
# image, and that node is fitted to the same rectangle the TextureRect uses.

@export_group("Water")
@export var water_enabled := true
@export_range(0.0, 0.6, 0.005) var water_opacity := 0.32
@export_range(0.0, 0.4, 0.005) var water_flow_speed := 0.055
@export_range(0.3, 4.0, 0.05) var water_ripple_scale := 1.7

@export_group("Smoke")
@export var smoke_enabled := true
@export_range(0.0, 1.0, 0.01) var smoke_opacity := 0.65
@export_range(0.2, 3.0, 0.05) var smoke_speed_scale := 1.0
@export_range(0.0, 2.0, 0.05) var smoke_amount_scale := 1.0

@export_group("Nodes")
@export_node_path("TextureRect") var picture_path := ^"../Picture"
@export_node_path("TextureRect") var water_path := ^"../WaterLayer"
@export_node_path("Node2D") var smoke_path := ^"../SmokeRoot"

var _picture: TextureRect
var _water: TextureRect
var _water_material: ShaderMaterial
var _smoke_root: Node2D
var _smoke: Array[GPUParticles2D] = []
var _smoke_material: ParticleProcessMaterial
var _base_velocity_min := 0.0
var _base_velocity_max := 0.0
var _base_amount: Array[int] = []

func _ready():
    _picture = get_node(picture_path)
    _water = get_node(water_path)
    _smoke_root = get_node(smoke_path)
    _water_material = _water.material as ShaderMaterial
    for child in _smoke_root.get_children():
        if child is GPUParticles2D:
            _smoke.append(child)
    if not _smoke.is_empty():
        _smoke_material = _smoke[0].process_material as ParticleProcessMaterial
        if _smoke_material != null:
            _base_velocity_min = _smoke_material.initial_velocity_min
            _base_velocity_max = _smoke_material.initial_velocity_max
    for emitter in _smoke:
        _base_amount.append(emitter.amount)

    _apply_settings()
    _layout_to_picture()
    get_viewport().size_changed.connect(_layout_to_picture)

func _apply_settings():
    _water.visible = water_enabled
    if _water_material != null:
        _water_material.set_shader_parameter("flow_speed", water_flow_speed)
        _water_material.set_shader_parameter("ripple_scale", water_ripple_scale)
        _water_material.set_shader_parameter("opacity", water_opacity)

    _smoke_root.visible = smoke_enabled
    if _smoke_material != null:
        _smoke_material.initial_velocity_min = _base_velocity_min * smoke_speed_scale
        _smoke_material.initial_velocity_max = _base_velocity_max * smoke_speed_scale
    for i in _smoke.size():
        _smoke[i].modulate = Color(1, 1, 1, smoke_opacity)
        _smoke[i].amount = maxi(1, int(round(_base_amount[i] * smoke_amount_scale)))

# The Picture is a full-rect TextureRect with STRETCH_KEEP_ASPECT_CENTERED and
# EXPAND_IGNORE_SIZE. This is the same fit, so local pixel (x, y) of the source
# image lands on the same screen point as that pixel of the panorama.
func _layout_to_picture():
    var texture: Texture2D = _picture.texture
    if texture == null:
        return
    var image := texture.get_size()
    if image.x <= 0.0 or image.y <= 0.0:
        return
    var view := get_viewport().get_visible_rect().size
    var fit := minf(view.x / image.x, view.y / image.y)
    _smoke_root.position = (view - image * fit) * 0.5
    _smoke_root.scale = Vector2(fit, fit)
