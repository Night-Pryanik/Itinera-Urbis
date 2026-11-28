# Headless regression test for the flint glass chain.
#
# Flint glass is the lead-fluxed glass that chemistry unlocks: the glassmaker fuses
# it in the glassmaker's house, and the optician grinds it in the optical workshop
# into the prism — the scholar's finest optical aid and the top tier of the
# optical instruments. The test follows the whole chain: product, recipe, cycle,
# group and the scholar's tiered bonus.
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")

var _failed := false

func _initialize() -> void:
    WATCHDOG.arm(self)
    call_deferred("_run")

func _run() -> void:
    var gd = root.get_node("GameData")
    gd.load_all_data()
    var city = root.get_node("CityData")
    city.setup()

    _test_chemistry(gd)
    _test_flint_product(gd)
    _test_flint_recipe(gd, city)
    _test_prism_product(gd)
    _test_prism_recipe(gd, city)
    _test_group(gd)
    _test_consumption(gd, city)

    WATCHDOG.report_skipped()
    print("FLINT GLASS TEST FAILED" if _failed else "FLINT GLASS TEST OK")
    quit(1 if _failed else 0)

func _test_chemistry(gd: Node) -> void:
    var chemistry := _record(gd.technologies, "chemistry")
    _check(not chemistry.is_empty(), "chemistry is a technology")
    if chemistry.is_empty():
        return
    _check(str(chemistry.get("era", "")) == "renaissance", "chemistry belongs to the renaissance era")
    _check(str(chemistry.get("icon", "")) != "", "chemistry names an icon")

func _test_flint_product(gd: Node) -> void:
    var product: Dictionary = gd.products.get("flint_glass", {})
    _check(not product.is_empty(), "product exists: flint_glass")
    if product.is_empty():
        return
    _check(str(product.get("type", "")) == "product", "flint glass is a product")
    _check(str(product.get("category", "")) == "material", "flint glass is a material, not a good")
    _check(str(product.get("unlock_tech", "")) == "chemistry",
        "flint glass is opened by chemistry")
    _check(int(product.get("price", 0)) > 0, "flint glass has a price")
    _check(str(product.get("icon", "")) != "", "flint glass names an icon")

func _test_flint_recipe(gd: Node, city: Node) -> void:
    var recipe: Dictionary = gd.find_craft("flint_glass")
    _check(not recipe.is_empty(), "recipe exists: flint_glass")
    if recipe.is_empty():
        return
    _check(recipe.get("produced_in", []) == ["glassmaker_house"],
        "flint glass is fused in the glassmaker's house")
    _check(str(recipe.get("unlock_tech", "")) == "chemistry", "the flint glass recipe keeps its gate")
    _check(int(recipe.get("result", {}).get("flint_glass", 0)) == 10,
        "the recipe yields ten blocks of flint glass")
    var ids := _ingredient_ids(recipe.get("resources", {}))
    _check(ids.has("quartz_sand") and ids.has("lead") and ids.has("potash"),
        "flint glass is fused from sand, lead and potash")

    _test_cycle(city, recipe, { "quartz_sand": 20, "lead": 10, "potash": 10 }, "flint_glass")

func _test_prism_product(gd: Node) -> void:
    var product: Dictionary = gd.products.get("prism", {})
    _check(not product.is_empty(), "product exists: prism")
    if product.is_empty():
        return
    _check(str(product.get("type", "")) == "product", "the prism is a product")
    _check(str(product.get("category", "")) == "tools", "the prism is a tool, like the lenses")
    _check(str(product.get("unlock_tech", "")) == "chemistry",
        "the prism needs the flint glass that chemistry unlocks")
    _check(int(product.get("price", 0)) > 0, "the prism has a price")
    _check(str(product.get("icon", "")) != "", "the prism names an icon")

