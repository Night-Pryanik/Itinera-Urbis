# Test of the modes of a group consumption rule: the pseudo-profession "all"
# takes the full amount from every member, the working professions rotate over
# one member per write-off. An explicit consume_all overrides either default.
#   godot --headless --path . --script res://tests/test_consume_all.gd
extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")

# get_profession() reads the improvement of the hex from the parent of the manager.
class MapStub extends Node:
    var tile_data: Array = []

func _initialize():
    WATCHDOG.arm(self)
    _run()

func _run() -> void:
    var state: Dictionary = {"failed": false}
    var city = get_root().get_node("CityData")
    var gdata = get_root().get_node("GameData")
    var save_manager = get_root().get_node("SaveManager")
    save_manager.new_game()
    city.total_population = 1
    city.market_consumption_enabled.clear()
    city.consumption_priority.clear()

    var stub := MapStub.new()
    get_root().add_child(stub)
    stub.tile_data = [[{"improvement": "mine"}]]
    var wm = load("res://scripts/worker_manager.gd").new()
    stub.add_child(wm)

    var all_rules: Array = gdata.get_profession_consumption("all")
    var miner_rules: Array = gdata.get_profession_consumption("miner")

    # --- The defaults: the citizens take the whole basket, the worker takes one kind ---
    var fruits = _find(all_rules, "@fruits")
    var instruments = _find(miner_rules, "@instruments")
    check(fruits != null and bool(fruits.get("consume_all", false)),
        "a city group rule must default to consume_all", state)
    check(instruments != null and not bool(instruments.get("consume_all", true)),
        "a professional group rule must not take the whole basket", state)

    # --- The city: a full ration from each member, whatever its place in the list ---
    var basket = _find(all_rules, "@consumer_goods")
    check(basket != null,
        "the rule of @consumer_goods must be declared", state)
    check(basket != null and bool(basket.get("consume_all", false)),
        "the basket rule must get consume_all from the city default", state)

    if basket != null:
        var members: Array = basket.get("group_members", [])
        var amount: int = int(basket.get("amount", 0))
        var interval: float = float(basket.get("interval", 1.0))
        check(members.size() >= 3, "the basket must hold at least three goods", state)

        _set_stock(city, members, amount * 3)
        wm.tick_city_consumption(interval)
        for pid in members:
            var left: int = city.get_storage_amount(str(pid))
            check(left == amount * 2,
                "the city must take %d from each member: %s has %d"
                    % [amount, str(pid), left], state)

        # An empty shelf does not stop the other goods of the basket.
        _clear_stock(city)
        for i in range(members.size()):
            _set_one(city, str(members[i]), 0 if i == 0 else amount * 3)
        wm.tick_city_consumption(interval)
        check(city.get_storage_amount(str(members[0])) == 0,
            "an empty first member must stay empty", state)
        for i in range(1, members.size()):
            var pid := str(members[i])
            var left: int = city.get_storage_amount(pid)
            check(left == amount * 2,
                "the other members must still be drawn in full: %s has %d"
                    % [pid, left], state)

        # An empty basket keeps the timer hot: the next goods are written off
        # on the nearest tick, without waiting for a full interval.
        _clear_stock(city)
        wm.tick_city_consumption(interval)
        _set_stock(city, members, amount)
        wm.tick_city_consumption(0.1)
        for pid in members:
            check(city.get_storage_amount(str(pid)) == 0,
                "goods that appeared after an empty tick must be drawn at once: %s"
                    % str(pid), state)

    # --- A professional rule marked consume_all: the same draw, plus the bonus ---
    gdata.product_groups["test_basket"] = ["salt", "soap"]
    gdata.consumption_rules.append({
        "resource": "@test_basket",
        "profession": ["miner"],
        "amount": 10,
        "interval": 10,
        "production_bonus": 0.5,
        "consume_all": true
    })
    wm.assigned_hexes["0,0"] = true
    check(int(wm.count_workers_by_profession().get("miner", 0)) == 1,
        "the stub must have one miner", state)

    _clear_stock(city)
    _set_one(city, "salt", 30)
    _set_one(city, "soap", 30)
    var multiplier: float = wm.tick_consumption(0, 0, 1.0)
    check(city.get_storage_amount("salt") == 29 and city.get_storage_amount("soap") == 29,
        "the miner must take the full per-tick amount from both members: %d and %d"
            % [city.get_storage_amount("salt"), city.get_storage_amount("soap")], state)
    check(multiplier >= 1.5 - 0.001,
        "a full stock of every member must grant the bonus of the group, got x%.3f"
            % multiplier, state)

    # One member below the full amount: the write-off still happens, the bonus does not.
    _clear_stock(city)
    _set_one(city, "salt", 5)
    _set_one(city, "soap", 30)
    multiplier = wm.tick_consumption(0, 0, 1.0)
    check(city.get_storage_amount("salt") == 4 and city.get_storage_amount("soap") == 29,
        "a short member must be emptied while the other is still drawn", state)
    check(multiplier < 1.001,
        "a member below the full amount must remove the bonus, got x%.3f" % multiplier, state)

    gdata.consumption_rules.remove_at(gdata.consumption_rules.size() - 1)
    gdata.product_groups.erase("test_basket")

    # --- The professional default: one member per tick, rotating ---
    var rotate_members: Array = ["honey", "sugar", "carob_syrup"]
    gdata.product_groups["rotate_basket"] = rotate_members
    gdata.consumption_rules.append({
        "resource": "@rotate_basket",
        "profession": ["miner"],
        "amount": 10,
        "interval": 10,
        "production_bonus": 0.0
    })
    _clear_stock(city)
    for pid in rotate_members:
        _set_one(city, pid, 30)
    for i in range(3):
        wm.tick_consumption(0, 0, 1.0)
    for pid in rotate_members:
        check(city.get_storage_amount(pid) == 29,
            "each member must be drawn once in three ticks: %s has %d"
                % [pid, city.get_storage_amount(pid)], state)

    # A member without stock is skipped without moving the rotation too far.
    _set_one(city, "honey", 0)
    wm.tick_consumption(0, 0, 1.0)
    check(city.get_storage_amount("honey") == 0 and city.get_storage_amount("sugar") == 28,
        "an empty member must be skipped: honey %d, sugar %d"
            % [city.get_storage_amount("honey"), city.get_storage_amount("sugar")], state)

    # The rotation index survives a save/load round trip.
    var saved: Array = wm.serialize_consumption_timers()
    var wm2 = load("res://scripts/worker_manager.gd").new()
    stub.add_child(wm2)
    wm2.load_consumption_timers(saved)
    var rot: Dictionary = wm2.consumption_timers.get("0,0", {}).get("rotation", {})
    # The key of a group record is its fractional key: "@" + the display key.
    check(int(rot.get("@@rotate_basket", -1)) == 2,
        "the rotation index must survive save/load, got %d"
            % int(rot.get("@@rotate_basket", -1)), state)
    wm2.free()
    gdata.consumption_rules.remove_at(gdata.consumption_rules.size() - 1)
    gdata.product_groups.erase("rotate_basket")

    var tool_multipliers := {
        "copper_tools": 1.10,
        "cast_iron_tools": 1.20,
        "bronze_tools": 1.15,
        "brass_tools": 1.15,
        "iron_tools": 1.20,
        "steel_tools": 1.25,
        "damascus_tools": 1.30,
    }
    for pid in tool_multipliers:
        wm.consumption_timers.clear()
        _clear_stock(city)
        _set_one(city, pid, 30)
        multiplier = wm.tick_consumption(0, 0, 1.0)
        check(is_equal_approx(multiplier, float(tool_multipliers[pid])),
            "%s must give x%.2f, got x%.2f" % [pid, tool_multipliers[pid], multiplier], state)
        check(city.get_storage_amount(pid) == 29,
            "%s must be consumed at one unit per second" % pid, state)

    wm.consumption_timers.clear()
    _clear_stock(city)
    _set_one(city, "damascus_tools", 30)
    _set_one(city, "steel_tools", 30)
    multiplier = wm.tick_consumption(0, 0, 1.0)
    check(is_equal_approx(multiplier, 1.30) and city.get_storage_amount("steel_tools") == 30
            and city.get_storage_amount("damascus_tools") == 29,
        "Damascus tools must take precedence over ordinary steel tools", state)
    _set_one(city, "damascus_tools", 0)
    multiplier = wm.tick_consumption(0, 0, 1.0)
    check(is_equal_approx(multiplier, 1.25) and city.get_storage_amount("steel_tools") == 29,
        "the miner must fall back to ordinary steel tools when Damascus tools are unavailable", state)

    # --- The precision instruments follow the same metal ladder as the work tools ---
    # The scholar's instruments are drawn, but this test has no building to host him: the
    # ladder is read directly from the assembled rule, the same way the boats and the work
    # tools are checked above.
    var scholar_rules: Array = gdata.get_profession_consumption("scientist")
    var precision = _find(scholar_rules, "@precision_instruments")
    check(precision != null, "@precision_instruments rule must exist for the scholar", state)
    if precision != null:
        # The group is drawn one kind at a time and the tiers order it: the best metal first.
        var ordered: Array = gdata.get_entry_members_ordered_by_tier(precision)
        check(str(ordered[0]) == "damascus_precision_instruments"
                and str(ordered[ordered.size() - 1]) == "copper_precision_instruments",
            "the precision instruments must be ordered from damascus down to copper (got: %s)"
                % str(ordered), state)

        # The same metal is worth the same in both families of instruments, and the metal
        # ladder does not stretch the interval: every precision instrument wears out at the
        # rate of the rule, as every work tool does.
        for pid in ["copper", "bronze", "brass", "iron", "steel", "damascus"]:
            var member := pid + "_precision_instruments"
            var prec_bn: float = gdata.get_entry_member_bonus(precision, member)
            var prec_iv: float = gdata.get_entry_member_interval(precision, member)
            var tool_bn: float = float(tool_multipliers[pid + "_tools"]) - 1.0
            check(is_equal_approx(prec_bn, tool_bn),
                "the %s step must match the work tools: expected +%.2f, got +%.2f"
                    % [pid, tool_bn, prec_bn], state)
            check(is_equal_approx(prec_iv, float(precision.get("interval", 0.0))),
                "every precision instrument must wear out at the rule interval: %s has %.1f s"
                    % [pid, prec_iv], state)

        # A stock of one kind grants the step of that kind, and the steps never add up.
        _clear_stock(city)
        _set_one(city, "damascus_precision_instruments", 30)
        _set_one(city, "copper_precision_instruments", 30)
        var both := wm._aggregate_production_bonus([precision])
        check(is_equal_approx(both, 0.30),
            "two stocked kinds must grant the best step only, got +%.2f" % both, state)
        _set_one(city, "damascus_precision_instruments", 0)
        var copper_only := wm._aggregate_production_bonus([precision])
        check(is_equal_approx(copper_only, 0.10),
            "the copper instruments alone must grant +0.10, got +%.2f" % copper_only, state)

    # --- Tiered group ("members"): wooden_boat takes priority over reed_boat ---
    stub.tile_data = [[{"improvement": "fishing_boats"}]]
    wm.consumption_timers.clear()
    _clear_stock(city)
    city.idle_population = maxi(city.idle_population, 2)
    wm.assign_worker(0, 0)

    var fisher_rules: Array = gdata.get_profession_consumption("fisherman")
    var boats = _find(fisher_rules, "@boats")
    check(boats != null, "@boats rule must exist for fisherman", state)
    if boats != null:
        var boat_amt := int(boats.get("amount", 0))
        var reed_iv: float = gdata.get_entry_member_interval(boats, "reed_boat")
        var wood_iv: float = gdata.get_entry_member_interval(boats, "wooden_boat")
        var reed_bn: float = gdata.get_entry_member_bonus(boats, "reed_boat")
        var wood_bn: float = gdata.get_entry_member_bonus(boats, "wooden_boat")
        check(is_equal_approx(reed_bn, 0.1) and is_equal_approx(wood_bn, 0.2),
            "reed_boat must give +10%% and wooden_boat +20%% (got %.2f / %.2f)"
                % [reed_bn, wood_bn], state)
        check(wood_iv > reed_iv and reed_iv > 0.0,
            "wooden_boat must wear out more slowly than reed_boat (%.1f vs %.1f s)"
                % [wood_iv, reed_iv], state)

        # Reverse index reports each boat's own interval and bonus.
        var reed_cons: Array = gdata.get_consumption_consumers("reed_boat")
        var wood_cons: Array = gdata.get_consumption_consumers("wooden_boat")
        check(not reed_cons.is_empty() and is_equal_approx(float(reed_cons[0].get("production_bonus", 0.0)), reed_bn)
                and is_equal_approx(float(reed_cons[0].get("interval", 0.0)), reed_iv),
            "get_consumption_consumers(reed_boat) must carry reed_boat tier values", state)
        check(not wood_cons.is_empty() and is_equal_approx(float(wood_cons[0].get("production_bonus", 0.0)), wood_bn)
                and is_equal_approx(float(wood_cons[0].get("interval", 0.0)), wood_iv),
            "get_consumption_consumers(wooden_boat) must carry wooden_boat tier values", state)

        # Both boats stocked: wooden_boat is spent exclusively, bonus is +20% (no stacking).
        _set_one(city, "reed_boat", boat_amt * 3)
        _set_one(city, "wooden_boat", boat_amt * 3)
        var mult_both: float = 1.0
        for _t in range(int(round(wood_iv))):
            mult_both = wm.tick_consumption(0, 0, 1.0)
        check(is_equal_approx(mult_both, 1.0 + wood_bn),
            "with both boats stocked the multiplier must be %.2f, got %.2f"
                % [1.0 + wood_bn, mult_both], state)
        check(city.get_storage_amount("wooden_boat") == boat_amt * 2
                and city.get_storage_amount("reed_boat") == boat_amt * 3,
            "wooden_boat must be spent first while reed_boat stays untouched (wood=%d, reed=%d)"
                % [city.get_storage_amount("wooden_boat"), city.get_storage_amount("reed_boat")], state)

        var pop_wood: Dictionary = wm.get_population_consumption_map().get("@boats", {})
        check(is_equal_approx(float(pop_wood.get("per_consumer_interval", 0.0)), wood_iv),
            "Trade card for @boats must reflect wooden_boat interval when stocked", state)

        # Anti-exploit: 1 wooden_boat + (amount - 1) reed_boat gives reed_boat bonus, not wooden_boat.
        _clear_stock(city)
        _set_one(city, "wooden_boat", 1)
        _set_one(city, "reed_boat", boat_amt - 1)
        var mixed_bonus: float = wm._aggregate_production_bonus([boats])
        check(is_equal_approx(mixed_bonus, reed_bn),
            "a single wooden_boat mixed with reed_boats must grant only %.2f, got %.2f"
                % [reed_bn, mixed_bonus], state)

        # Only reed_boat stocked: reed_boat is spent at reed_iv with +10% bonus.
        wm.consumption_timers.clear()
        _clear_stock(city)
        _set_one(city, "reed_boat", boat_amt * 3)
        var mult_reed: float = 1.0
        for _t in range(int(round(reed_iv))):
            mult_reed = wm.tick_consumption(0, 0, 1.0)
        check(is_equal_approx(mult_reed, 1.0 + reed_bn),
            "with only reed_boat stocked the multiplier must be %.2f, got %.2f"
                % [1.0 + reed_bn, mult_reed], state)
        check(city.get_storage_amount("reed_boat") == boat_amt * 2,
            "reed_boat must lose one pack (%d) over %.1f s, left %d"
                % [boat_amt, reed_iv, city.get_storage_amount("reed_boat")], state)

        var pop_reed: Dictionary = wm.get_population_consumption_map().get("@boats", {})
        check(is_equal_approx(float(pop_reed.get("per_consumer_interval", 0.0)), reed_iv),
            "Trade card for @boats must switch to reed_boat interval when wooden_boat is absent", state)

    wm.free()
    stub.free()
    city.total_population = 1
    _clear_stock(city)
    city.market_consumption_enabled.clear()
    city.consumption_priority.clear()

    if state["failed"]:
        print("CONSUME ALL TEST FAILED")
        quit(1)
    else:
        print("CONSUME ALL TEST OK")
        quit(0)

func _find(entries: Array, display_key: String):
    for e in entries:
        if str(e.get("display_key", "")) == display_key:
            return e
    return null

func _set_one(city, pid: String, amount: int) -> void:
    city.city_storage[pid] = amount
    city.city_quality_detail[pid] = {"common": amount}

func _set_stock(city, members: Array, amount: int) -> void:
    _clear_stock(city)
    for pid in members:
        _set_one(city, str(pid), amount)

func _clear_stock(city) -> void:
    city.city_storage.clear()
    city.city_quality_detail.clear()

func check(condition: bool, message: String, state: Dictionary) -> void:
    if condition:
        print("OK: ", message)
    else:
        state["failed"] = true
        push_error("FAIL: " + message)
