# Test of the zoom of the technology tree.
#   godot --headless --path . --script res://tests/test_tech_tree_zoom.gd
#
# The wheel zooms the tree, as the wheel zooms the map. The tree is drawn as a scaled
# picture of its layout, and the place of the tree under the cursor stays under the
# cursor.
#
# Checks:
#   1. The wheel over the tree zooms it, and the tree grows.
#   2. The tree is not rebuilt for the zoom — it stays a scaled picture.
#   3. The zoom is limited by ZOOM_MIN / ZOOM_MAX.
#   4. The technology under the cursor stays under the cursor — both for a single notch
#      of the wheel, and for a series of notches.
#   4c. A zoom in at the right edge, where the scroll is already at its end, stays put —
#       the range of the bars lags one layout pass behind the growing tree.
#   5. The wheel over a row of the unlocked content that overflows does not zoom the tree.
#   6. The wheel outside the tree does not zoom it.
#   7. The zoom is stored in the settings.
extends SceneTree

# The hang watchdog — see tests/watchdog.gd.
const WATCHDOG = preload("res://tests/watchdog.gd")
# Enough frames for the deferred layout of the freshly built tree.
const SETTLE_FRAMES := 4

func _initialize():
    WATCHDOG.arm(self)
    _run()

func _run() -> void:
    var state: Dictionary = {"failed": false}
    get_root().get_node("SaveManager").new_game()
    var main_map = load("res://scenes/MainMap.tscn").instantiate()
    get_root().add_child(main_map)
    for _i in range(SETTLE_FRAMES):
        await process_frame
    # A headless window is square, and with "expand" the viewport inherits its aspect.
    # The project canvas is 16:9: without this the tree panel is taller than the tree,
    # the vertical scroll stays at zero and the zoom anchor has nothing to compensate.
    get_root().size = Vector2i(1280, 720)
    for _i in range(SETTLE_FRAMES):
        await process_frame
    main_map.open_city()
    for _i in range(SETTLE_FRAMES):
        await process_frame
    var city_ui = main_map.get_node_or_null("CityUI")
    check(city_ui != null, "CityUI is found", state)
    if city_ui == null:
        _finish(state)
        return

    city_ui.show_technologies_tab()
    for _i in range(SETTLE_FRAMES):
        await process_frame

    var tree = city_ui.tech_tree
    var scroll: ScrollContainer = tree._scroll
    # The zoom is a player preference — the test starts from a known value and puts the
    # value of the player back at the end.
    var original_zoom: float = tree._zoom
    tree.set_zoom(1.0)
    await _settle()

    var width_at_one: float = tree._inner.custom_minimum_size.x

    # 1. The wheel over the tree zooms it. The point of the wheel stands over a technology
    # whose row of the unlocked content does not overflow — such a row keeps the wheel for
    # itself (see the check 5 below).
    var zoomed_id: String = _visible_tech_id(tree, scroll)
    var button_before: Button = _tech_button(tree, zoomed_id)
    var wheel_pos: Vector2 = _zoom_point(tree, scroll)
    await _wheel(tree, MOUSE_BUTTON_WHEEL_UP, wheel_pos)
    check(tree._zoom_target > 1.0,
        "the wheel sets the target of the zoom (%.2f)" % tree._zoom_target, state)
    check(tree._zoom_visual < tree._zoom_target,
        "the zoom approaches its target smoothly (%.2f of %.2f)"
            % [tree._zoom_visual, tree._zoom_target], state)
    await _settle_zoom(tree)
    check(tree._zoom_visual > 1.0, "the tree is zoomed (%.2f)" % tree._zoom_visual, state)
    check(tree._inner.custom_minimum_size.x > width_at_one,
        "the tree grows with the zoom (%.0f of %.0f)"
            % [tree._inner.custom_minimum_size.x, width_at_one], state)
    # 2. The tree is not rebuilt for the zoom: it stays a scaled picture of its layout.
    # A rebuild of the tree of 76 technologies would freeze the game for about 0.12 s
    # right after the gesture, and the scaled picture is as sharp as the native one.
    check(not is_equal_approx(tree._zoom, tree._zoom_visual),
        "the tree is not rebuilt for its zoom (%.2f of %.2f)"
            % [tree._zoom, tree._zoom_visual], state)
    check(is_equal_approx(tree._content.scale.x, tree._zoom_visual / tree._zoom),
        "the tree is shown as a scaled picture (%.3f)" % tree._content.scale.x, state)
    check(_tech_button(tree, zoomed_id) == button_before,
        "the buttons of the tree are the same after the zoom", state)

    # 3. The zoom is limited.
    for _i in range(10):
        await _wheel(tree, MOUSE_BUTTON_WHEEL_UP, wheel_pos)
    check(is_equal_approx(tree._zoom_target, tree.ZOOM_MAX),
        "the zoom stops at ZOOM_MAX (%.2f)" % tree._zoom_target, state)
    await _settle_zoom(tree)
    check(is_equal_approx(tree._zoom_visual, tree.ZOOM_MAX),
        "the tree reaches ZOOM_MAX (%.2f)" % tree._zoom_visual, state)
    for _i in range(20):
        await _wheel(tree, MOUSE_BUTTON_WHEEL_DOWN, wheel_pos)
    check(is_equal_approx(tree._zoom_target, tree.ZOOM_MIN),
        "the zoom stops at ZOOM_MIN (%.2f)" % tree._zoom_target, state)
    await _settle_zoom(tree)
    check(is_equal_approx(tree._zoom_visual, tree.ZOOM_MIN),
        "the tree reaches ZOOM_MIN (%.2f)" % tree._zoom_visual, state)

    # 4. The technology under the cursor stays under the cursor.
    tree.set_zoom(1.0)
    await _settle()
    var anchor_id: String = _visible_tech_id(tree, scroll)
    check(not anchor_id.is_empty(), "a visible technology is found", state)
    if not anchor_id.is_empty():
        var before: Vector2 = _tech_button(tree, anchor_id).get_global_rect().get_center()
        await _wheel(tree, MOUSE_BUTTON_WHEEL_UP, before)
        await _settle_zoom(tree)
        var after: Vector2 = _tech_button(tree, anchor_id).get_global_rect().get_center()
        check(tree._zoom_visual > 1.0, "the wheel over the technology zooms the tree (%.2f)" % tree._zoom_visual, state)
        check(before.distance_to(after) < 3.0,
            "the technology under the cursor stays under it (%.1f px)"
                % before.distance_to(after), state)

    # 4b. Several notches in a row: the second notch arrives while the tree is still
    # scaled, therefore the anchor is captured in the coordinates of the content.
    tree.set_zoom(1.0)
    await _settle()
    var multi_id: String = _visible_tech_id(tree, scroll)
    check(not multi_id.is_empty(), "a visible technology is found for the series of the notches", state)
    if not multi_id.is_empty():
        var cursor: Vector2 = _tech_button(tree, multi_id).get_global_rect().get_center()
        var point_before: Vector2 = _content_point(tree, cursor)
        for _n in range(3):
            await _wheel(tree, MOUSE_BUTTON_WHEEL_UP, cursor)
        await _settle_zoom(tree)
        var point_after: Vector2 = _content_point(tree, cursor)
        check(tree._zoom_visual > 1.15, "the series of the notches zooms the tree (%.2f)" % tree._zoom_visual, state)
        # The point of the tree under the cursor stays exactly under the cursor: the
        # remainder of the whole pixels of the scroll is given to the content. The tree is
        # not rebuilt, therefore the coordinates of the content do not change.
        var drift: float = point_after.distance_to(point_before)
        check(drift < 1.0,
            "the point of the tree under the cursor stays under it after a series of the notches (%.1f px)"
                % drift, state)

    # 4c. The right edge of the tree: the scroll is at its end, and zooming in grows the
    # content faster than the bars refresh their range. The point under the cursor must
    # not jump while the bars catch up.
    tree.set_zoom(1.0)
    await _settle()
    for _j in range(6):
        scroll.scroll_horizontal = 100000
        await process_frame
        await process_frame
    var hbar := scroll.get_h_scroll_bar()
    check(scroll.scroll_horizontal >= hbar.max_value - hbar.page - 2.0,
        "the tree is scrolled to its right edge (%.0f of %.0f)"
            % [scroll.scroll_horizontal, hbar.max_value - hbar.page], state)
    var edge_cursor: Vector2 = scroll.get_global_rect().end + Vector2(-6.0, -scroll.size.y * 0.5)
    var edge_before: Vector2 = _content_point(tree, edge_cursor)
    var edge_event := InputEventMouseButton.new()
    edge_event.button_index = MOUSE_BUTTON_WHEEL_UP
    edge_event.pressed = true
    edge_event.position = edge_cursor
    edge_event.global_position = edge_cursor
    get_root().push_input(edge_event, true)
    var edge_drift: float = 0.0
    for _f in range(400):
        await process_frame
        edge_drift = maxf(edge_drift, _content_point(tree, edge_cursor).distance_to(edge_before))
        if not tree._zoom_animating:
            break
    check(tree._zoom_visual > 1.0, "the wheel at the right edge zooms the tree (%.2f)" % tree._zoom_visual, state)
    check(edge_drift < 2.0,
        "the tree under the cursor does not jump while the bars catch up (%.1f px)"
            % edge_drift, state)

    # 5. The wheel over a row of the unlocked content that overflows scrolls the row and
    # does not zoom the tree.
    var row_pos: Vector2 = _overflowing_row_position(tree)
    if row_pos == Vector2.ZERO:
        print("SKIP: no row of the unlocked content overflows")
    else:
        var zoom_before: float = tree._zoom_visual
        await _wheel(tree, MOUSE_BUTTON_WHEEL_UP, row_pos)
        await _settle()
        check(is_equal_approx(tree._zoom_visual, zoom_before),
            "the wheel over the row of the unlocked content does not zoom the tree (%.2f)"
                % tree._zoom_visual, state)

    # 6. The wheel outside the tree does not zoom it.
    var zoom_before_outside: float = tree._zoom_visual
    await _wheel(tree, MOUSE_BUTTON_WHEEL_UP, scroll.get_global_rect().position - Vector2(40, 40))
    await _settle()
    check(is_equal_approx(tree._zoom_visual, zoom_before_outside),
        "the wheel outside the tree does not zoom it (%.2f)" % tree._zoom_visual, state)

    # 7. The zoom is a player preference — it lives in the settings.
    var config := ConfigFile.new()
    config.load("user://settings.cfg")
    check(is_equal_approx(float(config.get_value("interface", "tech_zoom", -1.0)), tree._zoom_visual),
        "the zoom is stored in the settings (%.2f)" % tree._zoom_visual, state)

    # The preference of the player is put back.
    tree.set_zoom(original_zoom)
    await _settle()

    _finish(state)

