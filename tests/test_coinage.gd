# Headless test of the coinage branch:
#   godot --headless --path . --script res://tests/test_coinage.gd
#
# The technology unlocks the Mint; the bonus belongs to the STAFFED building, not to the
# technology. One virtual unit of "coinage" from the building's additional_yield is +1% of
# the poll tax. Checks:
#
#   1. The data: the tech, the pseudo product without a price, the pseudo recipe, the building.
#   2. A staffed Mint raises the tax by 5% (CityData.mint_tax_share), and the treasury row
#      shows the share; an unstaffed one does nothing.
#   3. Several staffed Mints add their shares; removing a worker removes his share.
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")

func _initialize():
    WATCHDOG.arm(self)
    _run()

func _run() -> void:
    var state = {"failed": false}

    var save_manager = get_root().get_node("SaveManager")
    save_manager.new_game()
    var city = get_root().get_node("CityData")
    var gdata = get_root().get_node("GameData")

    var main_map = load("res://scenes/MainMap.tscn").instantiate()
    get_root().add_child(main_map)
    await process_frame
    await process_frame
    var tm = main_map.get_node("TownsfolkManager")
    var wm = main_map.get_node("WorkerManager")
    # A famine death would unassign the worker and change the population under the check.
    city.food_consumption_enabled = false

    # --- 1. The data of the branch ---
    var tech: Dictionary = {}
    for t in gdata.technologies:
        if str(t.get("id", "")) == "coinage":
            tech = t
            break
    check(not tech.is_empty(), "the technology \"coinage\" must exist", state)
    check(str(tech.get("era", "")) == "antiquity", "coinage must belong to the Antiquity era", state)
    var prereqs: Array = tech.get("prerequisites", [])
    check(prereqs.size() == 1 and prereqs[0] == ["currency", "metallurgy"],
            "coinage must require currency and metallurgy", state)
    var mint_data: Dictionary = gdata.get_building_data("mint")
    check(not mint_data.is_empty(), "the building \"mint\" must exist", state)
    check(str(mint_data.get("unlock_tech", "")) == "coinage",
            "the Mint must be unlocked by coinage", state)
    check(int(gdata.get_building_additional_yield("mint").get("coinage", 0)) == 5,
            "the Mint must give 5 virtual units of coinage", state)
    var recipes: Array = mint_data.get("default_recipes", [])
    check(recipes.has("coin_collection"), "the Mint must start with the coin collection recipe", state)
    check(gdata.get_price("coinage") <= 0.0,
            "coinage must be a virtual yield, not a priced good", state)

    # --- 2. One staffed Mint ---
    city.total_population = 20
    city.idle_population = 4
    tm.assigned_buildings.clear()
    city.city_built_buildings = [
        {"id": "mint", "slots": ["coin_collection"], "quality_priority": "best"}
    ]
    check(tm.assign_townsfolk(0), "a townsfolk must be assignable to the Mint", state)
    city.do_tick()
    check(absf(city.mint_tax_share - 0.05) < 0.0001,
            "one staffed Mint must add 5%% to the tax, got %f" % city.mint_tax_share, state)
    check(city.get_tax_income_per_tick() == 42,
            "with 20 citizens the tax must be 42 (40 + 5%%), got %d"
                    % city.get_tax_income_per_tick(), state)
    var row: Dictionary = wm.get_planned_treasury_income_map() \
            .get(city.TAX_INCOME_TYPE, {}).get(city.TREASURY_FLAT_TYPE_KEY, {})
    check(str(row.get("label", "")).contains("+ 5%"),
            "the treasury row must name the Mint's share, got \"%s\"" % str(row.get("label", "")), state)

    # Without a worker the building stands idle and gives nothing.
    tm.remove_townsfolk(0)
    city.do_tick()
    check(absf(city.mint_tax_share) < 0.0001,
            "an unstaffed Mint must not add to the tax, got %f" % city.mint_tax_share, state)
    check(city.get_tax_income_per_tick() == 40,
            "without a worker the tax must be the base 40, got %d"
                    % city.get_tax_income_per_tick(), state)

    # --- 3. Two Mints, the shares add up ---
    city.city_built_buildings.append(
        {"id": "mint", "slots": ["coin_collection"], "quality_priority": "best"}
    )
    city.idle_population = maxi(city.idle_population, 4)
    check(tm.assign_townsfolk(0), "the first Mint must get a worker again", state)
    city.do_tick()
    check(absf(city.mint_tax_share - 0.05) < 0.0001,
            "one of two staffed Mints must add 5%%, got %f" % city.mint_tax_share, state)
    check(tm.assign_townsfolk(1), "the second Mint must get a worker", state)
    city.do_tick()
    check(absf(city.mint_tax_share - 0.10) < 0.0001,
            "two staffed Mints must add 10%%, got %f" % city.mint_tax_share, state)
    check(city.get_tax_income_per_tick() == 44,
            "with 20 citizens and two Mints the tax must be 44, got %d"
                    % city.get_tax_income_per_tick(), state)

    _finish(main_map, state)

func _finish(main_map, state: Dictionary) -> void:
    if main_map != null and is_instance_valid(main_map):
        get_root().remove_child(main_map)
        main_map.free()
    if state["failed"]:
        print("COINAGE TEST FAILED")
        quit(1)
    else:
        print("COINAGE TEST OK")
        quit(0)

func check(cond: bool, msg: String, state: Dictionary):
    if not cond:
        push_error("ASSERT: " + msg)
        print("ASSERT FAILED: ", msg)
        state["failed"] = true
