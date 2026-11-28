# Both textile fame ladders, town sales and their shared clothing bonus.
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")

var _failed := false
var _town_economy = null

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
    # Load after the autoloads are ready, as town_economy references GameData.
    _town_economy = load("res://scripts/town_economy.gd")
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
    var pools: Dictionary = _town_economy.build_pools("textile_test", [])
    var local: Dictionary = _town_economy.build_pools("textile_local", ["flax", "wool"])
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
    var byssus_recipe: Dictionary = gd.find_craft("linen_byssus")
    var byssus_inputs: Dictionary = byssus_recipe.get("resources", {})
    _check(byssus_inputs.size() == 1 and int(byssus_inputs.get("@textile_crops", 0)) == 20,
        "byssus uses only textile crops")
    for fiber in gd.product_groups.get("textile_crops", []):
        _check(_town_economy.is_recipe_ready(byssus_recipe, {fiber: true}), "byssus accepts " + str(fiber))
    # These rope fibers are not textile crops; overlapping fibers such as hemp
    # remain valid because they are explicitly part of the textile group.
    for fiber in ["sisal", "papyrus", "velvetleaf", "coir"]:
        _check(not _town_economy.is_recipe_ready(byssus_recipe, {fiber: true}), "byssus rejects rope-only fiber " + fiber)
    var cashmere_inputs: Dictionary = gd.find_craft("cashmere").get("resources", {})
    _check(cashmere_inputs.size() == 1 and int(cashmere_inputs.get("wool", 0)) == 20,
        "cashmere uses wool directly")

    var town := {"id": "textile_test", "name": "Testville", "treasury": 1000000,
        "buy_pool": pools.get("buy_pool", [])}
    main_map.town_manager.towns.append(town)
    for line in [["fabric_clothes", "linen_byssus", "fabric_specialization", "branded_fabric_clothes", "fabric_clothing"],
                 ["wool_clothes", "cashmere", "wool_specialization", "branded_wool_clothes", "wool_clothing"]]:
        var pid: String = line[0]
        var prestige: String = line[1]
        var spec_id: String = line[2]
        var branded: String = line[3]
        var garment_recipe: Dictionary = gd.find_craft(branded)
        var product: Dictionary = _fame_group(gd, line[4])
        _check(gd.product_groups.get(str(product.get("product_group", "")), []) == [pid, branded],
            pid + " group includes only the ordinary and branded garment")
        _check(not gd.products[pid].has("challenge"), pid + " does not own the group ladder")
        _check(fame.challenge_id(product, product["reputation"]) == pid + "_challenge", pid + " reputation id is preserved")
        _check(fame.challenge_id(product, product["brand"]) == pid + "_challenge", pid + " brand id is preserved")
        var recipe: Dictionary = gd.find_craft(prestige)
        var brand_threshold := int(product["brand"]["threshold"])
        var challenge_threshold := int(product["challenge"]["threshold"])
        _check(not recipe.is_empty(), prestige + " recipe exists")
        _check(str(gd.products[prestige].get("brand_of", "")) == pid, prestige + " belongs to its own ladder")
        _check(not city.is_craft_available(recipe), prestige + " starts locked")
        _check(not city.is_craft_available(garment_recipe), branded + " starts locked")
        _check(garment_recipe.get("resources", {}).has(prestige), branded + " uses the prestige material")
        _check(not city.is_specialization_available(city.get_specialization(spec_id)), spec_id + " starts locked")
        _check(fame.tier_counter(product, product["challenge"]) == 0, pid + " starts independently of the other line")
        fame.record_sale(prestige, {"exceptional": 50})
        fame.record_production(branded, 50, "exceptional")
        _check(fame.tier_counter(product, product["challenge"]) == 0, "materials and production do not count as garment sales")
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
        _check(is_equal_approx(fame.get_fame_trade_price_share(branded), 0.10), branded + " receives group reputation")
        city.add_to_storage(branded, 1, "fine")
        _check(bool(_sell(trade, branded, 1).get("ok", false)), branded + " fine sale succeeds")
        _check(fame.tier_counter(product, product["challenge"]) == brand_threshold, branded + " below exceptional does not count")
        city.add_to_storage(branded, 200, "exceptional")
        _check(bool(_sell(trade, branded, 200).get("ok", false)), branded + " exceptional sale succeeds")
        _check(fame.tier_counter(product, product["challenge"]) == brand_threshold + 200, branded + " counts toward challenge")
        var dyed_id: String = gd.make_generated_id(pid, "woad")
        gd.materialise_generated(dyed_id)
        city.add_to_storage(dyed_id, 1, gd.make_quality_key("exceptional", "common"))
        _check(bool(_sell(trade, dyed_id, 1).get("ok", false)), pid + " dyed ordinary sale succeeds")
        var dyed_brand: String = gd.make_generated_id(branded, "woad")
        gd.materialise_generated(dyed_brand)
        var remaining := challenge_threshold - brand_threshold - 201
        city.add_to_storage(dyed_brand, remaining - 1, gd.make_quality_key("exceptional", "common"))
        _check(bool(_sell(trade, dyed_brand, remaining - 1).get("ok", false)), pid + " dyed branded sale succeeds")
        _check(fame.tier_counter(product, product["challenge"]) == challenge_threshold - 1, "dyed brand counts once")
        _check(not fame.is_challenge_completed(str(product["challenge"]["id"])), pid + " challenge waits for threshold")
        city.add_to_storage(dyed_brand, 1, gd.make_quality_key("exceptional", "common"))
        _check(bool(_sell(trade, dyed_brand, 1).get("ok", false)), pid + " final dyed branded sale succeeds")
        _check(fame.is_challenge_completed(str(product["challenge"]["id"])), pid + " challenge is complete")
        _check(city.is_specialization_available(city.get_specialization(spec_id)), spec_id + " is independently available")
        _check(is_zero_approx(fame.get_fame_trade_price_share(prestige)), prestige + " is not in the clothing fame group")

    var saved: Dictionary = fame.serialize()
    fame.deserialize(saved)
    for group_id in ["fabric_clothing", "wool_clothing"]:
        var product: Dictionary = _fame_group(gd, group_id)
        _check(fame.tier_counter(product, product["challenge"]) == 1000, group_id + " sale progress survives save")
        _check(fame.is_challenge_completed(str(product["challenge"]["id"])), group_id + " completion survives save")
        for pid in gd.product_groups[product["product_group"]]:
            _check(is_equal_approx(fame.get_fame_trade_price_share(pid), 0.10), pid + " reputation survives save")
    _check(city.get_pending_specialization_picks() == 2, "both challenges grant their own pick")
    _check(city.choose_specialization("wool_specialization"), "wool specialization can be chosen")
    _check_textile_bonuses(city, gd, 0.20, 0.15)
    _check(city.choose_specialization("fabric_specialization"), "fabric specialization can also be chosen")
    _check_textile_bonuses(city, gd, 0.40, 0.30)
    # Either branch alone must cover the same clothing basket, not its materials.
    city.chosen_specialization_ids.erase("wool_specialization")
    _check_textile_bonuses(city, gd, 0.20, 0.15)
    city.chosen_specialization_ids.append("wool_specialization")
    var multipliers: Dictionary = city.get_production_product_multipliers()

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
    _check(is_equal_approx(city.get_specialization_product_share("trade_sell_price", brand_variant), 0.30),
        "dyed branded clothing receives both sale bonuses")
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
    _check(gd.resolve_display_tags(named) == 'Ткань «Тестоград»', "linen prestige carries the city name")
    city.city_name = ""
    _check(gd.resolve_display_tags(named) == "Ткань", "an unnamed city leaves no empty quotes")
    TranslationServer.set_locale(locale)

    main_map.queue_free()
    _finish()

func _fame_group(gd: Node, id: String) -> Dictionary:
    for group in gd.fame_groups:
        if str(group.get("id", "")) == id:
            return group
    _check(false, "missing fame group: " + id)
    return {}

# Both branches cover all clothing for production and town prices, never its inputs.
func _check_textile_bonuses(city: Node, gd: Node, production: float, price: float) -> void:
    var multipliers: Dictionary = city.get_production_product_multipliers()
    for pid in gd.product_groups.get("clothes", []):
        _check(is_equal_approx(float(multipliers.get(pid, 1.0)), 1.0 + production),
            str(pid) + " receives the clothing production bonus")
        _check(is_equal_approx(city.get_specialization_product_share("trade_sell_price", str(pid)), price),
            str(pid) + " receives the clothing sale bonus")
    for pid in ["flax", "linen_byssus", "wool", "cashmere", "carpet"]:
        _check(is_equal_approx(float(multipliers.get(pid, 1.0)), 1.0), str(pid) + " has no clothing production bonus")
        _check(is_equal_approx(city.get_specialization_product_share("trade_sell_price", pid), 0.0),
            str(pid) + " has no clothing sale bonus")

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
