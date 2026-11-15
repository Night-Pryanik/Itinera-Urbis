# Headless test of the tooltip of the breakdown of the treasury in the ACTIVE PAUSE:
#   godot --headless --path . --script res://tests/test_treasury_tooltip_pause.gd
#
# The polling of the cursor over the label of the treasury lives in main_map._process —
# and that _process IS the simulation, therefore it stands still while the simulation is
# stopped. The tooltip of the breakdown must live anyway: the active pause keeps the
# interface on the screen, and the player has to be able to read the breakdown there.
#
# We check:
#   1) the state machine of the tooltip: the cursor on the label shows the breakdown
#      after the delay, and the cursor away from it hides the panel again;
#   2) the active pause forwards the polling to the map — therefore the tooltip of a
#      panel left over from before the pause does not hang over a stopped world;
#   3) the tooltip does not outlive the interface it belongs to: the pause and the
#      interface of the city hide it.
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")

# The stand-in for the map: the active pause forwards the polling of the tooltip to it,
# and the mock counts the calls. The real map is a node of the scene — it cannot be
# replaced in the test, therefore the forwarding is checked through the mock.
class MockMap:
    extends Node
    var treasury_polls: int = 0
    func _process_treasury_tooltip(_delta: float) -> void:
        treasury_polls += 1

var _failed := false

func _initialize() -> void:
    WATCHDOG.arm(self)
    _run()

func _run() -> void:
    get_root().get_node("SaveManager").new_game()

    var main_map = load("res://scenes/MainMap.tscn").instantiate()
    get_root().add_child(main_map)
    for _i in range(4):
        await process_frame

    var ap = main_map.active_pause
    if ap == null:
        check(false, "MainMap must own the active pause")
        _finish()
        return

    # The breakdown must not be empty: an empty breakdown hides the panel (there is
    # nothing to show). One expense in the window is enough.
    var cdata = get_root().get_node("CityData")
    cdata.treasury_expense_snapshot = {"Test expense": 5}

    var panel: Panel = main_map._map_ui_helpers.treasury_tooltip_panel
    var label = main_map.hud.get_node("VBoxContainer/TreasuryLabel")
    var label_center: Vector2 = label.get_global_rect().get_center()

    _test_state_machine(main_map, panel, label_center)
    _test_forwarding(ap, main_map, panel, label_center)
    _test_pause_hides(main_map, ap, panel, label_center)
    _test_city_hides(main_map, panel, label_center)

    _finish()

# -------------------------------------------------------
# 1. The state machine of the tooltip
# -------------------------------------------------------
func _test_state_machine(main_map, panel: Panel, label_center: Vector2) -> void:
    # The cursor on the label: the breakdown appears after the delay.
    main_map._update_treasury_tooltip(main_map.building_detail_delay + 0.1, label_center)
    check(panel.visible, "1: the cursor on the label shows the breakdown")

    # The cursor away from the label and from the panel: the panel is held for the grace
    # window and then hidden.
    var away: Vector2 = Vector2(1000, 700)
    check(not panel.get_global_rect().has_point(away),
            "1: the point of the test must be outside of the panel")
    for _i in range(6):
        main_map._update_treasury_tooltip(0.1, away)
    check(not panel.visible, "1: the cursor away from the label hides the breakdown")

# -------------------------------------------------------
# 2. The active pause forwards the polling
# -------------------------------------------------------
func _test_forwarding(ap, main_map, panel: Panel, label_center: Vector2) -> void:
    # The mock: the active pause must call the polling of the tooltip on the map.
    var mock := MockMap.new()
    get_root().add_child(mock)
    var saved_map = ap.main_map
    ap.main_map = mock
    ap._process(0.1)
    check(mock.treasury_polls == 1,
            "2: the active pause must forward the polling of the tooltip (%d calls)"
                % mock.treasury_polls)
    ap.main_map = saved_map
    mock.queue_free()

    # The real map: the panel, left over from before the pause, must not hang over a
    # stopped world. The cursor of the machine may stand anywhere, therefore the
    # expectation follows it: over the label or over the panel the breakdown stays,
    # anywhere else it goes away after the grace.
    ap.set_active(true)
    main_map._update_treasury_tooltip(main_map.building_detail_delay + 0.1, label_center)
    check(panel.visible, "2: the breakdown is shown while the world is stopped")
    var cursor: Vector2 = main_map.get_viewport().get_mouse_position()
    var expected_visible: bool = main_map._is_treasury_hovered(cursor)
    for _i in range(6):
        ap._process(0.1)
    check(panel.visible == expected_visible,
            "2: the panel must follow the cursor while the world is stopped (visible %s, expected %s)"
                % [str(panel.visible), str(expected_visible)])
    ap.set_active(false)

# -------------------------------------------------------
# 3. The pause and the interface of the city hide the tooltip
# -------------------------------------------------------
func _test_pause_hides(main_map, ap, panel: Panel, label_center: Vector2) -> void:
    main_map._update_treasury_tooltip(main_map.building_detail_delay + 0.1, label_center)
    check(panel.visible, "3: the breakdown is shown before the pause")
    ap.set_active(true)
    check(not panel.visible, "3: the pause must not leave the breakdown hanging")
    ap.set_active(false)

func _test_city_hides(main_map, panel: Panel, label_center: Vector2) -> void:
    main_map._update_treasury_tooltip(main_map.building_detail_delay + 0.1, label_center)
    check(panel.visible, "3: the breakdown is shown before the city interface")
    main_map.open_city()
    check(not panel.visible, "3: the interface of the city must not leave the breakdown hanging")
    main_map.city_ui.close_city()
    await process_frame
    check(main_map.hud.visible, "3: the HUD must come back with the map")

func _finish() -> void:
    WATCHDOG.report_skipped()
    if _failed:
        print("TREASURY TOOLTIP PAUSE TEST FAILED")
        quit(1)
    else:
        print("TREASURY TOOLTIP PAUSE TEST OK")
        quit(0)

func check(cond: bool, msg: String) -> void:
    if cond:
        print("OK: ", msg)
    else:
        _failed = true
        push_error("ASSERT FAILED: " + msg)
        print("ASSERT FAILED: ", msg)
