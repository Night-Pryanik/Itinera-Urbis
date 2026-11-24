# Test of the priority of a dedicated professional rule over the pseudo-profession
# "all": a resource declared for both must be written off once. The professionals
# take their own rule and its production bonus; the remaining residents keep the
# "all" rule. Coca leaf for the heavy labour professions (+10%) is the live case.
#   godot --headless --path . --script res://tests/test_consumption_priority.gd
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")

# get_profession() reads the improvement of the hex from the parent of the manager.
class MapStub extends Node:
    var tile_data: Array = []

func _initialize():
    WATCHDOG.arm(self)
    _run()

func _run() -> void:
    var state: Dictionary = {"failed": false}
    var city = get_root().get_node("CityData")
    var gdata = get_root().get_node("GameData")
    var save_manager = get_root().get_node("SaveManager")
    save_manager.new_game()
    city.total_population = 5
    city.market_consumption_enabled.clear()
    city.consumption_priority.clear()

    # --- The data: coca is declared for both "all" and the heavy professions ---
    var coca_all = null
    for e in gdata.get_profession_consumption("all"):
        if str(e.get("display_key", "")) == "coca_leaf":
            coca_all = e
            break
    check(coca_all != null, "the coca rule of the pseudo-profession all must be declared", state)

    var coca_miner = null
    for e in gdata.get_profession_consumption("miner"):
        if str(e.get("display_key", "")) == "coca_leaf":
            coca_miner = e
            break
    check(coca_miner != null, "the coca rule of the miner must be declared", state)
    if coca_miner != null:
        check(is_equal_approx(float(coca_miner.get("production_bonus", 0.0)), 0.1),
            "the miner's coca rule must grant +10% production", state)
    var consumers: Array = gdata.get_resource_consumer_professions("coca_leaf")
    check(consumers.has("miner"),
        "the miner must be listed as a consumer of coca by a dedicated rule", state)
    check(not consumers.has("all"),
        "the pseudo-profession all must not be returned as a dedicated consumer", state)

    # --- One miner among five citizens ---
    var stub := MapStub.new()
    get_root().add_child(stub)
    stub.tile_data = [[{"improvement": "mine"}]]
    var wm = load("res://scripts/worker_manager.gd").new()
    stub.add_child(wm)
    wm.assigned_hexes["0,0"] = true
    check(int(wm.count_workers_by_profession().get("miner", 0)) == 1,
        "the stub must have one miner", state)

    var all_src: String = gdata.profession_source_id("all")
    var miner_src: String = gdata.profession_source_id("miner")
    var amount_all: int = int(coca_all.get("amount", 0)) if coca_all != null else 0
    var amount_miner: int = int(coca_miner.get("amount", 0)) if coca_miner != null else 0

    # --- The plan: four residents and one miner, never five plus one ---
    var planned: Dictionary = wm.get_planned_consumption_map(false)
    var by_source: Dictionary = planned.get("coca_leaf", {})
    var all_entry: Dictionary = by_source.get(all_src, {})
    var miner_entry: Dictionary = by_source.get(miner_src, {})
    check(int(all_entry.get("count", -1)) == 4,
        "the all headcount must lose the miner: expected 4, got %d"
            % int(all_entry.get("count", -1)), state)
    check(int(all_entry.get("amount", -1)) == amount_all * 4,
        "the planned all expense must use the reduced headcount", state)
    check(int(miner_entry.get("count", -1)) == 1,
        "the miner must keep his own planned expense", state)
    check(int(miner_entry.get("amount", -1)) == amount_miner,
        "the miner's planned expense must come from his rule", state)

    # The Trade card must show the same split and the whole number of buyers.
    var pop_map: Dictionary = wm.get_population_consumption_map()
    var card: Dictionary = pop_map.get("coca_leaf", {})
    var sources: Dictionary = card.get("sources", {})
    check(int(card.get("consumers_total", -1)) == 5,
        "the card must count five buyers in total: expected 5, got %d"
            % int(card.get("consumers_total", -1)), state)
    check(int(sources.get(all_src, {}).get("count", -1)) == 4,
        "the card's all source must have four residents", state)
    check(int(sources.get(miner_src, {}).get("count", -1)) == 1,
        "the card's miner source must have one worker", state)

    # A resource without a dedicated rule keeps the whole population.
    check(int(planned.get("grapes", {}).get(all_src, {}).get("count", -1)) == 5,
        "a resource consumed only by all must keep the full population", state)

    # --- The fact: one tick writes off four residents' worth, not five ---
    city.city_storage.clear()
    city.city_quality_detail.clear()
    city.city_storage["coca_leaf"] = 100
    city.city_quality_detail["coca_leaf"] = {"common": 100}
    var before: int = city.get_storage_amount("coca_leaf")
    wm.tick_city_consumption(1.0)
    var after: int = city.get_storage_amount("coca_leaf")
    check(before - after == amount_all * 4,
        "the city must write off coca for four residents only: expected %d, got %d"
            % [amount_all * 4, before - after], state)

    # --- The bonus of the professional rule is granted on top ---
    var multiplier: float = wm.tick_consumption(0, 0, 1.0)
    check(multiplier >= 1.1 - 0.001,
        "the miner must get the coca production bonus of +10%%, got x%.3f" % multiplier, state)

    wm.free()
    stub.free()
    city.total_population = 1
    city.city_storage.clear()
    city.city_quality_detail.clear()
    city.market_consumption_enabled.clear()
    city.consumption_priority.clear()

    if state["failed"]:
        print("CONSUMPTION PRIORITY TEST FAILED")
        quit(1)
    else:
        print("CONSUMPTION PRIORITY TEST OK")
        quit(0)

func check(condition: bool, message: String, state: Dictionary) -> void:
    if condition:
        print("OK: ", message)
    else:
        state["failed"] = true
        push_error("FAIL: " + message)
