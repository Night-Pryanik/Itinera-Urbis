# Resolution and window mode of the game window.
#
# Godot does not expose the list of display modes a monitor supports, so the resolutions
# offered in the settings are a curated set filtered by the monitor's current size. The
# interface itself does not depend on the choice: the stretch scale in project.godot keeps
# its proportions at every window size.
class_name DisplaySettings
extends RefCounted

const SECTION := "video"
const KEY_RESOLUTION := "resolution"
const KEY_WINDOW_MODE := "window_mode"
const KEY_VSYNC := "vsync_mode"
const KEY_FPS_LIMIT := "fps_limit"

const MODE_FULLSCREEN := "fullscreen"
const MODE_MAXIMIZED := "maximized"
const MODE_WINDOWED := "windowed"
const DEFAULT_MODE := MODE_FULLSCREEN

# The values are saved as strings; the numbers are DisplayServer.VSYNC_* constants.
const VSYNC_MODES := [
    ["disabled", DisplayServer.VSYNC_DISABLED],
    ["enabled", DisplayServer.VSYNC_ENABLED],
    ["adaptive", DisplayServer.VSYNC_ADAPTIVE],
    ["mailbox", DisplayServer.VSYNC_MAILBOX],
]
const DEFAULT_VSYNC := "enabled"

# Zero lets the engine run as fast as it can; VSync still caps the frame rate when on.
const FPS_LIMITS: Array[int] = [0, 30, 60, 120, 144, 240]
const DEFAULT_FPS_LIMIT := 0

# The resolutions in use today (Steam Hardware Survey, 2026), from the smallest laptop
# panel to 4K and one common ultrawide size. A preset larger than the monitor is hidden.
const PRESETS: Array[Vector2i] = [
    Vector2i(1280, 720),
    Vector2i(1366, 768),
    Vector2i(1600, 900),
    Vector2i(1920, 1080),
    Vector2i(1920, 1200),
    Vector2i(2560, 1080),
    Vector2i(2560, 1440),
    Vector2i(2560, 1600),
    Vector2i(3440, 1440),
    Vector2i(3840, 2160),
]

static func native_resolution() -> Vector2i:
    var screen := DisplayServer.window_get_current_screen()
    if screen < 0:
        screen = DisplayServer.get_primary_screen()
    return Vector2i(DisplayServer.screen_get_size(screen))

# The headless DisplayServer reports no screen: keep the whole list so the settings menu
# can still be built and tested there.
static func available_resolutions() -> Array[Vector2i]:
    var native := native_resolution()
    var result: Array[Vector2i] = []
    for preset in PRESETS:
        if native.x > 0 and native.y > 0:
            if preset.x > native.x or preset.y > native.y:
                continue
        if not result.has(preset):
            result.append(preset)
    return result

static func resolution_to_text(size: Vector2i) -> String:
    return "%dx%d" % [size.x, size.y]

static func text_to_resolution(text: String) -> Vector2i:
    var parts := text.split("x")
    if parts.size() != 2:
        return Vector2i.ZERO
    var size := Vector2i(int(parts[0]), int(parts[1]))
    return size if size.x >= 640 and size.y >= 480 else Vector2i.ZERO

static func read_saved() -> Dictionary:
    var config := ConfigFile.new()
    config.load("user://settings.cfg")
    return {
        "mode": str(config.get_value(SECTION, KEY_WINDOW_MODE, DEFAULT_MODE)),
        "resolution": text_to_resolution(str(config.get_value(SECTION, KEY_RESOLUTION, ""))),
        "vsync": str(config.get_value(SECTION, KEY_VSYNC, DEFAULT_VSYNC)),
        "fps_limit": int(config.get_value(SECTION, KEY_FPS_LIMIT, DEFAULT_FPS_LIMIT)),
    }

static func apply(mode: String, resolution: Vector2i) -> void:
    match mode:
        MODE_FULLSCREEN:
            DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
        MODE_MAXIMIZED:
            DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
        _:
            DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
            var size := resolution if resolution.x > 0 and resolution.y > 0 else native_resolution()
            if size.x > 0 and size.y > 0:
                DisplayServer.window_set_size(size)

static func apply_vsync(mode: String) -> void:
    for entry in VSYNC_MODES:
        if str(entry[0]) == mode:
            DisplayServer.window_set_vsync_mode(int(entry[1]))
            return
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)

static func apply_fps_limit(limit: int) -> void:
    # A negative limit would freeze the engine: keep only the offered values.
    Engine.max_fps = limit if FPS_LIMITS.has(limit) else DEFAULT_FPS_LIMIT

static func apply_saved() -> void:
    var saved := read_saved()
    apply(str(saved["mode"]), saved["resolution"])
    apply_vsync(str(saved["vsync"]))
    apply_fps_limit(int(saved["fps_limit"]))
