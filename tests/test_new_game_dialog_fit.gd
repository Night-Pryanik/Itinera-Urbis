# Headless test of the new game window at a large interface size on a small screen:
#   godot --headless --path . --script res://tests/test_new_game_dialog_fit.gd
#
# The interface multiplier zooms the canvas, so a window laid out for the full canvas can
# end up below the screen with its OK and Cancel buttons out of reach. The window gives up
# room to a scroll instead of scaling its controls down: the fonts must still follow the
# chosen size, while the buttons land inside the screen.
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")
const UiScale = preload("res://scripts/ui_scale.gd")

const SCREEN := Vector2i(1280, 720)

func _initialize() -> void:
    WATCHDOG.arm(self)
    _run()

func _check(condition: bool, label: String, state: Dictionary) -> void:
    if not condition:
        state["failed"] = true
        print("FAIL: " + label)

func _run() -> void:
    var state := {"failed": false}
    var menu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
    get_root().add_child(menu)
    await process_frame
    await process_frame

    UiScale.apply(UiScale.MAXIMUM)
    menu.apply_ui_scale_compensation()
    get_root().size = SCREEN
    await process_frame
    await process_frame

    var screen: Vector2 = get_root().get_visible_rect().size
    _check(screen.y <= 400.0, "the zoomed canvas is small enough to need a fit (got %s)" % str(screen), state)

    menu._on_new_game()
    await process_frame
    await process_frame

    var dialog = menu.new_game_dialog
    _check(dialog != null and dialog.visible, "the new game dialog is open", state)
    if dialog == null:
        _finish(state)
        return

    _check(is_equal_approx(float(dialog.content_scale_factor), 1.0),
            "the window keeps the global interface scale", state)
    _check(is_equal_approx(get_root().content_scale_factor,
            UiScale.base_factor() * UiScale.MAXIMUM),
            "the interface multiplier is still applied to the canvas", state)

    _check(menu.tab_container.custom_minimum_size.x == float(menu.DIALOG_CONTENT_WIDTH),
            "the tabs keep the size their controls were laid out for", state)
    _check(menu.content_scroll.custom_minimum_size.x < float(menu.DIALOG_CONTENT_WIDTH)
            and menu.content_scroll.custom_minimum_size.y < float(menu.DIALOG_CONTENT_HEIGHT),
            "the content scrolls instead of shrinking the controls", state)

    var pos := Vector2(dialog.get_position_with_decorations())
    var size := Vector2(dialog.get_size_with_decorations())
    _check(pos.x >= -1.0 and pos.y >= -1.0
            and pos.x + size.x <= screen.x + 1.0 and pos.y + size.y <= screen.y + 1.0,
            "the window stays inside the screen (at %s, %s of %s)" % [str(pos), str(size), str(screen)], state)

    for button in [dialog.get_ok_button(), dialog.get_cancel_button()]:
        var rect: Rect2 = button.get_global_rect()
        var on_screen := Rect2(Vector2(dialog.position) + rect.position, rect.size)
        _check(on_screen.position.x >= -1.0 and on_screen.position.y >= -1.0
                and on_screen.end.x <= screen.x + 1.0 and on_screen.end.y <= screen.y + 1.0,
                "the button is reachable on the screen (%s)" % str(on_screen), state)

    dialog.hide()
    UiScale.apply(UiScale.DEFAULT)
    menu.free()
    await process_frame
    _finish(state)

func _finish(state: Dictionary) -> void:
    WATCHDOG.report_skipped()
    if state["failed"]:
        print("NEW GAME DIALOG FIT TEST FAILED")
        quit(1)
    else:
        print("NEW GAME DIALOG FIT TEST OK")
        quit(0)
