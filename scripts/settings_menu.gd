# scripts/settings_menu.gd
extends Control

const DisplaySettings = preload("res://scripts/display_settings.gd")
const UiScale = preload("res://scripts/ui_scale.gd")

@onready var hex_borders_checkbox: CheckBox = find_child("HexBordersCheckBox", true, false)
@onready var edge_scrolling_checkbox: CheckBox = find_child("EdgeScrollingCheckBox", true, false)
@onready var edge_scroll_speed_slider: HSlider = find_child("EdgeScrollSpeedSlider", true, false)
@onready var edge_scroll_speed_value_label: Label = find_child(
    "EdgeScrollSpeedValueLabel", true, false)
@onready var back_button: Button = find_child("BackButton", true, false)
@onready var language_option_button: OptionButton = find_child("LanguageOptionButton", true, false)
@onready var font_option_button: OptionButton = find_child("FontOptionButton", true, false)
@onready var theme_option_button: OptionButton = find_child("ThemeOptionButton", true, false)
@onready var tileset_hint: Label = find_child("TilesetHint", true, false)
@onready var tileset_grid: GridContainer = find_child("TilesetGrid", true, false)
@onready var tab_container: TabContainer = find_child("TabContainer", true, false)
@onready var tooltip_delay_slider: HSlider = find_child("TooltipDelaySlider", true, false)
@onready var tooltip_delay_value_label: Label = find_child("TooltipDelayValueLabel", true, false)
@onready var extended_tooltip_delay_slider: HSlider = find_child("ExtendedTooltipDelaySlider", true, false)
@onready var extended_tooltip_delay_value_label: Label = find_child("ExtendedTooltipDelayValueLabel", true, false)
@onready var building_detail_delay_slider: HSlider = find_child(
    "BuildingDetailDelaySlider", true, false)
@onready var building_detail_delay_value_label: Label = find_child(
    "BuildingDetailDelayValueLabel", true, false)
@onready var resource_display_interval_slider: HSlider = find_child(
    "ResourceDisplayIntervalSlider", true, false)
@onready var resource_display_interval_value_label: Label = find_child(
    "ResourceDisplayIntervalValueLabel", true, false)
@onready var hud_message_duration_slider: HSlider = find_child(
    "HudMessageDurationSlider", true, false)
@onready var hud_message_duration_value_label: Label = find_child(
    "HudMessageDurationValueLabel", true, false)
@onready var clock_checkbox: CheckBox = find_child("ClockCheckBox", true, false)
@onready var fps_checkbox: CheckBox = find_child("FpsCheckBox", true, false)
@onready var resolution_option_button: OptionButton = find_child(
    "ResolutionOptionButton", true, false)
@onready var window_mode_option_button: OptionButton = find_child(
    "WindowModeOptionButton", true, false)
@onready var vsync_option_button: OptionButton = find_child("VsyncOptionButton", true, false)
@onready var fps_limit_option_button: OptionButton = find_child(
    "FpsLimitOptionButton", true, false)
@onready var ui_scale_option_button: OptionButton = find_child("UiScaleOptionButton", true, false)

var config = ConfigFile.new()

# The type of icons -> the dropdown that chooses its set. Built in _setup_tileset_options().
var _tileset_options: Dictionary = {}

# The hint of the tilesets as the scene words it, for the case a set is installed. It is a
# catalog key rather than a finished line: the label translates it for display, so the same
# key stays right in every language.
var _tileset_hint_with_sets := ""

