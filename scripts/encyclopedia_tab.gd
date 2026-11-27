# encyclopedia_tab.gd
#
# The encyclopedia: a search field above three columns. The left column picks a kind of
# entity, the middle one lists the entities of that kind, and the right one shows the
# icon, the name and the description of the entity the player picked. A query in the
# field searches every kind at once, so the middle column then holds the matches from
# all seven sections, game concepts included.
#
# The description of an entity is a set of blocks divided by hairlines. Some blocks hold
# links to other entities: a click on one opens that entity in its own section instead
# of leaving the encyclopedia. A profession page describes its workplaces and consumption;
# an improvement page describes its costs, its unlock, its worker and its properties; a
# building page describes its costs, unlock, worker, slots, upgrade and historical note.
#
# The query and the picked entity are kept with the tab while the player moves between
# the sections and refreshes the window, so that neither is lost on a rebuild.
extends Node

const UiHelpers = preload("res://scripts/ui_helpers.gd")
const UI_THEME = preload("res://scripts/ui_theme.gd")

const ICON_SIZE := 32
const DETAIL_FALLBACK_ICON := "encyclopedia.svg"

# The flags of an improvement that say something about how it behaves. The order is the
# order in which the properties are written in the encyclopedia.
const IMPROVEMENT_PROPERTY_LABELS := {
    "conducts_water": "conducts water",
    "is_canal": "canal",
    "no_worker": "no worker required",
    "no_road": "no road is laid",
    "water_body_harbor": "opens the water resources of its water body",
    "requires_harbor": "requires a harbor on the same water body",
}

# The detail picture has room for 256 pixels but is drawn at the native size of the icon:
# a 200-pixel building stays 200 pixels instead of being blown up to fill the frame.

var panel: Control = null
var helpers: Node = null
var back_button: Button = null
var search_field: LineEdit = null
var sections_list: VBoxContainer = null
var title_label: Label = null
var entity_list: VBoxContainer = null
var detail_icon: TextureRect = null
var detail_name: Label = null
var description_box: VBoxContainer = null

var selected_section: String = "resources"
var search_text: String = ""
var selected_key: String = ""
var section_buttons: Dictionary = {}
var entity_group: ButtonGroup = null
# Each entry is a snapshot of the three fields that define an open page. The module
# survives the rebuilds of the lists, so the history survives them as well.
var history: Array = []

func setup(p: Control, ui_helpers: Node = null) -> void:
    if p == null or not is_instance_valid(p):
        return
    panel = p
    helpers = ui_helpers
    if helpers == null:
        var owner := get_parent()
        if owner != null:
            helpers = owner.get("ui_helpers")
    back_button = p.get_node_or_null("BackButton") as Button
    search_field = p.get_node_or_null("SearchField") as LineEdit
    sections_list = p.get_node_or_null("Body/SectionsColumn") as VBoxContainer
    title_label = p.get_node_or_null("Body/EntitiesColumn/TitleLabel") as Label
    entity_list = p.get_node_or_null("Body/EntitiesColumn/ScrollContainer/EntityList") as VBoxContainer
    detail_icon = p.get_node_or_null("Body/DetailColumn/Icon") as TextureRect
    detail_name = p.get_node_or_null("Body/DetailColumn/NameLabel") as Label
    description_box = p.get_node_or_null(
            "Body/DetailColumn/DescriptionScroll/Description") as VBoxContainer
    entity_group = ButtonGroup.new()
    entity_group.allow_unpress = false
    if search_field != null and not search_field.text_changed.is_connected(_on_search_text_changed):
        search_field.text_changed.connect(_on_search_text_changed)
    if back_button != null and not back_button.pressed.is_connected(_on_back_pressed):
        back_button.pressed.connect(_on_back_pressed)
    refresh()

