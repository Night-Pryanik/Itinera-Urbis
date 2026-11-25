# Headless test of the builder profession: a staffed Builder's Yard speeds up every build,
# an unstaffed one does not, and the supplies of the builder (binders and tools) raise that
# speed through the passive building yield "construction_work".
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
    check((yard.get("default_recipes", []) as Array).is_empty(),
            "the yard starts without a selected mixture recipe", state)
    check(gdata.get_craft("construction_work").is_empty(),
            "construction work must not be a selectable recipe", state)
    check(int(yard.get("additional_yield", {}).get("construction_work", 0)) == 4,
            "the yard must passively give 4 units of construction work", state)
    check(gdata.is_virtual_product("construction_work"),
            "construction work must be a virtual product", state)

    var binders: Array = gdata.product_groups.get("construction_binders", [])
    check(binders.size() == 5, "the mixes and binders group must hold five kinds", state)
    for pid in ["clay", "bitumen", "plaster", "mortar", "roman_concrete"]:
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
        check(is_equal_approx(gdata.get_entry_member_bonus(binder_rule, "roman_concrete"), 0.25),
                "Roman concrete must give the builder +25% production", state)
        var mixes: Array = gdata.get_entry_members_ordered_by_tier(binder_rule)
        check(not mixes.is_empty() and str(mixes[0]) == "roman_concrete",
                "the builder must prefer Roman concrete over other mixes and binders", state)
    if not tool_rule.is_empty():
        var tiers: Array = gdata.get_entry_members_ordered_by_tier(tool_rule)
        check(not tiers.is_empty() and str(tiers[0]) == "damascus_tools",
                "the tool rule must prefer the strongest tools", state)

    # --- A yard adds its share only when staffed ---
    tm.assigned_buildings.clear()
    city.city_built_buildings = [
        {"id": "builders_yard", "slots": ["empty"], "quality_priority": "best"}
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

    check(not city.is_building_idle(0), "a staffed yard with an empty slot is not idle", state)
    var panel = load("res://scripts/building_panel.gd").new()
    check(panel._count_working_buildings(tm, [0]) == 1,
            "the building panel must count a yard with an empty slot as active", state)
    panel.free()
    var tab = load("res://scripts/buildings_tab.gd").new()
    main_map.add_child(tab)
    tab.built_buildings = city.city_built_buildings
    var groups: Array = tab._group_buildings()
    check(groups.size() == 1 and int(groups[0].get("idle", -1)) == 0,
            "the building list must not label a yard with an empty slot as idle", state)
    tab.free()
    check(int(city.get_townsfolk_professions_count().get("builder", 0)) == 1,
            "an empty preparation slot must not remove the builder from professional demand", state)
    check(int(city.get_working_buildings_count().get("builders_yard", 0)) == 1,
            "an empty preparation slot must still count as a working yard", state)
    city.city_built_buildings[0]["slots"] = []
    city.do_tick()
    check(absf(city.builder_construction_share - 0.04) < 0.0001,
            "a yard without recipe slots must retain its passive work", state)
    city.city_built_buildings[0]["slots"] = ["empty", "empty"]
    city.do_tick()
    check(absf(city.builder_construction_share - 0.04) < 0.0001,
            "extra empty slots must not multiply construction work", state)
    city.city_built_buildings[0]["slots"] = ["empty"]

    # --- The supplies of the builder raise the share through the virtual yield ---
    city.city_storage.clear()
    city.city_quality_detail.clear()
    city.reset_counters()
    city.add_to_storage("mortar", 100)
    city.add_to_storage("copper_tools", 100)
    city.do_tick()
    check(absf(city.builder_construction_share - 0.048) < 0.0001,
            "mortar (+20%%) must be the best group bonus, got %f" % city.builder_construction_share, state)

    city.city_storage.clear()
    city.city_quality_detail.clear()
    city.reset_counters()
    city.add_to_storage("roman_concrete", 100)
    city.add_to_storage("mortar", 100)
    city.add_to_storage("clay", 100)
    city.do_tick()
    check(absf(city.builder_construction_share - 0.05) < 0.0001,
            "concrete (+25%%) must raise the yard share to 5%% without stacking binders, got %f"
            % city.builder_construction_share, state)
    check(city.get_storage_amount("roman_concrete") < 100,
            "the builder must consume concrete when it is available", state)
    check(city.get_storage_amount("mortar") == 100 and city.get_storage_amount("clay") == 100,
            "concrete must spare the weaker binders", state)
    city.city_storage.erase("roman_concrete")
    city.city_quality_detail.erase("roman_concrete")
    city.do_tick()
    check(absf(city.builder_construction_share - 0.048) < 0.0001,
            "when concrete runs out the builder must fall back to mortar, got %f"
            % city.builder_construction_share, state)

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
        {"id": "builders_yard", "slots": ["empty"], "quality_priority": "best"}
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

    _test_preparation(city, gdata, tm, main_map.get_node("WorkerManager"), state)

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

func _test_preparation(city, gdata, tm, wm, state: Dictionary) -> void:
    for tech in ["limestone_burning", "concrete"]:
        if not city.unlocked_technologies.has(tech):
            city.unlocked_technologies.append(tech)
    for recipe_id in ["mortar", "roman_concrete"]:
        var recipe: Dictionary = gdata.get_craft(recipe_id)
        check(recipe.get("produced_in", []) == ["builders_yard"],
                "only the builders prepare " + recipe_id, state)
        city.city_built_buildings[0]["slots"] = [recipe_id]
        city.city_storage.clear()
        city.city_quality_detail.clear()
        city.reset_counters()
        wm.building_consumption_timers.clear()
        city.do_tick()
        check(absf(city.builder_construction_share - 0.04) < 0.0001,
                "missing mixture ingredients must not stop construction work", state)
        check(city.get_storage_amount(recipe_id) == 0,
                "the yard cannot prepare a mixture without its ingredients", state)

        city.add_to_storage("roman_concrete", 100)
        var plan: Dictionary = city.get_building_planned_production()
        var source: String = gdata.building_source_id("builders_yard")
        check(int(plan.get(recipe_id, {}).get(source, {}).get("amount", 0)) == 10,
                "concrete supplies must not inflate the planned mixture output", state)
        check(is_equal_approx(wm.get_building_recipe_production_bonus(0), 1.0),
                "concrete must not boost its own manufacture", state)
        check(is_equal_approx(wm.get_building_production_bonus(0), 1.25),
                "concrete must still boost the crew's construction work", state)
        city.add_to_storage("lime", 10)
        if recipe_id == "mortar":
            city.add_to_storage("quartz_sand", 10)
        else:
            city.add_to_storage("tuff", 10)
            city.add_to_storage("basalt", 10)
        var ticks := ceili(float(recipe.get("time", 0)) / float(city.SIMULATION_TICK))
        var produced := 0
        for _tick in range(ticks):
            city.reset_counters()
            city.do_tick()
            produced += int(city.production_rates.get(recipe_id, 0))
            check(absf(city.builder_construction_share - 0.05) < 0.0001,
                    "supplied construction work must continue while a mixture is prepared", state)
        check(produced == 10, "a supplied yard must produce exactly ten units of " + recipe_id, state)

        var stock_before: int = city.get_storage_amount("roman_concrete")
        tm.remove_townsfolk(0)
        city.reset_counters()
        city.do_tick()
        check(is_zero_approx(city.builder_construction_share),
                "pausing the yard must stop construction work", state)
        check(city.get_storage_amount("roman_concrete") == stock_before,
                "pausing the yard must stop professional consumption", state)
        check(int(city.get_townsfolk_professions_count().get("builder", 0)) == 0,
                "a paused yard must leave the professional demand plan", state)
        check(tm.assign_townsfolk(0), "the yard can resume", state)

    city.city_built_buildings[0]["slots"] = ["mortar", "roman_concrete"]
    city.city_storage.clear()
    city.city_quality_detail.clear()
    wm.building_consumption_timers.clear()
    city.add_to_storage("roman_concrete", 100)
    city.do_tick()
    check(absf(city.builder_construction_share - 0.05) < 0.0001,
            "multiple preparation slots must not multiply the passive work", state)
    check(city.get_storage_amount("roman_concrete") == 99,
            "professional supplies must be consumed once per yard, not per slot", state)
    city.city_built_buildings[0]["slots"] = ["empty"]
    city.city_storage.clear()
    city.city_quality_detail.clear()

func check(condition: bool, message: String, state: Dictionary) -> void:
    if condition:
        print("OK: ", message)
    else:
        state["failed"] = true
        print("FAIL: ", message)
