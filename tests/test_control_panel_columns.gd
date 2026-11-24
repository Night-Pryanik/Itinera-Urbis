# Headless test of the bottom control panel at different interface sizes:
#   godot --headless --path . --script res://tests/test_control_panel_columns.gd
#
# The columns divide the panel by anchors. A larger interface scale shrinks the logical canvas
# and must shrink every column with it: fixed side offsets used to leave the middle column
# almost nothing while the two outer ones kept their old width.
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
    var root := get_root()
    var base := UiScale.base_factor()
    get_root().get_node("SaveManager").new_game()

    var map = load("res://scenes/MainMap.tscn").instantiate()
    root.add_child(map)
    for _i in range(4):
        await process_frame

    var panel := map.find_child("ControlPanel", true, false) as Control
    var info := map.find_child("InfoVBox", true, false) as Control
    var preview := map.find_child("PreviewContainer", true, false) as Control
    var actions := map.find_child("ActionsVBox", true, false) as Control
    var sep_left := map.find_child("SepInfoPreview", true, false) as Control
    var sep_right := map.find_child("SepPreviewActions", true, false) as Control
    _check(panel != null and info != null and preview != null and actions != null \
            and sep_left != null and sep_right != null,
        "the panel and its three columns are found", state)
    if panel == null or info == null or preview == null or actions == null \
            or sep_left == null or sep_right == null:
        _finish(state)
        return

    for size in [1.0, 1.5, 2.0]:
        UiScale.apply(size)
        await process_frame
        await process_frame
        var width := panel.size.x
        # The headless window is square, so the logical height follows the width; the share
        # is taken from the parent area, not from the window size in pixels.
        var share := panel.size.y / panel.get_parent_area_size().y
        _check(absf(share - 0.23) < 0.02,
            "at %d%% the panel takes the same share of the window (%.2f)"
                % [roundi(size * 100.0), share], state)
        _check(info.position.y >= 0.0 and actions.position.y >= 0.0
                and info.position.y + info.size.y <= panel.size.y + 1.0
                and preview.position.y + preview.size.y <= panel.size.y + 1.0
                and actions.position.y + actions.size.y <= panel.size.y + 1.0,
            "at %d%% the columns fit the panel height" % roundi(size * 100.0), state)
        var wi := info.size.x / width
        var wp := preview.size.x / width
        var wa := actions.size.x / width
        _check(wi > 0.24 and wi < 0.36 and wp > 0.34 and wp < 0.46 and wa > 0.24 and wa < 0.36,
            "at %d%% the columns keep their shares (%.2f / %.2f / %.2f)"
                % [roundi(size * 100.0), wi, wp, wa], state)
        _check(absf(wi - wa) < 0.03,
            "at %d%% the outer columns stay equal" % roundi(size * 100.0), state)
        _check(info.position.x + info.size.x <= preview.position.x + 1.0
                and preview.position.x + preview.size.x <= actions.position.x + 1.0,
            "at %d%% the columns do not overlap" % roundi(size * 100.0), state)
        var left_gap := sep_left.position.x + sep_left.size.x * 0.5 \
                - (info.position.x + info.size.x)
        var right_gap := sep_right.position.x + sep_right.size.x * 0.5 \
                - (preview.position.x + preview.size.x)
        _check(left_gap >= 0.0 and left_gap <= 12.0
                and right_gap >= 0.0 and right_gap <= 12.0,
            "at %d%% the rules sit on the column edges" % roundi(size * 100.0), state)

    # The collapse swaps the top anchor for the bottom one; expanding must bring the share back.
    panel._set_collapsed(true)
    await process_frame
    _check(is_equal_approx(panel.size.y, 28.0),
        "the collapsed panel is the height of the toggle button", state)
    panel._set_collapsed(false)
    await process_frame
    _check(absf(panel.size.y / panel.get_parent_area_size().y - 0.23) < 0.02,
        "expanding restores the share of the window", state)

    UiScale.apply(UiScale.DEFAULT)
    map.free()
    _finish(state)

func _finish(state: Dictionary) -> void:
    WATCHDOG.report_skipped()
    if state["failed"]:
        print("CONTROL PANEL COLUMNS TEST FAILED")
        quit(1)
    else:
        print("CONTROL PANEL COLUMNS TEST OK")
        quit(0)
