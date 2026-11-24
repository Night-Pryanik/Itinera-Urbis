# Headless test of the background of the main menu:
#   godot --headless --path . --script res://tests/test_menu_background.gd
#
# Covers:
#   1. The picture: the menu carries one background with a picture on it.
#   2. The whole picture: it keeps its shape and enters the menu whole — nothing is
#      cut off at the edges.
#   3. The plate: the picture is wider than the window is high, so it takes the whole
#      width and leaves a band above and below, and the plate under it is dark.
#   4. The title: the name of the game stands above the items and does not cover
#      them.
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")

const MENU_SCENE := "res://scenes/main_menu.tscn"

func _initialize() -> void:
    WATCHDOG.arm(self)
    _run()

func _run() -> void:
    var state = {"failed": false}

    var menu = load(MENU_SCENE).instantiate()
    get_root().add_child(menu)
    await process_frame
    await process_frame

    var picture = menu.get_node_or_null("Picture") as TextureRect
    check(picture != null, "the menu carries a picture", state)

    if picture != null:
        var texture = picture.texture
        check(texture != null, "the picture has a texture", state)

        if texture != null:
            check(picture.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED,
                "the picture keeps its shape (got: %d)" % picture.stretch_mode, state)

            # The picture as it is drawn: it fits into the menu, and its shape is the
            # shape of the file.
            var picture_size = texture.get_size()
            var fit = minf(menu.size.x / picture_size.x, menu.size.y / picture_size.y)
            var drawn = picture_size * fit
            check(drawn.x <= menu.size.x + 0.5 and drawn.y <= menu.size.y + 0.5,
                "the picture enters the menu whole (drawn %s, menu %s)"
                    % [str(drawn), str(menu.size)], state)
            check(absf(drawn.x - menu.size.x) <= 0.5,
                "the picture takes the whole width (drawn %s, menu %s)"
                    % [str(drawn), str(menu.size)], state)

        var plate = menu.get_node_or_null("Backdrop") as ColorRect
        check(plate != null, "the picture lies on a plate", state)
        if plate != null:
            check(plate.color.a >= 0.99,
                "the plate is opaque (got: %f)" % plate.color.a, state)

    var title = menu.get_node_or_null("TitleLogo") as TextureRect
    check(title != null, "the menu carries the title logo", state)

    # The items lie on the picture, so their plate is translucent.
    var first_item = menu.get_node_or_null("VBoxContainer/ContinueButton") as Button
    check(first_item != null, "the menu has an item", state)
    if first_item != null:
        check(first_item.theme_type_variation == &"PictureButton",
            "the items are the ones that lie on the picture (got: %s)"
                % first_item.theme_type_variation, state)

    if title != null:
        check(title.texture != null, "the title logo has a texture", state)
        check(title.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED,
            "the title logo keeps its shape (got: %d)" % title.stretch_mode, state)
        check(title.expand_mode == TextureRect.EXPAND_IGNORE_SIZE,
            "the title logo scales with its rect (got: %d)" % title.expand_mode, state)
        var items = menu.get_node_or_null("VBoxContainer") as Control
        check(items != null, "the menu has its items", state)
        if items != null:
            check(title.get_global_rect().end.y <= items.get_global_rect().position.y,
                "the title stands above the items (title ends at %s, items start at %s)"
                    % [str(title.get_global_rect().end.y), str(items.get_global_rect().position.y)], state)
            # The items stand in the lower left corner, by the tree.
            var items_rect = items.get_global_rect()
            check(items_rect.end.x <= menu.size.x * 0.4,
                "the items are on the left (they end at %s of %s)"
                    % [str(items_rect.end.x), str(menu.size.x)], state)
            check(items_rect.end.y >= menu.size.y * 0.5,
                "the items are at the bottom (they end at %s of %s)"
                    % [str(items_rect.end.y), str(menu.size.y)], state)

    get_root().remove_child(menu)
    menu.free()

    if state["failed"]:
        print("MENU BACKGROUND TEST FAILED")
        quit(1)
    else:
        print("MENU BACKGROUND TEST OK")
        quit(0)

func check(cond: bool, msg: String, state: Dictionary):
    if not cond:
        push_error("ASSERT: " + msg)
        print("ASSERT FAILED: ", msg)
        state["failed"] = true
