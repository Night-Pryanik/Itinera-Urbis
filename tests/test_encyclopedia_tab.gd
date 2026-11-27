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
#     A group of goods carries the standard dashed underline and unfolds its members on hover.
#     The butcher is a professional worker of the slaughterhouse and consumes work tools.
#  7. The page of a building lists its description, base and additional cost, upkeep,
#     unlocking technology, worker, slots, upgrade and historical note in separate blocks.
#     The technology, the profession, the materials and the upgrade are links or group labels.
#  8. The page of an improvement lists its base cost, upkeep, unlocking technology, worker,
#     special properties and historical note in separate blocks; the technology and the
#     profession are links into their own sections.
#  9. A query searches every section at once and survives a refresh and a change of language.
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

    var back := panel.get_node_or_null("BackButton") as Button
    check(back != null and back.disabled,
            "the back button is disabled before the first jump", state)
    check(search.get_global_rect().end.y <= body.get_global_rect().position.y + 1.0,
            "the search field stands above the body", state)
    check(search.get_global_rect().position.x > (back.get_global_rect().end.x
            if back != null else 0.0),
            "the search field stands to the right of the back button", state)
    check(column.get_global_rect().position.x < entities_column.get_global_rect().position.x,
            "the sections stand in the left column", state)
    check(entities_column.get_global_rect().position.x < detail_column.get_global_rect().position.x,
            "the description stands in the right column", state)
    check(detail_column.get_global_rect().size.x > entities_column.get_global_rect().size.x,
            "the description column is the widest", state)
    check(detail_icon.custom_minimum_size == DETAIL_ICON_SIZE,
            "the picture of the entity has room for 256 by 256", state)

    var expected := [tr("Resources"), tr("Products"), tr("Technologies"),
            tr("Buildings"), tr("Improvements"), tr("Professions"), tr("Game concepts")]
    check(column.get_child_count() == expected.size(),
            "the left column holds seven sections (got %d)" % column.get_child_count(), state)
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

    _check_hand_mill_description(state, panel, list, gdata, city_ui)

    column.get_child(4).pressed.emit()
    _check_farm_description(state, panel, list, gdata)

    column.get_child(5).pressed.emit()
    _check_butcher(state, panel, list, gdata, city_ui)
    var profession := _row_with_text(list, str(gdata.get_profession_name("miller")))
    check(profession != null, "the professions section lists the miller", state)
    if profession != null:
        profession.pressed.emit()
        check(str(detail_name.text) == str(profession.text),
                "the description names the picked profession", state)
        check(detail_icon.texture != null,
                "an entity without an icon still shows the fallback picture", state)
        _check_miller_description(state, panel, gdata)

    column.get_child(6).pressed.emit()
    check(str(title.text) == tr("Game concepts"),
            "the concepts section has its own caption (got \"%s\")" % str(title.text), state)
    check(gdata.game_concepts.size() >= 1, "the encyclopedia has at least one concept", state)
    if not gdata.game_concepts.is_empty():
        check(list.get_child_count() == gdata.game_concepts.size(),
                "one row per game concept (got %d of %d)"
                        % [list.get_child_count(), gdata.game_concepts.size()], state)
        var concept: Dictionary = gdata.game_concepts[0]
        var concept_name := str(concept.get("name", ""))
        var concept_row := _row_with_text(list, concept_name)
        check(concept_row != null, "the concept \"%s\" has a row" % concept_name, state)
        if concept_row != null:
            concept_row.pressed.emit()
            check(str(detail_name.text) == concept_name,
                    "the article opens under its name", state)
            var text := str(concept.get("description", ""))
            check(text.contains("•"), "the article uses a bulleted list", state)
            var blocks := text.split("\n\n")
            check(blocks.size() >= 2, "the text is divided into blocks by blank lines", state)
            var description_box = panel.get_node_or_null(
                    "Body/DetailColumn/DescriptionScroll/Description")
            check(_rich_labels(description_box).size() == blocks.size(),
                    "one description block per paragraph", state)
            check(_find_rich(description_box, blocks[1]) != null,
                    "the article shows the list from its locale file", state)

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
    check(str(gdata.get_profession_name("butcher")) == "Butcher",
            "the name of the butcher is translated", state)
    check(str(gdata.professions.get("butcher", {}).get("flavor", ""))
            .begins_with("Butchery is as old as domestication"),
            "the historical note of the butcher is translated", state)
    check(str(gdata.improvements.get("farm", {}).get("flavor", ""))
            .begins_with("Wherever grains were first domesticated"),
            "the historical note of the farm is translated", state)
    check(str(gdata.get_building_data("hand_mill").get("flavor", ""))
            .begins_with("Grinding grain between stones"),
            "the historical note of the hand mill is translated", state)
    check(not gdata.game_concepts.is_empty()
            and str(gdata.game_concepts[0].get("name", "")) == "Production mastery of goods",
            "the game concepts come from the file of the current language", state)
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

