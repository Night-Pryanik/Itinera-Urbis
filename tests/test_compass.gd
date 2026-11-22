# Headless test of the Medieval "Compass" technology:
#   godot --headless --path . --script res://tests/test_compass.gd
#
# Checks:
#   1. Data, icon, prerequisites, and City Effects tab entries.
#   2. Fishing boats +25% production multiplier.
#   3. Scouting chunk size grows from 5 to 7 while claiming stays at 5.
#   4. Scouting distance cost surcharge drops by 30%.
#   5. Maximum camera scroll distance grows by 25%, expanding scout reach.
#   6. Up to 2 concurrent non-overlapping scouting expeditions, independent
#      cancellation, and serialization/restoration.
#   7. Coastal town sea harbors without marine resources, and sea trade route
#      logistics via player + town harbors on the same connected sea body.
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")

var _gdata = null
var _cdata = null
var _mh = null

func _initialize() -> void:
    WATCHDOG.arm(self)
    _run()

func _run() -> void:
    var state := {"failed": false}
    get_root().get_node("SaveManager").new_game()
    _gdata = get_root().get_node("GameData")
    _cdata = get_root().get_node("CityData")
    _mh = load("res://scripts/map_helpers.gd")

    if WATCHDOG.wants_case("data_and_fishing"):
        _test_data_and_fishing(state)
    if WATCHDOG.wants_case("scouting_and_scroll"):
        await _test_scouting_and_scroll(state)
    if WATCHDOG.wants_case("sea_trade"):
        await _test_sea_trade(state)

    WATCHDOG.report_skipped()
    if state["failed"]:
        print("COMPASS TEST FAILED")
        quit(1)
    else:
        print("COMPASS TEST OK")
        quit(0)

func _test_data_and_fishing(state: Dictionary) -> void:
    _cdata.unlocked_technologies.clear()
    var compass: Dictionary = {}
    for t in _gdata.technologies:
        if str(t.get("id", "")) == "compass":
            compass = t
            break
    check(not compass.is_empty(), "technology 'compass' must exist", state)
    check(str(compass.get("era", "")) == "medieval",
            "Compass must belong to the 'medieval' era", state)
    var prereqs: Array = compass.get("prerequisites", [])
    check(prereqs.size() == 1 and prereqs[0] == ["cartography", "precision_instruments", "steel_making"],
            "Compass must require cartography, precision_instruments, and steel_making", state)
    var icon_reg = get_root().get_node("IconRegistry")
    check(icon_reg.get_texture("compass.png") != null,
            "compass.png must resolve in IconRegistry", state)

    var mult_before: float = _cdata.get_improvement_production_multiplier("fishing_boats", false)
    var dist_mult_before: float = _mh.get_scouting_distance_mult(12)
    check(_mh.get_scouting_chunk_size() == 5,
            "base scouting chunk size must be 5", state)
    check(_mh.get_max_scouting_expeditions() == 1,
            "base max scouting expeditions must be 1", state)
    check(is_equal_approx(_mh.get_max_scroll_tech_mult(), 1.0),
            "base max scroll multiplier must be 1.0", state)

    _cdata.unlocked_technologies.append("compass")
    var mult_after: float = _cdata.get_improvement_production_multiplier("fishing_boats", false)
    check(is_equal_approx(mult_after, mult_before * 1.25),
            "Compass must multiply fishing_boats production by 1.25 (before=%f, after=%f)"
                    % [mult_before, mult_after], state)

    var expected_dist_mult: float = 1.0 + 12.0 * _mh.get_distance_cost_modifier() * 0.7
    check(is_equal_approx(_mh.get_scouting_distance_mult(12), expected_dist_mult),
            "Compass must reduce scouting distance surcharge by 30%% (got %f, expected %f)"
                    % [_mh.get_scouting_distance_mult(12), expected_dist_mult], state)
    check(_mh.get_scouting_distance_mult(12) < dist_mult_before,
            "scouting distance multiplier at d=12 must decrease with Compass", state)
    check(_mh.get_scouting_chunk_size() == 7,
            "Compass must raise scouting chunk size to 7", state)
    check(_mh.get_max_scouting_expeditions() == 2,
            "Compass must raise max simultaneous scouting expeditions to 2", state)
    check(is_equal_approx(_mh.get_max_scroll_tech_mult(), 1.25),
            "Compass must raise max scroll distance multiplier to 1.25", state)

    var effects: Array = _cdata.get_city_effects()
    var compass_effects: int = 0
    var compass_tech_name: String = str(_cdata.get_tech_name("compass"))
    for eff in effects:
        if str(eff.get("source", "")) == compass_tech_name:
            compass_effects += 1
    check(compass_effects == 3,
            "Compass modifiers must appear in CityData.get_city_effects() (got %d)" % compass_effects, state)
    _cdata.unlocked_technologies.clear()