# The titles are built here rather than kept as a constant so that a change of language
# rebuilds the buttons with the new captions on the next refresh.
func _section_definitions() -> Array:
    return [
        {"id": "resources", "title": tr("Resources")},
        {"id": "products", "title": tr("Products")},
        {"id": "technologies", "title": tr("Technologies")},
        {"id": "buildings", "title": tr("Buildings")},
        {"id": "improvements", "title": tr("Improvements")},
        {"id": "professions", "title": tr("Professions")},
        {"id": "concepts", "title": tr("Game concepts")},
    ]

func refresh() -> void:
    if sections_list == null or not is_instance_valid(sections_list):
        return
    for child in sections_list.get_children():
        sections_list.remove_child(child)
        child.queue_free()
    section_buttons.clear()
    for section in _section_definitions():
        var id := str(section.get("id", ""))
        var button := Button.new()
        button.name = "SectionButton_%s" % id
        button.text = str(section.get("title", ""))
        button.alignment = HORIZONTAL_ALIGNMENT_LEFT
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        button.custom_minimum_size = Vector2(0, 30)
        button.focus_mode = Control.FOCUS_NONE
        button.pressed.connect(_on_section_pressed.bind(id))
        sections_list.add_child(button)
        section_buttons[id] = button
    _highlight_sections()
    _update_title()
    _rebuild_entities()
    _update_back_button()

# --- The way back ---

func _page_state() -> Dictionary:
    return {
        "section": selected_section,
        "search_text": search_text,
        "selected_key": selected_key,
        "field_text": search_field.text if search_field != null else search_text,
    }

func _push_history() -> void:
    var state := _page_state()
    if not history.is_empty() and history.back() == state:
        return
    history.append(state)
    if history.size() > 32:
        history.pop_front()
    _update_back_button()

func _update_back_button() -> void:
    if back_button != null and is_instance_valid(back_button):
        back_button.disabled = history.is_empty()

func _on_back_pressed() -> void:
    if history.is_empty():
        return
    var state: Dictionary = history.pop_back()
    selected_section = str(state.get("section", "resources"))
    search_text = str(state.get("search_text", ""))
    selected_key = str(state.get("selected_key", ""))
    if search_field != null and is_instance_valid(search_field):
        search_field.text = str(state.get("field_text", search_text))
    refresh()
    _update_back_button()

func _on_section_pressed(id: String) -> void:
    _push_history()
    selected_section = id
    selected_key = ""
    _highlight_sections()
    _update_title()
    _rebuild_entities()

# A query searches every section, so none of them is marked as open while it is in the field.
func _highlight_sections() -> void:
    for id in section_buttons:
        UiHelpers.highlight_toggle_button(section_buttons[id],
                _query() == "" and id == selected_section)

func _on_search_text_changed(text: String) -> void:
    search_text = text
    _highlight_sections()
    _update_title()
    _rebuild_entities()

func _query() -> String:
    return search_text.strip_edges().to_lower()

func _update_title() -> void:
    if title_label == null or not is_instance_valid(title_label):
        return
    if _query() != "":
        title_label.text = tr("Search by name")
        return
    for section in _section_definitions():
        if str(section.get("id", "")) == selected_section:
            title_label.text = str(section.get("title", ""))
            return
    title_label.text = ""

# --- The list of entities ---

# The middle column shows one section, or the matches from all sections when the search
# field is filled. Several records of one section can describe the same entity — two
# deposits of iron, three deposits of salt — so they share one row. The row keeps the ids
# of all its records for the description of the entity.
func _visible_entries() -> Array:
    var section_ids: Array = []
    if _query() == "":
        section_ids.append(selected_section)
    else:
        for section in _section_definitions():
            section_ids.append(str(section.get("id", "")))
    var entries := _entries_of(section_ids)
    var needle := _query()
    if needle != "":
        entries = entries.filter(func(entry):
                return str(entry.get("name", "")).to_lower().find(needle) >= 0)
    entries = _merge_variants(entries)
    entries.sort_custom(func(a, b):
            return str(a.get("name", "")).nocasecmp_to(str(b.get("name", ""))) < 0)
    return entries

