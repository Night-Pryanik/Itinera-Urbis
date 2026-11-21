# Itinera Urbis: Hearth to Horizon

> An economic simulator of a single city's development through historical eras.

**Itinera Urbis: Hearth to Horizon** is a game about how a small settlement gradually turns into a complex city, developing production, technology and infrastructure on a procedurally generated hexagonal map.

There is no army of thousands of units, no manual control over every citizen, and no need to build every house tile by tile.

The main character is the **city**.

---

## 🎮 About the project

Itinera Urbis: Hearth to Horizon combines elements of:

- an economic simulator;
- resource management;
- a soft 4X;
- a historical city-builder;
- procedural world generation.

The player explores the surrounding territory, gains access to new resources, builds production buildings, develops technologies and gradually expands the city's area of influence.

At the same time, most of the economy runs automatically. The player mostly makes decisions about **what to develop**, rather than doing constant micromanagement.

---

## 🌍 The world

Every new game starts with a procedurally created map.

The map consists of hexagons and contains:

- various terrain types;
- forests and other types of vegetation cover;
- rivers, lakes, marshes and seas;
- common and rare resources;
- one-time natural finds;
- territories of the city and towns;
- fog of war.

Resources may be visible before they can be used. Some of them require the corresponding technology to extract or process.

Other resources, such as underground metal deposits, may remain hidden until the corresponding technology is developed.

---

## 🏙️ The city

The city is the central element of the game.

Inside the city there are production buildings that form resource processing chains:

~~~text
natural resource
       ↓
   improvement
       ↓
     raw resource
       ↓
production building
       ↓
processed resource
       ↓
next production
~~~

Buildings have production slots and recipes.

As the city develops, buildings can be upgraded, yielding more advanced versions with additional capabilities. Upgrading a building is an ordinary construction task and uses the same shared labour mechanism as construction.

---

## 👥 Population and labour

The city's residents are not individual characters that have to be controlled manually.

They represent the available workforce.

Every active production or construction action requires work time.

The number of simultaneous actions is limited by the city's population:

> one resident can take part in at most one action at a time.

If there are fewer active tasks than residents, the remaining residents are free.

If there are more tasks than available workforce, they are completed more slowly.

Labour is not a resource that can be stored in a warehouse.

---

## 🔬 Technologies

Technologies unlock new opportunities for the city:

- buildings;
- terrain improvements;
- resources;
- production methods;
- new game mechanics;
- production bonuses;
- new stages of development.

The technology tree consists of eras and dependency chains.

Some technologies have several mandatory predecessors, and parallel branches can develop independently.

What the city actually uses depends first of all on the resources available on the map: many technologies exist as alternative ways to solve the same problem, and which of them the player takes is decided by what the region offers — or does not offer.

---

## ⛏️ Resources

Itinera Urbis: Hearth to Horizon's economy is built around interconnected resource chains.

A single raw material can have several uses at once, which creates real economic decisions:

> use a rare resource now, or save it for more valuable production?

The game also has one-time natural resources — an analogue of the foraging mechanic: wild plants, native metals and other one-off finds that disappear after being gathered.

---

## 🎨 Production and quality

Itinera Urbis: Hearth to Horizon uses a data-driven approach.

Resources, buildings, technologies, recipes and terrain types are described by data, rather than by hard-coded logic for individual objects.

This makes it possible to create complex production chains without rewriting code for every new resource.

The game also develops a system of resource and product quality.

---

## ✨ Procedural products

One of the project's planned systems is procedurally generated production results.

Instead of creating a separate recipe for every combination of ingredients, a recipe defines a base product, and additional ingredients modify it.

A base product — clothing, an ornament, any other item — can receive several additional materials: a dye, a trim, an inset stone. Each addition changes the description and the properties of the result.

This makes it possible to create a large number of product variants without a combinatorial explosion in the number of recipes and individual items.

---

## 🗺️ Territory expansion

The city starts with a limited area of influence.

As it develops, it gains the ability to expand its influence and explore the surrounding region.

Scouts can be sent to any point on the map that the screen can be scrolled to — including the territory of towns and the unexplored fog of war. But only after researching the **Cartography** technology: before that, scouting is limited to the unexplored part of the Region, and hexes in the fog of war cannot be hovered over or clicked. Claiming (buying) new hexes, however, remains possible only within the Region — the strips around the Ring of Influence.

