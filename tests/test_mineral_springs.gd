extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")
const SPRING := "mineral_spring"
const SALT_SPRING := "salt_spring"

var _failed := false

func _initialize() -> void:
    WATCHDOG.arm(self)
    var game_data = get_root().get_node("GameData")
    var generator = load("res://scripts/map_generator.gd").new()
    var helpers = load("res://scripts/map_helpers.gd")
    get_root().get_node("SaveManager").new_game()

    var registry = get_root().get_node("IconRegistry")
    var tile := {"terrain": "boreal_hill", "climate": "boreal_wet", "temperature": "cold"}
    var geological_ids := ["volcano", SPRING, SALT_SPRING]
    var chances := {}
    for cover_id in geological_ids:
        var cover: Dictionary = game_data.covers.get(cover_id, {})
        chances[cover_id] = cover.get("spawn_chance", 0.0)
        cover["spawn_chance"] = 0.0
    for spring_id in [SPRING, SALT_SPRING]:
        var cover: Dictionary = game_data.covers.get(spring_id, {})
        var chance := float(chances[spring_id])
        _check(chance > 0.0 and chance < 1.0, "%s must be rare" % spring_id)
        var icons: Array = cover.get("icons", [])
        _check(not icons.is_empty() and registry.get_texture(str(icons[0])) != null,
                "%s must have a loadable map texture" % spring_id)
        cover["spawn_chance"] = 100.0
        for terrain_id in ["boreal_hill", "boreal_mountain"]:
            tile["terrain"] = terrain_id
            _check(generator._roll_cover(tile) == spring_id, "%s must allow %s" % [terrain_id, spring_id])
        for terrain_id in ["boreal_plain", "boreal_swamp", "lake", "shallow_sea"]:
            tile["terrain"] = terrain_id
            _check(generator._roll_cover(tile) != spring_id, "%s must not allow %s" % [terrain_id, spring_id])
        cover["spawn_chance"] = 0.0
    for cover_id in geological_ids:
        if game_data.covers.has(cover_id):
            game_data.covers[cover_id]["spawn_chance"] = chances[cover_id]

    var tiles := []
    tile["terrain"] = "boreal_hill"
    tile["cover"] = "taiga"
    for row in range(3):
        var line := []
        for col in range(4):
            line.append(tile.duplicate())
        tiles.append(line)
    tiles[1][1]["cover"] = SPRING
    tiles[1][2]["cover"] = "none"
    generator._smooth_covers(tiles, 3, 4)
    _check(tiles[1][1]["cover"] == SPRING, "forest smoothing must preserve the spring")
    _check(tiles[1][2]["cover"] == "taiga", "forest smoothing must still fill an ordinary gap")
    _check(helpers.get_hex_water_access(1, 1, tiles, 3, 4) == "",
            "a mineral spring must not count as a freshwater source")

    var world = load("res://scripts/main_map/world.gd").new()
    world.tile_data = [[{"terrain": "boreal_mountain", "cover": SPRING}]]
    world.map_rows = 1
    world.map_cols = 1
    var bounds := {"start_row": 0, "end_row": 0, "start_col": 0, "end_col": 0}
    _check(world._find_spring_hex(bounds).is_empty(),
            "the aqueduct must not reserve an existing mineral spring")
    _check(world._raise_spring_mountain(bounds).is_empty(),
            "the aqueduct fallback must not replace an existing mineral spring")
    world.free()

    _test_mineral_water(game_data, generator, registry)
    _test_salt_spring(game_data, generator, helpers)
    generator.free()

    WATCHDOG.report_skipped()
    print("MINERAL SPRINGS TEST FAILED" if _failed else "MINERAL SPRINGS TEST OK")
    quit(1 if _failed else 0)

