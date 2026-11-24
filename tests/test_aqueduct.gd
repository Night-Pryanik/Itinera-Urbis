# Headless test of the mountain spring and the aqueduct (the second layer of
# the map improvements):
#   godot --headless --path . --script res://tests/test_aqueduct.gd
#
# Checks the whole chain on a live new game: a resource-less mountain is marked
# as a hidden spring, the spring gives no water on its own, "Concrete" reveals
# it and unlocks the staged project, every section is built one at a time, and
# only the finished line gives the city fresh water. The flags survive the
# serialization of the tiles, from which the network is rebuilt on loading.
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")

var _cdata = null
var _failed := false

func _initialize() -> void:
    WATCHDOG.arm(self)
    _run()

func check(condition: bool, what: String) -> void:
    if condition:
        print("OK: ", what)
    else:
        _failed = true
        push_error("ASSERT FAILED: " + what)

func _run() -> void:
    get_root().get_node("SaveManager").new_game()
    var game_data = get_root().get_node("GameData")
    _cdata = get_root().get_node("CityData")
    # In --script mode the autoload names are unavailable at compile time, so
    # the static helpers are loaded at runtime, like the other live tests do.
    var helpers = load("res://scripts/map_helpers.gd")

    var tech_found := false
    for t in game_data.technologies:
        if t.get("id", "") == "concrete":
            tech_found = true
            check(t.get("era", "") == "antiquity", "Concrete belongs to Antiquity")
            check(str(t.get("prerequisites", "")).find("limestone_burning") >= 0,
                    "Concrete requires mineral firing")
    check(tech_found, "the Concrete technology exists")
    var action: Dictionary = game_data.special_actions.get("build_aqueduct", {})
    check(not action.is_empty(), "the build_aqueduct special action exists")
    check(str(action.get("unlock_tech", "")) == "concrete",
            "the aqueduct is unlocked by Concrete")

    var main_map = load("res://scenes/MainMap.tscn").instantiate()
    get_root().add_child(main_map)
    await process_frame
    await process_frame
    await process_frame

    var spring: Dictionary = main_map.find_fresh_water_spring()
    check(not spring.is_empty(), "a new game designates one mountain spring")
    if spring.is_empty():
        _finish(main_map)
        return
    var s_row := int(spring.row)
    var s_col := int(spring.col)
    var s_tile = main_map.get_tile_data(s_row, s_col)
    # The spring may lie in the unexplored part of the Region: a real player
    # sees the tooltip only after scouting, and so does this test.
    s_tile["is_explored"] = true
    check(helpers.is_mountain_terrain(str(s_tile.get("terrain", ""))),
            "the spring stands on a mountain")
    check(s_tile.get("resource", null) == null, "the spring mountain has no resource")
    check(helpers.get_hex_water_access(s_row, s_col, main_map.tile_data,
            main_map.map_rows, main_map.map_cols) == "",
            "the hidden spring itself gives no water")
    check(not bool(s_tile.get("aqueduct", false)), "no aqueduct stands before the build")
    check(str(s_tile.get("cover", "")) != "mountain_spring",
            "the spring cover is absent before Concrete is researched")
    check(not bool(_cover_data(game_data).get("fresh_water_source", false)),
            "the spring cover carries no ordinary water-source flag")
    check(not _cdata.is_tech_unlocked("concrete"), "Concrete is not known at the start")
    var hidden_actions: Array = main_map.control_panel._collect_actions(s_row, s_col, s_tile)
    check(not _has_aqueduct_action(hidden_actions),
            "the spring gives no hint before Concrete is researched")

    # The research reveals the marker and the action; the marker is drawn by
    # the renderer from this same flag, so no separate "reveal" state is kept.
    _cdata.unlocked_technologies.append("concrete")
    # The real research signal must put the cover on the mountain.
    _cdata.research_completed.emit("concrete")
    if main_map.tech_popup != null:
        main_map.tech_popup.hide()
    if self.paused:
        self.paused = false
    check(main_map.is_concrete_researched(), "Concrete unlocks the spring")
    check(str(main_map.get_tile_data(s_row, s_col).get("cover", ""))
            == "mountain_spring", "research turns the mountain into the spring cover")
    var journal_texts: Array = []
    for entry in main_map.journal.entries:
        journal_texts.append(str((entry as Dictionary).get("text", "")))
    var in_journal := false
    for text in journal_texts:
        if str(text).find("mountain spring") >= 0:
            in_journal = true
    check(in_journal, "the reveal is an important message kept in the journal")
    check(helpers.get_hex_water_access(s_row, s_col, main_map.tile_data,
            main_map.map_rows, main_map.map_cols) == "",
            "the revealed cover still gives no water on its own")
    var revealed_actions: Array = main_map.control_panel._collect_actions(
            s_row, s_col, main_map.get_tile_data(s_row, s_col))
    check(_has_aqueduct_action(revealed_actions),
            "the revealed spring offers the aqueduct action")

    var plan: Dictionary = main_map.get_aqueduct_plan(s_row, s_col)
    check(plan.get("ok", false), "a route from the spring to the city exists: %s"
            % str(plan.get("reason", "")))
    var sections: Array = plan.get("sections", [])
    check(sections.size() > 0, "the route has at least one section")

    main_map.build_manager.set_process(false)
    check(not bool(main_map.get_tile_data(main_map.city_row, main_map.city_col).get(
            "aqueduct_water", false)), "the city has no aqueduct water before the build")
    check(main_map.start_aqueduct_project(s_row, s_col),
            "the aqueduct project starts from the spring")
    var project: Dictionary = main_map.project_manager.get_project_at(s_row, s_col)
    check(str(project.get("kind", "")) == "aqueduct", "the project kind is aqueduct")
    check(int(project.get("steps", []).size()) == sections.size(),
            "the queue has one step per section")
    check(main_map.project_manager.get_pending_ghost_segments("aqueduct").size()
            == sections.size(), "the ghost shows the whole line")

    # Each call of receive_labor finishes at most one section. After the FIRST
    # one the spring is touched, but the city is not reached yet: the tooltip
    # must not claim that the aqueduct is already connected.
    var labor: float = maxf(1.0, _cdata.get_total_labor())
    main_map.project_manager.receive_labor(labor * 1000.0, 1.0)
    check(not bool(main_map.get_tile_data(main_map.city_row, main_map.city_col).get(
            "aqueduct_water", false)), "one section does not bring water to the city")
    var partial_info: Dictionary = main_map.map_tooltip.build_hex_info(
            s_row, s_col, main_map.tile_data, main_map.city_row, main_map.city_col)
    var partial_text := str(partial_info.get("text", ""))
    check(partial_text.find("connected to the city") < 0,
            "a partly built aqueduct is not reported as connected")
    check(partial_text.find("partly built") >= 0,
            "a partly built aqueduct is reported as partial")

    # Feed enough labour to walk the rest of the queue.
    var guard := 0
    while main_map.project_manager.has_active_projects() and guard < sections.size() + 5:
        main_map.project_manager.receive_labor(labor * 1000.0, 1.0)
        guard += 1
    check(not main_map.project_manager.has_active_projects(), "the project finishes")

    check(main_map.aqueduct_manager.get_all_segments().size() == sections.size(),
            "every section of the line is built")
    check(bool(main_map.get_tile_data(s_row, s_col).get("aqueduct", false)),
            "the spring hex carries the second-layer improvement")
    check(bool(main_map.get_tile_data(main_map.city_row, main_map.city_col).get("aqueduct", false)),
            "the aqueduct reaches the city hex")
    check(_cdata.has_city_fresh_water(), "the finished aqueduct gives the city fresh water")
    var done_info: Dictionary = main_map.map_tooltip.build_hex_info(
            s_row, s_col, main_map.tile_data, main_map.city_row, main_map.city_col)
    check(str(done_info.get("text", "")).find("connected to the city") >= 0,
            "only the finished aqueduct is reported as connected")

    # The flags are written to the save, and the network is rebuilt from them.
    var save_manager = get_root().get_node("SaveManager")
    var saved: Array = save_manager._serialize_tile_data(main_map)
    var saved_spring: Dictionary = saved[s_row][s_col]
    var saved_city: Dictionary = saved[main_map.city_row][main_map.city_col]
    check(bool(saved_spring.get("fresh_water_spring", false)),
            "the hidden spring flag is saved")
    check(bool(saved_spring.get("aqueduct", false)), "the aqueduct flag is saved")
    check(bool(saved_city.get("aqueduct_water", false)), "the city water flag is saved")
    var count_before: int = int(main_map.aqueduct_manager.get_all_segments().size())
    main_map.aqueduct_manager.rebuild_from_tiles(main_map.tile_data,
            main_map.map_rows, main_map.map_cols)
    check(main_map.aqueduct_manager.get_all_segments().size() == count_before,
            "the network is rebuilt from the per-hex flags")

    _finish(main_map)

func _cover_data(game_data) -> Dictionary:
    return game_data.covers.get("mountain_spring", {})

func _has_aqueduct_action(actions: Array) -> bool:
    for a in actions:
        if str((a as Dictionary).get("action_id", "")) == "build_aqueduct":
            return true
    return false

func _finish(main_map) -> void:
    get_root().remove_child(main_map)
    main_map.free()
    if _failed:
        push_error("AQUEDUCT TEST FAILED")
    else:
        print("AQUEDUCT TEST OK")
    quit()
