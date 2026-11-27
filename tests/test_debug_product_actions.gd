# Headless test of the shared product form of the debug menu:
#   godot --headless --path . --script res://tests/test_debug_product_actions.gd
#
# Checks:
#   1. All three items — add to storage, sell to the towns and craft — open the same product form,
#      and only the label of its last button follows the item. A redraw keeps the item.
#   2. A manual craft puts the chosen amount and quality on the shelves and books the units to the
#      mastery of the good, exactly as a release of a building does.
#   3. A debug sale only simulates the "sell" trigger: it records the chosen amount and quality of
#      the good with the fame manager, without touching the shelves, the treasury or a town.
#   4. The window is stretched to the control panel at the bottom of the canvas, so all the items
#      of the menu fit on one screen.
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")

class HudStub extends Node:
    var messages: Array = []

    func show_message(text: String, type: int) -> void:
        messages.append([text, type])

class FameStub extends Node:
    var sales: Array = []
    var produced: Array = []

    func record_sale(pid: String, breakdown: Dictionary) -> void:
        sales.append([pid, breakdown])

    func record_production(pid: String, amount: int, quality: String) -> void:
        produced.append([pid, amount, quality])

    func get_fame_trade_price_share(_pid: String) -> float:
        return 0.0

class MapStub extends Node:
    var hud: Node = null
    var city_ui: Node = null
    var map_renderer: Node = null
    var control_panel: Node = null
    var challenge_manager: Node = null
    var craft_mastery_manager: Node = null

var _gdata = null
var _city = null
var _debug = null
var _hud = null
var _fame = null
var _mastery = null


func _initialize():
    WATCHDOG.arm(self)
    _run()


func _run() -> void:
    var state: Dictionary = {"failed": false}
    await process_frame
    TranslationServer.set_locale("en")
    _gdata = get_root().get_node("GameData")
    _city = get_root().get_node("CityData")
    _gdata.load_all_data()
    _city.setup()

    var map := MapStub.new()
    map.name = "MainMap"
    _hud = HudStub.new()
    map.hud = _hud
    _fame = FameStub.new()
    map.challenge_manager = _fame
    var mastery_script = load("res://scripts/craft_mastery_manager.gd")
    _mastery = mastery_script.new()
    map.craft_mastery_manager = _mastery
    map.add_child(_mastery)
    get_root().add_child(map)

    # Both scripts reference the autoloads, so they are loaded at runtime: a preload would
    # compile them before the autoload identifiers exist in --script mode.
    var debug_script = load("res://scripts/debug_manager.gd")
    _debug = debug_script.new()
    get_root().add_child(_debug)
    _debug.initialize(map)

    if WATCHDOG.wants_case("form"):
        _test_form(state)
    if WATCHDOG.wants_case("craft"):
        _test_craft(state)
    if WATCHDOG.wants_case("sell"):
        _test_sell(state)
    if WATCHDOG.wants_case("height"):
        _test_height(state, map)

    WATCHDOG.report_skipped()
    if state["failed"]:
        print("DEBUG PRODUCT ACTIONS TEST FAILED")
        quit(1)
    else:
        print("DEBUG PRODUCT ACTIONS TEST OK")
        quit(0)


func check(cond: bool, msg: String, state: Dictionary) -> void:
    if not cond:
        push_error("ASSERT: " + msg)
        print("ASSERT FAILED: ", msg)
        state["failed"] = true


func _reset() -> void:
    _city.city_storage.clear()
    _city.city_quality_detail.clear()
    _mastery.produced.clear()
    _mastery.ranks.clear()
    _fame.sales.clear()
    _fame.produced.clear()
    _hud.messages.clear()


func _button_with(button_text: String) -> Button:
    for child in _debug._content_vbox.get_children():
        if child is Button and str(child.text) == button_text:
            return child
    return null


