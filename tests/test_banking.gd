# Headless test of the Banking technology and its treasury bonuses:
#   godot --headless --path . --script res://tests/test_banking.gd
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")

func _initialize() -> void:
    WATCHDOG.arm(self)
    _run()

func _run() -> void:
    var state := {"failed": false}
    get_root().get_node("SaveManager").new_game()
    var city = get_root().get_node("CityData")
    var gdata = get_root().get_node("GameData")

    var banking: Dictionary = {}
    for tech in gdata.technologies:
        if str(tech.get("id", "")) == "banking":
            banking = tech
            break
    check(not banking.is_empty(), "the technology \"banking\" must exist", state)
    check(str(banking.get("name", "")) == "Banking", "the technology name must be Banking", state)
    check(str(banking.get("era", "")) == "antiquity", "Banking must belong to Antiquity", state)
    check(banking.get("prerequisites", []) == [["taxation", "coinage"]],
            "Banking must require both Taxation and Coinage", state)
    var description := str(banking.get("description", ""))
    check(description.contains("Tax income: +10%")
            and description.contains("Internal-market trade income: +10%")
            and description.contains("External-market trade income: +10%"),
            "the description must name all three 10% bonuses", state)
    var flavor := str(banking.get("flavor", "")).to_lower()
    check(flavor.contains("banking-like practices")
            and flavor.contains("ancient near east")
            and flavor.contains("mesopotamian temples")
            and flavor.contains("trapezitai")
            and flavor.contains("argentarii")
            and flavor.contains("śreṇi")
            and flavor.contains("tang china")
            and flavor.contains("guifang")
            and flavor.contains("feiqian")
            and flavor.contains("not modern banks"),
            "the flavor must mention distinct financial parallels across these regions", state)

    var modifier_values: Dictionary = {}
    var modifier_names: Dictionary = {}
    for modifier in gdata.modifiers.get("tech_modifiers", []):
        if str(modifier.get("tech_id", "")) != "banking":
            continue
        check(str(modifier.get("icon", "")) == "banking.png",
                "each Banking effect must use the Banking icon", state)
        for entry in modifier.get("modifiers", []):
            var target := str(entry.get("target", ""))
            modifier_values[target] = float(entry.get("value", 0.0))
            modifier_names[str(modifier.get("name", ""))] = true
    var tax_modifier_value := float(modifier_values.get("tax_income", 0.0))
    var internal_modifier_value := float(modifier_values.get("internal_market_trade_income", 0.0))
    var external_modifier_value := float(modifier_values.get("external_market_trade_income", 0.0))
    check(modifier_values.size() == 3
            and is_equal_approx(tax_modifier_value, 10.0)
            and is_equal_approx(internal_modifier_value, 10.0)
            and is_equal_approx(external_modifier_value, 10.0),
            "the modifier data must define all three 10% income targets", state)
    check(modifier_names.has("Tax income: +10%")
            and modifier_names.has("Internal-market trade income: +10%")
            and modifier_names.has("External-market trade income: +10%"),
            "all three effects must be named in the technology effects", state)

    city.total_population = 10
    city.tax_collector_share = 0.0
    if not city.is_tech_unlocked("taxation"):
        city.unlocked_technologies.append("taxation")
    if not city.is_tech_unlocked("coinage"):
        city.unlocked_technologies.append("coinage")
    var tax_without_banking: int = city.get_tax_income_per_tick()
    check(tax_without_banking == city.get_base_tax_per_citizen() * city.total_population,
            "Taxation without Banking must pay the base poll tax", state)
    var internal_price_without_banking: int = city.get_internal_market_price("silver", "common")
    var internal_income_without_banking: int = city.get_internal_market_income(
            "silver", {"common": 3})
    var external_multiplier_without_banking: float = \
            city.get_trade_sell_price_multiplier("silver_jewelry")

    check(not city.is_tech_unlocked("banking"), "a new city must not start with Banking", state)
    city.unlocked_technologies.append("banking")

    var expected_tax: int = int(round(float(tax_without_banking) * 1.1))
    check(city.get_tax_income_per_tick() == expected_tax,
            "Banking must raise poll-tax income by 10%", state)
    city.treasury = 0
    check(city.collect_taxes() == expected_tax and city.treasury == expected_tax,
            "the collected tax must include Banking's bonus", state)
    check(is_equal_approx(city.get_tax_income_technology_multiplier(), 1.1),
            "the tax breakdown must use the researched technology multiplier", state)
    var worker_manager = load("res://scripts/worker_manager.gd").new()
    var tax_breakdown: Dictionary = {}
    worker_manager._fill_tax_income(tax_breakdown)
    var tax_label: String = str(tax_breakdown.get(city.TAX_INCOME_TYPE, {})
            .get(city.TREASURY_FLAT_TYPE_KEY, {}).get("label", ""))
    check(tax_label.contains(" × 1.10 from researched technologies"),
            "the tax tooltip must explain the Banking multiplier", state)
    worker_manager.free()

    var internal_price_with_banking: int = city.get_internal_market_price("silver", "common")
    var expected_internal_price: int = int(round(float(internal_price_without_banking) * 1.1))
    check(internal_price_with_banking == expected_internal_price,
            "Banking must raise the internal-market price by 10%", state)
    check(internal_income_without_banking == internal_price_without_banking * 3,
            "the internal-market baseline must price every consumed unit", state)
    check(city.get_internal_market_income("silver", {"common": 3})
            == internal_price_with_banking * 3,
            "the actual internal-market income must use Banking's higher price", state)

    var external_multiplier_with_banking: float = \
            city.get_trade_sell_price_multiplier("silver_jewelry")
    check(is_equal_approx(external_multiplier_with_banking,
            external_multiplier_without_banking * 1.1),
            "Banking must raise external-market sale prices by 10%", state)

    var banking_effect_count := 0
    var banking_effect_names: Dictionary = {}
    for effect in city.get_city_effects():
        if str(effect.get("icon", "")) != "banking.png":
            continue
        banking_effect_count += 1
        banking_effect_names[str(effect.get("name", ""))] = true
    check(banking_effect_count == 3
            and banking_effect_names.has("Tax income: +10%")
            and banking_effect_names.has("Internal-market trade income: +10%")
            and banking_effect_names.has("External-market trade income: +10%"),
            "the city effects must show all three researched Banking bonuses", state)

    _test_external_sale(city, gdata, state)

    if state["failed"]:
        print("BANKING TEST FAILED")
        quit(1)
    else:
        print("BANKING TEST OK")
        quit(0)

