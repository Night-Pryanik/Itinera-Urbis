# scripts/ui_scale.gd
#
# The physical size of the interface on the display.
#
# The project lays the interface out on a 1365x768 canvas that the engine magnifies into the
# window. That canvas is fixed, so on a small phone screen the buttons and the text come out
# physically tiny. This multiplier goes on top of the project scale through the root window's
# content_scale_factor — the runtime counterpart of the stretch scale in project.godot — and
# enlarges every control, every label and the map at once. The cost is the same as with any
# zoom: fewer canvas units fit on the screen, so pages that do not fit have to scroll.
extends RefCounted

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "interface"
const KEY := "ui_scale"
const DEFAULT := 1.0
const MINIMUM := 1.0
const MAXIMUM := 2.0

# The offered choices. A value edited by hand in settings.cfg is clamped to the range but
# need not be one of these: the dropdown shows the closest step when a saved value is off it.
const STEPS: Array[float] = [1.0, 1.1, 1.25, 1.5, 1.75, 2.0]

static func base_factor() -> float:
    var value := float(ProjectSettings.get_setting("display/window/stretch/scale", 1.0))
    return value if value > 0.0 else 1.0

static func clamp_scale(value: float) -> float:
    if not is_finite(value):
        return DEFAULT
    return clampf(value, MINIMUM, MAXIMUM)

static func read_saved() -> float:
    var config := ConfigFile.new()
    if config.load(SETTINGS_PATH) != OK:
        return DEFAULT
    return clamp_scale(float(config.get_value(SECTION, KEY, DEFAULT)))

# The scale belongs to the root window, so it applies to the main menu and to the map alike,
# and survives a change of scene. base_factor() is read from the project settings rather than
# from the window: the window already carries the multiplier from an earlier call.
static func apply(value: float) -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null or tree.root == null:
        return
    tree.root.content_scale_factor = base_factor() * clamp_scale(value)
    # The glyphs on screen were rasterised for the old scale. Re-resolve them on the next
    # frame: otherwise a dropdown opened immediately after the change can resize the font
    # atlas while the old text still holds UVs into it, and the letters turn into blocks.
    var manager := tree.root.get_node_or_null("FontManager")
    if manager != null and manager.has_method("refresh_text"):
        manager.call_deferred("refresh_text")

static func apply_saved() -> void:
    apply(read_saved())

static func save(value: float) -> void:
    var config := ConfigFile.new()
    # Other managers write settings.cfg too; re-read so their keys survive this write.
    config.load(SETTINGS_PATH)
    config.set_value(SECTION, KEY, clamp_scale(value))
    config.save(SETTINGS_PATH)
    apply(value)

static func is_step(value: float) -> bool:
    for step in STEPS:
        if is_equal_approx(step, value):
            return true
    return false

# The index of the offered choice a saved value should show. An off-step value from a
# hand-edited file selects the nearest step; the settings menu adds it as its own item.
static func step_index(value: float) -> int:
    var saved := clamp_scale(value)
    var best := 0
    for i in STEPS.size():
        if absf(STEPS[i] - saved) < absf(STEPS[best] - saved):
            best = i
    return best
