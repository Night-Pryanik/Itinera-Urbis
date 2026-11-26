extends Control

# The cross-reference validator for data/*.json. It is declared via preload, and
# not as an autoload: it does not keep state between calls, and it is needed only by
# the main menu. An autoload for a single call would keep a set of
# rules in memory with no consumer at all.
const DataValidator = preload("res://scripts/data_validator.gd")
const DataProblemsWindow = preload("res://scripts/data_problems_window.gd")
const AboutWindow = preload("res://scripts/about_window.gd")
const UiHelpers = preload("res://scripts/ui_helpers.gd")
const UI_THEME = preload("res://scripts/ui_theme.gd")
const ModListScene = preload("res://scenes/mod_list.tscn")
const WorldPreview = preload("res://scripts/world_preview.gd")
const DisplaySettings = preload("res://scripts/display_settings.gd")
const UiScale = preload("res://scripts/ui_scale.gd")
const AndroidBack = preload("res://scripts/android_back.gd")

# The width of the city name field. It does not follow anything else: the name column is
# sized to it.
const NAME_FIELD_WIDTH := 340

# The content of the new game window. The width comes from the mod list, which is the
# widest of the tabs; the height is chosen for the settings list and the map preview, and
# the window keeps it on every tab.
const DIALOG_CONTENT_WIDTH := 860
const DIALOG_CONTENT_HEIGHT := 520
const DIALOG_EDGE_MARGIN := 10
# The least room a page keeps when the window is fitted to a small screen.
const PAGE_MIN_WIDTH := 160
const PAGE_MIN_HEIGHT := 120

# The space kept between a scrollbar and the rows it scrolls, and beside the controls of
# the picture. The picture column is only as wide as its widest control plus these sides.
const SCROLL_GUTTER := 20
# The room beside the window edge, before the text of a page starts.
const PAGE_SIDE_PADDING := 8
const PREVIEW_SIDE_MARGIN := 8
const PREVIEW_MIN_HEIGHT := 240
# The width of the picture when both columns have room. In a squeezed window it is
# narrowed down to the regenerate button instead.
const PREVIEW_WIDTH := 360
const SETTING_ROW_HEIGHT := 32
# Long labels wrap instead of making the whole settings column wide. The controls then
# sit closer to their text and the picture column keeps more room for its legend.
const SETTING_LABEL_WIDTH := 160
const SETTING_CONTROL_HEIGHT := 30
const STEP_FIELD_WIDTH := 58
const MIN_NUMBER_FIELD_WIDTH := 32
# A few extra canvas units at a zoomed interface keep four-character values such as
# "0.03" visible in full.
const NUMBER_FIELD_SCALE_EXTRA := 4

# The relief of the picture is the generator's own work on the whole map, and a giant map costs
# seconds per rebuild. It is kept while the settings that shape it are unchanged, and a number
# being typed rebuilds it once the typing pauses rather than on every keystroke.
const RELIEF_CACHE_LIMIT := 8
const RIVER_CACHE_LIMIT := 16
const PREVIEW_DEBOUNCE := 0.2

# From this side of the map up, the picture is built in stages, a frame apart (see
# WorldPreview.RELIEF_STAGES): a map that is built in a tenth of a second is built on the spot, and
# a huge one is built while the window keeps repainting.
const STAGED_PREVIEW_MAP_SIZE := 150

const TAB_CITY := 0
const TAB_WORLD := 1
const TAB_MODS := 2

# The map size presets offered in the world settings (the square side in hexes), and the
# bounds of the custom size. The player chooses one for a new game; the default is medium.
const MAP_SIZE_PRESETS: Array[int] = [30, 60, 100, 150, 200]
const MIN_MAP_SIZE := 10
const MAX_MAP_SIZE := 200
const DEFAULT_MAP_SIZE := 60
# One hex per click would barely move a side that spans 10..200, so a click moves it by ten.
const CUSTOM_SIZE_STEP := 10

# The number of towns a new world is generated with, and the lower bound of the field. The
# generator places as many as the map allows: a crowded map simply ends up with fewer.
const DEFAULT_TOWN_COUNT := 16
const MIN_TOWN_COUNT := 0
# The ceiling follows the map: one town per this many hexes, which is 40 on the medium map and
# 111 on a 100×100 one. A fixed ceiling would either choke a giant map or flood a small one.
const HEXES_PER_TOWN := 90

# The resource density presets, in the order of the dropdown: the multiplier applied to the
# number of specimens each resource spawns. The default is the standard density.
const RESOURCE_DENSITY_PRESETS: Array[float] = [0.5, 1.0, 1.5, 2.0, 3.0, 5.0]
const DEFAULT_RESOURCE_DENSITY := 1.0

# The climate the city starts in, in the order of the dropdown. The values are the temperature
# belts of the generator; "random" rolls the latitude of the city as usual.
const CLIMATE_PRESETS: Array[String] = ["random", "cold", "mild", "subtropical", "tropical"]
const DEFAULT_CLIMATE := "random"

# The sea generation modes, in the order of the dropdown. The values are the "mode" field of
# the sea configuration (CityData.world_sea); "none" leaves the map without a sea.
const SEA_MODES: Array[String] = ["none", "edge", "noise"]
const SEA_MODE_EDGE := "edge"
const SEA_MODE_NOISE := "noise"

# The kinds of the controls of the "Seas" section: a whole number, a fraction, a pair of
# whole numbers ("from" and "to") and a checkbox.
const SEA_INT := "int"
const SEA_FLOAT := "float"
const SEA_PAIR := "pair"
const SEA_CHECK := "check"

# The counts that follow the map size are averages, not promises: a world rolls its own number
# of rivers around them. A spread of 30% keeps the worlds recognisably similar without making
# them identical. The minimum lengths are constraints, so they are never rolled.
const RIVER_COUNT_KEYS: Array[String] = ["num_main_rivers", "num_tributaries"]
const RIVER_COUNT_SPREAD := 0.3

@onready var title_logo: TextureRect = $TitleLogo
@onready var continue_button = $VBoxContainer/ContinueButton
@onready var new_game_button = $VBoxContainer/NewGameButton
@onready var load_game_button = $VBoxContainer/LoadGameButton
@onready var settings_button = $VBoxContainer/SettingsButton
@onready var about_button = $VBoxContainer/AboutButton
@onready var quit_button = $VBoxContainer/QuitButton

# The splash screen keeps the size it was designed for: a large interface scale must not
# blow up the logo or push the buttons into the top left corner. The canvas scale is global,
# so the menu cancels it in the offsets of these nodes and the font sizes of the buttons.
# The settings window is a sibling, not one of them — it still follows the chosen size.
var _title_offsets: Array[float] = []
var _menu_offsets: Array[float] = []
var _button_font_sizes: Dictionary = {}
var _button_outlines: Dictionary = {}

# The window of the saves, created on the first click on "Load game".
var save_load_window: CanvasLayer = null
# The dialog of a new game: one window with a tab per question (the city, the world, the
# mods). It is built once and kept — the choice of mods survives a "Back".
var new_game_dialog: ConfirmationDialog = null
var tab_container: TabContainer = null
var settings_padding: MarginContainer = null
var settings_column: VBoxContainer = null
var preview_scroll: ScrollContainer = null
var preview_padding: MarginContainer = null
var preview_column: Control = null
var city_preview_scroll: ScrollContainer = null
var city_preview_padding: MarginContainer = null
var city_preview_column: Control = null
var regenerate_button: Button = null
var city_name_edit: LineEdit = null
# Every numeric field of the world settings. Their canvas width follows the interface
# multiplier, so a large size does not turn a two-digit value into a huge input box.
var number_fields: Array[LineEdit] = []
# The world settings of a new game (the map size and the number of towns). They are read
# once, when the game starts.
var map_size_option: OptionButton = null
var custom_size_row: HBoxContainer = null
var custom_size_edit: LineEdit = null
var town_count_edit: LineEdit = null
var town_count_minus: Button = null
var town_count_plus: Button = null
# The count of towns can follow the map size instead of being chosen. While it does, the
# field is read-only and the step buttons are off. The link button is the toggle.
var proportional_check: Button = null
# How many resource specimens the world spawns, as a multiplier of the standard amount.
var resource_density_option: OptionButton = null
# The climate belt the city starts in.
var climate_option: OptionButton = null
# The "Seas" section of the world settings: the mode dropdown, one entry per sea setting
# (keyed by its field in CityData.world_sea) and the rows with the modes they belong to.
var sea_mode_option: OptionButton = null
var sea_controls: Dictionary = {}
var sea_rows: Array = []
# The "Rivers" section of the world settings, keyed by its field in CityData.world_rivers.
var river_controls: Dictionary = {}
# The rivers can follow the map size like the towns do. While they do, the two count fields
# are read only and their step buttons are off. The link button is the toggle.
var proportional_river_check: Button = null
# The map previews, one on the City tab and one on the World tab. Both show the same world,
# so they are refreshed together.
var world_previews: Array = []
var mod_list = null
# The preview seed stays fixed while settings change, keeping those changes comparable. The
# player can reroll it explicitly with the button beside either preview.
var _preview_seed: int = 0
# The reliefs already built and the rivers drawn over them, oldest first; the timer of a rebuild
# waiting for the typing to pause; and the build in flight, when the picture is being built stage by
# stage (empty when nothing is running).
var _relief_cache: Dictionary = {}
var _relief_order: Array[String] = []
var _river_cache: Dictionary = {}
var _river_order: Array[String] = []
var _preview_timer: Timer = null
var _preview_build: Dictionary = {}

