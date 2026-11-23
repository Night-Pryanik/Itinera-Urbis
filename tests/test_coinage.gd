# Headless test of the coinage branch (the seigniorage of the Mint):
#   godot --headless --path . --script res://tests/test_coinage.gd
#
# The Coinage technology unlocks the Mint, and the Mint is a coiner: it melts copper,
# silver or gold into coin and keeps the difference between the face value of the coins
# and the metal spent on them. That difference is the seigniorage — a virtual yield of the
# recipe (display_result.seigniorage, data/crafts/pseudo.json), paid into the treasury over
# the cycle of the strike and never put into the storage. Checks:
#
#   1. The data: the technology, the building, the strike recipes, the virtual products.
#   2. The metal: a strike consumes its charge from the storage and pays the seigniorage
#      into the treasury, under the type CityData.SEIGNIORAGE_INCOME_TYPE; nothing of it
#      reaches the warehouse.
#   3. A starving Mint pays nothing: a strike without metal mints no coin.
#   4. The Assaying technology and the precision instruments of the mint master scale the
#      seigniorage through the building's output multiplier.
#   5. The treasury breakdown: the "Seigniorage" row is flat and matches the plan; the tax
#      is NOT raised by the Mint any more (that bonus belongs to the Tax Collector).
#   6. A reloaded container neither loses nor repeats a payment (virtual_paid is saved).
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
    # The toggle stops only the write-off: the population dynamics still run, and an empty
    # food pool counts as starvation. A zero ration keeps food_demand at zero.
    city.food_consumption_enabled = false
    city.food_per_citizen = 0
    city.city_food_pool.clear()

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
    check(str(mint_data.get("profession", "")) == "mint_worker",
            "the Mint must employ the mint worker", state)
    var recipes: Array = mint_data.get("default_recipes", [])
    check(recipes.has("strike_copper_coins"), "the Mint must start with a copper strike", state)
    check(gdata.is_virtual_product("seigniorage"),
            "seigniorage must be flagged as a virtual product", state)
    check(gdata.get_price("seigniorage") <= 0.0,
            "seigniorage must be a virtual yield, not a priced good", state)
    var strike: Dictionary = gdata.get_craft("strike_copper_coins")
    check(int(strike.get("display_result", {}).get("seigniorage", 0)) == 6,
            "a copper strike must pay 6 units of seigniorage", state)
    check(int(strike.get("resources", {}).get("copper", 0)) == 20,
            "a copper strike must spend 20 copper", state)
    # The poll tax bonus has moved to the Tax Collector: the Mint gives no coinage any more.
    check(gdata.get_building_additional_yield("mint").is_empty(),
            "the Mint must not carry a poll tax bonus any more", state)

    # --- 2. One strike with metal: the seigniorage reaches the treasury ---
    # The storage is emptied first: then the internal market has nothing to sell and the only
    # income of the treasury is the seigniorage (the upkeep of the Mint is an expense and is
    # checked through the same accumulators at the end of the cycle).
    city.city_storage.clear()
    city.city_quality_detail.clear()
    city.total_population = 20
    city.idle_population = 4
    tm.assigned_buildings.clear()
    city.city_built_buildings = [
        {"id": "mint", "slots": ["strike_copper_coins"], "quality_priority": "best"}
    ]
    check(tm.assign_townsfolk(0), "a townsfolk must be assignable to the Mint", state)
    city.treasury = 0
    city.treasury_income_accum.clear()
    city.treasury_income_product_accum.clear()
    city.treasury_expense_accum.clear()
    city.add_to_storage("copper", 200, "common")
    city.add_to_storage("charcoal", 200, "common")

    # The first tick has charged a tenth of the metal: floor(6 × 0.1) = 0 coins are due yet.
    city.do_tick()
    check(int(city.treasury_income_accum.get(city.SEIGNIORAGE_INCOME_TYPE, 0)) == 0,
            "on the first tenth of the charge nothing is due yet", state)
    # After the second tenth the strike owes floor(6 × 0.2) = 1 coin.
    city.do_tick()
    check(int(city.treasury_income_accum.get(city.SEIGNIORAGE_INCOME_TYPE, 0)) == 1,
            "after two tenths the strike must have paid 1 coin, got %d"
                    % int(city.treasury_income_accum.get(city.SEIGNIORAGE_INCOME_TYPE, 0)), state)
    check(int(city.city_storage.get("copper", 0)) < 200,
            "the strike must consume copper from the storage", state)
    check(not city.city_storage.has("seigniorage"),
            "the seigniorage must never reach the warehouse", state)

    # The rest of the cycle: exactly the yield of the recipe (6 coins), no more and no less.
    for i in range(8):
        city.do_tick()
    var paid_cycle: int = int(city.treasury_income_accum.get(city.SEIGNIORAGE_INCOME_TYPE, 0))
    check(paid_cycle == 6,
            "a full cycle must pay exactly 6 coins of seigniorage, got %d" % paid_cycle, state)
    check(int(city.city_storage.get("copper", 0)) == 180,
            "a copper strike must spend exactly 20 copper, got %d spent"
                    % (200 - int(city.city_storage.get("copper", 0))), state)
    check(int(city.city_storage.get("charcoal", 0)) == 190,
            "a copper strike must spend exactly 10 fuel, got %d spent"
                    % (200 - int(city.city_storage.get("charcoal", 0))), state)
    # The coins really reached the treasury: it grew by the income minus the recorded upkeep.
    check(city.treasury == _sum_flat(city.treasury_income_accum) - _sum_flat(city.treasury_expense_accum),
            "the treasury must equal the recorded income minus the upkeep (%d)"
                    % city.treasury, state)

    # --- 3. A starving Mint pays nothing ---
    city.city_storage.clear()
    city.city_quality_detail.clear()
    city.treasury = 0
    city.treasury_income_accum.clear()
    city.treasury_income_product_accum.clear()
    for i in range(5):
        city.do_tick()
    check(int(city.treasury_income_accum.get(city.SEIGNIORAGE_INCOME_TYPE, 0)) == 0,
            "a Mint without metal must mint no coin", state)
    check(city.treasury == 0, "a starving Mint must leave the treasury alone", state)

    # --- 4. The multipliers: Assaying and the precision instruments ---
    city.city_storage.clear()
    city.city_quality_detail.clear()
    city.add_to_storage("copper", 400, "common")
    city.add_to_storage("charcoal", 400, "common")
    city.unlocked_technologies.append("coinage")
    city.unlocked_technologies.append("assaying")
    city.do_tick()
    check(is_equal_approx(city.get_building_production_multiplier("mint", false), 1.5),
            "assaying must give the Mint a 1.5 building multiplier", state)
    var strike_recipe: Dictionary = gdata.get_craft("strike_copper_coins")
    check(city.get_seigniorage_per_cycle(strike_recipe, 1.5) == 9,
            "a copper strike under assaying must plan 9 coins, got %d"
                    % city.get_seigniorage_per_cycle(strike_recipe, 1.5), state)

    # The tools of the mint master: steel precision instruments add another 25%.
    city.add_to_storage("steel_precision_instruments", 40, "common")
    city.do_tick()
    var prof_bonus: float = wm.get_building_production_bonus(0)
    check(prof_bonus > 1.24 and prof_bonus < 1.26,
            "steel instruments must give the mint worker a 1.25 bonus, got %f" % prof_bonus, state)
    var cycle_with_tools: int = city.get_seigniorage_per_cycle(strike_recipe, 1.5 * prof_bonus)
    check(cycle_with_tools == 11,
            "with the tools a copper strike must plan 11 coins, got %d" % cycle_with_tools, state)

    # --- 5. The treasury breakdown: a flat "Seigniorage" row ---
    # The plan is the yield over the craft time: 11 coins per 10 sec = 1.1 / sec. The
    # accumulators are cleared, so the row carries the plan alone.
    city.treasury_income_accum.clear()
    city.treasury_income_product_accum.clear()
    city.treasury_income_snapshot.clear()
    city.treasury_income_product_snapshot.clear()
    var planned: Dictionary = wm.get_planned_treasury_income_map()
    check(planned.has(city.SEIGNIORAGE_INCOME_TYPE),
            "the planned breakdown must show the seigniorage", state)
    var planned_row: Dictionary = planned.get(city.SEIGNIORAGE_INCOME_TYPE, {}) \
            .get(city.TREASURY_FLAT_TYPE_KEY, {})
    var planned_rate: float = float(planned_row.get("rate", 0.0))
    check(absf(planned_rate - 1.1) < 0.01,
            "the planned seigniorage rate must be 1.1 coins/sec, got %f" % planned_rate, state)

    # And the paid coins show up as the same flat type of the actual breakdown: the actual
    # row reads the accumulator of the window, so the window is rotated to make the payments
    # of the past ticks the data of the last complete window.
    for i in range(10):
        city.do_tick()
    city.rotate_treasury_window()
    var actual: Dictionary = wm.get_actual_treasury_income_map()
    check(actual.has(city.SEIGNIORAGE_INCOME_TYPE),
            "the treasury breakdown must contain the type \"%s\"" % city.SEIGNIORAGE_INCOME_TYPE, state)
    var flat_row: Dictionary = actual.get(city.SEIGNIORAGE_INCOME_TYPE, {}) \
            .get(city.TREASURY_FLAT_TYPE_KEY, {})
    check(not flat_row.is_empty(),
            "the seigniorage must be a flat row (key %s)" % city.TREASURY_FLAT_TYPE_KEY, state)
    check(float(flat_row.get("rate", 0.0)) > 0.0,
            "the seigniorage row must carry a rate, got %s" % str(flat_row.get("rate", 0.0)), state)
    check(str(flat_row.get("label", "")).is_empty(),
            "the seigniorage row must not carry the tax label, got \"%s\""
                    % str(flat_row.get("label", "")), state)

    # The Mint no longer raises the poll tax: that bonus belongs to the Tax Collector.
    check(absf(city.tax_collector_share) < 0.0001,
            "a staffed Mint must not raise the poll tax any more, got %f" % city.tax_collector_share, state)

    # --- 6. The virtual payout is saved with the container ---
    var container = load("res://scripts/craft_container.gd").new(strike_recipe)
    container.add_virtual_paid(city.SEIGNIORAGE_YIELD_KEY, 4)
    var saved: Dictionary = container.serialize()
    check(saved.has("virtual_paid"), "the container must serialize its virtual payouts", state)
    var restored = load("res://scripts/craft_container.gd").new(strike_recipe, saved)
    check(restored.get_virtual_paid(city.SEIGNIORAGE_YIELD_KEY) == 4,
            "the restored container must keep the 4 coins already paid, got %d"
                    % restored.get_virtual_paid(city.SEIGNIORAGE_YIELD_KEY), state)
    container.reset()
    check(container.get_virtual_paid(city.SEIGNIORAGE_YIELD_KEY) == 0,
            "a new cycle must start with nothing paid", state)

    _finish(main_map, state)

# The sum of a flat accumulator: { source -> amount }.
func _sum_flat(accum: Dictionary) -> int:
    var total := 0
    for source in accum:
        total += int(accum[source])
    return total

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
