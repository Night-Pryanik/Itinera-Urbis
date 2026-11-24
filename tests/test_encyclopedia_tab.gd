# Headless test of the "Encyclopedia" tab of the city:
#   godot --headless --path . --script res://tests/test_encyclopedia_tab.gd
#
#  1. The button in the tab bar is a tab now: it switches the panel instead of reporting that
#     the section is under development.
#  2. The search field stands above three columns: the sections, the entities and the
#     description of the picked entity.
#  3. The left column holds the six kinds of entities; the middle one lists the entities of
#     the open section, named after the data.
#  4. Records that share a name share one row: the two deposits of iron, the two of bitumen
#     and the three of salt are not listed as separate entities.
#  5. Picking a row shows its name and its icon in the description column; the icon is drawn
#     at its native size, and an entity without an icon keeps the picture in place.
#  6. The page of a profession has its workplaces, its consumption, its description and a
#     historical note in separate blocks; the links in the first two open the target entity.
#  7. A query searches every section at once and survives a refresh and a change of language.
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")

const DETAIL_ICON_SIZE := Vector2(256, 256)

func _initialize():
    WATCHDOG.arm(self)
    _run()

func _run() -> void:
    var state: Dictionary = {"failed": false}
    var gdata = get_root().get_node("GameData")
    var main_map = load("res://scenes/MainMap.tscn").instantiate()
    get_root().add_child(main_map)
    await process_frame
    await process_frame

    var city_ui = main_map.get_node_or_null("CityUI")
    check(city_ui != null, "CityUI found in MainMap", state)
    if city_ui == null:
        _finish(state)
        return

    var button = city_ui.get_node_or_null("TabBarPanel/TabBar/EncyclopediaButton")
    check(button != null, "the tab bar has an encyclopedia button", state)
    check(city_ui.get_node_or_null("ContentPanel/EncyclopediaPanel") != null,
            "the encyclopedia has its own panel", state)
    check(city_ui.encyclopedia_tab != null, "the encyclopedia tab script is attached", state)
    if button == null or city_ui.encyclopedia_tab == null:
        _finish(state)
        return

    check(not (button in city_ui.stub_buttons),
            "the encyclopedia button is a tab, not a stub", state)
    button.pressed.emit()
    city_ui.show()
    await process_frame
    check(city_ui.active_tab == "encyclopedia",
            "the button switches to the encyclopedia (got \"%s\")" % city_ui.active_tab, state)
    check(city_ui.encyclopedia_panel.visible, "the encyclopedia panel is shown", state)
    check(not city_ui.resources_panel.visible, "the resources panel is hidden", state)

    var panel: Control = city_ui.encyclopedia_panel
    var search := panel.get_node_or_null("SearchField") as LineEdit
    var body := panel.get_node_or_null("Body") as HBoxContainer
    var column := panel.get_node_or_null("Body/SectionsColumn") as VBoxContainer
    var entities_column := panel.get_node_or_null("Body/EntitiesColumn") as VBoxContainer
    var detail_column := panel.get_node_or_null("Body/DetailColumn") as VBoxContainer
    var list := panel.get_node_or_null(
            "Body/EntitiesColumn/ScrollContainer/EntityList") as VBoxContainer
    var detail_icon := panel.get_node_or_null("Body/DetailColumn/Icon") as TextureRect
    var detail_name := panel.get_node_or_null("Body/DetailColumn/NameLabel") as Label
    check(search != null and body != null and column != null and entities_column != null
            and detail_column != null and list != null and detail_icon != null
            and detail_name != null,
            "the panel has a search field and three columns", state)
    if search == null or body == null or column == null or entities_column == null \
            or detail_column == null or list == null or detail_icon == null \
            or detail_name == null:
        _finish(state)
        return

    check(search.get_global_rect().end.y <= body.get_global_rect().position.y + 1.0,
            "the search field stands above the body", state)
    check(column.get_global_rect().position.x < entities_column.get_global_rect().position.x,
            "the sections stand in the left column", state)
    check(entities_column.get_global_rect().position.x < detail_column.get_global_rect().position.x,
            "the description stands in the right column", state)
    check(detail_column.get_global_rect().size.x > entities_column.get_global_rect().size.x,
            "the description column is the widest", state)
    check(detail_icon.custom_minimum_size == DETAIL_ICON_SIZE,
            "the picture of the entity has room for 256 by 256", state)

    var expected := [tr("Resources"), tr("Products"), tr("Technologies"),
            tr("Buildings"), tr("Improvements"), tr("Professions")]
    check(column.get_child_count() == expected.size(),
            "the left column holds six sections (got %d)" % column.get_child_count(), state)
    for i in mini(column.get_child_count(), expected.size()):
        check(str(column.get_child(i).text) == expected[i],
                "section %d is named \"%s\" (got \"%s\")"
                        % [i, expected[i], str(column.get_child(i).text)], state)

    var title := panel.get_node_or_null("Body/EntitiesColumn/TitleLabel") as Label
    check(title != null, "the middle column has a caption", state)
    if title == null:
        _finish(state)
        return
    check(str(title.text) == tr("Resources"),
            "the caption names the open section (got \"%s\")" % str(title.text), state)
    var raw_names := {}
    for res_id in gdata.raw_resources.keys():
        raw_names[str(gdata.get_product_name(str(res_id)))] = true
    check(list.get_child_count() == raw_names.size(),
            "the middle column lists one row per resource (got %d of %d)"
                    % [list.get_child_count(), raw_names.size()], state)
    for ids in [["hematite_deposit", "limonite_deposit"],
            ["bitumen_deposit", "bitumen_deposit_asphalt"],
            ["salt_deposit_lake", "salt_deposit_underground", "salt_evaporation"]]:
        var name := str(gdata.get_product_name(str(ids[0])))
        check(_rows_with_text(list, name).size() == 1,
                "the variants of \"%s\" share one row (got %d)"
                        % [name, _rows_with_text(list, name).size()], state)

    column.get_child(1).pressed.emit()
    check(str(title.text) == tr("Products"),
            "the caption follows the chosen section (got \"%s\")" % str(title.text), state)
    var product_names := {}
    for product_id in gdata.products.keys():
        product_names[str(gdata.get_product_name(str(product_id)))] = true
    check(list.get_child_count() == product_names.size(),
            "the middle column lists one row per product (got %d of %d)"
                    % [list.get_child_count(), product_names.size()], state)

    var pictured := _first_row_with_icon(list)
    check(pictured != null, "a product row carries an icon", state)
    if pictured != null:
        pictured.pressed.emit()
        check(str(detail_name.text) == str(pictured.text),
                "the description names the picked entity (got \"%s\")" % str(detail_name.text), state)
        check(detail_icon.texture != null, "the description shows the picture of the entity", state)

    # A building is drawn at the resolution its icon was made in, not blown up to 256.
    column.get_child(3).pressed.emit()
    var building := _first_row_with_icon(list)
    check(building != null, "a building row carries an icon", state)
    if building != null:
        building.pressed.emit()
        check(detail_icon.stretch_mode == TextureRect.STRETCH_KEEP_CENTERED,
                "the detail picture keeps the native size of the icon", state)
        check(detail_icon.texture.get_size().x <= 256.0
                and detail_icon.texture.get_size().y <= 256.0,
                "the detail picture never exceeds 256 pixels", state)

    column.get_child(5).pressed.emit()
    var profession := _row_with_text(list, str(gdata.get_profession_name("miller")))
    check(profession != null, "the professions section lists the miller", state)
    if profession != null:
        profession.pressed.emit()
        check(str(detail_name.text) == str(profession.text),
                "the description names the picked profession", state)
        check(detail_icon.texture != null,
                "an entity without an icon still shows the fallback picture", state)
        _check_miller_description(state, panel, gdata)

    column.get_child(0).pressed.emit()
    check(detail_name.text == "", "changing the section clears the description", state)

    # The query must reach a section that is not open: a product name is typed while the
    # resources are shown, and the product is still found.
    var resource_names := {}
    for res_id in gdata.raw_resources.keys():
        resource_names[gdata.get_product_name(str(res_id))] = true
    var product_name := ""
    for product_id in gdata.products.keys():
        var name: String = str(gdata.get_product_name(str(product_id)))
        if name != "" and not resource_names.has(name):
            product_name = name
            break
    check(product_name != "", "a product has a name of its own to search for", state)
    if product_name != "":
        search.text = product_name
        search.text_changed.emit(product_name)
        check(city_ui.encyclopedia_tab.search_text == product_name, "the tab keeps the query", state)
        check(str(title.text) == tr("Search by name"),
                "the caption names the search while the field is filled", state)
        check(_row_with_text(list, product_name) != null,
                "the search finds an entity from another section", state)

    city_ui.refresh()
    check(str(search.text) == product_name, "a refresh keeps the query in the field", state)
    check(str(column.get_child(1).text) == tr("Products"),
            "a refresh keeps the captions of the sections", state)

    var original_locale := TranslationServer.get_locale()
    TranslationServer.set_locale("en")
    city_ui.refresh()
    check(str(column.get_child(1).text) == "Products",
            "the sections are relabelled on a change of language", state)
    TranslationServer.set_locale(original_locale)
    city_ui.refresh()

    # A deposit and the good made from it share a name but are different entities: the
    # search shows one row for each of them.
    var iron_name := str(gdata.get_product_name("hematite_deposit"))
    check(str(gdata.get_product_name("iron")) == iron_name,
            "the iron deposit and the iron good have the same name", state)
    search.text = iron_name
    search.text_changed.emit(iron_name)
    check(_rows_with_text(list, iron_name).size() == 2,
            "the search keeps the resource and the product apart (got %d)"
                    % _rows_with_text(list, iron_name).size(), state)

    search.text = ""
    search.text_changed.emit("")
    check(str(title.text) == tr("Resources"),
            "the caption returns to the section when the query is cleared", state)
    check(list.get_child_count() == raw_names.size(),
            "clearing the query restores the list of the section", state)

    city_ui.hide()
    main_map.queue_free()
    _finish(state)

