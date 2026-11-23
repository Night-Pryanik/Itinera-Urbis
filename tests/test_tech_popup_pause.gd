# Headless regression for the pause flag around the window of a learned technology
# and the offer of a new era:
#   godot --headless --path . --script res://tests/test_tech_popup_pause.gd
#
# Both windows are pause sources of main_map.apply_pause_state. Opening one stops the
# simulation; closing it resumes the world only when no other source is still holding
# it. The city interface opened from the window must be able to process input.
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")

func _initialize():
    WATCHDOG.arm(self)
    _run()

func _run() -> void:
    var state := {"failed": false}
    var save_manager = get_root().get_node("SaveManager")
    var game_data = get_root().get_node("GameData")
    save_manager.new_game()

    var main_map = load("res://scenes/MainMap.tscn").instantiate()
    get_root().add_child(main_map)
    await process_frame
    await process_frame

    var popup = main_map.tech_popup
    var tech_id := str(game_data.technologies[0]["id"])

    # --- 1. Research shows the window and stops the world ---
    main_map._on_research_completed(tech_id)
    check(popup.visible, "the research window opens", state)
    check(paused, "the research window stops the simulation", state)

    # --- 2. "Go to the technology list" resumes the world and leaves a live city UI ---
    popup._on_techs_pressed()
    await process_frame
    check(not popup.visible, "the window closes on the button", state)
    check(main_map.city_ui.visible and main_map.city_ui.active_tab == "technologies",
            "the city interface opens on the technologies tab", state)
    check(not paused, "the city interface opens on a running world", state)
    check(main_map.city_ui.can_process(),
            "the city interface can process input after the jump", state)

    # --- 3. The same jump keeps the world stopped when the active pause is on ---
    main_map.city_ui.hide()
    main_map.hud.show()
    main_map.toggle_active_pause()
    paused = true
    popup.show_tech(tech_id, [])
    popup._on_techs_pressed()
    await process_frame
    check(paused, "the active pause survives the jump to the technology list", state)
    main_map.toggle_active_pause()
    check(not paused, "the world runs after the mode is off", state)

    # --- 4. The owner sees the open window; OK resumes only when it is the last source ---
    popup.show_tech(tech_id, [])
    main_map.apply_pause_state()
    check(paused, "apply_pause_state keeps the world stopped under the open window", state)
    popup._on_ok_pressed()
    check(not paused, "OK resumes the world when no other source is on", state)

    popup.show_tech(tech_id, [])
    main_map.open_pause_menu()
    popup._on_ok_pressed()
    check(paused, "OK does not resume a world stopped by the pause menu", state)
    main_map.pause_menu.hide()
    main_map.apply_pause_state()
    check(not paused, "closing the menu resumes the world", state)

    # --- 5. The offer of a new era is a pause source, and its answers respect another one ---
    main_map._show_era_advance_offer()
    check(main_map.era_dialog.visible and paused, "the era offer stops the simulation", state)
    main_map._on_era_dialog_declined()
    check(not main_map.era_dialog.visible and not paused, "declining resumes the world", state)

    main_map.open_pause_menu()
    main_map._show_era_advance_offer()
    main_map._on_era_dialog_declined()
    check(paused, "declining does not resume a world stopped by the menu", state)

    if state["failed"]:
        print("TECH POPUP PAUSE TEST FAILED")
        quit(1)
    else:
        print("TECH POPUP PAUSE TEST OK")
        quit(0)

func check(cond: bool, msg: String, state: Dictionary) -> void:
    if not cond:
        push_error("ASSERT: " + msg)
        print("ASSERT FAILED: ", msg)
        state["failed"] = true