func _test_scouting_and_scroll(state: Dictionary) -> void:
    get_root().get_node("SaveManager").new_game()
    var main_map = load("res://scenes/MainMap.tscn").instantiate()
    get_root().add_child(main_map)
    for _i in range(4):
        await process_frame
    while bool(main_map.world_generating):
        await process_frame
    _cdata.unlocked_technologies = ["cartography"]

    var scroll_before: Vector2 = main_map.get_max_scroll()
    var em = main_map.expansion_manager

    # Find an unexplored frontier hex for scouting before Compass.
    var frontier := _find_scoutable_hex(main_map)
    check(not frontier.is_empty(), "a scoutable frontier hex must exist", state)
    if not frontier.is_empty():
        var chunk_before: Array = em.get_chunk_hexes(int(frontier.row), int(frontier.col))
        check(chunk_before.size() == 5,
                "before Compass scouting chunk size must be 5, got %d" % chunk_before.size(), state)
        var cost_before: int = em.get_hex_scout_cost(int(frontier.row), int(frontier.col))

        _cdata.unlocked_technologies.append("compass")
        var scroll_after: Vector2 = main_map.get_max_scroll()
        check(is_equal_approx(scroll_after.x, scroll_before.x * 1.25) \
                and is_equal_approx(scroll_after.y, scroll_before.y * 1.25),
                "Compass must increase get_max_scroll() by 25%%", state)

        var chunk_after: Array = em.get_chunk_hexes(int(frontier.row), int(frontier.col))
        check(chunk_after.size() == 7,
                "with Compass scouting chunk size must be 7, got %d" % chunk_after.size(), state)
        var cost_after: int = em.get_hex_scout_cost(int(frontier.row), int(frontier.col))
        check(cost_after <= cost_before,
                "with Compass hex scout cost must not exceed pre-Compass cost (%d vs %d)"
                        % [cost_after, cost_before], state)

        # Start expedition #1, then assemble and start non-overlapping expedition #2.
        _cdata.treasury = 5000
        var cost_1: int = em.get_chunk_scout_cost(chunk_after)
        main_map.start_scouting(chunk_after)
        check(main_map.scouting_expeditions.size() == 1,
                "first scouting expedition must start", state)
        check(main_map.can_start_scouting(),
                "with Compass a second scouting slot must still be open", state)

        var second_hex := _find_scoutable_hex(main_map)
        check(not second_hex.is_empty(), "a second scoutable frontier hex must exist", state)
        if not second_hex.is_empty():
            var chunk_second: Array = em.get_chunk_hexes(int(second_hex.row), int(second_hex.col))
            check(not _chunks_overlap(chunk_after, chunk_second),
                    "second scouting chunk must not overlap active first expedition", state)
            var cost_2: int = em.get_chunk_scout_cost(chunk_second)
            main_map.start_scouting(chunk_second)
            check(main_map.scouting_expeditions.size() == 2,
                    "two scouting expeditions must run concurrently", state)
            check(not main_map.can_start_scouting(),
                    "third simultaneous scouting expedition must be blocked", state)

            # Serialization round-trip preserves both active expeditions.
            var snap: Array = main_map.serialize_scouting_expeditions()
            check(snap.size() == 2, "serialize_scouting_expeditions must save both expeditions", state)
            main_map.restore_scouting_expeditions(snap)
            check(main_map.scouting_expeditions.size() == 2,
                    "restore_scouting_expeditions must restore both expeditions", state)

            # Cancelling expedition #1 refunds cost_1 while expedition #2 keeps running.
            var treasury_mid: int = _cdata.treasury
            var anchor_1 = chunk_after[0]
            check(main_map.cancel_scouting(int(anchor_1.row), int(anchor_1.col)),
                    "cancelling the first expedition by its anchor hex must succeed", state)
            check(main_map.scouting_expeditions.size() == 1,
                    "second expedition must remain active after cancelling the first", state)
            check(_cdata.treasury == treasury_mid + cost_1,
                    "cancelling expedition #1 must refund its exact cost (%d)" % cost_1, state)

            # Completing the remaining expedition explores its chunk.
            main_map._complete_scouting(0)
            check(not main_map.is_scouting,
                    "completing the remaining expedition must leave zero active expeditions", state)
            for h in chunk_second:
                check(bool(main_map.tile_data[int(h.row)][int(h.col)].get("is_explored", false)),
                        "completed second expedition hex must be marked explored", state)
            var _unused := cost_2

    # Claiming explored chunks inside the Region stays capped at 5 even with Compass.
    for r in range(main_map.region_start_row, main_map.region_end_row + 1):
        var checked_claim := false
        for c in range(main_map.region_start_col, main_map.region_end_col + 1):
            var t = main_map.tile_data[r][c]
            if t == null or bool(t.get("in_influence", false)) or bool(t.get("in_town_influence", false)):
                continue
            t["is_explored"] = true
            for n in HexUtils.get_neighbors_odd_r(r, c, main_map.map_rows, main_map.map_cols):
                if main_map.is_valid_hex(n.row, n.col) \
                        and not bool(main_map.tile_data[n.row][n.col].get("in_influence", false)) \
                        and not bool(main_map.tile_data[n.row][n.col].get("in_town_influence", false)):
                    main_map.tile_data[n.row][n.col]["is_explored"] = true
            var claim_chunk: Array = em.get_chunk_hexes(r, c)
            check(claim_chunk.size() <= 5,
                    "claiming chunk size must stay <= 5 with Compass, got %d" % claim_chunk.size(), state)
            checked_claim = true
            break
        if checked_claim:
            break

    main_map.queue_free()
    await process_frame

