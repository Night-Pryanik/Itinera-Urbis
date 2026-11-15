@tool
class_name HexUtils

# The six neighbour offsets of the odd-r layout, per row parity. They are tables of the script, not
# of the call: the generation reads the neighbours of every hex of the map several times, and
# building the table inside the call cost more than the neighbours it serves.
const EVEN_ROW_OFFSETS: Array[Vector2i] = [
    Vector2i(0, -1), Vector2i(0, 1),
    Vector2i(-1, -1), Vector2i(-1, 0),
    Vector2i(1, -1), Vector2i(1, 0)
]
const ODD_ROW_OFFSETS: Array[Vector2i] = [
    Vector2i(0, -1), Vector2i(0, 1),
    Vector2i(-1, 0), Vector2i(-1, 1),
    Vector2i(1, 0), Vector2i(1, 1)
]

static func hex_center(row: int, col: int, radius: float) -> Vector2:
    var x_spacing = radius * sqrt(3)
    var y_spacing = radius * 1.5
    var x = col * x_spacing
    var y = row * y_spacing
    if row % 2 == 1:
        x += x_spacing / 2.0
    return Vector2(x, y)

static func hex_vertices(center_x: float, center_y: float, radius: float) -> PackedVector2Array:
    var verts = PackedVector2Array()
    for i in range(6):
        var angle_deg = 60 * i + 30
        var angle_rad = deg_to_rad(angle_deg)
        var x = center_x + radius * cos(angle_rad)
        var y = center_y + radius * sin(angle_rad)
        verts.append(Vector2(x, y))
    return verts

static func point_in_polygon(x: float, y: float, poly: PackedVector2Array) -> bool:
    var n = poly.size()
    var inside = false
    var j = n - 1
    for i in range(n):
        var xi = poly[i].x
        var yi = poly[i].y
        var xj = poly[j].x
        var yj = poly[j].y
        if ((yi > y) != (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi) + xi):
            inside = not inside
        j = i
    return inside

static func hex_distance(r1: int, c1: int, r2: int, c2: int) -> int:
    var q1 = c1 - int((r1 - (r1 & 1)) / 2.0)
    var q2 = c2 - int((r2 - (r2 & 1)) / 2.0)
    return int((abs(q1 - q2) + abs(r1 - r2) + abs((q1 + r1) - (q2 + r2))) / 2.0)

static func get_neighbors_odd_r(row: int, col: int, max_rows: int, max_cols: int) -> Array:
    var offsets := EVEN_ROW_OFFSETS if row % 2 == 0 else ODD_ROW_OFFSETS
    var neighbors: Array = []
    for d in offsets:
        var nr: int = row + d.x
        var nc: int = col + d.y
        if nr >= 0 and nr < max_rows and nc >= 0 and nc < max_cols:
            neighbors.append({"row": nr, "col": nc})
    return neighbors

# The neighbours of a hex as the flat indices row * cols + col, written into `into` (at least six
# elements long); the return value is how many of them are on the map. The loops that walk the
# whole map a hex at a time get the neighbours without a dictionary and an array per hex, and the
# order is the order of get_neighbors_odd_r, so a stage can switch between the two freely.
static func fill_neighbor_indices(row: int, col: int, max_rows: int, max_cols: int,
        into: PackedInt32Array) -> int:
    var offsets := EVEN_ROW_OFFSETS if row % 2 == 0 else ODD_ROW_OFFSETS
    var count := 0
    for d in offsets:
        var nr: int = row + d.x
        var nc: int = col + d.y
        if nr < 0 or nr >= max_rows or nc < 0 or nc >= max_cols:
            continue
        into[count] = nr * max_cols + nc
        count += 1
    return count

static func hex_vertex(row: int, col: int, vidx: int, radius: float) -> Vector2:
    var center = hex_center(row, col, radius)
    var verts = hex_vertices(center.x, center.y, radius)
    return verts[vidx]
