# Headless test of the mastery of the production of a good:
#   godot --headless --path . --script res://tests/test_production_mastery.gd
#
# Checks:
#   1. The thresholds come from the balance data and each one gives exactly one rank.
#   2. The counter is cumulative and per good: brandy never teaches the masters rum.
#   3. A good made with an additional ingredient is counted to its base good.
#   4. Every rank lifts the quality of the good by one level, up to the top of the scale, and
#      leaves the other goods alone.
#   5. The rank appears in the Effects tab, in the name of the building and in its tooltip data.
#   6. A new rank is an important HUD message and reaches the journal through the HUD.
#   7. The counters and the ranks survive a save round-trip.
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")

class HudStub extends Node:
    var messages: Array = []

    func show_message(text: String, type: int) -> void:
        messages.append([text, type])

class MapStub extends Node:
    var hud: Node = null
    var craft_mastery_manager: Node = null

var _gdata = null
var _city = null
var _mgr = null
var _hud = null
# The manager references the autoloads, so it is loaded at runtime, after they have joined the
# tree. A preload would compile it before the autoload identifiers exist in --script mode.
var _mastery_script: GDScript = null
var _events: Array = []


func _initialize():
    WATCHDOG.arm(self)
    _run()


func _run() -> void:
    var state: Dictionary = {"failed": false}
    # The autoloads join the tree on the first frame, and the watchdog pins the source language
    # there as well, so the assertions can read the English names of the goods.
    await process_frame
    TranslationServer.set_locale("en")
    _gdata = get_root().get_node("GameData")
    _city = get_root().get_node("CityData")
    _gdata.load_all_data()
    _mastery_script = load("res://scripts/craft_mastery_manager.gd")

    var map := MapStub.new()
    map.name = "MainMap"
    _hud = HudStub.new()
    _hud.name = "HUD"
    map.hud = _hud
    map.add_child(_hud)
    _mgr = _mastery_script.new()
    _mgr.name = "CraftMasteryManager"
    map.craft_mastery_manager = _mgr
    map.add_child(_mgr)
    get_root().add_child(map)
    _mgr.rank_gained.connect(func(pid: String, rank: int):
            _events.append([pid, rank]))

    if WATCHDOG.wants_case("thresholds"):
        _test_thresholds(state)
    if WATCHDOG.wants_case("ranks"):
        _test_ranks(state)
    if WATCHDOG.wants_case("per_product"):
        _test_per_product(state)
    if WATCHDOG.wants_case("generated"):
        _test_generated(state)
    if WATCHDOG.wants_case("quality"):
        _test_quality(state)
    if WATCHDOG.wants_case("effects_and_buildings"):
        _test_effects_and_buildings(state)
    if WATCHDOG.wants_case("message"):
        _test_message(state)
    if WATCHDOG.wants_case("save"):
        _test_save(state)

    WATCHDOG.report_skipped()
    if state["failed"]:
        print("PRODUCTION MASTERY TEST FAILED")
        quit(1)
    else:
        print("PRODUCTION MASTERY TEST OK")
        quit(0)


func check(cond: bool, msg: String, state: Dictionary) -> void:
    if not cond:
        push_error("ASSERT: " + msg)
        print("ASSERT FAILED: ", msg)
        state["failed"] = true


func _reset() -> void:
    _mgr.produced.clear()
    _mgr.ranks.clear()
    _events.clear()
    _hud.messages.clear()


# The thresholds are data: the test derives the units from it rather than assuming the numbers of
# the file, so a balance edit does not break the mechanics it describes.
func _test_thresholds(state: Dictionary) -> void:
    _reset()
    var thresholds: Array = _mgr.thresholds()
    check(thresholds.size() >= 2, "the mastery has at least two ranks", state)
    if thresholds.size() < 2:
        return
    for i in range(1, thresholds.size()):
        check(int(thresholds[i]) > int(thresholds[i - 1]),
                "the thresholds ascend with the rank", state)
    check(_mgr.rank_for_units(int(thresholds[0]) - 1) == 0,
            "the first rank is not earned before its threshold", state)
    check(_mgr.rank_for_units(int(thresholds[0])) == 1,
            "the first rank is earned at its threshold", state)
    check(_mgr.rank_for_units(int(thresholds[1]) - 1) == 1,
            "the second rank is not earned early", state)
    check(_mgr.rank_for_units(int(thresholds[1])) == 2,
            "the second rank is earned at its threshold", state)
    _mgr.record_production("brandy", 0)
    check(_events.is_empty(), "a release of zero units gives no rank", state)


func _test_ranks(state: Dictionary) -> void:
    _reset()
    var thresholds: Array = _mgr.thresholds()
    if thresholds.size() < 2:
        return
    var first := int(thresholds[0])
    var second := int(thresholds[1])
    _mgr.record_production("brandy", first - 1)
    check(_mgr.rank_of("brandy") == 0, "the rank waits for the whole threshold", state)
    _mgr.record_production("brandy", 1)
    check(_mgr.rank_of("brandy") == 1, "the first thousand units give the first rank", state)
    check(_events.size() == 1 and str(_events[0][0]) == "brandy" \
            and int(_events[0][1]) == 1, "the first rank is reported once", state)
    _mgr.record_production("brandy", second - first - 1)
    check(_mgr.rank_of("brandy") == 1,
            "the second rank asks for its own units on top of the first", state)
    _mgr.record_production("brandy", 1)
    check(_mgr.rank_of("brandy") == 2, "the second threshold gives the second rank", state)
    check(_events.size() == 2 and int(_events[1][1]) == 2,
            "the second rank is reported once", state)
    check(_mgr.units_of("brandy") == second, "the counter is cumulative", state)


