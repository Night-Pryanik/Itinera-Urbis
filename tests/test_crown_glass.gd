# Headless regression test for the crown glass chain.
#
# Crown glass is the medieval window glass: a technology that needs optics and
# glassmaking, a glass workshop that upgrades the glassmaker's house (2 slots),
# the crown glass product, the builder's yard that consumes the panes, and the
# bonus crown glass grants to the optician's lens grinding.
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

    _test_technology(gd)
    _test_building(gd, city)
    _test_product(gd)
    _test_recipe(gd, city)
    _test_consumption(gd)
    _test_bonus(gd, city)

    WATCHDOG.report_skipped()
    print("CROWN GLASS TEST FAILED" if _failed else "CROWN GLASS TEST OK")
    quit(1 if _failed else 0)

func _test_technology(gd: Node) -> void:
    var tech := _record(gd.technologies, "crown_glass")
    _check(not tech.is_empty(), "crown glass is a technology")
    if tech.is_empty():
        return
    _check(str(tech.get("era", "")) == "medieval", "crown glass belongs to the medieval era")
    _check(float(tech.get("science_cost", 0)) == 5.0, "crown glass keeps its science cost")
    _check(_option_has(tech, ["optics", "glassmaking"]),
        "crown glass needs optics and glassmaking")
    _check(str(tech.get("icon", "")) != "", "crown glass names an icon")

func _test_building(gd: Node, city: Node) -> void:
    var workshop := _record(gd.buildings, "glass_workshop")
    _check(not workshop.is_empty(), "the glass workshop is a building")
    if workshop.is_empty():
        return
    _check(float(workshop.get("production_slots", 0)) == 2.0,
        "the glass workshop has two production slots")
    _check(str(workshop.get("unlock_tech", "")) == "crown_glass",
        "the glass workshop is unlocked by crown glass")
    _check(str(workshop.get("profession", "")) == "glassmaker",
        "the glass workshop is worked by the glassmaker")
    _check(str(workshop.get("icon", "")) != "", "the glass workshop names an icon")

    var house := _record(gd.buildings, "glassmaker_house")
    _check(not house.is_empty(), "the glassmaker's house is a building")
    if not house.is_empty():
        _check(str(house.get("upgrades_into", "")) == "glass_workshop",
            "the glassmaker's house upgrades into the glass workshop")

    _check(str(city.get_building_upgrade_target("glassmaker_house")) == "glass_workshop",
        "the upgrade target of the glassmaker's house is the glass workshop")

func _test_product(gd: Node) -> void:
    var product: Dictionary = gd.products.get("crown_glass", {})
    _check(not product.is_empty(), "product exists: crown_glass")
    if product.is_empty():
        return
    _check(str(product.get("type", "")) == "product", "crown glass is a product")
    _check(str(product.get("category", "")) == "construction_material",
        "crown glass is a building material")
    _check(str(product.get("unlock_tech", "")) == "crown_glass",
        "crown glass is opened by its own technology")
    _check(int(product.get("price", 0)) > 0, "crown glass has a price")
    _check(str(product.get("icon", "")) != "", "crown glass names an icon")

func _test_recipe(gd: Node, city: Node) -> void:
    var recipe: Dictionary = gd.find_craft("crown_glass")
    _check(not recipe.is_empty(), "recipe exists: crown_glass")
    if recipe.is_empty():
        return
    _check(recipe.get("produced_in", []) == ["glass_workshop"],
        "crown glass is spun in the glass workshop, not the glassmaker's house")
    _check(str(recipe.get("unlock_tech", "")) == "crown_glass",
        "the crown glass recipe keeps its gate")
    _check(int(recipe.get("result", {}).get("crown_glass", 0)) == 10,
        "the recipe yields ten panes")
    var ids := _ingredient_ids(recipe.get("resources", {}))
    _check(not ids.has("glassware") and not ids.has("crystal_glassware"),
        "crown glass is melted from batch, not from finished vessels")
    _check(ids.has("@smelting_fuel"), "crown glass takes furnace fuel for the spinning")
    _check(_has_alkali_alternative(gd, recipe), "soda and potash are alternatives")

    for input_set in [{ "quartz_sand": 20, "soda": 10, "charcoal": 10 },
            { "quartz_sand": 20, "potash": 10, "charcoal": 10 }]:
        _test_cycle(city, recipe, input_set, "crown_glass")

func _test_consumption(gd: Node) -> void:
    var found := false
    for rule in gd.consumption_rules:
        if str(rule.get("resource", "")) != "crown_glass":
            continue
        found = true
        _check(("builder" in (rule.get("profession", []) as Array)),
            "the builder consumes crown glass")
        var buildings: Array = rule.get("buildings", [])
        _check(buildings == ["builders_yard"],
            "crown glass is spent at the builder's yard")
        _check(absf(float(rule.get("production_bonus", -1)) - 0.10) < 0.0001,
            "glazed windows grant the builder +10%")
    _check(found, "a consumption rule for crown glass exists")

func _test_bonus(gd: Node, city: Node) -> void:
    # The optician is a profession of its own: the master grinds the glassmaker's
    # glass into lenses rather than melting the batch.
    _check(gd.professions.has("optician"),
        "the optician is a profession")
    var workshop := _record(gd.buildings, "optical_workshop")
    if workshop.is_empty():
        _check(false, "the optical workshop is a building for the bonus check")
        return
    _check(str(workshop.get("profession", "")) == "optician",
        "the optical workshop is worked by the optician")

    # Mastering crown glass improves the optician's lens grinding: the thick
    # bullseye centre of the disc is the finest blank for a lens.
    var saved_techs: Array = city.unlocked_technologies.duplicate()
    city.unlocked_technologies = []
    _check(absf(city.get_building_production_multiplier("optical_workshop", false) - 1.0) < 0.0001,
        "crown glass gives no bonus before it is researched")
    city.unlocked_technologies.append("crown_glass")
    _check(absf(city.get_building_production_multiplier("optical_workshop", false) - 1.2) < 0.0001,
        "crown glass raises the optical workshop output by 20%")
    city.unlocked_technologies = saved_techs

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
