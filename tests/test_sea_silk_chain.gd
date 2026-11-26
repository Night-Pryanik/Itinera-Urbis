# Headless regression test for the pen shell and sea silk production chain.
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

    var shell: Dictionary = gd.raw_resources.get("pen_shell", {})
    _check(not shell.is_empty(), "pen shell is a map resource")
    _check(shell.get("improved_by", "") == "fishing_boats", "fishing boats collect sea silk")
    _check(shell.get("tech_required", "") == "fishing", "collection requires fishing")
    _check(int(shell.get("produces", {}).get("sea_silk", 0)) == 5, "pen shell yields usable sea silk directly")
    _check(not shell.get("produces", {}).has("raw_byssus"), "there is no raw byssus stage")
    _check(gd.products.get("raw_byssus", {}).is_empty(), "raw byssus is not a product")
    _check(not gd.products.get("sea_silk", {}).is_empty(), "sea silk is a product")
    _check(gd.products.get("sea_silk", {}).get("unlock_tech", "") == "fishing",
        "sea silk is available with fishing, independently of weaving")
    _check(not gd.products.get("sea_silk_clothes", {}).is_empty(), "sea silk clothes are a product")
    _check((gd.product_groups.get("clothes", []) as Array).has("sea_silk_clothes"),
        "sea silk clothes are consumed as clothing")

    var generator = load("res://scripts/map_generator.gd").new()
    var sea := [[{"terrain": "shallow_sea", "cover": "none", "climate": ""}]]
    generator.place_all_resources(sea, {"pen_shell": shell}, 1, 1, -2, -2)
    _check(sea[0][0].get("resource", "") == "pen_shell", "pen shell spawns in shallow sea without a climate zone")
    var land := [[{"terrain": "prairie_plain", "cover": "none", "climate": "prairie"}]]
    generator.place_all_resources(land, {"pen_shell": shell}, 1, 1, -2, -2)
    _check(land[0][0].get("resource", "") != "pen_shell", "pen shell does not spawn on land")
    generator.free()

    _check(gd.find_craft("sea_silk").is_empty(), "sea silk needs no intermediate spinning recipe")
    var clothes: Dictionary = gd.find_craft("sea_silk_clothes")
    _check(not clothes.is_empty(), "sea silk clothes recipe exists")
    _check(clothes.get("unlock_tech", "") == "weaving", "clothes need weaving, not sericulture")
    _check(clothes.get("produced_in", []).has("weaver_house"), "the weaver can make sea silk clothes")
    _check(clothes.get("produced_in", []).has("weaver_workshop"), "the upgraded weaver can make sea silk clothes")
    if not clothes.is_empty():
        _test_cycle(city, clothes, "sea_silk", "sea_silk_clothes")

    var icons = root.get_node("IconRegistry")
    for icon in ["pen_shell.png", "sea_silk.png", "sea_silk_clothes.png"]:
        var texture: Texture2D = icons.get_texture(icon)
        _check(texture != null, icon + " loads")
        if texture != null:
            var image := texture.get_image()
            _check(image != null, icon + " has image data")
            if image != null:
                for point in [Vector2i(0, 0), Vector2i(image.get_width() - 1, 0),
                        Vector2i(0, image.get_height() - 1),
                        Vector2i(image.get_width() - 1, image.get_height() - 1)]:
                    _check(image.get_pixelv(point).a == 0.0, icon + " has transparent corners")

    var previous_locale := TranslationServer.get_locale()
    TranslationServer.set_locale("ru")
    _check(TranslationServer.translate("Pen Shell", "resources.name") == "Пинна (виссонный моллюск)",
        "pen shell has a Russian resource name")
    _check(TranslationServer.translate("Sea Silk", "resources.name") == "Морской шёлк",
        "sea silk has a Russian resource name")
    _check(TranslationServer.translate("Sea Silk Clothes", "crafts.name") == "Одежда из морского шёлка",
        "clothes recipe has a Russian name")
    TranslationServer.set_locale(previous_locale)

    WATCHDOG.report_skipped()
    print("SEA SILK CHAIN TEST FAILED" if _failed else "SEA SILK CHAIN TEST OK")
    quit(1 if _failed else 0)

func _test_cycle(city: Node, recipe: Dictionary, input: String, output: String) -> void:
    city.city_storage.clear()
    var amount := int(recipe.get("resources", {}).get(input, 0))
    _check(amount > 0, output + " requires " + input)
    city.add_to_storage(input, amount, "common")
    var container = load("res://scripts/craft_container.gd").new(recipe)
    var result: Dictionary = container.tick(float(recipe.get("time", 1)), true, "best")
    _check(bool(result.get("completed", false)), output + " production completes")
    var quantity := 0
    for release in result.get("releases", []):
        if str(release.get("pid", "")) == output:
            quantity += int(release.get("amount", 0))
    _check(quantity > 0 and quantity == int(recipe.get("result", {}).get(output, 0)), output + " is produced")
    _check(int(city.get_storage_amount(input)) == 0, output + " consumes its input")

func _check(condition: bool, message: String) -> void:
    if not condition:
        _failed = true
        push_error("ASSERT: " + message)
        print("ASSERT FAILED: ", message)