func _test_sea_trade(state: Dictionary) -> void:
    get_root().get_node("SaveManager").new_game()
    var main_map = load("res://scenes/MainMap.tscn").instantiate()
    get_root().add_child(main_map)
    for _i in range(4):
        await process_frame
    while bool(main_map.world_generating):
        await process_frame
    _cdata.unlocked_technologies.clear()

    var rows: int = main_map.map_rows
    var cols: int = main_map.map_cols
    var td: Array = main_map.tile_data
    var tm = main_map.town_manager

    # Carve a controlled sea channel connecting a player coastal hex in the
    # Influence Ring to a coastal town outside the Ring without any land road.
    var p_row: int = main_map.city_row
    var p_col: int = main_map.influence_end_col
    var sea_start_col: int = p_col + 1
    var sea_end_col: int = mini(cols - 5, p_col + 5)
    var t_row: int = p_row
    var t_col: int = sea_end_col + 1

    for r in range(maxi(0, p_row - 4), mini(rows, p_row + 5)):
        for c in range(main_map.city_col, mini(cols, t_col + 5)):
            if r == main_map.city_row and c == main_map.city_col:
                continue
            td[r][c]["terrain"] = "steppe_plain"
            td[r][c]["climate"] = "steppe"
            td[r][c]["cover"] = "none"
            td[r][c]["resource"] = null
            td[r][c]["crop_bred"] = null
            td[r][c]["improvement"] = null
            td[r][c]["decorative"] = false
            td[r][c]["has_town"] = false
            td[r][c]["in_town_influence"] = false
            td[r][c]["is_explored"] = true
            td[r][c]["road_built"] = false
            td[r][c]["road_level"] = 1

    for c in range(sea_start_col, sea_end_col + 1):
        td[p_row][c]["terrain"] = "shallow_sea" if (c == sea_start_col or c == sea_end_col) else "sea"

    main_map.road_manager.initialize(main_map.city_row, main_map.city_col)
    main_map.road_manager.bump_map_knowledge()

    var coastal_town: Dictionary = tm._make_town_record(99, t_row, t_col, false)
    coastal_town["road_linked"] = false
    td[t_row][t_col]["has_town"] = true
    tm.towns = [coastal_town]
    tm.town_hexes = [{"row": t_row, "col": t_col}]
    tm.compute_all_town_influences(td, rows, cols)
    tm._place_decorative_town_improvements(td, rows, cols)
    # Populate the town warehouse after compute_all_town_influences(), which
    # refreshes sell_pool from ring resources and prunes storage to match.
    coastal_town["sell_pool"] = ["wood"]
    coastal_town["storage"] = {"wood": 100}
    coastal_town["quality"] = {"wood": "common"}
    coastal_town["treasury"] = 500
    main_map._rebuild_town_roads()

    # 1) Coastal town gets a decorative harbor even with zero marine resources in its ring.
    var town_has_harbor := false
    for h in coastal_town.get("influence_hexes", []):
        var ht = td[int(h.row)][int(h.col)]
        if ht != null and str(ht.get("improvement", "")) == "harbor":
            town_has_harbor = true
            break
    check(town_has_harbor,
            "coastal town must place a decorative harbor on adjacent sea even without marine resources",
            state)

    # 2) Player builds a harbor on the same sea body, but Compass is NOT researched yet.
    td[p_row][p_col]["improvement"] = "harbor"
    td[p_row][p_col]["decorative"] = false
    check(not tm.is_trade_available(coastal_town, td, rows, cols),
            "sea trade must remain unavailable before Compass is researched", state)

    # 3) Research Compass: trade becomes available without a land road!
    _cdata.unlocked_technologies.append("compass")
    check(tm.is_trade_available(coastal_town, td, rows, cols),
            "sea trade must become available once Compass is researched and both harbors share a sea",
            state)
    check(main_map.map_renderer._is_town_trade_connected(t_row, t_col),
            "map_renderer._is_town_trade_connected must report true for a sea-linked town", state)
    check(not main_map.has_road_route(t_row, t_col),
            "has_road_route must stay false when only a sea route exists", state)

    var route: Dictionary = main_map.get_route_to_city(t_row, t_col)
    check(bool(route.get("ok", false)) and bool(route.get("sea", false)),
            "get_route_to_city must return an active sea route", state)
    check(is_equal_approx(float(route.get("avg_speed", 0.0)), _mh.get_sea_trade_flow_rate()),
            "sea route throughput must equal sea_trade_flow_rate", state)
    var water_len := int(route.get("length", 0))
    check(water_len >= 1, "sea route water length must be positive, got %d" % water_len, state)

    # 4) Execute an actual purchase through town_trade_manager -> delivery_manager over the sea route.
    _cdata.treasury = 5000
    _cdata.city_storage["wood"] = 0
    var before_wood: int = int(_cdata.city_storage.get("wood", 0))
    var unit_price: int = int(round(_gdata.get_price_for_quality("wood", "common")))
    var order_res: Dictionary = main_map.town_trade_manager.submit_order({
        "town_id": str(coastal_town.get("id", "")),
        "side": "sell",
        "product_id": "wood",
        "amount": 10,
        "permanent": false,
        "unit_price": unit_price,
    })
    check(bool(order_res.get("ok", false)),
            "buying goods over a sea route must succeed: %s" % str(order_res.get("message", "")), state)
    check(int(_cdata.city_storage.get("wood", 0)) == before_wood,
            "purchased goods must enter sea transit rather than appearing instantly", state)

    main_map.delivery_manager.ship()
    var delay: float = float(water_len) * float(main_map.delivery_manager.get_transit_time_per_hex())
    main_map.delivery_manager.advance(delay + 0.5)
    check(int(_cdata.city_storage.get("wood", 0)) == before_wood + 10,
            "sea-shipped goods must arrive in city storage after water transit delay", state)

    # 5) Bidirectional priority comparison between sea route (60) and land road:
    #    a) Sea route active -> build trail road (10) around the bay -> sea (60 > 10) stays active,
    #       while get_land_route_to_city exposes the trail for road upgrades.
    var plan: Dictionary = main_map.get_road_plan(t_row, t_col)
    check(bool(plan.get("ok", false)),
            "a land bypass road plan around the bay to the coastal town must exist", state)
    if bool(plan.get("ok", false)):
        main_map.road_manager.build_road_to(
                t_row, t_col, td, rows, cols, -1, Callable(), 1)
        coastal_town["road_linked"] = true
        check(main_map.has_road_route(t_row, t_col),
                "after building a trail to the town has_road_route must be true", state)
        var route_with_trail: Dictionary = main_map.get_route_to_city(t_row, t_col)
        check(bool(route_with_trail.get("sea", false)),
                "sea route (60 units/sec) must stay preferred over a trail road (10 units/sec)", state)

        # b) Reverse order: without Compass the town uses the trail road (10); unlocking
        #    Compass switches automatically to the faster sea route (60 > 10).
        _cdata.unlocked_technologies.erase("compass")
        var route_pre_compass: Dictionary = main_map.get_route_to_city(t_row, t_col)
        check(bool(route_pre_compass.get("ok", false)) and not bool(route_pre_compass.get("sea", false)),
                "before Compass the land road must carry the trade", state)
        _cdata.unlocked_technologies.append("compass")
        var route_post_compass: Dictionary = main_map.get_route_to_city(t_row, t_col)
        check(bool(route_post_compass.get("sea", false)),
                "unlocking Compass must switch from a slower land road to the faster sea route", state)

        # c) Upgrade every segment of the land road to level 4 (80 units/sec > 60 units/sec):
        #    get_route_to_city switches automatically to the upgraded land highway!
        var land_before_upg: Dictionary = main_map.get_land_route_to_city(t_row, t_col)
        for seg_key in land_before_upg.get("segments", []):
            var parts: PackedStringArray = str(seg_key).split("|")
            if parts.size() == 2:
                var a: PackedStringArray = parts[0].split(",")
                var b: PackedStringArray = parts[1].split(",")
                main_map.road_manager.upgrade_road_segment(
                        int(a[0]), int(a[1]), int(b[0]), int(b[1]), 4)
        var route_after_highway: Dictionary = main_map.get_route_to_city(t_row, t_col)
        check(bool(route_after_highway.get("ok", false)) and not bool(route_after_highway.get("sea", false)),
                "upgrading the land road to Great Highways (80 > 60) must switch to the land route", state)
        check(float(route_after_highway.get("avg_speed", 0.0)) > _mh.get_sea_trade_flow_rate(),
                "selected land highway throughput must exceed sea_trade_flow_rate", state)

        # Reset land road so we can also verify closing sea trade when no land road exists.
        main_map.road_manager.initialize(main_map.city_row, main_map.city_col)
        main_map._rebuild_town_roads()
        coastal_town["road_linked"] = false

    # 6) Demolishing the player's harbor closes sea trade immediately when no land road exists.
    td[p_row][p_col]["improvement"] = null
    check(not tm.is_trade_available(coastal_town, td, rows, cols),
            "removing the player's harbor must close sea trade immediately", state)

    main_map.queue_free()
    await process_frame

func _find_scoutable_hex(main_map) -> Dictionary:
    var em = main_map.expansion_manager
    var bounds: Dictionary = main_map.get_scout_reach_bounds()
    for r in range(int(bounds.row_start), int(bounds.row_end) + 1):
        for c in range(int(bounds.col_start), int(bounds.col_end) + 1):
            var tile = main_map.tile_data[r][c]
            if tile == null or bool(tile.get("is_explored", false)) \
                    or bool(tile.get("in_influence", false)):
                continue
            if main_map.is_hex_being_scouted(r, c):
                continue
            var chunk: Array = em.get_chunk_hexes(r, c)
            if chunk.size() >= 5 and main_map.is_chunk_adjacent_to_known(chunk):
                return {"row": r, "col": c}
    return {}

func _chunks_overlap(a: Array, b: Array) -> bool:
    for ha in a:
        for hb in b:
            if int(ha.row) == int(hb.row) and int(ha.col) == int(hb.col):
                return true
    return false

func check(cond: bool, msg: String, state: Dictionary) -> void:
    if not cond:
        printerr("FAIL: ", msg)
        state["failed"] = true