func _ready():
    AndroidBack.disable_auto_quit()
    # The saved window is applied before the menu is shown, so a player who chose a
    # resolution or a window mode does not see the project default first.
    DisplaySettings.apply_saved()
    # The interface scale belongs to the root window and is carried into every scene. Applied
    # here, before the menu is shown, so a player who enlarged it never sees the old size first.
    UiScale.apply_saved()
    apply_ui_scale_compensation()
    # The data comes first: the tooltip of "Continue game" names the era of the save,
    # and on a cold start the menu is the first scene — GameData is not loaded yet.
    _check_game_data()
    _refresh_save_buttons()

    continue_button.pressed.connect(_on_continue_game)
    new_game_button.pressed.connect(_on_new_game)
    load_game_button.pressed.connect(_on_load_game)
    settings_button.pressed.connect(_on_settings)
    about_button.pressed.connect(_on_about)
    quit_button.pressed.connect(_on_quit)
    get_viewport().size_changed.connect(_on_viewport_resized)

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_GO_BACK_REQUEST:
        AndroidBack.forward_to_escape()

# Divides the offsets and button font sizes of the splash by the interface multiplier, so
# the logo and the buttons keep their physical size however large the in-game interface is
# made. The first call remembers the values written in the scene; the following ones only
# scale them.
func apply_ui_scale_compensation() -> void:
    if title_logo == null or continue_button == null:
        return
    var multiplier: float = maxf(UiScale.current(), 0.01)
    var factor := 1.0 / multiplier
    if _title_offsets.is_empty():
        _title_offsets = [title_logo.offset_left, title_logo.offset_top,
                title_logo.offset_right, title_logo.offset_bottom]
        var box := $VBoxContainer as Control
        _menu_offsets = [box.offset_left, box.offset_top, box.offset_right, box.offset_bottom]
        for button in [continue_button, new_game_button, load_game_button,
                settings_button, about_button, quit_button]:
            _button_font_sizes[button] = button.get_theme_font_size("font_size")
            _button_outlines[button] = button.get_theme_constant("outline_size")
    title_logo.offset_left = _title_offsets[0] * factor
    title_logo.offset_top = _title_offsets[1] * factor
    title_logo.offset_right = _title_offsets[2] * factor
    title_logo.offset_bottom = _title_offsets[3] * factor
    var menu_box := $VBoxContainer as Control
    menu_box.offset_left = _menu_offsets[0] * factor
    menu_box.offset_top = _menu_offsets[1] * factor
    menu_box.offset_right = _menu_offsets[2] * factor
    menu_box.offset_bottom = _menu_offsets[3] * factor
    for button in _button_font_sizes.keys():
        var size: int = _button_font_sizes[button]
        button.add_theme_font_size_override("font_size",
                maxi(8, roundi(float(size) * factor)))
        # The outline is measured in canvas pixels too: without this the smaller letters
        # keep the old, now relatively twice as thick black rim.
        button.add_theme_constant_override("outline_size",
                maxi(1, roundi(float(_button_outlines[button]) * factor)))

# Both items that need a save are gated by the same fact. The tooltip of "Continue game"
# names the save the click will take, so the button cannot promise one game and load
# another. The state is re-read after the window is closed as well: the last save can be
# deleted from its list.
func _refresh_save_buttons():
    var resume := SaveManager.get_resume_save()
    continue_button.disabled = resume.is_empty()
    continue_button.tooltip_text = UiHelpers.save_tooltip(resume)
    load_game_button.disabled = not SaveManager.has_save()

# Checks the integrity of the game data before the start of a game.
#
# The main menu is the first scene (run/main_scene in project.godot), therefore
# the check fires immediately after the game starts and before the player begins
# building: the MainMap scene with map generation has not been created yet.
#
# The problems found are shown in a WINDOW, and not just written to the console: the
# data author needs to see which identifier is missing and in which field it was
# referenced. Only a short summary is duplicated to the console — so that
# the error is not lost when running in headless mode.
func _check_game_data():
    # The validator needs the full set of data. Usually it is already loaded
    # (for example, when returning from a game), but on a cold start — it is not.
    if not GameData.data_loaded:
        GameData.load_all_data()

    var problems: Array = DataValidator.new().validate(GameData)
    if problems.is_empty():
        return

    # We hang the window on the window root, and not on the main menu: the anchors of
    # the menu Control are not set to the screen edges (scenes/main_menu.tscn), and the overlay
    # would cover only part of the screen.
    #
    # The addition is deferred: this code runs inside the _ready() of the main
    # menu, which means the tree root is still setting up its children
    # at that moment (it is adding the main_menu scene) — a direct add_child() on the root
    # is rejected with "Parent node is busy setting up children". We fill
    # the contents on the ready signal: before it the _ready() of the window has not built
    # the layout yet, and show_problems() would fall on null nodes.
    var window = Control.new()
    window.set_script(DataProblemsWindow)
    window.ready.connect(window.show_problems.bind(problems), CONNECT_ONE_SHOT)
    get_tree().root.add_child.call_deferred(window)

    var counts := DataValidator.new().count_by_kind(problems)
    print("Game data check: found %d problems (%s)" % [
        problems.size(), str(counts)])
    for problem in problems:
        print("  - ", problem["message"])

# The fast path: no window and no questions. The tooltip has already told the player
# which save the click takes.
func _on_continue_game():
    # The screen goes up before the read: restoring the save freezes the tree for a
    # while, and without the screen the click looks like a hang.
    var overlay := LoadingOverlay.present(get_tree(), tr("Loading game..."))
    overlay.set_status(tr("Reading save..."))
    # The first yield resumes in the same frame as the click, before its draw; only the
    # second one guarantees the screen is drawn before the read freezes the tree.
    await get_tree().process_frame
    await get_tree().process_frame
    if SaveManager.load_game():
        get_tree().change_scene_to_file("res://scenes/MainMap.tscn")
    else:
        # The save vanished between the refresh and the click: the menu must not keep
        # offering a game that cannot be loaded.
        overlay.queue_free()
        _refresh_save_buttons()

# A new game is one window with three tabs: the city, the world, the mods. The tab that
# opens is the city, because the name is the only thing the player has to type; the other
# two have working defaults.
func _on_new_game():
    if new_game_dialog == null:
        _build_new_game_dialog()
    mod_list.open(ModManager.active_ids)
    _refresh_mods_tab()
    city_name_edit.text = tr("City")
    tab_container.current_tab = TAB_CITY
    _popup_new_game_dialog()
    _refresh_town_row()
    _refresh_river_fields()
    _refresh_sea_rows()
    _preview_seed = _roll_preview_seed()
    _refresh_preview()
    city_name_edit.grab_focus()
    city_name_edit.select_all()

# A phone can be turned while the dialog is open, and the room it has changes with the
# canvas. The fit is recomputed so the buttons never end up below the new edge.
func _on_viewport_resized() -> void:
    if new_game_dialog != null and new_game_dialog.visible:
        _popup_new_game_dialog()

# The window keeps ONE size on all three tabs: a window that resized itself when the
# player switched tabs would jump under the cursor. The pages keep their controls at the
# chosen interface size and scroll inside the room the window has.
#
# The frame of a window (the title bar and the shadow) is drawn OUTSIDE the rect this
# node reports, and the frame is what the player sees, so the margins are kept for the
# decorated rect: a window sized by the bare rect alone would touch the screen edge.
func _popup_new_game_dialog():
    tab_container.custom_minimum_size = Vector2(DIALOG_CONTENT_WIDTH, DIALOG_CONTENT_HEIGHT)
    new_game_dialog.reset_size()
    new_game_dialog.popup_centered()

    var screen := Vector2i(get_viewport().get_visible_rect().size)
    if screen.x <= 0 or screen.y <= 0:
        return
    var frame := new_game_dialog.get_size_with_decorations() - new_game_dialog.size
    var room := Vector2(screen - Vector2i(DIALOG_EDGE_MARGIN * 2, DIALOG_EDGE_MARGIN * 2) - frame)
    # The title bar, the panel and the buttons take their share before the tabs get the rest.
    var chrome := Vector2(new_game_dialog.size) - Vector2(tab_container.custom_minimum_size)
    var available := room - chrome
    _apply_number_field_widths()
    # Measure the two columns at their designed widths, then give the window the room
    # they need when the screen has it: a wide window has no reason to scroll sideways.
    _apply_world_fit(false)
    var natural_width := settings_padding.get_combined_minimum_size().x \
            + preview_padding.get_combined_minimum_size().x + 16.0 + 24.0
    var wanted := Vector2(maxf(float(DIALOG_CONTENT_WIDTH), natural_width),
            float(DIALOG_CONTENT_HEIGHT))
    # A little slack keeps the scrollbar's own width from turning into horizontal
    # scrolling when the window has room to spare.
    if available.x >= wanted.x + 24.0:
        wanted.x += 24.0
    # Squeeze only if even that width does not fit beside the other column.
    var squeezed := available.x < wanted.x - 1.0 or available.y < wanted.y - 1.0
    if squeezed:
        _apply_world_fit(true)
    var fitted := Vector2(
            maxf(minf(wanted.x, available.x), float(PAGE_MIN_WIDTH)),
            maxf(minf(wanted.y, available.y), float(PAGE_MIN_HEIGHT)))
    tab_container.custom_minimum_size = fitted
    new_game_dialog.reset_size()
    new_game_dialog.popup_centered()

    var deco := new_game_dialog.get_size_with_decorations()
    var target := (screen - deco) / 2
    new_game_dialog.position += target - new_game_dialog.get_position_with_decorations()
    # A window smaller than its decorations can still end up half outside the screen.
    # Work in the coordinates of the decorated rect: the title bar is drawn above the
    # reported one, so clamping the bare position would push it off the top.
    var deco_now := Vector2(new_game_dialog.get_position_with_decorations())
    var deco_pos := deco_now.clamp(Vector2.ZERO,
            Vector2(maxf(0.0, screen.x - deco.x), maxf(0.0, screen.y - deco.y)))
    new_game_dialog.position += Vector2i(deco_pos - deco_now)

# Each page scrolls on its own. A narrow fitted window then keeps its buttons in place
# and never drags another page's scrollbar past the edge of the screen.
func _page_scroll(name: String, content: Control, follow_focus: bool = false) -> ScrollContainer:
    var scroll := ScrollContainer.new()
    scroll.name = name
    scroll.custom_minimum_size = Vector2(PAGE_MIN_WIDTH, PAGE_MIN_HEIGHT)
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.follow_focus = follow_focus
    scroll.add_child(content)
    return scroll

