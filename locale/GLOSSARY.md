# Itinera Urbis — glossary for translators

## What this is

The project is written in **English as its source language**: the English text
lives directly in the code, in the scenes and in `data/*.json`, and is what the
`msgid` of every catalog entry is built from.

The game was originally authored in Russian, and the original wording is kept in
the table below as a **reference column**. It explains what a term was before
the English pass, and it is *not* a target language. Translators of any language
work from the English column; the reference column only helps when the intended
meaning of a term is unclear.

Each target language gets its own catalog in `locale/`:

```
locale/messages.pot   # template: every source message, empty msgstr
locale/<code>.po       # one file per target language
```

When a new language is added, drop in `locale/<code>.po` next to the others and
register it in `project.godot` under
`internationalization/locale/translations`. No code changes are needed.

The catalog is the only file a language needs. The engine reads the `.po` with its
own loader (`TranslationLoaderPO`), so there is no import step and no compiled
copy: `res://locale/<code>.po` is what is loaded, and no `.mo` is shipped or read.
The header of the file carries the `Language:` field and the `Plural-Forms` rule,
which tells the engine how many forms a numeral has in that language (see "Plural
forms").

Two optional pieces follow the language rather than the translation:

- `msgctxt "language.name"`, `msgid` = the code of the language itself, and the
  native name in the `msgstr` (`"fr"` → `"Français"`). The settings read it from
  that catalog, so the list reads natively whatever interface language is on.
  Without the entry the engine's table gives the English name (`"French"`);
- `locale/city_names_<code>.json`, the pool of city names — a language without a
  pool of its own names its cities from the source pool.

## Rules for translating

1. **Placeholders are untouchable.** `%s`, `%d`, `%.0f`, `%05.2f`, `%%`, `%.2f`
   carry over verbatim, in the same number and the same order. Do not swap `%s`
   for `%v`, do not add placeholders, do not remove any.
2. **Keep every `\n`** exactly as it is, including leading and trailing
   newlines — they control line breaks and indentation inside tooltips.
3. No curly braces in the translated text.
4. Address the player in the second person, present tense: "Select a tile",
   "Not enough resources".
5. Short labels (buttons, tabs, headings) take no trailing period. Full
   sentences and hints take a period.
6. Capitalisation: ordinary labels in sentence case — `Resources`,
   `Built buildings`, `Cancel construction`. Imperative button commands are
   capitalised — `Build`, `Back`, `Trade`.
7. Do not invent UI that does not exist. If a string is a hint for an action,
   translate it as an instruction to the player.
8. Numbers and units: keep the original (`%d сек.` → `%d sec.`), but a decimal
   separator written with a comma in the original becomes a period in the
   translated text when it is part of the text rather than a value.
9. Units: `км` → `km`, `м` → `m`, `кг` → `kg`.
10. Quotes «…» become plain quotes, or no quotes if the meaning survives.

## Terminology

| Reference wording (original authoring) | English (source) |
|---|---|
| гекс, клетка | hex, tile |
| город | city |
| городок, поселение | town, settlement |
| житель, граждане, население | citizen, citizens, population |
| рабочий | worker |
| специалист | specialist |
| профессия | profession |
| здание | building |
| постройка, строительство | construction |
| слоты для производства | production slots |
| склад, запасы | storage, supplies |
| казна | treasury |
| доход | income |
| расход | expenses |
| баланс | balance |
| налог, налоги | tax, taxes |
| подушный налог | poll tax |
| торговля, торговец | trade, merchant |
| тариф | tariff |
| рынок, внутренний рынок | market, domestic market |
| цена | price |
| стоимость | cost |
| скидка, наценка | discount, markup |
| качество | quality |
| работа мастера | workmanship |
| ресурс | resource |
| сырьё | raw resource |
| продукт, товар | goods |
| группа продуктов | goods group |
| рецепт | recipe |
| производство | production |
| потребление | consumption |
| запас | supply |
| технология | technology |
| исследование | research |
| наука | science |
| улучшение | improvement |
| территория | territory |
| границы, влияние города | borders, city influence |
| владение | control |
| разведка | scouting |
| разведчик, разведчики | scout, scouts |
| обследование | surveying |
| освоение территории | claiming land |
| освоить | claim |
| отменить | cancel |
| подтвердить | confirm |
| назад | back |
| закрыть | close |
| продолжить | continue |
| эпоха | era |
| переход в эпоху | advance to the next era |
| карта | map |
| река | river |
| дорога | road |
| мост | bridge |
| лес | forest |
| вырубка леса | clear forest |
| болото | marsh |
| осушение | drainage |
| горы | mountains |
| глина | clay |
| камень | stone |
| песок | sand |
| руда | ore |
| слиток | ingot |
| зерно | grain |
| мука | flour |
| ткань | cloth |
| ковёр | carpet |
| пряжа | yarn |
| краситель | dye |
| кожа | leather |
| мёд | honey |
| вино | wine |
| пиво | beer |
| мясо | meat |
| говядина | beef |
| свинина | pork |
| баранина | mutton |
| козлятина | goat meat |
| конина | horsemeat |
| оленина | venison |
| скот, домашний скот | livestock |
| голова (единица скота) | head |
| стадо | herd |
| разведение, закладка стада | breeding |
| одомашнивание | domestication |
| бойня | slaughterhouse |
| монета | coin |
| пастбище | pasture |
| ферма | farm |
| плантация | plantation |
| сад | orchard |
| мельница | mill |
| кузница | forge |
| пекарня | bakery |
| шахта | mine |
| лесопилка | sawmill |
| каменоломня | quarry |
| верфь | shipyard |
| амбар | granary |
| склад | warehouse |
| рынок | market |
| пристань | harbor |
| маяк | lighthouse |
| обсерватория | observatory |
| библиотека | library |
| школа | school |
| мастерская | workshop |

## Where the text comes from

* `scripts/*.gd` — user-visible strings are wrapped in `tr(...)`. Inside
  `static func` use `TranslationServer.translate(...)` instead: GDScript does
  not allow `tr()` in a static context, and it does exactly the same thing.
* `scenes/*.tscn` — the `text` / `tooltip_text` properties are translated by
  Godot itself, so the property value is the `msgid`. No `tr()` needed.
* `data/*.json` — the `name`, `description` and `flavor` fields are
  player-visible; the translation is applied when the files are read
  (`scripts/data_loader.gd`). The English text stays in the JSON.
* Invented proper nouns (the city names in `locale/city_names_<code>.json`, one pool
  per language) are **not** translated — they are treated as names, not as text.

## When one English text needs several translations

A language may need more forms of a word than English has. Russian, for
example, has three cases where English has one:

| need | English msgid | Russian |
|---|---|---|
| subject of a sentence | `Building` | Здания |
| object after "a reference to" | `this building` | это здание |
| "present in ___" | `building` | здании |

Two ways to express that in the catalog:

1. **Different msgids** (`Building` / `this building` / `building`) — used by
   the data validator for entity names (`validator_entity_*`). Each form is
   its own translatable word, so no context is needed.
2. **Same msgid, different msgctxt** — used when one English text reads
   differently in another language depending on where it stands. The
   `covers.name_in_list` entries are an example: the same forest is «Лес» on its
   own and «лес» inside a list after a terrain, and German capitalises it in
   both places while Russian and French do not. The context is passed as the
   second argument to `tr()` / `TranslationServer.translate()`.

   Such a form is **optional**. A language that leaves it empty keeps reading
   the plain name everywhere: the loader writes the list form only when the
   catalog has one, because an empty `msgstr` comes back as the English msgid
   and would put the source text into a translated interface.

Choose form 1 when the surrounding English wording differs anyway (it is the
clearer catalog), and form 2 when the English word is genuinely one word.

## Plural forms

A numeral is **not** a context: the count picks the form by the rule of the
language, and that rule belongs to the catalog, not to the code. Such an entry
carries `msgid_plural` and one `msgstr[n]` per form the header declares in
`Plural-Forms`:

```
msgctxt "consumption_buildings"
msgid "building"
msgid_plural "buildings"
msgstr[0] "здание"
msgstr[1] "здания"
msgstr[2] "зданий"
```

English (`nplurals=2; plural=(n != 1);`), Russian (three forms) and a language
with a single form are all served by the same call: the code asks the engine
for the form of a given count (`TranslationServer.translate_plural`) and never
does arithmetic on the count itself.

The header has to be right — `nplurals` must match the number of `msgstr[n]`
entries, or the loader refuses the whole file.

## Rules for the data validator's texts

`scripts/data_validator.gd` reports broken cross-references in `data/*.json`
through a window (`scripts/data_problems_window.gd`).

* A problem record is split in two: a **language-independent structure**
  (`kind`, `ref_id`, `source_kind`, `field`, `file`, `line`) and the **text**
  (`headline`, `where`, `location`, `message`). The text is rebuilt from the
  structure by `DataValidator.build_text()`.
* Because of that split, changing the language re-renders the already open
  window without re-running the validation: the window listens to
  `LocalizationManager.locale_changed` and calls
  `DataValidator.localize_problems()`. The checks themselves never call
  `tr()`.
* Every `translate()` call in that file sits on **one line** and holds
  **exactly one** string literal. This is a requirement of
  `tools/i18n_build_po.py`, which parses the code line by line and takes the
  msgid from the literal inside the call. A multi-line call, a dictionary of
  texts, or a string concatenated inside the call would hide the msgid from
  the builder, and the text would stay English in every language.
* Identifiers (`hand_mill`, `produced_in`) and file paths are not translated —
  they are read from the data and must match it exactly.
