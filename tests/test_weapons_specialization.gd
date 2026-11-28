extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")
const WEAPONS := ["copper_weapons", "bronze_weapons", "iron_weapons", "steel_weapons", "damascus_weapons"]
var _failed := false

func _initialize() -> void:
    WATCHDOG.arm(self)
    _run()

func _run() -> void:
    var main_map = load("res://scenes/MainMap.tscn").instantiate()
    root.add_child(main_map)
    await process_frame
    await process_frame
    var gd = root.get_node("GameData")
    var city = root.get_node("CityData")
    var fame = main_map.challenge_manager
    var trade = main_map.town_trade_manager
    city.total_population = 0
    city.specialization_claimed = 0
    city.specialization_challenge_picks = 0
    city.chosen_specialization_ids.clear()
    city.city_storage.clear()
    city.city_quality_detail.clear()
    if not city.is_tech_unlocked("steel_making"):
        city.unlocked_technologies.append("steel_making")
    main_map.town_manager.towns.append({"id": "weapons_test", "name": "Testville",
        "treasury": 1000000, "buy_pool": WEAPONS.duplicate()})
    var product: Dictionary = gd.products["steel_weapons"]
    var challenge: Dictionary = product["challenge"]
    var brand: Dictionary = gd.find_craft("damascus_steel")
    var branded_weapons: Dictionary = gd.find_craft("damascus_weapons")
    _check(gd.product_groups.get("weapons_goods", []) == WEAPONS, "group includes all weapon types")
    for pid in gd.products:
        if gd.products[pid].get("category", "") == "weapons":
            _check(pid in WEAPONS, str(pid) + " belongs to the weapon group")
    _check(str(product.get("fame_group", "")) == "weapons_goods", "all fame tiers count the weapon group")
    for record in fame.fame_records():
        if str(record.get("product", "")) == "steel_weapons":
            _check(str(record.get("product_name", "")) == gd.get_product_group_name("weapons_goods"),
                "fame conditions name the weapon group")
    var reputation_text: String = fame.reward_text(product["reputation"]["reward"], "steel_weapons")
    _check(reputation_text.contains(gd.get_product_group_name("weapons_goods")), "reputation reward names the group")
    _check(not city.is_craft_available(brand) and not city.is_craft_available(branded_weapons), "brand and its weapons start locked")

    fame.record_production("copper_weapons", 1000, "exceptional")
    _sell(city, trade, "copper_weapons", 199, "common")
    _check(fame.tier_counter(product, product["reputation"]) == 199, "copper sales count for reputation")
    _check(is_zero_approx(fame.get_fame_trade_price_share("bronze_weapons")), "reputation waits for 200 sales")
    _sell(city, trade, "bronze_weapons", 1, "common")
    for pid in WEAPONS:
        _check(is_equal_approx(fame.get_fame_trade_price_share(pid), 0.10), pid + " gets reputation bonus")
    _sell(city, trade, "copper_weapons", 250, "fine")
    _sell(city, trade, "iron_weapons", 249, "fine")
    _check(fame.tier_counter(product, challenge) == 0, "production and lower-quality sales do not count for challenge")
    _check(fame.tier_counter(product, product["brand"]) == 499, "brand counts fine sales of different weapons")
    _check(not city.is_craft_available(brand), "brand waits for 500 fine sales")
    _sell(city, trade, "bronze_weapons", 1, "fine")
    _check(city.is_craft_available(brand) and city.is_craft_available(branded_weapons), "mixed weapon sales unlock branded steel and weapons")
    var saved: Dictionary = fame.serialize()
    fame.deserialize(saved)
    _check(city.is_craft_available(brand), "brand survives save")
    for pid in WEAPONS:
        _check(is_equal_approx(fame.get_fame_trade_price_share(pid), 0.10), pid + " keeps reputation bonus after save")

    var expected := 0
    for pid in WEAPONS:
        _sell(city, trade, pid, 100, "exceptional")
        expected += 100
        _check(fame.tier_counter(product, challenge) == expected, pid + " counts for challenge")
    _sell(city, trade, "copper_weapons", 499, "exceptional")
    _check(fame.tier_counter(product, challenge) == 999, "challenge counts mixed sales")
    _check(not fame.is_challenge_completed("steel_challenge"), "challenge waits for 1000 exceptional sales")
    _sell(city, trade, "bronze_weapons", 1, "exceptional")
    _check(fame.is_challenge_completed("steel_challenge"), "mixed weapon sales complete challenge")
    _check(city.get_pending_specialization_picks() == 1, "challenge grants one specialization pick")
    _sell(city, trade, "iron_weapons", 1, "exceptional")
    _check(city.get_pending_specialization_picks() == 1, "challenge grants its pick only once")
    saved = fame.serialize()
    fame.deserialize(saved)
    _check(fame.tier_counter(product, challenge) == 1001, "mixed progress survives save")
    _check(fame.is_challenge_completed("steel_challenge"), "completion survives save")
    _check(city.choose_specialization("weaponsmith_specialization"), "weapon specialization is available")
    var multipliers: Dictionary = city.get_production_product_multipliers()
    for pid in WEAPONS:
        _check(is_equal_approx(city.get_specialization_product_share("trade_sell_price", pid), 0.15), pid + " gets specialization sale bonus")
        _check(is_equal_approx(gd.product_output_multiplier(multipliers, pid), 1.20), pid + " gets specialization production bonus")
    for pid in ["copper", "steel", "damascus_steel", "damascus_tools"]:
        _check(is_zero_approx(fame.get_fame_trade_price_share(pid)), pid + " has no weapon reputation bonus")
        _check(is_zero_approx(city.get_specialization_product_share("trade_sell_price", pid)), pid + " has no weapon sale bonus")
        _check(is_equal_approx(gd.product_output_multiplier(multipliers, pid), 1.0), pid + " has no weapon production bonus")
    city.city_storage.clear()
    city.city_quality_detail.clear()
    city.add_to_storage("damascus_steel", 20, "common")
    city.add_to_storage("charcoal", 20, "common")
    var container = load("res://scripts/craft_container.gd").new(branded_weapons)
    var result: Dictionary = container.tick(float(branded_weapons.get("time", 1)), true, "best", 1.0, multipliers)
    var output := 0
    for release in result.get("releases", []):
        if str(release.get("pid", "")) == "damascus_weapons":
            output += int(release.get("amount", 0))
    _check(bool(result.get("completed", false)) and output == 12, "branded weapons receive the production bonus")
    main_map.queue_free()
    WATCHDOG.report_skipped()
    print("WEAPONS SPECIALIZATION TEST FAILED" if _failed else "WEAPONS SPECIALIZATION TEST OK")
    quit(1 if _failed else 0)

func _sell(city: Node, trade: Node, pid: String, amount: int, quality: String) -> void:
    city.add_to_storage(pid, amount, quality)
    var result: Dictionary = trade.submit_order({"town_id": "weapons_test", "side": "buy",
        "product_id": pid, "amount": amount, "unit_price": 1, "permanent": false})
    _check(bool(result.get("ok", false)), pid + " sale succeeds")

func _check(condition: bool, message: String) -> void:
    if not condition:
        _failed = true
        push_error("ASSERT: " + message)
        print("ASSERT FAILED: ", message)