func _ready():
    # The window is reached from the pause menu, that is, over a paused tree: a
    # pausable node would stop receiving ESC while the game is stopped (the same
    # reason as in journal_ui.gd).
    process_mode = Node.PROCESS_MODE_ALWAYS
    var missing_controls = not hex_borders_checkbox or not edge_scrolling_checkbox \
            or not edge_scroll_speed_slider or not edge_scroll_speed_value_label \
            or not back_button or not tooltip_delay_slider \
            or not tooltip_delay_value_label \
            or not extended_tooltip_delay_slider \
            or not extended_tooltip_delay_value_label \
            or not building_detail_delay_slider \
            or not building_detail_delay_value_label \
            or not resource_display_interval_slider \
            or not resource_display_interval_value_label \
            or not hud_message_duration_slider \
            or not hud_message_duration_value_label \
            or not clock_checkbox \
            or not fps_checkbox \
            or not resolution_option_button \
            or not window_mode_option_button \
            or not vsync_option_button \
            or not fps_limit_option_button \
            or not ui_scale_option_button \
            or not language_option_button \
            or not font_option_button \
            or not theme_option_button \
            or not tileset_hint \
            or not tileset_grid
    if missing_controls:
        print("Error: not all elements found in the settings scene!")
        return

    _apply_tab_titles()
    load_settings()
    _setup_resolution_option()
    _setup_window_mode_option()
    _setup_vsync_option()
    _setup_fps_limit_option()
    _setup_ui_scale_option()
    _setup_language_option()
    _setup_font_option()
    _setup_theme_option()
    # Read before the rows are built: the text of the scene is the hint of the case a set is
    # installed, and _setup_tileset_options() may replace it with the hint of an empty folder.
    _tileset_hint_with_sets = tileset_hint.text
    _setup_tileset_options()
    back_button.pressed.connect(_on_back_pressed)
    hex_borders_checkbox.toggled.connect(_on_hex_borders_toggled)
    edge_scrolling_checkbox.toggled.connect(_on_edge_scrolling_toggled)
    edge_scroll_speed_slider.value_changed.connect(_on_edge_scroll_speed_changed)
    tooltip_delay_slider.value_changed.connect(_on_tooltip_delay_changed)
    extended_tooltip_delay_slider.value_changed.connect(_on_extended_tooltip_delay_changed)
    building_detail_delay_slider.value_changed.connect(_on_building_detail_delay_changed)
    resource_display_interval_slider.value_changed.connect(_on_resource_display_interval_changed)
    hud_message_duration_slider.value_changed.connect(_on_hud_message_duration_changed)
    clock_checkbox.toggled.connect(_on_clock_toggled)
    fps_checkbox.toggled.connect(_on_fps_toggled)
    resolution_option_button.item_selected.connect(_on_resolution_selected)
    window_mode_option_button.item_selected.connect(_on_window_mode_selected)
    vsync_option_button.item_selected.connect(_on_vsync_selected)
    fps_limit_option_button.item_selected.connect(_on_fps_limit_selected)
    ui_scale_option_button.item_selected.connect(_on_ui_scale_selected)
    language_option_button.item_selected.connect(_on_language_selected)
    font_option_button.item_selected.connect(_on_font_selected)
    theme_option_button.item_selected.connect(_on_theme_selected)

# The tab titles are set manually: Godot takes them from the node NAMES, and node
# names are not translated. The titles are translated here by tr() calls with
# literals — otherwise neither the catalog builder nor the .pot generation
# in the editor would see them. The function is called both when opening the
# window and on a language change.
func _apply_tab_titles():
    if not tab_container:
        return
    var titles := [
        tr("Game"),
        tr("Video"),
        tr("Audio"),
        tr("Interface"),
        tr("Appearance"),
    ]
    for i in min(titles.size(), tab_container.get_tab_count()):
        tab_container.set_tab_title(i, titles[i])

# Fills the resolution dropdown with the presets that fit the monitor. The first item keeps
# the monitor's own resolution; its metadata is empty, which is also how it is saved.
func _setup_resolution_option():
    if resolution_option_button == null:
        return
    var saved := str(config.get_value(DisplaySettings.SECTION, DisplaySettings.KEY_RESOLUTION, ""))
    resolution_option_button.clear()
    resolution_option_button.add_item(tr("Monitor native"), 0)
    resolution_option_button.set_item_metadata(0, "")
    var selected := 0
    for size in DisplaySettings.available_resolutions():
        var text := DisplaySettings.resolution_to_text(size)
        var index := resolution_option_button.item_count
        resolution_option_button.add_item(text, index)
        resolution_option_button.set_item_metadata(index, text)
        if text == saved:
            selected = index
    if not saved.is_empty() and selected == 0:
        # A saved resolution the current monitor does not offer stays selectable: the
        # player can still see the choice the settings file holds.
        var index := resolution_option_button.item_count
        resolution_option_button.add_item(saved, index)
        resolution_option_button.set_item_metadata(index, saved)
        selected = index
    resolution_option_button.select(selected)