# The scrollbars are drawn inside their scrolls, so the rows always keep a gutter beside
# them. The picture is narrowed down to its button only when the two columns cannot share
# the window at their designed size.
func _apply_world_fit(squeezed: bool) -> void:
    if settings_padding == null:
        return
    settings_padding.add_theme_constant_override("margin_left", PAGE_SIDE_PADDING)
    settings_padding.add_theme_constant_override("margin_right", SCROLL_GUTTER)
    settings_padding.add_theme_constant_override("margin_bottom", SCROLL_GUTTER)

    var pane_width := PREVIEW_WIDTH
    if squeezed and world_previews.size() > 1:
        # The widest control of the picture is the row of five colour names in its legend,
        # not the regenerate button. Keep that row on the panel before taking room from
        # the settings, whose labels wrap to make space.
        var widest := _legend_width(world_previews[1])
        if regenerate_button != null:
            widest = maxi(widest, ceili(regenerate_button.get_combined_minimum_size().x))
        pane_width = widest + PREVIEW_SIDE_MARGIN * 2
    _fit_preview(preview_scroll, preview_padding, preview_column, pane_width)
    _fit_preview(city_preview_scroll, city_preview_padding, city_preview_column, pane_width)

# The legend draws five colour names in one row; they need more width than the button.
func _legend_width(preview: Control) -> int:
    var font := preview.get_theme_font("font", "Label")
    var labels := [tr("Sea"), tr("Shallows"), tr("Beach"), tr("Lake"), tr("Wetland")]
    var total := 0.0
    for label in labels:
        total += WorldPreview.LEGEND_SWATCH.x + WorldPreview.LEGEND_GAP * 2.0 \
                + font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1,
                        WorldPreview.LEGEND_FONT_SIZE).x
    return ceili(total)

func _fit_preview(scroll: ScrollContainer, padding: MarginContainer, column: Control,
        pane_width: int) -> void:
    if scroll == null or padding == null or column == null:
        return
    # ScrollContainer only stretches a child that asks to expand. Give the picture the
    # whole height of the column, so the controls below it sit at the bottom.
    padding.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    padding.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.size_flags_vertical = Control.SIZE_EXPAND_FILL
    padding.add_theme_constant_override("margin_left", PAGE_SIDE_PADDING)
    padding.add_theme_constant_override("margin_right", PAGE_SIDE_PADDING)
    padding.add_theme_constant_override("margin_bottom", PAGE_SIDE_PADDING)
    column.custom_minimum_size.x = pane_width
    # The picture needs only its side margins plus a little slack: its scrollbar is
    # gone at the supported sizes, so the rest goes to the settings on the left.
    scroll.custom_minimum_size.x = pane_width + PREVIEW_SIDE_MARGIN * 2 + 4
    for child in column.get_children():
        if child.name == "WorldPreview" or child.name == "PreviewDisclaimerLabel":
            child.custom_minimum_size.x = pane_width - PREVIEW_SIDE_MARGIN * 2

func _build_new_game_dialog():
    var dialog = ConfirmationDialog.new()
    dialog.title = tr("New game")
    dialog.ok_button_text = tr("Start")
    dialog.cancel_button_text = tr("Back")

    # AcceptDialog stretches its single child to the content area, so the tabs own the
    # whole window. The tab container paints no background of its own: the pages would
    # otherwise sit on a darker plate than the buttons under them.
    tab_container = TabContainer.new()
    tab_container.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
    dialog.add_child(tab_container)

    tab_container.add_child(_page_margin(_build_city_tab()))
    tab_container.add_child(_page_margin(_build_world_tab()))
    tab_container.add_child(_page_scroll("ModsScroll", _build_mods_tab()))
    tab_container.set_tab_title(TAB_CITY, tr("City"))
    tab_container.set_tab_title(TAB_WORLD, tr("World"))
    tab_container.set_tab_title(TAB_MODS, tr("Mods"))

    city_name_edit.text_submitted.connect(func(_text): dialog.get_ok_button().pressed.emit())
    dialog.confirmed.connect(func(): _start_new_game(city_name_edit.text))
    add_child(dialog)
    new_game_dialog = dialog

# The city tab: the one thing the player has to type, next to the preview of the world the
# city will be founded in.
func _build_city_tab() -> Control:
    var page := HBoxContainer.new()
    page.name = "CityTab"
    page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    page.size_flags_vertical = Control.SIZE_EXPAND_FILL
    page.add_theme_constant_override("separation", 16)

    var fields_scroll := ScrollContainer.new()
    fields_scroll.name = "CityFieldsScroll"
    fields_scroll.custom_minimum_size = Vector2(PAGE_MIN_WIDTH, PAGE_MIN_HEIGHT)
    fields_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    fields_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    fields_scroll.size_flags_stretch_ratio = 1.2
    fields_scroll.follow_focus = true
    page.add_child(fields_scroll)

    var column := VBoxContainer.new()
    column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    column.add_theme_constant_override("separation", 10)
    fields_scroll.add_child(column)

    var name_row = HBoxContainer.new()
    name_row.custom_minimum_size = Vector2(0, SETTING_CONTROL_HEIGHT)
    name_row.add_theme_constant_override("separation", 4)
    city_name_edit = LineEdit.new()
    city_name_edit.text = tr("City")
    # The field keeps its own width: a name field stretched across the tab reads as a text
    # area, not as a name.
    city_name_edit.custom_minimum_size = Vector2(NAME_FIELD_WIDTH, SETTING_CONTROL_HEIGHT)
    city_name_edit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    city_name_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    city_name_edit.select_all_on_focus = true
    name_row.add_child(city_name_edit)

    var random_button = Button.new()
    random_button.custom_minimum_size = Vector2(SETTING_CONTROL_HEIGHT, SETTING_CONTROL_HEIGHT)
    random_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    random_button.expand_icon = true
    random_button.icon = IconRegistry.get_texture("dice.svg")
    random_button.tooltip_text = tr("Suggest another name")
    random_button.pressed.connect(func():
        _ensure_game_data()
        _drop_preview_build()
        city_name_edit.text = GameData.get_random_city_name()
        city_name_edit.select_all()
        city_name_edit.grab_focus()
    )
    name_row.add_child(random_button)
    column.add_child(name_row)

    var hint := Label.new()
    hint.text = tr("An empty name gives the city a random one.")
    hint.add_theme_font_size_override("font_size", 12)
    hint.theme_type_variation = &"MutedLabel"
    hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    # A wrapped label reports its minimum height at its minimum width, which would be the
    # height of its longest word.
    hint.custom_minimum_size = Vector2(300, 0)
    column.add_child(hint)

    # The same column geometry as on the World tab keeps the picture in one place when
    # the player switches between the two questions.
    city_preview_scroll = ScrollContainer.new()
    city_preview_scroll.name = "CityPreviewScroll"
    city_preview_scroll.custom_minimum_size = Vector2(
            PREVIEW_WIDTH + SCROLL_GUTTER * 2, PAGE_MIN_HEIGHT)
    city_preview_scroll.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    city_preview_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    page.add_child(city_preview_scroll)

    city_preview_padding = MarginContainer.new()
    city_preview_scroll.add_child(city_preview_padding)
    city_preview_column = _make_preview()
    city_preview_padding.add_child(city_preview_column)
    return page

# The world tab: the settings and the picture they produce stand side by side, each in
# its own scroll. Moving one never moves the other, so the settings stay where the player
# left them while the picture is scrolled, and neither scrollbar leaves its own column.
func _build_world_tab() -> Control:
    var page := HBoxContainer.new()
    page.name = "WorldTab"
    page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    page.size_flags_vertical = Control.SIZE_EXPAND_FILL
    page.add_theme_constant_override("separation", 16)

    var settings_scroll := ScrollContainer.new()
    settings_scroll.name = "SettingsScroll"
    settings_scroll.custom_minimum_size = Vector2(PAGE_MIN_WIDTH, PAGE_MIN_HEIGHT)
    settings_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    settings_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    settings_scroll.size_flags_stretch_ratio = 1.2
    settings_scroll.follow_focus = true
    page.add_child(settings_scroll)

    # A scroll container clips at its own edge, and a control that ends exactly there loses
    # the border the focus ring draws on it. The padding keeps every row off the edge and
    # clear of the scrollbar drawn on that edge.
    settings_padding = MarginContainer.new()
    settings_padding.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    settings_scroll.add_child(settings_padding)

    settings_column = VBoxContainer.new()
    settings_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    settings_column.add_theme_constant_override("separation", 8)
    settings_padding.add_child(settings_column)
    _build_world_settings(settings_column)

    preview_scroll = ScrollContainer.new()
    preview_scroll.name = "PreviewScroll"
    preview_scroll.custom_minimum_size = Vector2(PREVIEW_WIDTH, PAGE_MIN_HEIGHT)
    # The picture keeps its own width; the rest goes to the settings.
    preview_scroll.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    preview_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    page.add_child(preview_scroll)

    preview_padding = MarginContainer.new()
    preview_scroll.add_child(preview_padding)
    preview_column = _make_preview()
    preview_padding.add_child(preview_column)
    return page

# The mods tab. The list was laid out for a window of its own, so it keeps its width and
# scrolls inside the tab when the dialog has less room. It takes no margins.
func _build_mods_tab() -> Control:
    mod_list = ModListScene.instantiate()
    mod_list.selection_changed.connect(_on_mods_changed)
    return mod_list

# The room between the settings of a tab and its edges. The mod list is the one page that
# does without it: it is a window's worth of content on its own.
func _page_margin(page: Control) -> Control:
    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 12)
    margin.add_theme_constant_override("margin_top", 10)
    margin.add_theme_constant_override("margin_right", 12)
    margin.add_theme_constant_override("margin_bottom", PAGE_SIDE_PADDING)
    margin.add_child(page)
    return margin

