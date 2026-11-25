# Both textile fame ladders, town sales and their shared clothing bonus.
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")
const TownEconomy = preload("res://scripts/town_economy.gd")

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
    var fame = main_map.get("challenge_manager")
    var trade = main_map.get("town_trade_manager")
    if fame == null or trade == null:
        _check(false, "the map provides fame and town trade")
        _finish()
        return

    city.total_population = 0
    city.specialization_claimed = 0
    city.specialization_challenge_picks = 0
    city.chosen_specialization_ids.clear()
    city.city_storage.clear()
    city.city_quality_detail.clear()
    if not city.is_tech_unlocked("weaving"):
        city.unlocked_technologies.append("weaving")

    # Resident demand is independent of the production closure and includes
    # each member of a consume-all basket, even if the town makes that member.
    var pools: Dictionary = TownEconomy.build_pools("textile_test", [])
    var local: Dictionary = TownEconomy.build_pools("textile_local", ["flax", "wool"])
    for entry in gd.get_profession_consumption("all"):
        if float(entry.get("interval", 0.0)) <= 0.0:
            continue
        var keys: Array = []
        if bool(entry.get("is_group", false)) and bool(entry.get("consume_all", false)):
            keys = entry.get("group_members", [])
        else:
            keys = [entry.get("display_key", "")]
        for key in keys:
            if gd.parse_generated_id(str(key)).is_empty():
                _check(pools["buy_pool"].has(key), "town demand follows citizen rule: " + str(key))
                _check(local["buy_pool"].has(key), "local production does not remove resident demand: " + str(key))
    _check(not pools["buy_pool"].has("flax"), "no fixed flax import")
    _check(not pools["buy_pool"].has("wool"), "no fixed wool import")
    _check(local["sell_pool"].has("wool_clothes") and local["buy_pool"].has("wool_clothes"),
        "residents buy wool clothes even where they are produced")
    for fiber in ["cotton", "flax", "hemp", "jute", "ramie", "kenaf", "yucca", "sisal", "papyrus", "velvetleaf", "coir"]:
        _check(gd.product_groups.get("plant_fibers", []).has(fiber), "byssus accepts " + fiber)
    _check(gd.find_craft("linen_byssus")["resources"].has("@plant_fibers"), "byssus uses plant fibers")
    _check(gd.find_craft("cashmere")["resources"].has("@wools"), "cashmere uses wool group")

    var town := {"id": "textile_test", "name": "Testville", "treasury": 1000000,
        "buy_pool": pools.get("buy_pool", [])}
    main_map.town_manager.towns.append(town)
    for line in [["fabric_clothes", "linen_byssus", "flax_specialization", "branded_fabric_clothes"],
                 ["wool_clothes", "cashmere", "wool_specialization", "branded_wool_clothes"]]:
        var pid: String = line[0]
        var prestige: String = line[1]
        var spec_id: String = line[2]
        var branded: String = line[3]
        var garment_recipe: Dictionary = gd.find_craft(branded)
        var product: Dictionary = gd.products[pid]
        var recipe: Dictionary = gd.find_craft(prestige)
        var brand_threshold := int(product["brand"]["threshold"])
        var challenge_threshold := int(product["challenge"]["threshold"])
        _check(not recipe.is_empty(), prestige + " recipe exists")
        _check(str(gd.products[prestige].get("brand_of", "")) == pid, prestige + " belongs to its own ladder")
        _check(not city.is_craft_available(recipe), prestige + " starts locked")
        _check(not city.is_craft_available(garment_recipe), branded + " starts locked")
        _check(garment_recipe.get("resources", {}).has(prestige), branded + " uses the prestige material")
        _check(not city.is_specialization_available(city.get_specialization(spec_id)), spec_id + " starts locked")
        city.add_to_storage(pid, 1, "common")
        _check(bool(_sell(trade, pid, 1).get("ok", false)), pid + " common-quality sale succeeds")
        _check(not city.is_craft_available(recipe), pid + " common quality does not count toward the brand")
        city.add_to_storage(pid, brand_threshold - 1, "exceptional")
        _check(bool(_sell(trade, pid, brand_threshold - 1).get("ok", false)), pid + " first sale succeeds")
        _check(not city.is_craft_available(recipe), prestige + " is locked below its brand threshold")
        city.add_to_storage(pid, 1, "exceptional")
        _check(bool(_sell(trade, pid, 1).get("ok", false)), pid + " brand sale succeeds")
        _check(city.is_craft_available(recipe), prestige + " opens at the brand threshold")
        _check(city.is_craft_available(garment_recipe), branded + " opens at the brand threshold")
        _check(not city.is_specialization_available(city.get_specialization(spec_id)), spec_id + " waits for the challenge")
        var dyed_id: String = gd.make_generated_id(pid, "woad")
        gd.materialise_generated(dyed_id)
        city.add_to_storage(dyed_id, challenge_threshold - brand_threshold, gd.make_quality_key("exceptional", "common"))
        _check(bool(_sell(trade, dyed_id, challenge_threshold - brand_threshold).get("ok", false)), pid + " dyed sale succeeds")
        _check(fame.is_challenge_completed(str(product["challenge"]["id"])), pid + " challenge is complete")
        _check(city.is_specialization_available(city.get_specialization(spec_id)), spec_id + " is independently available")

    var saved: Dictionary = fame.serialize()
    fame.deserialize(saved)
    for pid in ["fabric_clothes", "wool_clothes"]:
        var product: Dictionary = gd.products[pid]
        _check(fame.tier_counter(product, product["challenge"]) == 1000, pid + " sale progress survives save")
        _check(fame.is_challenge_completed(str(product["challenge"]["id"])), pid + " completion survives save")
    _check(city.get_pending_specialization_picks() == 2, "both challenges grant their own pick")
    _check(city.choose_specialization("wool_specialization"), "wool specialization can be chosen")
    for pid in gd.product_groups.get("clothes", []):
        _check(is_equal_approx(float(city.get_production_product_multipliers().get(pid, 1.0)), 1.2),
            str(pid) + " receives the wool bonus")
    _check(city.choose_specialization("flax_specialization"), "flax specialization can also be chosen")
    var multipliers: Dictionary = city.get_production_product_multipliers()
    for pid in gd.product_groups.get("clothes", []):
        _check(is_equal_approx(float(multipliers.get(pid, 1.0)), 1.4), str(pid) + " receives both bonuses")
    _check(is_equal_approx(float(multipliers.get("carpet", 1.0)), 1.0), "the clothing bonus does not affect carpets")
    _check(is_equal_approx(float(multipliers.get("cashmere", 1.0)), 1.2), "wool goods retain their own bonus")
    _check(is_equal_approx(float(multipliers.get("linen_byssus", 1.0)), 1.2), "flax goods receive their own bonus")

    # The multiplier map may have been built before the dyed product was registered.
    var variant: String = gd.make_generated_id("wool_clothes", "ochre")
    var before_registration: Dictionary = multipliers.duplicate()
    before_registration.erase(variant)
    _check(is_equal_approx(gd.product_output_multiplier(before_registration, variant), 1.4),
        "dyed clothing inherits both bonuses even before its first production tick")
    var dyed: Dictionary = gd.get_craft(variant)
    city.city_storage.clear()
    city.city_quality_detail.clear()
    city.add_to_storage("wool", 20, "common")
    city.add_to_storage("ochre", 10, "common")
    var container = load("res://scripts/craft_container.gd").new(dyed)
    var result: Dictionary = container.tick(float(dyed.get("time", 1)), true, "best", 1.0, multipliers)
    var output := 0
    for release in result.get("releases", []):
        if str(release.get("pid", "")) == variant:
            output += int(release.get("amount", 0))
    _check(bool(result.get("completed", false)) and output == 14, "dyed clothing actually produces 40 percent more")

    # The branded recipe is a real production chain and its generated result
    # inherits both specializations before the variant is materialised.
    var brand_variant: String = gd.make_generated_id("branded_wool_clothes", "ochre")
    _check(is_equal_approx(gd.product_output_multiplier(multipliers, brand_variant), 1.4),
        "dyed branded clothes inherit both bonuses")
    var brand_recipe: Dictionary = gd.get_craft(brand_variant)
    city.city_storage.clear()
    city.city_quality_detail.clear()
    city.add_to_storage("cashmere", 20, "common")
    city.add_to_storage("ochre", 10, "common")
    var brand_container = load("res://scripts/craft_container.gd").new(brand_recipe)
    var brand_result: Dictionary = brand_container.tick(float(brand_recipe.get("time", 1)), true, "best", 1.0, multipliers)
    var brand_output := 0
    for release in brand_result.get("releases", []):
        if str(release.get("pid", "")) == brand_variant:
            brand_output += int(release.get("amount", 0))
    _check(bool(brand_result.get("completed", false)) and brand_output == 14,
        "branded dyed clothes consume cashmere and produce 40 percent more")

    var locale := TranslationServer.get_locale()
    TranslationServer.set_locale("ru")
    var named := str(TranslationServer.translate('Cloth "<city_name>"', "resources.name"))
    city.city_name = "Тестоград"
    _check(gd.resolve_display_tags(named) == 'Ткань "Тестоград"', "linen prestige carries the city name")
    city.city_name = ""
    _check(gd.resolve_display_tags(named) == "Ткань", "an unnamed city leaves no empty quotes")
    TranslationServer.set_locale(locale)

    main_map.queue_free()
    _finish()

func _sell(trade: Node, pid: String, amount: int) -> Dictionary:
    return trade.submit_order({"town_id": "textile_test", "side": "buy",
        "product_id": pid, "amount": amount, "unit_price": 1, "permanent": false})

func _finish() -> void:
    WATCHDOG.report_skipped()
    print("TEXTILE SPECIALIZATIONS TEST FAILED" if _failed else "TEXTILE SPECIALIZATIONS TEST OK")
    quit(1 if _failed else 0)

func _check(condition: bool, message: String) -> void:
    if not condition:
        _failed = true
        push_error("ASSERT: " + message)
        print("ASSERT FAILED: ", message)