# Fills the window mode dropdown. The value of an item is the string saved in settings.cfg.
func _setup_window_mode_option():
    if window_mode_option_button == null:
        return
    var saved := str(config.get_value(DisplaySettings.SECTION, DisplaySettings.KEY_WINDOW_MODE,
        DisplaySettings.DEFAULT_MODE))
    window_mode_option_button.clear()
    var modes := [
        [tr("Fullscreen (borderless)"), DisplaySettings.MODE_FULLSCREEN],
        [tr("Maximized"), DisplaySettings.MODE_MAXIMIZED],
        [tr("Windowed"), DisplaySettings.MODE_WINDOWED],
    ]
    var selected := 0
    for i in modes.size():
        window_mode_option_button.add_item(str(modes[i][0]), i)
        window_mode_option_button.set_item_metadata(i, str(modes[i][1]))
        if str(modes[i][1]) == saved:
            selected = i
    window_mode_option_button.select(selected)

func _on_resolution_selected(_index: int):
    save_settings()
    _apply_display_settings()

func _on_window_mode_selected(_index: int):
    save_settings()
    _apply_display_settings()

# Fills the VSync dropdown. The value of an item is the string saved in settings.cfg.
func _setup_vsync_option():
    if vsync_option_button == null:
        return
    var saved := str(config.get_value(DisplaySettings.SECTION, DisplaySettings.KEY_VSYNC,
        DisplaySettings.DEFAULT_VSYNC))
    vsync_option_button.clear()
    var labels := [tr("Disabled"), tr("Enabled"), tr("Adaptive"), tr("Mailbox")]
    var selected := 0
    for i in DisplaySettings.VSYNC_MODES.size():
        var id := str(DisplaySettings.VSYNC_MODES[i][0])
        vsync_option_button.add_item(labels[i], i)
        vsync_option_button.set_item_metadata(i, id)
        if id == saved:
            selected = i
    vsync_option_button.select(selected)

# Fills the frame rate dropdown. The metadata is the limit passed to Engine.max_fps.
func _setup_fps_limit_option():
    if fps_limit_option_button == null:
        return
    var saved := int(config.get_value(DisplaySettings.SECTION, DisplaySettings.KEY_FPS_LIMIT,
        DisplaySettings.DEFAULT_FPS_LIMIT))
    fps_limit_option_button.clear()
    var selected := 0
    for i in DisplaySettings.FPS_LIMITS.size():
        var limit: int = DisplaySettings.FPS_LIMITS[i]
        var label := tr("No limit") if limit == 0 else tr("%d FPS") % limit
        fps_limit_option_button.add_item(label, i)
        fps_limit_option_button.set_item_metadata(i, limit)
        if limit == saved:
            selected = i
    fps_limit_option_button.select(selected)

func _on_vsync_selected(_index: int):
    save_settings()
    _apply_display_settings()

func _on_fps_limit_selected(_index: int):
    save_settings()
    _apply_display_settings()

# Fills the interface size dropdown. The labels are percentages of the size the interface is
# designed for; the metadata is the multiplier kept in settings.cfg. The numbers need no
# translation, so they are built here rather than stored in the translated scene.
func _setup_ui_scale_option():
    if ui_scale_option_button == null:
        return
    ui_scale_option_button.clear()
    for value in UiScale.STEPS:
        var index := ui_scale_option_button.item_count
        var label := "%d%%" % int(round(value * 100.0))
        if UiScale.is_experimental(value):
            label += " · " + tr("Experimental")
        ui_scale_option_button.add_item(label, index)
        ui_scale_option_button.set_item_metadata(index, value)
    var saved := UiScale.read_saved()
    if UiScale.is_step(saved):
        ui_scale_option_button.select(UiScale.step_index(saved))
    else:
        # A hand-edited value stays visible and selectable instead of being silently replaced
        # by the nearest offered step when the window opens.
        var index := ui_scale_option_button.item_count
        var label := "%d%%" % int(round(saved * 100.0))
        if UiScale.is_experimental(saved):
            label += " · " + tr("Experimental")
        ui_scale_option_button.add_item(label, index)
        ui_scale_option_button.set_item_metadata(index, saved)
        ui_scale_option_button.select(index)
    # select() does not send item_selected: opening the window shows the applied size
    # instead of choosing it again.