# One line of the settings list: the name of the setting on the left, its control on the
# right. The controls keep their own width, so their right edges line up. The name wraps
# instead of forcing the whole column to the width of the longest Russian phrase.
#
# The hint of a row is long enough to need breaking, and the engine's own tooltip never
# breaks a line (see scripts/wrapped_tooltip.gd), so it is wrapped.
func _add_setting_row(column: VBoxContainer, text: String, control: Control,
        tooltip: String = "") -> HBoxContainer:
    var row := HBoxContainer.new()
    row.custom_minimum_size = Vector2(0, SETTING_ROW_HEIGHT)
    row.add_theme_constant_override("separation", 12)

    var label := Label.new()
    label.text = text
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.custom_minimum_size.x = SETTING_LABEL_WIDTH
    if not tooltip.is_empty():
        WrappedTooltip.attach(label, tooltip)
    row.add_child(label)

    control.size_flags_horizontal = Control.SIZE_SHRINK_END
    control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(control)

    column.add_child(row)
    return row

# The map preview of a tab. Both tabs that have room for one get their own copy: the tabs
# are separate subtrees, and a node cannot be in two of them at once.
func _make_preview() -> Control:
    regenerate_button = Button.new()
    regenerate_button.name = "RegeneratePreviewButton"
    regenerate_button.text = tr("Regenerate")
    regenerate_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    regenerate_button.pressed.connect(_regenerate_preview)

    var column := VBoxContainer.new()
    column.custom_minimum_size = Vector2(PREVIEW_WIDTH, 0)
    column.size_flags_horizontal = Control.SIZE_SHRINK_END
    column.add_theme_constant_override("separation", 6)

    var preview = WorldPreview.new()
    preview.name = "WorldPreview"
    preview.custom_minimum_size = Vector2(PREVIEW_WIDTH, PREVIEW_MIN_HEIGHT)
    preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
    preview.max_map_size = MAX_MAP_SIZE
    world_previews.append(preview)
    column.add_child(preview)
    column.add_child(regenerate_button)

    var disclaimer := Label.new()
    disclaimer.name = "PreviewDisclaimerLabel"
    disclaimer.text = tr("The coast, the relief and the belts are the world itself. Resources are not shown; towns and rivers are a sketch.")
    disclaimer.custom_minimum_size = Vector2(PREVIEW_WIDTH - 24, 0)
    disclaimer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    disclaimer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    disclaimer.add_theme_font_size_override("font_size", 12)
    disclaimer.theme_type_variation = &"MutedLabel"
    column.add_child(disclaimer)
    return column

# The sides of the sea are rolled from the seed, so the picture and the world read the same coast
# from the same configuration.
func _resolved_sea_config(seed_value: int = 0) -> Dictionary:
    var cfg := _selected_sea_config()
    cfg["sides"] = SeaManager.resolve_sides(cfg, seed_value)
    return cfg

# The previews show the world the current settings describe, so they are refreshed from one
# place instead of each control knowing about them. One picture is handed to both: the two tabs
# show the same world, and running the generator twice would double the cost of every change of
# a setting.
func _refresh_preview():
    if _preview_timer != null:
        _preview_timer.stop()
    # The newest settings win: a picture still being built is dropped where it stands. Two builds
    # must never run at once, because the generator draws from the one sequence of dice and two of
    # them would spoil each other's world.
    _drop_preview_build()
    var side := _selected_map_size()
    var sea := _resolved_sea_config(_preview_seed)
    var climate := _selected_climate()
    var key := _relief_key(side, sea, climate)
    if _relief_cache.has(key):
        _show_preview(key, side, _relief_cache[key])
    elif side < STAGED_PREVIEW_MAP_SIZE:
        _show_preview(key, side, _remember(_relief_cache, _relief_order, key,
                WorldPreview.build_relief(side, sea, _preview_seed, climate), RELIEF_CACHE_LIMIT))
    else:
        _start_staged_build(side, sea, climate, key)

# Only the size, the sea, the seed and the climate shape the relief. The key names all four, so a
# relief is rebuilt exactly when one of them moves.
func _relief_key(side: int, sea: Dictionary, climate: String) -> String:
    return "%d|%d|%s|%s" % [side, _preview_seed, JSON.stringify(sea), climate]

# The oldest entries are dropped, so a long session of comparing settings does not keep a giant map
# (nor the courses of its rivers) per attempt.
func _remember(cache: Dictionary, order: Array, key: String, value, limit: int):
    cache[key] = value
    order.append(key)
    while order.size() > limit:
        cache.erase(order.pop_front())
    return value

# The picture with its rivers drawn over it. A course is a search over the whole picture, so the
# courses are kept while the relief and the river settings stay put: the towns, the density and
# everything else drawn over the picture move no river.
func _show_preview(key: String, side: int, picture: Dictionary) -> void:
    var river_key := "%s|%s" % [key, JSON.stringify(_selected_river_config())]
    var courses = _river_cache.get(river_key)
    if courses == null:
        courses = _remember(_river_cache, _river_order, river_key,
                _build_rivers_for_preview(picture, side), RIVER_CACHE_LIMIT)
    picture["rivers"] = courses["rivers"]
    picture["deltas"] = courses.get("deltas", [])
    var towns := _selected_town_count()
    for preview in world_previews:
        preview.set_world(side, towns, picture)

# The courses of one river setting, kept together: the distributaries belong to the same search
# as the main rivers and must not be rebuilt from a different relief than their parent courses.
func _build_rivers_for_preview(picture: Dictionary, side: int) -> Dictionary:
    var rivers := WorldPreview.build_rivers(picture, side, _selected_river_config(), _preview_seed)
    return {"rivers": rivers, "deltas": picture.get("deltas", [])}

# The picture of a huge map, built in stages with a frame between them: building it in one go
# freezes the window for as long as it takes, and the player is watching the picture to compare
# settings. The first stage starts at once, so the picture on the screen is veiled at the first
# frame rather than after the first stage.
func _start_staged_build(side: int, sea: Dictionary, climate: String, key: String) -> void:
    _preview_build = {
        "side": side,
        "key": key,
        "relief": WorldPreview.begin_relief(side, sea, _preview_seed, climate),
        "stage": 0,
    }
    for preview in world_previews:
        preview.set_busy(true)
    # The steps come from the tree's own frame signal rather than from a coroutine of this node: a
    # window that closes mid-build leaves nothing behind to resume, and the connection dies with the
    # node it belongs to.
    if not get_tree().process_frame.is_connected(_on_preview_step):
        get_tree().process_frame.connect(_on_preview_step)
    _on_preview_step()

# One stage of the staged build, and no more than one per frame: the frame between the stages is
# what lets the window repaint and answer the player while a huge map is being built.
func _on_preview_step() -> void:
    if _preview_build.is_empty():
        return
    var relief: Dictionary = _preview_build["relief"]
    var stage: int = _preview_build["stage"]
    WorldPreview.run_relief_stage(relief, stage)
    _preview_build["stage"] = stage + 1
    if _preview_build["stage"] < WorldPreview.RELIEF_STAGES.size():
        return
    var side: int = _preview_build["side"]
    var key: String = _preview_build["key"]
    var picture := WorldPreview.build_picture(WorldPreview.finish_relief(relief), side)
    _preview_build = {}
    _show_preview(key, side, _remember(_relief_cache, _relief_order, key, picture,
            RELIEF_CACHE_LIMIT))

# A staged build holds the global sequence of dice while it runs, so anything else that draws from
# that sequence (the dice of the city name, a new preview seed) must drop the build first: it would
# otherwise hand the picture a world of its own.
func _drop_preview_build() -> void:
    if _preview_build.is_empty():
        return
    WorldPreview.abort_relief(_preview_build["relief"])
    _preview_build = {}
    for preview in world_previews:
        preview.set_busy(false)

# A build cut short by the window going away keeps the generator it was using: nothing will step it
# again, and an orphan node is a leak.
func _exit_tree() -> void:
    if not _preview_build.is_empty():
        WorldPreview.abort_relief(_preview_build["relief"])
        _preview_build = {}

# A rebuild waits for the typing to pause. A discrete change refreshes at once and cancels the
# wait, so a pending rebuild never draws a value the player has already left behind.
func _queue_preview_refresh():
    if _preview_timer == null:
        _preview_timer = Timer.new()
        _preview_timer.one_shot = true
        _preview_timer.wait_time = PREVIEW_DEBOUNCE
        _preview_timer.timeout.connect(_refresh_preview)
        add_child(_preview_timer)
    _preview_timer.start()

func _regenerate_preview():
    var next_seed := _roll_preview_seed()
    if next_seed == _preview_seed:
        next_seed += 1
    _preview_seed = next_seed
    _refresh_preview()

# Zero is the seed of a world that was not previewed, so the seed of a picture is never zero.
func _roll_preview_seed() -> int:
    return randi_range(1, 2147483647)

# The belts of the chosen climate are drawn on the picture, so the climate moves it like any other
# setting of the world.
func _on_climate_selected(_index: int) -> void:
    _refresh_preview()

# The link means the count is tied to the map size. A square icon toggle takes less room
# than the old checkbox with its label, and the tooltip still names what the link does.
func _make_proportional_button() -> Button:
    var button := Button.new()
    button.toggle_mode = true
    button.button_pressed = true
    button.icon = IconRegistry.get_texture("proportional_toggle.png")
    button.expand_icon = true
    button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
    button.custom_minimum_size = Vector2(SETTING_CONTROL_HEIGHT, SETTING_CONTROL_HEIGHT)
    button.tooltip_text = tr("Proportional to the map size")
    button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    return button