# A notch of the wheel over the tree. The event is pushed into the viewport as it is
# delivered to the game: the coordinates of the canvas, without the transformation of the
# window (the headless window scales the events of the mouse by a factor of its own).
func _wheel(tree, button_index: int, global_pos: Vector2) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = button_index
    event.pressed = true
    event.position = global_pos
    event.global_position = global_pos
    get_root().push_input(event, true)
    await process_frame
    await process_frame

# The id of a technology whose button lies inside the visible area of the tree and whose
# row of the unlocked content does not overflow — such a row keeps the wheel for itself.
func _visible_tech_id(tree, scroll: ScrollContainer) -> String:
    var rect: Rect2 = scroll.get_global_rect()
    for tech_id in tree._tech_nodes:
        var btn: Button = tree._tech_nodes[tech_id]["button"]
        if not is_instance_valid(btn):
            continue
        if not rect.has_point(btn.get_global_rect().get_center()):
            continue
        if _row_overflows(tree, btn):
            continue
        return tech_id
    return ""

# Whether the row of the unlocked content of the button overflows.
func _row_overflows(tree, btn: Button) -> bool:
    var strip := btn.get_node_or_null("UnlockIconsScroll") as ScrollContainer
    if strip == null:
        return false
    var row := strip.get_node_or_null("UnlockIconsRow") as HBoxContainer
    return row != null and tree._unlock_row_overflows(row)