func _check_miller_description(state: Dictionary, panel: Control, gdata) -> void:
    var box := panel.get_node_or_null(
            "Body/DetailColumn/DescriptionScroll/Description") as VBoxContainer
    check(box != null, "the description column has a text block", state)
    if box == null:
        return
    var labels := _rich_labels(box)
    check(box.get_child_count() == 8,
            "four blocks of the description are divided by hairlines (got %d)"
                    % box.get_child_count(), state)
    check(labels.size() == 3,
            "the description holds three rich blocks (got %d)" % labels.size(), state)
    if labels.size() >= 2:
        var work := str(labels[0].text)
        check(work.begins_with(tr("Works at:")), "the workplace block is titled", state)
        check(work.contains("[url=buildings:hand_mill]"),
                "a workplace is a link to the buildings section", state)
        check(work.contains(str(gdata.get_building_display_name("hand_mill"))),
                "the workplace link shows the name of the building", state)
        check(not str(labels[0].get_parsed_text()).contains("[url="),
                "the link tags are not shown to the player", state)
        var consumes := str(labels[1].text)
        check(consumes.begins_with(tr("Consumes:")), "the consumption block is titled", state)
        check(consumes.contains("[url=products:"),
                "a consumed good is a link to the products section", state)
    if labels.size() >= 3:
        var history := str(labels[2].text)
        check(history.begins_with(tr("Historical background:")),
                "the historical note is titled", state)
        check(history.contains(str(gdata.professions.get("miller", {}).get("flavor", ""))),
                "the historical note comes from the profession data", state)

    var link_label: RichTextLabel = null
    for label in labels:
        if str(label.text).contains("[url=buildings:hand_mill]"):
            link_label = label
            break
    if link_label == null:
        return
    link_label.meta_clicked.emit("buildings:hand_mill")
    var title := panel.get_node_or_null("Body/EntitiesColumn/TitleLabel") as Label
    var name_label := panel.get_node_or_null("Body/DetailColumn/NameLabel") as Label
    check(title != null and str(title.text) == tr("Buildings"),
            "the link opens the buildings section", state)
    check(name_label != null
            and str(name_label.text) == str(gdata.get_building_display_name("hand_mill")),
            "the link opens the page of that building", state)