# The world settings of a new game: the map size, the number of towns, the climate, the
# resource density, the seas and the rivers. Every setting is one line of the list, and the
# list grows downwards.
func _build_world_settings(column: VBoxContainer):
    # The map size: a preset dropdown and a custom side field that appears only when
    # "Custom size" is chosen. The map is square, so one side applies to width and height.
    map_size_option = OptionButton.new()
    map_size_option.add_item(tr("Small (30×30)"))
    map_size_option.add_item(tr("Medium (60×60)"))
    map_size_option.add_item(tr("Large (100×100)"))
    map_size_option.add_item(tr("Huge (150×150)"))
    map_size_option.add_item(tr("Giant (200×200)"))
    map_size_option.add_item(tr("Custom size"))
    map_size_option.select(MAP_SIZE_PRESETS.find(DEFAULT_MAP_SIZE))
    map_size_option.item_selected.connect(_on_map_size_selected)
    map_size_option.custom_minimum_size = Vector2(200, SETTING_CONTROL_HEIGHT)
    _add_setting_row(column, tr("Map size"), map_size_option,
            tr("The side of the square map, in hexes."))

    custom_size_edit = LineEdit.new()
    custom_size_edit.custom_minimum_size = Vector2(_number_field_width(), SETTING_CONTROL_HEIGHT)
    number_fields.append(custom_size_edit)
    custom_size_edit.max_length = 3
    custom_size_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
    custom_size_edit.tooltip_text = tr("A whole number from %d to %d.") % [MIN_MAP_SIZE, MAX_MAP_SIZE]
    custom_size_edit.text_changed.connect(_on_custom_size_text_changed)
    custom_size_edit.focus_exited.connect(_normalize_custom_size)
    custom_size_row = _add_setting_row(column, tr("Side length"),
            _make_stepper(custom_size_edit, _on_custom_size_step.bind(-CUSTOM_SIZE_STEP),
                    _on_custom_size_step.bind(CUSTOM_SIZE_STEP)))
    custom_size_row.visible = false

    # The towns: a number that can be typed or stepped with the buttons beside it. The map
    # size decides how many of them fit, so the field is not tied to the presets above it.
    town_count_edit = LineEdit.new()
    town_count_edit.custom_minimum_size = Vector2(_number_field_width(), SETTING_CONTROL_HEIGHT)
    number_fields.append(town_count_edit)
    town_count_edit.max_length = 3
    town_count_edit.text = str(DEFAULT_TOWN_COUNT)
    town_count_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
    town_count_edit.text_changed.connect(_on_town_count_text_changed)
    town_count_edit.focus_exited.connect(_normalize_town_count)

    var stepper := _make_stepper(town_count_edit, _on_town_count_step.bind(-1),
            _on_town_count_step.bind(1))
    town_count_minus = stepper.get_child(0)
    town_count_plus = stepper.get_child(2)

    # The link ties the count to the map size. The number is then computed, and neither
    # the field nor the buttons take input.
    proportional_check = _make_proportional_button()
    # Set before the signal is wired so building the layout does not rebuild the preview;
    # the fields are refreshed once the dialog opens.
    proportional_check.toggled.connect(_on_proportional_toggled)

    var towns_control := HBoxContainer.new()
    towns_control.add_theme_constant_override("separation", 8)
    towns_control.add_child(proportional_check)
    towns_control.add_child(stepper)
    _add_setting_row(column, tr("Number of towns"), towns_control)

    # The climate of the city's latitude. The preview draws the belts of the chosen climate, so
    # the choice refreshes it.
    climate_option = OptionButton.new()
    climate_option.add_item(tr("Random climate"))
    climate_option.add_item(tr("Boreal"))
    climate_option.add_item(tr("Temperate"))
    climate_option.add_item(tr("Subtropics"))
    climate_option.add_item(tr("Tropics"))
    climate_option.select(CLIMATE_PRESETS.find(DEFAULT_CLIMATE))
    climate_option.custom_minimum_size = Vector2(200, SETTING_CONTROL_HEIGHT)
    climate_option.item_selected.connect(_on_climate_selected)
    var climate_tooltip := tr("The climate belt the city starts in. It decides the terrain and the resources around the city.")
    WrappedTooltip.attach(climate_option, climate_tooltip)
    _add_setting_row(column, tr("Climate"), climate_option, climate_tooltip)

    # How rich the map is in resources: a multiplier of the number of specimens each
    # resource spawns. The preview does not draw resources, so the choice needs no refresh.
    resource_density_option = OptionButton.new()
    resource_density_option.add_item(tr("Low") + " (0.5x)")
    resource_density_option.add_item(tr("Standard") + " (1x)")
    resource_density_option.add_item(tr("Above average") + " (1.5x)")
    resource_density_option.add_item(tr("High") + " (2x)")
    resource_density_option.add_item(tr("Very high") + " (3x)")
    resource_density_option.add_item(tr("Extremely high") + " (5x)")
    resource_density_option.select(RESOURCE_DENSITY_PRESETS.find(DEFAULT_RESOURCE_DENSITY))
    resource_density_option.custom_minimum_size = Vector2(200, SETTING_CONTROL_HEIGHT)
    var density_tooltip := tr("How many resource deposits the map gets: a low density halves their number, a high density doubles it. A resource that appears only once is never reduced below one.")
    WrappedTooltip.attach(resource_density_option, density_tooltip)
    _add_setting_row(column, tr("Resource density"), resource_density_option, density_tooltip)

    _build_sea_settings(column)
    _build_river_settings(column)

# The "Seas" section: how the seas of the world are generated. The rows follow the modes of
# the generator (CityData.world_sea): the coastal strips own the island settings, the
# elevation field owns its own, and the common settings are shared by the two. A row is
# shown only while its mode is chosen, so the list never offers a setting the chosen mode
# would ignore.
func _build_sea_settings(column: VBoxContainer):
    _add_section_header(column, tr("Seas"))

    sea_mode_option = OptionButton.new()
    sea_mode_option.add_item(tr("None"))
    sea_mode_option.add_item(tr("Coasts"))
    sea_mode_option.add_item(tr("Noise"))
    sea_mode_option.custom_minimum_size = Vector2(200, SETTING_CONTROL_HEIGHT)
    sea_mode_option.select(maxi(0, SEA_MODES.find(str(_sea_default("mode")))))
    sea_mode_option.item_selected.connect(_on_sea_mode_selected)
    var mode_tooltip := tr("Coasts — strips with bays along the map edges; Noise — the sea comes from an elevation field; None — no sea at all.")
    WrappedTooltip.attach(sea_mode_option, mode_tooltip)
    _add_setting_row(column, tr("Mode"), sea_mode_option, mode_tooltip)

    var both: Array = [SEA_MODE_EDGE, SEA_MODE_NOISE]
    var edge: Array = [SEA_MODE_EDGE]
    var noise: Array = [SEA_MODE_NOISE]

    _add_sea_pair_row(column, "sides", tr("Edges with sea"),
            tr("How many map edges get a sea: from the minimum to the maximum. Zero leaves the map without a sea."),
            0, 4, both)
    _add_sea_check_row(column, "beach", tr("Beaches"),
            tr("Land next to the sea becomes a beach."), both)
    _add_sea_int_row(column, "max_sea_depth", tr("Maximum sea depth"),
            tr("How far the sea may reach from the map edge, in hexes, so that it does not eat the map."),
            1, 100, both)
    _add_sea_int_row(column, "coast_max_depth", tr("Shallow water depth"),
            tr("The deepest shallow water off the coast, in hexes; the depth varies smoothly along the shore."),
            1, 20, both)

    _add_sea_int_row(column, "edge_width_min", tr("Narrowest coast"),
            tr("The narrowest coastal strip, in hexes. Zero lets the shore break into bays."),
            0, 100, edge)
    _add_sea_int_row(column, "edge_width_max", tr("Widest coast"),
            tr("The widest coastal strip, in hexes."), 0, 100, edge)
    _add_sea_float_row(column, "edge_envelope_strength", tr("Bays"),
            tr("0 — a solid strip from edge to edge, about 0.7 — a bay in the middle of a side with land at its ends, 1 — only the peak of the bay."),
            0.0, 1.0, edge)

    # The island settings belong to the island checkbox: while it is off there is nothing to
    # set up, so they leave the list with their heading.
    var islands_header: Dictionary = _add_sea_subheader(column, tr("Islands in the seas"), edge)
    var islands_check: CheckBox = _add_sea_check_row(column, "edge_islands_enabled",
            tr("Generate islands"), tr("Grow islands inside the seas."), edge)
    islands_header["gate"] = islands_check
    islands_check.toggled.connect(_on_sea_islands_toggled)
    _add_sea_pair_row(column, "edge_island_size", tr("Island size"),
            tr("The smallest and the largest island, in hexes."), 1, 50, edge, islands_check)
    # A hundredth per click: the default share is only 0.03, so a tenth would triple it at once.
    _add_sea_float_row(column, "edge_island_density", tr("Island density"),
            tr("The number of islands follows the area of the sea: the area times this share, plus a random spread. A small sea often gets none, a large one may get many."),
            0.0, 1.0, edge, islands_check, 0.01)
    _add_sea_int_row(column, "edge_island_min_distance", tr("Distance between islands"),
            tr("The least distance between two islands, in hexes, so that they do not stick together."),
            0, 50, edge, islands_check)
    _add_sea_int_row(column, "edge_island_max_attempts", tr("Island search attempts"),
            tr("How many times the generator tries to find a free spot for an island before it gives up."),
            1, 1000, edge, islands_check, 10)
    # A twentieth per click: the threshold decides land from sea, and a tenth flips whole
    # coastlines at once.
    _add_sea_float_row(column, "noise_sea_level", tr("Sea level"),
            tr("The land/sea threshold: a hex at or below it is sea."), -1.0, 1.0, noise, null, 0.05)
    _add_sea_float_row(column, "noise_strength", tr("Coast raggedness"),
            tr("The amplitude of the elevation noise: how ragged the coast is and how many islands it makes."),
            0.0, 2.0, noise, null, 0.05)
    _add_sea_float_row(column, "noise_edge_gradient", tr("Continentality"),
            tr("0 — islands everywhere, 1 — the sea strictly at the edges of the map."),
            0.0, 1.0, noise)
    _add_sea_float_row(column, "noise_city_bump", tr("Land around the city"),
            tr("The elevation hill around the city: it guarantees that the city starts on a continent."),
            0.0, 5.0, noise, null, 0.5)
    _add_sea_int_row(column, "noise_city_bump_radius", tr("Guaranteed land radius"),
            tr("The radius around the city that is always land, in hexes."), 0, 50, noise)

