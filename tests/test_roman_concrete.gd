# Headless regression test of the pozzolanic concrete chain and its technology gate.
#   godot --headless --path . --script res://tests/test_roman_concrete.gd
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")
const PRODUCT := "roman_concrete"
const AGGREGATES := ["basalt", "sandstone", "limestone"]

var _failed := false
var _done := false

func _initialize() -> void:
    WATCHDOG.arm(self)

func _process(_delta: float) -> bool:
    if not _done:
        _done = true
        _run()
    return true

func _run() -> void:
    TranslationServer.set_locale("en")
    var gd = root.get_node("GameData")
    gd.load_all_data()
    var city = root.get_node("CityData")
    city.setup()
    city.ignore_tech_requirements = false
    city.food_consumption_enabled = false

    var product: Dictionary = gd.products.get(PRODUCT, {})
    _check(not product.is_empty(), "Roman concrete is a product")
    _check(product.get("category", "") == "construction_material", "concrete is a construction material")
    _check(product.get("unlock_tech", "") == "concrete", "the product requires Concrete")
    _check(float(product.get("price", 0)) > float(gd.products.get("mortar", {}).get("price", 0)),
        "concrete is dearer than ordinary mortar")
    _check(root.get_node("IconRegistry").get_texture(str(product.get("icon", ""))) != null,
        "the concrete product icon loads")

    var recipe: Dictionary = city.get_craft_by_id(PRODUCT)
    _check(not recipe.is_empty(), "the concrete recipe exists")
    _check(recipe.get("produced_in", []) == ["mason_workshop"], "only the mason mixes concrete")
    _check(recipe.get("unlock_tech", "") == "concrete", "the recipe requires Concrete")
    _check(recipe.get("result", {}) == {"roman_concrete": 10}, "one cycle yields ten units of concrete")
    _check(float(recipe.get("time", 0)) > 0, "concrete has a positive cycle time")
    var ingredients: Array = gd.craft_alternatives(recipe)
    _check(ingredients.size() == 3, "lime, pozzolan and aggregate are all mandatory")
    if ingredients.size() == 3:
        _check(ingredients[0] == [{"key": "lime", "amount": 10}], "lime is mandatory")
        _check(ingredients[1] == [{"key": "tuff", "amount": 10}], "tuff supplies the pozzolan")
        var aggregate_ids: Array = []
        for variant in ingredients[2]:
            aggregate_ids.append(str(variant.get("key", "")))
            _check(int(variant.get("amount", 0)) == 10, "each aggregate needs ten units")
        _check(aggregate_ids == AGGREGATES, "ordinary stone alternatives supply aggregate only")
    var mortar: Dictionary = city.get_craft_by_id("mortar")
    _check(mortar.get("resources", {}) == {"lime": 10, "quartz_sand": 10},
        "ordinary lime mortar uses sand, not pozzolan")
    _check(mortar.get("unlock_tech", "") == "limestone_burning", "ordinary mortar keeps its earlier gate")
    _check((gd.product_groups.get("construction_binders", []) as Array).has(PRODUCT),
        "builders can consume prepared concrete")
    _check(not (gd.product_groups.get("processed_construction_materials", []) as Array).has(PRODUCT),
        "prepared concrete does not substitute for stone blocks or bricks in building costs")

    city.unlocked_technologies = ["limestone_burning", "masonry"]
    _check(not city.is_product_available(PRODUCT), "concrete product is locked before Concrete")
    _check(not city.is_craft_available(recipe), "concrete recipe is locked before Concrete")
    _check(city.is_craft_available(mortar), "ordinary mortar is already available")
    city.unlocked_technologies.append("concrete")
    _check(city.is_product_available(PRODUCT), "Concrete unlocks the product")
    _check(city.is_craft_available(recipe), "Concrete unlocks the recipe")
    _check(city.can_craft_in(PRODUCT, "mason_workshop"), "the mason accepts the concrete recipe")
    _check(not city.can_craft_in(PRODUCT, "lime_kilns"), "a kiln does not mix concrete")
    _test_production(city, recipe)

    print("ROMAN CONCRETE TEST FAILED" if _failed else "ROMAN CONCRETE TEST OK")
    quit(1 if _failed else 0)

func _test_production(city: Node, recipe: Dictionary) -> void:
    var main_map := Node.new()
    main_map.name = "MainMap"
    root.add_child(main_map)
    var tm = load("res://scripts/townsfolk_manager.gd").new()
    tm.name = "TownsfolkManager"
    main_map.add_child(tm)
    city.total_population = 1
    city.idle_population = 0
    tm.assigned_buildings = {"0": true}
    var ticks := ceili(float(recipe.get("time", 6.0)) / float(city.SIMULATION_TICK))

    for aggregate in AGGREGATES:
        city.city_built_buildings = [
            {"id": "mason_workshop", "slots": [PRODUCT], "quality_priority": "best"}
        ]
        city.city_storage.clear()
        city.city_quality_detail.clear()
        city.reset_counters()
        for pid in ["lime", "tuff", aggregate]:
            city.add_to_storage(pid, 10, "common")
        for _tick in range(ticks):
            city.do_tick()
        _check(city.get_storage_amount(PRODUCT) == 10, "one cycle produces concrete using " + aggregate)
        for pid in ["lime", "tuff", aggregate]:
            _check(city.get_storage_amount(pid) == 0, "the cycle consumes its input: " + pid)
        for _tick in range(ticks):
            city.do_tick()
        _check(city.get_storage_amount(PRODUCT) == 10, "concrete production stops without fresh inputs")

    # Sand or extra aggregate cannot replace the reactive volcanic component.
    city.city_built_buildings = [
        {"id": "mason_workshop", "slots": [PRODUCT], "quality_priority": "best"}
    ]
    city.city_storage.clear()
    city.city_quality_detail.clear()
    city.reset_counters()
    for pid in ["lime", "quartz_sand", "basalt"]:
        city.add_to_storage(pid, 100, "common")
    for _tick in range(ticks * 2):
        city.do_tick()
    _check(city.get_storage_amount(PRODUCT) == 0, "concrete cannot be made without tuff")
    city.city_built_buildings.clear()
    tm.assigned_buildings.clear()
    main_map.free()

func _check(condition: bool, message: String) -> void:
    if condition:
        print("OK: ", message)
    else:
        _failed = true
        push_error("ASSERT: " + message)
        print("ASSERT FAILED: ", message)