func _check_hand_mill_description(state: Dictionary, panel: Control, list: VBoxContainer, gdata, city_ui) -> void:
    var title := panel.get_node_or_null("Body/EntitiesColumn/TitleLabel") as Label
    check(title != null and str(title.text) == tr("Buildings"),
            "the caption names the buildings section", state)
    var mill_name := str(gdata.get_building_display_name("hand_mill"))
    var row := _row_with_text(list, mill_name)
    check(row != null, "the buildings section lists the hand mill", state)
    if row == null:
        return
    row.pressed.emit()
    var box := panel.get_node_or_null(
            "Body/DetailColumn/DescriptionScroll/Description") as VBoxContainer
    check(box != null, "the building has a description", state)
    if box == null:
        return
    var data: Dictionary = gdata.get_building_data("hand_mill")
    check(box.get_child_count() == 18,
            "eight blocks and a cost row of the building are divided by hairlines (got %d)"
                    % box.get_child_count(), state)
    var separators := 0
    for child in box.get_children():
        if child is ColorRect:
            separators += 1
    check(separators == 9, "a hairline stands before every subsection (got %d)"
            % separators, state)
    var labels := _rich_labels(box)
    check(labels.size() == 8, "the building page has eight titled blocks (got %d)"
            % labels.size(), state)
    if labels.size() < 8:
        return
    check(str(labels[0].text).contains(tr("Description:"))
            and str(labels[0].text).contains(str(data.get("description", ""))),
            "the description comes from the building data", state)
    check(str(labels[1].text).contains(tr("Base cost:"))
            and str(labels[1].text).contains("%d" % int(data.get("work_cost", 0))),
            "the base cost comes from the building data", state)
    var cost_row := box.get_node_or_null("AdditionalCostRow") as HFlowContainer
    check(cost_row != null, "the additional cost stands in a wrapping row", state)
    if cost_row == null:
        return
    check(str(cost_row.get_child(0).text).begins_with(tr("Additional cost:")),
            "the additional cost is titled", state)
    var children_width := 0.0
    for child in cost_row.get_children():
        children_width += (child as Control).get_combined_minimum_size().x
    check(cost_row.get_combined_minimum_size().x < children_width,
            "the materials flow into rows instead of forcing one overwide line", state)
    var plank_link := _find_rich(cost_row, "[url=products:planks]") as RichTextLabel
    check(plank_link != null, "a required material is a link to its page", state)
    if plank_link != null:
        check(str(plank_link.text).contains(tr(" x%d") % 30),
                "the required amount stands next to the material", state)
        check(plank_link.size_flags_horizontal == 0,
                "the material takes only the width of its text", state)
    check(str(labels[2].text).contains(tr("Maintenance cost:"))
            and str(labels[2].text).contains("%s" % str(data.get("maintenance_cost", 0.0))),
            "the upkeep comes from the building data", state)
    check(str(labels[3].text).contains(tr("Unlocked by technology:"))
            and str(labels[3].text).contains("—"),
            "a building without an unlock is shown with a dash", state)
    check(str(labels[4].text).contains("[url=professions:miller]")
            and str(labels[4].text).contains(str(gdata.get_profession_name("miller"))),
            "the worker is a link with the profession name", state)
    check(str(labels[5].text).contains(tr("Production slots:"))
            and str(labels[5].text).contains("1"),
            "the number of slots comes from the building data", state)
    check(str(labels[6].text).contains(tr("Can be upgraded into:"))
            and str(labels[6].text).contains("[url=buildings:animal_mill]")
            and str(labels[6].text).contains(str(gdata.get_building_display_name("animal_mill"))),
            "the improved version is a link to its page", state)
    check(str(labels[7].text).contains(tr("Historical essay:"))
            and str(labels[7].text).contains(str(data.get("flavor", ""))),
            "the historical note comes from the building data", state)

    var name_label := panel.get_node_or_null("Body/DetailColumn/NameLabel") as Label
    var back := panel.get_node_or_null("BackButton") as Button
    var worker_link := _find_rich(box, "[url=professions:miller]") as RichTextLabel
    if worker_link != null:
        worker_link.meta_clicked.emit("professions:miller")
        check(title != null and str(title.text) == tr("Professions"),
                "the profession link opens the professions section", state)
        check(name_label != null
                and str(name_label.text) == str(gdata.get_profession_name("miller")),
                "the profession link opens the miller page", state)
        if back != null:
            back.pressed.emit()
            check(title != null and str(title.text) == tr("Buildings"),
                    "back returns to the buildings section", state)
            check(name_label != null and str(name_label.text) == mill_name,
                    "back returns to the hand mill page", state)

    var upgrade_link := _find_rich(box, "[url=buildings:animal_mill]") as RichTextLabel
    check(upgrade_link != null, "the upgrade link survives the return", state)
    if upgrade_link != null:
        upgrade_link.meta_clicked.emit("buildings:animal_mill")
        check(title != null and str(title.text) == tr("Buildings"),
                "the upgrade stays inside the buildings section", state)
        check(name_label != null
                and str(name_label.text) == str(gdata.get_building_display_name("animal_mill")),
                "the upgrade link opens the improved building", state)

        # The improved mill needs a group of goods; the group is the standard dashed label.
        var group_name := str(gdata.get_product_group_name("building_stone"))
        var group_label := _find_underlined(box, group_name)
        check(group_name != "" and group_label != null,
                "a group of materials carries the dashed underline", state)
        if group_label == null:
            return
        check(str(group_label.get("underline_text")) == group_name,
                "only the name of the group is underlined, not the amount", state)
        var helpers = city_ui.ui_helpers
        group_label.mouse_entered.emit()
        check(helpers != null and helpers.group_tooltip_panel.visible,
                "hovering a group shows the standard tooltip", state)
        group_label.mouse_exited.emit()
        check(helpers == null or not helpers.group_tooltip_panel.visible,
                "leaving the group hides the tooltip", state)

    var material_link := _find_rich(box, "[url=products:planks]") as RichTextLabel
    check(material_link != null, "the material link survives the jumps", state)
    if material_link != null:
        material_link.meta_clicked.emit("products:planks")
        check(title != null and str(title.text) == tr("Products"),
                "the material opens the products section", state)
        check(name_label != null
                and str(name_label.text) == str(gdata.get_product_name("planks")),
                "the material opens the planks page", state)

