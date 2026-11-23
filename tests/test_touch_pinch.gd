# Headless test of pinch-to-zoom on touch devices.
#   godot --headless --path . --script res://tests/test_touch_pinch.gd
#
# A single finger is emulated as a mouse and needs no special code. A pinch needs the raw
# touches: the two fingers must zoom around their midpoint, and the emulated mouse events
# that come with them must not pan the map, press a hex or pan the technology tree.
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

    await _test_map(state, main_map)
    await _test_tech_tree(state, main_map)

    WATCHDOG.report_skipped()
    if state["failed"]:
        print("TOUCH PINCH TEST FAILED")
        quit(1)
    else:
        print("TOUCH PINCH TEST OK")
        quit(0)

func _test_map(state: Dictionary, main_map) -> void:
    var ih = main_map.input_handler
    main_map.set_zoom(1.0)
    var middle: Vector2 = main_map.get_viewport_rect().size / 2.0
    var world_before: Vector2 = main_map.screen_to_local(middle)
    var fingers: Array = [middle + Vector2(-40, 0), middle + Vector2(40, 0)]

    _touch(0, fingers[0], true)
    _touch(1, fingers[1], true)
    check(ih._pinching, "two fingers on the map start a pinch", state)

    fingers = [middle + Vector2(-60, 0), middle + Vector2(60, 0)]
    _drag(0, fingers[0])
    _drag(1, fingers[1])
    check(is_equal_approx(main_map.zoom, 1.5),
        "spreading the fingers zooms the map in (%.3f)" % main_map.zoom, state)
    check(main_map.screen_to_local(middle).distance_to(world_before) < 3.0,
        "the point between the fingers stays in place (%.3f px)"
            % main_map.screen_to_local(middle).distance_to(world_before), state)
    for _i in range(6):
        _drag(0, middle + Vector2(-70, 0))
        _drag(1, middle + Vector2(70, 0))
        _drag(0, middle + Vector2(-60, 0))
        _drag(1, middle + Vector2(60, 0))
    check(main_map.screen_to_local(middle).distance_to(world_before) < 3.0,
        "a long pinch does not drift away from the fingers (%.3f px)"
            % main_map.screen_to_local(middle).distance_to(world_before), state)

    # The emulated mouse of the pinch is ignored while the fingers own the map.
    var scroll_before: Vector2 = main_map.scroll_offset
    var motion := InputEventMouseMotion.new()
    motion.position = middle + Vector2(120, 0)
    motion.global_position = motion.position
    ih._handle_mouse_motion(motion)
    check(main_map.scroll_offset.distance_to(scroll_before) < 0.01,
        "the emulated mouse does not pan the map during a pinch", state)
    ih._handle_mouse_button(_mouse_button(MOUSE_BUTTON_LEFT, middle, true))
    ih._handle_mouse_button(_mouse_button(MOUSE_BUTTON_LEFT, middle, false))
    check(not main_map.control_panel.has_selection(),
        "the emulated click does not select a hex during a pinch", state)

    _touch(0, fingers[0], false)
    _touch(1, fingers[1], false)
    check(not ih._pinching, "lifting a finger ends the pinch", state)
    check(is_equal_approx(main_map.zoom, 1.5),
        "the zoom reached by the fingers stays for this session", state)

func _test_tech_tree(state: Dictionary, main_map) -> void:
    main_map.open_city()
    for _i in range(SETTLE_FRAMES):
        await process_frame
    var city_ui = main_map.get_node_or_null("CityUI")
    check(city_ui != null, "CityUI is found", state)
    if city_ui == null:
        return
    city_ui.show_technologies_tab()
    for _i in range(SETTLE_FRAMES):
        await process_frame
    var tree = city_ui.tech_tree
    tree.set_zoom(1.0)
    await process_frame

    var scroll: ScrollContainer = tree._scroll
    var middle: Vector2 = scroll.get_global_rect().get_center()
    var point_before: Vector2 = _content_point(tree, middle)
    var fingers: Array = [middle + Vector2(-40, 0), middle + Vector2(40, 0)]
    _touch(0, fingers[0], true)
    _touch(1, fingers[1], true)
    check(tree._pinching, "two fingers over the tree start a pinch", state)

    fingers = [middle + Vector2(-60, 0), middle + Vector2(60, 0)]
    _drag(0, fingers[0])
    _drag(1, fingers[1])
    check(is_equal_approx(tree._zoom_visual, 1.5),
        "spreading the fingers zooms the tree in (%.3f)" % tree._zoom_visual, state)
    check(_content_point(tree, middle).distance_to(point_before) < 3.0,
        "the point between the fingers stays in place (%.3f px)"
            % _content_point(tree, middle).distance_to(point_before), state)
    # A continuous pinch sends many drags; the error of one step must not accumulate.
    for _i in range(6):
        _drag(0, middle + Vector2(-70, 0))
        _drag(1, middle + Vector2(70, 0))
        _drag(0, middle + Vector2(-60, 0))
        _drag(1, middle + Vector2(60, 0))
    check(_content_point(tree, middle).distance_to(point_before) < 3.0,
        "a long pinch does not drift away from the fingers (%.3f px)"
            % _content_point(tree, middle).distance_to(point_before), state)

    # The pan of the tree is driven by the raw LMB events. The emulated ones of a pinch
    # must not start it (the release of an emulated click must not start a research).
    check(not tree._drag_possible, "the emulated press does not start a pan of the tree", state)

    _touch(0, fingers[0], false)
    _touch(1, fingers[1], false)
    check(not tree._pinching, "lifting a finger ends the pinch of the tree", state)
    var config := ConfigFile.new()
    config.load("user://settings.cfg")
    check(is_equal_approx(float(config.get_value("interface", "tech_zoom", -1.0)), tree._zoom_visual),
        "the zoom reached by the fingers is stored", state)

func _content_point(tree, screen: Vector2) -> Vector2:
    var scroll: ScrollContainer = tree._scroll
    var offsets := Vector2(scroll.scroll_horizontal, scroll.scroll_vertical)
    return (screen - scroll.global_position + offsets - tree._content.position) / tree._content.scale.x

func _touch(index: int, pos: Vector2, pressed: bool) -> void:
    var event := InputEventScreenTouch.new()
    event.index = index
    event.position = pos
    event.pressed = pressed
    get_root().push_input(event, true)
    await process_frame

func _drag(index: int, pos: Vector2) -> void:
    var event := InputEventScreenDrag.new()
    event.index = index
    event.position = pos
    get_root().push_input(event, true)
    await process_frame

func _mouse_button(index: int, pos: Vector2, pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = index
    event.position = pos
    event.global_position = pos
    event.pressed = pressed
    return event

func check(condition: bool, message: String, state: Dictionary) -> void:
    if condition:
        print("OK: ", message)
    else:
        state["failed"] = true
        push_error("ASSERT FAILED: " + message)
