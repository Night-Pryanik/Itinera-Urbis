# aqueduct_manager.gd
# The model of the SECOND LAYER of the map improvements: the aqueducts.
#
# An ordinary improvement lives in tile["improvement"], one per hex. The aqueduct
# is independent of that slot: it may cross a hex that already carries a farm,
# a road or any other improvement, and it is stored as a network of segments
# between neighbouring hexes (the same idea as the roads, but a different
# network and a different drawing). The mountain spring itself is not an
# improvement: it is a hidden flag on a resource-less mountain, revealed by
# the technology "Concrete".
#
# Only one spring exists on the map, therefore only one aqueduct line is ever
# built; the manager is nevertheless a network, so a second spring added by a
# future mod would not need a new model.

extends Node

# The canonical segment key is shared with the project ghosts and the renderer.
const SEPARATOR := "|"

# key -> true. The segments are rebuilt from the per-hex flags on loading.
var segments: Dictionary = {}
# "row,col" -> true, the hexes touched by the network.
var connected_hexes: Dictionary = {}

static func segment_key(from_row: int, from_col: int, to_row: int, to_col: int) -> String:
    var a := from_row * 100000 + from_col
    var b := to_row * 100000 + to_col
    if a > b:
        var tmp := a
        a = b
        b = tmp
    return "%d%s%d" % [a, SEPARATOR, b]

static func hex_key(row: int, col: int) -> String:
    return "%d,%d" % [row, col]

func has_segment(from_row: int, from_col: int, to_row: int, to_col: int) -> bool:
    return segments.has(segment_key(from_row, from_col, to_row, to_col))

func is_hex_built(row: int, col: int) -> bool:
    return connected_hexes.has(hex_key(row, col))

func get_all_segments() -> Dictionary:
    return segments

func clear() -> void:
    segments.clear()
    connected_hexes.clear()

# Lays one section of the network. The per-hex flag is the input data for the
# save: the segments themselves are not written and are rebuilt from the flags
# after the load (see rebuild_from_tiles).
func build_step(from_row: int, from_col: int, to_row: int, to_col: int,
        tile_data: Array) -> void:
    segments[segment_key(from_row, from_col, to_row, to_col)] = true
    connected_hexes[hex_key(from_row, from_col)] = true
    connected_hexes[hex_key(to_row, to_col)] = true
    _mark_hex(tile_data, from_row, from_col)
    _mark_hex(tile_data, to_row, to_col)

func _mark_hex(tile_data: Array, row: int, col: int) -> void:
    if row >= 0 and row < tile_data.size() and col >= 0 and col < tile_data[row].size():
        if tile_data[row][col] != null:
            tile_data[row][col]["aqueduct"] = true

# Recreates the network from the flags stored on the hexes. Two neighbouring
# hexes carrying the flag are joined by a section; this is enough for a line
# that always grows as one connected chain from the spring to the city.
func rebuild_from_tiles(tile_data: Array, map_rows: int, map_cols: int) -> void:
    clear()
    for row in range(map_rows):
        for col in range(map_cols):
            if row >= tile_data.size() or col >= tile_data[row].size():
                continue
            var tile = tile_data[row][col]
            if tile == null or not bool(tile.get("aqueduct", false)):
                continue
            connected_hexes[hex_key(row, col)] = true
            for n in HexUtils.get_neighbors_odd_r(row, col, map_rows, map_cols):
                if n.row < row or (n.row == row and n.col < col):
                    continue
                if n.row >= tile_data.size() or n.col >= tile_data[n.row].size():
                    continue
                var neighbor = tile_data[n.row][n.col]
                if neighbor != null and bool(neighbor.get("aqueduct", false)):
                    segments[segment_key(row, col, n.row, n.col)] = true

# Whether a hex can carry an aqueduct section. Water and impassable terrain are
# excluded; a mountain is allowed because the spring itself is a mountain, and
# a rocky ridge is exactly where an aqueduct needs a tunnel.
static func is_passable_terrain(terrain_id: String) -> bool:
    if terrain_id == "" or MapHelpers.is_water_terrain(terrain_id):
        return false
    var data: Dictionary = GameData.terrains.get(terrain_id, {})
    return int(data.get("move_cost", 1)) < 999

# Plans the whole line from the spring to the city at once. Dijkstra over the
# land hexes, weighted by the movement cost of the terrain: the line prefers a
# gentle detour to a steep ridge. The result is the full path (spring -> city)
# and the sections between its consecutive hexes. The plan is pure: it never
# touches tile_data and never starts a project.
func plan(tile_data: Array, map_rows: int, map_cols: int,
        spring_row: int, spring_col: int, city_row: int, city_col: int) -> Dictionary:
    if spring_row < 0 or spring_row >= map_rows or spring_col < 0 or spring_col >= map_cols:
        return {"ok": false, "reason": "The spring is outside the map"}
    if city_row < 0 or city_row >= map_rows or city_col < 0 or city_col >= map_cols:
        return {"ok": false, "reason": "The city is outside the map"}
    var start_key := hex_key(spring_row, spring_col)
    var goal_key := hex_key(city_row, city_col)
    var distance := {start_key: 0.0}
    var previous := {}
    var queue: Array = [{"row": spring_row, "col": spring_col, "cost": 0.0}]

    while not queue.is_empty():
        var best_index := 0
        for i in range(1, queue.size()):
            if float(queue[i].cost) < float(queue[best_index].cost):
                best_index = i
        var current: Dictionary = queue.pop_at(best_index)
        var row := int(current.row)
        var col := int(current.col)
        var cost := float(current.cost)
        var current_key := hex_key(row, col)
        if cost > float(distance.get(current_key, INF)) + 0.0001:
            continue
        if current_key == goal_key:
            break
        for n in HexUtils.get_neighbors_odd_r(row, col, map_rows, map_cols):
            if n.row < 0 or n.row >= map_rows or n.col < 0 or n.col >= map_cols:
                continue
            var tile = tile_data[n.row][n.col]
            if tile == null or not is_passable_terrain(str(tile.get("terrain", "plain"))):
                continue
            var terrain_data: Dictionary = GameData.terrains.get(str(tile.get("terrain", "plain")), {})
            # The mountain of the spring is passable, but every other ridge is
            # avoided when a flank exists: its movement cost is the weight.
            var weight := 1.0 + maxf(0.0, float(terrain_data.get("move_cost", 1)) - 1.0)
            var next_key := hex_key(n.row, n.col)
            var next_cost := cost + weight
            if next_cost < float(distance.get(next_key, INF)) - 0.0001:
                distance[next_key] = next_cost
                previous[next_key] = {"row": row, "col": col}
                queue.append({"row": n.row, "col": n.col, "cost": next_cost})

    if not distance.has(goal_key):
        return {"ok": false, "reason": "No land route from the spring to the city"}

    var path: Array = []
    var key := goal_key
    while true:
        var parts := key.split(",")
        path.append({"row": int(parts[0]), "col": int(parts[1])})
        if key == start_key:
            break
        if not previous.has(key):
            return {"ok": false, "reason": "No land route from the spring to the city"}
        var prev: Dictionary = previous[key]
        key = hex_key(int(prev.row), int(prev.col))
    path.reverse()

    var sections: Array = []
    for i in range(1, path.size()):
        var a: Dictionary = path[i - 1]
        var b: Dictionary = path[i]
        sections.append({
            "from": {"row": int(a.row), "col": int(a.col)},
            "to": {"row": int(b.row), "col": int(b.col)},
            "key": segment_key(int(a.row), int(a.col), int(b.row), int(b.col)),
        })
    return {"ok": true, "path": path, "sections": sections}
