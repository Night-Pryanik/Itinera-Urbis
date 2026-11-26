# Headless test of the interface sizes offered as supported:
#   godot --headless --path . --script res://tests/test_supported_ui_scales.gd
#
# At 110%, 125% and 150% the new game dialog must keep both columns side by side in a
# 1920x1080 window. Larger sizes are offered as experimental.
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")
const UiScale = preload("res://scripts/ui_scale.gd")

const SCREEN := Vector2i(1920, 1080)

func _initialize() -> void:
    WATCHDOG.arm(self)
    _run()

func _check(condition: bool, label: String, state: Dictionary) -> void:
    if not condition:
        state["failed"] = true
        print("FAIL: " + label)

func _run() -> void:
    var state := {"failed": false}
    _check(is_equal_approx(UiScale.SUPPORTED_MAX, 1.5),
            "the supported sizes end at 150%%", state)
    for value in [1.1, 1.25, 1.5]:
        _check(not UiScale.is_experimental(value),
                "%d%% is supported" % int(round(value * 100.0)), state)
    for value in [1.75, 2.0]:
        _check(UiScale.is_experimental(value),
                "%d%% is experimental" % int(round(value * 100.0)), state)

    var menu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
    get_root().add_child(menu)
    await process_frame
    await process_frame
    for value in [1.1, 1.25, 1.5]:
        UiScale.apply(value)
        get_root().size = SCREEN
        await process_frame
        await process_frame
        if menu.new_game_dialog == null or not menu.new_game_dialog.visible:
            menu._on_new_game()
            for _i in 4:
                await process_frame
        else:
            menu._popup_new_game_dialog()
            await process_frame
        menu.tab_container.current_tab = menu.TAB_WORLD
        await process_frame
        await process_frame
        var screen := get_root().get_visible_rect().size
        var picture := menu.tab_container.get_tab_control(menu.TAB_WORLD).find_child(
                "PreviewScroll", true, false) as ScrollContainer
        var settings := menu.tab_container.get_tab_control(menu.TAB_WORLD).find_child(
                "SettingsScroll", true, false) as ScrollContainer
        _check(settings != null and not settings.get_h_scroll_bar().visible,
                "the settings fit horizontally at %d%%" % int(round(value * 100.0)), state)
        var legend := float(menu._legend_width(menu.world_previews[1]))
        _check(picture != null and picture.custom_minimum_size.x >= legend \
                + float(menu.PREVIEW_SIDE_MARGIN) * 2.0 + 3.0,
                "the legend fits the picture column at %d%%" % int(round(value * 100.0)), state)
        _check(picture != null and not picture.get_v_scroll_bar().visible,
                "the picture fits vertically at %d%%" % int(round(value * 100.0)), state)
        var density: LineEdit = menu.sea_controls["edge_island_density"]["control"]
        var extra: int = menu.NUMBER_FIELD_SCALE_EXTRA if value > 1.01 else 0
        var expected := maxi(menu.MIN_NUMBER_FIELD_WIDTH,
                roundi(float(menu.STEP_FIELD_WIDTH) / value) + extra)
        _check(density.custom_minimum_size.x == float(expected),
                "a four-character value fits its field at %d%% (got %d, need %d)"
                        % [int(round(value * 100.0)), int(density.custom_minimum_size.x), expected],
                state)
        var deco := Vector2(menu.new_game_dialog.get_size_with_decorations())
        _check(deco.x <= screen.x + 1.0,
                "the window fits the screen width at %d%% (%d of %d)"
                        % [int(round(value * 100.0)), int(deco.x), int(screen.x)], state)
    if menu.new_game_dialog != null:
        menu.new_game_dialog.hide()
    UiScale.apply(UiScale.DEFAULT)
    menu.free()
    await process_frame
    _finish(state)

func _finish(state: Dictionary) -> void:
    WATCHDOG.report_skipped()
    if state["failed"]:
        print("SUPPORTED UI SCALES TEST FAILED")
        quit(1)
    else:
        print("SUPPORTED UI SCALES TEST OK")
        quit(0)
