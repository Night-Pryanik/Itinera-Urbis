extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")
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
    city.total_population = 0
    city.specialization_claimed = 0
    city.specialization_challenge_picks = 0
    city.chosen_specialization_ids.clear()
    city.ignore_tech_requirements = false
    city.unlocked_technologies.erase("dyeing")
    if not city.is_tech_unlocked("leatherworking"):
        city.unlocked_technologies.append("leatherworking")
    _check(city.are_prerequisites_met("morocco_leather"), "leatherworking alone satisfies the prerequisites")
    if not city.is_tech_unlocked("morocco_leather"):
        city.unlocked_technologies.append("morocco_leather")
    _check(not city.is_tech_unlocked("dyeing"), "dyeing remains locked")
    _check(city.is_craft_available(gd.find_craft("morocco_leather")), "morocco leather is available without dyeing")
    _check(city.is_craft_available(gd.find_craft("morocco_leather_clothes")), "morocco clothes are available without dyeing")
    var inputs: Dictionary = gd.find_craft("morocco_leather").get("resources", {})
    _check(inputs.size() == 2 and inputs.has("hide") and inputs.has("@tannins"), "morocco leather needs no dye")

    var tech: Dictionary = {}
    var house: Dictionary = {}
    var workshop: Dictionary = {}
    for item in gd.technologies:
        if item.get("id") == "morocco_leather":
            tech = item
    for item in gd.buildings:
        if item.get("id") == "leatherworker_house":
            house = item
        if item.get("id") == "leatherworker_workshop":
            workshop = item
    _check(tech.get("era") == "medieval" and tech.get("prerequisites") == [["leatherworking"]], "technology and prerequisites")
    _check(house.get("upgrades_into") == "leatherworker_workshop", "house upgrades to workshop")
    _check(float(workshop.get("production_slots", 0)) == 2.0 and workshop.get("unlock_tech") == "morocco_leather", "workshop capacity and gate")
    for recipe_id in ["leather", "leather_clothes", "morocco_leather", "morocco_leather_clothes", "branded_leather"]:
        _check("leatherworker_workshop" in gd.find_craft(recipe_id).get("produced_in", []), recipe_id + " works in workshop")
    _check(gd.find_craft("morocco_leather_clothes").get("resources", {}).has("morocco_leather"), "clothes consume morocco leather")
    _check("morocco_leather_clothes" in gd.product_groups.get("clothes", []), "clothes are consumed")

    city.city_storage.clear()
    city.city_quality_detail.clear()
    var pools: Dictionary = load("res://scripts/town_economy.gd").build_pools("leather_test", [])
    main_map.town_manager.towns.append({"id": "leather_test", "name": "Testville",
        "treasury": 1000000, "buy_pool": pools.get("buy_pool", [])})
    var trade = main_map.town_trade_manager
    var product: Dictionary = gd.products["leather_clothes"]
    var brand: Dictionary = gd.find_craft("branded_leather")
    _check(not city.is_craft_available(brand), "brand starts locked")
    fame.record_production("morocco_leather_clothes", 2000, "exceptional")
    _check(fame.tier_counter(product, product["challenge"]) == 0, "production does not count as sales")
    _sell(city, trade, "leather_clothes", 200, "common")
    _check(is_equal_approx(fame.get_fame_trade_price_share("morocco_leather_clothes"), 0.10), "reputation applies to both garments")
    _sell(city, trade, "leather_clothes", 200, "fine")
    _sell(city, trade, "leather_clothes", 100, "exceptional")
    _sell(city, trade, "morocco_leather_clothes", 199, "exceptional")
    _check(not city.is_craft_available(brand), "brand waits for 500 fine sales")
    _sell(city, trade, "morocco_leather_clothes", 1, "exceptional")
    _check(city.is_craft_available(brand), "mixed sales unlock brand")
    _check(not fame.is_challenge_completed("leather_challenge"), "challenge waits for exceptional sales")
    var dyed: String = gd.make_generated_id("morocco_leather_clothes", "woad")
    gd.materialise_generated(dyed)
    _sell(city, trade, dyed, 700, gd.make_quality_key("exceptional", "common"))
    _check(fame.tier_counter(product, product["challenge"]) == 1000, "dyed and ordinary sales count once")
    _check(fame.is_challenge_completed("leather_challenge"), "mixed sales complete challenge")
    _check(city.get_pending_specialization_picks() == 1, "challenge grants one pick")
    _sell(city, trade, "leather_clothes", 10, "exceptional")
    _check(city.get_pending_specialization_picks() == 1, "challenge cannot grant twice")
    var saved: Dictionary = fame.serialize()
    fame.deserialize(saved)
    _check(fame.is_challenge_completed("leather_challenge"), "completion survives save")
    _check(fame.tier_counter(product, product["challenge"]) == 1010, "mixed sales survive save")
    _check(is_equal_approx(fame.get_fame_trade_price_share(dyed), 0.10), "dyed reputation survives save")
    _check(city.choose_specialization("leather_specialization"), "specialization is unlocked")
    for pid in ["leather_clothes", "morocco_leather_clothes", dyed]:
        _check(is_equal_approx(city.get_specialization_product_share("trade_sell_price", pid), 0.15), pid + " price bonus")
        _check(is_equal_approx(gd.product_output_multiplier(city.get_production_product_multipliers(), pid), 1.20), pid + " production bonus")
    for pid in ["leather", "morocco_leather", "branded_leather", "wool_clothes"]:
        _check(is_equal_approx(city.get_specialization_product_share("trade_sell_price", pid), 0.0), pid + " has no bonus")
    var locale := TranslationServer.get_locale()
    TranslationServer.set_locale("ru")
    city.city_name = "Тестоград"
    _check(gd.resolve_display_tags(str(TranslationServer.translate('Leather "<city_name>"', "resources.name"))) == 'Кожа «Тестоград»', "brand is localized with city name")
    TranslationServer.set_locale(locale)
    main_map.queue_free()
    WATCHDOG.report_skipped()
    print("MOROCCO LEATHER TEST FAILED" if _failed else "MOROCCO LEATHER TEST OK")
    quit(1 if _failed else 0)

func _sell(city: Node, trade: Node, pid: String, amount: int, quality: String) -> void:
    city.add_to_storage(pid, amount, quality)
    var result: Dictionary = trade.submit_order({"town_id": "leather_test", "side": "buy",
        "product_id": pid, "amount": amount, "unit_price": 1, "permanent": false})
    _check(bool(result.get("ok", false)), pid + " sale succeeds")

func _check(condition: bool, message: String) -> void:
    if not condition:
        _failed = true
        push_error("ASSERT: " + message)
        print("ASSERT FAILED: ", message)