# The "Rivers" section: how many rivers the world gets and how long they have to be. The
# preview draws the main rivers in this world's rolled count; the tributaries are not on it.
# Only the counts can follow the map size; the minimum lengths stay a manual choice.
func _build_river_settings(column: VBoxContainer):
    _add_section_header(column, tr("Rivers"))
    proportional_river_check = _make_proportional_button()
    proportional_river_check.toggled.connect(_on_proportional_rivers_toggled)
    _add_setting_row(column, tr("Number of rivers"), proportional_river_check)
    _add_river_int_row(column, "num_main_rivers", tr("Main rivers"),
            tr("The average number of main rivers. A main river starts in the mountains and mouths in a lake or the sea; a world gets a little more or fewer than the average."),
            0, 40)
    _add_river_int_row(column, "num_tributaries", tr("Tributaries"),
            tr("The average number of tributaries. A tributary starts in the mountains or on the hills and flows into a river; a world gets a little more or fewer than the average."),
            0, 80)
    _add_river_int_row(column, "min_river_length", tr("Shortest main river"),
            tr("The least length of a main river, in hexes."), 1, 100)
    _add_river_int_row(column, "min_tributary_length", tr("Shortest tributary"),
            tr("The least length of a tributary, in hexes."), 1, 100)
    _add_river_float_row(column, "delta_chance", tr("Delta chance"),
            tr("The chance that a main river reaching a lake or the sea splits into distributaries at its mouth."),
            0.0, 1.0, 0.05)

# A whole-number row of the "Rivers" section. The step buttons are kept with the spec so the
# proportional switch can take them away together with the field.
func _add_river_int_row(column: VBoxContainer, key: String, label: String, tooltip: String,
        lo: int, hi: int):
    var default := int(_river_default(key))
    var edit := _make_number_field(str(default), false, tooltip, _normalize_river_fields)
    var control := _stepped_field(edit, 1, false, lo, hi, default, _normalize_river_fields)
    _add_setting_row(column, label, control, tooltip)
    river_controls[key] = {"kind": SEA_INT, "control": edit, "lo": lo, "hi": hi,
            "default": default, "minus": control.get_child(0), "plus": control.get_child(2)}

# A fractional row of the "Rivers" section, for the chance of a sea delta.
func _add_river_float_row(column: VBoxContainer, key: String, label: String, tooltip: String,
        lo: float, hi: float, step: float):
    var default := float(_river_default(key))
    var edit := _make_number_field(_format_number(default), true, tooltip,
            _normalize_river_fields)
    var control := _stepped_field(edit, step, true, lo, hi, default, _normalize_river_fields)
    _add_setting_row(column, label, control, tooltip)
    river_controls[key] = {"kind": SEA_FLOAT, "control": edit, "lo": lo, "hi": hi,
            "default": default, "minus": control.get_child(0), "plus": control.get_child(2)}

# A heading of the settings list, with a line above it: the sections of a long list read
# apart, and the line tells where the next one starts.
func _add_section_header(column: VBoxContainer, text: String):
    var separator := HSeparator.new()
    separator.custom_minimum_size = Vector2(0, 14)
    column.add_child(separator)

    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", 16)
    column.add_child(label)

# A heading inside a section, one size below it. The returned entry is the line itself: a
# heading that introduces a group gated by a checkbox takes the gate after the checkbox is
# built (see _add_sea_row).
func _add_sea_subheader(column: VBoxContainer, text: String, modes: Array) -> Dictionary:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", 13)
    column.add_child(label)
    var entry := {"row": label, "modes": modes}
    sea_rows.append(entry)
    return entry

# A whole-number row of the "Seas" section.
func _add_sea_int_row(column: VBoxContainer, key: String, label: String, tooltip: String,
        lo: int, hi: int, modes: Array, gate: BaseButton = null, step: int = 1):
    var default := int(_sea_default(key))
    var edit := _make_number_field(str(default), false, tooltip, _normalize_sea_fields)
    var control := _stepped_field(edit, step, false, lo, hi, default, _normalize_sea_fields)
    _add_sea_row(column, key, label, control, tooltip, modes,
            {"kind": SEA_INT, "control": edit, "lo": lo, "hi": hi, "default": default}, gate)

# A fractional row of the "Seas" section.
func _add_sea_float_row(column: VBoxContainer, key: String, label: String, tooltip: String,
        lo: float, hi: float, modes: Array, gate: BaseButton = null, step: float = 0.1):
    var default := float(_sea_default(key))
    var edit := _make_number_field(_format_number(default), true, tooltip,
            _normalize_sea_fields)
    var control := _stepped_field(edit, step, true, lo, hi, default, _normalize_sea_fields)
    _add_sea_row(column, key, label, control, tooltip, modes,
            {"kind": SEA_FLOAT, "control": edit, "lo": lo, "hi": hi, "default": default}, gate)

# A row of two whole numbers — the bounds of a range. The two fields read as one value, so
# they stand together in one control.
func _add_sea_pair_row(column: VBoxContainer, key: String, label: String, tooltip: String,
        lo: int, hi: int, modes: Array, gate: BaseButton = null):
    var default: Array = _sea_default(key)
    var from_edit := _make_number_field(str(int(default[0])), false, tooltip,
            _normalize_sea_fields)
    var to_edit := _make_number_field(str(int(default[1])), false, tooltip,
            _normalize_sea_fields)

    var box := HBoxContainer.new()
    # Wider than the stepper's own gaps: the dash must read as the range separator, not as
    # another sign button between the two steppers.
    box.add_theme_constant_override("separation", 10)
    box.add_child(_stepped_field(from_edit, 1, false, lo, hi, int(default[0]),
            _normalize_sea_fields))
    var dash := Label.new()
    dash.text = "–"
    box.add_child(dash)
    box.add_child(_stepped_field(to_edit, 1, false, lo, hi, int(default[1]),
            _normalize_sea_fields))

    _add_sea_row(column, key, label, box, tooltip, modes,
            {"kind": SEA_PAIR, "from": from_edit, "to": to_edit, "lo": lo, "hi": hi,
                    "default": [int(default[0]), int(default[1])]}, gate)

# A checkbox row of the "Seas" section. It is returned, because the rows it switches may
# hang on it.
func _add_sea_check_row(column: VBoxContainer, key: String, label: String, tooltip: String,
        modes: Array, gate: BaseButton = null) -> CheckBox:
    var check := CheckBox.new()
    check.button_pressed = bool(_sea_default(key))
    WrappedTooltip.attach(check, tooltip)
    check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    check.toggled.connect(func(_pressed): _refresh_preview())
    _add_sea_row(column, key, label, check, tooltip, modes,
            {"kind": SEA_CHECK, "control": check, "default": bool(_sea_default(key))}, gate)
    return check

# Registers a line of the "Seas" section: it is drawn like every other setting, and it is
# remembered with the modes it belongs to and the checkbox that switches it on (see
# _refresh_sea_rows), and with the control that holds its value (see _selected_sea_config).
func _add_sea_row(column: VBoxContainer, key: String, label: String, control: Control,
        tooltip: String, modes: Array, spec: Dictionary, gate: BaseButton = null):
    var row := _add_setting_row(column, label, control, tooltip)
    sea_rows.append({"row": row, "modes": modes, "gate": gate})
    spec["row"] = row
    sea_controls[key] = spec

func _number_field_width() -> int:
    var scale := maxf(UiScale.current(), 0.01)
    var extra := NUMBER_FIELD_SCALE_EXTRA if scale > 1.01 else 0
    return maxi(MIN_NUMBER_FIELD_WIDTH,
            roundi(float(STEP_FIELD_WIDTH) / scale) + extra)

func _apply_number_field_widths() -> void:
    var width := _number_field_width()
    for edit in number_fields:
        if edit == null or not is_instance_valid(edit):
            continue
        # A LineEdit reserves room for this many wide characters regardless of the text
        # it holds. The default reserves thousands; these fields only hold tens.
        var font := edit.get_theme_font("font")
        var em := 1.0
        if font != null:
            em = maxf(font.get_char_size(87, edit.get_theme_font_size("font_size")).x, 1.0)
        edit.add_theme_constant_override("minimum_character_width",
                maxi(1, floori(float(width) / em)))
        edit.custom_minimum_size.x = width

# A number field of the world settings. A whole number keeps the digits, a fraction also
# keeps a single decimal point and a leading minus. The field is rewritten only when the input
# really holds something else, so the caret does not jump on every keystroke. The normalizer
# of the section brings the value into its allowed range when the field loses focus.
func _make_number_field(value: String, fractional: bool, tooltip: String,
        normalizer: Callable) -> LineEdit:
    var edit := LineEdit.new()
    edit.custom_minimum_size = Vector2(_number_field_width(), SETTING_CONTROL_HEIGHT)
    number_fields.append(edit)
    edit.max_length = 6
    edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
    edit.text = value
    WrappedTooltip.attach(edit, tooltip)
    edit.text_changed.connect(func(text): _keep_number(edit, text, fractional))
    # The picture follows the number while it is being typed, not only when the field loses
    # focus: the sea and the rivers are the parts of the world a setting changes by a
    # visible amount. It follows once the typing pauses, because every keystroke would run the
    # generator's stages over the whole map again.
    edit.text_changed.connect(func(_text): _queue_preview_refresh())
    edit.focus_exited.connect(normalizer)
    return edit

# The value of a sea setting a new game starts from (CityData.DEFAULT_SEA).
func _sea_default(key: String):
    return CityData.DEFAULT_SEA.get(key)

# The value of a river setting a new game starts from (CityData.DEFAULT_RIVERS).
func _river_default(key: String):
    return CityData.DEFAULT_RIVERS.get(key)

# The rows of the "Seas" section follow the chosen mode, and the rows of a group follow the
# checkbox that switches the group on. A row that is not shown keeps its value: switching
# back and forth does not lose it.
func _refresh_sea_rows():
    if sea_mode_option == null:
        return
    var mode: String = SEA_MODES[maxi(0, sea_mode_option.selected)]
    for entry in sea_rows:
        var shown: bool = mode in entry["modes"]
        var gate: BaseButton = entry.get("gate")
        if shown and gate != null:
            shown = gate.button_pressed
        entry["row"].visible = shown

