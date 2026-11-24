# Headless test of the main menu at a larger interface size:
#   godot --headless --path . --script res://tests/test_main_menu_scale.gd
#
# The title and the buttons of the splash keep the size they were designed for, while the
# settings window — a sibling of that splash — still follows the chosen interface size.
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")
const UiScale = preload("res://scripts/ui_scale.gd")

func _initialize() -> void:
    WATCHDOG.arm(self)
    _run()

func _check(condition: bool, label: String, state: Dictionary) -> void:
    if not condition:
        state["failed"] = true
        print("FAIL: " + label)

func _run() -> void:
    var state := {"failed": false}
    UiScale.apply(UiScale.DEFAULT)
    var menu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
    get_root().add_child(menu)
    await process_frame
    await process_frame

    var title: Label = menu.title_label
    var button: Button = menu.continue_button
    _check(title != null and button != null, "the menu owns the title and the buttons", state)
    if title == null or button == null:
        _finish(state)
        return

    var title_size := title.get_theme_font_size("font_size")
    var button_size := button.get_theme_font_size("font_size")
    var title_outline := title.get_theme_constant("outline_size")
    var button_outline := button.get_theme_constant("outline_size")
    var title_top := title.offset_top
    var box_top := (menu.get_node("VBoxContainer") as Control).offset_top

    var settings := (load("res://scenes/settings_menu.tscn") as PackedScene).instantiate()
    menu.add_child(settings)
    await process_frame
    var option := settings.find_child("UiScaleOptionButton", true, false) as OptionButton
    _check(option != null, "the settings window is found", state)
    var option_size := 0
    if option != null:
        option_size = option.get_theme_font_size("font_size")

    UiScale.apply(2.0)
    menu.apply_ui_scale_compensation()
    await process_frame
    await process_frame

    _check(title.get_theme_font_size("font_size") == maxi(8, roundi(title_size * 0.5)),
        "the title font is halved in canvas units", state)
    _check(button.get_theme_font_size("font_size") == maxi(8, roundi(button_size * 0.5)),
        "the button font is halved in canvas units", state)
    _check(title.get_theme_constant("outline_size") == maxi(1, roundi(title_outline * 0.5))
            and button.get_theme_constant("outline_size")
                    == maxi(1, roundi(button_outline * 0.5)),
        "the outlines are halved with the fonts", state)
    _check(is_equal_approx(title.offset_top, title_top * 0.5)
            and is_equal_approx((menu.get_node("VBoxContainer") as Control).offset_top,
                    box_top * 0.5),
        "the offsets follow the same compensation", state)
    if option != null:
        _check(option.get_theme_font_size("font_size") == option_size
                and is_equal_approx(settings.scale.x, 1.0),
            "the settings window is not compensated", state)

    UiScale.apply(UiScale.DEFAULT)
    menu.free()
    _finish(state)

func _finish(state: Dictionary) -> void:
    WATCHDOG.report_skipped()
    if state["failed"]:
        print("MAIN MENU SCALE TEST FAILED")
        quit(1)
    else:
        print("MAIN MENU SCALE TEST OK")
        quit(0)
