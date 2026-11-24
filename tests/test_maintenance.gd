# Headless test of the upkeep of the built buildings and improvements:
#   godot --headless --path . --script res://tests/test_maintenance.gd
#
# Checks:
#   1. Every vanilla building and improvement declares a non-negative fixed maintenance_cost.
#   2. The cost does not depend on the recipe or the resource: a plantation pays 54/sec
#      whether it grows apples or saffron, and a farm pays the founding 0.2/sec.
#   3. A new game has no upkeep: the decorative improvements of the towns are not the
#      player's property and are not charged for.
#   4. The cost is per built entity: two farms cost twice as much.
#   5. The charge is made in whole coins with a per-source fractional remainder.
#   6. An unpaid charge is not a debt: the treasury does not go negative, the warning
#      is emitted, and the following ticks do not collect the missed coins.
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")

func _initialize():
    WATCHDOG.arm(self)
    _run()

func _run() -> void:
    var state = {"failed": false, "missed": -1, "warnings": 0}
    var save_manager = get_root().get_node("SaveManager")
    var city = get_root().get_node("CityData")
    var gdata = get_root().get_node("GameData")

    save_manager.new_game()
    var main_map = load("res://scenes/MainMap.tscn").instantiate()
    get_root().add_child(main_map)
    await process_frame
    await process_frame

    # --- 1. The fixed costs in the data ---
    for b in gdata.buildings:
        var id = str(b.get("id", ""))
        check(b.has("maintenance_cost") and float(b.get("maintenance_cost", -1)) >= 0.0,
                "building %s must have a non-negative maintenance_cost" % id, state)
    for imp_id in gdata.improvements:
        var imp = gdata.improvements[imp_id]
        check(imp.has("maintenance_cost") and float(imp.get("maintenance_cost", -1)) >= 0.0,
                "improvement %s must have a non-negative maintenance_cost" % imp_id, state)
    check(gdata.get_building_maintenance_cost("hand_mill") == 3.6,
            "the hand mill must cost 3.6 coins/sec", state)
    check(gdata.get_building_maintenance_cost("bakery") == 21.6,
            "the bakery must cost 21.6 coins/sec", state)
    check(gdata.get_improvement_maintenance_cost("farm") == 0.2,
            "the founding farm must cost 0.2 coins/sec", state)
    check(gdata.get_improvement_maintenance_cost("plantation") == 54.0,
            "a plantation must cost 54 coins/sec", state)
    check(gdata.get_improvement_maintenance_cost("vineyard") == 54.0,
            "a vineyard must cost 54 coins/sec", state)
    check(gdata.get_improvement_maintenance_cost("mine") == 36.0,
            "a mine must cost 36 coins/sec", state)
    check(gdata.get_improvement_maintenance_cost("unknown") == 0.0,
            "an unknown entity must be free", state)

    # --- 2. The start of the game: no player-built improvements ---
    check(main_map.get_built_improvement_ids().is_empty(),
            "a new game must have no player-built improvements", state)
    check(city.get_maintenance_per_sec() == 0.0,
            "a new game must have no upkeep", state)

    # --- 3. The cost is per entity, not per recipe or resource ---
    var row: int = mini(2, main_map.map_rows - 1)
    main_map.tile_data[row][2]["improvement"] = "farm"
    main_map.tile_data[row][2]["decorative"] = false
    main_map.tile_data[row][3]["improvement"] = "plantation"
    main_map.tile_data[row][3]["decorative"] = false
    main_map.invalidate_improvement_index()
    check(main_map.get_built_improvement_ids().size() == 2,
            "both improvements must be counted", state)
    check(is_equal_approx(city.get_maintenance_per_sec(), 54.2),
            "the farm and the plantation must cost 54.2/sec (got %f)"
                    % city.get_maintenance_per_sec(), state)
    # Changing the crop on the plantation does not change the cost.
    main_map.tile_data[row][3]["improvement"] = "plantation"
    main_map.tile_data[row][4]["improvement"] = "plantation"
    main_map.tile_data[row][4]["decorative"] = false
    main_map.invalidate_improvement_index()
    check(is_equal_approx(float(city.get_maintenance_sources().get("@imp:plantation", 0.0)), 108.0),
            "two plantations must cost 108/sec regardless of their crop (got %f)"
                    % float(city.get_maintenance_sources().get("@imp:plantation", 0.0)), state)

    # --- 4. The whole-coin charge and its sources ---
    city.treasury = 1000
    city.maintenance_source_accum.clear()
    city.treasury_expense_accum.clear()
    city.tick_maintenance()
    check(city.treasury == 892,
            "the first charge must be 108 whole coins (got %d)" % city.treasury, state)
    check(city.treasury_expense_accum.has("@imp:plantation"),
            "the plantations must appear in the breakdown", state)
    # The farm at 0.2/sec needs five ticks to pay its first whole coin.
    for i in range(4):
        city.tick_maintenance()
    check(city.treasury_expense_accum.has("@imp:farm"),
            "the farm must appear in the breakdown after five ticks", state)

    # --- 5. An unpaid charge: no debt, a warning, no negative treasury ---
    city.treasury = 1
    city.maintenance_source_accum.clear()
    city.treasury_expense_accum.clear()
    city.maintenance_warning_cooldown = 0.0
    city.maintenance_shortfall.connect(func(missed):
        state["missed"] = missed
        state["warnings"] += 1
    )
    city.tick_maintenance()
    check(city.treasury == 0, "the treasury must pay what it can and stop at zero", state)
    check(state["warnings"] == 1, "one warning must be emitted", state)
    var fractional_only := func() -> bool:
        for src in city.maintenance_source_accum:
            var rem := float(city.maintenance_source_accum[src])
            if rem < 0.0 or rem >= 1.0:
                return false
        return true
    check(fractional_only.call(),
            "only the fractional part may remain after an unpaid charge", state)
    city.tick_maintenance()
    check(city.treasury == 0, "the treasury may not go negative", state)
    check(state["warnings"] == 1, "the warning must be throttled", state)
    check(fractional_only.call(), "the missed whole coins must not be carried over", state)

    if state["failed"]:
        print("MAINTENANCE TEST FAILED")
        quit(1)
    else:
        print("MAINTENANCE TEST OK")
        quit(0)

func check(cond: bool, msg: String, state: Dictionary):
    if not cond:
        push_error("ASSERT: " + msg)
        print("ASSERT FAILED: ", msg)
        state["failed"] = true
