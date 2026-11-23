extends Node2D

# Distant birds crossing the sky near the sun. bird_flap.png holds a flap
# cycle as a horizontal strip of frames; positions are pixels of the
# panorama, and main_menu_ambience.gd fits this node to the picture.

@export var columns := 16
@export var flap_fps := 12.0
@export var flap_cycles := 3
@export var glide_frame := 6
@export var glide_seconds := 2.4
@export var fly_speed := 34.0
@export var bob_amount := 1.2
@export var opacity := 0.82
@export var left_edge := -80.0
@export var right_edge := 500.0
@export var fade_zone := 100.0

var _birds: Array[Sprite2D] = []
var _frames: Array[AtlasTexture] = []
var _start: Array[Vector2] = []
var _factors: Array[float] = []
var _phases: Array[float] = []
var _position: Array[float] = []
var _cycles: Array[int] = []
var _glide: Array[float] = []
var _shown: Array[int] = []
var _time := 0.0

func _ready():
    for child in get_children():
        if child is Sprite2D:
            _birds.append(child)
    if _birds.is_empty():
        return
    var sheet: Texture2D = _birds[0].texture
    var frame_size := Vector2(sheet.get_width() / float(columns), sheet.get_height())
    for i in columns:
        var frame := AtlasTexture.new()
        frame.atlas = sheet
        frame.region = Rect2(i * frame_size.x, 0.0, frame_size.x, frame_size.y)
        # The frames touch in the strip, so sampling is clamped to the region
        # to keep a neighbour from bleeding in while a bird is scaled down.
        frame.filter_clip = true
        _frames.append(frame)

    for i in _birds.size():
        var phase := float(_birds[i].get_meta("phase", 0.0))
        _start.append(_birds[i].position)
        _factors.append(float(_birds[i].get_meta("speed_factor", 1.0)))
        _phases.append(phase)
        _position.append(phase * columns)
        _cycles.append(flap_cycles)
        _glide.append(0.0)
        _shown.append(-1)
    modulate.a = opacity

func _process(delta):
    if _birds.is_empty():
        return
    _time += delta
    var span := right_edge - left_edge
    for i in _birds.size():
        var bird: Sprite2D = _birds[i]
        var travelled := _time * fly_speed * _factors[i]
        var x := left_edge + fmod(_start[i].x - left_edge + travelled, span)
        bird.position.x = x
        bird.position.y = _start[i].y + sin(_time * 0.7 + _phases[i] * TAU) * bob_amount
        # The wrap happens where the bird is fully transparent.
        bird.modulate.a = clampf(minf((x - left_edge) / fade_zone,
                (right_edge - x) / fade_zone), 0.0, 1.0)

        # Several wing beats, then the bird holds a spread-wing pose and glides.
        # The pose is the level frame of the cycle, so both entering and leaving
        # the glide continues the stroke instead of cutting to another shape.
        if _glide[i] > 0.0:
            _glide[i] -= delta
            if _glide[i] <= 0.0:
                _cycles[i] = flap_cycles
        else:
            var before := _position[i]
            _position[i] += delta * flap_fps * _factors[i]
            if _position[i] >= columns:
                _position[i] -= columns
                _cycles[i] = maxi(_cycles[i] - 1, 0)
            if _cycles[i] == 0 and before < glide_frame and _position[i] >= glide_frame:
                _position[i] = glide_frame
                _glide[i] = glide_seconds

        var index := int(_position[i]) % columns
        if _shown[i] != index:
            bird.texture = _frames[index]
            _shown[i] = index
