# localization_manager.gd (LocalizationManager autoload)
#
# It holds the selected game language and switches it in TranslationServer.
#
# The order of the autoloads in project.godot matters: LocalizationManager goes
# FIRST, so that the language is chosen before GameData reads data/*.json
# and applies the translation on top of it. Otherwise the first frame after the
# start draws the text of the previous (or source) language, and the needed one
# appears only after the first data reload.
#
# The source language is English: the English text lives in the code, in the
# scenes and in data/*.json, and it serves as the translation key. Each target
# language has its own catalog in locale/ (locale/<code>.po); none of them is
# special — the source catalog messages.pot is structured exactly the same way.
extends Node

# The "language changed" signal. Subscribers redraw what they build in code:
# the text set directly in the scene is translated by Godot itself (see the note
# above about the auto-translation of Control), but the strings assembled in
# GDScript have to be rebuilt manually.
signal locale_changed(locale: String)

const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "interface"
const SETTINGS_KEY := "locale"

# English — the default language (the source language).
const DEFAULT_LOCALE := "en"

# A pseudo setting value: take the language from the operating system settings.
# It is exactly what is chosen on the very first launch of the game.
const SYSTEM_LOCALE := "system"

# The context of the entry that names a language in its own tongue (see
# language_own_name). The msgid of that entry is the code of the language itself.
const LANGUAGE_NAME_CONTEXT := "language.name"

# Every language the project ships a catalog for, built from the catalogs actually
# loaded rather than from a table in the code: the code is the locale of the
# translation, the name is the one the language gives itself (see language_own_name).
# A missing locale/<code>.po therefore hides the language by itself, and a new one
# needs no edit here — only a line in project.godot.
#
# The list is sorted by code, so the dropdown of the settings does not depend on the
# order the translations happened to be registered in.
func described_languages() -> Array:
    var result: Array = []
    for code in TranslationServer.get_loaded_locales():
        if code == DEFAULT_LOCALE or result.any(func(lang): return lang["code"] == code):
            continue
        result.append({"code": code, "name": language_own_name(code)})
    result.sort_custom(func(a, b): return str(a["code"]) < str(b["code"]))
    return result


# The name of a language in that language ("Русский", not "Russian") — so that the list
# reads the same way whatever the player has chosen before.
#
# The name is data, not code: each catalog may carry it under the "language.name"
# context, with the code of its own language as the msgid (see locale/GLOSSARY.md).
# Reading it from that catalog — and not from the current one — is what makes the name
# its own: the Russian entry says «Русский» in a French interface as well.
#
# The engine's table gives the English name of a language and knows nothing of the
# native one, so it is the fallback: a catalog without the entry still gets a readable
# name, and a language the engine does not know falls back to its code.
func language_own_name(code: String) -> String:
    var short := short_language_code(code)
    for translation in TranslationServer.get_translations():
        if translation == null or translation.get_locale() != short:
            continue
        var own: StringName = translation.get_message(short, LANGUAGE_NAME_CONTEXT)
        if not str(own).is_empty():
            return str(own)
    return TranslationServer.get_language_name(short)

# The current game language (a code described_languages() offers, always a real one,
# not SYSTEM_LOCALE).
var current_locale: String = DEFAULT_LOCALE

# Whether the "system language" item is chosen in the settings instead of a specific language.
var follow_system_locale: bool = false

# The last applied code — so that re-selecting the same language does not
# start a data reload and an interface redraw for nothing.
var _applied_locale: String = ""


func _ready() -> void:
    _init_locale()


# The language choice at game start: the saved setting, and in its absence
# (that is, on the very first launch) the operating system language, and if it
# is not supported — English by default. The chosen value is immediately
# written to the settings, so that the next launch is predictable.
func _init_locale() -> void:
    var config := ConfigFile.new()
    var stored: Variant = null
    if config.load(SETTINGS_PATH) == OK:
        stored = config.get_value(SETTINGS_SECTION, SETTINGS_KEY, null)

    var requested := str(stored) if stored != null else SYSTEM_LOCALE

    if requested == SYSTEM_LOCALE:
        follow_system_locale = true
        current_locale = resolve_system_locale()
    elif is_supported(requested):
        follow_system_locale = false
        current_locale = requested
    else:
        # An unknown or removed language code: we do not crash, but take
        # the system language and rewrite the setting on the next launch.
        push_warning("Unknown language in the settings: \"%s\" — taking the system language." % requested)
        follow_system_locale = true
        current_locale = resolve_system_locale()

    _apply_locale(current_locale)
    _save_locale_setting(SYSTEM_LOCALE if follow_system_locale else current_locale)


