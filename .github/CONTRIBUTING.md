# Contributing to Itinera Urbis

Itinera Urbis is a game in active development. Everything is welcome: a bug report, a
fix, a new resource in the economy, a translation, a mod.

## The short version

1. Open an issue first for anything bigger than a typo fix — it saves everybody the
   work of a pull request that goes in the wrong direction.
2. Make one change per pull request, and describe what it changes and why.
3. Run the tests before you push.

## Running the game

The project is written in GDScript and needs **Godot 4.7**. Open the project folder
in Godot and press F5.

The project is data-driven: the economy — resources, recipes, buildings,
technologies, terrains — is described in `data/*.json`, and the code reads it. A
new good usually means a new record in the JSON and no code at all.

## Running the tests

GitHub Actions runs the full suite on pull requests when they are opened,
reopened, or updated with new commits. The **Godot tests** check shows the
result, and the workflow run provides a **godot-test-logs** artifact.

The tests are headless scripts in `tests/`. The runner starts Godot itself and
runs them in parallel:

```
python tools/run_tests.py            # the fast suite
python tools/run_tests.py --all      # every test
python tools/run_tests.py --only road,sea   # only the tests whose name matches
```

The runner looks for Godot in the usual places and in `PATH`; if it is somewhere
else, point it there with the `GODOT` environment variable.

A single test can also be run by hand:

```
godot --headless --path . --script res://tests/test_road_building.gd
```

After you add a **new** script with a `class_name`, the cache of the global
classes has to be rebuilt, otherwise the headless runs fail with "Identifier not
declared in the current scope":

```
godot --headless --path . --import
```

The JSON of the game data can be checked on its own:

```
python tools/validate_json.py
```

## The rules of the code

* Indentation is a four spaces, as in the rest of the project.
* The comments are in English, and they explain the current state of the system
  and the reason behind a decision — not the history of how it was written. A
  comment that only repeats the code is not needed.
* The game data is checked by the validator: a resource that is referenced by a
  recipe must exist, and the identifiers must be unique. The check runs on every
  start of the game and reports the broken references in a window.
* **There is no save migration.** The game does not keep the saves of older
  versions, and a change of the data format simply invalidates the old saves. Do
  not write code that converts the old saves.

The full description of the project and of its systems is in
[`design_doc.md`](../design_doc.md).

The rules of the community are in [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).

## Translations

English is the source language: the English text of a string is its key, and it
lives in the code and in the JSON of the data. Each target language has one
catalog, [`locale/<code>.po`](../locale) — the Russian one is
[`locale/ru.po`](../locale/ru.po).

Godot reads the `.po` itself: the engine has a loader for the format
(`TranslationLoaderPO`), so the catalog is loaded straight from
`res://locale/<code>.po` — the paths listed under
`internationalization/locale/translations` in `project.godot` — and no import
step, no `.godot/imported/` copy and no other build step takes part. The engine
can read `.mo` as well, but nothing in this project reads one: a `.mo` file in the
repository would be a second copy that nothing loads, nothing checks and nothing
updates with the `.po`, so the catalog is kept in `.po` alone and `.gitignore`
keeps a compiled catalog out of the repository.

A new string therefore needs two things: the English text in the code, and the
translation in `locale/<code>.po`.

### A new language

1. Put `locale/<code>.po` next to the others. The header of the file carries the
   `Language:` field and the `Plural-Forms` rule of that language.
2. Register it in `project.godot`:

   ```
   locale/translations=PackedStringArray("res://locale/ru.po", "res://locale/fr.po")
   ```

No code change is needed: the languages the settings offer are read from the
catalogs that are loaded (`scripts/localization_manager.gd`), not from a table in
the code.

Two optional pieces then make the language read like a language of its own:

- an entry that names it in its own tongue, `msgctxt "language.name"` with the
  code as the `msgid` (`"fr"` → `"Français"`). Without it the list falls back to
  the engine's language table, which gives the English name (`"French"`);
- `locale/city_names_<code>.json`, the pool of invented city names — a language
  without it takes the source pool.

The plural forms of a string are a `msgid_plural` entry with one `msgstr[n]` per
form that `Plural-Forms` declares for the language:

```
msgctxt "consumption_buildings"
msgid "building"
msgid_plural "buildings"
msgstr[0] "здание"
msgstr[1] "здания"
msgstr[2] "зданий"
```

The rule belongs to the catalog, and the code asks the engine for the form it
needs (`TranslationServer.translate_plural`), so a language with two forms, with
one form, or with six needs no change in the code.


## Mods

A mod is a separate work with its own license — the license of a mod is the
license of its author, and it is not bound by the license of the game. The
mechanism of the mods is described in [`mods/README.md`](../mods/README.md).

## The license of a contribution

The code of the game is published under CC BY-NC-SA 4.0, the artwork and the game
data under CC BY 4.0. By contributing you agree that your contribution is
published under the same license as the part it belongs to.

The names of the authors are listed in [`AUTHORS`](../AUTHORS).