Both scouting and claiming work **only from the border of the known world**: a chunk must border the Ring of Influence or already explored hexes. Scouts do not jump over unexplored land — the border of the known world expands forward chunk by chunk, and "pockets" in the fog of war cannot be scouted. For a chunk that does not adjoin, the action button is greyed out and explains the reason. A hex in the fog of war reveals no information: neither the tooltip on hover nor the left column of the panel shows terrain and resources until the hex is explored.

Scouting and claiming are paid for with **coins from the city treasury**: the price is calculated per hex of the chunk and grows with distance from the city. Claiming additionally requires labour: it accumulates over time, as in construction.

Exploring and claiming territory make it possible to discover new resources and opportunities.

When advancing to the next stage of development, the area of influence expands in a jump, opening a new scale of city development.

---

## 🏘️ Towns

Besides the main city, the map may contain small settlements — **towns**.

They have:

- their own names;
- their own area of influence;
- a separate visual border design;
- colour-coded territory.

The names of cities and towns are procedurally chosen from a large set of invented toponyms.

The world is deliberately not tied to a single historical culture: toponyms may evoke the naming traditions of very different real-world cultures, as well as deliberate cultural hybrids.

This is part of the world's artistic design.

---

## 🧠 Design principles

Itinera Urbis: Hearth to Horizon follows several important principles.

### 95/5

About 95% of the economy should run automatically.

The player intervenes where a decision is genuinely required.

### The city is the main character

Residents are first and foremost workforce.

The game does not try to turn every resident into a separately simulated NPC.

### Data-driven

Resources, buildings, recipes, technologies and other game elements should be defined by data wherever possible.

This simplifies the project's development and opens up the possibility of mods.

### Availability decides

The player works with what the map provides. The set of resources available in a region determines which production paths and technologies make sense there — the same building or craft can remain relevant through all eras if its resource stays available.

### Minimum micromanagement

The player should manage the city's economy, not constantly press buttons to keep it running.

### Economy matters more than the amount of content

A new resource or building should create an interesting connection with the existing economy, rather than simply lengthening the list of items.

---

## 🛠️ Tech stack

The project is developed in **Godot** (GDScript).

All game data — resources, buildings, technologies, recipes, terrains — lives in JSON files, which keeps the game data-driven and moddable.

---

## 📌 Development philosophy

Itinera Urbis: Hearth to Horizon does not try to be a maximally realistic historical reconstruction.

History is used as a source of:

- technologies;
- materials;
- production processes;
- cultural images;
- ideas for the economy.

But the ultimate goal is to create a self-contained game system.

If a historical detail makes the economy more interesting, it may appear in the game.

If it only adds micromanagement or creates a useless resource, it can be dropped.

---

## 📖 Documentation

The design principles, the worldview of the game and the intended structure of its systems are described in:

`design_doc.md`

When key game systems change, the documentation must be updated together with the code.

---

## 🤝 Contributing

Bug reports, fixes, new resources, translations and mods are all welcome. The
rules of the code, the tests and the translation catalog are described in
[`.github/CONTRIBUTING.md`](.github/CONTRIBUTING.md), the rules of the community
in [`.github/CODE_OF_CONDUCT.md`](.github/CODE_OF_CONDUCT.md), and the names of the
authors are listed in [`AUTHORS`](AUTHORS).

## 📜 License

The project is licensed in two parts:

| Part | Where | License |
|---|---|---|
| Code — scripts, scenes, tests, tools | `scripts/`, `scenes/`, `tests/`, `tools/` | CC BY-NC-SA 4.0 — [`LICENSE`](LICENSE) |
| Artwork and game data — icons, tilesets, JSON data, texts | `icons/`, `tilesets/`, `data/`, `locale/` | CC BY 4.0 — [`LICENSE-ASSETS.md`](LICENSE-ASSETS.md) |

In plain words:

- **the code** may be read, changed and shared by anyone; it may not be used to make
  money, so nobody may sell Itinera Urbis: Hearth to Horizon or a paid game built on this code; a changed
  version must stay under the same license, so it remains open;
- **the artwork and the data** may be reused by anyone, including for money, as long
  as Itinera Urbis: Hearth to Horizon is credited — which is what a mod that reuses vanilla icons or vanilla
  data has to do.

Third-party components — the bundled font and the engine — keep their own licenses
and are listed in [`NOTICE.md`](NOTICE.md).

Mods are third-party content: a mod carries its own license, stated by its author.
The two mods that ship with the game are part of the project and follow the licenses
above.

The name **Itinera Urbis: Hearth to Horizon**, the logo and the branding are not covered by the license.
The license grants permission to use the material, not to present a modified or
derived work as the original game.