# A point of the tree at which the wheel zooms it: the middle of a visible technology
# whose row of the unlocked content does not overflow.
func _zoom_point(tree, scroll: ScrollContainer) -> Vector2:
    var tech_id: String = _visible_tech_id(tree, scroll)
    if not tech_id.is_empty():
        return _tech_button(tree, tech_id).get_global_rect().get_center()
    return scroll.get_global_rect().get_center()

func _tech_button(tree, tech_id: String) -> Button:
    return tree._tech_nodes[tech_id]["button"]

# The position of an icon of a row of the unlocked content that overflows (such a row
# scrolls itself by the wheel).
func _overflowing_row_position(tree) -> Vector2:
    for tech_id in tree._tech_nodes:
        var btn: Button = tree._tech_nodes[tech_id]["button"]
        if not is_instance_valid(btn):
            continue
        var strip := btn.get_node_or_null("UnlockIconsScroll") as ScrollContainer
        if strip == null:
            continue
        var row := strip.get_node_or_null("UnlockIconsRow") as HBoxContainer
        if row == null or not tree._unlock_row_overflows(row):
            continue
        for child in row.get_children():
            if child is Control:
                return (child as Control).get_global_rect().get_center()
    return Vector2.ZERO
# The place of a point of the screen in the coordinates of the content of the tree.
func _content_point(tree, screen: Vector2) -> Vector2:
    var scroll: ScrollContainer = tree._scroll
    var offsets := Vector2(scroll.scroll_horizontal, scroll.scroll_vertical)
    return (screen - scroll.global_position + offsets - tree._content.position) / tree._content.scale.x

func _settle() -> void:
    for _i in range(SETTLE_FRAMES):
        await process_frame

# Waits until the zoom reaches its target: the tree approaches it smoothly, and it keeps
# the scale it has reached when the gesture settles.
func _settle_zoom(tree) -> void:
    for _i in range(400):
        if not tree._zoom_animating:
            await process_frame
            return
        await process_frame

func _finish(state: Dictionary) -> void:
    WATCHDOG.report_skipped()
    if state["failed"]:
        print("TECH TREE ZOOM TEST FAILED")
        quit(1)
    else:
        print("TECH TREE ZOOM TEST OK")
        quit(0)

func check(condition: bool, message: String, state: Dictionary) -> void:
    if condition:
        print("OK: ", message)
    else:
        state["failed"] = true
        push_error("ASSERT FAILED: " + message)