func _entries_of(section_ids: Array) -> Array:
    var entries: Array = []
    for section_id in section_ids:
        var id := str(section_id)
        match id:
            "resources":
                for res_id in GameData.raw_resources.keys():
                    entries.append(_entry(id, str(res_id), GameData.raw_resources[res_id], true))
            "products":
                for product_id in GameData.products.keys():
                    entries.append(_entry(id, str(product_id), GameData.products[product_id], true))
            "technologies":
                for record in GameData.technologies:
                    if record is Dictionary:
                        entries.append(_entry(id, str(record.get("id", "")), record, false))
            "buildings":
                for record in GameData.buildings:
                    if record is Dictionary:
                        entries.append(_entry(id, str(record.get("id", "")), record, false))
            "improvements":
                for imp_id in GameData.improvements.keys():
                    entries.append(_entry(id, str(imp_id), GameData.improvements[imp_id], false))
            "professions":
                for prof_id in GameData.professions.keys():
                    entries.append(_entry(id, str(prof_id), GameData.professions[prof_id], false))
            "concepts":
                for record in GameData.game_concepts:
                    if record is Dictionary:
                        entries.append(_entry(id, str(record.get("id", "")), record, false))
    return entries

func _entry(section: String, id: String, record: Dictionary, goods: bool) -> Dictionary:
    var name := ""
    if goods:
        name = GameData.get_product_name(id)
    else:
        match section:
            "buildings":
                name = GameData.get_building_display_name(id)
            "improvements":
                name = GameData.get_improvement_display_name(id)
            "professions":
                name = GameData.get_profession_name(id)
            _:
                name = str(record.get("name", id))
    if name.is_empty():
        name = id
    return {
        "key": section + ":" + id,
        "section": section,
        "id": id,
        "name": name,
        "icon": str(record.get("icon", "")),
    }

# Records of one entity carry the same display name inside one section: the deposits of
# iron or salt are variants of a resource, while the crafted good of that name is a
# different entity of another section. The first icon found is enough for the row, because
# the variants of one entity share their picture in the data.
func _merge_variants(entries: Array) -> Array:
    var groups: Dictionary = {}
    var order: Array = []
    for entry in entries:
        var name := str(entry.get("name", ""))
        var key := str(entry.get("section", "")) + ":" + name
        if not groups.has(key):
            groups[key] = {
                "key": key,
                "name": name,
                "icon": "",
                "records": [],
            }
            order.append(key)
        var group: Dictionary = groups[key]
        var icon := str(entry.get("icon", ""))
        if str(group.get("icon", "")).is_empty() and icon != "":
            group["icon"] = icon
        var records: Array = group.get("records", [])
        records.append({"section": str(entry.get("section", "")),
                "id": str(entry.get("id", ""))})
    var merged: Array = []
    for key in order:
        merged.append(groups[key])
    return merged

func _rebuild_entities() -> void:
    if entity_list == null or not is_instance_valid(entity_list):
        return
    for child in entity_list.get_children():
        entity_list.remove_child(child)
        child.queue_free()
    var restored := false
    for entry in _visible_entries():
        var key := str(entry.get("key", ""))
        var button := Button.new()
        button.name = "Entity_%s" % key
        button.text = str(entry.get("name", ""))
        button.alignment = HORIZONTAL_ALIGNMENT_LEFT
        button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        button.custom_minimum_size = Vector2(0, 32)
        button.toggle_mode = true
        button.button_group = entity_group
        var texture := IconRegistry.get_texture(str(entry.get("icon", "")))
        if texture != null:
            button.icon = texture
            button.expand_icon = true
            button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
            button.add_theme_constant_override("icon_max_width", ICON_SIZE)
            button.add_theme_constant_override("icon_max_height", ICON_SIZE)
        button.pressed.connect(_on_entity_pressed.bind(entry))
        entity_list.add_child(button)
        if key == selected_key and selected_key != "":
            button.set_pressed(true)
            _show_detail(entry)
            restored = true
    if not restored:
        _clear_detail()

func _on_entity_pressed(entry: Dictionary) -> void:
    var key := str(entry.get("key", ""))
    if key != selected_key:
        _push_history()
    selected_key = key
    _show_detail(entry)

