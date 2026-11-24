# Multilingual support test (headless):
#   godot --headless --path . --script res://tests/test_multilingual.gd
#
# The game ships more than one language, and nothing in the code may prefer one of
# them. This test pins the four places where a language could otherwise be written
# into the code, so that adding a catalog stays a data change:
#
#   1) THE LANGUAGE LIST. The settings offer every language whose catalog is loaded,
#      plus the source one — not a table in LocalizationManager. A language is hidden
#      by removing its catalog, and its name is the one the language gives itself.
#   2) THE PLURAL FORMS. The count of working buildings takes its form from the rule
#      the catalog declares (Plural-Forms), not from an arithmetic on the count in the
#      code. The catalog of a language with other forms therefore needs no code change.
#   3) THE CASE OF A LIST. A cover inside "Terrain, Cover" reads in the form the catalog
#      gives it (covers.name_in_list), so the language decides the case of the later
#      parts, and no language needs a case rule of its own in the code.
#   4) THE LETTER CHECK. The characters a font has to draw come from the translated
#      text of the language itself, so a catalog with any script is covered without an
#      alphabet table in the code.
#
# A catalog written here is synthetic and lives in user://: the test must not depend on
# what the shipped catalog happens to contain, and it must not edit locale/.
extends SceneTree

# Hang watchdog: without it, an aborted _initialize() coroutine looks from the
# outside like eternal silence. Details — in tests/watchdog.gd.
const WATCHDOG = preload("res://tests/watchdog.gd")

# The exception, with the reason it is not a language preference: the manager itself is
# where the source language is named as the default one. Every other script is expected
# to treat the languages alike.
const LOCALE_ALLOWED := {
    "localization_manager.gd": "the manager names the source language as its default",
}

# The code and the texts of the synthetic language. It is Esperanto with a few
# characters accented on purpose (ĉ, ĝ, ĵ): the letters of the test have to be characters
# that appear in no Latin alphabet of the project, so that the check of the fonts can only
# pass by reading this catalog. The name is written in the catalog, not taken from the
# engine's table, so that the section of the language list depends on no table of Godot.
# The folder of the run. Outside locale/ on purpose: the test writes, the repository does
# not change.
const SANDBOX := "user://test_multilingual"

const SANDWICH_LOCALE := "eo"
const SANDWICH_NAME := "Esperanto"
const SANDWICH_FOREST := "arbaro"
const SANDWICH_LIST := "tropika arbaro"
# Two plural forms, but with a rule no other language of the project uses: the test
# proves the form is read from the catalog rather than guessed from the count.
const SANDWICH_PO := """msgid ""
msgstr ""
"Project-Id-Version: test\\n"
"Language: eo\\n"
"MIME-Version: 1.0\\n"
"Content-Type: text/plain; charset=UTF-8\\n"
"Content-Transfer-Encoding: 8bit\\n"
"Plural-Forms: nplurals=2; plural=(n != 1);\\n"

msgctxt "language.name"
msgid "eo"
msgstr "Esperanto"

msgctxt "consumption_buildings"
msgid "building"
msgid_plural "buildings"
msgstr[0] "konstruaĵo"
msgstr[1] "konstruaĵoj"

msgctxt "terrains.name"
msgid "Tropical, Plain"
msgstr "Tropika, ebenaĵo"

msgctxt "covers.name"
msgid "Tropical Rainforest"
msgstr "Tropika pluvarbaro"

msgctxt "covers.name_in_list"
msgid "Tropical Rainforest"
msgstr "tropika arbaro"
"""


func _initialize():
    WATCHDOG.arm(self)
    var state = {"failed": false}

    _test_language_list(state)
    _test_plural_rule(state)
    _test_list_form(state)
    _test_letters(state)
    _test_no_hardcoded_locale(state)

    _cleanup()

    if state["failed"]:
        print("MULTILINGUAL TEST FAILED")
        quit(1)
    else:
        print("MULTILINGUAL TEST OK")
        quit(0)


# --- 0. Helpers ---------------------------------------------------------------------

