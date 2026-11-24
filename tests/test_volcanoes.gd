# Headless checks for the rare volcanic mountain cover and its resource neighborhood.
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")

func _initialize() -> void:
    WATCHDOG.arm(self)
    _run()

func _run() -> void:
    var state := {"failed": false}
    get_root().get_node("SaveManager").new_game()
    var gdata = get_root().get_node("GameData")
    var helpers = load("res://scripts/map_helpers.gd")
    var generator = load("res://scripts/map_generator.gd").new()

    var volcano: Dictionary = gdata.covers.get("volcano", {})
    check(not volcano.is_empty(), "the volcano cover must be loaded", state)
    check(volcano.get("terrain_families", []) == ["mountain"],
            "volcanoes must be restricted to the mountain relief", state)
    var jewelry_options: Array = gdata.get_recipe_extra_options("gold_jewelry")
    var gemstone_items: Array = []
    if not jewelry_options.is_empty():
        gemstone_items = jewelry_options[0].get("items", [])
    var obsidian_is_gem_option := false
    for item in gemstone_items:
        if str(item.get("product", "")) == "obsidian":
            obsidian_is_gem_option = true
            break
    check(obsidian_is_gem_option,
            "obsidian must be available as an optional gemstone in jewelry recipes", state)
    var volcano_chance := float(volcano.get("spawn_chance", 0.0))
    check(volcano_chance > 0.0 and volcano_chance < 5.0,
            "volcanoes must have a rare spawn chance", state)

    var tile_data := []
    for row in range(3):
        var line := []
        for col in range(3):
            line.append({"terrain": "steppe_hill", "cover": "none"})
        tile_data.append(line)
    tile_data[1][1]["cover"] = "volcano"
    var adjacent_condition := {"spawn_conditions": [[
        {"type": "near_cover", "cover_id": "volcano", "chance": 100}
    ]]}
    check(helpers.is_hex_conditions_met(tile_data, 1, 2, adjacent_condition),
            "a hex beside a volcano must satisfy near_cover", state)
    check(not helpers.is_hex_conditions_met(tile_data, 0, 0, adjacent_condition),
            "a distant hex must not satisfy near_cover", state)
    check(helpers.is_hex_conditions_met(tile_data, 1, 1, adjacent_condition),
            "the volcanic hex itself must satisfy near_cover", state)

    for resource_id in ["basalt_deposit", "tuff_deposit", "sulfur_deposit", "obsidian_deposit"]:
        var resource: Dictionary = gdata.raw_resources.get(resource_id, {})
        check(not resource.is_empty(), "%s must exist" % resource_id, state)
        check(helpers.is_hex_conditions_met(tile_data, 1, 2, resource),
                "%s must be able to spawn beside a volcano" % resource_id, state)
        check(not helpers.is_hex_conditions_met(tile_data, 0, 0, resource),
                "%s must not spawn far from a volcano" % resource_id, state)

    var original_chance := float(volcano.get("spawn_chance", 0.0))
    volcano["spawn_chance"] = 100.0
    var mountain := {"terrain": "steppe_mountain", "climate": "steppe", "temperature": "mild"}
    var plain := {"terrain": "steppe_plain", "climate": "steppe", "temperature": "mild"}
    check(generator._roll_cover(mountain) == "volcano",
            "the eligible mountain must roll the volcanic cover at guaranteed chance", state)
    check(generator._roll_cover(plain) != "volcano",
            "the volcanic cover must never roll on plains", state)
    volcano["spawn_chance"] = original_chance

    WATCHDOG.report_skipped()
    if state["failed"]:
        print("VOLCANOES TEST FAILED")
        quit(1)
    print("VOLCANOES TEST OK")
    quit(0)

func check(condition: bool, message: String, state: Dictionary) -> void:
    if condition:
        return
    state["failed"] = true
    printerr("FAIL: %s" % message)