func _test_external_sale(city, gdata, state: Dictionary) -> void:
    var product := "silver_jewelry"
    var amount := 2
    var base_unit_price := int(round(float(gdata.get_price(product))))
    var expected_unit_price := int(round(float(gdata.get_price(product))
            * city.get_trade_sell_price_multiplier(product)))
    check(expected_unit_price > base_unit_price,
            "Banking must raise the selected external-sale price", state)
    var town := {
        "id": "banking_test_town",
        "name": "Banking Test Town",
        "row": 1,
        "col": 1,
        "treasury": 10000,
        "buy_pool": [product],
    }
    var town_manager = load("res://scripts/town_manager.gd").new()
    town_manager.towns = [town]
    var trade_manager = load("res://scripts/town_trade_manager.gd").new()
    trade_manager.initialize(town_manager, null)

    city.city_storage.clear()
    city.city_quality_detail.clear()
    city.treasury = 100
    city.treasury_income_accum.clear()
    city.add_to_storage(product, amount, "common")
    var order := {
        "town_id": "banking_test_town",
        "town_name": "Banking Test Town",
        "row": 1,
        "col": 1,
        "side": "buy",
        "product_id": product,
        "product_name": gdata.get_product_name(product),
        "amount": amount,
        "permanent": false,
        "unit_price": 0,
    }
    var town_before: int = town_manager.get_town_treasury(town)
    var city_before: int = city.treasury
    var result: Dictionary = trade_manager.submit_order(order)
    var expected_total: int = amount * expected_unit_price
    check(bool(result.get("ok", false)),
            "the city must be able to sell goods at the Banking price: %s"
                    % str(result.get("message", "")), state)
    check(city.treasury == city_before + expected_total,
            "the external sale must credit the Banking price to the city", state)
    check(town_manager.get_town_treasury(town) == town_before - expected_total,
            "the town must pay the Banking price", state)
    check(int(city.treasury_income_accum.get(gdata.SRC_TOWN_TRADE, 0)) == expected_total,
            "the external-market income record must include the Banking bonus", state)

    trade_manager.free()
    town_manager.free()

func check(condition: bool, message: String, state: Dictionary) -> void:
    if condition:
        return
    push_error("ASSERT: " + message)
    print("ASSERT FAILED: " + message)
    state["failed"] = true
