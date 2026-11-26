extends RefCounted

# Android delivers the system Back button as a window request, not as a key event. Godot
# quits on that request by default, so it is turned into Escape instead: the map, the pause
# menu and every popup then share the one cancel chain the keyboard already uses.

const REPEAT_WINDOW_MSEC: int = 100
static var _last_forward_msec: int = -REPEAT_WINDOW_MSEC

static func disable_auto_quit() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.quit_on_go_back = false

static func forward_to_escape() -> void:
    # Some Android versions deliver two requests for a single press. Without the guard the
    # first Escape would open the pause menu and the second would immediately close it.
    var now := Time.get_ticks_msec()
    if now - _last_forward_msec < REPEAT_WINDOW_MSEC:
        return
    _last_forward_msec = now

    var press := InputEventKey.new()
    press.keycode = KEY_ESCAPE
    press.pressed = true
    Input.parse_input_event(press)

    var release := InputEventKey.new()
    release.keycode = KEY_ESCAPE
    Input.parse_input_event(release)
