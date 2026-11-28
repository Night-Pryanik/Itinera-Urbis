extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")
const GOODS := ["pottery", "bricks", "amphora", "porcelain", "fine_ceramics", "clay_tablets"]
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
    if not city.is_tech_unlocked("pottery"):
        city.unlocked_technologies.append("pottery")
    main_map.town_manager.towns.append({"id": "ceramics_test", "name": "Testville",
        "treasury": 1000000, "buy_pool": GOODS.duplicate()})
    var product: Dictionary = gd.products["pottery"]
    var challenge: Dictionary = product["challenge"]
    _check(gd.product_groups.get("ceramics_goods", []) == GOODS, "ceramics group contains all six goods")
    _check(str(product.get("fame_group", "")) == "ceramics_goods", "all fame tiers count the ceramics group")
    for record in fame.fame_records():
        if str(record.get("product", "")) == "pottery":
            _check(str(record.get("product_name", "")) == gd.get_product_group_name("ceramics_goods"),
                "fame conditions name the ceramics group")
    var reputation_text: String = fame.reward_text(product["reputation"]["reward"], "pottery")
    _check(reputation_text.contains(gd.get_product_group_name("ceramics_goods")), "reputation reward names the ceramics group")
    _check(not city.is_craft_available(gd.find_craft("porcelain")), "porcelain starts locked")
    _sell(city, trade, "bricks", 1000, "exceptional")
    _check(fame.is_challenge_completed("ceramics_challenge"), "brick sales alone complete the challenge")
    _check(city.is_craft_available(gd.find_craft("porcelain")), "brick sales alone also unlock porcelain")
    fame.deserialize({"sold": {}})
    city.specialization_challenge_picks = 0
    fame.record_production("bricks", 1000, "exceptional")
    _sell(city, trade, "amphora", 199, "common")
    _check(fame.tier_counter(product, product["reputation"]) == 199, "reputation counts amphora sales")
    _check(is_zero_approx(fame.get_fame_trade_price_share("bricks")), "reputation waits for 200 sales")
    _sell(city, trade, "bricks", 1, "common")
    for pid in GOODS:
        _check(is_equal_approx(fame.get_fame_trade_price_share(pid), 0.10), pid + " gets the reputation price bonus")
    _sell(city, trade, "bricks", 250, "fine")
    _sell(city, trade, "clay_tablets", 249, "fine")
    _check(fame.tier_counter(product, challenge) == 0, "production and below-exceptional sales do not count for challenge")
    _check(fame.tier_counter(product, product["brand"]) == 499, "brand counts fine sales of different ceramics")
    _check(not city.is_craft_available(gd.find_craft("porcelain")), "brand waits for 500 fine sales")
    var dyed: String = gd.make_generated_id("fine_ceramics", "woad")
    gd.materialise_generated(dyed)
    _sell(city, trade, dyed, 1, gd.make_quality_key("fine", "common"))
    _check(fame.tier_counter(product, product["brand"]) == 500, "dyed ceramics count once for the brand")
    _check(city.is_craft_available(gd.find_craft("porcelain")), "mixed ceramics sales unlock porcelain")
    var brand_saved: Dictionary = fame.serialize()
    fame.deserialize(brand_saved)
    _check(city.is_craft_available(gd.find_craft("porcelain")), "brand unlock survives save")
    for pid in GOODS + [dyed]:
        _check(is_equal_approx(fame.get_fame_trade_price_share(pid), 0.10), pid + " keeps the reputation bonus after save")
    var expected := 0
    for pid in GOODS:
        _sell(city, trade, pid, 100, "exceptional")
        expected += 100
        _check(fame.tier_counter(product, challenge) == expected, pid + " sale counts toward the challenge")
    _sell(city, trade, dyed, 399, gd.make_quality_key("exceptional", "common"))
    _check(fame.tier_counter(product, challenge) == 999, "dyed ceramics count once")
    _check(not fame.is_challenge_completed("ceramics_challenge"), "challenge remains locked below threshold")
    _sell(city, trade, dyed, 1, gd.make_quality_key("exceptional", "common"))
    _check(fame.is_challenge_completed("ceramics_challenge"), "challenge completes at threshold")
    _check(city.get_pending_specialization_picks() == 1, "challenge grants one specialization pick")
    var saved: Dictionary = fame.serialize()
    fame.deserialize(saved)
    _check(fame.tier_counter(product, challenge) == 1000, "mixed progress survives save")
    _check(fame.is_challenge_completed("ceramics_challenge"), "completion survives save")
    _check(city.choose_specialization("ceramics_specialization"), "ceramics specialization is available")
    var multipliers: Dictionary = city.get_production_product_multipliers()
    for pid in GOODS + [dyed]:
        _check(is_equal_approx(city.get_specialization_product_share("trade_sell_price", pid), 0.15), pid + " receives sale bonus")
        _check(is_equal_approx(gd.product_output_multiplier(multipliers, pid), 1.20), pid + " receives production bonus")
    for pid in ["clay", "kaolin", "leather_clothes"]:
        _check(is_equal_approx(city.get_specialization_product_share("trade_sell_price", pid), 0.0), pid + " has no ceramics sale bonus")
        _check(is_equal_approx(gd.product_output_multiplier(multipliers, pid), 1.0), pid + " has no ceramics production bonus")
    main_map.queue_free()
    WATCHDOG.report_skipped()
    print("CERAMICS SPECIALIZATION TEST FAILED" if _failed else "CERAMICS SPECIALIZATION TEST OK")
    quit(1 if _failed else 0)

func _sell(city: Node, trade: Node, pid: String, amount: int, quality: String) -> void:
    city.add_to_storage(pid, amount, quality)
    var result: Dictionary = trade.submit_order({"town_id": "ceramics_test", "side": "buy",
        "product_id": pid, "amount": amount, "unit_price": 1, "permanent": false})
    _check(bool(result.get("ok", false)), pid + " sale succeeds")

func _check(condition: bool, message: String) -> void:
    if not condition:
        _failed = true
        push_error("ASSERT: " + message)
        print("ASSERT FAILED: ", message)