func _on_sea_mode_selected(_index: int):
    _refresh_sea_rows()
    _refresh_preview()

# The island checkbox refreshes the rows it switches. The picture follows the checkbox on its
# own: every check box of the section is wired to the preview (see _add_sea_check_row).
func _on_sea_islands_toggled(_pressed: bool):
    _refresh_sea_rows()

# The sea configuration the world will be generated with. Every row is read, including the
# rows of a mode that is not chosen: the generator ignores the fields of the other mode, and
# the values are then kept while the player compares the two.
func _selected_sea_config() -> Dictionary:
    var cfg: Dictionary = CityData.DEFAULT_SEA.duplicate(true)
    if sea_mode_option == null:
        return cfg
    cfg["mode"] = SEA_MODES[maxi(0, sea_mode_option.selected)]
    for key in sea_controls.keys():
        var spec: Dictionary = sea_controls[key]
        match spec["kind"]:
            SEA_CHECK:
                cfg[key] = spec["control"].button_pressed
            SEA_INT:
                cfg[key] = _read_whole(spec["control"], spec["lo"], spec["hi"], spec["default"])
            SEA_FLOAT:
                cfg[key] = _read_fraction(spec["control"], spec["lo"], spec["hi"], spec["default"])
            SEA_PAIR:
                cfg[key] = _read_pair(spec)
    return cfg

# The river configuration the world will be generated with. While the counts follow the map,
# they are rolled around their average from the preview seed, which is also the world seed: the
# picture and the generated world therefore get the same number of rivers. The minimum lengths
# are always read from the fields.
func _selected_river_config() -> Dictionary:
    var cfg: Dictionary = CityData.DEFAULT_RIVERS.duplicate(true)
    var side := _selected_map_size()
    var proportional := proportional_river_check != null \
            and proportional_river_check.button_pressed
    for key in river_controls.keys():
        var spec: Dictionary = river_controls[key]
        if proportional and key in RIVER_COUNT_KEYS:
            cfg[key] = _rolled_river_count(_proportional_river_value(side, spec), key, spec)
        elif spec["kind"] == SEA_FLOAT:
            cfg[key] = _read_fraction(spec["control"], spec["lo"], spec["hi"], spec["default"])
        else:
            # The minimum lengths are constraints chosen by the player, not a map-size average.
            cfg[key] = _read_whole(spec["control"], spec["lo"], spec["hi"], spec["default"])
    return cfg

# The average count that follows the map size uses the same side-based factor as the towns: the
# medium map keeps the base count, and a bigger map gets proportionally more rivers.
func _proportional_river_value(side: int, spec: Dictionary) -> int:
    var base := int(spec["default"])
    var scaled := roundi(float(base) * float(side) / float(DEFAULT_MAP_SIZE))
    return clampi(scaled, int(spec["lo"]), int(spec["hi"]))

# A world gets a number near the average rather than the average itself. The spread grows with
# the average so a giant map varies more than a small one, and the salt keeps the two kinds of
# rivers on separate rolls while staying the same from one rebuild to the next.
func _rolled_river_count(average: int, key: String, spec: Dictionary) -> int:
    var spread := maxi(1, roundi(float(average) * RIVER_COUNT_SPREAD))
    var rng := RandomNumberGenerator.new()
    var salt := 7919 if key == "num_tributaries" else 0
    rng.seed = _preview_seed + salt
    return clampi(average + rng.randi_range(-spread, spread),
            int(spec["lo"]), int(spec["hi"]))

# Brings the two count fields in line with the map. While the switch is on they show the average
# and take no input — a number the player cannot change must not look editable. When it goes off,
# the number the field was showing becomes the manual one. The minimum lengths are not affected.
func _refresh_river_fields():
    if proportional_river_check == null or river_controls.is_empty():
        return
    var proportional := proportional_river_check.button_pressed
    var side := _selected_map_size()
    for key in RIVER_COUNT_KEYS:
        var spec: Dictionary = river_controls.get(key)
        if spec == null:
            continue
        var edit: LineEdit = spec["control"]
        edit.editable = not proportional
        spec["minus"].disabled = proportional
        spec["plus"].disabled = proportional
        if proportional:
            if edit.has_focus():
                edit.release_focus()
            # The count is a target, not what every world gets; the sign is the only honest way
            # to show an average in a number field.
            edit.text = "≈%d" % _proportional_river_value(side, spec)
        else:
            edit.text = str(_read_whole(edit, spec["lo"], spec["hi"], spec["default"]))

func _on_proportional_rivers_toggled(_pressed: bool):
    _refresh_river_fields()
    _refresh_preview()

# A whole number of a sea setting. An empty or a malformed field is read as the default of
# the setting: the game must never be started with a number that cannot be parsed.
func _read_whole(edit: LineEdit, lo: int, hi: int, fallback: int) -> int:
    # A count that follows the map shows its average as "≈N"; turning the switch off keeps that
    # number as the manual starting value.
    var raw := edit.text.strip_edges().trim_prefix("≈").strip_edges()
    if not raw.is_valid_int():
        return clampi(fallback, lo, hi)
    return clampi(int(raw), lo, hi)

func _read_fraction(edit: LineEdit, lo: float, hi: float, fallback: float) -> float:
    var raw := edit.text.strip_edges()
    if not raw.is_valid_float():
        return clampf(fallback, lo, hi)
    return clampf(float(raw), lo, hi)

# The bounds of a range, kept in order: the "from" never rises above the "to".
func _read_pair(spec: Dictionary) -> Array:
    var lo: int = spec["lo"]
    var hi: int = spec["hi"]
    var from_value := _read_whole(spec["from"], lo, hi, int(spec["default"][0]))
    var to_value := _read_whole(spec["to"], lo, hi, int(spec["default"][1]))
    return [from_value, maxi(from_value, to_value)]

# Every field of the "Seas" section shows the value the game will use: a number outside the
# allowed range is pulled to the nearest bound when the field loses focus.
func _normalize_sea_fields():
    for spec in sea_controls.values():
        match spec["kind"]:
            SEA_INT:
                spec["control"].text = str(_read_whole(spec["control"], spec["lo"],
                        spec["hi"], spec["default"]))
            SEA_FLOAT:
                spec["control"].text = _format_number(_read_fraction(spec["control"],
                        spec["lo"], spec["hi"], spec["default"]))
            SEA_PAIR:
                var pair := _read_pair(spec)
                spec["from"].text = str(pair[0])
                spec["to"].text = str(pair[1])

# Every field of the "Rivers" section shows the value the game will use, like the sea fields.
func _normalize_river_fields():
    var proportional := proportional_river_check != null \
            and proportional_river_check.button_pressed
    for key in river_controls.keys():
        # A count that follows the map shows "≈N"; normalising it here would drop the sign.
        if proportional and key in RIVER_COUNT_KEYS:
            continue
        var spec: Dictionary = river_controls[key]
        if spec["kind"] == SEA_FLOAT:
            spec["control"].text = _format_number(_read_fraction(spec["control"],
                    spec["lo"], spec["hi"], spec["default"]))
        else:
            spec["control"].text = str(_read_whole(spec["control"], spec["lo"],
                    spec["hi"], spec["default"]))

# A fraction of a sea setting, without the trailing zeros of a longer number.
func _format_number(value: float) -> String:
    return String.num(value, 3)

# The fields of the "Seas" section take digits only; a fraction also takes a decimal point
# and a minus sign at the front.
func _keep_number(edit: LineEdit, text: String, fractional: bool):
    # A read-only field shows a computed average that may carry a "≈" sign.
    if not edit.editable:
        return
    var filtered := ""
    var has_point := false
    for ch in text:
        if ch.is_valid_int():
            filtered += ch
        elif ch == "-" and filtered.is_empty():
            filtered += ch
        elif ch == "." and fractional and not has_point:
            has_point = true
            filtered += ch
    if filtered != text:
        edit.text = filtered

# A square button with a sign on it. The two of them and the field between them read as one
# control, so they share the height of the field.
func _make_step_button(sign: String, callback: Callable) -> Button:
    var button := Button.new()
    button.text = sign
    button.custom_minimum_size = Vector2(SETTING_CONTROL_HEIGHT, SETTING_CONTROL_HEIGHT)
    button.pressed.connect(callback)
    return button

# The field between its two step buttons, the layout of the town count.
func _make_stepper(edit: LineEdit, minus: Callable, plus: Callable) -> HBoxContainer:
    var box := HBoxContainer.new()
    box.add_theme_constant_override("separation", 4)
    box.add_child(_make_step_button("−", minus))
    box.add_child(edit)
    box.add_child(_make_step_button("+", plus))
    return box

# A number field whose buttons step it by the increment of its setting.
func _stepped_field(edit: LineEdit, step: float, fractional: bool, lo: float, hi: float,
        fallback: float, normalizer: Callable) -> HBoxContainer:
    return _make_stepper(edit,
            _on_number_step.bind(edit, -step, fractional, lo, hi, fallback, normalizer),
            _on_number_step.bind(edit, step, fractional, lo, hi, fallback, normalizer))

# The buttons step the number and stop at the bounds, so a click never produces a value the
# field would have to clamp on the next focus change. The section normalizer runs afterwards
# because a step of one bound of a range may carry the other bound with it.
func _on_number_step(edit: LineEdit, step: float, fractional: bool, lo: float, hi: float,
        fallback: float, normalizer: Callable):
    var current: float
    if fractional:
        current = _read_fraction(edit, lo, hi, fallback)
    else:
        current = float(_read_whole(edit, int(lo), int(hi), int(fallback)))
    var value := clampf(current + step, lo, hi)
    edit.text = _format_number(value) if fractional else str(roundi(value))
    normalizer.call()
    _refresh_preview()

