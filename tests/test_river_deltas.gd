# Headless test for river deltas:
#   godot --headless --path . --script res://tests/test_river_deltas.gd
#
# A delta is a set of distributaries of one main river that mouths into a lake or the sea. The
# test checks that the chance in the world settings really selects the rivers, that every
# distributary starts on its parent, reaches another mouth of the same water body and does not
# cross a main river, that the geometry survives a save/load round trip, and that the new-game
# preview forks its courses. Both lakes and seas are valid mouths.
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")

func _initialize() -> void:
    WATCHDOG.arm(self)
    _run()

func _run() -> void:
    var state := {"failed": false}
    var city_data = get_root().get_node("CityData")
    var WorldPreview = load("res://scripts/world_preview.gd")

    city_data.world_seed = 424242
    get_root().get_node("SaveManager").new_game()
    var main_map = load("res://scenes/MainMap.tscn").instantiate()
    get_root().add_child(main_map)
    await process_frame
    await process_frame
    await process_frame

    var river_manager = main_map.get_node("RiverManager")
    var rows: int = main_map.map_rows
    var cols: int = main_map.map_cols
    var radius: float = main_map.HEX_RADIUS

    # --- 1. A chance of zero builds no distributaries at all ---
    _regenerate(main_map, river_manager, city_data, 0.0, 1001)
    check(river_manager.get_deltas().is_empty(),
            "a zero delta chance must build no distributaries", state)

    # --- 2. A full chance builds forks on the rivers that reach a lake or the sea ---
    var seed_value := -1
    var deltas: Array = []
    for attempt in range(12):
        var candidate_seed := 1001 + attempt
        _regenerate(main_map, river_manager, city_data, 1.0, candidate_seed)
        deltas = river_manager.get_deltas()
        if not deltas.is_empty():
            seed_value = candidate_seed
            break
    check(seed_value >= 0 and not deltas.is_empty(),
            "a river with a water mouth must fork with a full delta chance", state)
    if deltas.is_empty():
        _finish(main_map, state)
        return

    var main_rivers: Array = river_manager.get_main_rivers()
    var graph: Dictionary = river_manager.get_cached_graph()
    var edge_len: float = float(graph.get("edge_len", 1.0))
    for delta in deltas:
        check(delta.size() >= 2, "every distributary has a path", state)
        # A branch goes to the nearest water: its course may not wind far around the rivers
        # already on the map to reach a mouth it happened to pick.
        var straight: float = delta[0].distance_to(delta[delta.size() - 1]) / edge_len
        check(float(delta.size() - 1) <= straight * 1.35 + 1.0,
                "a distributary must take a direct route to the shore (steps %d, straight %.1f)"
                        % [delta.size() - 1, straight], state)
        # The fork is a shared vertex of the parent course, not a fresh river source.
        var shared := false
        for main in main_rivers:
            if delta[0] in main:
                shared = true
                break
        check(shared, "a distributary must start on its parent river", state)
        # The far end is another mouth of a lake or the sea (including the shallows).
        var end_id: int = river_manager._find_vertex_id(delta[delta.size() - 1], graph)
        check(end_id >= 0, "the mouth of a distributary is a vertex of the map", state)
        if end_id >= 0:
            var hex_off: PackedInt32Array = graph["hex_off"]
            var hex_data: PackedInt32Array = graph["hex_data"]
            var touches_water := false
            for k in range(hex_off[end_id], hex_off[end_id + 1]):
                var hex_index: int = hex_data[k] / 6
                var terrain := str(main_map.tile_data[hex_index / cols][hex_index % cols]["terrain"])
                if terrain == "lake" or terrain == "sea" or terrain == "shallow_sea":
                    touches_water = true
                    break
            check(touches_water, "a distributary must end at a lake or sea mouth", state)

    # A distributary may leave from a shared corner, but must not cross the parent any further.
    var crossings: Array = []
    for delta in deltas:
        for main in main_rivers:
            if _meets_after_fork(delta, main):
                crossings.append([delta, main])
    check(crossings.is_empty(),
            "distributaries must not cross the main rivers (pairs %d)" % crossings.size(), state)

    # --- 3. The distributaries are saved as their own list and restored ---
    var saved: Dictionary = river_manager.serialize_rivers()
    check(saved.has("deltas") and saved["deltas"].size() == deltas.size(),
            "the save keeps the distributaries (got %s)"
                    % str(saved.get("deltas", []).size()), state)
    river_manager.load_rivers(saved)
    var restored: Array = river_manager.get_deltas()
    check(restored.size() == deltas.size(),
            "a loaded game restores the distributaries (got %d)" % restored.size(), state)

    # --- 3b. A lake is a valid delta coast, not just the sea ---
    var lake_delta := false
    for attempt in range(12):
        _regenerate(main_map, river_manager, city_data, 1.0, 3000 + attempt)
        var lake_graph: Dictionary = river_manager.get_cached_graph()
        for delta in river_manager.get_deltas():
            var end_id: int = river_manager._find_vertex_id(delta[delta.size() - 1], lake_graph)
            if end_id < 0:
                continue
            var lake_hex_off: PackedInt32Array = lake_graph["hex_off"]
            var lake_hex_data: PackedInt32Array = lake_graph["hex_data"]
            for k in range(lake_hex_off[end_id], lake_hex_off[end_id + 1]):
                var hex_index: int = lake_hex_data[k] / 6
                var terrain := str(main_map.tile_data[hex_index / cols][hex_index % cols]["terrain"])
                if terrain == "lake":
                    lake_delta = true
                    break
            if lake_delta:
                break
        if lake_delta:
            break
    check(lake_delta, "a river ending in a lake must also be able to form a delta", state)

    # --- 4. The preview forks the courses that reach a lake or the sea ---
    var sea_cfg: Dictionary = city_data.DEFAULT_SEA.duplicate(true)
    sea_cfg["mode"] = "edge"
    var no_delta: Dictionary = city_data.DEFAULT_RIVERS.duplicate(true)
    no_delta["delta_chance"] = 0.0
    var with_delta: Dictionary = city_data.DEFAULT_RIVERS.duplicate(true)
    with_delta["delta_chance"] = 1.0
    var dry: Dictionary = WorldPreview.build(60, sea_cfg, seed_value, no_delta)
    check(dry.get("deltas", []).is_empty(),
            "a zero delta chance draws no branches on the preview", state)
    var wet: Dictionary = WorldPreview.build(60, sea_cfg, seed_value, with_delta)
    var preview_deltas: Array = wet.get("deltas", [])
    check(not preview_deltas.is_empty(),
            "a full delta chance draws distributaries on the preview", state)
    var preview_cells: PackedByteArray = wet["cells"]
    var preview_grid: int = int(wet["grid"])
    for branch in preview_deltas:
        check(branch.size() >= 2, "every preview distributary has a path", state)
        var drawn_length: float = 0.0
        for index in range(branch.size() - 1):
            drawn_length += branch[index].distance_to(branch[index + 1])
        var straight_cells: float = branch[0].distance_to(branch[branch.size() - 1])
        check(drawn_length <= straight_cells * 1.35 + 1.0,
                "a preview distributary must take a direct route to the shore (length %.1f, straight %.1f)"
                        % [drawn_length, straight_cells], state)
        for index in range(branch.size() - 1):
            var steps := maxi(1, ceili(branch[index].distance_to(branch[index + 1]) * 4.0))
            for step in range(steps + 1):
                var point: Vector2 = branch[index].lerp(branch[index + 1],
                        float(step) / float(steps))
                var cell := clampi(int(floor(point.y)), 0, preview_grid - 1) * preview_grid \
                        + clampi(int(floor(point.x)), 0, preview_grid - 1)
                check(not _is_water(preview_cells[cell]),
                        "a preview distributary stays on land", state)

    _finish(main_map, state)

