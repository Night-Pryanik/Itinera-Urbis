# Headless regression test for the three-step mirror ladder.
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")

const LADDER := [
    {
        "product": "bronze_mirror", "recipe": "bronze_mirror", "tech": "jewelry",
        "building": "jeweler_house", "price": 25,
        "inputs": { "bronze": 10, "pumice": 10 },
    },
    {
        "product": "glass_mirror", "recipe": "glass_mirror", "tech": "mirror_making",
        "building": "glassmaker_house", "price": 45,
        "inputs": { "quartz_sand": 20, "soda": 10, "mercury": 10, "tin": 10 },
        "alt_inputs": { "quartz_sand": 20, "potash": 10, "mercury": 10, "tin": 10 },
    },
    {
        "product": "silvered_mirror", "recipe": "silvered_mirror", "tech": "silvered_glass",
        "building": "alchemist_house", "price": 80,
        "inputs": { "quartz_sand": 20, "soda": 10, "silver": 10, "nitric_acid": 10 },
        "alt_inputs": { "quartz_sand": 20, "potash": 10, "silver": 10, "nitric_acid": 10 },
    },
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

    for step in LADDER:
        _test_product(gd, step)
        _test_recipe(gd, city, step)

    _test_technologies(gd)
    _test_group(gd)
    _test_consumption(gd)

    WATCHDOG.report_skipped()
    print("MIRROR LADDER TEST FAILED" if _failed else "MIRROR LADDER TEST OK")
    quit(1 if _failed else 0)

func _test_product(gd: Node, step: Dictionary) -> void:
    var pid := str(step["product"])
    var product: Dictionary = gd.products.get(pid, {})
    _check(not product.is_empty(), "product exists: " + pid)
    if product.is_empty():
        return
    _check(str(product.get("type", "")) == "product", "the mirror is a product: " + pid)
    _check(str(product.get("category", "")) == "household_items", "the mirror is a household good: " + pid)
    _check(int(product.get("price", 0)) == int(step["price"]), "the mirror keeps its price: " + pid)
    _check(str(product.get("unlock_tech", "")) == str(step["tech"]), "the mirror keeps its gate: " + pid)
    _check(str(product.get("icon", "")) != "", "the mirror names an icon: " + pid)
    _check(not _record(gd.technologies, str(step["tech"])).is_empty(),
        "the gate technology exists: " + str(step["tech"]))

func _test_recipe(gd: Node, city: Node, step: Dictionary) -> void:
    var rid := str(step["recipe"])
    var recipe: Dictionary = gd.find_craft(rid)
    _check(not recipe.is_empty(), "recipe exists: " + rid)
    if recipe.is_empty():
        return
    _check(recipe.get("produced_in", []) == [str(step["building"])], "the recipe keeps its building: " + rid)
    _check(str(recipe.get("unlock_tech", "")) == str(step["tech"]), "the recipe keeps its gate: " + rid)
    _check(int(recipe.get("result", {}).get(str(step["product"]), 0)) == 10,
        "the recipe yields ten mirrors: " + rid)
    var ids := _ingredient_ids(recipe.get("resources", {}))
    _check(not ids.has("glassware") and not ids.has("crystal_glassware"),
        "the mirror is melted from batch, not from finished tableware: " + rid)
    if rid == "silvered_mirror":
        _check(not ids.has("lead"), "the silvered mirror is not made of lead crystal")
    if step.has("alt_inputs"):
        _check(ids.has("quartz_sand") and ids.has("soda") and ids.has("potash"),
            "both alkalis are accepted: " + rid)
        _check(_has_alkali_alternative(gd, recipe), "soda and potash are one OR group: " + rid)

    for input_set in [step["inputs"], step.get("alt_inputs", step["inputs"])]:
        _test_cycle(city, recipe, input_set, str(step["product"]), rid)

    var short: Dictionary = {}
    var inputs: Dictionary = step["inputs"]
    var skipped := false
    for input_id in inputs:
        if skipped:
            short[input_id] = inputs[input_id]
        else:
            skipped = true
    _test_cycle(city, recipe, short, str(step["product"]), rid + " needs every input", false)

func _test_technologies(gd: Node) -> void:
    var mirror_making := _record(gd.technologies, "mirror_making")
    _check(not mirror_making.is_empty(), "mirror making is a technology")
    if not mirror_making.is_empty():
        _check(str(mirror_making.get("era", "")) == "medieval", "mirror making belongs to the medieval era")
        _check(_option_has(mirror_making, ["glassblowing", "distillation"]),
            "the mercury-tin mirror needs glassblowing and distillation")

    var silvered := _record(gd.technologies, "silvered_glass")
    _check(not silvered.is_empty(), "silvered glass is a technology")
    if not silvered.is_empty():
        _check(str(silvered.get("era", "")) == "renaissance", "silvered glass belongs to the renaissance era")
        _check(_option_has(silvered, ["chemistry", "mirror_making"]),
            "the silvered mirror needs chemistry and mirror making")

func _test_group(gd: Node) -> void:
    var group: Array = gd.product_groups.get("mirrors", [])
    _check(group.size() == 3, "the mirrors group holds the three kinds")
    _check(group == ["bronze_mirror", "glass_mirror", "silvered_mirror"],
        "the everyday mirror comes first and the costly one last")

func _test_consumption(gd: Node) -> void:
    var found := false
    for rule in gd.consumption_rules:
        if str(rule.get("resource", "")) != "@mirrors":
            continue
        found = true
        _check(float(rule.get("interval", 0)) == 20.0, "mirrors are replaced as rarely as furniture")
        _check(float(rule.get("production_bonus", -1)) == 0.0, "household mirrors grant no production bonus")
    _check(found, "the citizens write off mirrors")

func _test_cycle(city: Node, recipe: Dictionary, inputs: Dictionary, output: String,
        label: String, should_complete: bool = true) -> void:
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
    var options: Array = tech.get("prerequisites", [])
    for option in options:
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