func _on_ui_scale_selected(index: int):
    UiScale.save(float(ui_scale_option_button.get_item_metadata(index)))
    # The main menu cancels the global scale for its splash, so it has to re-read the new
    # multiplier. The window itself is a sibling of that splash and keeps scaling normally.
    var main_menu := get_tree().root.find_child("MainMenu", true, false)
    if main_menu != null and main_menu.has_method("apply_ui_scale_compensation"):
        main_menu.apply_ui_scale_compensation()

func _apply_display_settings():
    if resolution_option_button == null or window_mode_option_button == null:
        return
    var mode := str(window_mode_option_button.get_item_metadata(
        window_mode_option_button.selected))
    var resolution := str(resolution_option_button.get_item_metadata(
        resolution_option_button.selected))
    DisplaySettings.apply(mode, DisplaySettings.text_to_resolution(resolution))
    if vsync_option_button != null:
        DisplaySettings.apply_vsync(str(vsync_option_button.get_item_metadata(
            vsync_option_button.selected)))
    if fps_limit_option_button != null:
        DisplaySettings.apply_fps_limit(int(fps_limit_option_button.get_item_metadata(
            fps_limit_option_button.selected)))

# Fills in the language dropdown and sets the saved choice in it.
# The value of an item is a language code; the "system language" item is stored as "system".
func _setup_language_option():
    var languages: Array = LocalizationManager.available_languages()
    var selected := LocalizationManager.get_stored_locale()
    var selected_index := 0
    language_option_button.clear()
    for i in languages.size():
        var code := str(languages[i]["code"])
        if code == selected:
            selected_index = i
        language_option_button.add_item(LocalizationManager.get_language_label(code), i)
        language_option_button.set_item_metadata(i, code)
    language_option_button.select(selected_index)
    # The signal is connected in _ready, and select() does not send it: when the settings
    # window opens the language is not re-chosen, but simply shown as the current one.

func _on_language_selected(index: int):
    var code := str(language_option_button.get_item_metadata(index))
    if LocalizationManager.set_locale(code):
        # The tab titles and the scene text are translated by Godot itself on the
        # TranslationServer notification, while the language list and the label of
        # the selected item depend on LocalizationManager — we update them manually.
        _apply_tab_titles()
        _setup_language_option()
        # The font list is rebuilt as well: a change of the language may make the
        # current font give way (FontManager checks the letters of the language),
        # and the shown choice has to be the applied one.
        _setup_font_option()
        # The names of the themes are catalog strings too, so the list is rebuilt
        # for the new language.
        _setup_theme_option()
        # The labels of the Video dropdowns are catalog strings as well.
        _setup_resolution_option()
        _setup_window_mode_option()
        _setup_vsync_option()
        _setup_fps_limit_option()
        # The names of the types of icons and the "Original icons" item are catalog
        # strings: the rows of the tilesets are rebuilt in the new language as well.
        _setup_tileset_options()

# Fills in the font dropdown and sets the applied font in it. The value of an item is
# the family name — the name the font itself declares, therefore it is not translated.
# The list is rebuilt from the folders every time: a font copied into the folder while
# the game is running appears here without a restart.
func _setup_font_option():
    FontManager.rescan()
    var fonts: Array = FontManager.available_fonts()
    var current := FontManager.current_family
    font_option_button.clear()
    if fonts.is_empty():
        return
    var selected_index := 0
    for i in fonts.size():
        var family := str(fonts[i])
        if family == current:
            selected_index = i
        font_option_button.add_item(family, i)
        font_option_button.set_item_metadata(i, family)
    font_option_button.select(selected_index)
    # The signal is connected in _ready, and select() does not send it: when the settings
    # window opens the font is not re-chosen, but simply shown as the current one.

func _on_font_selected(index: int):
    var family := str(font_option_button.get_item_metadata(index))
    if not FontManager.set_font(family):
        # The file disappeared between the scan and the click: the list is stale.
        _setup_font_option()

