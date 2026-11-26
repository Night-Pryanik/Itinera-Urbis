# Headless test of the long tap on a hex (the Android way to read the hex tooltip).
#   godot --headless --path . --script res://tests/test_long_tap_tooltip.gd
#
# A single finger has no hover: the emulated mouse gives the map a tap, but nothing
# feeds the hover timer. A hold must start that timer from the raw touch, show the
# tooltip at the finger, keep it after the lift and leave a short tap to select.
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")
const SETTLE_FRAMES := 4

func _initialize() -> void:
    WATCHDOG.arm(self)
    _run()

func _run() -> void:
    var state: Dictionary = {"failed": false}
    get_root().get_node("SaveManager").new_game()
    var main_map = load("res://scenes/MainMap.tscn").instantiate()
    get_root().add_child(main_map)
    for _i in range(SETTLE_FRAMES):
        await process_frame
    main_map.use_edge_scrolling = false
    var ih = main_map.input_handler

    main_map.set_zoom(1.0)
    main_map.center_on_hex(main_map.city_row, main_map.city_col)
    await process_frame
    var pos: Vector2 = main_map.get_viewport_rect().size / 2.0
    var hex = ih._pixel_to_hex(pos.x, pos.y)
    check(hex != null and hex.row == main_map.city_row and hex.col == main_map.city_col,
        "the city hex is under the centre of the screen", state)

    # A short tap keeps its old meaning: select the hex.
    _mouse(ih, pos, true)
    _mouse(ih, pos, false)
    check(main_map.control_panel.has_selection(), "a short tap selects the hex", state)
    main_map.clear_selection()

    # A hold opens the ordinary tooltip, but only after the usual hover delay.
    _touch(ih, 0, pos, true)
    check(ih._long_tap_index == 0, "a touch starts the hold timer", state)
    ih.handle_process(0.2)
    check(not main_map.hex_tooltip.visible, "the tooltip waits out the delay", state)
    ih.handle_process(0.4)
    check(main_map.hex_tooltip.visible, "a long tap shows the hex tooltip", state)
    check(main_map.tooltip_text_label.text != "", "the tooltip holds the text of the hex", state)
    check(ih._touch_tooltip, "the tooltip belongs to the touch, not to the mouse", state)
    check(main_map.hex_tooltip.position.distance_to(pos + Vector2(15, 15)) < 40.0,
        "the tooltip is anchored at the finger", state)

    # There is no hover after the lift, so the tooltip must stay until a new gesture.
    _touch(ih, 0, pos, false)
    check(main_map.hex_tooltip.visible, "the tooltip stays after the finger is lifted", state)
    _mouse(ih, pos, false)
    check(not main_map.control_panel.has_selection(),
        "the emulated release of a long tap does not select the hex", state)

    _touch(ih, 0, pos + Vector2(60, 0), true)
    check(not main_map.hex_tooltip.visible, "the next touch dismisses the tooltip", state)
    _touch(ih, 0, pos + Vector2(60, 0), false)

    # A second finger is a pinch, not an inspection: it cancels a hold in progress.
    _touch(ih, 0, pos, true)
    ih.handle_process(0.6)
    check(main_map.hex_tooltip.visible, "the hold shows the tooltip again", state)
    _touch(ih, 1, pos + Vector2(60, 0), true)
    check(not main_map.hex_tooltip.visible, "a pinch dismisses the tooltip", state)
    _touch(ih, 0, pos, false)
    _touch(ih, 1, pos + Vector2(60, 0), false)

    WATCHDOG.report_skipped()
    if state["failed"]:
        print("LONG TAP TOOLTIP TEST FAILED")
        quit(1)
    else:
        print("LONG TAP TOOLTIP TEST OK")
        quit(0)

func _touch(ih, index: int, pos: Vector2, pressed: bool) -> void:
    var event := InputEventScreenTouch.new()
    event.index = index
    event.position = pos
    event.pressed = pressed
    ih.handle_input(event)

func _mouse(ih, pos: Vector2, pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.position = pos
    event.global_position = pos
    event.pressed = pressed
    ih.handle_input(event)

func check(condition: bool, message: String, state: Dictionary) -> void:
    if condition:
        print("OK: ", message)
    else:
        state["failed"] = true
        push_error("ASSERT FAILED: " + message)
