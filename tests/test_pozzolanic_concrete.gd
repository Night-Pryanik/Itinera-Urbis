# Headless regression test of the pozzolanic concrete chain and its technology gate.
#   godot --headless --path . --script res://tests/test_pozzolanic_concrete.gd
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")
const PRODUCT := "pozzolanic_concrete"
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
    _check(recipe.get("produced_in", []) == ["lime_kilns"], "only the kiln yard mixes concrete")
    _check(recipe.get("unlock_tech", "") == "concrete", "the recipe requires Concrete")
    # JSON quantities are floats; compare numeric values rather than typed dictionaries.
    var outputs: Dictionary = recipe.get("result", {})
    _check(outputs.keys() == [PRODUCT] and float(outputs.get(PRODUCT, 0)) == 10.0,
        "one cycle yields ten units of concrete")
    _check(is_equal_approx(float(recipe.get("time", 0)), 11.0),
        "concrete cycle includes five seconds of firing and six of mixing")
    var ingredients: Array = gd.craft_alternatives(recipe)
    _check(ingredients.size() == 4, "limestone, pozzolan, aggregate and fuel are mandatory")
    if ingredients.size() == 4:
        _check(ingredients[0] == [{"key": "limestone", "amount": 20}],
            "the integrated cycle burns twenty units of limestone")
        _check(ingredients[3] == [{"key": "@smelting_fuel", "amount": 10}],
            "the integrated cycle requires furnace fuel")
        _check(ingredients[1] == [{"key": "tuff", "amount": 10}], "tuff supplies the pozzolan")
        var aggregate_ids: Array = []
        for variant in ingredients[2]:
            aggregate_ids.append(str(variant.get("key", "")))
            _check(int(variant.get("amount", 0)) == 10, "each aggregate needs ten units")
        _check(aggregate_ids == AGGREGATES, "ordinary stone alternatives supply aggregate only")
    var mortar: Dictionary = city.get_craft_by_id("mortar")
    var mortar_inputs: Dictionary = mortar.get("resources", {})
    _check(mortar_inputs.size() == 3 and float(mortar_inputs.get("limestone", 0)) == 20.0
        and float(mortar_inputs.get("quartz_sand", 0)) == 10.0
        and float(mortar_inputs.get("@smelting_fuel", 0)) == 10.0,
        "mortar is made directly from limestone, sand and furnace fuel")
    _check(is_equal_approx(float(mortar.get("time", 0)), 10.0),
        "mortar cycle includes firing and mixing")
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
    _check(city.can_craft_in(PRODUCT, "lime_kilns"), "the kiln yard accepts the concrete recipe")
    _check(not city.can_craft_in(PRODUCT, "mason_workshop"), "the mason does not mix concrete")
    _check(not city.can_craft_in(PRODUCT, "builders_yard"), "builders do not manufacture concrete")
    _check(mortar.get("produced_in", []) == ["lime_kilns"], "only the kiln yard mixes mortar")
    _check(not city.can_craft_in("mortar", "mason_workshop")
        and not city.can_craft_in("mortar", "builders_yard"), "mortar is not made by masons or builders")
    _check(city.can_craft_in("lime", "lime_kilns"), "the separate lime recipe remains in the kiln")
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
    var ticks := ceili(float(recipe.get("time", 11.0)) / float(city.SIMULATION_TICK))

    for aggregate in AGGREGATES:
        var inputs := {"limestone": 20, "tuff": 10, "charcoal": 10}
        inputs[aggregate] = int(inputs.get(aggregate, 0)) + 10
        _prepare_kiln(city, PRODUCT, inputs)
        for _tick in range(ticks):
            city.do_tick()
        _check(city.get_storage_amount(PRODUCT) == 10, "one cycle produces concrete using " + aggregate)
        for pid in inputs:
            _check(city.get_storage_amount(pid) == 0, "the cycle consumes its input: " + pid)
        _check(city.get_storage_amount("lime") == 0, "the full cycle needs no warehouse stock of lime")
        for _tick in range(ticks):
            city.do_tick()
        _check(city.get_storage_amount(PRODUCT) == 10, "concrete production stops without fresh inputs")

    # Missing components are tested independently; stored lime cannot replace limestone.
    var full_inputs := {"limestone": 20, "tuff": 10, "basalt": 10, "charcoal": 10}
    for missing in ["limestone", "tuff", "charcoal"]:
        var partial: Dictionary = full_inputs.duplicate()
        partial.erase(missing)
        partial["lime"] = 100
        _prepare_kiln(city, PRODUCT, partial)
        for _tick in range(ticks * 2):
            city.do_tick()
        _check(city.get_storage_amount(PRODUCT) == 0, "concrete requires " + missing)
        _check(city.get_storage_amount("lime") == 100, "stored lime is not used in the direct recipe")

    # The same limestone cannot count as both fired binder feedstock and aggregate.
    _prepare_kiln(city, PRODUCT, {"limestone": 20, "tuff": 10, "charcoal": 10})
    for _tick in range(ticks * 2):
        city.do_tick()
    _check(city.get_storage_amount(PRODUCT) < 10,
        "limestone aggregate needs thirty units in total, not twenty")

    var mortar: Dictionary = city.get_craft_by_id("mortar")
    var mortar_ticks := ceili(float(mortar.get("time", 10.0)) / float(city.SIMULATION_TICK))
    var mortar_inputs := {"limestone": 20, "quartz_sand": 10, "charcoal": 10}
    _prepare_kiln(city, "mortar", mortar_inputs)
    for _tick in range(mortar_ticks):
        city.do_tick()
    _check(city.get_storage_amount("mortar") == 10, "the kiln yard produces mortar directly from limestone")
    for pid in mortar_inputs:
        _check(city.get_storage_amount(pid) == 0, "mortar cycle consumes " + pid)
    _check(city.get_storage_amount("lime") == 0, "mortar needs no warehouse stock of lime")
    for missing in mortar_inputs:
        var partial: Dictionary = mortar_inputs.duplicate()
        partial.erase(missing)
        partial["lime"] = 100
        _prepare_kiln(city, "mortar", partial)
        for _tick in range(mortar_ticks * 2):
            city.do_tick()
        _check(city.get_storage_amount("mortar") == 0, "mortar requires " + missing)
        _check(city.get_storage_amount("lime") == 100, "mortar does not consume stored lime")
    _check(is_zero_approx(city.builder_construction_share), "a kiln never grants construction work")
    city.city_built_buildings.clear()
    tm.assigned_buildings.clear()
    main_map.free()

func _prepare_kiln(city: Node, recipe_id: String, inputs: Dictionary) -> void:
    city.city_built_buildings = [
        {"id": "lime_kilns", "slots": [recipe_id], "quality_priority": "best"}
    ]
    city.city_storage.clear()
    city.city_quality_detail.clear()
    city.reset_counters()
    for pid in inputs:
        city.add_to_storage(pid, int(inputs[pid]), "common")

func _check(condition: bool, message: String) -> void:
    if condition:
        print("OK: ", message)
    else:
        _failed = true
        push_error("ASSERT: " + message)
        print("ASSERT FAILED: ", message)
