# Headless regression test for the amber resource and its jewelry chain:
#   godot --headless --path . --script res://tests/test_amber_chain.gd
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")
const DEPOSIT_ID := "amber_deposit"
const AMBER_ID := "amber"
const JEWELRY_ID := "amber_jewelry"

var _failed := false

func _initialize() -> void:
    WATCHDOG.arm(self)
    var gd = get_root().get_node("GameData")
    gd.load_all_data()

    var deposit: Dictionary = gd.raw_resources.get(DEPOSIT_ID, {})
    _check(not deposit.is_empty(), "the amber deposit is a map resource")
    _check(deposit.get("produces", {}).get(AMBER_ID, 0) > 0,
        "the map deposit yields amber")
    _check(deposit.get("improved_by", "") == "mine",
        "the amber deposit is worked by a mine")

    var tiles := [[{"terrain": "boreal_plain", "cover": "none"}]]
    var generator = load("res://scripts/map_generator.gd").new()
    generator.place_all_resources(tiles, {DEPOSIT_ID: deposit}, 1, 1, -2, -2)
    _check(tiles[0][0].get("resource", "") == DEPOSIT_ID,
        "the amber deposit spawns on an eligible map tile")
    generator.free()

    var amber: Dictionary = gd.products.get(AMBER_ID, {})
    _check(not amber.is_empty() and amber.get("category", "") == "minerals",
        "amber is a mineral-category product")
    _check(str(amber.get("icon", "")) == "amber.png",
        "the amber product uses the amber resource icon")

    var jewelry: Dictionary = gd.products.get(JEWELRY_ID, {})
    _check(not jewelry.is_empty(), "amber jewelry is a product")
    _check((gd.product_groups.get("jewelry", []) as Array).has(JEWELRY_ID),
        "amber jewelry belongs to the household jewelry group")

    var recipe: Dictionary = gd.find_craft(JEWELRY_ID)
    _check(not recipe.is_empty(), "the amber jewelry recipe exists")
    _check(recipe.get("produced_in", []).has("jeweler_house"),
        "amber jewelry is made in the jeweler's house")
    _check(recipe.get("resources", {}).get(AMBER_ID, 0) > 0,
        "amber is the recipe's material")
    _check(recipe.get("result", {}).get(JEWELRY_ID, 0) > 0,
        "the recipe produces amber jewelry")

    _check(gd.craft_extras.get(AMBER_ID, {}).get("kind", "") == "gemstone",
        "amber can also decorate other jewelry recipes")

    var icons = get_root().get_node("IconRegistry")
    _check(icons.get_texture("amber.png") != null, "the amber icon loads")
    _check(icons.get_texture("amber_jewelry.png") != null, "the amber jewelry icon loads")

    WATCHDOG.report_skipped()
    print("AMBER CHAIN TEST FAILED" if _failed else "AMBER CHAIN TEST OK")
    quit(1 if _failed else 0)

func _check(condition: bool, message: String) -> void:
    if not condition:
        _failed = true
        push_error("ASSERT: " + message)
        print("ASSERT FAILED: ", message)