# Fills in the theme dropdown and sets the applied preset in it. The value of an item is
# the preset id; the label is the name_key of the preset, translated by the catalog.
# The list is rebuilt from the folder every time, as with the fonts: a preset copied into
# the folder while the game is running appears here without a restart.
func _setup_theme_option():
    ThemeManager.rescan()
    var presets: Array = ThemeManager.available_presets()
    var current := ThemeManager.get_preset_id()
    theme_option_button.clear()
    var selected_index := 0
    for i in presets.size():
        var id := str(presets[i]["id"])
        if id == current:
            selected_index = i
        # The key goes to tr() in a variable of its own: the catalog builder reads the
        # literal arguments of a tr() call as source strings, and an index inside the call
        # would land in the catalog as a message of its own.
        var name_key := str(presets[i]["name_key"])
        theme_option_button.add_item(tr(name_key), i)
        theme_option_button.set_item_metadata(i, id)
    theme_option_button.select(selected_index)
    # select() does not send item_selected: opening the window shows the applied theme
    # instead of choosing it again.

func _on_theme_selected(index: int):
    var id := str(theme_option_button.get_item_metadata(index))
    if not ThemeManager.set_preset(id):
        # The file disappeared between the scan and the click: the list is stale.
        _setup_theme_option()

# Fills in the rows of the tilesets: one row per type of icons, "Icon sets" being one
# section of the settings rather than seven. Every type keeps its row even when no set is
# drawn for it — the rows are what tells the player which kinds of pictures a set can
# replace, and an empty folder is no reason to hide the whole section.
#
# The value of an item is the id of the set, "" for the vanilla icons. A type starts on the
# set the folder rule gave it (TilesetManager.get_choice), so an installed set is already
# applied when the window is opened for the first time.
func _setup_tileset_options():
    if tileset_grid == null:
        return
    for child in tileset_grid.get_children():
        # Removed at once and freed later: a queued child still counts for the grid, and the
        # rebuilt rows would land next to the old ones.
        tileset_grid.remove_child(child)
        child.queue_free()
    _tileset_options.clear()
    for type_name in TilesetManager.TYPES:
        tileset_grid.add_child(_make_tileset_label(type_name))
        tileset_grid.add_child(_make_tileset_option(type_name))
    if tileset_hint != null:
        # The hint of the scene assumes a set is installed; with an empty folder it would
        # describe a choice that is not there to make.
        if TilesetManager.available_tilesets().is_empty():
            # One literal, however long the line: the catalog is built from the arguments of
            # tr(), and a string glued from pieces would land there in pieces.
            tileset_hint.text = tr("No icon sets found: the tilesets folder is empty, so every type keeps the original pictures. A set put in that folder appears in these lists.")
        else:
            tileset_hint.text = _tileset_hint_with_sets

func _make_tileset_label(type_name: String) -> Label:
    var label := Label.new()
    label.text = _tileset_type_label(type_name)
    label.custom_minimum_size = Vector2(150, 0)
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    return label

func _make_tileset_option(type_name: String) -> OptionButton:
    var option := OptionButton.new()
    option.custom_minimum_size = Vector2(260, 0)
    option.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    option.add_item(tr("Original icons"))
    option.set_item_metadata(0, "")
    var current := TilesetManager.get_choice(type_name)
    var selected := 0
    for record in TilesetManager.available_tilesets():
        if not (record["types"] as Array).has(type_name):
            continue
        var index := option.item_count
        option.add_item(str(record["name"]))
        option.set_item_metadata(index, str(record["id"]))
        if str(record["id"]) == current:
            selected = index
    option.select(selected)
    # A type no set is drawn for has one item only: the row still says which pictures are
    # used, but there is nothing to choose, and a list of one item would pretend otherwise.
    option.disabled = option.item_count == 1
    # select() does not send item_selected: opening the window shows the applied set instead
    # of choosing it again.
    option.item_selected.connect(_on_tileset_selected.bind(type_name))
    _tileset_options[type_name] = option
    return option

# The name of a type of icons in the interface language. Every label is a tr() call with a
# literal: the catalog is built from the literal arguments, and a table of untranslated
# strings would never reach it.
func _tileset_type_label(type_name: String) -> String:
    match type_name:
        "resources":
            return tr("Resources")
        "buildings":
            return tr("Buildings")
        "technologies":
            return tr("Technologies")
        "terrains":
            return tr("Terrains")
        "improvements":
            return tr("Improvements")
        "special_actions":
            return tr("Special actions")
        "misc":
            return tr("Miscellaneous")
    return type_name