func _test_form(state: Dictionary) -> void:
    _debug._show_main_menu()
    check(not _debug._status_label.visible,
            "the empty hint of the main screen does not take a row above the items", state)
    check(_button_with(tr("[9] Sell a product to towns")) != null,
            "the main menu has the sale item", state)
    check(_button_with(tr("Craft a product")) != null,
            "the main menu has the craft item", state)

    var sell_btn := _button_with(tr("[9] Sell a product to towns"))
    if sell_btn != null:
        sell_btn.pressed.emit()
        check(_debug._pending_action == _debug.ACTION_SELL
                and _debug._view == _debug.VIEW_PRODUCT_LIST,
                "the sale item opens the shared product list", state)
    var craft_btn := _button_with(tr("Craft a product"))
    if craft_btn != null:
        craft_btn.pressed.emit()
        check(_debug._pending_action == _debug.ACTION_CRAFT,
                "the craft item opens the shared product list", state)

    var expected := {
        _debug.ACTION_ADD: tr("Add to storage"),
        _debug.ACTION_SELL: tr("Sell to towns"),
        _debug.ACTION_CRAFT: tr("Craft a product"),
    }
    for action in expected:
        _debug._show_product_list(action)
        check(_debug._status_label.visible
                and str(_debug._status_label.text) == tr("Select a product:"),
                "a sub-screen shows its hint", state)
        _debug._show_product_form("brandy")
        var rows: Array = _debug._content_vbox.get_children()
        var last = rows[rows.size() - 1] if not rows.is_empty() else null
        check(last is Button and str(last.text) == str(expected[action]),
                "the form of %s ends with its own button (got %s)"
                        % [action, str(last.text) if last is Button else "none"], state)
        _debug._redraw_current_view()
        check(_debug._pending_action == action,
                "a redraw keeps the %s item of the form" % action, state)


func _test_craft(state: Dictionary) -> void:
    _reset()
    var thresholds: Array = _mastery.thresholds()
    if thresholds.is_empty():
        return
    var amount := int(thresholds[0])
    _debug._pending_action = _debug.ACTION_CRAFT
    _debug._pending_product_id = "brandy"
    _debug._pending_amount = str(amount)
    _debug._pending_quality = "fine"
    _debug._on_product_action_pressed()

    check(int(_city.city_storage.get("brandy", 0)) == amount,
            "the manual craft puts the goods on the shelves", state)
    check(int(_city.city_quality_detail.get("brandy", {}).get("fine", 0)) == amount,
            "the manual craft keeps the chosen quality", state)
    check(_mastery.rank_of("brandy") == 1,
            "the manual craft teaches the city the mastery of the good", state)
    check(_fame.produced.size() == 1 and str(_fame.produced[0][0]) == "brandy",
            "the arrival of the goods still feeds the fame of the good", state)
    var reported := false
    for message in _hud.messages:
        if str(message[0]).contains(tr("Crafted")):
            reported = true
    check(reported, "the craft reports what it made", state)


func _test_sell(state: Dictionary) -> void:
    _reset()
    var treasury_before := int(_city.treasury)

    _debug._pending_action = _debug.ACTION_SELL
    _debug._pending_product_id = "brandy"
    _debug._pending_amount = "60"
    _debug._pending_quality = "fine"
    _debug._on_product_action_pressed()

    check(_fame.sales.size() == 1, "the sale is recorded once", state)
    if _fame.sales.size() == 1:
        var entry: Array = _fame.sales[0]
        check(str(entry[0]) == "brandy", "the sale names the good", state)
        check((entry[1] as Dictionary).get("fine", 0) == 60,
                "the sale counts the chosen quality", state)
    check(int(_city.city_storage.get("brandy", 0)) == 0,
            "a simulated sale does not take anything off the shelves", state)
    check(int(_city.treasury) == treasury_before,
            "a simulated sale does not pay the treasury", state)
    var reported := false
    for message in _hud.messages:
        if str(message[0]).contains(tr("Sold")):
            reported = true
    check(reported, "the sale reports what it simulated", state)

    # An empty warehouse is not a refusal: the tool exists to reach the next rung of the ladder.
    _debug._pending_amount = "1000"
    _debug._pending_quality = "perfect"
    _debug._on_product_action_pressed()
    check(_fame.sales.size() == 2, "a sale needs no stock", state)
    if _fame.sales.size() == 2:
        var entry: Array = _fame.sales[1]
        check((entry[1] as Dictionary).get("perfect", 0) == 1000,
                "the second sale keeps its own quality", state)


func _test_height(state: Dictionary, map) -> void:
    map.control_panel = null
    _debug._fit_panel()
    check(_debug._panel.size.y > _debug.MIN_WINDOW_HEIGHT,
            "without a control panel the window still has a usable height", state)

    var panel := Control.new()
    panel.position = Vector2(0, 600)
    panel.size = Vector2(1000, 150)
    get_root().add_child(panel)
    map.control_panel = panel
    _debug._fit_panel()
    check(is_equal_approx(_debug._panel.size.y, 600.0 - _debug.WINDOW_BOTTOM_GAP),
            "the window ends just above the control panel", state)
    check(is_equal_approx(_debug._panel.size.x, _debug.WINDOW_WIDTH),
            "the width of the window is unchanged", state)
    check(_debug._panel.position.y + _debug._panel.size.y <= panel.get_global_rect().position.y,
            "the window does not overlap the control panel", state)
    panel.free()
    map.control_panel = null
