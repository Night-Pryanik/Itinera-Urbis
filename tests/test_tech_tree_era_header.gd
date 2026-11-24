# Test of the pinned headings of the eras of the technology tree.
#   godot --headless --path . --script res://tests/test_tech_tree_era_header.gd
#
# The headings must stay at the top of the scroll viewport while the columns move beneath
# them, and they must keep following the columns horizontally. The tree is a scaled picture,
# so the check is made in global coordinates at several scroll positions and at a zoom away
# from the one the tree was built for.
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")
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
    get_root().size = Vector2i(1280, 720)
    for _i in range(SETTLE_FRAMES):
        await process_frame
    main_map.open_city()
    for _i in range(SETTLE_FRAMES):
        await process_frame
    var city_ui = main_map.get_node_or_null("CityUI")
    if city_ui == null:
        check(false, "CityUI is found", state)
        _finish(state)
        return
    city_ui.show_technologies_tab()
    for _i in range(SETTLE_FRAMES):
        await process_frame

    var tree = city_ui.tech_tree
    var scroll: ScrollContainer = tree._scroll
    check(tree._era_labels.size() > 0, "the headings of the eras exist", state)
    check(tree._era_strip != null, "the band behind the headings exists", state)

    for v in [0, 120, 400, 900]:
        scroll.scroll_vertical = v
        await process_frame
        await process_frame
        var top: float = scroll.global_position.y
        var pinned := true
        for lab in tree._era_labels:
            if absf(lab.global_position.y - top) > 1.0:
                pinned = false
        check(pinned, "the headings stay at the top of the viewport (scroll %d)" % v, state)
        check(is_equal_approx(tree._era_strip.global_position.y, top),
            "the band stays at the top of the viewport (scroll %d)" % v, state)

    scroll.scroll_vertical = 0
    scroll.scroll_horizontal = 0
    await process_frame
    await process_frame
    scroll.scroll_horizontal = 150
    await process_frame
    await process_frame
    var first_group: Dictionary = tree._era_groups[0]
    var page_width: float = scroll.size.x
    var vbar = scroll.get_v_scroll_bar()
    if vbar != null and vbar.visible:
        page_width -= vbar.size.x
    var band_left: float = tree._era_strip.global_position.x
    var band_right: float = band_left + tree._era_strip.size.x * tree._content.scale.x
    var span_left: float = maxf(band_left, tree._content.global_position.x)
    var span_right: float = minf(band_right,
        tree._content.global_position.x + tree._content.scale.x * float(first_group["x_boundary"]))
    var expected_center: float = (span_left + span_right) * 0.5
    var actual_center: float = tree._era_labels[0].global_position.x + tree._era_labels[0].size.x * 0.5
    check(absf(actual_center - expected_center) <= 1.0,
        "the heading is centred in the visible part of its era", state)

    # With the boundary between two eras in the middle of the viewport, both headings must
    # remain visible, each inside its own era.
    tree.set_zoom(1.0)
    for _i in range(SETTLE_FRAMES):
        await process_frame
    var boundary: float = float(tree._era_groups[0]["x_boundary"])
    scroll.scroll_horizontal = maxf(0.0, boundary - scroll.size.x * 0.5)
    await process_frame
    await process_frame
    var viewport_left: float = scroll.global_position.x
    var viewport_right: float = viewport_left + page_width
    band_left = tree._era_strip.global_position.x
    band_right = band_left + tree._era_strip.size.x * tree._content.scale.x
    check(band_left > viewport_left and band_right < viewport_right,
        "the band stops inside the frame of the window", state)
    var first: Control = tree._era_labels[0]
    var second: Control = tree._era_labels[1]
    check(first.global_position.x >= viewport_left - 1.0
        and first.global_position.x + first.size.x <= viewport_right + 1.0,
        "the heading of the left era stays in view", state)
    check(second.global_position.x >= viewport_left - 1.0
        and second.global_position.x + second.size.x <= viewport_right + 1.0,
        "the heading of the right era stays in view", state)
    var boundary_screen: float = tree._content.global_position.x + tree._content.scale.x * boundary
    check(first.global_position.x + first.size.x <= boundary_screen + 1.0,
        "the heading stays inside its era", state)
    var left_center: float = (band_left + boundary_screen) * 0.5
    var right_center: float = (boundary_screen + band_right) * 0.5
    check(absf(first.global_position.x + first.size.x * 0.5 - left_center) <= 1.0,
        "the left heading is centred in its visible area", state)
    check(absf(second.global_position.x + second.size.x * 0.5 - right_center) <= 1.0,
        "the right heading is centred in its visible area", state)

    # A sliver of the era narrower than the whole heading box must still show the text:
    # the label is centred in the sliver instead of being dropped off the screen.
    scroll.scroll_horizontal = boundary - 150.0
    await process_frame
    await process_frame
    var sliver_end: float = tree._content.global_position.x + tree._content.scale.x * boundary
    var text_center: float = first.global_position.x + first.size.x * 0.5
    check(text_center > viewport_left + 1.0 and text_center < sliver_end - 1.0,
        "the heading stays visible on a narrow sliver of its era", state)

    scroll.scroll_horizontal = 0
    var center: Vector2 = scroll.get_global_rect().get_center()
    tree.zoom_by(1.15, center)
    for _i in range(30):
        await process_frame
    scroll.scroll_vertical = 350
    await process_frame
    await process_frame
    var top_zoom: float = scroll.global_position.y
    var pinned_zoom := true
    for lab in tree._era_labels:
        if absf(lab.global_position.y - top_zoom) > 1.0:
            pinned_zoom = false
    check(pinned_zoom, "the headings stay pinned while the tree is scaled", state)

    _finish(state)

func _finish(state: Dictionary) -> void:
    WATCHDOG.report_skipped()
    if state["failed"]:
        print("TECH TREE ERA HEADER TEST FAILED")
        quit(1)
    else:
        print("TECH TREE ERA HEADER TEST OK")
        quit(0)

func check(condition: bool, message: String, state: Dictionary) -> void:
    if condition:
        print("OK: ", message)
    else:
        state["failed"] = true
        push_error("ASSERT FAILED: " + message)