func _rich_labels(box: VBoxContainer) -> Array:
    var out: Array = []
    for child in box.get_children():
        var label := child as RichTextLabel
        if label != null:
            out.append(label)
    return out

func _first_row(list: VBoxContainer) -> Button:
    if list.get_child_count() == 0:
        return null
    return list.get_child(0) as Button

func _first_row_with_icon(list: VBoxContainer) -> Button:
    for child in list.get_children():
        var row := child as Button
        if row != null and row.icon != null:
            return row
    return null

func _row_with_text(list: VBoxContainer, text: String) -> Button:
    var rows := _rows_with_text(list, text)
    return rows[0] if not rows.is_empty() else null

func _rows_with_text(list: VBoxContainer, text: String) -> Array:
    var rows: Array = []
    for child in list.get_children():
        var row := child as Button
        if row != null and str(row.text) == text:
            rows.append(row)
    return rows

func _finish(state: Dictionary) -> void:
    if state["failed"]:
        print("ENCYCLOPEDIA TAB TEST FAILED")
        quit(1)
    else:
        print("ENCYCLOPEDIA TAB TEST OK")
        quit(0)

func check(condition: bool, message: String, state: Dictionary) -> void:
    if condition:
        print("OK: ", message)
    else:
        state["failed"] = true
        push_error("FAIL: " + message)
