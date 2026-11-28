extends SceneTree

const WATCHDOG = preload("res://tests/watchdog.gd")
var _failed := false

func _initialize() -> void:
    WATCHDOG.arm(self)
    _run()

func _run() -> void:
    var main_map = load("res://scenes/MainMap.tscn").instantiate()
    root.add_child(main_map)
    await process_frame
    await process_frame
    var gd = root.get_node("GameData")
    var fame = main_map.challenge_manager
    var cheese: Dictionary = gd.products["cheese"]
    _check(cheese.has("reputation") and not cheese.has("fame_group"), "single products retain their own tiers")
    for pid in ["pottery", "leather_clothes", "steel_weapons"]:
        _check(not gd.products[pid].has("fame_group") and not gd.products[pid].has("challenge"),
            pid + " does not own a group ladder")

    for expected in [["ceramics", "pottery_challenge", "ceramics_challenge"],
            ["leather_clothing", "leather_clothes_challenge", "leather_challenge"],
            ["weapons", "steel_weapons_challenge", "steel_challenge"]]:
        for existing in gd.fame_groups:
            if str(existing.get("id", "")) == expected[0]:
                _check(fame.challenge_id(existing, existing["reputation"]) == expected[1], "reputation id preserved")
                _check(fame.challenge_id(existing, existing["brand"]) == expected[1], "brand id preserved")
                _check(fame.challenge_id(existing, existing["challenge"]) == expected[2], "challenge id preserved")

    # The same merge and blacklist machinery used by mod loading applies to the new collection.
    var loader = load("res://scripts/data_loader.gd").new()
    var merged := {"fame_groups": [{"id": "mod_group", "product_group": "test_fame_goods"}]}
    loader._merge_mod_data(merged, {"fame_groups": [{"id": "mod_group", "challenge": {"id": "mod_challenge"}}]})
    _check(merged["fame_groups"].size() == 1 and merged["fame_groups"][0].has("product_group"), "mod merges fame groups by id")
    loader._apply_blacklist(merged, {"blacklist": {"fame_groups": ["mod_group"]}})
    _check(merged["fame_groups"].is_empty(), "blacklist removes a fame group")
    _check(loader.removed_challenge_ids.has("mod_challenge"), "blacklisted group records removed challenge id")
    loader.free()

    fame.deserialize({"tiers": ["pottery_challenge:reputation", "pottery_challenge:brand"]})
    _check(is_equal_approx(fame.get_fame_trade_price_share("bricks"), 0.10), "old reputation id restores the group price")
    _check(fame.is_tier_done("pottery_challenge", "brand"), "old brand id remains completed")
    fame.deserialize({"tiers": []})

    var group := {
        "id": "test_fame",
        "product_group": "test_fame_goods",
        "reputation": {"threshold": 2, "trigger": "sell", "reward": {"type": "trade_price", "value": 0.07}},
        "brand": {"threshold": 5, "trigger": "produce", "min_quality": "fine", "reward": {"type": "effect_stub", "id": "test"}},
        "challenge": {"threshold": 3, "trigger": "sell", "min_quality": "exceptional", "reward": {"type": "effect_stub", "id": "test"}}
    }
    gd.product_groups["test_fame_goods"] = ["cheese", "wool"]
    gd.fame_groups.append(group)
    fame._rebuild_fame_groups()
    fame.record_sale("cheese", {"exceptional": 1})
    fame.record_sale("wool", {"exceptional": 1})
    _check(fame.tier_counter(cheese, cheese["reputation"]) == 1, "product ladder counts only its own good")
    _check(fame.tier_counter(group, group["reputation"]) == 2, "group ladder sums both goods")
    _check(fame.is_tier_done("test_fame_challenge", "reputation"), "group reputation opens independently")
    _check(is_equal_approx(fame.get_fame_trade_price_share("cheese"), 0.07), "group reputation applies to first member")
    _check(is_equal_approx(fame.get_fame_trade_price_share("wool"), 0.07), "group reputation applies to second member")
    fame.record_production("wool", 5, "fine")
    _check(fame.is_tier_done("test_fame_challenge", "brand"), "group production trigger works")
    _check(not fame.is_challenge_completed("test_fame_challenge"), "production does not count as a sale")
    fame.record_sale("wool", {"exceptional": 1})
    _check(fame.is_challenge_completed("test_fame_challenge"), "default group challenge id is resolved")
    var record: Dictionary = fame.fame_record_of("test_fame_challenge")
    _check(str(record.get("product", "")) == "fame_group:test_fame", "group ladder has its own UI identity")
    var saved: Dictionary = fame.serialize()
    fame.deserialize(saved)
    _check(is_equal_approx(fame.get_fame_trade_price_share("wool"), 0.07), "group price survives save")
    _check(fame.is_challenge_completed("test_fame_challenge"), "group completion survives save")

    group["product_group"] = "missing_test_fame_goods"
    var problems: Array = load("res://scripts/data_validator.gd").new().validate(gd)
    var found := false
    for problem in problems:
        if str(problem.get("kind", "")) == "fame_group" and str(problem.get("source_id", "")) == "test_fame":
            found = true
    _check(found, "validator reports an unknown product group on the fame entity")
    gd.fame_groups.erase(group)
    gd.product_groups.erase("test_fame_goods")
    main_map.queue_free()
    WATCHDOG.report_skipped()
    print("FAME GROUPS TEST FAILED" if _failed else "FAME GROUPS TEST OK")
    quit(1 if _failed else 0)

func _check(condition: bool, message: String) -> void:
    if not condition:
        _failed = true
        push_error("ASSERT: " + message)
        print("ASSERT FAILED: ", message)