# Loads a catalog the way the project loads its own: a .po file read by the engine's
# Translation loader. The file is written to user://, so the repository is untouched.
func _load_synthetic(locale: String, po: String, variant: String = "") -> Translation:
    var dir := SANDBOX
    DirAccess.make_dir_recursive_absolute(dir)
    var path := dir.path_join("test_%s%s.po" % [locale, variant])
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(_declared_as(po, locale))
    file.close()
    # The cache of the resource loader is refreshed rather than reused: a section that
    # writes another catalog to the same path must not be served the previous answer.
    var translation: Translation = ResourceLoader.load(
            path, "Translation", ResourceLoader.CACHE_MODE_REPLACE)
    # A catalog the engine refuses (a broken header, a count of forms that does not match
    # nplurals) comes back as null: adding it would be a crash, not a test failure.
    if translation != null:
        TranslationServer.add_translation(translation)
    return translation


# The catalogs of the run are removed: another test run must not find a language of the
# previous one, and the folder of the player must not keep a file of a test.
func _cleanup() -> void:
    var dir := DirAccess.open(SANDBOX)
    if dir == null:
        return
    dir.list_dir_begin()
    var name := dir.get_next()
    while name != "":
        if not dir.current_is_dir():
            dir.remove(name)
        name = dir.get_next()
    dir.list_dir_end()
    DirAccess.remove_absolute(SANDBOX)


func _unload(translation: Translation) -> void:
    if translation != null:
        TranslationServer.remove_translation(translation)


# The same catalog with the covers.name_in_list entry taken out: a language that
# translated a cover but left its list form alone.
func _without_list_form(po: String) -> String:
    var kept: Array = []
    var dropping := false
    for line in po.split("\n"):
        if line.begins_with("msgctxt"):
            dropping = line.contains("covers.name_in_list")
        if not dropping:
            kept.append(line)
    return "\n".join(kept)


# The same catalog with the "Language:" field of the header replaced: the engine takes
# the locale of a .po from exactly that field.
func _declared_as(po: String, declared: String) -> String:
    var lines := po.split("\n")
    for i in lines.size():
        if lines[i].begins_with("\"Language:"):
            lines[i] = "\"Language: %s\\n\"" % declared
    return "\n".join(lines)


func _find(languages: Array, code: String) -> Dictionary:
    for lang in languages:
        if str(lang["code"]) == code:
            return lang
    return {}


# --- 1. The language list ------------------------------------------------------------

func _test_language_list(state: Dictionary) -> void:
    var localization = get_root().get_node("LocalizationManager")
    var offered: Array = localization.described_languages()
    check(_find(offered, "ru") != {}, "the shipped Russian catalog is offered", state)
    check(_find(offered, localization.DEFAULT_LOCALE) == {},
        "the source language is not in the list of catalogs: it has no catalog of its own", state)
    check(_find(localization.available_languages(), localization.DEFAULT_LOCALE) != {},
        "the source language is still selectable", state)

    # The name comes from the catalog of that language, not from the code and not from
    # the engine's English table ("Russian" would be the engine's answer).
    var russian := str(_find(offered, "ru").get("name", ""))
    check(russian != "Russian",
        "a language is named by its own catalog, not by the engine's English table, got \"%s\""
            % russian, state)
    check(not russian.is_empty(), "the language carries a name, got \"%s\"" % russian, state)

    # The source language is named as well: it has no catalog of its own, so the fallback
    # is what it gets — the engine's table or its bare code, both readable.
    var english := str(_find(localization.available_languages(),
        localization.DEFAULT_LOCALE).get("name", ""))
    check(not english.is_empty(), "the source language carries a name, got \"%s\"" % english,
        state)
    # The dropdown draws every item through this label, so the source language has to be
    # known to it as well: a bare code in the list would read as "en".
    var source_label: String = localization.get_language_label(localization.DEFAULT_LOCALE)
    check(source_label != localization.DEFAULT_LOCALE,
        "the source language is labelled, got \"%s\"" % source_label, state)

    # A catalog that is not loaded means a language that is not offered: the list is
    # built from the loaded catalogs, so this is the same mechanism a new .po uses.
    var translation := _load_synthetic(SANDWICH_LOCALE, SANDWICH_PO)
    check(translation != null, "the synthetic catalog is read as a Translation", state)
    var after: Array = localization.described_languages()
    var entry := _find(after, SANDWICH_LOCALE)
    check(entry != {}, "a newly loaded catalog appears in the list with no code change", state)
    check(str(entry.get("name", "")) == SANDWICH_NAME,
        "the language names itself, got \"%s\"" % str(entry.get("name", "")), state)
    check(localization.is_supported(SANDWICH_LOCALE),
        "a language with a loaded catalog is selectable", state)
    _unload(translation)

    var removed := _find(localization.described_languages(), SANDWICH_LOCALE)
    check(removed == {}, "a language whose catalog is gone is not offered", state)
    check(not localization.is_supported(SANDWICH_LOCALE),
        "a language with no catalog is not selectable", state)

    # The codes are sorted, so the dropdown does not follow the registration order.
    var codes: Array = []
    for lang in localization.described_languages():
        codes.append(str(lang["code"]))
    var sorted_codes := codes.duplicate()
    sorted_codes.sort()
    check(codes == sorted_codes, "the languages are listed in a stable order", state)


