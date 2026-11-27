# Headless test of the pumice by-product:
#   godot --headless --path . --script res://tests/test_pumice_byproduct.gd
#
# The pumice has no deposit of its own. It rides along with the volcanic stone: the
# quarry that cuts tuff or basalt knocks it out as a second product of the same hex.
# Nothing outside the deposit points at that link — no recipe and no consumption rule
# mentions where the pumice comes from — therefore every part of the chain is pinned here.
#
# Checks:
#   1. The product: a household good of the stone trade, opened by the quarry technology.
#   2. The by-product: the tuff and the basalt quarries yield the pumice besides their stone.
#   3. The gate: the pumice opens with the very technology that opens the quarry, so the
#      by-product can never be locked while its source works.
#   4. The consumption: the citizens use pumice as a household good, while the trades
#      share a separate abrasive group.
#   5. The recipes: stoneware, mirrors and jewelry do not require abrasives.
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")

const PRODUCT := "pumice"
const QUARRY_TECH := "masonry"
const DEPOSITS := ["tuff_deposit", "basalt_deposit"]
const DEPOSIT_STONE := { "tuff_deposit": "tuff", "basalt_deposit": "basalt" }
const HOUSEHOLD_GROUP := "consumer_goods"
const TRADES := ["mason", "jeweler", "glassmaker"]
const ABRASIVES := ["pumice", "quartz_sand", "ochre", "emery"]
const ABRASIVE_RECIPES := [
    "stone_tableware",
    "bronze_mirror",
    "lazurite_jewelry",
    "malachite_jewelry",
    "nephrite_jewelry",
    "porphyry_jewelry",
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

    _test_product(gd)
    _test_by_product(gd)
    _test_gate(gd, city)
    _test_consumption(gd, city)
    _test_recipes(city)

    if _failed:
        print("PUMICE BY-PRODUCT TEST FAILED")
        quit(1)
    else:
        print("PUMICE BY-PRODUCT TEST OK")
        quit(0)

func _test_product(gd: Node) -> void:
    var product: Dictionary = gd.products.get(PRODUCT, {})
    _check(not product.is_empty(), "the pumice product exists")
    _check(str(product.get("type", "")) == "product", "pumice is a product, not a deposit")
    _check(str(product.get("category", "")) == "household_items",
        "pumice is a household good")
    _check(int(product.get("price", 0)) > 0, "pumice has a price")
    _check(str(product.get("unlock_tech", "")) != "", "pumice names the technology that opens it")
    _check(not _record(gd.technologies, QUARRY_TECH).is_empty(),
        "the quarry technology exists")
    _check(str(product.get("icon", "")) != "", "pumice names an icon")

func _test_by_product(gd: Node) -> void:
    for deposit_id in DEPOSITS:
        var deposit: Dictionary = gd.raw_resources.get(deposit_id, {})
        _check(not deposit.is_empty(), "the deposit exists: " + deposit_id)
        _check(str(deposit.get("improved_by", "")) == "quarry",
            "the deposit is worked by a quarry: " + deposit_id)
        var produces: Dictionary = deposit.get("produces", {})
        _check(produces.has(PRODUCT), "the quarry yields pumice: " + deposit_id)
        _check(float(produces.get(PRODUCT, 0)) > 0.0,
            "the pumice output is positive: " + deposit_id)
        var stone_id := str(DEPOSIT_STONE.get(deposit_id, ""))
        _check(produces.has(stone_id), "the deposit keeps its stone: " + deposit_id)
        _check(float(produces.get(stone_id, 0)) > 0.0,
            "the stone output stays positive: " + deposit_id)
        _check(gd.products.has(stone_id),
            "the stone of the deposit is a product: " + stone_id)

# The by-product must not be locked while the improvement that yields it already works:
# the product and the quarry share one gate. The gate is the one the production tick reads
# (CityData._is_product_available), therefore a mismatch here means a quarry that yields
# its stone and silently nothing else.
func _test_gate(gd: Node, city: Node) -> void:
    var quarry: Dictionary = gd.improvements.get("quarry", {})
    _check(not quarry.is_empty(), "the quarry improvement exists")
    var quarry_tech := str(quarry.get("unlock_tech", ""))
    _check(quarry_tech == QUARRY_TECH, "the quarry is opened by the stone technology")
    var product: Dictionary = gd.products.get(PRODUCT, {})
    _check(str(product.get("unlock_tech", "")) == quarry_tech,
        "the pumice is opened together with the quarry that yields it")

    _check(not city.is_product_available(PRODUCT),
        "the pumice is locked before the quarry technology")
    city.unlocked_technologies.append(quarry_tech)
    _check(city.is_product_available(PRODUCT),
        "the quarry technology opens the pumice")

# The citizens write the pumice off as a member of the household group: one norm covers
# the whole shelf of the soap, the sponge and the friends, and the stone travels with it.
# A row of its own would split the stone off that shelf — one more parallel need of the
# same citizens instead of a good they pick up at the same counter.
func _test_consumption(gd: Node, city: Node) -> void:
    var members: Array = gd.product_groups.get(HOUSEHOLD_GROUP, [])
    _check(members.has(PRODUCT), "the pumice rides in the household group")

    var city_rule: Dictionary = _find_rule(
            gd.get_profession_consumption("all"), "@" + HOUSEHOLD_GROUP)
    _check(not city_rule.is_empty(), "the citizens have the household norm")
    _check(bool(city_rule.get("is_group", false)),
        "the household norm is a write-off of a group")
    _check((city_rule.get("group_members", []) as Array).has(PRODUCT),
        "the household norm covers the pumice")

    # The stone must not be declared twice: the shelf is spent through the group, and a
    # rule naming the pumice itself would write the same citizens off a second time.
    _check(_find_rule(gd.get_profession_consumption("all"), PRODUCT).is_empty(),
        "the pumice has no norm of its own besides the group")

    var group: Array = gd.product_groups.get("abrasives", [])
    _check(group == ABRASIVES, "the abrasive group contains every interchangeable material")
    var wm = load("res://scripts/worker_manager.gd").new()
    root.add_child(wm)
    for profession_id in TRADES:
        var rule: Dictionary = _find_rule(
                gd.get_profession_consumption(profession_id), "@abrasives")
        _check(not rule.is_empty(), "%s consumes abrasives" % profession_id)
        _check(bool(rule.get("is_group", false)), "%s consumes one group" % profession_id)
        _check(int(rule.get("amount", 0)) == 10 and float(rule.get("interval", 0)) == 10.0,
            "%s keeps the abrasive consumption rate" % profession_id)
        _check(absf(float(rule.get("production_bonus", 0.0)) - 0.1) < 0.0001,
            "%s gets the abrasive production bonus" % profession_id)
        _check(_find_rule(gd.get_profession_consumption(profession_id), PRODUCT).is_empty(),
            "%s has no separate pumice rule" % profession_id)
        _check(gd.get_resource_consumer_professions("@abrasives").has(profession_id),
            "%s is listed as an abrasive group consumer" % profession_id)
        city.city_storage.clear()
        city.city_quality_detail.clear()
        _check(is_zero_approx(wm._entry_effective_bonus(rule)),
            "%s gets no abrasive bonus without stock" % profession_id)
        for abrasive in ABRASIVES:
            var found_consumer := false
            for consumer in gd.get_consumption_consumers(abrasive):
                if str(consumer.get("profession_id", "")) == profession_id:
                    found_consumer = true
            _check(found_consumer, "%s is listed as a consumer of %s" % [profession_id, abrasive])
            city.city_storage.clear()
            city.city_quality_detail.clear()
            city.add_to_storage(abrasive, 11, "common")
            _check(absf(wm._entry_effective_bonus(rule) - 0.1) < 0.0001,
                "%s gets the bonus from %s" % [profession_id, abrasive])
            var timers := {}
            wm._tick_profession_consumption(profession_id, "test", timers, 1.0)
            _check(int(city.get_storage_amount(abrasive)) == 10,
                "%s consumes %s" % [profession_id, abrasive])
        city.city_storage.clear()
        city.city_quality_detail.clear()
        for abrasive in ABRASIVES:
            city.add_to_storage(abrasive, 10, "common")
        _check(absf(wm._aggregate_production_bonus([rule]) - 0.1) < 0.0001,
            "%s does not stack bonuses within one abrasive group" % profession_id)
    wm.queue_free()

func _test_recipes(city: Node) -> void:
    var base_inputs := {
        "stone_tableware": {"alabaster": 20},
        "bronze_mirror": {"bronze": 10},
        "lazurite_jewelry": {"lazurite_ore": 10},
        "malachite_jewelry": {"malachite_ore": 10},
        "nephrite_jewelry": {"nephrite": 10},
        "porphyry_jewelry": {"porphyry": 10},
    }
    for recipe_id in ABRASIVE_RECIPES:
        var recipe: Dictionary = city.get_craft_by_id(recipe_id)
        _check(not recipe.is_empty(), "the recipe exists: " + recipe_id)
        if recipe.is_empty():
            continue
        var inputs: Dictionary = recipe.get("resources", {})
        _check(not inputs.has("@abrasives"), "the recipe needs no abrasive group: " + recipe_id)
        for abrasive in ABRASIVES:
            _check(not inputs.has(abrasive), "the recipe needs no %s: %s" % [abrasive, recipe_id])
        var outputs: Dictionary = recipe.get("result", {})
        _check(not outputs.has(PRODUCT), "the pumice is not a result: " + recipe_id)
        city.city_storage.clear()
        city.city_quality_detail.clear()
        for pid in base_inputs[recipe_id]:
            city.add_to_storage(pid, int(base_inputs[recipe_id][pid]), "common")
        var container = load("res://scripts/craft_container.gd").new(recipe)
        var result: Dictionary = container.tick(float(recipe.get("time", 1)), true, "best")
        _check(bool(result.get("completed", false)), recipe_id + " works without abrasives")
        var quantity := 0
        for release in result.get("releases", []):
            if str(release.get("pid", "")) == recipe_id:
                quantity += int(release.get("amount", 0))
        _check(quantity == int(outputs.get(recipe_id, 0)), recipe_id + " yields its full output")
        for pid in base_inputs[recipe_id]:
            _check(int(city.get_storage_amount(pid)) == 0, recipe_id + " consumes " + str(pid))
        city.city_storage.clear()
        city.city_quality_detail.clear()
        container = load("res://scripts/craft_container.gd").new(recipe)
        result = container.tick(float(recipe.get("time", 1)), true, "best")
        _check(not bool(result.get("completed", false)), recipe_id + " still needs its raw material")

func _find_rule(entries: Array, display_key: String) -> Dictionary:
    for entry in entries:
        if not (entry is Dictionary):
            continue
        if str(entry.get("display_key", "")) == display_key:
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
