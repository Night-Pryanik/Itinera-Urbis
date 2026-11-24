# Headless test of the Video settings: the resolution presets, the window modes,
# their persistence and the controls of the settings scene.
#   godot --headless --path . --script res://tests/test_display_settings.gd
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")
const DisplaySettings = preload("res://scripts/display_settings.gd")

func _initialize() -> void:
    WATCHDOG.arm(self)
    _run()

func _check(condition: bool, label: String, state: Dictionary) -> void:
    if not condition:
        state["failed"] = true
        print("FAIL: " + label)

func _run() -> void:
    var state := {"failed": false}
    var sizes := DisplaySettings.available_resolutions()
    _check(not sizes.is_empty(), "the preset list is not empty", state)
    _check(sizes.has(Vector2i(1920, 1080)), "1080p is offered", state)
    _check(sizes.has(Vector2i(3840, 2160)), "4K is offered when the screen is unknown", state)
    for i in range(1, sizes.size()):
        var previous: Vector2i = sizes[i - 1]
        var current: Vector2i = sizes[i]
        _check(current.x > previous.x or (current.x == previous.x and current.y > previous.y),
            "the presets are sorted and unique", state)
    for size in sizes:
        _check(DisplaySettings.text_to_resolution(
            DisplaySettings.resolution_to_text(size)) == size,
            "the resolution text round-trips: %s" % str(size), state)
    _check(DisplaySettings.text_to_resolution("") == Vector2i.ZERO,
        "an empty resolution is the monitor native", state)
    _check(DisplaySettings.text_to_resolution("bad") == Vector2i.ZERO,
        "a broken resolution is rejected", state)

    var saved := DisplaySettings.read_saved()
    _check(str(saved["mode"]) == DisplaySettings.DEFAULT_MODE,
        "the default window mode is fullscreen", state)
    _check(saved["resolution"] == Vector2i.ZERO,
        "the default resolution is the monitor native", state)
    DisplaySettings.apply(DisplaySettings.MODE_WINDOWED, Vector2i(1280, 720))
    DisplaySettings.apply(DisplaySettings.MODE_MAXIMIZED, Vector2i.ZERO)
    DisplaySettings.apply(DisplaySettings.MODE_FULLSCREEN, Vector2i.ZERO)

    var menu := (load("res://scenes/settings_menu.tscn") as PackedScene).instantiate()
    get_root().add_child(menu)
    await process_frame
    var resolution := menu.find_child("ResolutionOptionButton", true, false) as OptionButton
    var mode := menu.find_child("WindowModeOptionButton", true, false) as OptionButton
    var vsync := menu.find_child("VsyncOptionButton", true, false) as OptionButton
    var fps_limit := menu.find_child("FpsLimitOptionButton", true, false) as OptionButton
    _check(resolution != null and mode != null and vsync != null and fps_limit != null,
        "the Video page owns all four dropdowns", state)
    if resolution == null or mode == null or vsync == null or fps_limit == null:
        _finish(state)
        return
    _check(resolution.item_count == sizes.size() + 1,
        "the dropdown offers the native item and every preset", state)
    _check(str(resolution.get_item_metadata(0)) == "",
        "the native item saves as an empty resolution", state)
    _check(mode.item_count == 3, "the mode dropdown has three items", state)
    _check(str(mode.get_item_metadata(0)) == DisplaySettings.MODE_FULLSCREEN,
        "the mode items carry saved values", state)
    _check(vsync.item_count == DisplaySettings.VSYNC_MODES.size(),
        "the VSync dropdown has all modes", state)
    _check(str(vsync.get_item_metadata(1)) == "enabled",
        "the VSync items carry saved values", state)
    _check(fps_limit.item_count == DisplaySettings.FPS_LIMITS.size(),
        "the frame rate dropdown has all limits", state)
    _check(int(fps_limit.get_item_metadata(0)) == 0,
        "the first frame rate limit is no limit", state)

    var target := -1
    for i in resolution.item_count:
        if str(resolution.get_item_metadata(i)) == "1280x720":
            target = i
            break
    _check(target > 0, "1280x720 is in the dropdown", state)
    resolution.select(target)
    resolution.item_selected.emit(target)
    var config := ConfigFile.new()
    config.load("user://settings.cfg")
    _check(str(config.get_value("video", "resolution", "")) == "1280x720",
        "a chosen resolution is saved", state)
    _check(str(config.get_value("video", "window_mode", "")) == DisplaySettings.MODE_FULLSCREEN,
        "choosing a resolution keeps the window mode", state)

    mode.select(2)
    mode.item_selected.emit(2)
    config.load("user://settings.cfg")
    _check(str(config.get_value("video", "window_mode", "")) == DisplaySettings.MODE_WINDOWED,
        "a chosen window mode is saved", state)
    vsync.select(0)
    vsync.item_selected.emit(0)
    fps_limit.select(3)
    fps_limit.item_selected.emit(3)
    config.load("user://settings.cfg")
    _check(str(config.get_value("video", "vsync_mode", "")) == "disabled",
        "a chosen VSync mode is saved", state)
    _check(int(config.get_value("video", "fps_limit", -1)) == 120,
        "a chosen frame rate limit is saved", state)
    _check(Engine.max_fps == 120, "the frame rate limit is applied", state)
    var restored := DisplaySettings.read_saved()
    _check(restored["resolution"] == Vector2i(1280, 720),
        "the saved resolution is read back", state)
    _check(str(restored["vsync"]) == "disabled" and int(restored["fps_limit"]) == 120,
        "the saved VSync and frame rate are read back", state)

    Engine.max_fps = 0
    menu.free()
    _finish(state)

func _finish(state: Dictionary) -> void:
    if state["failed"]:
        print("DISPLAY SETTINGS TEST FAILED")
        quit(1)
    else:
        print("DISPLAY SETTINGS TEST OK")
        quit(0)