func _on_tileset_selected(index: int, type_name: String):
    var option: OptionButton = _tileset_options.get(type_name)
    if option == null:
        return
    if not TilesetManager.set_choice(type_name, str(option.get_item_metadata(index))):
        # The set disappeared between the scan and the click: the list is stale.
        _setup_tileset_options()

func load_settings():
    var err = config.load("user://settings.cfg")
    if err == OK:
        hex_borders_checkbox.button_pressed = config.get_value("interface", "show_hex_borders", true)
        edge_scrolling_checkbox.button_pressed = config.get_value("interface", "edge_scrolling", true)
        edge_scroll_speed_slider.value = config.get_value("interface", "edge_scroll_speed", 300.0)
        tooltip_delay_slider.value = config.get_value("interface", "tooltip_delay", 0.5)
        extended_tooltip_delay_slider.value = config.get_value("interface", "extended_tooltip_delay", 1.0)
        building_detail_delay_slider.value = config.get_value(
            "interface", "building_detail_delay", 0.5)
        resource_display_interval_slider.value = config.get_value(
            "game", "resource_display_interval", 1.0)
        hud_message_duration_slider.value = config.get_value(
            "interface", "hud_message_duration", 3.0)
        clock_checkbox.button_pressed = config.get_value("interface", "show_clock", true)
        fps_checkbox.button_pressed = config.get_value("interface", "show_fps", true)
    else:
        hex_borders_checkbox.button_pressed = true
        edge_scrolling_checkbox.button_pressed = true
        edge_scroll_speed_slider.value = 300.0
        tooltip_delay_slider.value = 0.5
        extended_tooltip_delay_slider.value = 1.0
        building_detail_delay_slider.value = 0.5
        resource_display_interval_slider.value = 1.0
        hud_message_duration_slider.value = 3.0
        clock_checkbox.button_pressed = true
        fps_checkbox.button_pressed = true
    # The minimum value of the extended tooltip cannot be less than the main one
    extended_tooltip_delay_slider.min_value = tooltip_delay_slider.value
    _update_edge_scroll_speed_label()
    _update_tooltip_delay_label()
    _update_extended_tooltip_delay_label()
    _update_building_detail_delay_label()
    _update_resource_display_interval_label()
    _update_hud_message_duration_label()
    _refresh_setting_blocks()

# The setting blocks (scripts/settings_block.gd) are children of the menu and know
# their own gates. The menu only tells them that a fresh set of values is in: the
# saved state is assigned to button_pressed, which does not emit toggled, so a block
# would otherwise keep the state of the scene default.
func _refresh_setting_blocks() -> void:
    for child in get_children():
        if child is SettingsBlock:
            child.refresh()

func save_settings():
    # We re-read the file before writing: LocalizationManager writes the language here,
    # and without re-reading its key would be overwritten by our values.
    config.load("user://settings.cfg")
    config.set_value("interface", "show_hex_borders", hex_borders_checkbox.button_pressed)
    config.set_value("interface", "edge_scrolling", edge_scrolling_checkbox.button_pressed)
    config.set_value("interface", "edge_scroll_speed", edge_scroll_speed_slider.value)
    config.set_value("interface", "tooltip_delay", tooltip_delay_slider.value)
    config.set_value("interface", "extended_tooltip_delay", extended_tooltip_delay_slider.value)
    config.set_value("interface", "building_detail_delay", building_detail_delay_slider.value)
    config.set_value("game", "resource_display_interval", resource_display_interval_slider.value)
    config.set_value("interface", "hud_message_duration", hud_message_duration_slider.value)
    config.set_value("interface", "show_clock", clock_checkbox.button_pressed)
    config.set_value("interface", "show_fps", fps_checkbox.button_pressed)
    if resolution_option_button != null and window_mode_option_button != null:
        config.set_value(DisplaySettings.SECTION, DisplaySettings.KEY_RESOLUTION,
            str(resolution_option_button.get_item_metadata(resolution_option_button.selected)))
        config.set_value(DisplaySettings.SECTION, DisplaySettings.KEY_WINDOW_MODE,
            str(window_mode_option_button.get_item_metadata(window_mode_option_button.selected)))
    if vsync_option_button != null:
        config.set_value(DisplaySettings.SECTION, DisplaySettings.KEY_VSYNC,
            str(vsync_option_button.get_item_metadata(vsync_option_button.selected)))
    if fps_limit_option_button != null:
        config.set_value(DisplaySettings.SECTION, DisplaySettings.KEY_FPS_LIMIT,
            int(fps_limit_option_button.get_item_metadata(fps_limit_option_button.selected)))
    config.save("user://settings.cfg")

