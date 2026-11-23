# Headless test of the map view across a change of the interface size:
#   godot --headless --path . --script res://tests/test_map_view_scale.gd
#
# The offsets are calibrated for the zoom the map starts with. A resize (a window resize or a
# change of the interface scale) has to keep that calibration. Recomputing them with the zoom
# of the moment used to leave the world shifted after a 200% -> 100% round-trip, so the
# symmetric scroll clamp stopped matching the picture and one side of the map was unreachable.
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
    get_root().get_node("SaveManager").new_game()
    var map = load("res://scenes/MainMap.tscn").instantiate()
    get_root().add_child(map)
    for _i in range(4):
        await process_frame

    # Calibrate at zoom 1, then zoom in the way the player does during the game.
    map.set_zoom(1.0)
    map._calc_offsets()
    map.set_zoom(1.5)
    map.scroll_offset = Vector2.ZERO
    var original := Vector2(map.offset_x, map.offset_y)

    UiScale.apply(2.0)
    await process_frame
    await process_frame
    var enlarged := Vector2(map.offset_x, map.offset_y)
    _check(not enlarged.is_equal_approx(original),
        "a larger interface rescales the offsets", state)

    UiScale.apply(1.0)
    await process_frame
    await process_frame
    var restored := Vector2(map.offset_x, map.offset_y)
    _check(restored.is_equal_approx(original),
        "returning to 100%% restores the offsets (%.2f,%.2f -> %.2f,%.2f)"
            % [original.x, original.y, restored.x, restored.y], state)
    _check(is_equal_approx(map.zoom, 1.5),
        "the round-trip does not change the zoom", state)

    map.free()
    UiScale.apply(UiScale.DEFAULT)
    _finish(state)

func _finish(state: Dictionary) -> void:
    WATCHDOG.report_skipped()
    if state["failed"]:
        print("MAP VIEW SCALE TEST FAILED")
        quit(1)
    else:
        print("MAP VIEW SCALE TEST OK")
        quit(0)