# --- 2. The plural forms -------------------------------------------------------------

func _test_plural_rule(state: Dictionary) -> void:
    var ConsumptionUI = load("res://scripts/consumption_ui.gd")
    TranslationServer.set_locale("ru")

    # Russian: 1 здание, 2 здания, 5 зданий, 21 здание, 11 зданий.
    var cases := {1: "здание", 2: "здания", 5: "зданий",
        21: "здание", 11: "зданий", 22: "здания"}
    for count in cases:
        var got := str(ConsumptionUI._buildings_plural(count))
        check(got == cases[count],
            "the Russian catalog gives \"%s\" for %d, got \"%s\"" % [cases[count], count, got],
            state)

    # The source language gives its own answer without any catalog: TranslationDomain
    # returns the msgid for 1 and the msgid_plural for every other count. It needs a
    # locale whose language nothing translates — the synthetic "eo" that a previous
    # section unloaded — because the shipped catalog of Russian is still registered.
    TranslationServer.set_locale(SANDWICH_LOCALE)
    check(ConsumptionUI._buildings_plural(1) == "building", "English: 1 building", state)
    check(ConsumptionUI._buildings_plural(5) == "buildings", "English: 5 buildings", state)

    # A catalog with its own rule serves its own forms with the same call: nothing in
    # the code counts modulo anything, the engine applies the catalog's rule.
    var translation := _load_synthetic(SANDWICH_LOCALE, SANDWICH_PO)
    TranslationServer.set_locale(SANDWICH_LOCALE)
    # The synthetic catalog is keyed by the very messages the game passes, and its own
    # Plural-Forms rule picks the form: (n != 1) gives form 0 for 1 and form 1 for 3.
    check(ConsumptionUI._buildings_plural(1) == "konstruaĵo",
        "a new catalog's singular form is used", state)
    check(ConsumptionUI._buildings_plural(3) == "konstruaĵoj",
        "a new catalog's plural form is used", state)
    TranslationServer.set_locale("ru")
    _unload(translation)


# --- 3. The case of a list -----------------------------------------------------------

func _test_list_form(state: Dictionary) -> void:
    var game_data = get_root().get_node("GameData")
    TranslationServer.set_locale("ru")
    game_data.load_all_data()

    # "Тропики, равнина, влажный тропический лес": the later parts are lowercase
    # in Russian. The loading has to take the list form from the SOURCE name — the
    # message is looked up before the names are translated, or the key would be
    # the translation.
    var name: String = game_data.terrain_display_name(
        "tropical_plain", "tropical_rainforest")
    check(name.ends_with("влажный тропический лес"),
        "Russian reads the cover in its list form, got \"%s\"" % name, state)
    check(not name.ends_with("Влажный тропический лес"),
        "the list form is not the plain name of the cover, got \"%s\"" % name, state)

    # The same cover outside a list keeps the capital: the two forms are different
    # messages of the catalog, and the list one does not leak into the plain name.
    var plain: String = str(game_data.covers.get("tropical_rainforest", {}).get("name", ""))
    check(plain == "Влажный тропический лес",
        "the plain name of the cover keeps its case, got \"%s\"" % plain, state)

    # The source language keeps the case of every part: it has no list form, and the
    # name it already has is the one that is read.
    TranslationServer.set_locale("en")
    game_data.load_all_data()
    var source_name: String = game_data.terrain_display_name(
        "tropical_plain", "tropical_rainforest")
    check(source_name.ends_with("Tropical Rainforest"),
        "the source language keeps the case of the cover, got \"%s\"" % source_name, state)

    # A language that has the form reads it, and one that has not is not broken by its
    # absence: it reads the plain name of the cover — its own, not the English key of the
    # message it did not translate. An untranslated message comes back as the key, so that
    # answer must never be taken for a translation.
    var translation := _load_synthetic(SANDWICH_LOCALE, SANDWICH_PO)
    TranslationServer.set_locale(SANDWICH_LOCALE)
    game_data.load_all_data()
    var with_form: String = game_data.terrain_display_name(
        "tropical_plain", "tropical_rainforest")
    check(with_form.ends_with(SANDWICH_LIST),
        "a language with the list form reads it, got \"%s\"" % with_form, state)

    _unload(translation)
    translation = _load_synthetic(SANDWICH_LOCALE, _without_list_form(SANDWICH_PO), "_plain")
    game_data.load_all_data()
    var without_form: String = game_data.terrain_display_name(
        "tropical_plain", "tropical_rainforest")
    check(without_form.ends_with(SANDWICH_FOREST),
        "a language without the list form reads the plain name, got \"%s\"" % without_form,
        state)
    check(not without_form.contains("Rainforest"),
        "the plain name of that language is not the source text, got \"%s\"" % without_form,
        state)

    _unload(translation)
    TranslationServer.set_locale("ru")
    game_data.load_all_data()