# --- The column of the description ---

# An entity may have no icon of its own, so the book stands in for it: the detail column
# keeps its size whatever row is picked.
func _show_detail(entry: Dictionary) -> void:
    if detail_icon != null and is_instance_valid(detail_icon):
        var texture := IconRegistry.get_texture(str(entry.get("icon", "")))
        if texture == null:
            texture = IconRegistry.get_texture(DETAIL_FALLBACK_ICON)
        detail_icon.texture = texture
        detail_icon.visible = texture != null
    if detail_name != null and is_instance_valid(detail_name):
        detail_name.text = str(entry.get("name", ""))
    _build_description(entry)

func _clear_detail() -> void:
    if detail_icon != null and is_instance_valid(detail_icon):
        detail_icon.texture = null
        detail_icon.visible = false
    if detail_name != null and is_instance_valid(detail_name):
        detail_name.text = ""
    _clear_description()

# A link carries the section and the id of its target ("buildings:hand_mill"). A click
# stays inside the encyclopedia: the target becomes the open entity of its own section,
# with the search cleared so that the player sees where he has landed.
func show_entry(section: String, id: String) -> void:
    var known := false
    for definition in _section_definitions():
        if str(definition.get("id", "")) == section:
            known = true
            break
    if not known:
        return
    _push_history()
    selected_section = section
    search_text = ""
    if search_field != null and is_instance_valid(search_field):
        search_field.text = ""
    selected_key = ""
    for entry in _visible_entries():
        for record in entry.get("records", []):
            if str(record.get("section", "")) == section and str(record.get("id", "")) == id:
                selected_key = str(entry.get("key", ""))
                break
    refresh()
    _update_back_button()

func _on_meta_clicked(meta: Variant) -> void:
    var link := str(meta)
    var separator := link.find(":")
    if separator < 0:
        return
    show_entry(link.substr(0, separator), link.substr(separator + 1))

func _clear_description() -> void:
    if helpers != null and is_instance_valid(helpers):
        helpers.hide_group_tooltip()
    if description_box == null or not is_instance_valid(description_box):
        return
    for child in description_box.get_children():
        description_box.remove_child(child)
        child.queue_free()

func _build_description(entry: Dictionary) -> void:
    _clear_description()
    for record in entry.get("records", []):
        var section := str(record.get("section", ""))
        var id := str(record.get("id", ""))
        if section == "buildings":
            _build_building_description(id)
            return
        if section == "improvements":
            _build_improvement_description(id)
            return
        if section == "professions":
            _build_profession_description(id)
            return
        if section == "concepts":
            _build_concept_description(id)
            return

# A concept takes its text from a locale/game_concepts_<code>.json file. Blank lines divide the
# text into blocks; the article itself decides what goes into them (a list, a paragraph, headings).
func _build_concept_description(concept_id: String) -> void:
    var record: Dictionary = {}
    for candidate in GameData.game_concepts:
        if candidate is Dictionary and str(candidate.get("id", "")) == concept_id:
            record = candidate
            break
    if record.is_empty():
        return
    var paragraphs := str(record.get("description", "")).split("\n\n")
    for i in paragraphs.size():
        if i > 0:
            _add_separator()
        _add_rich_block(_bbcode_escape(str(paragraphs[i])))

