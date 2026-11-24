# Headless test of the builder profession: a staffed Builder's Yard speeds up every build,
# an unstaffed one does not, and the supplies of the builder (binders and tools) raise that
# speed through the virtual yield "construction_work".
#   godot --headless --path . --script res://tests/test_builders.gd
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")

func _initialize():
    WATCHDOG.arm(self)
    _run()

func _run() -> void:
    var state := {"failed": false}
    var save_manager = get_root().get_node("SaveManager")
    save_manager.new_game()
    var city = get_root().get_node("CityData")
    var gdata = get_root().get_node("GameData")

    var main_map = load("res://scenes/MainMap.tscn").instantiate()
    get_root().add_child(main_map)
    await process_frame
    await process_frame
    var tm = main_map.get_node("TownsfolkManager")

    # A famine death would change the population under the checks.
    city.food_consumption_enabled = false
    city.food_per_citizen = 0
    city.city_food_pool.clear()
    city.total_population = 8
    city.idle_population = 8
    city.city_built_buildings = []
    city.city_storage.clear()
    city.city_quality_detail.clear()
    city.reset_counters()
    city.do_tick()
    check(absf(city.builder_construction_share) < 0.0001,
            "a city without a Builder's Yard must have no builder bonus", state)
    check(is_equal_approx(city.get_construction_speed_multiplier(), 1.0),
            "a city without builders must build at base speed", state)

    # --- The data of the branch ---
    check(gdata.professions.has("builder"), "the profession \"builder\" must exist", state)
    var yard: Dictionary = gdata.get_building_data("builders_yard")
    check(not yard.is_empty(), "the building \"builders_yard\" must exist", state)
    check(str(yard.get("profession", "")) == "builder",
            "the Builder's Yard must employ the builder", state)
    check(str(yard.get("unlock_tech", "")) == "masonry",
            "the Builder's Yard must be unlocked by masonry", state)
    check((yard.get("default_recipes", []) as Array).has("construction_work"),
            "the Builder's Yard must start with the construction work recipe", state)
    var recipe: Dictionary = gdata.get_craft("construction_work")
    check(not recipe.is_empty(), "the recipe \"construction_work\" must exist", state)
    check(int(recipe.get("display_result", {}).get("construction_work", 0)) == 4,
            "the construction work must give 4 units of the virtual yield", state)
    check(gdata.is_virtual_product("construction_work"),
            "construction work must be a virtual product", state)

    var binders: Array = gdata.product_groups.get("construction_binders", [])
    check(binders.size() == 4, "the binders group must hold four kinds", state)
    for pid in ["clay", "bitumen", "plaster", "mortar"]:
        check(binders.has(pid), "the binders group must hold \"%s\"" % pid, state)
    var cons: Array = gdata.get_profession_consumption("builder", "builders_yard")
    var binder_rule: Dictionary = {}
    var tool_rule: Dictionary = {}
    for entry in cons:
        if str(entry.get("display_key", "")) == "@construction_binders":
            binder_rule = entry
        elif str(entry.get("display_key", "")) == "@instruments":
            tool_rule = entry
    check(not binder_rule.is_empty(), "the builder must consume the binders group", state)
    check(not tool_rule.is_empty(), "the builder must consume work tools", state)
    if not binder_rule.is_empty():
        check(is_equal_approx(gdata.get_entry_member_bonus(binder_rule, "clay"), 0.05)
                and is_equal_approx(gdata.get_entry_member_bonus(binder_rule, "mortar"), 0.20),
                "lime mortar must beat clay in the tier ladder of binders", state)
    if not tool_rule.is_empty():
        var tiers: Array = gdata.get_entry_members_ordered_by_tier(tool_rule)
        check(not tiers.is_empty() and str(tiers[0]) == "damascus_tools",
                "the tool rule must prefer the strongest tools", state)

    # --- A yard adds its share only when staffed ---
    tm.assigned_buildings.clear()
    city.city_built_buildings = [
        {"id": "builders_yard", "slots": ["construction_work"], "quality_priority": "best"}
    ]
    city.city_storage.clear()
    city.city_quality_detail.clear()
    city.reset_counters()
    city.do_tick()
    check(absf(city.builder_construction_share) < 0.0001,
            "an unstaffed Builder's Yard must add no speed", state)
    check(tm.assign_townsfolk(0), "a townsfolk must be assignable to the Builder's Yard", state)
    city.do_tick()
    check(absf(city.builder_construction_share - 0.04) < 0.0001,
            "one staffed yard must add 4%%, got %f" % city.builder_construction_share, state)
    check(is_equal_approx(city.get_construction_speed_multiplier(), 1.04),
            "the builder bonus must reach the construction speed", state)

    # --- The supplies of the builder raise the share through the virtual yield ---
    city.city_storage.clear()
    city.city_quality_detail.clear()
    city.reset_counters()
    city.add_to_storage("mortar", 100)
    city.add_to_storage("copper_tools", 100)
    city.do_tick()
    check(absf(city.builder_construction_share - 0.048) < 0.0001,
            "mortar (+20%%) must be the best group bonus, got %f" % city.builder_construction_share, state)

    # A cheap clay gives a smaller bonus, and the empty binder shelf drops the share back.
    city.city_storage.clear()
    city.city_quality_detail.clear()
    city.reset_counters()
    city.add_to_storage("clay", 100)
    city.do_tick()
    check(absf(city.builder_construction_share - 0.042) < 0.0001,
            "clay (+5%%) must give less than mortar, got %f" % city.builder_construction_share, state)
    city.city_storage.clear()
    city.city_quality_detail.clear()
    city.reset_counters()
    city.do_tick()
    check(absf(city.builder_construction_share - 0.04) < 0.0001,
            "without supplies the yard must fall back to the base share", state)

    # Two yards add their shares; a removed worker takes his share away.
    city.city_built_buildings.append(
        {"id": "builders_yard", "slots": ["construction_work"], "quality_priority": "best"}
    )
    city.idle_population = maxi(city.idle_population, 4)
    check(tm.assign_townsfolk(1), "the second Builder's Yard must get a worker", state)
    city.do_tick()
    check(absf(city.builder_construction_share - 0.08) < 0.0001,
            "two staffed yards must add 8%%, got %f" % city.builder_construction_share, state)
    tm.remove_townsfolk(1)
    city.do_tick()
    check(absf(city.builder_construction_share - 0.04) < 0.0001,
            "after the worker leaves his share must drop", state)

    # --- The hoisting mechanisms raise the productivity of the yard ---
    var hoist_tech := "hoisting_mechanisms"
    if not city.unlocked_technologies.has(hoist_tech):
        city.unlocked_technologies.append(hoist_tech)
    check(is_equal_approx(city.get_building_production_multiplier("builders_yard", false), 1.1),
            "the hoist must give the Builder's Yard +10% production", state)
    city.do_tick()
    check(absf(city.builder_construction_share - 0.044) < 0.0001,
            "the hoist must raise the base share to 4.4%%, got %f" % city.builder_construction_share, state)

    city.city_storage.clear()
    city.city_quality_detail.clear()
    city.reset_counters()
    city.add_to_storage("mortar", 100)
    city.do_tick()
    check(absf(city.builder_construction_share - 0.0528) < 0.0001,
            "the hoist and the mortar must multiply, got %f" % city.builder_construction_share, state)

    tm.remove_townsfolk(0)
    tm.assigned_buildings.clear()
    city.city_built_buildings = []
    main_map.free()
    city.city_storage.clear()
    city.city_quality_detail.clear()
    if state["failed"]:
        print("BUILDERS TEST FAILED")
        quit(1)
    else:
        print("BUILDERS TEST OK")
        quit(0)

func check(condition: bool, message: String, state: Dictionary) -> void:
    if condition:
        print("OK: ", message)
    else:
        state["failed"] = true
        print("FAIL: ", message)