func _check_farm_description(state: Dictionary, panel: Control, list: VBoxContainer, gdata) -> void:
    var title := panel.get_node_or_null("Body/EntitiesColumn/TitleLabel") as Label
    check(title != null and str(title.text) == tr("Improvements"),
            "the caption names the improvements section", state)
    var farm_name := str(gdata.get_improvement_display_name("farm"))
    var row := _row_with_text(list, farm_name)
    check(row != null, "the improvements section lists the farm", state)
    if row == null:
        return
    row.pressed.emit()
    var box := panel.get_node_or_null(
            "Body/DetailColumn/DescriptionScroll/Description") as VBoxContainer
    check(box != null, "the improvement has a description", state)
    if box == null:
        return
    check(box.get_child_count() == 12,
            "six blocks of the improvement are divided by hairlines (got %d)"
                    % box.get_child_count(), state)
    var separators := 0
    for child in box.get_children():
        if child is ColorRect:
            separators += 1
    check(separators == 6, "a hairline stands before every subsection (got %d)"
            % separators, state)
    var labels := _rich_labels(box)
    check(labels.size() == 6, "the improvement page has six titled blocks (got %d)"
            % labels.size(), state)
    if labels.size() < 6:
        return
    check(str(labels[0].text).contains(tr("Base cost:"))
            and str(labels[0].text).contains("%d" % int(gdata.improvements["farm"].get("work_cost", 0))),
            "the base cost comes from the improvement data", state)
    check(str(labels[1].text).contains(tr("Maintenance cost:")),
            "the maintenance cost is titled", state)
    var tech_name := ""
    for record in gdata.technologies:
        if str(record.get("id", "")) == "farming":
            tech_name = str(record.get("name", ""))
            break
    check(str(labels[2].text).contains("[url=technologies:farming]")
            and str(labels[2].text).contains(tech_name),
            "the unlocking technology is a link with its name", state)
    check(str(labels[3].text).contains("[url=professions:farmer]")
            and str(labels[3].text).contains(str(gdata.get_profession_name("farmer"))),
            "the worker is a link with the profession name", state)
    check(str(labels[4].text).contains(tr("conducts water")),
            "a conductor of water is named among the properties", state)
    check(str(labels[5].text).contains(tr("Historical essay:"))
            and str(labels[5].text).contains(str(gdata.improvements["farm"].get("flavor", ""))),
            "the historical note comes from the improvement data", state)

    var name_label := panel.get_node_or_null("Body/DetailColumn/NameLabel") as Label
    var back := panel.get_node_or_null("BackButton") as Button
    labels[2].meta_clicked.emit("technologies:farming")
    check(title != null and str(title.text) == tr("Technologies"),
            "the technology link opens the technologies section", state)
    check(name_label != null and str(name_label.text) == tech_name,
            "the technology link opens the farming page", state)
    if back != null:
        back.pressed.emit()
        check(title != null and str(title.text) == tr("Improvements"),
                "back returns to the improvements section", state)
        check(name_label != null and str(name_label.text) == farm_name,
                "back returns to the farm page", state)

    var farm_row := _row_with_text(list, farm_name)
    if farm_row == null:
        return
    farm_row.pressed.emit()
    var worker_link := _find_rich(box, "[url=professions:farmer]") as RichTextLabel
    check(worker_link != null, "the profession link survives the return", state)
    if worker_link != null:
        worker_link.meta_clicked.emit("professions:farmer")
        check(title != null and str(title.text) == tr("Professions"),
                "the profession link opens the professions section", state)
        check(name_label != null and str(name_label.text) == str(gdata.get_profession_name("farmer")),
                "the profession link opens the farmer page", state)

