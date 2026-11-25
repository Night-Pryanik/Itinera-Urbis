# Headless regression test for the pen shell, its byssus and the sea silk woven from it.
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

    var shells: Dictionary = gd.raw_resources.get("pen_shell", {})
    _check(not shells.is_empty(), "pen shells exist")
    _check(shells.get("allowed_terrain", []) == ["shallow_sea"], "pen shells live in the shallow sea only")
    _check(shells.get("improved_by", "") == "fishing_boats", "fishing boats gather pen shells")
    _check(shells.get("tech_required", "") == "fishing", "gathering requires fishing")
    _check(float(shells.get("produces", {}).get("byssus", 0)) > 0, "pen shells yield byssus")

    var registry = root.get_node("IconRegistry")
    for pid in ["byssus", "sea_silk", "sea_silk_clothes"]:
        var product: Dictionary = gd.products.get(pid, {})
        _check(not product.is_empty(), pid + " is a product")
        _check(registry.get_texture(str(product.get("icon", ""))) != null, pid + " icon loads")
    _check(gd.products.get("sea_silk_clothes", {}).get("category", "") == "clothes", "sea silk clothes are clothes")
    _check(float(gd.products.get("sea_silk", {}).get("price", 0)) > float(gd.products.get("byssus", {}).get("price", 0)),
        "sea silk is worth more than byssus")
    _check(float(gd.products.get("sea_silk_clothes", {}).get("price", 0)) > float(gd.products.get("sea_silk", {}).get("price", 0)),
        "sea silk clothes are worth more than sea silk")

    var clothes: Array = gd.product_groups.get("clothes", [])
    _check(clothes.has("sea_silk_clothes"), "citizens wear sea silk clothes")
    _check(not clothes.is_empty() and clothes.back() == "sea_silk_clothes", "sea silk clothes are worn last, as the costliest")

    var generator = load("res://scripts/map_generator.gd").new()
    var sea := [[{"terrain": "shallow_sea", "cover": "none"}]]
    generator.place_all_resources(sea, {"pen_shell": shells}, 1, 1, -2, -2)
    _check(sea[0][0].get("resource", "") == "pen_shell", "pen shells spawn on the shallow sea")
    var land := [[{"terrain": "prairie_plain", "cover": "none", "climate": "prairie"}]]
    generator.place_all_resources(land, {"pen_shell": shells}, 1, 1, -2, -2)
    _check(land[0][0].get("resource", "") != "pen_shell", "pen shells do not spawn on land")
    generator.free()

    var sea_silk: Dictionary = gd.find_craft("sea_silk")
    var garments: Dictionary = gd.find_craft("sea_silk_clothes")
    _check(not sea_silk.is_empty() and not garments.is_empty(), "both recipes exist")
    if not sea_silk.is_empty() and not garments.is_empty():
        for recipe in [sea_silk, garments]:
            _check((recipe.get("produced_in", []) as Array).has("weaver_house"), recipe["id"] + " is woven in the weaver's house")
            _check((recipe.get("produced_in", []) as Array).has("weaver_workshop"), recipe["id"] + " is woven in the weaver's workshop")
            _check(recipe.get("unlock_tech", "") == "weaving", recipe["id"] + " unlocks with weaving")
        _test_cycle(city, sea_silk, {"byssus": 20}, "sea_silk", "sea silk from byssus")
        _test_cycle(city, sea_silk, {"byssus": 10}, "sea_silk", "sea silk needs a full batch of byssus", false)
        _test_cycle(city, garments, {"sea_silk": 20}, "sea_silk_clothes", "clothes from sea silk")
        _test_cycle(city, garments, {"silk": 20}, "sea_silk_clothes", "sea silk clothes are not woven from silk", false)

    WATCHDOG.report_skipped()
    print("SEA SILK CHAIN TEST FAILED" if _failed else "SEA SILK CHAIN TEST OK")
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
