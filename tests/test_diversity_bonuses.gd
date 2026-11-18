# Test of the diversity bonuses of data/bonuses.json: the tiers count the kinds
# of a product group available during the tick, not the leftovers in the storage
# and not the ration that happened to be eaten. The construction speed multiplier
# reads the reached tier of the stone bonus.
#   godot --headless --path . --script res://tests/test_diversity_bonuses.gd
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")

# do_tick() needs get_tree(), which is available only from the first frame on.
var _done := false

func _initialize():
    WATCHDOG.arm(self)

func _process(_delta) -> bool:
    if _done:
        return true
    _done = true
    _run()
    return true

func _run() -> void:
    var state: Dictionary = {"failed": false}
    var city = get_root().get_node("CityData")
    var gdata = get_root().get_node("GameData")
    var save_manager = get_root().get_node("SaveManager")
    save_manager.new_game()
    city.city_storage.clear()
    city.city_quality_detail.clear()
    city.reset_counters()

    check(gdata.diversity_bonuses.size() == 2,
        "both diversity bonuses must be loaded from data/bonuses.json", state)
    var members: Array = gdata.product_groups.get("building_stone", [])
    check(members.size() >= 5,
        "the building stone group must hold at least five kinds", state)
    if members.size() < 5:
        _finish(state)
        return

    # One ration is exactly enough: the bar is food_per_citizen, inclusive.
    city.add_to_storage(str(members[0]), int(city.food_per_citizen) - 1)
    var row: Dictionary = _row(city)
    check(int(row.get("varieties", -1)) == 0,
        "a ration minus one must not count as a variety", state)
    city.add_to_storage(str(members[0]), 1)
    row = _row(city)
    check(int(row.get("varieties", -1)) == 1 and float(row.get("value", -1.0)) == 0.0,
        "one ration of one kind must count, but give no bonus yet", state)
    check(is_equal_approx(city.get_construction_speed_multiplier(), 1.0),
        "the construction speed must stay x1.00 without a tier", state)

    # Two kinds: the first tier.
    city.add_to_storage(str(members[1]), 20)
    row = _row(city)
    check(int(row.get("varieties", -1)) == 2 and is_equal_approx(float(row.get("value", 0.0)), 0.05),
        "two kinds must give +5%", state)
    check(int(row.get("next_min", 0)) == 3,
        "the next tier after two kinds must be three", state)
    check(is_equal_approx(city.get_construction_speed_multiplier(), 1.05),
        "the construction speed must be x1.05 at the first tier", state)

    # Three kinds: the second tier.
    city.add_to_storage(str(members[2]), 20)
    row = _row(city)
    check(is_equal_approx(float(row.get("value", 0.0)), 0.10),
        "three kinds must give +10%", state)

    # Five kinds: the last tier.
    city.add_to_storage(str(members[3]), 20)
    city.add_to_storage(str(members[4]), 20)
    row = _row(city)
    check(is_equal_approx(float(row.get("value", 0.0)), 0.20),
        "five kinds must give +20%", state)
    check(is_equal_approx(city.get_construction_speed_multiplier(), 1.20),
        "the construction speed must be x1.20 at the last tier", state)

    # A good produced and immediately consumed in the same tick still counts.
    city.city_storage.clear()
    city.city_quality_detail.clear()
    city.reset_counters()
    for pid in members:
        city.add_to_storage(str(pid), 20)
    for pid in members:
        city.remove_from_storage(str(pid), 20)
    var empty := true
    for pid in members:
        if city.get_storage_amount(str(pid)) > 0:
            empty = false
    check(empty, "the storage must be empty after the write-off", state)
    check(is_equal_approx(city.get_construction_speed_multiplier(), 1.20),
        "the kinds present during the tick must count even after the write-off", state)

    # A new tick with an empty storage drops the bonus.
    city.reset_counters()
    check(is_equal_approx(city.get_construction_speed_multiplier(), 1.0),
        "an empty storage at the start of a tick must drop the bonus", state)

    # --- The meat bonus counts the opportunity to eat a variety, not the ration ---
    var meat: Array = gdata.product_groups.get("meat", [])
    check(meat.size() >= 3, "the meat group must hold at least three kinds", state)
    check(_row(city, "meat").get("bonus_type", "") == "food_variety",
        "the meat bonus must be declared as food_variety", state)

    # do_tick() resolves MainMap/TownsfolkManager for the population change.
    var main_map := Node.new()
    main_map.name = "MainMap"
    get_root().add_child(main_map)
    var townsfolk = load("res://scripts/townsfolk_manager.gd").new()
    townsfolk.name = "TownsfolkManager"
    main_map.add_child(townsfolk)

    city.city_storage.clear()
    city.city_quality_detail.clear()
    city.city_food_pool.clear()
    city.total_population = 11
    var kinds: Array = [str(meat[0]), str(meat[1]), str(meat[2])]
    var ration: int = max(0, city.total_population - 1) * int(city.food_per_citizen)
    for pid in kinds:
        city.city_food_pool[pid] = true
        city.add_to_storage(pid, ration)
    city.reset_counters()
    var meat_row: Dictionary = _row(city, "meat")
    check(int(meat_row.get("varieties", -1)) == 3 and is_equal_approx(float(meat_row.get("value", 0.0)), 0.10),
        "three kinds of meat in stock must give +10%", state)

    # Eating the ration must not turn the bonus off: availability during the tick
    # is what counts, not whether a particular kind was on the plate.
    city.do_tick()
    meat_row = _row(city, "meat")
    check(int(meat_row.get("varieties", -1)) == 3 and is_equal_approx(float(meat_row.get("value", 0.0)), 0.10),
        "the tier must stay after the ration is eaten", state)
    for pid in kinds:
        check(int(city.get_storage_amount(pid)) < ration,
            "the basket must feed on every kind of meat: %s" % pid, state)
    check(is_equal_approx(city.get_construction_speed_multiplier(), 1.0),
        "a display-only bonus must not change the construction speed", state)

    # A hoard nobody touches is not a variety: once the flow window passes,
    # the bonus drops even though the meat is still on the shelves.
    for i in range(city.DIVERSITY_FLOW_WINDOW_TICKS + 1):
        city.reset_counters()
    meat_row = _row(city, "meat")
    check(int(meat_row.get("varieties", -1)) == 0,
        "a static hoard must not give a bonus after the flow window", state)
    city.add_to_storage(str(kinds[0]), 1)
    meat_row = _row(city, "meat")
    check(int(meat_row.get("varieties", -1)) == 1,
        "one kind back in circulation must count again", state)
    for pid in kinds:
        city.add_to_storage(str(pid), 1)
    meat_row = _row(city, "meat")
    check(int(meat_row.get("varieties", -1)) == 3,
        "all three kinds in circulation must restore +10%", state)

    main_map.free()
    city.city_storage.clear()
    city.city_quality_detail.clear()
    city.city_food_pool.clear()
    _finish(state)

func _row(city, group_id: String = "building_stone") -> Dictionary:
    for entry in city.get_diversity_bonuses():
        if str(entry.get("group_id", "")) == group_id:
            return entry
    return {}

func _finish(state: Dictionary) -> void:
    if state["failed"]:
        print("DIVERSITY BONUSES TEST FAILED")
        quit(1)
    else:
        print("DIVERSITY BONUSES TEST OK")
        quit(0)

func check(condition: bool, message: String, state: Dictionary) -> void:
    if condition:
        print("OK: ", message)
    else:
        state["failed"] = true
        push_error("FAIL: " + message)