# A building page reads its numbers from the record; only the historical note is authored
# text. The additional cost is skipped when the building needs no materials, and the upgrade
# row is skipped when it has no improved version.
func _build_building_description(building_id: String) -> void:
    var record: Dictionary = GameData.get_building_data(building_id)
    if record.is_empty():
        return

    _add_separator()
    _add_labeled_block(tr("Description:"), _bbcode_escape(str(record.get("description", ""))))

    _add_separator()
    _add_labeled_block(tr("Base cost:"),
            _bbcode_escape(tr("%d work") % int(record.get("work_cost", 0))))

    var materials := _additional_cost_goods(record)
    if not materials.is_empty():
        _add_separator()
        _add_goods_block(tr("Additional cost:"), materials, "AdditionalCostRow", true)

    _add_separator()
    _add_labeled_block(tr("Maintenance cost:"), UiHelpers.money_rate(
            str(maxf(0.0, float(record.get("maintenance_cost", 0.0))))))

    _add_separator()
    var tech_id := str(record.get("unlock_tech", ""))
    var tech_name := _technology_name(tech_id)
    var tech_value := "—"
    if tech_name != "":
        tech_value = _link(tech_name, "technologies:" + tech_id)
    _add_labeled_block(tr("Unlocked by technology:"), tech_value)

    _add_separator()
    var prof_id := str(record.get("profession", ""))
    var prof_value := "—"
    if prof_id != "" and GameData.professions.has(prof_id):
        prof_value = _link(GameData.get_profession_name(prof_id), "professions:" + prof_id)
    _add_labeled_block(tr("Who works:"), prof_value)

    _add_separator()
    _add_labeled_block(tr("Production slots:"),
            str(int(record.get("production_slots", 0))))

    var upgrade_id := str(record.get("upgrades_into", ""))
    if upgrade_id != "":
        _add_separator()
        var upgrade_value := "—"
        if not GameData.get_building_data(upgrade_id).is_empty():
            upgrade_value = _link(GameData.get_building_display_name(upgrade_id),
                    "buildings:" + upgrade_id)
        _add_labeled_block(tr("Can be upgraded into:"), upgrade_value)

    _add_separator()
    var flavor := str(record.get("flavor", ""))
    var history_text := tr("Historical essay:")
    if flavor == "":
        history_text += " —"
    else:
        history_text += "\n[color=%s]%s[/color]" % [
                UI_THEME.color("text_muted").to_html(false), _bbcode_escape(flavor)]
    _add_rich_block(history_text)

# An improvement has no separate description field: the costs, the unlock, the worker and
# the flags are all read from its record, and only the historical note is authored text.
func _build_improvement_description(imp_id: String) -> void:
    var record: Dictionary = GameData.improvements.get(imp_id, {})
    if record.is_empty():
        return

    _add_separator()
    _add_labeled_block(tr("Base cost:"),
            _bbcode_escape(tr("%d work") % int(record.get("work_cost", 0))))

    _add_separator()
    _add_labeled_block(tr("Maintenance cost:"), UiHelpers.money_rate(
            str(maxf(0.0, float(record.get("maintenance_cost", 0.0))))))

    _add_separator()
    var tech_id := str(record.get("unlock_tech", ""))
    var tech_name := _technology_name(tech_id)
    var tech_value := "—"
    if tech_name != "":
        tech_value = _link(tech_name, "technologies:" + tech_id)
    _add_labeled_block(tr("Unlocked by technology:"), tech_value)

    _add_separator()
    var prof_id := str(record.get("profession", ""))
    var prof_value := "—"
    if prof_id != "" and GameData.professions.has(prof_id):
        prof_value = _link(GameData.get_profession_name(prof_id), "professions:" + prof_id)
    _add_labeled_block(tr("Who works:"), prof_value)

    _add_separator()
    var properties := _improvement_properties(record)
    var properties_value := "—"
    if not properties.is_empty():
        properties_value = ", ".join(properties)
    _add_labeled_block(tr("Additional properties:"), properties_value)

    _add_separator()
    var flavor := str(record.get("flavor", ""))
    var history_text := tr("Historical essay:")
    if flavor == "":
        history_text += " —"
    else:
        history_text += "\n[color=%s]%s[/color]" % [
                UI_THEME.color("text_muted").to_html(false), _bbcode_escape(flavor)]
    _add_rich_block(history_text)