func _test_mineral_water(game_data: Node, generator: Node, registry: Node) -> void:
    var source_id := "mineral_water_source"
    var catchment_id := "spring_catchment"
    var tiles := [[
        {"terrain": "boreal_hill", "cover": SPRING},
        {"terrain": "boreal_mountain", "cover": SPRING},
        {"terrain": "boreal_hill", "cover": SALT_SPRING},
        {"terrain": "boreal_hill", "cover": SPRING, "resource": "existing"}
    ]]
    var source: Dictionary = game_data.raw_resources.get(source_id, {})
    generator.place_all_resources(tiles, {source_id: source}, 1, 4, -2, -2)
    _check(tiles[0][0].get("resource") == source_id and tiles[0][1].get("resource") == source_id,
            "every free mineral spring must supply water")
    _check(tiles[0][2].get("resource") == null and tiles[0][3].get("resource") == "existing",
            "the source must not spawn off the cover or overwrite other resources")
    var outputs: Dictionary = source.get("produces", {})
    _check(source.get("improved_by") == catchment_id and outputs.size() == 1
            and int(outputs.get("mineral_water", 0)) > 0,
            "the catchment must produce finished mineral water directly")
    for craft in game_data.crafts:
        _check(not craft.get("result", {}).has("mineral_water"),
                "mineral water must not require a workshop recipe")
    var drinks: Array = game_data.product_groups.get("non_alcoholic_beverages", [])
    _check("mineral_water" in drinks, "mineral water belongs to the city's beverage group")
    var product: Dictionary = game_data.products.get("mineral_water", {})
    var catchment: Dictionary = game_data.improvements.get(catchment_id, {})
    for record in [source, product, catchment]:
        _check(registry.get_texture(str(record.get("icon", ""))) != null,
                "the source, product and catchment must have loadable icons")

    var city = get_root().get_node("CityData")
    city.unlocked_technologies.append("pottery")
    _check(not city.is_improvement_unlocked(catchment_id) and not city.is_product_available("mineral_water"),
            "Ceramics must not unlock the catchment or mineral water")
    city.unlocked_technologies.erase("pottery")
    city.unlocked_technologies.append("masonry")
    _check(city.is_improvement_unlocked(catchment_id) and city.is_product_available("mineral_water"),
            "Masonry alone must unlock the catchment and mineral water")

func _test_salt_spring(game_data: Node, generator: Node, helpers) -> void:
    var source_id := "salt_spring_brine"
    var source: Dictionary = game_data.raw_resources.get(source_id, {})
    var tiles := [[
        {"terrain": "boreal_hill", "cover": SALT_SPRING},
        {"terrain": "boreal_mountain", "cover": SALT_SPRING},
        {"terrain": "boreal_hill", "cover": SPRING},
        {"terrain": "salt_lake", "cover": "none"}
    ]]
    generator.place_all_resources(tiles, {source_id: source}, 1, 4, -2, -2)
    _check(tiles[0][0].get("resource") == source_id and tiles[0][1].get("resource") == source_id,
            "salt spring brine must spawn inland on both eligible terrain families")
    _check(tiles[0][2].get("resource") == null and tiles[0][3].get("resource") == null,
            "salt spring brine must not spawn on mineral springs or salt lakes")
    _check(helpers.get_hex_water_access(0, 0, tiles, 1, 4) == "",
            "a salt spring must not count as a freshwater source")
    var outputs: Dictionary = source.get("produces", {})
    _check(source.get("improved_by") == "salt_pond" and outputs.size() == 1
            and int(outputs.get("salt", 0)) > 0,
            "a salt pond must evaporate this brine into ordinary salt")
    var city = get_root().get_node("CityData")
    _check(not city.is_improvement_unlocked("salt_pond"), "salt ponds must be locked at the start")
    city.unlocked_technologies.append("salt_extraction")
    _check(city.is_improvement_unlocked("salt_pond") and city.is_product_available("salt"),
            "Salt Extraction must unlock both the pond and its output")

func _check(condition: bool, message: String) -> void:
    if not condition:
        _failed = true
        printerr("FAIL: " + message)
