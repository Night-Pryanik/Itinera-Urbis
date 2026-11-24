# Headless test of the interface size setting:
#   godot --headless --path . --script res://tests/test_ui_scale.gd
#
# The setting is a multiplier on the stretch scale of project.godot. The test checks the
# clamp, the dropdown of the settings window, the live change of the root window and the
# persistence in settings.cfg.
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")
const UiScale = preload("res://scripts/ui_scale.gd")
const SETTINGS_PATH := "user://settings.cfg"

func _initialize() -> void:
    WATCHDOG.arm(self)
    _run()

func _check(condition: bool, label: String, state: Dictionary) -> void:
    if not condition:
        state["failed"] = true
        print("FAIL: " + label)

func _run() -> void:
    var state := {"failed": false}

    var base := UiScale.base_factor()
    _check(base > 0.0, "the project has a positive stretch scale", state)
    _check(is_equal_approx(UiScale.clamp_scale(-1.0), UiScale.MINIMUM),
        "a negative multiplier is clamped", state)
    _check(is_equal_approx(UiScale.clamp_scale(4.0), UiScale.MAXIMUM),
        "a huge multiplier is clamped", state)
    _check(is_equal_approx(UiScale.clamp_scale(NAN), UiScale.DEFAULT),
        "a broken multiplier falls back to the default", state)
    _check(UiScale.step_index(1.0) == 0
            and UiScale.step_index(3.0) == UiScale.STEPS.size() - 1,
        "an off-list value selects the nearest offered step", state)
    _check(UiScale.is_step(1.25) and not UiScale.is_step(1.3),
        "the offered steps are recognised", state)

    var root := get_root()
    UiScale.apply(1.5)
    _check(is_equal_approx(root.content_scale_factor, base * 1.5),
        "the multiplier reaches the root window at once", state)
    UiScale.apply(3.0)
    _check(is_equal_approx(root.content_scale_factor, base * UiScale.MAXIMUM),
        "the root window never goes past the limit", state)

    # The saved value is restored by apply_saved(); the menu and the map use it at startup.
    # A sentinel in the same section checks that the write keeps the keys of the neighbours.
    var config := ConfigFile.new()
    config.load(SETTINGS_PATH)
    config.set_value("interface", "ui_scale_probe", true)
    config.save(SETTINGS_PATH)
    UiScale.save(1.25)
    config.load(SETTINGS_PATH)
    _check(bool(config.get_value("interface", "ui_scale_probe", false)),
        "writing the size keeps the other keys", state)
    UiScale.apply(UiScale.DEFAULT)
    UiScale.apply_saved()
    _check(is_equal_approx(root.content_scale_factor, base * 1.25),
        "apply_saved() restores the chosen size", state)

    var menu := (load("res://scenes/settings_menu.tscn") as PackedScene).instantiate()
    get_root().add_child(menu)
    await process_frame
    var dropdown := menu.find_child("UiScaleOptionButton", true, false) as OptionButton
    _check(dropdown != null, "the settings window owns the interface size dropdown", state)
    if dropdown != null:
        _check(dropdown.item_count == UiScale.STEPS.size(),
            "the dropdown offers every step", state)
        _check(dropdown.item_count > 0
                and is_equal_approx(float(dropdown.get_item_metadata(0)), UiScale.STEPS[0]),
            "the items carry the multipliers as metadata", state)
        _check(is_equal_approx(float(dropdown.get_item_metadata(dropdown.selected)), 1.25),
            "the dropdown shows the saved choice", state)

        # A value hand-edited into settings.cfg keeps its own item instead of pretending to
        # be the nearest offered step.
        UiScale.save(1.3)
        menu._setup_ui_scale_option()
        _check(dropdown.item_count == UiScale.STEPS.size() + 1,
            "an off-step value gets an extra item", state)
        _check(is_equal_approx(float(dropdown.get_item_metadata(dropdown.selected)), 1.3),
            "the off-step value is selected", state)
        UiScale.save(1.25)
        menu._setup_ui_scale_option()

        var target := UiScale.step_index(1.5)
        dropdown.select(target)
        dropdown.item_selected.emit(target)
        config.load(SETTINGS_PATH)
        _check(is_equal_approx(float(config.get_value("interface", "ui_scale", 0.0)), 1.5),
            "a chosen size is saved", state)
        _check(is_equal_approx(root.content_scale_factor, base * 1.5),
            "a chosen size is applied without a restart", state)

        dropdown.select(0)
        dropdown.item_selected.emit(0)
        UiScale.apply_saved()
        _check(is_equal_approx(root.content_scale_factor, base),
            "the default size can be chosen back", state)

    menu.free()
    UiScale.apply(UiScale.DEFAULT)
    config.load(SETTINGS_PATH)
    config.erase_section_key("interface", "ui_scale_probe")
    config.save(SETTINGS_PATH)
    _finish(state)

func _finish(state: Dictionary) -> void:
    WATCHDOG.report_skipped()
    if state["failed"]:
        print("UI SCALE TEST FAILED")
        quit(1)
    else:
        print("UI SCALE TEST OK")
        quit(0)