func _build_profession_description(prof_id: String) -> void:
    var record: Dictionary = GameData.professions.get(prof_id, {})
    if record.is_empty():
        return

    _add_separator()
    var places := _workplaces(prof_id)
    var workplace_text := tr("Works at:") + (" " if not places.is_empty() else " —")
    if not places.is_empty():
        for i in places.size():
            if i > 0:
                workplace_text += ", "
            var place: Dictionary = places[i]
            workplace_text += _link(str(place.get("name", "")),
                    "%s:%s" % [str(place.get("section", "")), str(place.get("id", ""))])
    _add_rich_block(workplace_text)

    _add_separator()
    _add_consumption_block(_consumption(prof_id))

    _add_separator()
    var description := str(record.get("description", ""))
    _add_text_block(description if description != "" else "—", "text")

    _add_separator()
    var flavor := str(record.get("flavor", ""))
    var history_text := tr("Historical background:")
    if flavor == "":
        history_text += " —"
    else:
        history_text += "\n[color=%s]%s[/color]" % [
                UI_THEME.color("text_muted").to_html(false), _bbcode_escape(flavor)]
    _add_rich_block(history_text)

# The technologies are kept as an array, so the name is looked up by id. An unknown id has
# no page to link to and is shown as an empty value instead.
func _technology_name(tech_id: String) -> String:
    for record in GameData.technologies:
        if str(record.get("id", "")) == tech_id:
            return str(record.get("name", ""))
    return ""

func _improvement_properties(record: Dictionary) -> Array:
    var labels: Array = []
    for flag in IMPROVEMENT_PROPERTY_LABELS:
        if bool(record.get(flag, false)):
            labels.append(tr(str(IMPROVEMENT_PROPERTY_LABELS[flag])))
    return labels

# Workplaces come from two collections: the city buildings and the map improvements.
# A profession such as the miller has several buildings, all of them listed.
func _workplaces(prof_id: String) -> Array:
    var places: Array = []
    for building in GameData.buildings:
        if str(building.get("profession", "")) != prof_id:
            continue
        var id := str(building.get("id", ""))
        if id.is_empty():
            continue
        places.append({"section": "buildings", "id": id,
                "name": GameData.get_building_display_name(id)})
    for imp_id in GameData.improvements.keys():
        var improvement: Dictionary = GameData.improvements.get(imp_id, {})
        if str(improvement.get("profession", "")) != prof_id:
            continue
        var id := str(imp_id)
        places.append({"section": "improvements", "id": id,
                "name": GameData.get_improvement_display_name(id)})
    places.sort_custom(func(a, b):
            return str(a.get("name", "")).nocasecmp_to(str(b.get("name", ""))) < 0)
    return places

# The common and the building-scoped rules together are what the profession needs; a
# group is not a link, because it names several goods rather than one entity.
func _consumption(prof_id: String) -> Array:
    var records: Array = GameData.get_profession_consumption(prof_id)
    records.append_array(GameData.get_profession_building_scoped_consumption(prof_id))
    var seen := {}
    var goods: Array = []
    for entry in records:
        if not (entry is Dictionary):
            continue
        var key := str(entry.get("display_key", entry.get("product_id", "")))
        if key.is_empty() or seen.has(key):
            continue
        seen[key] = true
        goods.append({"key": key, "name": str(entry.get("product_name", "")),
                "is_group": bool(entry.get("is_group", false))})
    goods.sort_custom(func(a, b):
            return str(a.get("name", "")).nocasecmp_to(str(b.get("name", ""))) < 0)
    return goods

# An @-prefixed key names a group of goods rather than one product: it gets the group
# label and its hover panel, while a plain key links to the good's own page. The batches
# of additional_cost are flattened, since the encyclopedia lists what is required, not
# the order in which the game writes it off.
func _additional_cost_goods(record: Dictionary) -> Array:
    var seen := {}
    var goods: Array = []
    for bundle in GameData.parse_additional_cost(record.get("additional_cost", [])):
        for key in bundle:
            var id := str(key)
            if id.is_empty() or seen.has(id):
                continue
            seen[id] = true
            var is_group := id.begins_with("@")
            var name := GameData.get_product_group_name(id) if is_group else GameData.get_product_name(id)
            goods.append({"key": id, "name": name, "is_group": is_group,
                    "amount": int(bundle[key])})
    return goods

func _add_separator() -> void:
    if description_box != null and is_instance_valid(description_box):
        description_box.add_child(UiHelpers.build_separator())