# The custom row is shown only when the player picked "Custom size" (the last item).
func _on_map_size_selected(index: int):
    var custom := index == MAP_SIZE_PRESETS.size()
    custom_size_row.visible = custom
    if custom and custom_size_edit.text.strip_edges().is_empty():
        custom_size_edit.text = str(DEFAULT_MAP_SIZE)
    _refresh_town_row()
    _refresh_river_fields()
    _refresh_preview()
    if not custom:
        return
    custom_size_edit.grab_focus()
    custom_size_edit.select_all()

# The side input accepts only digits: the map size is a whole positive number.
func _on_custom_size_text_changed(text: String):
    _keep_digits(custom_size_edit, text)
    # A half-typed number is clamped to the nearest bound, and the preview would jump to
    # that bound on every keystroke: it follows only a value that is already valid.
    var raw := custom_size_edit.text.strip_edges()
    if not raw.is_empty() and int(raw) >= MIN_MAP_SIZE and int(raw) <= MAX_MAP_SIZE:
        _refresh_town_row()
        _refresh_river_fields()
        _queue_preview_refresh()

# A number outside the allowed range is pulled to the nearest bound when the field loses
# focus, so the player sees the value the game is about to use.
func _normalize_custom_size():
    custom_size_edit.text = str(_selected_map_size())
    _refresh_town_row()
    _refresh_river_fields()
    _refresh_preview()

func _on_custom_size_step(step: int):
    custom_size_edit.text = str(clampi(_selected_map_size() + step, MIN_MAP_SIZE, MAX_MAP_SIZE))
    _refresh_town_row()
    _refresh_river_fields()
    _refresh_preview()

# The town count is a whole number of the same kind.
func _on_town_count_text_changed(text: String):
    _keep_digits(town_count_edit, text)
    var raw := town_count_edit.text.strip_edges()
    if not raw.is_empty() and int(raw) <= _max_town_count(_selected_map_size()):
        _queue_preview_refresh()

func _normalize_town_count():
    town_count_edit.text = str(_selected_town_count())
    _refresh_preview()

# The buttons step the number and stop at the bounds, so a click never produces a value the
# field would have to clamp on the next focus change.
func _on_town_count_step(step: int):
    var value := clampi(_selected_town_count() + step, MIN_TOWN_COUNT,
            _max_town_count(_selected_map_size()))
    town_count_edit.text = str(value)
    _refresh_preview()

func _on_proportional_toggled(_pressed: bool):
    _refresh_town_row()
    _refresh_preview()

# Brings the town row in line with the rest of the settings. The ceiling follows the map, so a
# count typed for a bigger world comes down when the map shrinks; the computed count replaces
# the typed one while the checkbox is on, and the field then takes no input — a number the
# player cannot change must not look editable.
func _refresh_town_row():
    if proportional_check == null:
        return
    var side := _selected_map_size()
    var ceiling := _max_town_count(side)
    var proportional := proportional_check.button_pressed

    town_count_edit.max_length = str(ceiling).length()
    town_count_edit.tooltip_text = tr("A whole number from %d to %d. Zero leaves the map without towns.") \
            % [MIN_TOWN_COUNT, ceiling]

    town_count_edit.editable = not proportional
    town_count_minus.disabled = proportional
    town_count_plus.disabled = proportional

    if proportional:
        # A field that cannot be typed into must not keep the caret of the keyboard focus.
        if town_count_edit.has_focus():
            town_count_edit.release_focus()
        town_count_edit.text = str(_proportional_town_count(side))
    else:
        town_count_edit.text = str(_selected_town_count())

# The most towns a map of this size may hold. The ceiling is a density, not a number: it is
# what makes the same field usable on a 30×30 village map and on a 200×200 world.
func _max_town_count(side: int) -> int:
    return maxi(1, roundi(float(side) * float(side) / float(HEXES_PER_TOWN)))

# The count that matches the map. It keeps the default 16 towns on the medium map and follows
# the SIDE of the map rather than its area: an area-proportional 200×200 world would be 178
# towns, and the density thins out as the map grows instead.
func _proportional_town_count(side: int) -> int:
    return clampi(roundi(DEFAULT_TOWN_COUNT * float(side) / float(DEFAULT_MAP_SIZE)),
            MIN_TOWN_COUNT, _max_town_count(side))

# Both numeric fields of the world settings take digits only. The field is rewritten only
# when the input really holds something else, so the caret does not jump on every keystroke.
func _keep_digits(edit: LineEdit, text: String):
    var filtered := ""
    for ch in text:
        if ch.is_valid_int():
            filtered += ch
    if filtered != text:
        edit.text = filtered

# The side of the square map chosen in the world settings. For a preset it is its fixed
# value; for "Custom size" it is the clamped number in the input field. Falls back to the
# default when the settings have not been built (a direct start of a new game).
func _selected_map_size() -> int:
    if map_size_option == null:
        return DEFAULT_MAP_SIZE
    var index := map_size_option.selected
    if index >= 0 and index < MAP_SIZE_PRESETS.size():
        return MAP_SIZE_PRESETS[index]
    var raw := custom_size_edit.text.strip_edges()
    if raw.is_empty():
        return DEFAULT_MAP_SIZE
    return clampi(int(raw), MIN_MAP_SIZE, MAX_MAP_SIZE)

# The number of towns the map will be generated with. While the count follows the map size
# it is computed, not read. Falls back to the default when the settings have not been built
# (a direct start of a new game).
func _selected_town_count() -> int:
    if proportional_check != null and proportional_check.button_pressed:
        return _proportional_town_count(_selected_map_size())
    if town_count_edit == null:
        return DEFAULT_TOWN_COUNT
    var raw := town_count_edit.text.strip_edges()
    if raw.is_empty():
        return DEFAULT_TOWN_COUNT
    return clampi(int(raw), MIN_TOWN_COUNT, _max_town_count(_selected_map_size()))

# The resource density multiplier the world will be generated with. Falls back to the
# standard density when the settings have not been built (a direct start of a new game).
func _selected_resource_density() -> float:
    if resource_density_option == null:
        return DEFAULT_RESOURCE_DENSITY
    var index := resource_density_option.selected
    if index >= 0 and index < RESOURCE_DENSITY_PRESETS.size():
        return RESOURCE_DENSITY_PRESETS[index]
    return DEFAULT_RESOURCE_DENSITY

# The climate belt the city will start in. Falls back to a random latitude when the settings
# have not been built (a direct start of a new game).
func _selected_climate() -> String:
    if climate_option == null:
        return DEFAULT_CLIMATE
    var index := climate_option.selected
    if index >= 0 and index < CLIMATE_PRESETS.size():
        return CLIMATE_PRESETS[index]
    return DEFAULT_CLIMATE

# The set is handed over at once, so the game that starts runs exactly the data the
# player has chosen. The data itself is rebuilt later, when something really reads it:
# a full rebuild on every checkbox makes the list feel slow, and the set of the game is
# known without it.
func _on_mods_changed(mod_ids: Array):
    ModManager.set_active(mod_ids)
    _refresh_mods_tab()

# The random name is the only thing inside this dialog that reads the data, and the data
# is stale as soon as the set changes (ModManager drops it). The start of the game
# reloads it on its own.
func _ensure_game_data():
    if not GameData.data_loaded:
        GameData.load_all_data()

# The title of the tab tells at a glance that a game is about to start with mods, without
# opening the tab.
func _refresh_mods_tab():
    if tab_container == null or mod_list == null:
        return
    var count: int = mod_list.selected_ids().size()
    tab_container.set_tab_title(TAB_MODS,
            tr("Mods") if count == 0 else "%s (%d)" % [tr("Mods"), count])

func _start_new_game(city_name: String):
    # Empty input — we substitute a random name.
    if city_name.strip_edges().is_empty():
        city_name = GameData.get_random_city_name()
    SaveManager.new_game()
    CityData.city_name = city_name.strip_edges()
    CityData.world_map_size = _selected_map_size()
    CityData.world_town_count = _selected_town_count()
    CityData.world_sea = _resolved_sea_config(_preview_seed)
    CityData.world_rivers = _selected_river_config()
    CityData.world_resource_density = _selected_resource_density()
    CityData.world_climate = _selected_climate()
    CityData.world_seed = _preview_seed
    # The overlay is hung on the ROOT, not on the menu: the scene change frees the
    # menu, and the world generation runs inside MainMap. MainMap updates the very
    # same bar and removes it when the world is ready.
    LoadingOverlay.present(get_tree(), tr("Creating a new world..."))
    await get_tree().process_frame
    get_tree().change_scene_to_file("res://scenes/MainMap.tscn")

func _on_load_game():
    if not SaveManager.has_save():
        return
    if save_load_window == null:
        save_load_window = load("res://scenes/save_load_window.tscn").instantiate()
        add_child(save_load_window)
        save_load_window.load_requested.connect(_on_load_requested)
        save_load_window.closed.connect(_refresh_save_buttons)
    save_load_window.open_load()

func _on_load_requested(slot_id: String):
    var overlay := LoadingOverlay.present(get_tree(), tr("Loading game..."))
    overlay.set_status(tr("Reading save..."))
    # Two yields: the first resumes before the draw of the click's frame (see _on_continue_game).
    await get_tree().process_frame
    await get_tree().process_frame
    if SaveManager.load_game(slot_id):
        save_load_window.close()
        get_tree().change_scene_to_file("res://scenes/MainMap.tscn")
    else:
        overlay.queue_free()
        print("Save loading error")

func _on_settings():
    var settings_menu = load("res://scenes/settings_menu.tscn").instantiate()
    add_child(settings_menu)
    settings_menu.show()

# The "About" window: the author, the licenses and the third-party components.
#
# The window is created on every click and removes itself when it is closed, therefore
# it does not outlive the visit to it. It is added to the scene tree root, and not to
# the menu: the anchors of the menu Control are not set to the screen edges
# (scenes/main_menu.tscn), and the plate of the window would cover only part of it.
func _on_about():
    var window = Control.new()
    window.set_script(AboutWindow)
    get_tree().root.add_child(window)
    window.show_about()

func _on_quit():
    get_tree().quit()
