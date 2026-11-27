# Headless test of the size and the scrolling of the building details window:
#   godot --headless --path . --script res://tests/test_building_panel_slots_fit.gd
#
# The "Consumes:" section of a profession can have many rows, and a building can
# have many production slots. The window fits its content up to the viewport,
# hides a long supply list behind its header, and scrolls the whole content
# when it still does not fit. The close button stays outside the scroll.
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")

var _failed := false

func _initialize():
    WATCHDOG.arm(self)
    _run()

func _run() -> void:
    get_root().get_node("SaveManager").new_game()
    var gdata = get_root().get_node("GameData")
    var city = get_root().get_node("CityData")

    # The building with the longest professional supply list, derived from the data.
    var building_id := ""
    var row_count := 0
    for b in gdata.buildings:
        var id := str(b.get("id", ""))
        var prof := str(gdata.get_profession_for_building(id))
        if prof.is_empty():
            continue
        var rows: Array = gdata.get_profession_consumption(prof, id)
        if rows.size() > row_count:
            building_id = id
            row_count = rows.size()
    check(not building_id.is_empty() and row_count >= 6,
        "the data has a building with a long list of supplies (got %s, %d rows)"
            % [building_id, row_count])
    if building_id.is_empty():
        _finish()
        return

    city.city_built_buildings = [{"id": building_id, "slots": ["empty"], "quality_priority": "best"}]
    var holder := Control.new()
    root.add_child(holder)
    var ui_helpers = load("res://scripts/ui_helpers.gd").new()
    ui_helpers.setup(holder, Label.new())
    holder.add_child(ui_helpers)
    var panel = load("res://scripts/building_panel.gd").new()
    root.add_child(panel)
    await process_frame
    await process_frame
    panel.open(building_id, {
        "products": gdata.products,
        "raw_resources": gdata.raw_resources,
        "crafts_data": gdata.crafts,
        "ui_helpers": ui_helpers,
    })
    await process_frame
    await process_frame

    check(panel.visible, "the building details window is open")
    check(panel.consumption_box.visible, "the long list of supplies is shown")
    var window := panel.panel as Control
    var window_scroll := panel.content_vbox.get_parent() as ScrollContainer
    check(window_scroll != null, "the whole content of the window lives in one scroll")
    if window_scroll == null:
        _finish()
        return
    var viewport_size: Vector2 = panel.get_viewport_rect().size
    check(window.size.y <= viewport_size.y,
        "the window stays within the viewport (actual %.1f of %.1f)"
            % [window.size.y, viewport_size.y])

    # A long supply list is hidden behind its header, and the slots are reachable
    # without scrolling — the case that used to hide them completely.
    var toggle := panel._consumption_toggle as Button
    check(toggle != null and toggle.visible, "the long list has a toggle in its header")
    var list := panel._consumption_rows as VBoxContainer
    check(list != null and list.get_child_count() == row_count, "all supply rows are built")
    if toggle == null or list == null:
        _finish()
        return
    check(_visible_rows(list) == 0,
        "no rows are shown when the list is collapsed (got %d)" % _visible_rows(list))
    var first_slot := panel.slots_container.get_child(1) as Control
    check(_intersects(first_slot.get_global_rect(), window_scroll.get_global_rect()),
        "the first slot is visible without scrolling")
    var collapsed_height := window.size.y

    toggle.pressed.emit()
    await process_frame
    await process_frame
    check(_visible_rows(list) == row_count,
        "all rows are shown after expanding (got %d)" % _visible_rows(list))
    check(window.size.y > collapsed_height,
        "the window grows when the list expands (%.1f -> %.1f)"
            % [collapsed_height, window.size.y])

    # A periodic rebuild must not undo the choice of the player.
    panel._refresh()
    await process_frame
    await process_frame
    list = panel._consumption_rows as VBoxContainer
    toggle = panel._consumption_toggle as Button
    check(list != null and _visible_rows(list) == row_count,
        "a refresh keeps the list expanded")
    if toggle != null and list != null:
        toggle.pressed.emit()
        await process_frame
        await process_frame
        check(_visible_rows(list) == 0,
            "the list collapses again (got %d)" % _visible_rows(list))

    # A content taller than the viewport must scroll, while the close button
    # stays reachable outside the scroll.
    var many := []
    for i in range(40):
        many.append("empty")
    city.city_built_buildings[0]["slots"] = many
    panel._refresh()
    await process_frame
    await process_frame
    var bar := window_scroll.get_v_scroll_bar()
    check(bar != null and bar.visible, "a long content shows the vertical scrollbar")
    if bar != null:
        window_scroll.scroll_vertical = int(bar.max_value)
        await process_frame
        await process_frame
        var last_slot := panel.slots_container.get_child(panel.slots_container.get_child_count() - 1) as Control
        check(_intersects(last_slot.get_global_rect(), window_scroll.get_global_rect()),
            "the last slot can be scrolled into view")
    var close_rect: Rect2 = panel.close_button.get_global_rect()
    check(close_rect.end.y <= window.get_global_rect().end.y + 1.0,
        "the close button stays inside the window")
    _finish()

func _visible_rows(list: VBoxContainer) -> int:
    var result := 0
    for child in list.get_children():
        if (child as Control).visible:
            result += 1
    return result

func _intersects(a: Rect2, b: Rect2) -> bool:
    return a.position.y < b.end.y and a.end.y > b.position.y

func _finish() -> void:
    WATCHDOG.report_skipped()
    if _failed:
        print("BUILDING PANEL SLOTS FIT TEST FAILED")
        quit(1)
    else:
        print("BUILDING PANEL SLOTS FIT TEST OK")
        quit(0)

func check(cond: bool, msg: String) -> void:
    if cond:
        print("OK: ", msg)
    else:
        _failed = true
        push_error("ASSERT FAILED: " + msg)
        print("ASSERT FAILED: ", msg)
