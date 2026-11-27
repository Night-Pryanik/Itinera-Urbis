# Headless test of the Medieval "Bills of Exchange" technology:
#   godot --headless --path . --script res://tests/test_bills_of_exchange.gd
#
# Checks:
#   1. The technology record: era, prerequisites, icon and description.
#   2. The tech modifier reduces only the per-hex part of the outpost fee.
#   3. Wheel and Horse Collar, which discount the LABOUR distance cost, leave
#      the coin fee alone.
#   4. The effect is listed in the City Effects tab only while researched.
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

    var tech: Dictionary = {}
    for t in _gdata.technologies:
        if str(t.get("id", "")) == "bills_of_exchange":
            tech = t
            break
    check(not tech.is_empty(), "technology 'bills_of_exchange' must exist", state)
    check(str(tech.get("name", "")) == "Bills of Exchange",
            "the technology must be named Bills of Exchange", state)
    check(str(tech.get("era", "")) == "medieval",
            "Bills of Exchange must belong to the 'medieval' era", state)
    check(tech.get("prerequisites", []) == [["banking", "emporia"]],
            "Bills of Exchange must require both Banking and Emporia", state)
    check(str(tech.get("icon", "")) == "bills_of_exchange.png",
            "the technology must name its own icon file", state)
    check(str(tech.get("description", "")).contains("outpost fee")
            and str(tech.get("description", "")).contains("20%"),
            "the description must name the 20% outpost fee discount", state)

    var discount := 0.0
    var effect_name := ""
    var records := 0
    for modifier in _gdata.modifiers.get("tech_modifiers", []):
        if str(modifier.get("tech_id", "")) != "bills_of_exchange":
            continue
        records += 1
        effect_name = str(modifier.get("name", ""))
        for entry in modifier.get("modifiers", []):
            if str(entry.get("target", "")) == "outpost_fee_distance_cost":
                discount = float(entry.get("value", 0.0))
    check(records == 1, "there must be one modifier record for the technology", state)
    check(is_equal_approx(discount, -20.0),
            "the outpost fee distance charge must be reduced by 20%% (got %f)"
                    % discount, state)

    var base := int(_gdata.game_balance.get("outpost_fee_base", 0))
    var per_hex := float(_gdata.game_balance.get("outpost_fee_per_hex", 0.0))
    check(base > 0 and per_hex > 0.0,
            "the outpost fee constants must be configured in game_balance.json", state)

    _cdata.unlocked_technologies.clear()
    check(is_equal_approx(_mh.get_outpost_fee_distance_tech_mult(), 1.0),
            "a new city must have no outpost fee discount", state)
    for distance in range(0, 10):
        var fee: int = _mh.get_outpost_fee(distance, 0, 0, 0)
        check(fee == base + int(ceil(float(distance) * per_hex)),
                "without the technology the fee at d=%d must stay base + d * per_hex (got %d)"
                        % [distance, fee], state)

    # These two technologies discount the distance contribution to the LABOUR
    # cost of improvements. They must not change the coin fee of an outpost.
    _cdata.unlocked_technologies.append("wheel")
    _cdata.unlocked_technologies.append("horse_collar")
    check(_mh.get_outpost_fee(8, 0, 0, 0)
            == base + int(ceil(8.0 * per_hex)),
            "labour distance technologies must not discount the coin fee", state)

    _cdata.unlocked_technologies.append("bills_of_exchange")
    check(is_equal_approx(_mh.get_outpost_fee_distance_tech_mult(), 0.8),
            "Bills of Exchange must set the fee distance multiplier to 0.8", state)
    for distance in range(0, 10):
        var discounted: int = _mh.get_outpost_fee(distance, 0, 0, 0)
        check(discounted == base + int(ceil(float(distance) * per_hex * 0.8)),
                "with the technology the fee at d=%d must discount only the per-hex charge (got %d)"
                        % [distance, discounted], state)
    check(_mh.get_outpost_fee(0, 0, 0, 0) == base,
            "the flat base fee must stay in force at zero distance", state)

    var effects: Array = _cdata.get_city_effects()
    var shown := 0
    for eff in effects:
        if str(eff.get("name", "")) == effect_name:
            shown += 1
    check(shown == 1,
            "the technology effect must be listed once in the City Effects tab", state)
    _cdata.unlocked_technologies.erase("bills_of_exchange")
    shown = 0
    for eff in _cdata.get_city_effects():
        if str(eff.get("name", "")) == effect_name:
            shown += 1
    check(shown == 0, "the effect must disappear once the technology is removed", state)

    if state["failed"]:
        print("BILLS OF EXCHANGE TEST FAILED")
        quit(1)
    else:
        print("BILLS OF EXCHANGE TEST OK")
        quit(0)

func check(condition: bool, message: String, state: Dictionary) -> void:
    if condition:
        return
    state["failed"] = true
    print("FAIL: ", message)