func _regenerate(main_map, river_manager, city_data, chance: float, seed_value: int) -> void:
    city_data.world_rivers["delta_chance"] = chance
    city_data.world_seed = seed_value
    seed(seed_value)
    river_manager.generate_rivers(main_map.map_rows, main_map.map_cols,
            main_map.HEX_RADIUS, main_map.tile_data)

func _finish(main_map, state: Dictionary) -> void:
    if main_map != null and is_instance_valid(main_map):
        get_root().remove_child(main_map)
        main_map.free()
    if state["failed"]:
        print("RIVER DELTAS TEST FAILED")
        quit(1)
    else:
        print("RIVER DELTAS TEST OK")
        quit(0)

func _meets_after_fork(delta: Array, main: Array) -> bool:
    if main.size() < 2 or delta.size() < 2:
        return false
    # Segment 0 leaves the shared fork; the meeting there is the confluence itself.
    for i in range(1, delta.size() - 1):
        for j in range(main.size() - 1):
            if Geometry2D.segment_intersects_segment(delta[i], delta[i + 1],
                    main[j], main[j + 1]) != null:
                return true
    return false

func _is_water(code: int) -> bool:
    return code == 1 or code == 2 or code == 4

func check(condition: bool, message: String, state: Dictionary) -> void:
    if not condition:
        state["failed"] = true
        print("FAIL: ", message)
