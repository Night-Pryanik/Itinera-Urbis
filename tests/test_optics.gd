# Headless regression test for the optics technology and the scholar's lenses.
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")

const OPTICAL := [
    { "product": "magnifying_glass", "price": 40, "time": 12.0,
      "inputs": { "quartz_sand": 20, "soda": 10, "pumice": 10 },
      "alt_inputs": { "quartz_sand": 20, "potash": 10, "pumice": 10 } },
    { "product": "spectacles", "price": 70, "time": 16.0,
      "inputs": { "quartz_sand": 20, "potash": 10, "lead": 10, "pumice": 10 } },
]

var _failed := false

func _initialize() -> void:
    WATCHDOG.arm(self)
    call_deferred("_run")

func _run() -> void:
    var gd = root.get_node("GameData")
    gd.load_all_data()
    var city = root.get_node("CityData")
    city.setup()

    _test_technology(gd)
    for item in OPTICAL:
        _test_product(gd, item)
        _test_recipe(gd, city, item)
    _test_group(gd)
    _test_consumption(gd)

    var wm = load("res://scripts/worker_manager.gd").new()
    root.add_child(wm)
    _test_stacking(gd, city, wm)

    WATCHDOG.report_skipped()
    print("OPTICS TEST FAILED" if _failed else "OPTICS TEST OK")
    quit(1 if _failed else 0)

func _test_technology(gd: Node) -> void:
    var tech := _record(gd.technologies, "optics")
    _check(not tech.is_empty(), "optics is a technology")
    if tech.is_empty():
        return
    _check(str(tech.get("era", "")) == "antiquity", "optics belongs to the antiquity era")
    _check(float(tech.get("science_cost", 0)) == 5.0, "optics keeps its science cost")
    _check(_option_has(tech, ["glassmaking", "precision_instruments"]),
        "lens grinding needs glassmaking and precision instruments")
    _check((tech.get("unlock_effects", []) as Array).is_empty(),
        "the knowledge of optics alone grants no scholar bonus")

    for entry in gd.modifiers.get("tech_modifiers", []):
        _check(str(entry.get("tech_id", "")) != "optics",
            "optics has no free scholar multiplier; the lenses carry the bonus")

func _test_product(gd: Node, item: Dictionary) -> void:
    var pid := str(item["product"])
    var product: Dictionary = gd.products.get(pid, {})
    _check(not product.is_empty(), "product exists: " + pid)
    if product.is_empty():
        return
    _check(str(product.get("type", "")) == "product", "the lens is a product: " + pid)
    _check(str(product.get("category", "")) == "tools", "the lens is a tool: " + pid)
    _check(int(product.get("price", 0)) == int(item["price"]), "the lens keeps its price: " + pid)
    _check(str(product.get("unlock_tech", "")) == "optics", "the lens is opened by optics: " + pid)
    _check(str(product.get("icon", "")) != "", "the lens names an icon: " + pid)

func _test_recipe(gd: Node, city: Node, item: Dictionary) -> void:
    var pid := str(item["product"])
    var recipe: Dictionary = gd.find_craft(pid)
    _check(not recipe.is_empty(), "recipe exists: " + pid)
    if recipe.is_empty():
        return
    _check(recipe.get("produced_in", []) == ["glassmaker_house"], "lenses are ground in the glasshouse: " + pid)
    _check(str(recipe.get("unlock_tech", "")) == "optics", "the lens recipe keeps its gate: " + pid)
    _check(float(recipe.get("time", 0)) == float(item["time"]), "the lens keeps its time: " + pid)
    _check(int(recipe.get("result", {}).get(pid, 0)) == 10, "the recipe yields ten lenses: " + pid)
    _check(not _ingredient_ids(recipe.get("resources", {})).has("glassware"),
        "lenses are ground from batch, not from finished vessels: " + pid)

    if item.has("alt_inputs"):
        _check(_has_alkali_alternative(gd, recipe), "soda and potash are alternatives: " + pid)
    for input_set in [item["inputs"], item.get("alt_inputs", item["inputs"])]:
        _test_cycle(city, recipe, input_set, pid)

func _test_group(gd: Node) -> void:
    var group: Array = gd.product_groups.get("optical_instruments", [])
    _check(group == ["magnifying_glass", "spectacles"],
        "the plainer lens comes first and the finer one last")

func _test_consumption(gd: Node) -> void:
    var rule := _find_rule(gd.get_profession_consumption("scientist"), "@optical_instruments")
    _check(not rule.is_empty(), "the scholar consumes optical instruments")
    if rule.is_empty():
        return
    _check(float(rule.get("interval", 0)) == 20.0, "lenses wear out like metal instruments")
    _check(absf(gd.get_entry_member_bonus(rule, "magnifying_glass") - 0.25) < 0.0001,
        "the magnifier grants +25%")
    _check(absf(gd.get_entry_member_bonus(rule, "spectacles") - 0.35) < 0.0001,
        "spectacles grant +35%")

func _test_stacking(gd: Node, city: Node, wm: Node) -> void:
    var precision := _find_rule(gd.get_profession_consumption("scientist"), "@precision_instruments")
    var optical := _find_rule(gd.get_profession_consumption("scientist"), "@optical_instruments")
    _check(not precision.is_empty() and not optical.is_empty(),
        "the scholar has both instrument groups")
    if precision.is_empty() or optical.is_empty():
        return

    city.city_storage.clear()
    city.add_to_storage("copper_precision_instruments", 30, "common")
    city.add_to_storage("magnifying_glass", 30, "common")
    city.add_to_storage("spectacles", 30, "common")
    _check(absf(wm._entry_effective_bonus(optical) - 0.35) < 0.0001,
        "inside the optical group the better lens wins, got +%f" % wm._entry_effective_bonus(optical))
    var stacked: float = wm._aggregate_production_bonus([precision, optical])
    _check(absf(stacked - 0.45) < 0.0001,
        "metal and optical instruments stack (+0.10 + +0.35), got +%f" % stacked)

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

func _has_alkali_alternative(gd: Node, recipe: Dictionary) -> bool:
    for group in gd.parse_craft_resources(recipe.get("resources", {})):
        var ids: Array = []
        for variant in group:
            if variant is Dictionary:
                ids.append(str(variant.get("key", "")))
        if ids.has("soda") and ids.has("potash"):
            return true
    return false

func _find_rule(rules: Array, key: String) -> Dictionary:
    for entry in rules:
        if str(entry.get("display_key", "")) == key:
            return entry
    return {}

func _option_has(tech: Dictionary, ids: Array) -> bool:
    for option in tech.get("prerequisites", []):
        if not option is Array:
            continue
        var matches := true
        for id in ids:
            if not option.has(id):
                matches = false
        if matches:
            return true
    return false

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
