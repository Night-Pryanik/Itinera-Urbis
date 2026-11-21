# Headless test of the Astronomy branch:
#   godot --headless --path . --script res://tests/test_astronomy.gd
#
# Checks:
#   1. The data: Astronomy, its prerequisites and its modifier; Foreign Trade and
#      its OR prerequisites, which must not force Emporia on a coastal map.
#   2. The multiplier is 1.0 before the research and 1.15 after it.
#   3. The science rate of a staffed library grows by 15%, while the base income
#      of science stays untouched: the bonus belongs to the scholars.
#   4. The breakdown keeps the technology bonus separate from the consumption
#      bonus, so the tooltip does not name the writing set as its source.
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")

func _initialize():
    WATCHDOG.arm(self)
    _run()

func _run() -> void:
    var state = {"failed": false}
    get_root().get_node("SaveManager").new_game()
    var city = get_root().get_node("CityData")
    var gdata = get_root().get_node("GameData")

    var astronomy: Dictionary = {}
    var foreign_trade: Dictionary = {}
    for t in gdata.technologies:
        var tid := str(t.get("id", ""))
        if tid == "astronomy":
            astronomy = t
        elif tid == "long_distance_trade":
            foreign_trade = t
    check(not astronomy.is_empty(), "the technology \"astronomy\" must exist", state)
    check(not foreign_trade.is_empty(), "the technology \"long_distance_trade\" must exist", state)
    check(str(astronomy.get("era", "")) == "antiquity",
            "Astronomy must belong to the Antiquity era", state)
    var prereqs: Array = astronomy.get("prerequisites", [])
    check(prereqs.size() == 1 and prereqs[0] == ["mathematics", "precision_instruments"],
            "Astronomy must require mathematics and precision instruments", state)
    var trade_prereqs: Array = foreign_trade.get("prerequisites", [])
    check(trade_prereqs.size() == 2 \
            and trade_prereqs[0] == ["astronomy", "coinage"] \
            and trade_prereqs[1] == ["navigation", "coinage"],
            "Foreign Trade must offer the land and the sea route without Emporia", state)

    var modifier_value := 0.0
    for mod in gdata.modifiers.get("tech_modifiers", []):
        if str(mod.get("tech_id", "")) != "astronomy":
            continue
        for entry in mod.get("modifiers", []):
            if str(entry.get("target", "")) == "scholar_production":
                modifier_value = float(entry.get("value", 0))
    check(is_equal_approx(modifier_value, 15.0),
            "Astronomy must add 15%% to scholar production, got %f" % modifier_value, state)

    check(is_equal_approx(city.get_scholar_production_mult(), 1.0),
            "before the research the scholar multiplier must be 1.0", state)
    city.unlocked_technologies.append("astronomy")
    check(is_equal_approx(city.get_scholar_production_mult(), 1.15),
            "after the research the scholar multiplier must be 1.15", state)

    var main_map = load("res://scenes/MainMap.tscn").instantiate()
    get_root().add_child(main_map)
    await process_frame
    await process_frame
    var tm = main_map.get_node("TownsfolkManager")
    city.food_consumption_enabled = false
    city.total_population = 20
    city.idle_population = 4
    city.city_storage["writing_set"] = 1000
    city.city_built_buildings = [
        {"id": "library", "slots": ["science"], "quality_priority": "best"}
    ]
    tm.assigned_buildings.clear()
    check(tm.assign_townsfolk(0), "a townsfolk must be assignable to the library", state)

    city.unlocked_technologies.erase("astronomy")
    city.do_tick()
    var plain_rate: float = city.science_buildings_rate_per_sec
    check(plain_rate > 0.0, "a staffed library must produce science", state)
    var plain_total: float = city.get_science_rate_per_sec()

    city.unlocked_technologies.append("astronomy")
    city.do_tick()
    var boosted_rate: float = city.science_buildings_rate_per_sec
    check(is_equal_approx(boosted_rate, plain_rate * 1.15),
            "Astronomy must raise the scholars' output by 15%% (%.3f -> %.3f)" \
                    % [plain_rate, boosted_rate], state)
    # The base income of science (1.0/sec) must NOT be multiplied: only the
    # rate of the working buildings changes.
    check(is_equal_approx(city.get_science_rate_per_sec() - plain_total,
            (boosted_rate - plain_rate)),
            "the base science must stay untouched by Astronomy", state)

    var breakdown: Dictionary = city.get_science_breakdown()
    var buildings: Array = breakdown.get("buildings", [])
    check(buildings.size() == 1, "the breakdown must hold the one library", state)
    if not buildings.is_empty():
        var entry: Dictionary = buildings[0]
        check(is_equal_approx(float(entry.get("bonus", 1.0)), 1.25),
                "the consumption bonus must stay separate (got %f)" \
                        % float(entry.get("bonus", 1.0)), state)
        check(is_equal_approx(float(entry.get("tech_bonus", 1.0)), 1.15),
                "the technology bonus must be reported separately (got %f)" \
                        % float(entry.get("tech_bonus", 1.0)), state)

    main_map.free()
    if state["failed"]:
        print("ASTRONOMY TEST FAILED")
        quit(1)
    else:
        print("ASTRONOMY TEST OK")
        quit(0)

func check(cond: bool, msg: String, state: Dictionary):
    if not cond:
        push_error("ASSERT: " + msg)
        print("ASSERT FAILED: ", msg)
        state["failed"] = true
