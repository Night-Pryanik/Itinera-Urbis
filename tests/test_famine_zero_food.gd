# Headless test for the famine at an empty food storage:
#   godot --headless --path . --script res://tests/test_famine_zero_food.gd
#
# The famine is decided in _check_population_change() from a food deficit. The deficit must use
# the citizens' ration demand, not the recorded consumption: reset_counters() clears the rates at
# the start of the tick and the food write-off fills them only while there is food in the storage.
# At zero food — exactly when the citizens starve — the recorded consumption is zero, so comparing
# it against the production would stall the famine after the tick that drained the warehouse.
#
# This test drives the real tick (reset_counters() followed by do_tick()); it does not plant
# consumption_rates by hand as the isolated famine tests do.
extends SceneTree

# Without the watchdog a broken coroutine inside _run() looks like a silent hang
# from the outside. See tests/watchdog.gd.
const WATCHDOG = preload("res://tests/watchdog.gd")

var _city = null

func _initialize() -> void:
    WATCHDOG.arm(self)
    _run()

func _run() -> void:
    var state = {"failed": false}

    get_root().get_node("SaveManager").new_game()
    _city = get_root().get_node("CityData")
    await process_frame
    await process_frame

    _city.city_food_pool = {"wheat": true}
    _city.city_storage = {"wheat": 0}
    _city.food_consumption_enabled = true
    _city.improvement_planned_production = {}
    _city.total_population = 3
    _city.idle_population = 3

    # --- 1. An empty storage with no production starves on the real tick ---
    _city.reset_counters()
    _city.do_tick()
    check(_city.total_population == 2,
            "the tick that starts at zero food must kill one resident", state)
    check(_city.consumption_rates.is_empty(),
            "no consumption is recorded at an empty storage — the deficit must come from demand", state)

    # --- 2. Starvation continues on the following ticks, it does not stall at zero ---
    _city.reset_counters()
    _city.do_tick()
    check(_city.total_population == 1,
            "starvation must continue while the storage stays empty", state)

    # --- 3. The last citizen is spared ---
    _city.reset_counters()
    _city.do_tick()
    check(_city.total_population == 1,
            "the last citizen must not die of the famine", state)

    if state["failed"]:
        print("FAMINE ZERO FOOD TEST FAILED")
        quit(1)
    else:
        print("FAMINE ZERO FOOD TEST OK")
        quit(0)

func check(condition: bool, message: String, state: Dictionary) -> void:
    if condition:
        return
    push_error("ASSERT: " + message)
    print("ASSERT FAILED: ", message)
    state["failed"] = true
