# Headless test of the new game window at a large interface size on a small screen:
#   godot --headless --path . --script res://tests/test_new_game_dialog_fit.gd
#
# The interface multiplier zooms the canvas, so a window laid out for the full canvas can
# end up below the screen with its OK and Cancel buttons out of reach. The window gives up
# room to a scroll instead of scaling its controls down: the fonts must still follow the
# chosen size, while the buttons land inside the screen.
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")
const UiScale = preload("res://scripts/ui_scale.gd")

const SCREEN := Vector2i(1280, 720)

func _initialize() -> void:
    WATCHDOG.arm(self)
    _run()

func _check(condition: bool, label: String, state: Dictionary) -> void:
    if not condition:
        state["failed"] = true
        print("FAIL: " + label)

func _run() -> void:
    var state := {"failed": false}
    var menu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
    get_root().add_child(menu)
    await process_frame
    await process_frame

    UiScale.apply(UiScale.MAXIMUM)
    menu.apply_ui_scale_compensation()
    get_root().size = SCREEN
    await process_frame
    await process_frame

    var screen: Vector2 = get_root().get_visible_rect().size
    _check(screen.y <= 400.0, "the zoomed canvas is small enough to need a fit (got %s)" % str(screen), state)

    menu._on_new_game()
    for _i in 4:
        await process_frame

    var dialog = menu.new_game_dialog
    _check(dialog != null and dialog.visible, "the new game dialog is open", state)
    if dialog == null:
        _finish(state)
        return

    _check(is_equal_approx(float(dialog.content_scale_factor), 1.0),
            "the window keeps the global interface scale", state)
    _check(is_equal_approx(get_root().content_scale_factor,
            UiScale.base_factor() * UiScale.MAXIMUM),
            "the interface multiplier is still applied to the canvas", state)

    var narrow := maxi(menu.MIN_NUMBER_FIELD_WIDTH,
            roundi(float(menu.STEP_FIELD_WIDTH) / UiScale.MAXIMUM)
                    + menu.NUMBER_FIELD_SCALE_EXTRA)
    var sea_edit: LineEdit = menu.sea_controls["max_sea_depth"]["control"]
    _check(menu.town_count_edit.custom_minimum_size.x == float(narrow)
            and sea_edit.custom_minimum_size.x == float(narrow),
            "number fields give up their extra canvas width at 200%% (got %d)"
                    % narrow, state)
    _check(menu.town_count_edit.get_combined_minimum_size().x <= float(narrow) + 8.0
            and sea_edit.get_combined_minimum_size().x <= float(narrow) + 8.0,
            "the fields actually shrink, not only their custom minimum", state)

    _check(menu.tab_container.custom_minimum_size.x < float(menu.DIALOG_CONTENT_WIDTH)
            and menu.tab_container.custom_minimum_size.y < float(menu.DIALOG_CONTENT_HEIGHT),
            "the tabs are fitted to the screen", state)

    menu.tab_container.current_tab = menu.TAB_WORLD
    await process_frame
    await process_frame
    var world: Node = menu.tab_container.get_tab_control(menu.TAB_WORLD)
    var settings_scroll := world.find_child("SettingsScroll", true, false) as ScrollContainer
    var preview_scroll := world.find_child("PreviewScroll", true, false) as ScrollContainer
    _check(settings_scroll != null and preview_scroll != null,
            "the world tab has a scroll for the settings and one for the picture", state)
    if settings_scroll != null and preview_scroll != null:
        var origin := Vector2(dialog.position)
        var left := Rect2(origin + settings_scroll.get_global_rect().position,
                settings_scroll.get_global_rect().size)
        var right := Rect2(origin + preview_scroll.get_global_rect().position,
                preview_scroll.get_global_rect().size)
        _check(left.end.x <= right.position.x + 1.0,
                "the two scrolls stay side by side", state)
        _check(left.position.x >= -1.0 and right.end.x <= screen.x + 1.0
                and left.position.y >= -1.0 and right.end.y <= screen.y + 1.0,
                "both scrolls stay inside the screen (%s / %s)" % [str(left), str(right)], state)
        var padding := settings_scroll.get_child(0) as MarginContainer
        _check(padding != null and padding.get_theme_constant("margin_right") >= menu.SCROLL_GUTTER,
                "the settings end before the scrollbar starts", state)
        var regenerate := menu.find_child("RegeneratePreviewButton", true, false) as Button
        if regenerate != null:
            var legend := float(menu._legend_width(menu.world_previews[1]))
            var limit := maxf(float(regenerate.get_combined_minimum_size().x), legend) \
                    + float(menu.PREVIEW_SIDE_MARGIN) * 4.0 + 5.0
            var width := float(preview_scroll.custom_minimum_size.x)
            _check(width >= legend + float(menu.PREVIEW_SIDE_MARGIN) * 2.0 + 3.0 and width <= limit,
                    "the picture column fits the legend (got %f, legend %f)" % [width, legend], state)

    var world_preview_rect := preview_scroll.get_global_rect() if preview_scroll != null else Rect2()
    menu.tab_container.current_tab = menu.TAB_CITY
    await process_frame
    await process_frame
    var city_control: Node = menu.tab_container.get_tab_control(menu.TAB_CITY)
    var city_preview := city_control.find_child("CityPreviewScroll", true, false) as ScrollContainer
    if city_preview != null and preview_scroll != null:
        var city_rect := city_preview.get_global_rect()
        _check(absf(city_rect.position.x - world_preview_rect.position.x) <= 1.0
                and absf(city_rect.size.x - world_preview_rect.size.x) <= 1.0,
                "the previews share one column position on both tabs", state)
    menu.tab_container.current_tab = menu.TAB_WORLD
    await process_frame

    var pos := Vector2(dialog.get_position_with_decorations())
    var size := Vector2(dialog.get_size_with_decorations())
    _check(pos.x >= -1.0 and pos.y >= -1.0
            and pos.x + size.x <= screen.x + 1.0 and pos.y + size.y <= screen.y + 1.0,
            "the window stays inside the screen (at %s, %s of %s)" % [str(pos), str(size), str(screen)], state)

    for button in [dialog.get_ok_button(), dialog.get_cancel_button()]:
        var rect: Rect2 = button.get_global_rect()
        var on_screen := Rect2(Vector2(dialog.position) + rect.position, rect.size)
        _check(on_screen.position.x >= -1.0 and on_screen.position.y >= -1.0
                and on_screen.end.x <= screen.x + 1.0 and on_screen.end.y <= screen.y + 1.0,
                "the button is reachable on the screen (%s)" % str(on_screen), state)

    dialog.hide()
    UiScale.apply(UiScale.DEFAULT)
    menu.free()
    await process_frame
    _finish(state)

func _finish(state: Dictionary) -> void:
    WATCHDOG.report_skipped()
    if state["failed"]:
        print("NEW GAME DIALOG FIT TEST FAILED")
        quit(1)
    else:
        print("NEW GAME DIALOG FIT TEST OK")
        quit(0)