# --- 4. The letter check -------------------------------------------------------------

func _test_letters(state: Dictionary) -> void:
    # The autoload script is loaded here, not preloaded as a const: a const preload would
    # compile it before the autoloads are registered, and it refers to LocalizationManager.
    var font_manager_script = load("res://scripts/font_manager.gd")
    var ru_letters: String = font_manager_script.locale_letters("ru")
    check(ru_letters.contains("Ж"), "the Russian catalog brings its Cyrillic letters", state)
    check(ru_letters.contains("A"), "the source letters are always part of the check", state)
    check(not ru_letters.contains(" "), "the sample carries no whitespace", state)

    # A language with no catalog has nothing to check beyond the source letters.
    var unknown: String = font_manager_script.locale_letters("xx")
    check(unknown == font_manager_script.SOURCE_LETTERS,
        "a language with no catalog checks only the source letters", state)

    # The letters follow the catalog, so a catalog of another script is covered with no
    # table in the code that would have to list its alphabet. The catalog is declared as
    # a language of its own, so nothing of the project's own catalogs takes part.
    var translation := _load_synthetic(SANDWICH_LOCALE, SANDWICH_PO)
    var eo_letters: String = font_manager_script.locale_letters(SANDWICH_LOCALE)
    check(eo_letters.contains("ĵ"),
        "the letters come from the catalog of that language, got \"%s\"" % eo_letters, state)
    check(not eo_letters.contains("Р"),
        "another language does not bring the Russian letters", state)
    _unload(translation)

    # The check is a real check: a font without the letters is refused.
    var empty_font := FontFile.new()
    check(not font_manager_script.covers_locale(empty_font, "ru"),
        "a font that cannot draw the letters is refused", state)
    check(font_manager_script.covers_locale(empty_font, ""),
        "an empty language has nothing to check", state)


# --- 5. No locale in the logic -------------------------------------------------------

# A locale written into a condition is exactly what makes a new catalog need a code
# change, so the test reads the sources and refuses such a condition anywhere.
func _test_no_hardcoded_locale(state: Dictionary) -> void:
    var offenders: Array = []
    for path in _script_files("res://scripts"):
        if LOCALE_ALLOWED.has(path.get_file()):
            continue
        var source := FileAccess.get_file_as_string(path)
        for line in source.split("\n"):
            var text: String = line.strip_edges()
            if text.begins_with("#"):
                continue
            # A locale written into a comparison or a lookup: exactly what makes a new
            # catalog need a code change.
            for pattern in ["\"ru\"", "'ru'", "\"en\"", "'en'"]:
                if text.contains(pattern) and (text.contains("locale") or text.contains("LANG")):
                    offenders.append("%s: %s" % [path.get_file(), text])
                    break
    check(offenders.is_empty(),
        "no script may prefer a language: %s" % str(offenders), state)


# Every .gd file of a folder and of its subfolders.
func _script_files(folder: String) -> Array:
    var out: Array = []
    var dir := DirAccess.open(folder)
    if dir == null:
        return out
    dir.list_dir_begin()
    var name := dir.get_next()
    while name != "":
        if dir.current_is_dir():
            out.append_array(_script_files(folder.path_join(name)))
        elif name.ends_with(".gd"):
            out.append(folder.path_join(name))
        name = dir.get_next()
    dir.list_dir_end()
    return out


# The verdict of one check: the run continues after a failure, so that one broken
# section does not hide the state of the others.
func check(cond: bool, msg: String, state: Dictionary) -> void:
    if not cond:
        push_error("ASSERT: " + msg)
        print("ASSERT FAILED: ", msg)
        state["failed"] = true