func _apply_to_game():
    # We find the main game scene (MainMap) and update its settings
    var root = get_tree().root
    var main_map = root.find_child("MainMap", true, false)
    if main_map and main_map.has_method("apply_settings"):
        main_map.apply_settings()

func _on_hex_borders_toggled(_pressed: bool):
    save_settings()
    _apply_to_game()

func _on_edge_scrolling_toggled(_pressed: bool):
    save_settings()
    _apply_to_game()

func _on_edge_scroll_speed_changed(_value: float):
    _update_edge_scroll_speed_label()
    save_settings()
    _apply_to_game()

func _on_tooltip_delay_changed(_value: float):
    _update_tooltip_delay_label()
    # The minimum value of the extended tooltip cannot be less than the main one
    if extended_tooltip_delay_slider.value < tooltip_delay_slider.value:
        extended_tooltip_delay_slider.value = tooltip_delay_slider.value
    save_settings()
    _apply_to_game()

func _on_extended_tooltip_delay_changed(_value: float):
    # We do not allow it to go below the main delay
    if extended_tooltip_delay_slider.value < tooltip_delay_slider.value:
        extended_tooltip_delay_slider.value = tooltip_delay_slider.value
    _update_extended_tooltip_delay_label()
    save_settings()
    _apply_to_game()

func _on_building_detail_delay_changed(_value: float):
    _update_building_detail_delay_label()
    save_settings()
    _apply_to_game()

func _on_resource_display_interval_changed(_value: float):
    _update_resource_display_interval_label()
    save_settings()
    _apply_to_game()

func _on_hud_message_duration_changed(_value: float):
    _update_hud_message_duration_label()
    save_settings()
    _apply_to_game()

func _on_clock_toggled(_pressed: bool):
    save_settings()
    _apply_to_game()

func _on_fps_toggled(_pressed: bool):
    save_settings()
    _apply_to_game()

# The slider step is 50 pixels per second: the whole number is exactly enough.
func _update_edge_scroll_speed_label():
    var speed = int(round(edge_scroll_speed_slider.value))
    edge_scroll_speed_value_label.text = tr("%d px/s") % speed

func _update_tooltip_delay_label():
    var seconds = snappedf(tooltip_delay_slider.value, 0.25)
    tooltip_delay_value_label.text = tr("%.2f sec") % seconds

func _update_extended_tooltip_delay_label():
    var seconds = snappedf(extended_tooltip_delay_slider.value, 0.25)
    extended_tooltip_delay_value_label.text = tr("%.2f sec") % seconds

func _update_building_detail_delay_label():
    var seconds = snappedf(building_detail_delay_slider.value, 0.25)
    building_detail_delay_value_label.text = tr("%.2f sec") % seconds

func _update_resource_display_interval_label():
    # The slider step is 1 second, fractional values do not happen (see CityData:
    # the simulation tick = 1 sec, a fractional interval would give an uneven rhythm).
    var seconds = int(round(resource_display_interval_slider.value))
    resource_display_interval_value_label.text = tr("%d sec") % seconds

func _update_hud_message_duration_label():
    # The slider step is half a second: one decimal is exactly enough.
    var seconds = snappedf(hud_message_duration_slider.value, 0.5)
    hud_message_duration_value_label.text = tr("%.1f sec") % seconds

func _on_back_pressed():
    hide()

# ESC belongs to the window while it is open: neither the map nor the window
# underneath (the pause menu) sees the key. Closing is exactly hiding — the pause
# menu, if it is the host, returns through the visibility_changed signal.
func _unhandled_input(event: InputEvent) -> void:
    if not visible:
        return
    if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        get_viewport().set_input_as_handled()
        hide()