func _add_text_block(text: String, color_token: String) -> void:
    var label := Label.new()
    label.text = text
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    label.add_theme_color_override("font_color", UI_THEME.color(color_token))
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    description_box.add_child(label)

func _add_consumption_block(goods: Array) -> void:
    _add_goods_block(tr("Consumes:"), goods, "ConsumesRow", false)

# The goods stand in one row. A single good is a link to its page; a group is the same
# dashed-underlined label the recipes and the costs use — it leads nowhere, but its hover
# unfolds the composition in the standard panel. The cost of a building also carries the
# required amount next to the name.
func _add_goods_block(title: String, goods: Array, row_name: String, with_amount: bool) -> void:
    var row := HBoxContainer.new()
    row.name = row_name
    # The comma carries the space after it; the container must not add one before it.
    row.add_theme_constant_override("separation", 0)
    var title_label := Label.new()
    title_label.text = title + (" " if not goods.is_empty() else " —")
    title_label.add_theme_color_override("font_color", UI_THEME.color("text_secondary"))
    title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_child(title_label)
    for i in goods.size():
        if i > 0:
            var comma := Label.new()
            comma.text = ", "
            comma.mouse_filter = Control.MOUSE_FILTER_IGNORE
            row.add_child(comma)
        var good: Dictionary = goods[i]
        var name := str(good.get("name", ""))
        var amount_text := ""
        if with_amount:
            amount_text = tr(" x%d") % int(good.get("amount", 0))
        if bool(good.get("is_group", false)):
            var group_label = load("res://scripts/underlined_label.gd").new()
            group_label.text = name + amount_text
            group_label.underline_text = name
            group_label.mouse_filter = Control.MOUSE_FILTER_PASS
            group_label.mouse_entered.connect(
                    _on_group_hover.bind(str(good.get("key", ""))))
            group_label.mouse_exited.connect(_on_group_exit)
            row.add_child(group_label)
        else:
            var text := _link(name, "products:%s" % str(good.get("key", "")))
            if amount_text != "":
                text += _bbcode_escape(amount_text)
            var link := _make_rich_text(text)
            link.autowrap_mode = TextServer.AUTOWRAP_OFF
            # The row is a flow of short references: a link must take the width of
            # its own text, not expand and push the other goods apart.
            link.size_flags_horizontal = 0
            row.add_child(link)
    description_box.add_child(row)

func _on_group_hover(group_key: String) -> void:
    if helpers != null and is_instance_valid(helpers):
        helpers.show_group_tooltip(get_viewport().get_mouse_position(), group_key, GameData.products)

func _on_group_exit() -> void:
    if helpers != null and is_instance_valid(helpers):
        helpers.hide_group_tooltip()

func _add_rich_block(text: String) -> void:
    description_box.add_child(_make_rich_text(text))

# A titled row of an improvement page: the caption is muted, the value carries the links.
func _add_labeled_block(title: String, value: String) -> void:
    _add_rich_block("[color=%s]%s[/color] %s" % [
            UI_THEME.color("text_secondary").to_html(false), _bbcode_escape(title), value])

func _make_rich_text(text: String) -> RichTextLabel:
    var label := RichTextLabel.new()
    label.bbcode_enabled = true
    label.fit_content = true
    label.scroll_active = false
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    # The links underline themselves with [u] so that only they carry a line.
    label.meta_underlined = false
    if detail_name != null and is_instance_valid(detail_name):
        label.add_theme_font_size_override("normal_font_size",
                detail_name.get_theme_font_size("font_size"))
    label.meta_clicked.connect(_on_meta_clicked)
    label.text = text
    return label

func _link(text: String, meta: String) -> String:
    return "[url=%s][color=%s][u]%s[/u][/color][/url]" % [
            meta, UI_THEME.color("info").to_html(false), _bbcode_escape(text)]

func _bbcode_escape(text: String) -> String:
    return text.replace("\\", "\\\\").replace("[", "\\[").replace("]", "\\]")
