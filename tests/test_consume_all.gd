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

    # --- The defaults: the citizens take the whole basket, the worker rotates ---
    var fruits = _find(all_rules, "@fruits")
    var instruments = _find(miner_rules, "@instruments")
    check(fruits != null and bool(fruits.get("consume_all", false)),
        "a city group rule must default to consume_all", state)
    check(instruments != null and not bool(instruments.get("consume_all", true)),
        "a professional group rule must default to rotation", state)

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

    wm.free()
    stub.free()
    gdata.consumption_rules.remove_at(gdata.consumption_rules.size() - 1)
    gdata.product_groups.erase("rotate_basket")
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