# Translates the operating system language code into a game language code.
# ru_RU → ru. If the game has no such language — English by default.
func resolve_system_locale() -> String:
    var short_code := short_language_code(OS.get_locale_language())
    if is_supported(short_code):
        return short_code
    return DEFAULT_LOCALE


# Cuts the country off from the system language code: "pt_BR" → "pt", "ru" → "ru".
# It is put in a separate function, so that the rule can be checked in tests
# without substituting the operating system locale.
static func short_language_code(system_code: String) -> String:
    return system_code.to_lower().split("_")[0]


# Whether such a language is in the game. Empty and unknown — false.
func is_supported(code: String) -> bool:
    if code.is_empty():
        return false
    if code == DEFAULT_LOCALE:
        return true
    return is_translation_loaded(code)


# A language is available for selection if its translation is actually loaded: the
# source language is always there, a target language only while its catalog is (see
# described_languages).
func is_translation_loaded(code: String) -> bool:
    return code == DEFAULT_LOCALE or TranslationServer.get_loaded_locales().has(code)


# The list for the settings dropdown: the "system language" first, then the source language
# and every language whose catalog is loaded, both sorted by code.
#
# The source language is listed here although it has no catalog of its own: it is what the
# game says before any translation is applied, so the player has to be able to return to
# it. Without this item, a player who chose a target language could only get the source
# one back by choosing the system language and hoping the system speaks English.
func available_languages() -> Array:
    var result: Array = [ {"code": SYSTEM_LOCALE, "name": tr("System Language")}]
    var entries: Array = [ {"code": DEFAULT_LOCALE, "name": language_own_name(DEFAULT_LOCALE)} ]
    entries.append_array(described_languages())
    entries.sort_custom(func(a, b): return str(a["code"]) < str(b["code"]))
    result.append_array(entries)
    return result


func get_locale() -> String:
    return current_locale


# The language label for the dropdown: for the "system language" we show what
# exactly the system chose — otherwise the item looks undetermined.
func get_language_label(code: String) -> String:
    if code == SYSTEM_LOCALE:
        return tr("System Language") + " (%s)" % language_own_name(resolve_system_locale())
    # The list is asked rather than described_languages(): the source language is not
    # among the catalogs, and it has to read by its name in the dropdown as well.
    for lang in available_languages():
        if lang["code"] == code:
            return str(lang["name"])
    return code


# The entry point from the settings. code is either a language code, or SYSTEM_LOCALE.
# It returns false if such a language cannot be chosen.
func set_locale(code: String) -> bool:
    var resolved: String
    if code == SYSTEM_LOCALE:
        resolved = resolve_system_locale()
    else:
        if not is_supported(code):
            return false
        resolved = code

    follow_system_locale = (code == SYSTEM_LOCALE)
    current_locale = resolved

    if resolved == _applied_locale:
        # The language has not changed: we still write the setting (the player might have
        # returned to the "system language"), but we do not touch the data and the interface.
        _save_locale_setting(code)
        return true

    _apply_locale(resolved)
    _save_locale_setting(code)
    return true


func _apply_locale(code: String) -> void:
    _applied_locale = code
    TranslationServer.set_locale(code)
    # The game data stores the English source text and applies the translation on
    # loading, therefore after a language change it has to be re-read from scratch.
    # The data is already loaded at the moment of the change from the main menu;
    # on a change from within a game — as well (CityData.setup calls GameData.load_all_data).
    if GameData.data_loaded:
        GameData.load_all_data()
        # The names of the generated goods are built from the data names when the good is
        # created, so a re-read of the data in another language has to rebuild them.
        if is_instance_valid(CityData):
            CityData.rebuild_generated_products()
    locale_changed.emit(code)


func _save_locale_setting(code: String) -> void:
    var config := ConfigFile.new()
    # We re-read the file: settings_menu.gd writes the settings too, and its
    # in-memory copy may not know about the key that was just written.
    config.load(SETTINGS_PATH)
    config.set_value(SETTINGS_SECTION, SETTINGS_KEY, code)
    config.save(SETTINGS_PATH)


# Reads the saved language choice, without applying it. It is needed by the
# settings in order to show the current value of the item when the window opens.
func get_stored_locale() -> String:
    var config := ConfigFile.new()
    if config.load(SETTINGS_PATH) != OK:
        return SYSTEM_LOCALE
    var stored: Variant = config.get_value(SETTINGS_SECTION, SETTINGS_KEY, null)
    if stored == null:
        return SYSTEM_LOCALE
    var code := str(stored)
    if code == SYSTEM_LOCALE or is_supported(code):
        return code
    return SYSTEM_LOCALE