func _test_per_product(state: Dictionary) -> void:
    _reset()
    var thresholds: Array = _mgr.thresholds()
    if thresholds.is_empty():
        return
    _mgr.record_production("brandy", int(thresholds[0]))
    _mgr.record_production("rum", 1)
    check(_mgr.rank_of("brandy") == 1 and _mgr.rank_of("rum") == 0,
            "the mastery of brandy gives nothing to rum", state)
    check(_mgr.units_of("rum") == 1, "each good keeps its own counter", state)
    check(_city.apply_mastery_to_quality("rum", "common") == "common",
            "a good with no rank keeps its quality", state)


func _test_generated(state: Dictionary) -> void:
    _reset()
    var generated: String = _gdata.make_generated_id("gold_jewelry", "lazurite_ore")
    check(generated != "gold_jewelry", "the generated id of a good with an addition exists", state)
    check(_mgr.mastery_product_id(generated) == "gold_jewelry",
            "a good with an addition is counted to its base good", state)
    var thresholds: Array = _mgr.thresholds()
    if thresholds.is_empty():
        return
    _mgr.record_production(generated, int(thresholds[0]))
    check(_mgr.rank_of("gold_jewelry") == 1,
            "the units of a dyed good earn the rank of the base good", state)
    check(_events.size() == 1 and str(_events[0][0]) == "gold_jewelry",
            "the news names the base good", state)


func _test_quality(state: Dictionary) -> void:
    _reset()
    check(_gdata.raise_quality_key("common", 0) == "common",
            "no rank leaves the quality as it is", state)
    check(_gdata.raise_quality_key("common", 1) == "fine",
            "one rank raises the common good to fine", state)
    check(_gdata.raise_quality_key("fine", 2) == "perfect",
            "two ranks raise fine to perfect", state)
    check(_gdata.raise_quality_key("perfect", 2) == "perfect",
            "the top level of the scale is the cap", state)
    check(_gdata.raise_quality_key("fine|common", 1) == "exceptional|common",
            "a rank raises the base of a good with an addition, not the addition", state)
    check(_mgr.rank_stars(1) == "★" and _mgr.rank_stars(2) == "★★",
            "the ranks are written with the stars of the quality scale", state)

    var thresholds: Array = _mgr.thresholds()
    if thresholds.is_empty():
        return
    _mgr.record_production("brandy", int(thresholds[0]))
    check(_city.apply_mastery_to_quality("brandy", "common") == "fine",
            "the quality of the mastered good rises in the city", state)
    check(_city.apply_mastery_to_quality("brandy", "exceptional") == "perfect",
            "the rank raises a good already of exceptional quality", state)


func _test_effects_and_buildings(state: Dictionary) -> void:
    _reset()
    var thresholds: Array = _mgr.thresholds()
    if thresholds.size() < 2:
        return
    _mgr.record_production("brandy", int(thresholds[1]))

    var rows: Array = []
    for effect in _city.get_city_effects():
        if str(effect.get("group", "")) == "mastery":
            rows.append(effect)
    check(rows.size() == 1, "one mastered good gives one row on the Effects tab (%d)" % rows.size(),
            state)
    if rows.size() == 1:
        var row: Dictionary = rows[0]
        check(str(row.get("name", "")) == tr("%s production mastery")
                % _gdata.get_product_name("brandy"), "the row names the mastered good", state)
        check(str(row.get("value", "")) == "+★★", "the row carries the stars of the rank", state)
        check(str(row.get("source", "")) == tr("Rank %d") % 2,
                "the row names the rank", state)

    var products: Array = _city.get_building_mastery_products("distillery")
    check(products.has("brandy") and products.has("rum"),
            "the distillery makes brandy and rum", state)
    check(_city.get_building_mastery_stars("distillery") == "★★",
            "the name of the distillery carries the stars of its mastered good", state)
    check(_city.get_building_mastery_stars("bakery") == "",
            "a building of another craft carries no stars", state)
    var records: Array = _city.get_building_mastery_records("distillery")
    check(records.size() == 1 and str(records[0].get("product_id", "")) == "brandy",
            "the tooltip of the distillery lists its mastered good alone", state)


func _test_message(state: Dictionary) -> void:
    _reset()
    var thresholds: Array = _mgr.thresholds()
    if thresholds.is_empty():
        return
    _mgr.record_production("brandy", int(thresholds[0]))
    check(_hud.messages.size() == 1, "a new rank says one thing out loud", state)
    if _hud.messages.size() == 1:
        var message: Array = _hud.messages[0]
        check(int(message[1]) == _gdata.HUD_MESSAGE_IMPORTANT,
                "the news is important, so the HUD keeps it in the journal", state)
        check(str(message[0]).contains(_gdata.get_product_name("brandy")) \
                and str(message[0]).contains("★"),
                "the news names the good and the stars it gained", state)


func _test_save(state: Dictionary) -> void:
    _reset()
    var thresholds: Array = _mgr.thresholds()
    if thresholds.size() < 2:
        return
    _mgr.record_production("brandy", int(thresholds[0]) + 7)
    var snapshot: Dictionary = _mgr.serialize()
    _mgr.record_production("brandy", 10)
    check(int(snapshot.get("produced", {}).get("brandy", 0)) == int(thresholds[0]) + 7,
            "a snapshot does not alias the live counter", state)

    var restored = _mastery_script.new()
    restored.deserialize(snapshot)
    check(restored.rank_of("brandy") == 1, "the rank comes back from the save", state)
    check(restored.units_of("brandy") == int(thresholds[0]) + 7,
            "the counter comes back from the save", state)
    restored.free()
