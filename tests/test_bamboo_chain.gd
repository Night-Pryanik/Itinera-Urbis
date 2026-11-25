# Headless regression test for bamboo cultivation and its crafting uses.
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

    var grove: Dictionary = gd.raw_resources.get("bamboo_grove", {})
    _check(not grove.is_empty(), "bamboo grove exists")
    _check(grove.get("improved_by", "") == "plantation", "plantations harvest bamboo")
    _check(grove.get("tech_required", "") == "plantations", "cultivation requires plantations")
    _check(float(grove.get("produces", {}).get("bamboo", 0)) > 0, "the grove yields bamboo")
    _check(not gd.products.get("bamboo", {}).is_empty(), "bamboo is a product")
    _check(root.get_node("IconRegistry").get_texture("bamboo.png") != null, "bamboo icon loads")

    var generator = load("res://scripts/map_generator.gd").new()
    var eligible := [[{"terrain": "prairie_plain", "cover": "none", "climate": "prairie"}]]
    generator.place_all_resources(eligible, {"bamboo_grove": grove}, 1, 1, -2, -2)
    _check(eligible[0][0].get("resource", "") == "bamboo_grove", "bamboo spawns on an eligible hex")
    var cold := [[{"terrain": "boreal_plain", "cover": "none", "climate": "boreal_wet"}]]
    generator.place_all_resources(cold, {"bamboo_grove": grove}, 1, 1, -2, -2)
    _check(cold[0][0].get("resource", "") != "bamboo_grove", "bamboo does not spawn in boreal climate")
    generator.free()

    _check((gd.product_groups.get("paper_fibers", []) as Array).has("bamboo"), "paper fibers include bamboo")
    var paper: Dictionary = gd.find_craft("paper")
    var furniture: Dictionary = gd.find_craft("furniture")
    _check(not paper.is_empty() and not furniture.is_empty(), "both recipes exist")
    if not paper.is_empty() and not furniture.is_empty():
        _test_cycle(city, paper, {"bamboo": 10, "lime": 10}, "paper", "paper from bamboo")
        _test_cycle(city, paper, {"hemp": 10, "lime": 10}, "paper", "paper from hemp")
        _test_cycle(city, paper, {"bamboo": 10}, "paper", "paper still needs lime", false)
        _test_cycle(city, furniture, {"bamboo": 20}, "furniture", "furniture from bamboo")
        _test_cycle(city, furniture, {"wood": 20}, "furniture", "furniture from wood")

    WATCHDOG.report_skipped()
    print("BAMBOO CHAIN TEST FAILED" if _failed else "BAMBOO CHAIN TEST OK")
    quit(1 if _failed else 0)

func _test_cycle(city: Node, recipe: Dictionary, inputs: Dictionary, output: String, label: String, should_complete: bool = true) -> void:
    city.city_storage.clear()
    for pid in inputs:
        city.add_to_storage(pid, inputs[pid], "common")
    var container = load("res://scripts/craft_container.gd").new(recipe)
    var result: Dictionary = container.tick(float(recipe.get("time", 1)), true, "best")
    _check(bool(result.get("completed", false)) == should_complete, label + " completion")
    var quantity := 0
    for release in result.get("releases", []):
        if str(release.get("pid", "")) == output:
            quantity += int(release.get("amount", 0))
    if should_complete:
        _check(quantity == int(recipe.get("result", {}).get(output, 0)), label + " output")
        for pid in inputs:
            _check(int(city.get_storage_amount(pid)) == 0, label + " consumes " + str(pid))
    else:
        _check(quantity == 0, label + " produces nothing")

func _check(condition: bool, message: String) -> void:
    if not condition:
        _failed = true
        push_error("ASSERT: " + message)
        print("ASSERT FAILED: ", message)