func _check_butcher(state: Dictionary, panel: Control, list: VBoxContainer, gdata, city_ui) -> void:
    check(str(gdata.get_profession_for_building("slaughterhouse")) == "butcher",
            "the slaughterhouse has the butcher profession", state)
    var row := _row_with_text(list, str(gdata.get_profession_name("butcher")))
    check(row != null, "the professions section lists the butcher", state)
    if row == null:
        return
    row.pressed.emit()
    var box := panel.get_node_or_null(
            "Body/DetailColumn/DescriptionScroll/Description") as VBoxContainer
    if box == null:
        return
    var labels := _rich_labels(box)
    check(labels.size() >= 2, "the butcher page has workplace and consumption blocks", state)
    if labels.size() < 2:
        return
    check(str(labels[0].text).contains("[url=buildings:slaughterhouse]"),
            "the butcher works at the slaughterhouse and the workplace is a link", state)
    var group_name := str(gdata.get_product_group_name("instruments"))
    var group_label := _find_underlined(box, group_name)
    check(group_name != "" and group_label != null,
            "the butcher consumes the group of work tools", state)
    if group_label == null:
        return
    if group_label != null:
        check(str(group_label.get("underline_text")) == group_name,
                "the group name carries the dashed underline", state)
        check(group_label.mouse_filter == Control.MOUSE_FILTER_PASS,
                "the group label receives the hover", state)

    # Hovering the group opens the same panel the recipes and the costs use.
    var helpers = city_ui.ui_helpers
    group_label.mouse_entered.emit()
    check(helpers != null and helpers.group_tooltip_panel.visible,
            "hovering a group shows the standard group tooltip", state)
    if helpers != null and helpers.group_tooltip_panel.visible:
        check(helpers.group_tooltip_content.get_child_count() > 1,
                "the group tooltip lists its members", state)
    group_label.mouse_exited.emit()
    check(helpers == null or not helpers.group_tooltip_panel.visible,
            "leaving the group hides the tooltip", state)

    # A link into another section and the way back to the profession.
    labels[0].meta_clicked.emit("buildings:slaughterhouse")
    var title := panel.get_node_or_null("Body/EntitiesColumn/TitleLabel") as Label
    var name_label := panel.get_node_or_null("Body/DetailColumn/NameLabel") as Label
    check(title != null and str(title.text) == tr("Buildings"),
            "the butcher's workplace link opens the buildings section", state)
    check(name_label != null
            and str(name_label.text) == str(gdata.get_building_display_name("slaughterhouse")),
            "the butcher's workplace link opens the slaughterhouse page", state)
    var back := panel.get_node_or_null("BackButton") as Button
    check(back != null and not back.disabled,
            "the back button is enabled after a jump", state)
    if back != null:
        back.pressed.emit()
        check(title != null and str(title.text) == tr("Professions"),
                "back returns to the profession section", state)
        check(name_label != null and str(name_label.text) == str(row.text),
                "back returns to the butcher page", state)

