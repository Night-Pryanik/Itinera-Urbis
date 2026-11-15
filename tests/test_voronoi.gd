# The two walks the relief is built on: the neighbour table of a hex and the Voronoi diagram of the
# centres. Both are read for every hex of the world several times, so they work on flat indices
# (row * cols + col) instead of dictionaries; these cases pin the properties the flat versions must
# keep — the neighbours must be the neighbours, and the diagram must be exact.
#
#   godot --headless --path . --script res://tests/test_voronoi.gd
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")

var _gdata = null
var _cdata = null
var _generator = null
var _hu = null

func _initialize() -> void:
    WATCHDOG.arm(self)
    call_deferred("_run")

func _run() -> void:
    var state := {"failed": false}
    await process_frame
    get_root().get_node("SaveManager").new_game()
    _gdata = get_root().get_node("GameData")
    _cdata = get_root().get_node("CityData")
    _generator = load("res://scripts/map_generator.gd").new()
    _hu = load("res://scripts/HexUtils.gd")

    if WATCHDOG.wants_case("neighbour_indices"):
        _test_neighbour_indices(state)
    if WATCHDOG.wants_case("nearest_centre"):
        _test_nearest_centre(state)
    if WATCHDOG.wants_case("outward_corridor"):
        _test_outward_corridor(state)

    _generator.free()
    WATCHDOG.report_skipped()
    if state["failed"]:
        print("VORONOI TEST FAILED")
        quit(1)
    else:
        print("VORONOI TEST OK")
        quit(0)

# The flat neighbour indices of a hex are the neighbours get_neighbors_odd_r names, in the same
# order: a stage that reads the index table must not disagree with the rest of the game about where
# the neighbours of a hex are.
func _test_neighbour_indices(state: Dictionary) -> void:
    for sizes in [[1, 1], [2, 3], [5, 4], [9, 13]]:
        var rows: int = sizes[0]
        var cols: int = sizes[1]
        var into := PackedInt32Array()
        into.resize(6)
        for r in range(rows):
            for c in range(cols):
                var count: int = _hu.fill_neighbor_indices(r, c, rows, cols, into)
                var expected: Array = _hu.get_neighbors_odd_r(r, c, rows, cols)
                check(count == expected.size(),
                        "(%d,%d) of %dx%d: %d indices for %d neighbours" %
                        [r, c, rows, cols, count, expected.size()], state)
                for i in range(mini(count, expected.size())):
                    var hex: Dictionary = expected[i]
                    check(into[i] == hex.row * cols + hex.col,
                            "(%d,%d) of %dx%d: the neighbour %d is (row %d, col %d), not index %d" %
                            [r, c, rows, cols, i, hex.row, hex.col, into[i]], state)

# Every hex is claimed by the nearest centre: the diagram is exact in the hex metric, so a lake
# centre cannot reach around a ridge into the yard of the city and the boundaries of two terrains
# are the ones the distance between the hexes says.
func _test_nearest_centre(state: Dictionary) -> void:
    var rows := 40
    var cols := 40
    var rng := RandomNumberGenerator.new()
    rng.seed = 20261115
    var centers: Array = []
    for _i in range(60):
        centers.append({"r": rng.randi() % rows, "c": rng.randi() % cols, "terrain": "plain"})
    # Two centres on one hex: the first one keeps it, as the generator's own centres cannot share a
    # hex either.
    centers.append({"r": 0, "c": 0, "terrain": "hill"})
    var owner: PackedInt32Array = _generator._build_voronoi(rows, cols, centers)
    check(owner.size() == rows * cols, "the diagram does not cover the map", state)
    var wrong := 0
    for r in range(rows):
        for c in range(cols):
            var ci: int = owner[r * cols + c]
            if ci < 0:
                wrong += 1
                continue
            var nearest_distance := 1 << 30
            for index in range(centers.size()):
                var center: Dictionary = centers[index]
                var distance: int = _hu.hex_distance(r, c, int(center.r), int(center.c))
                if distance < nearest_distance:
                    nearest_distance = distance
            var chosen: Dictionary = centers[ci]
            if _hu.hex_distance(r, c, int(chosen.r), int(chosen.c)) != nearest_distance:
                wrong += 1
    check(wrong == 0, "%d hexes are not claimed by a nearest centre" % wrong, state)

# A city walled in by water still gets a way out: the corridor is laid through the impassable hexes
# to the edge of the map. The map is all water, so the first walk of the corridor stage cannot find
# an exit and the breakthrough is the only thing that can save the city.
func _test_outward_corridor(state: Dictionary) -> void:
    var rows := 20
    var cols := 20
    var city_row := 10
    var city_col := 10
    var tile_data: Array = _generator.init_tile_data(rows, cols)
    for r in range(rows):
        for c in range(cols):
            tile_data[r][c]["terrain"] = "lake"
            tile_data[r][c]["climate"] = ""
    tile_data[city_row][city_col]["terrain"] = "plain"
    _generator.ensure_outward_corridor(tile_data, rows, cols, city_row, city_col)
    check(_reaches_edge(tile_data, rows, cols, city_row, city_col),
            "the city has no way out of a map of water", state)

# Whether the city reaches the edge of the map over the passable hexes.
func _reaches_edge(tile_data: Array, rows: int, cols: int, city_row: int,
        city_col: int) -> bool:
    var seen := {}
    var queue: Array = [Vector2i(city_row, city_col)]
    seen[Vector2i(city_row, city_col)] = true
    var head := 0
    while head < queue.size():
        var current: Vector2i = queue[head]
        head += 1
        if current.x == 0 or current.x == rows - 1 or current.y == 0 or current.y == cols - 1:
            return true
        for neighbour in _hu.get_neighbors_odd_r(current.x, current.y, rows, cols):
            var key := Vector2i(neighbour.row, neighbour.col)
            if seen.has(key):
                continue
            if int(_gdata.terrains.get(tile_data[neighbour.row][neighbour.col]["terrain"],
                    {}).get("move_cost", 1)) >= 999:
                continue
            seen[key] = true
            queue.append(key)
    return false

func check(condition: bool, message: String, state: Dictionary) -> void:
    if not condition:
        state["failed"] = true
        print("FAIL: ", message)