func _test_prism_recipe(gd: Node, city: Node) -> void:
    var recipe: Dictionary = gd.find_craft("prism")
    _check(not recipe.is_empty(), "recipe exists: prism")
    if recipe.is_empty():
        return
    _check(recipe.get("produced_in", []) == ["optical_workshop"],
        "the prism is ground in the optical workshop")
    _check(str(recipe.get("unlock_tech", "")) == "chemistry", "the prism recipe keeps its gate")
    _check(int(recipe.get("result", {}).get("prism", 0)) == 10, "the recipe yields ten prisms")
    var ids := _ingredient_ids(recipe.get("resources", {}))
    _check(ids.has("flint_glass"), "the prism is ground from flint glass, not glassware")
    _check(not ids.has("glassware"), "the prism does not consume ordinary glassware")

    _test_cycle(city, recipe, { "flint_glass": 10 }, "prism")

func _test_group(gd: Node) -> void:
    var group: Array = gd.product_groups.get("optical_instruments", [])
    _check(group == ["magnifying_glass", "spectacles", "prism"],
        "the plain magnifier comes first and the flint-glass prism last")

func _test_consumption(gd: Node, city: Node) -> void:
    var rule := _find_rule(gd.get_profession_consumption("scientist"), "@optical_instruments")
    _check(not rule.is_empty(), "the scholar consumes optical instruments")
    if rule.is_empty():
        return

    var members: Array = rule.get("group_members", [])
    _check("prism" in members, "the prism is a member of the optical instruments group")
    _check(absf(gd.get_entry_member_bonus(rule, "prism") - 0.45) < 0.0001,
        "the prism grants the scholar +45%")
    _check(absf(gd.get_entry_member_interval(rule, "prism") - 25.0) < 0.0001,
        "the prism outlasts the lenses")

    # The prism is the top tier: the best bonus, so it is drawn first.
    var ordered: Array = gd.get_entry_members_ordered_by_tier(rule)
    _check(not ordered.is_empty() and str(ordered[0]) == "prism",
        "the prism is the top tier of the optical instruments")

    # With the prism in stock the scholar draws its bonus; the optical and metal
    # groups still add up.
    var wm = load("res://scripts/worker_manager.gd").new()
    root.add_child(wm)
    city.city_storage.clear()
    city.add_to_storage("prism", 10, "common")
    _check(absf(wm._entry_effective_bonus(rule) - 0.45) < 0.0001,
        "a stocked prism grants the optical group +45%%, got +%f" % wm._entry_effective_bonus(rule))

    city.city_storage.clear()
    city.add_to_storage("copper_precision_instruments", 10, "common")
    city.add_to_storage("prism", 10, "common")
    var precision := _find_rule(gd.get_profession_consumption("scientist"), "@precision_instruments")
    var stacked: float = wm._aggregate_production_bonus([precision, rule])
    _check(absf(stacked - 0.55) < 0.0001,
        "metal and optical instruments still stack (+0.10 + +0.45), got +%f" % stacked)

func _test_cycle(city: Node, recipe: Dictionary, inputs: Dictionary, output: String) -> void:
    city.city_storage.clear()
    for pid in inputs:
        city.add_to_storage(pid, inputs[pid], "common")
    var container = load("res://scripts/craft_container.gd").new(recipe)
    var result: Dictionary = container.tick(float(recipe.get("time", 1)), true, "best")
    _check(bool(result.get("completed", false)), output + " cycle completes")
    var quantity := 0
    for release in result.get("releases", []):
        if str(release.get("pid", "")) == output:
            quantity += int(release.get("amount", 0))
    _check(quantity == int(recipe.get("result", {}).get(output, 0)), output + " output")
    for pid in inputs:
        _check(int(city.get_storage_amount(pid)) == 0, output + " consumes " + str(pid))

func _ingredient_ids(raw) -> Array:
    var ids: Array = []
    if raw is Dictionary:
        return raw.keys()
    if raw is Array:
        for term in raw:
            if term is Dictionary:
                ids.append_array(term.keys())
            elif term is Array:
                for variant in term:
                    if variant is Dictionary:
                        ids.append_array(variant.keys())
    return ids

func _find_rule(rules: Array, key: String) -> Dictionary:
    for entry in rules:
        if str(entry.get("display_key", "")) == key:
            return entry
    return {}

func _record(records: Array, id: String) -> Dictionary:
    for record in records:
        if str(record.get("id", "")) == id:
            return record
    return {}

func _check(condition: bool, message: String) -> void:
    if not condition:
        _failed = true
        push_error("ASSERT: " + message)
        print("ASSERT FAILED: ", message)