func _check_miller_description(state: Dictionary, panel: Control, gdata) -> void:
    var box := panel.get_node_or_null(
            "Body/DetailColumn/DescriptionScroll/Description") as VBoxContainer
    check(box != null, "the description column has a text block", state)
    if box == null:
        return
    check(box.get_child_count() == 8,
            "four blocks of the description are divided by hairlines (got %d)"
                    % box.get_child_count(), state)
    var work := _find_rich(box, tr("Works at:"))
    check(work != null, "the workplace block is titled", state)
    if work != null:
        check(str(work.text).contains("[url=buildings:hand_mill]"),
                "a workplace is a link to the buildings section", state)
        check(str(work.text).contains(str(gdata.get_building_display_name("hand_mill"))),
                "the workplace link shows the name of the building", state)
        check(not str(work.get_parsed_text()).contains("[url="),
                "the link tags are not shown to the player", state)
    var product_link := _find_rich(box, "[url=products:")
    check(product_link != null,
            "a consumed good is a link to the products section", state)
    if product_link != null:
        check(product_link.size_flags_horizontal == 0,
                "a consumed good keeps the width of its text", state)
    var consumes_row := box.get_node_or_null("ConsumesRow") as HFlowContainer
    check(consumes_row != null, "the consumed goods stand in a wrapping row", state)
    if consumes_row != null:
        check(consumes_row.get_theme_constant("h_separation") == 0,
                "the comma is not pushed away from the preceding good", state)
        var commas := 0
        for child in consumes_row.get_children():
            var label := child as Label
            if label != null and str(label.text) == ", ":
                commas += 1
        var expected_commas := maxi(0, int((consumes_row.get_child_count() - 2) / 2.0))
        check(commas == expected_commas,
                "the list is separated by commas with a space after them", state)
    var history := _find_rich(box, tr("Historical background:"))
    check(history != null, "the historical note is titled", state)
    if history != null:
        check(str(history.text).contains(
                str(gdata.professions.get("miller", {}).get("flavor", ""))),
                "the historical note comes from the profession data", state)

    var link_label := _find_rich(box, "[url=buildings:hand_mill]") as RichTextLabel
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

func _find_rich(node: Node, needle: String) -> RichTextLabel:
    if node is RichTextLabel and str((node as RichTextLabel).text).contains(needle):
        return node as RichTextLabel
    for child in node.get_children():
        var found := _find_rich(child, needle)
        if found != null:
            return found
    return null

func _find_underlined(node: Node, text: String) -> Label:
    if text == "":
        return null
    if node is Label:
        var underline: Variant = node.get("underline_text")
        if underline != null and str(underline) == text:
            return node as Label
    for child in node.get_children():
        var found := _find_underlined(child, text)
        if found != null:
            return found
    return null

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
